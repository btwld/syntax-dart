# File and diff example matrix

This matrix separates an implemented API from an interaction that users can
actually try. It covers file and diff examples, including the native keyboard
alternatives.

The Flutter gallery is in `packages/syntax_flutter/example`. Its first six pages
cover the original workflows; six focused interaction pages follow them. The
terminal example is `packages/syntax_noir/example/main.dart` and includes an
**Interactions** page.

| Capability | Gap found | Current public API and example | Validation |
| --- | --- | --- | --- |
| Unified/split diffs | Already available | Diff review and every focused diff page; `PatchController.mode` | Existing renderer suites; selection survives a mode switch |
| Multi-line selection | Click/Shift-click existed, but no gutter drag or focused demo | **Line selection**: drag line numbers, extend with Shift, use presets, clear, copy, or annotate. Gutter drags scroll at the viewport edge. Terminal uses Shift+arrows and Ctrl+C | Flutter gesture tests cover reverse direction, exact source, autoscroll and release |
| Directed whole-line ranges | Reverse file selections could omit the original anchor line | `EditorController.selectLines(anchor, active)` includes both complete endpoint lines, preserving direction | Core UTF-16/CRLF test and Flutter upward-drag/Shift-click test |
| Selections crossing old/new sides | Extending to the other side discarded the anchor | `DiffSelection.activeSide`, `PatchController.isLineSelected`; **Select across sides** works in unified and split layouts | Core forward/reverse copying and Flutter cross-side drag tests |
| Named section folding | Section metadata was passive text | `PatchController(foldableHunks: true)`, `toggleHunk`, `setHunksCollapsed`; **Named sections** folds individual functions, folds all, or reveals a target | Core state/revision/reveal checks, Flutter semantics test, terminal Enter/reveal driver test |
| Incremental context expansion | Existing controls were difficult to discover; collapse required reset | **Named sections** exposes expansion above/below gaps and expand/collapse context; `collapseContext` preserves review state | Core context restoration and gallery interaction tests |
| Separator presentation | One default and an application builder | `HunkSeparatorStyle`: line info, compact, patch metadata and minimal. **Named sections** and **Appearance** expose choices; terminal has equivalent text styles | Renderer analysis and gallery tests |
| Diff markers and line numbers | Markers could only be enabled/disabled; diff line numbers were always visible | `DiffIndicators`: classic, bars, none; `showLineNumbers`, `showBackgrounds`; **Appearance** and terminal **Interactions** | Gallery marker/number/background controls; terminal painter suite |
| Inline comparisons and wrapping | APIs existed, with options hidden in menus | **Appearance** exposes all comparison modes and wrapping alongside split/unified | Existing inline diff suites and gallery control tests |
| Token hover/activation | Token click callbacks existed; no hover or inspection example | Flutter `PatchView.tokenTooltip`, click or keyboard activation through `onTokenTap`; **Token details** pins details and has an inspect-selected-line button. Terminal uses Alt+Enter and `onToken` | Gallery token inspection test and existing terminal token input support |
| Custom file headers | Builder existed without a focused example | **Custom headers** switches default/custom presentation and invokes the supplied fold callback | Gallery fold/expand test |
| Fonts and palettes | Focused examples overrode the gallery font; native controls could inherit the opposite palette | **Appearance** uses available loaded fonts; code surfaces apply palette colors to controls, annotations, carets and diagnostic severities | Opposite app/code palettes, font selection/reset, and all gallery pages at compact widths in light/dark themes |
| Arbitrary source comparison | Core API existed without editable input fields; comparison state leaked into adjacent samples | **Compare text** recomputes a real diff using `diffTexts`; each focused example has independent state and reset | Edited-input comparison, navigation to token inspection, and reset tests |
| Annotations and review decisions | Already available; selection entry point was not obvious | **Diff review** and **Line selection** add notes; accept/reject/combine remain in review workflows | Gallery annotation test and existing core/renderer review suites |
| Editing, markers and proposed edits | Suggestions lost syntax colors and typography; search inputs intercepted code shortcuts | **Editing** preserves the code palette, font and wrapping in suggestions and diff editors, exposes keyboard help, and limits editing shortcuts to code input | Proposal colors/visibility, Ctrl/Cmd history/comment/search/copy, Tab navigation, line movement/duplication, custom shortcuts and safe replacement tests |
| Conflicts | Syntax was highlighted, but conflict roles had no colors and actions were detached from source | **Merge conflicts** uses themed current/base/incoming backgrounds and inline resolution actions; terminal Conflicts colors the same source ranges | Section boundaries, theme overrides, light/dark presentation, sequential resolution, source selection, narrow layouts, and terminal cell-color checks |
| Streaming | Existing-line colors were cleared on every chunk; example delivery appended an extra final newline | **Streaming** retains valid prefix highlighting and exact source; stress-test streams expose wrapping and restart after cancellation | Core streaming boundaries, pending-result colors, completed-source equality, cancellation/reset and wrapping tests |
| Virtualization and partial loading | Already available after performance fixes | **Large files** and stress-test workflows demonstrate 100,000 lines, distant navigation and partial patches | Mounted-row/cache bounds, worker tests and recorded benchmarks |

## Selection and folding contracts

Line numbers in `DiffSelection` are one-based; `EditorController.selectLines`
uses zero-based lines. For a same-side diff selection, copying reads that source.
For a cross-side selection, copying follows unified diff order, includes context
once, and omits gutters, markers and annotations. Reversing a selection retains
its direction without reversing copied text. Available source terminators are
preserved; separate unterminated old/new fragments are separated with LF.

Named folding uses `DiffHunk.section`, the function/class/context text after a
patch's `@@` coordinates. The gallery supplies explicit names for its fixtures.
It folds a diff section, not an AST-derived function body in an arbitrary source
file. Automatic language-aware function discovery remains outside this API;
applications can provide section labels from their parser. Folding is opt-in,
retained across layout changes, and cleared when the source revision changes.
Revealing a line expands the containing section without opening other sections.

Native tooltip content is application supplied; the library does not bundle an
external documentation database. Font choices use installed fonts and normal
platform fallback. Platform styling uses Dart options/builders rather than CSS.

## Verification

- Core: `interaction_test.dart`, `diff_test.dart`, `review_edit_test.dart`, and
  `review_regression_test.dart`.
- Flutter: `interaction_test.dart` plus the existing renderer suite.
- Gallery: `interaction_examples_test.dart` and `showcase_test.dart`, including
  compact layouts and working input/action controls.
- Terminal: painter/unit suites and `workflow_driver_test.dart`, including
  keyboard section folding and reveal.
- Workspace analysis, formatting, and a release web build.
