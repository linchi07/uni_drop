# 0.1.1

- Add synchronous onDropStart with the final location before metadata I/O, so
  editors can track a durable insertion anchor while asynchronous reads run.

# 0.1.0

Extract UniChat's embedded paste_and_drop component into an independent package.

- Remove imports of UniChat's app singleton and path utilities.
- Preserve unified text/image/text-file/file receiving and the language map.
- Deliver final view/local coordinates and session ID with the reader.
- Correct text/image allowlists, JPEG aliases and extension normalization.
- Prefer file content over alternate text/URL representations, without duplicates.
- Register native identifiers for Apple, Windows and MIME-based platforms.
- Decode Windows UTF-16LE values without an app-specific platform switch.
- Prefer usable real file URLs over broken file promises.
- Bound metadata/reads, request cancellation, and close late virtual files.
- Close streams/files on failures without replacing the original read error.
- Replace broad temporary-directory deletion with task-owned cleanup.
- Stage file writes before replacement, preserve extensions, sanitize names,
  and refuse unintended overwrites.
- Isolate drop sessions, route nested targets, and freeze the target before I/O.
- Register only attached regions, unregister on detach, and serialize updates.
- Use copy operations only and do not initialize native drag-source hooks.
- Add explicit clipboard-reader disposal and use upstream text-writing codecs.

Native upstream hangs are not claimed fixed by Dart timeouts. See README.
