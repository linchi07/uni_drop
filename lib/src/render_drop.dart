import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:super_native_extensions/raw_clipboard.dart' as clipboard;
import 'package:super_native_extensions/raw_drag_drop.dart' as raw;

import 'formats.dart';
import 'models.dart';
import 'resolver.dart';

typedef NativeDropResolver = Future<List<NativeData>> Function(
    List<clipboard.DataReaderItem> items,
    Set<FileFormat> formats,
    Duration metadataTimeout,
    Duration readTimeout);

/// Owns the native receiving context, with no drag-source/mouse-hook setup.
/// A context has one delegate: do not install super_drag_and_drop DropRegion
/// alongside uni_drop on that same context. Clipboard use is independent.
class DropFormatRegistry extends raw.DropContextDelegate {
  DropFormatRegistry(
      {Future<raw.DropContext> Function()? contextProvider,
      NativeDropResolver? resolver,
      this.viewId})
      : _contextProvider = contextProvider ?? raw.DropContext.instance,
        _resolver = resolver ?? _resolve;
  static final instance = DropFormatRegistry();
  final Future<raw.DropContext> Function() _contextProvider;
  final NativeDropResolver _resolver;

  /// The raw upstream context belongs to one Flutter view/engine.
  final int? viewId;
  final _regions = <RenderDropRegionBox>{};
  final _sessions = <int, RenderDropRegionBox>{};
  raw.DropContext? _context;
  Set<String>? _lastFormats;
  Future<void> _pending = Future.value();
  Future<void> get ready => _pending;

  static Future<List<NativeData>> _resolve(
          List<clipboard.DataReaderItem> items,
          Set<FileFormat> formats,
          Duration metadataTimeout,
          Duration readTimeout) =>
      NativeTypeResolver.resolveItems(items, formats,
          metadataTimeout: metadataTimeout, readTimeout: readTimeout);

  void register(RenderDropRegionBox region) {
    _regions.add(region);
    _scheduleSync();
  }

  void unregister(RenderDropRegionBox region) {
    _regions.remove(region);
    _sessions.removeWhere((_, target) => identical(target, region));
    _scheduleSync();
  }

  void formatsChanged() => _scheduleSync();

  void _scheduleSync() {
    // Serialize native registration so a slow older update cannot overwrite
    // newer formats, and never create DragContext just to receive a drop.
    _pending = _pending.then((_) async {
      if (_regions.isEmpty && _context == null) return;
      final context = _context ??= await _contextProvider();
      if (context.delegate != null && !identical(context.delegate, this)) {
        throw StateError(
            'Another drop delegate already owns this native context');
      }
      context.delegate = this;
      final formats =
          _regions.expand((r) => platformFormatsFor(r.formats)).toSet();
      if (!setEquals(formats, _lastFormats)) {
        await context.registerDropFormats(formats.toList(growable: false));
        _lastFormats = formats;
      }
    }).catchError((Object error, StackTrace stack) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'uni_drop',
          context: ErrorDescription('registering native drop formats')));
    });
  }

  Iterable<RenderDropRegionBox> _targets(Offset location) sync* {
    final id = viewId ?? PlatformDispatcher.instance.implicitView?.viewId;
    if (id == null) return;
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, location, id);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderDropRegionBox &&
          target.attached &&
          identical(target.registry, this) &&
          _regions.contains(target)) {
        yield target;
      }
    }
  }

  bool _accepts(RenderDropRegionBox target, raw.DropEvent event) {
    if (!event.allowedOperations.contains(raw.DropOperation.copy) ||
        target.formats.isEmpty) {
      return false;
    }
    return event.items.any((item) {
      if (item.formats.any(directoryFormats.contains)) return false;
      if (target.formats.any((f) => f is AllowAllFileFormats)) return true;
      final isFile = item.formats.any(fileUriFormats.contains);
      final imageTypes = item.formats
          .map((f) => fileTypeForFormats([f]))
          .whereType<FileType>()
          .where((type) => type.mimeType.startsWith('image/'));
      if (imageTypes.isNotEmpty) {
        return imageTypes.any((type) => target.formats.any(
            (f) => type.extensions.contains(normalizeExtension(f.extension))));
      }
      if (!isFile &&
          item.formats.any(plainTextFormats.contains) &&
          target.formats.any((f) => f is AllowPlainText)) {
        return true;
      }
      // iOS can advertise a text file with the same type as a snippet, with
      // its filename available only after acceptance. Negotiate optimistically;
      // resolveInfo applies the strict file/snippet filter before delivery.
      if (item.formats.any(plainTextFormats.contains) &&
          target.formats.any((f) =>
              f is AllowAllTextFileFormats ||
              (f is! AllowPlainText &&
                  Language.getLanguage(f.extension) != null))) {
        return true;
      }
      final type = fileTypeForFormats(
          item.formats.where((f) => !plainTextFormats.contains(f)));
      if (type != null) {
        if ((type.mimeType.startsWith('text/') ||
                Language.getLanguage(type.extensions.first) != null) &&
            target.formats.any((f) => f is AllowAllTextFileFormats)) {
          return true;
        }
        return target.formats.any((f) =>
            f is! AllowPlainText &&
            f is! AllowAllTextFileFormats &&
            type.extensions.contains(normalizeExtension(f.extension)));
      }
      // Desktop file names/extensions are not always available until drop.
      // Recheck against full metadata before delivering any item.
      return isFile && target.formats.any((f) => f is! AllowPlainText);
    });
  }

  NativeDropSession _session(raw.DropEvent event) => NativeDropSession(
      sessionId: event.sessionId,
      allowedOperations: event.allowedOperations,
      items: event.items
          .map(
              (i) => NativeDropItem(formats: i.formats, localData: i.localData))
          .toList());

  void _leave(int sessionId) {
    final target = _sessions.remove(sessionId);
    if (target != null && target.attached) {
      target.onDropLeave?.call(NativeDropLeaveEvent(sessionId: sessionId));
    }
  }

  @override
  Future<raw.DropOperation> onDropUpdate(raw.DropEvent event) async {
    try {
      for (final target in _targets(event.locationInView)) {
        if (!_accepts(target, event)) continue;
        final session = _session(event);
        final local = target.globalToLocal(event.locationInView);
        final operation = await (target.onDropUpdate?.call(NativeDropOverEvent(
                session: session,
                location: event.locationInView,
                localLocation: local)) ??
            raw.DropOperation.copy);
        if (operation != raw.DropOperation.copy ||
            !target.attached ||
            !_regions.contains(target)) {
          continue;
        }
        if (!identical(_sessions[event.sessionId], target)) {
          _leave(event.sessionId);
          _sessions[event.sessionId] = target;
          target.onDropEnter?.call(NativeDropEnterEvent(
              session: session,
              location: event.locationInView,
              localLocation: local));
        }
        return raw.DropOperation.copy;
      }
      _leave(event.sessionId);
      return raw.DropOperation.none;
    } catch (error, stack) {
      final target = _sessions[event.sessionId];
      _leave(event.sessionId);
      _report(target, event.sessionId, error, stack);
      return raw.DropOperation.none;
    }
  }

  @override
  Future<void> onPerformDrop(raw.DropEvent event) async {
    RenderDropRegionBox? target;
    try {
      // Freeze the final target, coordinates and callback before metadata I/O.
      // Do not dispatch to a different widget after an await/hit-test repeat.
      final previous = _sessions[event.sessionId];
      for (final candidate in _targets(event.locationInView)) {
        if (previous != null && !identical(previous, candidate)) continue;
        if (_accepts(candidate, event)) {
          target = candidate;
          break;
        }
      }
      if (target == null ||
          (event.acceptedOperation != null &&
              event.acceptedOperation != raw.DropOperation.copy)) {
        return;
      }
      final callback = target.onPerformDrop;
      final local = target.globalToLocal(event.locationInView);
      final formats = target.formats;
      final session = _session(event);
      final items = event.items
          .map((i) => i.readerItem)
          .whereType<clipboard.DataReaderItem>()
          .toList(growable: false);
      final values = await _resolver(
          items, formats, target.metadataTimeout, target.readTimeout);
      if (!target.attached || !_regions.contains(target)) return;
      final reader = NativeDataReader(
          values.where((value) => acceptsData(formats, value)));
      if (reader.items.isEmpty) return;
      await callback(NativeDropEvent(
          session: session,
          location: event.locationInView,
          localLocation: local,
          reader: reader));
    } catch (error, stack) {
      _report(target, event.sessionId, error, stack);
    } finally {
      _leave(event.sessionId);
    }
  }

  void _report(RenderDropRegionBox? target, int sessionId, Object error,
      StackTrace stack) {
    if (target != null && target.attached && target.onDropError != null) {
      target.onDropError!(NativeDropFailure(
          sessionId: sessionId, error: error, stackTrace: stack));
    } else {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'uni_drop',
          context:
              ErrorDescription('receiving native drop session $sessionId')));
    }
  }

  @override
  Future<void> onDropLeave(raw.BaseDropEvent event) async =>
      _leave(event.sessionId);
  @override
  Future<void> onDropEnded(raw.BaseDropEvent event) async =>
      _leave(event.sessionId);
  @override
  Future<raw.ItemPreview?> onGetItemPreview(
          raw.ItemPreviewRequest request) async =>
      null;
}

class RenderDropRegionBox extends RenderProxyBoxWithHitTestBehavior {
  RenderDropRegionBox(
      {required this.registry,
      required Set<FileFormat> formats,
      required this.onPerformDrop,
      required this.metadataTimeout,
      required this.readTimeout,
      required super.behavior,
      this.onDropEnter,
      this.onDropUpdate,
      this.onDropLeave,
      this.onDropError})
      : _formats = Set.unmodifiable(formats);
  final DropFormatRegistry registry;
  Set<FileFormat> _formats;
  Set<FileFormat> get formats => _formats;
  FutureOr<void> Function(NativeDropEvent) onPerformDrop;
  void Function(NativeDropEnterEvent)? onDropEnter;
  FutureOr<raw.DropOperation> Function(NativeDropOverEvent)? onDropUpdate;
  void Function(NativeDropLeaveEvent)? onDropLeave;
  void Function(NativeDropFailure)? onDropError;
  Duration metadataTimeout;
  Duration readTimeout;

  void updateFormats(Set<FileFormat> value) {
    if (setEquals(_formats, value)) return;
    _formats = Set.unmodifiable(value);
    if (attached) registry.formatsChanged();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    registry.register(this);
  }

  @override
  void detach() {
    registry.unregister(this);
    super.detach();
  }
}
