# Documents, editing and review sessions

The existing `Highlighter`, `TokenizedDocument`, `HighlightedCode`,
`SyntaxTextEditingController` and `PatchView` constructors remain available.
Use the new shared controllers when a draft or review interaction must survive
collapse, scrolling or a change of renderer.

## Coordinates and identity

Create `SourceFile(id: ..., path: ..., text: ...)` with a stable, unique ID.
Changing the display order or path must not change that ID. Publish a new
revision when supplying changed content. Document positions are zero-based;
columns and offsets count UTF-16 code units, including surrogate pairs.
Ranges are half-open. Diff line numbers and `DiffSelection` endpoints are
one-based, and line selections include both endpoints.

`TextDocument` preserves LF, CRLF, lone CR and final-newline state. Edits in
one atomic batch all address the document before that batch. Overlapping
edits throw before changing text or history. Use `positionAt` / `offsetAt`
instead of converting lines with `split('\n')`. A requested `lineIdentity`
survives edits that preserve that complete line; `lineForIdentity` locates it
again. `DocumentChange.mapOffset` gives explicit insertion affinity.

```dart
final editor = EditorController(
  file: const SourceFile(id: 'settings', path: 'settings.dart', text: 'final n = 1;'),
);
editor.setSelections([const DocumentSelection(10, 11)]);
editor.insertText('42');
editor.undo();
editor.redo();
```

In Flutter, pass the session to `SyntaxEditor` or `SyntaxFileView` with a
highlighter and theme. In noir, the corresponding widgets consume the same
core controller; import core as `syntax` when noir also exports conflicting
names. `SyntaxEditor.onComplete` returns an application decision. The editor
itself never persists a file or sends a proposal to an external service.

`EditorCommand` covers indentation, comments, line movement/duplication,
undo/redo and proposal actions. Both editors expose configurable shortcuts,
selection-action builders, annotations, diagnostics and remote carets.
Flutter owns composing ranges; terminal input maps graphemes and cells back
to the same UTF-16 selection contract.

Terminal annotations wrap by cell width and preserve explicit newlines. For
custom multiline content, pair `annotationRowCount` with
`annotationRowBuilder`; the renderer builds visible annotation rows and
remeasures on resize. Long patch notes can receive Tab focus and scroll with
arrows or Home/End. The earlier `annotationBuilder` remains a single-row option.

## Flat file collections and lifetime

`FileListController` and `SyntaxFileList` retain drafts, history, selection and
scroll state by ID. The collection is flat. Its session limit bounds inactive
sessions; mounted sessions are protected. A manually managed view calls
`acquire(id)` once and `release(id)` when unmounted. Dispose the collection
when its application owner closes it. Standalone `EditorController` objects
also require disposal. Disposing a renderer binding leaves its controller
alive.

Multiple mounted views can claim the same session; each claim needs its own
release. Replacing a collection refreshes clean sessions automatically. A dirty
session retains its draft and reports `hasSourceConflict(id)` when its source
changes. Both file-list surfaces offer a reload action. `reload(id)` explicitly
discards that draft; completion rejects an obsolete base before calling the
application. Replacing a renderer's controller releases the previous owner's
claim even when both collections use the same file ID.

`reveal(id, range)` scrolls a file collection to a document range;
`EditorController.reveal(range)` targets a standalone file. Repeated reveal
commands increment a request counter even when targeting the same range.

## Controlled patches

```dart
final review = PatchController(
  parsePatch(patchText),
  contentsLoader: (file, cancellation) async {
    final pair = await loadBothSources(file);
    cancellation.throwIfCancelled();
    return pair; // ({String oldText, String newText})
  },
);
// Both renderer packages expose PatchView.controlled(controller: review, ...).
```

Use `parsePatchDocuments` for introductions, multiple commits and diagnostics.
`parsePatch` remains a tolerant file-list convenience. Parsed patches retain
object IDs, modes, original paths and transport line endings. Complete text
is explicitly nullable: load it before editing or reconstructing a review
result. Loaded text is checked against hunk content and unchanged regions;
obsolete loads are discarded.

Concurrent loads and navigation requests share one pending load per file.
Cancelled loads stop waiting even when the application provider ignores its
cancellation token. A newer navigation request wins over an older slow load.
`PatchStreamParser` preserves commit-qualified file identities across arbitrary
chunk boundaries. `DiffLine.sourceLineEnding` distinguishes source CRLF from
the patch's transport convention, including during source-only copying.
Hydration validates both source terminators and final-newline markers. Editing
a known source clears its obsolete Git object ID. Unified export rejects
lone-CR logical line terminators instead of silently normalizing them; document
editing and review operations still preserve lone CR.

`review.expand`, `expandAll` and `revealLine` change logical layout without
allocating every offscreen row. `review.changeAt` finds the change block at
a source line; `resolve` accepts an optional `changeIndex` to resolve that
block or the whole hunk. `ChangeResolution.old`, `newer` and `both` retain the
chosen source sections and recompute the remaining diff.

`beginEdit(id)` claims a new-side draft while the displayed diff regions stay
stable. `releaseEdit(id)` keeps an inactive draft within the configured bound.
`completeEdit(id, accept: ...)` recomputes a candidate and calls the application
before installing it. Completion retains a live session and its history for
other mounted views; rejecting leaves the source and draft unchanged.
`discardEdit` resets active sessions to the latest source and evicts inactive
drafts. Each view still releases its claim. Concurrent source
replacement or further input makes an in-flight completion obsolete.

`MergeController` resolves ordinary and diff3 conflicts sequentially, retaining
the surrounding document and final-newline convention. `MergeConflictView`
provides the corresponding Flutter and terminal controls.

## Streaming and proposed edits

`StreamDocumentController.add` accepts strings or UTF-8 byte chunks.
`replaceProvisional` replaces the unfinished final logical line; `finish`
flushes decoding, and `cancel` stops delivery while retaining accumulated
text. `StreamingCodeView` observes the same session in either renderer.
Invalid UTF-8 closes delivery with an observable error and never reports
successful completion. A string chunk or provisional replacement requires any
preceding byte sequence to be complete, so mixed chunks cannot reorder text.
`StreamingHighlighter` is the lower-level line-token stream, with provisional
preview and whole-document-equivalent completed output.

A `ProposedEditProvider` receives an immutable source revision, selections and
cancellation token. Return a non-overlapping edit batch against that revision.
`EditorController` debounces requests, validates edits and rejects stale
responses. Providers are application-supplied. The editors expose preview,
accept and dismiss controls; no hosted service is required.

## Catalogs and themes

The pinned catalog includes 242 top-level languages, their embedded and
injection grammars, and 65 third-party themes. Individual imports remain
available; hyphenated IDs use underscores in Dart filenames, such as
`langs/git_commit.dart`. Catalog IDs retain their hyphens.

```dart
import 'package:syntax/langs/catalog.dart';
import 'package:syntax/themes/catalog.dart';

final languages = createBundledLanguageRegistry(Highlighter());
await languages.resolve('vue'); // Also loads required embedded grammars.
final themes = ThemeResolver();
bundledThemeCollection.registerInto(themes);
final theme = await themes.resolve('github-dark');
```

Import `langs/all.dart` or `themes/all.dart` only to opt into eager catalogs.
Use `Highlighter.setLanguageForPath` for filename or compound-extension
overrides. `ThemeResolver` shares concurrent loads; `SyntaxThemeController`
handles light/dark/system selection with application-owned persistence.
`themeFromZed` imports a theme entry from a Zed collection. `createSyntaxTheme`
provides project-owned light/dark palette variants with redundant diff markers.

`renderFileHtml` and `renderDiffHtml` produce escaped static output with named
palettes, CSS variables and decoration hooks. `parseAnsi` interprets SGR
styles while removing executable terminal control sequences. Serializable
`HighlightResult` snapshots can be reused across renderers; see
[background execution](execution.md).
