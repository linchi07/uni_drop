import 'dart:async';

import 'package:flutter/widgets.dart';

import 'models.dart';
import 'render_drop.dart';

/// Receives native drops, including over otherwise empty child/padding areas.
/// Read/copy incoming data before [onPerformDrop] returns. Keep expensive parsing
/// and network work outside the native callback after stabilizing the input.
class NativeDropRegion extends SingleChildRenderObjectWidget {
  const NativeDropRegion(
      {super.key,
      required super.child,
      required this.supportedFormats,
      required this.onPerformDrop,
      this.onDropUpdate,
      this.onDropEnter,
      this.onDropLeave,
      this.onDropError,
      this.hitTestBehavior = HitTestBehavior.opaque,
      this.registry,
      this.metadataTimeout = const Duration(seconds: 10),
      this.readTimeout = const Duration(seconds: 30)});
  final Set<FileFormat> supportedFormats;
  final FutureOr<void> Function(NativeDropEvent event) onPerformDrop;
  final FutureOr<DropOperation> Function(NativeDropOverEvent event)?
      onDropUpdate;
  final void Function(NativeDropEnterEvent event)? onDropEnter;
  final void Function(NativeDropLeaveEvent event)? onDropLeave;
  final void Function(NativeDropFailure failure)? onDropError;
  final HitTestBehavior hitTestBehavior;

  /// Optional receiving context owner for embedding or native integration tests.
  final DropFormatRegistry? registry;
  final Duration metadataTimeout;
  final Duration readTimeout;
  @override
  RenderDropRegionBox createRenderObject(BuildContext context) =>
      RenderDropRegionBox(
          registry: registry ?? DropFormatRegistry.instance,
          formats: supportedFormats,
          behavior: hitTestBehavior,
          onPerformDrop: onPerformDrop,
          onDropEnter: onDropEnter,
          onDropUpdate: onDropUpdate,
          onDropLeave: onDropLeave,
          onDropError: onDropError,
          metadataTimeout: metadataTimeout,
          readTimeout: readTimeout);
  @override
  void updateRenderObject(
      BuildContext context, RenderDropRegionBox renderObject) {
    assert(
        identical(
            renderObject.registry, registry ?? DropFormatRegistry.instance),
        'Use a new widget key when changing the receiving registry');
    renderObject.updateFormats(supportedFormats);
    renderObject.behavior = hitTestBehavior;
    renderObject.onPerformDrop = onPerformDrop;
    renderObject.onDropEnter = onDropEnter;
    renderObject.onDropUpdate = onDropUpdate;
    renderObject.onDropLeave = onDropLeave;
    renderObject.onDropError = onDropError;
    renderObject.metadataTimeout = metadataTimeout;
    renderObject.readTimeout = readTimeout;
  }
}
