## 0.1.0-dev

- First release.
- `HighlightedCode` for read-only code, with optional line numbers and
  selection.
- `SyntaxTextEditingController` for highlighting as you type. It
  re-tokenizes and restyles incrementally.
- `PatchView` for diffs and patches, painting the rows from `layoutDiff`:
  - unified and split modes;
  - file headers with change counts;
  - word-level highlights;
  - expandable unchanged lines;
  - a marker for a missing final newline;
  - copying that takes only the code;
  - translatable words through `DiffLabels`.
- Code reads left to right in right-to-left apps.
- `HighlighterScope` for sharing one `Highlighter`.
