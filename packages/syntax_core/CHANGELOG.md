## 0.0.2

- `HighlightedDiff.of` and `HighlightedDiff.tokenize` honor `budget` for
  parsed patches too, not only for diffs with full texts. A large patch is
  tokenized a slice at a time, the new side first, with the state carried
  across slices within a hunk and reset at each hunk as before; lines not
  tokenized yet are plain. `PatchView` in `syntax_flutter` therefore colors
  long parsed patches between frames instead of in one blocking call.

## 0.0.1

See https://github.com/btwld/syntax-dart/releases/tag/syntax_core-v0.0.1
