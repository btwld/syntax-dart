# syntax_flutter

Flutter widgets for [syntax](https://pub.dev/packages/syntax): code highlighted with TextMate grammars
and VS Code themes.

```dart
import 'package:syntax/langs/dart.dart';
import 'package:syntax/langs/yaml.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

final highlighter = Highlighter(languages: [dartLanguage, yamlLanguage]);

// Share one highlighter, so grammars compile once.
HighlighterScope(highlighter: highlighter, child: app);

// Read-only code.
HighlightedCode(
  source,
  language: 'dart',
  theme: githubDarkTheme,
  lineNumbers: true,
);

// Highlight as you type. Only the lines an edit can affect are re-tokenized
// and restyled. textStyle is merged onto the field's own style.
final controller = SyntaxTextEditingController(
  highlighter: highlighter,
  language: 'dart',
  theme: githubDarkTheme,
  text: source,
);
TextField(controller: controller, maxLines: null, style: defaultCodeTextStyle);
```

```dart
// Code changes, unified or split, with word-level highlights.
PatchView.fromPatch(gitDiffOutput, theme: githubDarkTheme);
PatchView.fromTexts(
  oldText: before,
  newText: after,
  path: 'lib/main.dart',
  theme: githubDarkTheme,
  mode: DiffMode.split,
);
```

`PatchView` parses or diffs its input when it changes, so for very large
changes build the `FileDiff`s ahead of time and pass them to
`PatchView(files: ...)`. The language comes from each file's path unless
`language` is set. Copying a selection takes only the code, without line
numbers, markers or headers. Its words come from `DiffLabels`;
extend it to translate them. `PatchView` uses Material widgets and icons,
so it expects a `MaterialApp`.

Code always reads left to right, also in right-to-left apps.
`HighlightedCode` shows a language the highlighter doesn't know as plain
text.

`HighlightedCode` options:

- `textStyle` for the font;
- `padding`;
- `selectable`, which uses `SelectionArea`;
- `softWrap`;
- `borderRadius`.

`SyntaxThemeColors` exposes the theme's editor colors: `backgroundColor`,
`lineNumberColor`, `selectionColor` and `cursorColor`.

For your own widgets, `TokenTextStyles` converts `TokenStyle` to
`TextStyle`, and `highlightedTextSpan` builds a span tree.

See [`example/`](example) for a live editor with every bundled language
and theme.

## License

BSD 3-Clause, see [LICENSE](LICENSE).

## Shared file and review sessions

`SyntaxFileView`, `SyntaxFileList`, `SyntaxEditor`, `StreamingCodeView`,
`MergeConflictView` and `PatchView.controlled` consume renderer-neutral
controllers from `syntax`. Editing, history, selection, annotations, diagnostics,
proposed changes and drafts survive view replacement. Applications own controller
disposal and acceptance callbacks. File collections are flat.

The example demonstrates editing, retained file sessions, unified/split review,
partial-content loading, conflict resolution, streaming, palettes and a large
file. See [migration](../../docs/migration.md),
[capabilities](../../docs/capabilities.md) and
[execution](../../docs/execution.md) for contracts and validation.

## Selection actions and comments

Pass `onComment` to `SyntaxFileView`, `SyntaxFileList` previews, or any `PatchView`
constructor to show a comment button beside the active end of a logical line
selection. Drag line numbers or extend with Shift. The button stays in the active
pane of a split diff and does not change the selection when activated.
Ctrl/Cmd+Shift+M invokes the same callback while the view has focus; the button
also supports Tab and Enter. Native text selection remains separate.

```dart
PatchView.controlled(
  controller: review,
  theme: githubDarkTheme,
  onComment: (details) {
    // Open your form using details.file.id, details.file.revision,
    // and details.selection (including both endpoints and their sides).
  },
  selectionActionStyle: const SelectionActionStyle(
    tooltip: 'Discuss selected lines',
    icon: Icon(Icons.chat_bubble_outline, size: 14),
    buttonStyle: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.indigo),
      foregroundColor: WidgetStatePropertyAll(Colors.white),
    ),
  ),
);
```

`FileSelectionDetails` captures a source snapshot, UTF-16 selection, zero-based
line endpoints and source-only `selectedText`. `DiffSelectionDetails` captures
the file snapshot and directed, inclusive one-based `DiffSelection`. Before
applying an asynchronous comment, check that the file identity and revision are
still current. Forms, storage, permissions and annotation rendering belong to
your application; use the controller's annotations and `annotationBuilder` to
display saved comments.

Use `selectionActionBuilder: (context, details) => yourWidget` to replace the
entire action, even without `onComment`. Return null to hide it for a particular
selection. Custom widgets supply their own callbacks and accessible labels.
`SelectionActionStyle` controls placement within the source row, the reserved
`gutterWidth`, the default icon/button/tooltip, and shortcut bindings. Increase
the gutter width for a wider custom action, or use zero with trailing alignment.
Actions fit within the source row, keep its height unchanged and leave the
viewport with it. Use `commentBuilder` for a form below the selected range.

Shortcuts invoke `onComment` independently of a custom builder; pass
`shortcuts: []` to disable them, or supply your own `ShortcutActivator`s. Omit
both the callback and builder to disable selection actions entirely. The
**Line selection** gallery page demonstrates default and custom actions in
both file and diff views.

### Inline comment editors

Keep the selected snapshot and draft controller in application state, then pass
`commentSelection` and `commentBuilder` to the view. The composer appears below
the last selected display row, even for upward or cross-side selections. In a
split diff it spans both panes. It stays attached to that snapshot when the live
selection changes; folding or scrolling the row out of view preserves an
application-owned draft. A changed source revision hides the stale form.

```dart
// State fields; dispose the controller with your review session.
final draft = TextEditingController();
DiffSelectionDetails? pendingComment;

// In build:
PatchView.controlled(
  controller: review,
  theme: githubDarkTheme,
  onComment: (details) => setState(() => pendingComment = details),
  commentSelection: pendingComment,
  commentBuilder: (context, details) => SyntaxCommentComposer(
    controller: draft,
    onSubmit: (text) {
      if (!review.files.any(details.matches)) return;
      // Save text with details.selection in your application's review store.
      draft.clear();
      setState(() => pendingComment = null);
    },
    onCancel: () {
      draft.clear();
      setState(() => pendingComment = null);
    },
  ),
);
```

`SyntaxFileView` and `SyntaxFileList` use the same properties with
`FileSelectionDetails`. Use `matches` before saving to validate the captured
source. An app can call `reveal` or `revealLine` when opening a hidden range;
`DiffSelectionDetails.endIn(mode)` identifies the final display endpoint.

`SyntaxCommentComposer` is optional: `commentBuilder` accepts any widget. Its
`inputBuilder` and `actionsBuilder` receive `CommentComposerDetails`, containing
the retained controller, optional focus node, submitting state, and nullable
submit/cancel commands. Use them for rich inputs, attachments or custom buttons.
The default form supports Ctrl/Cmd+Enter to submit and Escape to cancel;
`shortcutsEnabled: false` lets your input supply its own commands. Native input
shortcuts are isolated from the surrounding source viewer's shortcuts.

Customize the heading, labels, input decoration, typography, card decoration,
padding and margin, or replace the input and action area entirely. Applications
own `isSubmitting`, `errorText`, persistence and permissions. Empty drafts and
pending submissions disable the supplied submit command; pending submissions
also disable cancellation. The form never saves or clears text itself. Retain
controllers outside row builders to preserve drafts during virtualization.

Saved notes remain controller annotations. `annotationLineBuilder` on file
views can position a range annotation below its last line, while preserving its
full source range. Diff annotations can use the endpoint from `endIn(mode)`.

### Posted comment threads

Render `SyntaxCommentThread` from an `annotationBuilder` to add replies, inline
message editing, inline delete confirmation, and resolve/reopen actions. The
renderer-neutral `ReviewThread` and `ReviewComment` models live in `syntax`;
annotation ranges remain independent of the messages. Deleting a root message
keeps the remaining replies. Deleting the last message produces an empty thread
that the application can remove from its annotation list.

```dart
// Own sessions by stable thread ID, outside virtualized annotation builders.
final discussion = CommentThreadController(
  thread: ReviewThread(
    id: 'discussion-42',
    comments: const [
      ReviewComment(
        id: 'message-1',
        author: 'Alex',
        authorId: 'alex',
        body: 'Could we cover an empty name in a test?',
      ),
    ],
  ),
  onUpdate: persistThread, // FutureOr<ReviewThread> Function(ReviewThreadChange)
  permissions: CommentThreadPermissions(
    edit: (comment) => comment.authorId == currentUserId,
    delete: (comment) => comment.authorId == currentUserId,
  ),
);

// Within the corresponding file or diff annotationBuilder:
SyntaxCommentThread(controller: discussion);
```

`onUpdate` receives a `ReviewThreadChange` with its operation, exact base snapshot,
and message ID, text or resolution state. Authorize and persist it in your app,
then return the same thread ID with a higher revision. `ReviewThread.copyWith`
increments the revision by default. Subscribe to the controller to synchronize
annotation payloads or other application state. Omitting `onUpdate` makes the
thread read-only; permission predicates also hide individual actions. Backend
authorization remains the application's responsibility.

The controller retains reply/edit text and focus across row unmounts. Saves are
serialized, failed requests keep their drafts open, and errors appear inline.
Closing a tall inline editor preserves the discussion in the viewport as the row
shrinks.
`setThread` applies newer remote snapshots; stale responses and responses after
disposal cannot overwrite them. A remotely changed message cannot be overwritten
by an edit based on its old contents. Local invalidation does not cancel a server
request: also validate `change.thread.revision` at your persistence boundary.
Dispose sessions after their views unmount or when the containing session ends.

Resolved discussions collapse into a compact **Resolved** indicator with
**Expand discussion** and **Reopen** controls. Expanding reveals messages and
retained reply/edit drafts without changing the resolution or saving a revision.
Reopening saves through `onUpdate` and expands only after success. Failed requests
stay inline, including in the collapsed summary. Explicit expansion survives
scrolling, folding, and newer snapshots that keep the same resolution status.
Read-only threads can still expand and collapse.

`CommentThreadController(collapseResolved: false, ...)` opts out of automatic
collapse. Applications can also call `expand()` and `collapse()` and observe
`isCollapsed`; these affect local presentation only. A newly resolved remote
snapshot follows the same automatic-collapse policy. Collapsing unfocuses hidden
inputs while retaining their draft text.

Customize any level of the presentation:

- `builder(context, details, child)` replaces or wraps the whole thread.
- `headerBuilder` and `actionsBuilder` replace the header and thread commands.
- `collapsedBuilder(context, details, child)` replaces or wraps the compact
  resolved summary; `collapsedActionsBuilder` replaces its expand/reopen actions.
  Details expose `isCollapsed`, `expand`, `collapse`, and `toggleResolved`.
  The same card styling and error builder apply to collapsed discussions.
- `commentBuilder(context, details, child)` replaces a complete message;
  `commentActionsBuilder` replaces its edit/delete controls.
- `composerBuilder` replaces reply/edit input and actions. Its details contain
  retained text/focus controllers and nullable submit/cancel commands.
- `errorBuilder` renders application failures. Default errors avoid displaying
  raw exception details.
- `CommentThreadLabels`, `decoration`, `textStyle`, `padding`, and `margin`
  customize default text and presentation.

Builder details expose guarded commands and the application-owned controller,
including deletion confirmation and cancellation. The default reply/edit forms
support Ctrl/Cmd+Enter and Escape through `SyntaxCommentComposer`. Custom editors
can supply their own keyboard behavior. `SyntaxCommentComposer.canSubmit` disables
submission for additional validation or permissions without discarding a draft.

The **Line selection** example's **Custom threads** toggle demonstrates custom
layout, inputs, message actions, thread actions, collapsed summaries, and a
copy-discussion command. Default expand/collapse labels are customizable through
`CommentThreadLabels`; default controls support Tab traversal and Enter/Space.
The [gallery session store](example/lib/comment_threads.dart) demonstrates local
persistence, permission checks, annotation updates, and controller disposal.

### Discussion counts, navigation and filters

Bind `CommentNavigationController` to the same source that holds your
`ReviewThread` annotations, and pass it to the view. Headers then show the live
number of unresolved discussions. Counts include hidden threads and count each
discussion once, regardless of how many replies it contains.

```dart
// Retain outside build; dispose before disposing review.
final discussions = CommentNavigationController.patch(review);

Column(children: [
  SyntaxCommentNavigation(controller: discussions),
  Expanded(child: PatchView.controlled(
    controller: review,
    highlighter: highlighter,
    theme: theme,
    commentNavigation: discussions,
    annotationBuilder: (context, annotation) => SyntaxCommentThread(
      controller: threadSessions[annotation.id]!,
    ),
  )),
]);
```

Use `.file(editor)` for `SyntaxFileView`, or `.files(files)` for
`SyntaxFileList`. The file binding accepts `annotationLine` when your view's
`annotationLineBuilder` anchors discussions at a range endpoint. The file-list
binding observes retained sessions without mounting their views. Applications
with persisted discussions beyond that bounded cache can use the ordinary
constructor with `CommentThreadLocation` entries and `onReveal`, updating anchors
through `setThreads`. `onCancelReveal` cancels application scroll requests when
navigation is superseded, filtered or disposed.

Previous/next wraps through visible threads in source order, unfolds the target,
loads missing patch context, and reveals the individual discussion even when
several share a line. Pass `fileId` to `SyntaxCommentNavigation` to restrict
navigation and counts to one file. `CommentThreadFilter.all`, `.unresolved`, and
`.resolved` control both annotation visibility and navigation; other annotation
types stay visible. Filtering leaves the underlying annotations and app-owned
thread sessions intact, including reply/edit drafts.

Controls can live in any application toolbar. `builder` replaces or wraps the
whole `SyntaxCommentNavigation`; `countBuilder`, `actionsBuilder`, and
`errorBuilder` customize individual parts. `CommentNavigationDetails` exposes
counts, current position, visible threads, guarded previous/next commands, and
`setFilter`. `CommentNavigationLabels`, padding and decoration customize defaults.
Native buttons support Tab traversal and Enter/Space.

File, collection and patch views expose `commentCountBuilder` to replace the
header badge, including alongside custom headers. Return `SizedBox.shrink()` to
hide it, or place `SyntaxCommentCount` in your own header. The **Custom threads**
gallery option demonstrates custom count badges, navigation buttons, and a
**Hide resolved** filter. Default controls also offer resolved-only review.
