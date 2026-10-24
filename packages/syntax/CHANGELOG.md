## 0.1.0-dev

- First release.
- A TextMate tokenizer ported from vscode-textmate. It supports
  begin/end and begin/while rules, captures with their own patterns,
  external includes, end backreferences and injections.
- An Oniguruma-to-ECMAScript regex translator, so grammars run on Dart's
  built-in `RegExp`. Capture offsets are measured from the match start,
  so finding them costs the same anywhere in a long line.
- A rule's patterns are searched with one combined regex only when they're
  small (`DartRegexEngine.combineMaxSource`). Grammars with very large
  patterns, such as TypeScript, no longer stall on first use. Oniguruma's
  absent repeater `(?~...)` is translated, and combined scanners fall back
  to individual scans on non-ASCII lines and Dart 3.9 native runtimes.
- Equal `const` grammar maps are cloned per grammar, and decoded untyped
  maps keep stable views, so TextMate rule identities stay distinct.
- `Highlighter` tracks `revision`, supports `setLanguageForPath`,
  `clearPathLanguages` and compound file suffixes, and keeps aliases from
  shadowing canonical language names.
- VS Code theme resolution, plus HTML and ANSI rendering.
- Renderer-neutral building blocks:
  - `TokenizedDocument` for incremental highlighting. With a time budget,
    `update` and `tokenize` work a slice at a time, so a large file never
    blocks a UI thread;
  - `StyledRange` and `Highlighter.highlightRanges` for styling a whole
    string;
  - `RowHeightIndex` for logarithmic prefix-sum row height indexing;
  - editor colors on `SyntaxTheme`, and `alphaBlend`.
- Diff tools:
  - `parsePatch` for unified diffs and `git diff` output, including
    renames, copies, binary files, quoted paths, git header object IDs and
    modes, and independent transport and source line endings;
  - `diffTexts`, a Myers line diff that groups changes the way git does,
    preserving `\n`, `\r\n` and `\r` source line endings and copying `id`,
    `revision` and `language` onto `FileDiff`;
  - `WordChanges` and `InlineDiffMode` (`word`, `mergedWords`,
    `changedSpan`, `character`, `none`), skipping lines over 10,000
    characters;
  - `HighlightedDiff`, with a `language` override and `segmentsFor`, and
    `DiffHighlightCache` to keep it per file. Both can highlight a slice
    at a time too;
  - `DiffLayout`, `layoutDiff`, `DiffIndicators` and `HunkSeparatorStyle`,
    which lay out the rows of a diff view lazily;
  - `renderDiffHtml` and `HtmlDecoration` for multi-theme static diff HTML;
  - `DiffLabels`, the English words a diff view shows;
  - `FileDiff.changeBlocks` for a GitHub-style change bar;
  - `DiffColors`, read from VS Code themes;
  - `Highlighter.languageForPath`.
- Lines over 20,000 characters are left untokenized by default, as in
  VS Code; see `Highlighter.maxLineLength`.
- 18 bundled grammars and 15 bundled themes. Token scopes and colors match
  Shiki on every bundled sample.
