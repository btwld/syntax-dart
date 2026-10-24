# syntax

TextMate-grammar syntax highlighting in pure Dart. It uses the same grammars
and VS Code themes as VS Code and Shiki, and its output matches Shiki
token for token. It runs anywhere Dart runs, including servers, CLIs, the
web and Flutter.

## Usage

```dart
import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';

final highlighter = Highlighter(languages: [dartLanguage]);

// Styled tokens per line.
final lines = highlighter.highlight(code, language: 'dart', theme: githubDarkTheme);
for (final token in lines.first) {
  print('${token.text} ${colorToHex(token.style.foreground)}');
}

// Or render directly.
final html = highlighter.toHtml(code, language: 'dart', theme: githubDarkTheme);
print(highlighter.toAnsi(code, language: 'dart', theme: githubDarkTheme));
```

### Raw tokens and incremental state

```dart
final grammar = highlighter.grammar('dart');
StateStack? state; // null = start of document
for (final line in splitLines(code)) {
  final result = grammar.tokenizeLine(line, state);
  for (final t in result.tokens) {
    print('${line.substring(t.start, t.end)}  ${t.scopes}');
  }
  state = result.endState; // equal states mean identical tokens from here
}
```

For text that changes, such as an editor's, `TokenizedDocument` keeps the
lines tokenized and re-tokenizes only what an edit affects:

```dart
final document = TokenizedDocument(highlighter.grammar('dart'));
document.update(source); // call again after every edit
final ranges = document.ranges(githubDarkTheme); // StyledRange(start, end, style)
```

`StyledRange` offsets index into the whole text, CRLF line breaks
included. `highlighter.highlightRanges(code, ...)` returns the same ranges
in one call.

### Bundled grammars and themes

Each grammar and theme is its own library, so unused ones are tree-shaken:

- `package:syntax/langs/<name>.dart`. The bundled languages are:
  - css, dart, diff, go, html, javascript, json, jsonc, kotlin, markdown,
    python, rust, shellscript, sql, swift, typescript, xml and yaml.
  - Markdown highlights fenced code blocks for any of these languages
    that you register.
- `package:syntax/themes/<name>.dart`. The bundled themes are:
  - github-dark and github-light;
  - dark-plus and light-plus;
  - one-dark-pro, dracula, nord, monokai and tokyo-night;
  - catppuccin (latte and mocha) and vitesse (dark and light);
  - min-light and solarized-light.
- `package:syntax/langs/all.dart` and `package:syntax/themes/all.dart` contain
  everything.

### Your own grammars and themes

Any VS Code `*.tmLanguage.json` or color theme works:

```dart
highlighter.addLanguage(Language.fromJson(jsonDecode(grammarJson), name: 'toml'));
final theme = SyntaxTheme.fromJson(jsonDecode(themeJson));
```

A grammar that injects into others, such as SQL inside JS template
strings, takes `injectTo: ['source.js']`.

### Diffs and patches

```dart
// From git, or any unified diff.
final files = parsePatch(gitDiffOutput);

// Or between two versions of a file. This keeps both texts, so viewers
// can expand unchanged lines and highlight exactly.
final diff = diffTexts(before, after, path: 'lib/main.dart');

final highlighted = HighlightedDiff.of(
  diff,
  highlighter: highlighter,
  theme: githubDarkTheme,
);
final words = WordChanges.of(diff); // changed ranges inside edited lines
final colors = DiffColors.of(githubDarkTheme); // from diffEditor.* colors
```

The language comes from the file extension through
`Highlighter.languageForPath`. `.sh`, `.yml` and `.md` resolve through
language aliases. Pass `language:` to `HighlightedDiff.of` to override it.

`parsePatch` reads git's headers for added, deleted, renamed, copied and
binary files, including quoted and non-ASCII paths. Both it and `diffTexts`
leave the `\r` of CRLF lines out of `DiffLine.text`; `diffTexts` still
counts a line-ending change as a change.

To show a diff, `layoutDiff` turns files into the rows a view paints:
- file headers;
- notices, such as for a binary file;
- `@@` headers;
- collapsed unchanged lines;
- lines, or side-by-side pairs in `DiffMode.split`.

`HighlightedDiff.segmentsFor(line, words)` returns a line's styled pieces,
with the changed words marked.

## Writing a renderer

Everything except painting lives here, in neutral types: ARGB `int`
colors and UTF-16 offsets. A renderer maps them to its own widgets:
- `StyledRange` and `TokenizedDocument` for code;
- `layoutDiff`, `DiffHighlightCache` and `DiffSegment` for diffs;
- `SyntaxTheme`'s editor colors (`lineNumberForeground`,
  `selectionBackground`, `cursorForeground`) and `DiffColors` for chrome;
- `DiffLabels` for the words, and `alphaBlend` where colors can't blend.

Renderers keep their own interaction state and wording; for example,
`DiffNotice` says why a file has no lines, and the renderer words it.
`syntax_flutter` and `syntax_noir` are built this way.

Names such as `Token`, `Language` and `Grammar` are common. If they
clash with your own, import with a prefix:
`import 'package:syntax/syntax.dart' as syntax;`.

## Regex engine

Grammars are written for Oniguruma. `DartRegexEngine`, the default,
translates them to Dart `RegExp`, which is the browser's native engine on
the web. A pattern that ECMAScript cannot express never matches. Pass
`onUnsupportedPattern` to log such patterns. To run another engine,
implement `RegexEngine`.

## License

BSD 3-Clause, see [LICENSE](LICENSE). Bundled grammars and themes keep their own licenses, listed in [NOTICE](NOTICE).
