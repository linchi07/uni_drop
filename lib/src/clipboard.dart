import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart' as clipboard;
import 'package:super_native_extensions/raw_clipboard.dart' as raw;

import 'models.dart';
import 'resolver.dart';

/// Clipboard receiving shares the drop resolver. Dispose the returned reader
/// after all reads/copies complete (prefer try/finally or [withReader]).
class NativeClipboard {
  static Future<NativeClipboardReader?> read(
      {Set<FileFormat>? supportedFormats,
      Duration metadataTimeout = const Duration(seconds: 10),
      Duration readTimeout = const Duration(seconds: 30)}) async {
    if (!raw.ClipboardReader.instance.available) return null;
    final source = await raw.ClipboardReader.instance.newClipboardReader();
    try {
      final items = await source.getItems().timeout(metadataTimeout);
      final resolved = await NativeTypeResolver.resolveItems(
          items, supportedFormats,
          metadataTimeout: metadataTimeout, readTimeout: readTimeout);
      return NativeClipboardReader(resolved, source.dispose);
    } catch (_) {
      await source.dispose();
      rethrow;
    }
  }

  static Future<T?> withReader<T>(
      Future<T> Function(NativeDataReader reader) action,
      {Set<FileFormat>? supportedFormats}) async {
    final reader = await read(supportedFormats: supportedFormats);
    if (reader == null) return null;
    try {
      return await action(reader);
    } finally {
      await reader.dispose();
    }
  }

  /// The shared format codec handles Windows text encoding and provider
  /// ownership. This writes clipboard data; uni_drop creates no drag sources.
  static Future<void> write(List<NativeDataWriterItem> items) async {
    final destination = clipboard.SystemClipboard.instance;
    if (destination == null) throw UnsupportedError('Clipboard is unavailable');
    await destination.write(items.map((item) {
      final value = clipboard.DataWriterItem(suggestedName: item.suggestedName);
      if (item._texts.isNotEmpty) {
        value.add(clipboard.Formats.plainText(item._texts.join('\n')));
      }
      for (final file in item._files) {
        value.add(clipboard.EncodedData([
          raw.DataRepresentation.simple(format: file.format, data: file.data)
        ]));
      }
      return value;
    }));
  }
}

class NativeClipboardReader extends NativeDataReader {
  NativeClipboardReader(super.items, this._dispose);
  final Future<void> Function() _dispose;
  Future<void>? _disposal;
  Future<void> dispose() => _disposal ??= _dispose();
}

class NativeDataWriterItem {
  NativeDataWriterItem({this.suggestedName});
  String? suggestedName;
  final List<String> _texts = [];
  final List<({String format, Uint8List data})> _files = [];
  void addText(String text) => _texts.add(text);

  /// [format] is a native format identifier, e.g. public.png on Apple platforms.
  void addData(Uint8List data, {required String format}) =>
      _files.add((format: format, data: data));
}
