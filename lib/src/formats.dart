import 'models.dart';

/// A file's encodings, distinct from alternative text/URL representations.
class FileType {
  const FileType(this.extensions, this.mimeType, this.platformFormats);
  final List<String> extensions;
  final String mimeType;
  final List<String> platformFormats;
}

const fileTypes = [
  FileType(['png'], 'image/png', ['public.png', 'image/png']),
  FileType(['jpg', 'jpeg'], 'image/jpeg', ['public.jpeg', 'image/jpeg']),
  FileType(['gif'], 'image/gif', ['com.compuserve.gif', 'image/gif']),
  FileType(['webp'], 'image/webp', ['org.webmproject.webp', 'image/webp']),
  FileType(['heic', 'heif'], 'image/heic',
      ['public.heic', 'public.heif', 'image/heic', 'image/heif']),
  FileType(['tif', 'tiff'], 'image/tiff', ['public.tiff', 'image/tiff']),
  FileType(['bmp'], 'image/bmp', ['com.microsoft.bmp', 'image/bmp']),
  FileType(['svg'], 'image/svg+xml', ['public.svg-image', 'image/svg+xml']),
  FileType(['pdf'], 'application/pdf', ['com.adobe.pdf', 'application/pdf']),
  FileType(['txt'], 'text/plain',
      ['public.utf8-plain-text', 'public.plain-text', 'text/plain']),
  FileType(['md', 'markdown'], 'text/markdown',
      ['net.daringfireball.markdown', 'public.markdown', 'text/markdown']),
  FileType(['html', 'htm'], 'text/html', ['public.html', 'text/html']),
  FileType(['json'], 'application/json', ['public.json', 'application/json']),
  FileType(['mp4', 'm4v'], 'video/mp4', ['public.mpeg-4', 'video/mp4']),
  FileType(['mov'], 'video/quicktime',
      ['com.apple.quicktime-movie', 'video/quicktime']),
  FileType(['mp3'], 'audio/mpeg', ['public.mp3', 'audio/mpeg']),
  FileType(['wav'], 'audio/wav', ['com.microsoft.waveform-audio', 'audio/wav']),
];

const plainTextFormats = [
  'public.utf8-plain-text',
  'public.plain-text',
  'text/plain',
  'NativeShell_CF_13'
];
const fileUriFormats = [
  'public.file-url',
  'text/uri-list',
  'NativeShell_CF_15'
];
const directoryFormats = ['public.folder', 'inode/directory'];
const metadataFormats = {
  ...fileUriFormats,
  'public.url',
  'public.url-name',
  'text/html',
  'public.html',
  'HTML Format',
  'application/x-moz-file-promise-url',
};

String normalizeExtension(String extension) =>
    extension.trim().replaceFirst(RegExp(r'^\.+'), '').toLowerCase();

FileType? fileTypeForExtension(String extension) {
  final value = normalizeExtension(extension);
  for (final type in fileTypes) {
    if (type.extensions.contains(value)) return type;
  }
  return null;
}

FileType? fileTypeForFormats(Iterable<String> formats) {
  // Respect the source's preferred representation, rather than table order.
  for (final format in formats) {
    for (final type in fileTypes) {
      if (type.platformFormats.contains(format)) return type;
    }
  }
  return null;
}

List<String> platformFormatsForFile(FileFormat format) => {
      ...?fileTypeForExtension(format.extension)?.platformFormats,
      if (format.mimeType != null) format.mimeType!,
    }.toList(growable: false);

/// Register native identifiers as well as MIME types. Files may be advertised
/// by URL, virtual-file type, or bytes, depending on the platform/source app.
List<String> platformFormatsFor(Set<FileFormat> formats) {
  if (formats.isEmpty) return [];
  final result = <String>{...fileUriFormats};
  for (final format in formats) {
    if (format is AllowAllFileFormats) {
      result.addAll(plainTextFormats);
      result.addAll([
        'public.item',
        'public.content',
        'public.data',
        'application/octet-stream'
      ]);
      for (final type in fileTypes) {
        result.addAll(type.platformFormats);
      }
    } else if (format is AllowPlainText) {
      result.addAll(plainTextFormats);
    } else if (format is AllowAllTextFileFormats) {
      result.addAll(plainTextFormats);
      result.add('public.text');
      result.add('public.source-code');
      for (final type in fileTypes.where((t) =>
          t.mimeType.startsWith('text/') || t.mimeType == 'application/json')) {
        result.addAll(type.platformFormats);
      }
      for (final language in Language.knownLanguages) {
        if (language.mime != null) result.add(language.mime!);
      }
    } else {
      result.addAll(platformFormatsForFile(format));
    }
  }
  return result.toList(growable: false);
}

bool acceptsData(Set<FileFormat>? allowed, NativeData value) {
  if (allowed == null || allowed.any((f) => f is AllowAllFileFormats)) {
    return true;
  }
  if (value is NativeText) return allowed.any((f) => f is AllowPlainText);
  if (value is NativeTextFile &&
      allowed.any((f) => f is AllowAllTextFileFormats)) {
    return true;
  }
  final extension = normalizeExtension(value.format.extension);
  final type = fileTypeForExtension(extension);
  return allowed.any((f) =>
      f is! AllowPlainText &&
      f is! AllowAllTextFileFormats &&
      (normalizeExtension(f.extension) == extension ||
          (type != null &&
              type.extensions.contains(normalizeExtension(f.extension)))));
}
