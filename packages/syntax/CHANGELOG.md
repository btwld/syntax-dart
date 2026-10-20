## 0.1.0-dev

- First release.
- A TextMate tokenizer ported from vscode-textmate. It supports
  begin/end and begin/while rules, captures with their own patterns,
  external includes, end backreferences and injections.
- An Oniguruma-to-ECMAScript regex translator, so grammars run on Dart's
  built-in `RegExp`. Capture offsets are measured from the match start,
  so finding them costs the same anywhere in a long line.
- VS Code theme resolution, plus HTML and ANSI rendering.
- Renderer-neutral building blocks:
  - `TokenizedDocument` for incremental highlighting;
  - `StyledRange` and `Highlighter.highlightRanges` for styling a whole
    string;
  - editor colors on `SyntaxTheme`, and `alphaBlend`.
- Diff tools:
  - `parsePatch` for unified diffs and `git diff` output, including
    renames, copies, binary files and quoted paths;
  - `diffTexts`, a Myers line diff that groups changes the way git does;
  - `WordChanges`;
  - `HighlightedDiff`, with a `language` override and `segmentsFor`;
  - `layoutDiff`, which lays out the rows of a diff view;
  - `DiffLabels`, the English words a diff view shows;
  - `FileDiff.changeBlocks` for a GitHub-style change bar;
  - `DiffColors`, read from VS Code themes;
  - `Highlighter.languageForPath`.
- Lines over 20,000 characters are left untokenized by default, as in
  VS Code; see `Highlighter.maxLineLength`.
- 18 bundled grammars and 15 bundled themes. Token scopes and colors match
  Shiki on every bundled sample.
