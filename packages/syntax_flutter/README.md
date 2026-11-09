# syntax_flutter

Flutter widgets for [syntax](https://pub.dev/packages/syntax_core): code highlighted with TextMate grammars
and VS Code themes.

```dart
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/langs/yaml.dart';
import 'package:syntax_core/themes/github_dark.dart';
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
extend it to translate them.

Both views render under a routed `WidgetsApp`, with no Material theme,
localizations, ancestor or icon font. File headers and context gaps support
pointer, Enter and Space activation and expose button semantics. Default
chevrons, expansion glyphs and missing-newline markers are painted; the
missing-newline marker announces `DiffLabels.noNewlineAtEnd` to assistive
technology and stays outside copied code.

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
- `selectable`, which uses the widgets-layer `SelectableRegion`;
- `selectionChrome` for selection controls and menus;
- `softWrap`;
- `borderRadius`.

To use your host's selection controls or action widgets, pass the same
`SyntaxSelectionChrome` to either view:

```dart
final chrome = SyntaxSelectionChrome(
  selectionControls: mySelectionControls,
  contextMenuBuilder: mySelectionMenu,
  actionBuilder: (context, action, child) => MyButton(
    label: action.label,
    onPressed: action.onInvoke,
    child: child,
  ),
  noNewlineMarkerBuilder: (context, message) => MyMarker(message: message),
);

HighlightedCode(source, language: 'dart', theme: githubDarkTheme,
    selectionChrome: chrome);
PatchView.fromPatch(gitDiffOutput, theme: githubDarkTheme,
    selectionChrome: chrome);
```

`selectionControls` is required on the configuration. Controls that mix in
`TextSelectionHandleControls` use `contextMenuBuilder`; legacy Flutter controls
manage their own toolbar. A null menu builder uses the plain Copy/Select all
menu, localized through `WidgetsLocalizations`. Omit `selectionChrome` to use
`SyntaxSelectionChrome.plain`, including painted draggable handles. Custom
`actionBuilder` controls own focus, keyboard activation and semantics;
`action` supplies `kind`, `label`, `enabled`, `onInvoke` and `expanded`.
`noNewlineMarkerBuilder` replaces the visual marker while preserving its
accessible description. Callers can supply their design system's tooltip here.

`SyntaxChrome` applies palette colors with `DefaultTextStyle`, `IconTheme`,
`DefaultSelectionStyle` and a `ColoredBox`; it does not install an application
theme or restyle application buttons.

For source navigation, own a controller and dispose it with your view:

```dart
final source = CodeViewController(sourceId: 'lib/main.dart', code: code);
source.selectLines(12, 9); // Inclusive, directed, zero-based source lines.
source.revealLine(9); // Can be requested before mounting.

HighlightedCode.controlled(
  controller: source,
  language: 'dart',
  theme: githubDarkTheme,
  lineNumbers: true,
  softWrap: true,
  lineBackgroundBuilder: (line) => line == 9 ? const Color(0x223399ff) : null,
  gutterBuilder: (context, line) => line == 9 ? const Text('!') : null,
);

source.setCode(updatedCode, revision: 1); // Clears selection and reveal.
```

Gutter clicks and drags select whole lines; Shift extends from the anchor.
Control+C and Command+C copy the selected source with its original line
breaks. Native character selection takes precedence over line selection.
An empty source has one line, and a trailing newline adds an empty final
line. Invalid selection or reveal indices throw `RangeError`.

Both constructors accept `lineBackgroundBuilder` and `gutterBuilder`.
Backgrounds cover each source line's wrapped continuations, with controller
line selection painted over them. A gutter builder reserves 24 logical pixels
before the line number, even for `null` markers;
markers stay fixed during horizontal scrolling and are excluded from copying.
Line slots and controlled views use individual virtualized source rows,
so line numbers remain aligned when wrapping. Give large sources a bounded
height to keep layout limited to visible rows.

Large bounded views request only built line windows. They paint plain text
while colors arrive, advance grammar state before each window, and bound
retained work. Small sources keep incremental highlighting by default.
Unbounded code layouts still tokenize synchronously because every row is laid
out; give large sources a bounded height.

Both widgets accept `executor:`, a `HighlightExecutor` function with the same
signature as `highlightWindow`. This allows an application-owned isolate or
worker, which creates its own highlighter inside its isolate. Calls are
serialized, including cancelled calls that have not settled;
results must echo the exact request, theme and grammar revision. Source and
grammar changes invalidate old colors, and disposal ignores late results.
`HighlightWindowScheduler` exposes this scheduling contract and retention
counters for custom views. One oversize input is allowed alone. Executors
should honor cancellation between lines; a single regex match cannot be
interrupted by cooperative cancellation.

`SyntaxThemeColors` exposes the theme's editor colors: `backgroundColor`,
`lineNumberColor`, `selectionColor` and `cursorColor`.

For your own widgets, `TokenTextStyles` converts `TokenStyle` to
`TextStyle`, and `highlightedTextSpan` builds a span tree.

See [`example/`](example) for a live preview with every bundled language
and theme. The [plain widgets demo](example/lib/widgets_app.dart) runs with
`flutter run -t lib/widgets_app.dart` from the example directory.

## License

BSD 3-Clause, see [LICENSE](LICENSE).
