## Unreleased

- Add shared-controller file, file-list, editor, conflict and streaming surfaces.
- Add keyboard review actions, directed selection, source-only clipboard copying,
  partial patch loading and application-controlled completion of edited diffs.
- Add cell-aware wrapping, retained drafts, search, diagnostics, annotations,
  proposed edits, custom shortcuts and background presentation.
- Expand the terminal example to demonstrate editing and review workflows,
  including large files and partial patches.

## 0.1.0-dev

- First release.
- `SyntaxCodeHighlighter`, a `CodeHighlighter` for noir's `CodeView`. It
  re-tokenizes only the lines an edit affects.
- `PatchView` for diffs and patches in the terminal:
  - unified and split modes;
  - file headers with change counts;
  - word-level highlights;
  - expandable unchanged lines and collapsible files;
  - long lines end in `…`, colored like a changed word when they hide one.
- `PatchPainter` to paint diff rows for custom views.
- `noirColor` and `noirTextStyle` to convert syntax's colors and styles.
