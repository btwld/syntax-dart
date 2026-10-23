# ADR-0003: Keep syntax-dart to the engine and read-only rendering

**Status:** Proposed
**Date:** 2026-10-23
**Amends:** [ADR-0001](0001-textmate-engine-on-dart-regexp.md), [ADR-0002](0002-renderer-neutral-core.md)

## Context

[ADR-0001](0001-textmate-engine-on-dart-regexp.md) chose a pure-Dart TextMate
tokenizer on `RegExp`, and [ADR-0002](0002-renderer-neutral-core.md) put
non-painting logic in `syntax` so `syntax_flutter` and `syntax_noir` only
paint.

PR #4 grew `syntax`, `syntax_flutter` and `syntax_noir` to cover full file
editing, multi-caret commands, undo history, merge-conflict resolution,
review approvals, line selections and inline comment threads, along with the
controllers that drive them (`TextDocument`, `EditorController`,
`PatchController`, `FileListController`, `MergeController`). That mixed two
different jobs in one set of packages:

- a syntax highlighting engine and read-only views of code, diffs and
  patches;
- an application-level code editor and pull-request review workflow.

Review threads, approval state, comment drafts and editor commands vary from
app to app. Putting them in `syntax` ties every consumer to one product's
domain model and doubles the surface area that every renderer has to keep in
sync.

## Decision

`syntax-dart` owns **the highlighting engine and read-only rendering of
code, diffs and patches**. It does not own editing, code review, approval,
selection or comment state, and those concerns are not split into sibling
packages in this repository either.

### In scope

- **`syntax`**:
  - the TextMate grammar compiler, tokenizer and Oniguruma-to-ECMAScript
    regex translator;
  - grammars, themes, `LanguageRegistry`, `ThemeCollection` and
    `ThemeResolver`;
  - `TokenizedDocument` (including budgeted `update` and `tokenize`) for
    incremental line-state reuse;
  - diff parsing, Myers `diffTexts`, word-level inline diffs, `DiffLayout`
    and `layoutDiff`, `DiffHighlightCache` (including budgeted slicing),
    `DiffColors` and `DiffLabels`;
  - static HTML (`toHtml`, `renderDiffHtml`) and ANSI (`toAnsi`) rendering;
  - pure layout helpers such as `RowHeightIndex`.
- **`syntax_flutter`** and **`syntax_noir`**:
  - `HighlightedCode` and `SyntaxCodeHighlighter`;
  - viewport and horizontal/vertical scroll primitives for large read-only
    views (`IndexedViewport`, `CodeHorizontalScroll`, `RowHeightIndex`);
  - read-only code, diff and patch views (`PatchView`), including collapsing
    files, expanding context gaps and scrolling to a row or offset;
  - `SyntaxTextEditingController`, which is already on `main`, stays in
    `syntax_flutter` until the consuming app replaces it with its own
    controller on top of `TokenizedDocument`.

### Out of scope

- mutable document models, undo/redo history, multi-caret editing and editor
  commands (`TextDocument`, `EditorController`, `FileListController`);
- diff review state, file approval, hunk/change resolution, merge-conflict
  workflows and comment threads (`PatchController`, `MergeController`,
  `review.dart` and comment widgets);
- background isolate or worker pools coupled to those controllers.

## Consequences

- `syntax`, `syntax_flutter` and `syntax_noir` stay small, renderer-focused
  and independent of any application's review or editor state.
- Read-only improvements from PR #4 (grammar/regex fixes, opt-in catalogs,
  line-ending preservation, inline diff modes, `DiffLayout`, `renderDiffHtml`
  and virtualized patch views) land on `main` without pulling in editor or
  review controllers.
- Applications that need editing, review or comments build their own state
  models above `TokenizedDocument`, `FileDiff`, `DiffLayout` and the
  read-only widgets.
