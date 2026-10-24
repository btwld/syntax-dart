# ADR-0002: The core owns everything but painting

**Status:** Accepted
**Date:** 2026-10-19
**Amended by:** [ADR-0003](0003-engine-and-readonly-rendering.md). Renderers stay read-only. Editing and review state stay in the consuming application.

## Context

`syntax_flutter` is the first renderer, and `syntax_noir` is planned for
[noir](https://github.com/btwld/noir), a terminal UI framework on OpenTUI.
`syntax` itself already renders HTML and ANSI.

Noir's `CodeView` and `DiffView` take a `CodeHighlighter`, an interface with
one method. It returns non-overlapping UTF-16 `StyledTextRange`s over the
whole source, styled with noir's own `TextStyle` (see
`packages/noir/lib/src/widgets/code_view.dart` in that repository).

Until now, several pieces that have nothing to do with Flutter lived
privately in `syntax_flutter`:

- incremental re-tokenizing, in the text controller;
- the fallbacks for line number, selection and cursor colors;
- the patch layout: gaps, split pairing and line numbering;
- splitting tokens where changed words start and end.

A second renderer would have copied them. The patch layout alone had two
line-numbering bugs found in review, so copies would have copied
bugs too.

## Decision

`syntax` provides everything a renderer needs, in neutral types: colors as
ARGB `int`s, offsets in UTF-16 code units, and no `dart:ui`. A renderer only
paints and handles interaction.

| Need | Core API |
|---|---|
| Tokens and incremental state | `Grammar.tokenizeLine`, `StateStack` |
| Styles | `TokenStyle` (colors and bold, italic, underline, strikethrough), `SyntaxTheme` |
| Editor colors | `SyntaxTheme.foreground`, `background`, `lineNumberForeground`, `selectionBackground`, `cursorForeground`, `editorColor` |
| One styled string | `Highlighter.highlightRanges` returning `StyledRange`s |
| A document being edited | `TokenizedDocument`; unchanged `DocumentLine`s keep their identity, so renderers can cache per line |
| Diffs | `parsePatch`, `diffTexts`, `FileDiff` |
| Diff presentation | `layoutDiff` returning `DiffRow`s, `DiffHighlightCache` and `HighlightedDiff.segmentsFor` returning `DiffSegment`s, `DiffColors` (including opaque chrome colors), `FileDiff.maxLineNumber`, `FileDiff.changeBlocks` |
| Words | `DiffLabels`, English defaults that renderers extend to translate |
| Blending | `alphaBlend`, for renderers such as terminals that can't blend |

Renderers own:

- widgets, layout, fonts and spacing;
- interaction state, such as collapsed files, expanded gaps and selection;
- the final wording. The core reports *why* a file has no lines as a
  `DiffNotice` value, and `DiffLabels` gives English defaults that a
  renderer, or an app, extends to translate.

`syntax_flutter` now follows this. `PatchView` paints `layoutDiff` rows,
`SyntaxTextEditingController` keeps a `TokenizedDocument`, and the
`SyntaxThemeColors` getters wrap the core colors.

### `syntax_noir`

`packages/syntax_noir` follows this split:

- `SyntaxCodeHighlighter` implements noir's `CodeHighlighter` with a
  `TokenizedDocument` per language, for noir's `CodeView`.
- Its `PatchView` paints `layoutDiff` rows as one terminal line each.
- Colors go through `alphaBlend` first, because terminals don't blend.

noir's own `DiffView` can't use syntax's highlighting. It passes the
highlighter its whole rendered text, including `@@` lines, line numbers and
`+`/`-` markers, and in split mode both sides on one line. No grammar reads
that correctly, so `syntax_noir` has its own patch view. If `DiffView`
passed each line's code instead, it could use `SyntaxCodeHighlighter`
directly.

noir needs Dart 3.10 while the workspace packages support Dart 3.9, so
`syntax_noir` resolves on its own, with a dependency override on
`../syntax` until syntax is published. noir also exports `DiffLine`,
`DiffHunk` and `DiffLineKind`, so code using both imports syntax with a
prefix.

## Options considered

- **Keep the logic in each renderer.** This means less public API in core,
  but every renderer re-implements the patch layout and the incremental
  tokenizer, and their bugs.
- **Core owns all non-painting logic (chosen).** Renderers stay thin, and
  the logic is tested once, in plain Dart, without widget tests. The cost is
  that `DiffRow`, `TokenizedDocument` and friends are now public contracts.
- **A full renderer interface in core**, such as `abstract class
  SyntaxRenderer`. Flutter and a terminal framework share too little at the
  painting level for one interface to help, so data types are the
  contract instead.

## Consequences

- A new renderer maps rows and segments to its own widgets. It never
  computes line numbers, gaps or word ranges.
- The core's public surface is larger, and changes to the row types or
  `TokenizedDocument` affect every renderer.
- Layout behavior is tested in `packages/syntax/test`. That includes a
  property test that expanding every gap rebuilds both files.

## Reconsider when

- A renderer needs something the core can't express neutrally, such as
  measured text widths for wrapping or bidirectional text.
- Noir's `CodeHighlighter` gains incremental or streaming semantics that
  `TokenizedDocument.update` with the whole source doesn't fit.
- Very large patches need the layout to be lazy, producing rows on demand
  instead of as one list.
