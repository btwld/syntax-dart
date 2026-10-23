# syntax_flutter

Flutter widgets for [syntax](https://pub.dev/packages/syntax): code highlighted with TextMate grammars
and VS Code themes.

```dart
import 'package:syntax/langs/dart.dart';
import 'package:syntax/langs/yaml.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

final highlighter = Highlighter(languages: [dartLanguage, yamlLanguage]);

// Share one highlighter, so grammars compile once.
HighlighterScope(highlighter: highlighter, child: app);

// Read-only code.
HighlightedCode(
  source,
  language: 'dart',
  theme: githubDarkTheme,
  lineNumbers: true,
);
```

```dart
// Code changes, unified or split, with word-level highlights.
PatchView.fromPatch(gitDiffOutput, theme: githubDarkTheme);
PatchView.fromTexts(
  oldText: before,
  newText: after,
  path: 'lib/main.dart',
  theme: githubDarkTheme,
  mode: DiffMode.split,
);
```

`PatchView` parses or diffs its input when it changes, so for very large
changes build the `FileDiff`s ahead of time and pass them to
`PatchView(files: ...)`. The language comes from each file's path unless
`language` is set. Copying a selection takes only the code, without line
numbers, markers or headers. Its words come from `DiffLabels`;
extend it to translate them. `PatchView` uses Material widgets and icons,
so it expects a `MaterialApp`.

Code always reads left to right, also in right-to-left apps.
`HighlightedCode` shows a language the highlighter doesn't know as plain
text. Give a large file a bounded height, for example with `Expanded`: it
then lays out only the lines on screen. Inside another scroll view every
line is laid out. Above 200 lines, `HighlightedCode` has no intrinsic
height, so it cannot sit inside `IntrinsicHeight` or an `AlertDialog`'s
content.

`HighlightedCode` options:

- `textStyle` for the font;
- `padding`;
- `selectable`, which uses `SelectionArea`;
- `softWrap`;
- `borderRadius`.

`SyntaxThemeColors` exposes the theme's editor colors: `backgroundColor`,
`lineNumberColor`, `selectionColor` and `cursorColor`.

For your own widgets, `TokenTextStyles` converts `TokenStyle` to
`TextStyle`, and `highlightedTextSpan` builds a span tree.

See [`example/`](example) for a live preview with every bundled language
and theme.

## License

BSD 3-Clause, see [LICENSE](LICENSE).
