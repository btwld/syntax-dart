# syntax_noir

Terminal widgets for [syntax](https://pub.dev/packages/syntax_darts) on
[noir](https://pub.dev/packages/noir): code highlighted with TextMate
grammars and VS Code themes, with the same colors as VS Code.

## Usage

noir and syntax both export `DiffLine`, `DiffHunk` and `DiffLineKind`, so
import syntax with a prefix:

```dart
import 'package:noir/noir.dart';
import 'package:syntax_darts/langs/dart.dart';
import 'package:syntax_darts/syntax.dart' as syntax;
import 'package:syntax_darts/themes/github_dark.dart';
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

Each row is one terminal line; long lines end in `…`. Arrow keys move the
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

`pubspec_overrides.yaml` points `syntax` at the sibling package in this
repo. That file is not part of the published package. After `syntax` is on
pub.dev, a checkout without the override resolves it from there.

## License

BSD 3-Clause, see [LICENSE](LICENSE).
