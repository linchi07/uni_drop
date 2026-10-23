# uni_drop

A native drop-receiving and clipboard package extracted from **UniChat**.
The name remembers the project where this component first became useful.

Instead of repeating platform-format conditionals at every input widget,
applications receive one normalized item per source item: `NativeText`,
`NativeImage`, `NativeTextFile`, `NativeFile`, `NativeVideo`, or `NativeAudio`.

Built on `super_native_extensions` / `super_clipboard` 0.9.1, with receiving-side
routing and normalization maintained here. uni_drop does not create drag sources.
The original UniChat application is unchanged. See [origin and licenses](THIRD_PARTY_NOTICES.md).

## Install

This is a Git dependency, not a pub.dev release. Pin a tested commit:

```yaml
dependencies:
  uni_drop:
    git:
      url: https://github.com/linchi07/uni_drop.git
      ref: <full-commit-sha>
```

For local library development, use a temporary pubspec_overrides.yaml with a
path dependency rather than changing a consumer's committed pin.

## Receive

```dart
import 'package:uni_drop/uni_drop.dart';

NativeDropRegion(
  supportedFormats: {
    const AllowPlainText(),
    const AllowAllTextFileFormats(),
    const FileFormat(extension: 'png'),
    const FileFormat(extension: 'jpg'), // also matches jpeg
    const FileFormat(extension: 'pdf'),
  },
  onPerformDrop: (event) async {
    final position = event.localLocation;
    for (final item in event.reader.items) {
      if (item is NativeText) {
        final text = await item.getText();
        // Insert text at your editor's position derived from `position`.
      } else {
        // Stream into an application-owned import directory before returning.
        final file = await item.copyTo(importDirectory);
        // Register `file` with the application's own attachment/resource store.
      }
    }
  },
  onDropError: (failure) {
    // Show/report failure.error; failure.sessionId identifies the operation.
  },
  child: editor,
)
```

`event.location` is in logical pixels within the Flutter view;
`event.localLocation` is local to the receiving region. Neither is physical
screen coordinates. The final location, callback, format set and target are
captured before metadata I/O. Text caret/paragraph geometry and durable document
anchors belong to the editor, not this generic receiving package.

`onDropEnter`, `onDropUpdate`, and `onDropLeave` provide hover feedback.
The default hit-test behavior also accepts blank child/padding areas.
Only copy is accepted; move-only sessions are rejected. A child can reject a
session with `DropOperation.none`, allowing an eligible parent to receive it.

A file with an alternate text representation remains a file. AllowPlainText
accepts snippets; AllowAllTextFileFormats accepts text files, not snippets.
AllowAllFileFormats accepts any supported file or snippet. Known directories
are excluded; recursive folder import is outside this release.
Extensions and MIME/type identifiers provide classification, not a guarantee
about the contents or safety of a file.

### Reading and lifecycle

- Read/copy the required content **before onPerformDrop returns**. Native reader
  handles belong to the session and cannot be saved for later reads.
- Use copyTo/openRead for large files. readBytes explicitly buffers the entire
  item. Keep CPU-heavy parsing, network operations and application indexing
  outside the native callback after stabilizing the input.
- metadataTimeout defaults to 10 seconds. readTimeout defaults to 30 seconds
  per request/chunk and can be increased for cloud-backed providers.
- Timeouts request best-effort native cancellation, close late-arriving files,
  and clean only staging files owned by this operation. They cannot unwind a
  platform-thread hang that prevents Dart callbacks from running.
- copyTo is native-filesystem-only. On web use openRead/readBytes. Missing file
  extensions are inferred for known formats; existing extensions are preserved.
  Passing extension explicitly replaces the extension. Existing destination
  files are preserved unless replaceIfExist is true, including on read failure.
- One native context has one receiving delegate. Do not mix uni_drop regions and
  super_drag_and_drop DropRegion on the same context. Using super_clipboard is
  compatible. The upstream raw context is tied to one view/engine; this release
  does not promise arbitrary multi-view/multi-isolate drag routing.

### Clipboard

```dart
await NativeClipboard.withReader((reader) async {
  for (final item in reader.items.whereType<NativeText>()) {
    final text = await item.getText();
  }
}, supportedFormats: {const AllowPlainText()});
```

For explicit ownership, use NativeClipboard.read and await reader.dispose in
finally. withReader performs disposal automatically. Clipboard writes remain
available via NativeDataWriterItem / NativeClipboard.write; this does not add
outbound dragging.

## Platforms and verification

Apple identifiers, Windows CF_UNICODETEXT/CF_HDROP and MIME/URI-list receiving
are supported. Unit/widget regressions exercise format selection, UTF-16LE,
streaming, cancellation, late cleanup, nested targets, session isolation and
logical/local coordinates. These use fake native contexts and do not establish
real-device interoperability across all operating systems or source apps.

Native binary/build prerequisites are inherited from
[super_native_extensions](https://github.com/superlistapp/super_native_extensions).
Android uses the native NDK toolchain (minimum API 23). Writing Android clipboard
images/custom data additionally requires the upstream DataProvider manifest
entry; receiving-only use does not add it. Web requires browser-provided drop
access, and has no filesystem copyTo operation.

Known upstream reports, not reproduced or claimed resolved here:
[macOS drag-source initialization/tap delay](https://github.com/superlistapp/super_native_extensions/issues/602),
[Windows native perform-drop wait](https://github.com/superlistapp/super_native_extensions/issues/601).
uni_drop initializes only DropContext, avoiding the unnecessary drag-source
initialization path. It does not silently vendor or patch upstream native code.
The old VS Code macOS file-promise hang is mitigated by real-file preference and
bounded reads; its Objective-C/Rust root cause still requires native reproduction.

## Develop

```sh
flutter pub get
flutter analyze
flutter test
```

An item/position inspector is provided in example/lib/main.dart. Generate the
platform runner you want without replacing its Dart entry point:

```sh
cd example
flutter create --platforms=macos --project-name uni_drop_example .
flutter run -d macos
```

The public callback changed from onPerformDrop(reader) to onPerformDrop(event);
the reader is now event.reader. The paste_and_drop.dart import is retained as a
migration convenience. Clipboard read results now have explicit disposal.
