# Highlighting execution and browser assets

`HighlightRequest` contains a stable file identity, content revision, raw
grammars, theme and options. An optional half-open line window limits output
presentation while preceding lines still advance TextMate state.
`HighlightResult` retains scope information and can be serialized or rethemed
without another tokenization pass.

Choose `SynchronousHighlightExecutor` for small explicit jobs,
`CooperativeHighlightExecutor` for yielding on the current isolate,
`createNativeHighlightExecutor()` for cancellable native isolates, or
`createBrowserHighlightExecutor(workerUri: ...)` for a compiled Dart worker.
Omitting the worker URI selects cooperative execution. Native creation also
falls back to cooperative execution on browser targets.

```dart
final pool = HighlightPool(
  executor: createNativeHighlightExecutor(),
  concurrency: 2,
  queueSize: 64,
  cacheSize: 16,
);
final presentation = PresentationController(
  editor: editor,
  highlighter: highlighter,
  theme: theme,
  executor: pool,
);
presentation.setViewport(100, 140);
await presentation.flush();
// presentation.line(100) returns retained presentation tokens if ready.
presentation.dispose();
pool.dispose();
```

A presentation controller does not dispose the executor supplied by its owner.
Pass a shared executor through `SyntaxFileView.executor` or
`SyntaxEditor.executor` in either renderer to use this coordinator directly.
The Flutter editor's explicit `language` override also applies to background
requests; both renderers also honor the source file's language.
The pool shares identical requests, bounds distinct queued work and cached
results, rejects queue overflow, applies a timeout, and exposes `stats`.
Cancellation ends a caller's wait immediately; another consumer of a shared
request may still need its result. `evict(fileId)` and `clearCache()` prevent
obsolete in-flight work from repopulating an invalidated cache.

`PresentationController` rejects stale source, grammar, palette and option
results. A palette-only change reuses scopes when a snapshot is available.
`LiveHighlighter` provides incremental per-line reuse when the document stays
on the caller isolate. Dispose controllers, pools and standalone executors
when their owner closes. An error is observable rather than silently applied
to another revision.

## Compile the worker

Run from the repository root after `flutter pub get`:

```sh
dart tool/build_worker.dart packages/syntax_flutter/example/web/highlight_worker.js
cd packages/syntax_flutter/example
flutter build web --release --dart-define=SYNTAX_WORKER=true
```

The application must serve the generated classic-worker script at a
same-origin URL allowed by its Content Security Policy. Supply that URL to
`createBrowserHighlightExecutor`. Worker code is compiled entirely from Dart;
there is no handwritten JavaScript dependency or separate highlighting runtime.
The worker build is an application asset step, not a runtime download.

The Flutter workflows example uses the worker when `SYNTAX_WORKER=true`, and
cooperative browser execution otherwise. A worker startup/crash error rejects
pending work, terminates the worker and switches subsequent requests to the
cooperative backend. Native isolates are killed on cancellation or disposal.

For browser tests, `dart tool/build_worker.dart` without an output argument
writes the ignored test fixture. Then run from `packages/syntax`:

```sh
flutter pub run test -p chrome test/browser_worker_test.dart test/session_test.dart test/presentation_test.dart
```

## Scale checks

Run `flutter pub run tool/benchmark.dart` from the repository root. It measures
a 100,000-line document, incremental reuse, indexed expansion, 1,000 file diffs
and bounded presentation caching. Timing is reported for inspection, not used
as a fragile CI threshold. Structural assertions check unchanged-line reuse,
compact layout blocks and cache capacity. Widget tests separately check that
large read-only files mount a bounded number of rows and can jump to a distant
line with variable-height annotations.
