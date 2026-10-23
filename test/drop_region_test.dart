import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_native_extensions/raw_drag_drop.dart' as raw;
import 'package:uni_drop/uni_drop.dart';

import 'fakes.dart';

raw.DropEvent event(
        {int session = 1,
        Offset location = const Offset(100, 100),
        List<String> formats = const ['text/plain'],
        List<DropOperation> operations = const [DropOperation.copy]}) =>
    raw.DropEvent(
        sessionId: session,
        locationInView: location,
        allowedOperations: operations,
        items: [raw.DropItem(itemId: 1, formats: formats)]);

NativeData textValue() => NativeTypeResolver.resolveInfo([
      FakeInfo(formats: ['text/plain'], item: FakeItem({'text/plain': 'hello'}))
    ], null)
        .single;

Widget positioned(Widget child, {double left = 50, double top = 60}) =>
    Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          Positioned(
              left: left, top: top, width: 200, height: 160, child: child)
        ]));

void main() {
  testWidgets('start freezes final location before awaiting metadata',
      (tester) async {
    final context = FakeContext();
    final pending = Completer<List<NativeData>>();
    var started = false;
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) {
          expect(started, isTrue);
          return pending.future;
        });
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onDropStart: (event) {
          started = true;
          expect(event.localLocation, const Offset(75, 60));
        },
        onPerformDrop: (_) {},
        child: const SizedBox.expand())));
    await registry.ready;
    await context.delegate!.onDropUpdate(event());
    final receiving = context.delegate!
        .onPerformDrop(event(location: const Offset(125, 120)));
    expect(started, isTrue);
    pending.complete([textValue()]);
    await receiving;
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets(
      'receives over blank padding and freezes final view/local coordinates',
      (tester) async {
    final context = FakeContext();
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) async =>
            [textValue()]);
    NativeDropEvent? received;
    NativeDropOverEvent? over;
    final leaves = <int>[];
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onDropUpdate: (e) {
          over = e;
          return DropOperation.copy;
        },
        onDropLeave: (e) => leaves.add(e.sessionId),
        onPerformDrop: (e) {
          received = e;
        },
        child: const SizedBox.expand())));
    await registry.ready;
    expect(context.registrations.single, contains('NativeShell_CF_13'));
    expect(await context.delegate!.onDropUpdate(event()), DropOperation.copy);
    expect(over?.localLocation, const Offset(50, 40));
    await context.delegate!
        .onPerformDrop(event(location: const Offset(125, 120)));
    expect(received?.location, const Offset(125, 120));
    expect(received?.localLocation, const Offset(75, 60));
    expect(received?.session.sessionId, 1);
    expect(received?.reader.items.single, isA<NativeText>());
    await context.delegate!.onDropEnded(raw.BaseDropEvent(sessionId: 1));
    expect(leaves, [1]);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
    expect(context.registrations.last, isEmpty);
  });

  testWidgets('nested rejecting child falls back to accepting parent',
      (tester) async {
    final context = FakeContext();
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) async =>
            [textValue()]);
    var outer = 0;
    var inner = 0;
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onPerformDrop: (_) {
          outer++;
        },
        child: NativeDropRegion(
            registry: registry,
            supportedFormats: {const FileFormat(extension: 'png')},
            onPerformDrop: (_) {
              inner++;
            },
            child: const SizedBox.expand()))));
    await registry.ready;
    expect(await context.delegate!.onDropUpdate(event()), DropOperation.copy);
    await context.delegate!.onPerformDrop(event());
    expect(outer, 1);
    expect(inner, 0);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets('custom child veto preserves the negotiated parent on final drop',
      (tester) async {
    final context = FakeContext();
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) async =>
            [textValue()]);
    var outer = 0;
    var inner = 0;
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onPerformDrop: (_) {
          outer++;
        },
        child: NativeDropRegion(
            registry: registry,
            supportedFormats: {const AllowPlainText()},
            onDropUpdate: (_) => DropOperation.none,
            onPerformDrop: (_) {
              inner++;
            },
            child: const SizedBox.expand()))));
    await registry.ready;
    expect(await context.delegate!.onDropUpdate(event()), DropOperation.copy);
    await context.delegate!.onPerformDrop(event());
    expect(outer, 1);
    expect(inner, 0);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets('rejects destructive move-only sessions and empty filters',
      (tester) async {
    final context = FakeContext();
    final registry = DropFormatRegistry(contextProvider: () async => context);
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onPerformDrop: (_) => fail('should not accept'),
        child: const SizedBox.expand())));
    await registry.ready;
    expect(
        await context.delegate!
            .onDropUpdate(event(operations: [DropOperation.move])),
        DropOperation.none);
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {},
        onPerformDrop: (_) => fail('should not accept'),
        child: const SizedBox.expand())));
    await registry.ready;
    expect(await context.delegate!.onDropUpdate(event()), DropOperation.none);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets('session leave and end cannot clear another session',
      (tester) async {
    final context = FakeContext();
    final registry = DropFormatRegistry(contextProvider: () async => context);
    final leaves = <int>[];
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onPerformDrop: (_) {},
        onDropLeave: (e) => leaves.add(e.sessionId),
        child: const SizedBox.expand())));
    await registry.ready;
    await context.delegate!.onDropUpdate(event(session: 1));
    await context.delegate!.onDropUpdate(event(session: 2));
    await context.delegate!.onDropLeave(raw.BaseDropEvent(sessionId: 1));
    await context.delegate!.onDropEnded(raw.BaseDropEvent(sessionId: 1));
    expect(leaves, [1]);
    await context.delegate!.onDropEnded(raw.BaseDropEvent(sessionId: 2));
    expect(leaves, [1, 2]);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets('does not deliver an old drop to a replacement target after I/O',
      (tester) async {
    final context = FakeContext();
    final pending = Completer<List<NativeData>>();
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) =>
            pending.future);
    var deliveries = 0;
    Widget region(Key key) => positioned(NativeDropRegion(
        key: key,
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onPerformDrop: (_) {
          deliveries++;
        },
        child: const SizedBox.expand()));
    await tester.pumpWidget(region(const ValueKey('original')));
    await registry.ready;
    await context.delegate!.onDropUpdate(event());
    final receiving = context.delegate!.onPerformDrop(event());
    await tester.pumpWidget(region(const ValueKey('replacement')));
    pending.complete([textValue()]);
    await receiving;
    expect(deliveries, 0);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets(
      'coordinates stay tied to the drop even if target moves during I/O',
      (tester) async {
    final context = FakeContext();
    final pending = Completer<List<NativeData>>();
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) =>
            pending.future);
    NativeDropEvent? received;
    Widget region(double left) => positioned(
        NativeDropRegion(
            registry: registry,
            supportedFormats: {const AllowPlainText()},
            onPerformDrop: (e) {
              received = e;
            },
            child: const SizedBox.expand()),
        left: left);
    await tester.pumpWidget(region(50));
    await registry.ready;
    await context.delegate!.onDropUpdate(event());
    final receiving = context.delegate!.onPerformDrop(event());
    await tester.pumpWidget(region(75));
    pending.complete([textValue()]);
    await receiving;
    expect(received?.localLocation, const Offset(50, 40));
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets(
      'text-file hover can accept an ambiguous iOS text type, then filters snippets',
      (tester) async {
    final context = FakeContext();
    var returnSnippet = false;
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) async =>
            returnSnippet
                ? [textValue()]
                : NativeTypeResolver.resolveInfo([
                    FakeInfo(
                        suggestedName: 'draft', formats: ['public.plain-text'])
                  ], null));
    var deliveries = 0;
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowAllTextFileFormats()},
        onPerformDrop: (e) {
          deliveries++;
          expect(e.reader.items.single, isA<NativeTextFile>());
        },
        child: const SizedBox.expand())));
    await registry.ready;
    expect(
        await context.delegate!
            .onDropUpdate(event(formats: ['public.plain-text'])),
        DropOperation.copy);
    await context.delegate!
        .onPerformDrop(event(formats: ['public.plain-text']));
    expect(deliveries, 1);
    returnSnippet = true;
    expect(await context.delegate!.onDropUpdate(event(session: 2)),
        DropOperation.copy);
    await context.delegate!.onPerformDrop(event(session: 2));
    expect(deliveries, 1);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });

  testWidgets('reports reader errors and clears highlight once',
      (tester) async {
    final context = FakeContext();
    final registry = DropFormatRegistry(
        contextProvider: () async => context,
        resolver: (items, formats, metadataTimeout, readTimeout) async =>
            throw StateError('metadata failed'));
    NativeDropFailure? failure;
    var leaves = 0;
    await tester.pumpWidget(positioned(NativeDropRegion(
        registry: registry,
        supportedFormats: {const AllowPlainText()},
        onPerformDrop: (_) => fail('should not accept'),
        onDropError: (e) {
          failure = e;
        },
        onDropLeave: (_) {
          leaves++;
        },
        child: const SizedBox.expand())));
    await registry.ready;
    await context.delegate!.onDropUpdate(event(session: 3));
    await context.delegate!.onPerformDrop(event(session: 3));
    expect(failure?.sessionId, 3);
    expect(failure?.error, isA<StateError>());
    expect(leaves, 1);
    await tester.pumpWidget(const SizedBox());
    await registry.ready;
  });
}
