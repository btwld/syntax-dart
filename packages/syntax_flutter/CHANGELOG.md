## 0.0.4

- Requires `syntax_core` 0.0.2, which `PatchView` now relies on to color
  parsed patches between frames.
- `IndexedCodeViewport` keeps the rows it has built while it scrolls. Its
  list of rows used to be keyed by its first row, which changes on nearly
  every scrolled frame, so every visible row was built again, element, state
  and text layout included. The list now starts at a row that moves only on a
  jump past everything built, a layout change, or scrolling above it (then a
  screen higher at once), and the extent of the rows after it comes from
  their measured and estimated heights. When a row built before comes back
  above the anchor with a new height, the list starts again so the rows
  above it stay where their heights put them.
- Rows are no longer rebuilt just because the viewport scrolled, and a row's
  `State` now survives scrolling. A `builder` whose rows depend on state
  outside the widget tree must rebuild the viewport's parent (or change its
  `layoutKey`) when that state changes.

## 0.0.3

Depends on `syntax_core` instead of `syntax_darts`.

## 0.0.2

Depends on `syntax_darts` instead of `syntax_core`.

## 0.0.1

See https://github.com/btwld/syntax-dart/releases/tag/syntax_flutter-v0.0.1
