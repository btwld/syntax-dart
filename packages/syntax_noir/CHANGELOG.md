## 0.1.0-dev

- First release.
- `SyntaxCodeHighlighter`, a `CodeHighlighter` for noir's `CodeView`. It
  re-tokenizes only the lines an edit affects.
- `PatchView` for diffs and patches in the terminal:
  - unified and split modes;
  - file headers with change counts;
  - word-level highlights;
  - expandable unchanged lines and collapsible files, with `collapsed` and
    `expanded` sets owned by the caller (`onToggleFile`, `onExpandGap`);
  - long lines end in `…`, colored like a changed word when they hide one;
  - optional line wrapping (`wrap`), horizontal scrolling (`Alt+←`/`Alt+→`),
    sticky headers, and display flags (`inlineDiffMode`, `showBackgrounds`,
    `showChangeIndicators`, `indicators`, `showLineNumbers`,
    `hunkSeparatorStyle`).
- `PatchPainter` to paint diff rows for custom views, with display flags
  and horizontal `codeOffset` slicing.
- `noirColor` and `noirTextStyle` to convert syntax's colors and styles.
