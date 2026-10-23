# Verification — 2026-10-23

Environment: Flutter 3.41.6, Dart 3.11.4, Apple Silicon macOS.

- flutter analyze --no-pub: no findings, including the inspector example.
- flutter test --no-pub: 27 unit/widget regression tests passed.
- Disposable macOS host: native plugin compiled and one integration test passed
  for real DropContext initialization, format registration, widget mount/detach
  and unregister. No simulator build was run in EverNote or UniChat.
- Disposable Web host: production JavaScript compilation and Wasm dry run passed.
- All seven original UniChat component files match the extraction SHA-256
  manifest; no writes were made to UniChat.

The native-context test does not simulate an OS-level Finder drag. Windows,
Android, iOS and Linux have not been validated on real devices in this extraction.
Web compilation is not a browser/source-application interoperability test.
The package regressions simulate source metadata and native contexts to cover
format and encoding rules, cancellation and cleanup, nesting, session routing,
and drop coordinates. Native bugs in upstream platform-thread code remain
subject to real-device reproduction as described in README.
