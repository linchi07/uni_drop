import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:super_native_extensions/raw_clipboard.dart' as raw;
import 'package:super_native_extensions/raw_drag_drop.dart' show DropOperation;

import 'file_semantic_map.g.dart';
import 'formats.dart';

export 'package:super_native_extensions/raw_drag_drop.dart' show DropOperation;

class NativeDropSession {
  NativeDropSession(
      {required this.sessionId,
      required List<NativeDropItem> items,
      required List<DropOperation> allowedOperations})
      : items = List.unmodifiable(items),
        allowedOperations = List.unmodifiable(allowedOperations);
  final int sessionId;
  final List<NativeDropItem> items;
  final List<DropOperation> allowedOperations;
}

class NativeDropItem {
  NativeDropItem({required List<String> formats, this.localData})
      : formats = List.unmodifiable(formats);
  final List<String> formats;
  final Object? localData;
  bool canProvide(String format) => formats.contains(format);
}

class NativeDropEnterEvent {
  const NativeDropEnterEvent(
      {required this.session,
      required this.location,
      required this.localLocation});
  final NativeDropSession session;

  /// Logical pixels in the Flutter view; not physical/screen coordinates.
  final Offset location;
  final Offset localLocation;
}

class NativeDropOverEvent extends NativeDropEnterEvent {
  const NativeDropOverEvent(
      {required super.session,
      required super.location,
      required super.localLocation});
}

class NativeDropLeaveEvent {
  const NativeDropLeaveEvent({required this.sessionId});
  final int sessionId;
}

class NativeDropFailure {
  const NativeDropFailure(
      {required this.sessionId, required this.error, required this.stackTrace});
  final int sessionId;
  final Object error;
  final StackTrace stackTrace;
}

/// Position and receiving target are captured before metadata is awaited.
class NativeDropEvent extends NativeDropEnterEvent {
  const NativeDropEvent(
      {required super.session,
      required super.location,
      required super.localLocation,
      required this.reader});
  final NativeDataReader reader;
}

class AllowPlainText extends FileFormat {
  const AllowPlainText() : super(mimeType: 'text/plain', extension: 'allPlain');
}

class AllowAllTextFileFormats extends FileFormat {
  const AllowAllTextFileFormats() : super(extension: 'allText');
}

/// Accepts any supported file or text snippet. Directories are excluded.
class AllowAllFileFormats extends FileFormat {
  const AllowAllFileFormats() : super(extension: '*');
}

class FileFormat {
  const FileFormat({this.mimeType, required this.extension});
  final String? mimeType;

  /// Dots and case are normalized when matching.
  final String extension;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileFormat &&
          runtimeType == other.runtimeType &&
          normalizeExtension(extension) == normalizeExtension(other.extension);
  @override
  int get hashCode => Object.hash(runtimeType, normalizeExtension(extension));
  @override
  String toString() => 'FileFormat(ext: $extension, mime: $mimeType)';
}

class NativeDataReader {
  NativeDataReader(Iterable<NativeData> items)
      : items = List.unmodifiable(items);
  final List<NativeData> items;
  List<NativeData> getData({Set<FileFormat>? only}) => only == null
      ? items
      : items.where((item) => acceptsData(only, item)).toList(growable: false);
}

/// Normalized receiving item. Start and await reads inside the drop callback:
/// native readers cannot be kept after the session ends. Prefer [copyTo] for
/// large files; it streams data without accumulating the full file in memory.
abstract class NativeData {
  NativeData(
      {this.name,
      required this.format,
      this.path,
      required raw.DataReaderItem item,
      required raw.DataReaderItemInfo info,
      this.readTimeout = const Duration(seconds: 30)})
      : _item = item,
        _info = info;
  final String? name;
  final FileFormat format;
  final String? path;
  final Duration readTimeout;
  final raw.DataReaderItem _item;
  final raw.DataReaderItemInfo _info;

  Future<Object?> _readValue(String format) {
    final (future, progress) = _item.getDataForFormat(format);
    return future.timeout(readTimeout, onTimeout: () {
      progress.cancel();
      throw TimeoutException('Reading $format timed out', readTimeout);
    });
  }

  Future<String?> _resolveFilePath() async {
    if (path != null) return path;
    for (final format in fileUriFormats) {
      if (!_info.formats.contains(format)) continue;
      final data = await _readValue(format);
      final text = decodeNativeText(data, format);
      if (text == null) continue;
      // URI lists may contain comments, CRLF/LF, or a text/uri-list web link.
      for (final line in text.split(RegExp(r'[\r\n\x00]+'))) {
        final candidate = line.trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        final uri = Uri.tryParse(candidate);
        if (uri?.scheme == 'file') {
          return uri!.toFilePath(
              windows: format == 'NativeShell_CF_15' ||
                  (!kIsWeb && Platform.isWindows));
        }
        if (format == 'NativeShell_CF_15' && p.windows.isAbsolute(candidate)) {
          return p.windows.normalize(candidate);
        }
        if (format == 'public.file-url' && p.posix.isAbsolute(candidate)) {
          return candidate;
        }
      }
    }
    return null;
  }

  List<String> get _payloadFormats => [
        ...platformFormatsForFile(format),
        if (this is NativeText || this is NativeTextFile) ...plainTextFormats,
        if (this is NativeTextFile) 'public.text',
        if (this is NativeTextFile) 'public.source-code',
        'application/octet-stream',
        'public.data',
      ];

  /// Streams real files before trying promised files. This avoids the old
  /// VS Code macOS file-promise failure when a usable file URL also exists.
  Stream<Uint8List> openRead() async* {
    final sourcePath = kIsWeb ? null : await _resolveFilePath();
    if (sourcePath != null) {
      final type = await FileSystemEntity.type(sourcePath);
      if (type == FileSystemEntityType.directory) {
        throw UnsupportedError('Directory drops are not supported');
      }
      if (type == FileSystemEntityType.file) {
        yield* File(sourcePath)
            .openRead()
            .map((chunk) =>
                chunk is Uint8List ? chunk : Uint8List.fromList(chunk))
            .timeout(readTimeout);
        return;
      }
      // A virtual representation may still be available for an unavailable URL.
      if (_info.virtualReceivers.isEmpty) {
        throw FileSystemException('Dropped file is unavailable', sourcePath);
      }
    }

    raw.VirtualFileReceiver? receiver;
    for (final preferred in _payloadFormats) {
      for (final candidate in _info.virtualReceivers) {
        if (candidate.format == preferred) {
          receiver = candidate;
          break;
        }
      }
      if (receiver != null) break;
    }
    if (receiver == null &&
        this is NativeFile &&
        _info.virtualReceivers.isNotEmpty) {
      receiver = _info.virtualReceivers.first;
    }
    if (receiver != null) {
      final (pending, progress) = receiver.receiveVirtualFile();
      var abandoned = false;
      // A completion arriving after timeout still owns a file and must close it.
      final guarded = pending.then((file) {
        if (abandoned) file.close();
        return file;
      });
      final file = await guarded.timeout(readTimeout, onTimeout: () {
        abandoned = true;
        progress.cancel();
        throw TimeoutException('Receiving virtual file timed out', readTimeout);
      });
      try {
        while (true) {
          final bytes =
              await file.readNext().timeout(readTimeout, onTimeout: () {
            progress.cancel();
            throw TimeoutException(
                'Reading virtual file timed out', readTimeout);
          });
          if (bytes.isEmpty) break;
          yield bytes;
        }
      } finally {
        file.close();
      }
      return;
    }

    for (final candidate in _payloadFormats.toSet()) {
      if (!_info.formats.contains(candidate) &&
          !_info.synthesizedFormats.contains(candidate)) {
        continue;
      }
      final value = await _readValue(candidate);
      if (value is Uint8List) {
        yield value;
        return;
      }
      if (value is List<int>) {
        yield Uint8List.fromList(value);
        return;
      }
      if (value is String && (this is NativeText || this is NativeTextFile)) {
        yield Uint8List.fromList(utf8.encode(value));
        return;
      }
    }
    throw StateError('No readable payload for ${name ?? format.extension}');
  }

  Future<Uint8List> readBytes() async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in openRead()) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// Native platforms only. Builds an owned staging file and atomically moves
  /// it into place. A failure never truncates an existing destination file.
  Future<File> copyTo(String pathToDir,
      {String? rename,
      bool replaceIfExist = false,
      bool createDirIfNotExist = true,
      String? extension}) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'copyTo is unavailable on web; use openRead or readBytes');
    }
    final directory = Directory(pathToDir);
    if (createDirIfNotExist) await directory.create(recursive: true);
    final fileName = safeFileName(rename ?? name ?? 'unnamed_file',
        extension: extension, defaultExtension: format.extension);
    final target = File(p.join(directory.path, fileName));
    var reserved = false;
    Directory? staging;
    try {
      if (!replaceIfExist) {
        await target.create(exclusive: true);
        reserved = true;
      }
      staging = await directory.createTemp('.uni-drop-');
      final temporary = File(p.join(staging.path, 'data'));
      final sink = temporary.openWrite();
      try {
        await sink.addStream(openRead());
        await sink.close();
      } catch (error, stack) {
        // addStream may already have closed the sink on a source error. Its
        // secondary close error must not replace the useful original failure.
        try {
          await sink.close();
        } catch (_) {}
        Error.throwWithStackTrace(error, stack);
      }
      await temporary.rename(target.path);
      reserved = false;
      return target;
    } catch (_) {
      if (reserved && await target.exists()) await target.delete();
      rethrow;
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
}

class NativeImage extends NativeData {
  NativeImage(
      {required super.format,
      required super.item,
      required super.info,
      super.name,
      super.path,
      super.readTimeout});
}

class NativeText extends NativeData {
  NativeText(
      {required super.format,
      required super.item,
      required super.info,
      super.name,
      super.path,
      super.readTimeout});
  Future<String> getText() async {
    for (final format in plainTextFormats) {
      if (!_info.formats.contains(format)) continue;
      final text = decodeNativeText(await _readValue(format), format);
      if (text != null) return text;
    }
    return utf8.decode(await readBytes());
  }

  NativeTextFile toNativeTextFile() => NativeTextFile(
      format: format,
      item: _item,
      info: _info,
      name: name,
      path: path,
      readTimeout: readTimeout);
}

class NativeTextFile extends NativeData {
  NativeTextFile(
      {required super.format,
      required super.item,
      required super.info,
      super.name,
      super.path,
      super.readTimeout,
      this.color,
      this.language});
  final Color? color;
  final Language? language;
}

class NativeFile extends NativeData {
  NativeFile(
      {required super.format,
      required super.item,
      required super.info,
      super.name,
      super.path,
      super.readTimeout});
}

class NativeVideo extends NativeFile {
  NativeVideo(
      {required super.format,
      required super.item,
      required super.info,
      super.name,
      super.path,
      super.readTimeout});
}

class NativeAudio extends NativeFile {
  NativeAudio(
      {required super.format,
      required super.item,
      required super.info,
      super.name,
      super.path,
      super.readTimeout});
}

/// Windows native CF_UNICODETEXT/CF_HDROP are UTF-16LE, including terminators;
/// other supported text representations are UTF-8. A String is already decoded.
String? decodeNativeText(Object? data, String platformFormat) {
  if (data is String) return data.replaceFirst(RegExp(r'\x00+$'), '');
  if (data is! List<int>) return null;
  if (platformFormat == 'NativeShell_CF_13' ||
      platformFormat == 'NativeShell_CF_15') {
    if (data.length.isOdd) {
      throw const FormatException('Odd-length UTF-16LE value');
    }
    final units = <int>[];
    for (var index = 0; index < data.length; index += 2) {
      units.add(data[index] | data[index + 1] << 8);
    }
    while (units.isNotEmpty && units.last == 0) {
      units.removeLast();
    }
    if (units.isNotEmpty && units.first == 0xfeff) units.removeAt(0);
    return String.fromCharCodes(units);
  }
  return utf8.decode(data).replaceFirst(RegExp(r'\x00+$'), '');
}

String safeFileName(String name,
    {String? extension, String? defaultExtension}) {
  // Handle paths supplied in either platform's syntax, regardless of host OS.
  var result = p.posix
      .basename(p.windows.basename(name))
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceFirst(RegExp(r'[ .]+$'), '');
  if (result.isEmpty || result == '.' || result == '..') {
    result = 'unnamed_file';
  }
  final ext = normalizeExtension(extension ?? defaultExtension ?? '');
  if (ext.contains(RegExp(r'[^a-z0-9_+-]'))) {
    throw ArgumentError.value(ext, 'extension', 'Invalid extension');
  }
  if (extension != null) {
    result = '${p.withoutExtension(result)}${ext.isEmpty ? '' : '.$ext'}';
  } else if (p.extension(result).isEmpty && ext.isNotEmpty) {
    result = '$result.$ext';
  }
  if (RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
          caseSensitive: false)
      .hasMatch(result)) {
    result = '_$result';
  }
  return result;
}

enum Type { code, data, document }

class Language {
  const Language(
      {required this.name, int? colorCode, required this.type, this.mime})
      : _colorCode = colorCode;
  final Type type;
  final String name;
  final int? _colorCode;
  final String? mime;
  Color get color => Color(_colorCode ?? 0x00000000);
  static List<Language> get knownLanguages => LANGUAGES;
  static Language? getLanguage(String extension) {
    final ext = normalizeExtension(extension);
    // Deterministic overrides for known ambiguous entries in the legacy map.
    const common = {
      'json': Language(name: 'JSON', type: Type.data, mime: 'application/json'),
      'txt': Language(name: 'Text', type: Type.document, mime: 'text/plain'),
      'md': Language(
          name: 'Markdown', type: Type.document, mime: 'text/markdown'),
    };
    final index = EXT_INDEX[ext];
    return common[ext] ?? (index == null ? null : LANGUAGES[index]);
  }
}
