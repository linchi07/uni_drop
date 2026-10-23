import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uni_drop/src/formats.dart';
import 'package:uni_drop/uni_drop.dart';

import 'fakes.dart';

List<NativeData> resolve(FakeInfo info, [Set<FileFormat>? allowed]) =>
    NativeTypeResolver.resolveInfo([info], allowed);

void main() {
  test('plain-text filtering rejects text in an images-only region', () {
    final info = FakeInfo(formats: ['text/plain']);
    expect(resolve(info, {const FileFormat(extension: 'png')}), isEmpty);
    expect(resolve(info, {const AllowPlainText()}).single, isA<NativeText>());
    expect(resolve(info, {const AllowAllTextFileFormats()}), isEmpty);
    expect(resolve(info, {}), isEmpty);
  });
  test('PNG and JPG obey filters; case and JPEG aliases are normalized', () {
    for (final name in ['photo.png', 'photo.jpg', 'photo.jpeg']) {
      final info = FakeInfo(suggestedName: name, formats: ['public.file-url']);
      expect(resolve(info, {const FileFormat(extension: 'pdf')}), isEmpty);
    }
    expect(
        resolve(
            FakeInfo(suggestedName: 'PHOTO.JPEG', formats: ['public.file-url']),
            {const FileFormat(extension: '.JPG')}).single,
        isA<NativeImage>());
    expect(const FileFormat(extension: '.PNG'),
        const FileFormat(extension: 'png'));
    expect(const FileFormat(extension: '.PNG').hashCode,
        const FileFormat(extension: 'png').hashCode);
  });
  test('type inference preserves unnamed JPEG and iOS missing extensions', () {
    final jpeg = resolve(FakeInfo(formats: ['public.jpeg'])).single;
    expect(jpeg, isA<NativeImage>());
    expect(jpeg.format.extension, 'jpg');
    expect(jpeg.format.mimeType, 'image/jpeg');
    expect(
        resolve(FakeInfo(suggestedName: 'scan', formats: ['com.adobe.pdf']))
            .single
            .name,
        'scan.pdf');
  });
  test('file beats alternate plain text, without duplicating one source item',
      () {
    final info = FakeInfo(
        suggestedName: 'paper.pdf', formats: ['public.file-url', 'text/plain']);
    final values = resolve(info);
    expect(values, hasLength(1));
    expect(values.single, isA<NativeFile>());
    expect(resolve(info, {const AllowPlainText()}), isEmpty);
    final image = resolve(FakeInfo(formats: ['image/png', 'text/plain']));
    expect(image.single, isA<NativeImage>());
  });
  test('text files and common JSON language metadata are deterministic', () {
    final txt = resolve(
        FakeInfo(suggestedName: 'notes.TXT', formats: ['text/uri-list']),
        {const AllowAllTextFileFormats()}).single;
    expect(txt, isA<NativeTextFile>());
    expect(txt.format.extension, 'txt');
    expect(Language.getLanguage('.JSON')?.name, 'JSON');
    expect(resolve(FakeInfo(formats: ['inode/directory'])), isEmpty);
  });
  test('selects an allowed image rendition instead of its alternate text',
      () async {
    final info = FakeInfo(
      formats: ['text/plain', 'public.jpeg'],
      synthesizedFormats: ['public.png'],
      item: FakeItem({
        'public.png': Uint8List.fromList([1, 2, 3])
      }),
    );
    final value = resolve(info, {const FileFormat(extension: 'png')}).single;
    expect(value, isA<NativeImage>());
    expect(value.format.extension, 'png');
    expect(await value.readBytes(), [1, 2, 3]);
    expect(resolve(info, {const AllowPlainText()}), isEmpty);
  });
  test('each metadata entry retains its own reader handle and source order',
      () async {
    final first = FakeInfo(
        formats: ['text/plain'], item: FakeItem({'text/plain': 'one'}));
    final second = FakeInfo(
        formats: ['text/plain'], item: FakeItem({'text/plain': 'two'}));
    final values = NativeTypeResolver.resolveInfo([second, first], null);
    expect(await (values[0] as NativeText).getText(), 'two');
    expect(await (values[1] as NativeText).getText(), 'one');
  });
  test('Apple source-code UTI is readable without an exact MIME payload',
      () async {
    final info = FakeInfo(
        suggestedName: 'main.dart',
        formats: ['public.source-code'],
        item: FakeItem({
          'public.source-code':
              Uint8List.fromList(utf8.encode('void main() {}'))
        }));
    final value = resolve(info, {const AllowAllTextFileFormats()}).single;
    expect(value, isA<NativeTextFile>());
    expect(utf8.decode(await value.readBytes()), 'void main() {}');
  });
  test('Windows UTF-16LE handles non-BMP text, BOM and terminators', () async {
    final expected = '你好 🐧';
    final units = [0xfeff, ...expected.codeUnits, 0, 0];
    final bytes =
        Uint8List.fromList(units.expand((u) => [u & 255, u >> 8]).toList());
    final item = FakeItem({'NativeShell_CF_13': bytes});
    final text = resolve(FakeInfo(formats: ['NativeShell_CF_13'], item: item))
        .single as NativeText;
    expect(await text.getText(), expected);
    expect(decodeNativeText('already decoded\x00', 'NativeShell_CF_13'),
        'already decoded');
    expect(() => decodeNativeText([1], 'NativeShell_CF_13'),
        throwsFormatException);
  });
  test('registers native file and text formats, including Windows identifiers',
      () {
    final formats = platformFormatsFor(
        {const AllowPlainText(), const FileFormat(extension: 'jpg')});
    expect(
        formats,
        containsAll([
          'NativeShell_CF_13',
          'NativeShell_CF_15',
          'public.jpeg',
          'text/uri-list',
          'text/plain'
        ]));
    expect(platformFormatsFor({}), isEmpty);
  });
  test('filenames do not duplicate extensions or escape destination', () {
    expect(safeFileName('photo.png', defaultExtension: 'png'), 'photo.png');
    expect(safeFileName('photo', defaultExtension: 'png'), 'photo.png');
    expect(safeFileName('old.png', extension: '.JPG'), 'old.jpg');
    expect(safeFileName('../../outside.png', defaultExtension: 'png'),
        'outside.png');
    expect(safeFileName(r'C:\folder\photo.png'), 'photo.png');
    expect(safeFileName('CON', defaultExtension: 'txt'), '_CON.txt');
    expect(() => safeFileName('x', extension: '../txt'), throwsArgumentError);
  });

  group('file materialization', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('uni-drop-test-');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('copies a real URI-list file before trying a broken promise',
        () async {
      final original = File('${directory.path}/source.bin');
      await original.writeAsBytes([0, 1, 255]);
      final never = Completer<FakeVirtualFile>();
      final receiver = FakeReceiver('application/octet-stream', never.future);
      final info = FakeInfo(
          suggestedName: 'source.bin',
          formats: ['text/uri-list'],
          item: FakeItem({'text/uri-list': '# comment\n${original.uri}\n'}),
          virtualReceivers: [receiver]);
      final value = resolve(info).single;
      final file = await value.copyTo('${directory.path}/import');
      expect(await file.readAsBytes(), [0, 1, 255]);
      expect(receiver.requests, 0);
      expect(file.uri.pathSegments.last, 'source.bin');
    });
    test('virtual files stream and close exactly once on success', () async {
      final virtual = FakeVirtualFile([
        [1, 2],
        [3]
      ]);
      final receiver =
          FakeReceiver('application/octet-stream', Future.value(virtual));
      final value = resolve(
              FakeInfo(suggestedName: 'data.bin', virtualReceivers: [receiver]))
          .single;
      final file = await value.copyTo(directory.path);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(virtual.closes, 1);
      expect(await directory.list().length, 1);
    });
    test('failure removes only owned staging data and preserves destination',
        () async {
      final existing = File('${directory.path}/keep.bin');
      await existing.writeAsString('keep');
      final foreign =
          await Directory('${directory.path}/vfr-other-owner').create();
      final virtual = FakeVirtualFile([], error: StateError('read failed'));
      final value = resolve(FakeInfo(
          suggestedName: 'keep.bin',
          virtualReceivers: [
            FakeReceiver('application/octet-stream', Future.value(virtual))
          ])).single;
      await expectLater(
          value.copyTo(directory.path, replaceIfExist: true), throwsStateError);
      expect(await existing.readAsString(), 'keep');
      expect(await foreign.exists(), isTrue);
      expect(virtual.closes, 1);
      expect(await directory.list().length, 2);
    });
    test(
        'exclusive destination refuses overwrite and failure removes reservation',
        () async {
      final info = FakeInfo(
          suggestedName: 'data.bin',
          formats: ['application/octet-stream'],
          item: FakeItem({
            'application/octet-stream': Uint8List.fromList([1])
          }));
      final value = resolve(info).single;
      await value.copyTo(directory.path);
      await expectLater(
          value.copyTo(directory.path), throwsA(isA<FileSystemException>()));
      final broken = resolve(FakeInfo(
          suggestedName: 'broken.pdf',
          formats: ['public.file-url'],
          item: FakeItem({'public.file-url': 'https://example.com'}))).single;
      await expectLater(broken.copyTo(directory.path), throwsStateError);
      expect(await File('${directory.path}/broken.pdf').exists(), isFalse);
      expect(await directory.list().length, 1);
    });
    test('file URL is never written as binary payload', () async {
      final info = FakeInfo(
          suggestedName: 'paper.pdf',
          formats: ['public.file-url'],
          item: FakeItem(
              {'public.file-url': 'file:///missing-uni-drop-test-source.pdf'}));
      final value = resolve(info).single;
      await expectLater(value.readBytes(), throwsA(isA<FileSystemException>()));
      expect(info.item.requested, ['public.file-url']);
    });
    test('timeout cancels, closes late completion and leaves foreign temp data',
        () async {
      final pending = Completer<FakeVirtualFile>();
      final receiver = FakeReceiver('application/octet-stream', pending.future);
      final info =
          FakeInfo(suggestedName: 'late.bin', virtualReceivers: [receiver]);
      final value = NativeTypeResolver.resolveInfo([info], null,
              readTimeout: const Duration(milliseconds: 10))
          .single;
      await expectLater(
          value.copyTo(directory.path), throwsA(isA<TimeoutException>()));
      expect(receiver.progress.cancellations, 1);
      final late = FakeVirtualFile([]);
      pending.complete(late);
      await Future<void>.delayed(Duration.zero);
      expect(late.closes, 1);
      expect(await directory.list().length, 0);
    });
    test('read timeouts cancel the native text operation', () async {
      final pending = Completer<Object?>();
      final item = FakeItem({'text/plain': pending.future});
      final info = FakeInfo(formats: ['text/plain'], item: item);
      final value = NativeTypeResolver.resolveInfo([info], null,
              readTimeout: const Duration(milliseconds: 10))
          .single as NativeText;
      await expectLater(value.getText(), throwsA(isA<TimeoutException>()));
      expect(item.progresses.single.cancellations, 1);
      pending.complete(utf8.encode('late'));
    });
  });
}
