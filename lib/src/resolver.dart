import 'package:path/path.dart' as p;
import 'package:super_native_extensions/raw_clipboard.dart' as raw;

import 'formats.dart';
import 'models.dart';

/// Normalizes each source item once; file representations take precedence over
/// their alternate text/URL representations. No app-specific platform singleton.
class NativeTypeResolver {
  static Future<List<NativeData>> resolveItems(
      Iterable<raw.DataReaderItem> items, Set<FileFormat>? allowedFormats,
      {Duration metadataTimeout = const Duration(seconds: 10),
      Duration readTimeout = const Duration(seconds: 30)}) async {
    final infos =
        await raw.DataReaderItem.getItemInfo(items, timeout: metadataTimeout)
            .timeout(metadataTimeout);
    return resolveInfo(infos, allowedFormats, readTimeout: readTimeout);
  }

  /// Also usable with reader metadata supplied by a host/native integration.
  static List<NativeData> resolveInfo(
      Iterable<raw.DataReaderItemInfo> infos, Set<FileFormat>? allowedFormats,
      {Duration readTimeout = const Duration(seconds: 30)}) {
    final values = <NativeData>[];
    for (final info in infos) {
      final formats = [
        ...info.formats,
        ...info.synthesizedFormats,
        ...info.virtualReceivers.map((r) => r.format)
      ];
      if (formats.any(directoryFormats.contains)) continue;
      final item =
          info.item; // Metadata belongs to its own handle, not list index.
      var name = info.suggestedName;
      var ext = normalizeExtension(p.extension(name ?? ''));
      final imageTypes = <FileType>[];
      for (final platformFormat in formats) {
        final candidate = fileTypeForFormats([platformFormat]);
        if (candidate?.mimeType.startsWith('image/') == true &&
            !imageTypes.contains(candidate)) {
          imageTypes.add(candidate!);
        }
      }
      var advertisedType =
          imageTypes.isEmpty ? fileTypeForFormats(formats) : imageTypes.first;
      // For unnamed image data choose an allowed native/synthesized rendition
      // rather than rejecting it because the source preferred another format.
      // Real files retain their original representation and filename.
      if (ext.isEmpty &&
          info.synthesizedFromURIFormat == null &&
          !info.formats.any(fileUriFormats.contains) &&
          allowedFormats != null &&
          !allowedFormats.any((f) => f is AllowAllFileFormats)) {
        for (final candidate in imageTypes) {
          if (allowedFormats.any((f) =>
              candidate.extensions.contains(normalizeExtension(f.extension)))) {
            advertisedType = candidate;
            break;
          }
        }
      }
      final isFile = info.synthesizedFromURIFormat != null ||
          info.formats.any(fileUriFormats.contains) ||
          info.virtualReceivers.isNotEmpty ||
          name != null;
      final hasText = info.formats.any(plainTextFormats.contains);
      if (!isFile &&
          hasText &&
          advertisedType?.mimeType.startsWith('image/') != true) {
        final value = NativeText(
            format: const FileFormat(mimeType: 'text/plain', extension: 'txt'),
            item: item,
            info: info,
            name: name,
            readTimeout: readTimeout);
        if (acceptsData(allowedFormats, value)) values.add(value);
        continue;
      }
      if (ext.isEmpty && advertisedType != null) {
        ext = advertisedType.extensions.first;
        if (name != null) name = '$name.$ext';
      }
      final type = fileTypeForExtension(ext) ?? advertisedType;
      final language = Language.getLanguage(ext);
      final format = FileFormat(
          mimeType:
              type?.mimeType ?? language?.mime ?? 'application/octet-stream',
          extension: ext);
      final NativeData value;
      if (type?.mimeType.startsWith('image/') == true) {
        value = NativeImage(
            format: format,
            item: item,
            info: info,
            name: name,
            readTimeout: readTimeout);
      } else if (language != null ||
          type?.mimeType.startsWith('text/') == true) {
        value = NativeTextFile(
            format: format,
            item: item,
            info: info,
            name: name,
            readTimeout: readTimeout,
            language: language,
            color: language?.color);
      } else if (type?.mimeType.startsWith('video/') == true) {
        value = NativeVideo(
            format: format,
            item: item,
            info: info,
            name: name,
            readTimeout: readTimeout);
      } else if (type?.mimeType.startsWith('audio/') == true) {
        value = NativeAudio(
            format: format,
            item: item,
            info: info,
            name: name,
            readTimeout: readTimeout);
      } else if (isFile ||
          type != null ||
          formats.contains('application/octet-stream') ||
          formats.contains('public.data')) {
        value = NativeFile(
            format: format,
            item: item,
            info: info,
            name: name,
            readTimeout: readTimeout);
      } else {
        continue;
      }
      if (acceptsData(allowedFormats, value)) values.add(value);
    }
    return values;
  }
}
