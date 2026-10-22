# Syntax playground

A gallery of working file and diff examples built with the public
`syntax_flutter` widgets and shared `syntax` controllers. The interface has
light and dark themes, responsive navigation, and project-owned code samples.

- **Diff review:** unified/split comparisons, collapsible file headers, incremental
  context expansion, inline comparison modes, line selection, source-only copy,
  local comments, hunk accept/reject actions, and editing the new side.
- **Collapsible files:** highlighted files with editable drafts retained through
  folding and navigation. Click a file header to fold it or its pencil to edit.
- **Editing:** native input, undo/redo, search/replace, an informational diagnostic,
  and an application-supplied suggestion to increase the sample retry budget.
- **Merge conflicts:** resolve current, incoming, or both, with a source preview.
- **Streaming:** start, pause, and reset a line-by-line code stream.
- **Large files:** jump to line 90,001 in a 100,000-line document.

Click **Reset** to restore the samples. Review decisions, comments, and edits
stay in memory for this browser session. **Languages & themes** opens the full
catalog editor/preview; **Stress-test workflows** includes partial-patch loading
and the 1,000-file fixture. These are flat file collections, with no file tree.

Every push to `main` deploys it to <https://btwld.github.io/syntax-dart/>.

```bash
# From this directory:
flutter run -d chrome
```

To use the compiled highlighting worker, run from the repository root:

```bash
dart tool/build_worker.dart packages/syntax_flutter/example/web/highlight_worker.js
cd packages/syntax_flutter/example
flutter run -d chrome --dart-define=SYNTAX_WORKER=true
```

Without this asset/configuration, browser highlighting uses cooperative
execution. The worker is used by the large-file example.

It also runs on macOS with `flutter run -d macos`. Fonts load from Google
Fonts, so the first run needs network access.

Run the gallery interaction tests with `flutter test` from this directory.
