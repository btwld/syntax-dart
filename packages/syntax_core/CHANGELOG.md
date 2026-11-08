## Unreleased

- Add `DiffSide`, directed, revision-bearing `DiffSelection` ranges and
  `DiffAnnotation<T>` payloads with value equality. Selections retain cross-side
  endpoints for copying; annotations reject mismatched source files/revisions
  and invalid coordinates.

## 0.0.3

- `SyntaxTheme.background` and `foreground` start from the editor colors. A
  theme whose first token setting names only a foreground, such as Monokai and
  Solarized Light, used to get a white background, so a dark theme drew its
  diff chrome on white.
- `DiffColors.muted` is stronger, so `@@` lines and other diff labels reach
  4.5:1 on `hunkHeader` in the GitHub themes. They read 4.03:1 in GitHub Light.
  Catppuccin Latte, One Dark Pro, Solarized Light, Tokyo Night and Vitesse
  Light stay below 4.5:1 but improve.

## 0.0.2

- `HighlightedDiff.of` and `HighlightedDiff.tokenize` honor `budget` for
  parsed patches too, not only for diffs with full texts. A large patch is
  tokenized a slice at a time, the new side first, with the state carried
  across slices within a hunk and reset at each hunk as before; lines not
  tokenized yet are plain. `PatchView` in `syntax_flutter` therefore colors
  long parsed patches between frames instead of in one blocking call.

## 0.0.1

See https://github.com/btwld/syntax-dart/releases/tag/syntax_core-v0.0.1
