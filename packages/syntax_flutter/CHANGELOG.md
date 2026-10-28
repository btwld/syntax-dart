## 0.0.7

- Keep only the explicitly requested viewport rows alive during native text
  selection. Flutter's automatic selection retention no longer keeps every
  intermediate selected row mounted.

## 0.0.6

- Upward scrolling after a far jump keeps existing row elements and state.
  Extending the virtual list remaps row offsets instead of remounting it.
- `IndexedCodeViewport.retainedRows` keeps explicitly named row identities
  alive during scrolling, for example a text selection's endpoints. Releasing
  those identities lets offscreen rows be disposed normally.
- Export `RowSelectionDelegate` for selection across virtualized code cells.

## 0.0.5

- `IndexedCodeViewport` keeps the first visible row, and the rows after it,
  in place when the layout changes: a new `layoutKey`, `count` or
  `estimatedHeight`, or a new width. Since 0.0.4, a row the list kept
  through such a change was not measured again, so its height fell back to
  the estimate and the rows below it landed off by the difference, as a
  file's header did when its rows were loaded below it.

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
