## 0.1.0-dev

- First release.
- `HighlightedCode` for read-only code, with optional line numbers and
  selection.
- **Breaking:** removed `SyntaxTextEditingController`. Editing belongs in
  the consuming application on top of `TokenizedDocument`.
- `PatchView` for diffs and patches, painting the rows from `layoutDiff`:
  - unified and split modes;
  - file headers with change counts;
  - word-level highlights;
  - expandable unchanged lines;
  - a marker for a missing final newline;
  - copying that takes only the code;
  - translatable words through `DiffLabels`.
- Code reads left to right in right-to-left apps.
- `PatchView` highlights large files between frames, so a big diff
  doesn't block them. Lines show plain until their colors are ready.
- `PatchView` virtualizes row layout with `IndexedCodeViewport`, takes
  caller-owned `collapsed` and `expanded` sets with `onToggleFile` and
  `onExpandGap` callbacks, sizes gutters by the widest digit, and supports
  synchronized horizontal scrolling (`HorizontalCode`, `wrap: false`),
  sticky file headers, custom header and hunk builders, and display
  options (`inlineDiffMode`, `showBackgrounds`, `showChangeIndicators`,
  `indicators`, `showLineNumbers`, `hunkSeparatorStyle`).
- `SyntaxChrome` adapts Material controls to the active `SyntaxTheme`.
- `HighlightedCode` re-tokenizes only the lines that change.
- `HighlightedCode` lays out a large file in blocks of lines, and only the
  blocks on screen when its height is bounded, so a 7,500-line file shows
  without freezing. It tokenizes between frames, and code taller than its
  box now scrolls. Line numbers keep the height of their lines, and
  copying keeps line breaks and the lines scrolled out of view.
- **Breaking:** `HighlightedCode` with more than 200 lines can't report
  intrinsic sizes, so it can't sit inside `IntrinsicHeight` or an
  `AlertDialog`'s content. Give it a size instead.
- `HighlighterScope` for sharing one `Highlighter`.
