# File and diff capability checklist

Scope: highlighted files, flat file collections, patches, review interactions,
editing, conflicts, streaming, catalogs and execution.

Dedicated gallery coverage and the interaction gaps found during review are
tracked separately in the [file and diff example matrix](example-matrix.md).
An API entry below does not by itself imply a dedicated example.

The checklist maps public contracts to working renderer surfaces and behavioral
checks. Examples are `packages/syntax_flutter/example/lib/workflows.dart` and
`packages/syntax_noir/example/main.dart`; both include Editor, Files, Patch,
Conflicts, Stream and Large workflows. The original Flutter example also
provides the complete language/theme picker.

| Complete | Capability and public contract | Renderer/demo integration | Behavioral validation |
| --- | --- | --- | --- |
| [x] | Stable files, revisions, zero-based positions, half-open UTF-16 transactions, original line endings: `SourceFile`, `TextDocument` | Shared native editor bindings | `review_edit_test`, `lifecycle_test`; randomized edits, atomic overlap rejection, emoji, all CRLF edit boundaries |
| [x] | Directed/multiple selections, undo/redo, search/replace, indentation, comments, line operations, surrounding and matching brackets: `EditorController` | Both `SyntaxEditor` surfaces, command shortcuts and selection-action builders | Core editing tests; Flutter native typing/IME and multi-selection tests; noir input/undo/search drivers |
| [x] | Annotations through edits, diagnostics, external carets, gutter/line/token events | Both file/editor/patch surfaces and custom builders | Core annotation transforms, Flutter annotation/caret tests, noir annotation/diagnostic driver cases |
| [x] | Draft/history/view-state retention with explicit release: `SessionStore`, `FileListController`, patch edit sessions | Collapse and unmount in flat file lists and review editors | Core active-session protection and bounded inactive drafts; both renderer restoration tests |
| [x] | Incremental token revisions, changed ranges, viewport priority, pause/resume/flush and unchanged-line reuse: `LiveHighlighter` | Visible file/editor lines and background presentation option | `session_test`, `presentation_test`, scale benchmark |
| [x] | UTF-8/text streaming, incomplete characters/lines, provisional replacement, completion and cancellation | `StreamingCodeView` in both examples | Every UTF-8 split compared to whole-document output; stream decode failure/cancellation tests; Flutter streamed input |
| [x] | Filename/compound-extension overrides, aliases, lazy registration and scope classification | Existing highlighter input and file language detection | `highlighter_test`, `session_test`, `lifecycle_test` |
| [x] | Complete pinned catalog: 242 language IDs, 260 grammar libraries including dependencies/injections, 65 third-party themes | Individual imports, eager catalogs and deferred registries; complete example picker | Every bundled pattern compiles; 37 conformance fixtures under three palettes; lazy dependency/alias checks; deterministic generation |
| [x] | Theme collections, shared async loading, persistence, light/dark/system appearance and Zed import | Themes passed directly to all renderer surfaces; palette controls in both examples | `session_test`, `lifecycle_test`; import, deduplication, contrast and theme-only scope reuse |
| [x] | Ten project-owned accessible palette variants with redundant change markers | Both examples expose variant and brightness controls | Normal text contrast >= 7:1 and syntax accents >= 4.5:1 in each palette |
| [x] | Multi-palette static file/diff HTML, escaped decoration hooks, CSS classes/variables and safe ANSI input | Renderer-independent export APIs | `presentation_test` validates escaping, diff output and removal of OSC/cursor controls |
| [x] | Patch introductions, modes/object IDs/paths, multi-file/multi-commit parsing, extraction, trimming, diagnostics and incremental transport | `PatchView.fromPatch`, controlled reviews and partial-loading demo | Parser/diff fixtures, `review_edit_test`, mailbox and malformed-input checks |
| [x] | Partial-patch full-source loading with validation and revision rejection | Load-contents controls in both patch views | Core invalid/stale load checks; Flutter hydration and review actions |
| [x] | Word, merged-word, changed-span, character and disabled inline comparison | Configurable patch mode in both examples | `word_diff_test`, core comparison cases and patch painter checks |
| [x] | Lazy indexed layout, source lookup, above/below expansion, expand-all and reveal | Both `PatchView` surfaces; distant-file navigation | Core 100,000-line layout test; renderer expansion and navigation tests |
| [x] | Directed source-line selection, source-only copy, individual-block/hunk accept/reject/combine | Both controlled patch views | Reconstruction and block lookup tests; Flutter review workflow and noir source-copy drivers |
| [x] | Ordinary/diff3 conflict parsing and sequential current/incoming/both resolution | `MergeConflictView` in both examples | Exact surrounding text/final-newline core tests and both renderer conflict interactions |
| [x] | Stable new-side edit sessions and recomputation on application-controlled completion | Review editing in both patch surfaces | Core stale completion/session bounds and renderer completion tests |
| [x] | Optional debounced proposed edits, cancellation, version checks, preview, accept/dismiss | Both editors; example TODO provider | Core stale proposal checks, Flutter acceptance, noir suggestion driver |
| [x] | Unified/split rows, wrapping/horizontal scrolling, aligned gutters, optional backgrounds/indicators, sticky/custom headers and separators | Both file/review renderers | Existing patch suites plus workflow/resize tests; synchronized split scrolling and measured Flutter rows |
| [x] | Native Flutter input, IME, semantics and selection overlays | `SyntaxEditor` and selectable file/patch widgets | Flutter controller, semantics, composition and interaction suites |
| [x] | Terminal cell/grapheme-aware input, clipboard and keyboard actions | noir input intents, OSC 52 or custom copy callback | Painter Unicode/tab tests and native noir driver interactions |
| [x] | Synchronous/cooperative/native-isolate/browser-worker execution, bounded queue/cache, shared requests and disposal | `PresentationController`; large-file demos choose native or browser execution | Executor equivalence, cancellation/invalidation/disposal tests; compiled worker failure and fallback tests |
| [x] | Serializable precomputed presentations and theme-only restyling | `HighlightResult` and viewport coordinator | Round-trip result equality, stale output rejection and retained raw scopes |
| [x] | Bounded mounted read-only rows, grammar state before a viewport, variable-height measurements and stable source anchoring | Indexed Flutter file/patch windows; terminal visible row painting | Large-file widget assertions, `RowHeightIndex` tests and `tool/benchmark.dart` |

## Verification commands

From the workspace root:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed packages tool
dart analyze --fatal-infos
dart tool/build_worker.dart
```

From `packages/syntax`:

```sh
flutter pub run test
flutter pub run test -p chrome test/translator_test.dart test/highlighter_test.dart test/document_test.dart test/review_edit_test.dart test/review_regression_test.dart test/session_test.dart test/presentation_test.dart test/lifecycle_test.dart test/browser_worker_test.dart
```

Run `flutter test` in `packages/syntax_flutter`, and `dart test` in
`packages/syntax_noir`. Build the Flutter web example with the compiled worker
as described in [execution](execution.md). CI also checks the minimum SDKs and
deterministic catalog generation. See [benchmark results](benchmarks.md) for
recorded scale measurements and their limits.

## Verified implementation

Verified on 2026-10-21:

| Check | Result |
| --- | --- |
| Core VM suite | 588 passed on Dart 3.12.0 and 3.9.2 |
| Browser suite, including compiled worker | 119 passed in Chrome |
| Flutter widget and interaction suites | 55 passed on Flutter 3.44.0 and 3.35.7 |
| Terminal unit and native driver suites | 35 passed on Dart 3.12.0 and 3.10.0 |
| Formatting and analysis | Clean |
| Generated catalog and notices | 330 files identical after regeneration |
| Flutter web release example with worker asset | Built on both Flutter SDKs |

Minimum-SDK verification used an isolated source copy with fresh dependency and
build caches. The core remains free of runtime package dependencies.

## Review regression coverage

The follow-up review added 20 core, five Flutter, and six terminal regression
cases. The fixes are also exercised by the complete existing suites.

| Area | Corrected behavior | Validation |
| --- | --- | --- |
| Session ownership | Shared mounted views retain independent claims; completion/discard keeps other views usable; clean sources refresh, stale drafts require explicit reload | Core session regressions; Flutter controller replacement/reload; terminal collection replacement |
| Navigation | Repeated reveals work, obsolete loads cannot overwrite a newer target, logical patch targets survive row-count changes, terminal reveal does not move the caret | Core concurrent reveal checks; Flutter repeated reveal; native terminal distant/first/distant navigation |
| Partial loading | Concurrent and reentrant requests share one load; cancellation stops waiting for uncooperative providers; hydration preserves review marks and validates source endings/counts | Core loading, cancellation, annotation and malformed-source cases |
| Native editing | Adjacent selections remain distinct, the primary direction survives surrounding, repeated-character insertions update every caret, and deletion respects grapheme boundaries | Core edit regressions and both platform text-input bindings |
| Rendering | Grammar replacement invalidates existing file/editor presentation; wrapped Flutter rows remeasure and restore the source anchor; terminal controller swaps clear old row indexes | Flutter grammar replacement/viewport cases; terminal controller swap driver |
| Terminal annotations | Multiline notes wrap by grapheme/cell width; custom row measurements participate in layout; long review notes have keyboard scrolling; resize preserves source anchors | Four native driver cases for default/custom height, resize and scrolling; terminal example |
| Patch fidelity | Source CRLF and transport CRLF round-trip independently; partial and complete source copy preserves terminators; edited object IDs are invalidated; streamed commits keep unique IDs | Round-trip, hydration, source copy and every-chunk-boundary tests |
| Streaming and execution | Invalid UTF-8 never reports successful completion; byte/string chunks cannot reorder text; failures detach producers; the last cancelled consumer releases queued or active highlighting capacity | Core stream/pool regressions, VM and Chrome |

Unified patch export rejects lone-CR logical line terminators because its
line-oriented representation cannot encode those boundaries faithfully.
Documents, edits and native review operations preserve them. The existing
large-file platform layout and grammar-state limits are recorded in
[benchmarks](benchmarks.md).
