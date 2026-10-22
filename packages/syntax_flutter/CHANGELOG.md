## Unreleased

- Add shared-controller file, file-list, editor, conflict and streaming widgets.
- Extend patch reviews with partial loading, annotations, selections, source
  copying, hunk and individual-change actions, and application-controlled edits.
- Add native IME editing, search, diagnostics, proposed edits, custom shortcuts
  and retained drafts; virtualize read-only rows with measured scroll anchoring.
- Add synchronized horizontal scrolling, background presentation and complete
  workflow examples, including large files and browser workers.

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
