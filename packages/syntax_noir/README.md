# syntax_noir

Terminal widgets for [syntax](https://pub.dev/packages/syntax) on
[noir](https://pub.dev/packages/noir): code highlighted with TextMate
grammars and VS Code themes, with the same colors as VS Code.

## Usage

noir and syntax both export `DiffLine`, `DiffHunk` and `DiffLineKind`, so
import syntax with a prefix:

```dart
import 'package:noir/noir.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_noir/syntax_noir.dart';

final highlighter = syntax.Highlighter(languages: [dartLanguage]);
```

Highlight noir's `CodeView`:

```dart
CodeView(
  code: source,
  language: 'dart',
  highlighter: SyntaxCodeHighlighter(highlighter, githubDarkTheme),
);
```

Show code changes, unified or split, with the changed words highlighted:

```dart
PatchView.fromPatch(gitDiffOutput, highlighter: highlighter, theme: githubDarkTheme);
PatchView.fromTexts(
  oldText: before,
  newText: after,
  path: 'lib/main.dart',
  highlighter: highlighter,
  theme: githubDarkTheme,
  mode: syntax.DiffMode.split,
);
```

By default each source row is one terminal line; enable `wrap` to wrap code by
terminal cell width. Arrow keys move the
selection, and Enter collapses a file or shows hidden unchanged lines. The
rows come from syntax's `layoutDiff`, so they match `syntax_flutter`'s
`PatchView`. To build your own view, `PatchPainter` paints any row as a
`TextSpan` of a given width.

Don't give `SyntaxCodeHighlighter` to noir's `DiffView`. That view
highlights its rendered text, line numbers and `+`/`-` included, which no
grammar reads correctly.

Colors are converted with `noirColor` and `noirTextStyle`. Terminals don't
blend, so translucent theme colors are painted over the background first.

See [`example/main.dart`](example/main.dart).

## License

BSD 3-Clause, see [LICENSE](LICENSE).

## Shared file and review sessions

`SyntaxFileView`, `SyntaxFileList`, `SyntaxEditor`, `StreamingCodeView`,
`MergeConflictView` and `PatchView.controlled` consume renderer-neutral
controllers from `syntax`. Editing, history, selection, annotations, diagnostics,
proposed changes and drafts survive view replacement. Applications own controller
disposal and acceptance callbacks. File collections are flat.

Annotations preserve line breaks and wrap by grapheme and terminal cell width.
Editors include their measured height in the source-row index. Review notes
use a bounded panel: Tab into it and use arrows, Page Up/Down or Home/End to
scroll. Resizing remeasures annotations and preserves the editor's source
anchor. For custom variable-height content, supply `annotationRowCount` and
`annotationRowBuilder`; only visible rows build widgets. The existing
`annotationBuilder` remains a single-row convenience.

The example demonstrates editing, retained file sessions, unified/split review,
partial-content loading, conflict resolution, streaming, palettes and a large
file. See [migration](../../docs/migration.md),
[capabilities](../../docs/capabilities.md) and
[execution](../../docs/execution.md) for contracts and validation.
