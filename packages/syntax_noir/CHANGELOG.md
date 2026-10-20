## 0.1.0-dev

- First release.
- `SyntaxCodeHighlighter`, a `CodeHighlighter` for noir's `CodeView`. It
  re-tokenizes only the lines an edit affects.
- `PatchView` for diffs and patches in the terminal:
  - unified and split modes;
  - file headers with change counts;
  - word-level highlights;
  - expandable unchanged lines and collapsible files.
- `PatchPainter` to paint diff rows for custom views.
- `noirColor` and `noirTextStyle` to convert syntax's colors and styles.
