# ADR-0002: Shared document and review state, native rendering

**Status:** Accepted

**Updated:** 2026-10-21

## Decision

`syntax` owns source documents, transactions, tokenization, themes, diffs,
review state, editing commands and background presentation requests. It has
no runtime package dependencies and does not import Flutter or terminal UI
libraries. Flutter and noir own input, composition, focus, measurement,
painting, platform clipboard access and accessibility.

Application-supplied `SourceFile.id` identifies a document independently of
its display path or position in a collection. Content revisions increase
on every transaction, including undo/redo. Asynchronous loads and proposals
must match both their source identity and current revision before being
installed. A display path can inform language detection; it is not a path
management API. File trees and filesystem operations are outside the scope.

| Responsibility | Core contract |
| --- | --- |
| Indexed source and history | `TextDocument`, `DocumentChange`, `OffsetEdit` |
| Coordinates | Zero-based `DocumentPosition`, half-open UTF-16 ranges, directed `DocumentSelection` |
| Shared editor state | `EditorController`, `EditorCommand`, annotations, diagnostics and remote carets |
| Draft lifetime | `FileListController`, bounded `SessionStore`, explicit acquire/release |
| Incremental tokens | `LiveHighlighter`, retained raw scopes and unchanged line identities |
| Streamed source | `StreamDocumentController`, `StreamingHighlighter` |
| Patch transport | `parsePatchDocuments`, `PatchStreamParser`, metadata and diagnostics |
| Review state | `PatchController`, directed one-based `DiffSelection`, partial-content loading |
| Logical diff rows | `DiffLayout`, source lookup and bounded context expansion |
| Measurement index | `RowHeightIndex`; renderers supply pixel or cell measurements |
| Review changes | `resolveDiffChange`, `MergeController`, application acceptance callbacks |
| Appearance | `SyntaxTheme`, `ThemeResolver`, `SyntaxThemeController`, lazy collections |
| Background work | `HighlightExecutor`, `HighlightPool`, `PresentationController` |
| Portable output | `HighlightResult` serialization, static file/diff HTML and safe ANSI parsing |

`Highlighter`, `TokenizedDocument`, `HighlightedCode`, the existing text
controller adapters and `PatchView` constructors remain useful entry points.
New interactive surfaces use shared controllers so unmounting a widget does
not destroy a draft or undo history. A renderer disposes its bindings, and
the controller owner disposes the controller. Active session claims are
protected; applications release them when a view closes. Inactive sessions
are evicted according to their configured bound.
Claims are counted per mounted view. Replacing source refreshes clean sessions;
dirty sessions retain their draft and require an explicit reload before they
can complete against a changed source. Completing one view leaves other
claimants' session and history available.

## Native integration

Flutter's editor binds a native `TextField` to `EditorController`. Flutter
owns IME composing ranges and selection overlays; the shared controller owns
source, logical selections, commands and history. Read-only file and patch
surfaces mount an indexed window with overscan and measure variable-height
rows. Split panes share vertical rows and a horizontal scroll group.

The terminal editor uses noir input intents and grapheme/cell measurement.
It paints visible source rows, retaining logical UTF-16 positions in core.
Keyboard actions provide review, search, proposals, copying and conflict
resolution. Clipboard transport can be supplied by the application; the
default uses OSC 52 on an interactive terminal.
Annotation measurements count wrapped terminal cells and explicit newlines.
Custom annotation row-count and row-builder callbacks allow indexed variable
heights without building widgets for hidden rows. Long patch annotations use
a bounded, keyboard-scrollable panel.

Core supplies no widget tree, font metrics or DOM hydration API. Native
Flutter editing still uses the platform text layout for the document; only
visible lines build styled spans. The read-only file and patch surfaces are
independently virtualized. Applications can use background execution for
large documents and cooperative execution where workers are unavailable.

## Execution and compatibility

Synchronous, cooperative, native-isolate and compiled Dart browser-worker
backends consume the same serializable request. `HighlightPool` bounds
concurrency, queued distinct requests and cached results. Theme-only changes
retheme retained scopes. Grammar changes invalidate compiled state. Failure,
cancellation, timeout and disposal are explicit outcomes.

The package split and SDK minimums remain Dart 3.9 / Flutter 3.35 for the
workspace and Dart 3.10 for `syntax_noir`. There is one TextMate engine and
no additional WASM or native highlighting runtime.

## Consequences

The public core surface is larger, but selection, revision, layout and
reconstruction behavior can be tested once and exercised by both renderers.
Renderer tests cover the platform bindings in addition to core behavior.
Applications remain responsible for loading file contents, supplying proposal
providers, choosing persistence and deciding whether an edited result is
accepted. See [migration](../migration.md), [capabilities](../capabilities.md)
and [execution](../execution.md) for usage and validation.
