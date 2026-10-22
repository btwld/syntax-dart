# Syntax playground

A gallery of working file and diff examples built with the public
`syntax_flutter` widgets and shared `syntax` controllers. The interface has
light and dark themes, responsive navigation, and project-owned code samples.

- **Diff review:** unified/split comparisons, collapsible file headers, incremental
  context expansion, inline comparison modes, line selection, source-only copy,
  local comments, hunk accept/reject actions, and editing the new side.
- **Collapsible files:** highlighted files with editable drafts retained through
  folding and navigation. Click a file header to fold it or its pencil to edit.
- **Editing:** native input, undo/redo, search/replace, an informational diagnostic,
  and an application-supplied suggestion to increase the sample retry budget.
- **Merge conflicts:** resolve current, incoming, or both, with a source preview.
- **Streaming:** start, pause, and reset a line-by-line code stream.
- **Large files:** a 100,000-line virtual list with a draggable scrollbar,
  visible-line counter, and direct jumps. Unwrapped rows use fixed extents;
  wrapping switches to measured heights. Highlighting reuses bounded cached
  windows and grammar checkpoints.

Click **Reset** to restore the current sample without changing other drafts. Review decisions, comments, and edits
stay in memory for this browser session. **Languages & themes** opens the full
catalog editor/preview; **Stress-test workflows** includes partial-patch loading
and the 1,000-file fixture.

Every push to `main` deploys it to <https://btwld.github.io/syntax-dart/>.

```bash
# From this directory:
flutter run -d chrome
```

To use the compiled highlighting worker, run from the repository root:

```bash
dart tool/build_worker.dart packages/syntax_flutter/example/web/highlight_worker.js
cd packages/syntax_flutter/example
flutter run -d chrome --dart-define=SYNTAX_WORKER=true
```

Without this asset/configuration, browser highlighting uses cooperative
execution. The worker is used by the large-file example.

It also runs on macOS with `flutter run -d macos`. Fonts load from Google
Fonts, so the first run needs network access.

Run the gallery interaction tests with `flutter test` from this directory.

Focused gallery pages cover gutter drag selection, cross-side ranges, named
section folding, separator styles, appearance and typography, token details,
custom headers, and comparing pasted sources. See the
[example matrix](../../../docs/example-matrix.md) for API mappings and limits.

The Editing toolbar includes **Keyboard shortcuts**. While the code field is
focused, use Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z for history, Ctrl/Cmd+F for search,
Ctrl/Cmd+/ for comments, Tab/Shift+Tab for indentation, Alt+Up/Down to move lines,
and Alt+Shift+Up/Down to duplicate them. Search inputs retain normal text editing
and Tab navigation. After a gutter selection, Ctrl/Cmd+C copies the selected
source in file and diff views.

Drag line numbers to reveal a comment icon at the moving end of the selection.
Click it or use Ctrl/Cmd+Shift+M to open an inline editor below the selected
lines. Ctrl/Cmd+Enter posts the note and Escape discards it. **Line selection**
supports file and diff notes, a **Custom comment action** toggle for the gutter
button, and **Custom composer** for application-supplied input and actions.
Try changing the composer while typing or switching between file and diff views:
each draft stays with its original range. The library exposes the source
snapshot and range; the gallery owns its inputs, actions and temporary notes.

Posted comments are full discussions. **Reply** opens another inline input;
**Edit** updates your own message, and **Delete** asks for confirmation inline.
**Resolve** collapses the conversation into a compact resolved indicator.
**Expand discussion** shows its messages without changing that status, while
**Reopen** expands it and returns it to an open discussion. Drafts stay available
after expanding again, and failed saves leave inline feedback. Deleting one
message keeps the other replies; deleting the final message removes the thread.
The initial review note belongs to another author, so it offers replies and
resolution while your own messages also offer edit/delete.

Switch **Custom threads** on the Line selection page to try app-supplied layout,
message actions, reply/edit inputs, resolution buttons, and **Copy discussion**.
Its custom resolved summary shows the message count and **Show discussion** /
**Reopen thread** actions; expanded resolved threads offer **Hide discussion**.
Drafts survive switching the presentation, folding files, and scrolling away.

File headers show unresolved discussion counts. The discussion toolbar jumps
backward/forward through threads and filters all, unresolved, or resolved ones.
Filtering preserves replies and drafts; counts update when discussions are
posted, resolved, reopened, or deleted. **Custom threads** also replaces the
header badges, previous/next buttons, and filter with app-supplied controls.

**Discussion shortcuts** shows the active review keys. While the review area has
focus, Alt/Option+Down/Up moves between threads, Alt/Option+R opens a reply, and
Alt/Option+Enter resolves or reopens the selected thread. Click a discussion to
select it, or select one by navigating. These commands pause while typing in an
input; Ctrl/Cmd+Enter and Escape still submit or cancel reply drafts.
**Line selection → Custom shortcuts** switches to J/K, R and X and updates the
guide and tooltips. It works in both file and diff mode.

In **Line selection**, use **Load sample threads** to add three discussions,
including a resolved one. Previous/next buttons and review hotkeys move the
active outline and linked source tint between them and reveal the selected discussion.
Each sample covers three source lines. **Custom source highlight** switches the
line tint and gutter marker to cyan independently of the card. **Custom
highlight** changes its color, tint, shape, thickness and scroll spacing; both
file and diff modes demonstrate it. The main **Diff review** uses the default
highlight. Selection stays visible through resizing and thread expansion;
manual scrolling takes precedence until the next navigation command.

Discussion icons now appear in the source gutter. Click an icon to expand,
reveal, and focus its thread; resolved threads remain resolved. A count indicates
multiple discussions at the same line, and repeated clicks cycle through them.
Filters also hide the corresponding markers. **Custom gutter** demonstrates
different icons, colors, labels, and an application-owned open action. Markers
work in file, unified, and split mode without changing the current selection.

Hover a discussion marker to preview its messages, replies, and resolved status.
The preview stays open while moving into it; **Open thread** expands and focuses
the chosen discussion. F2 opens a preview from a focused marker, and Escape
closes it. **Custom preview** adds a review notebook header, changes the surface,
and replaces the actions with **Continue review** and **Dismiss**. Both file and
diff modes demonstrate it; the main Diff review uses the default preview.

Previews also support **Reply**, **Resolve**, and **Reopen** without navigating
away. Replies share the inline thread's retained draft and persistence. Escape
keeps the draft; Cancel discards it; Ctrl/Cmd+Enter submits. **Custom preview**
replaces these controls with **Quick reply**, **Mark done** / **Reopen note**, and
an application-owned input with **Send reply** / **Discard draft**. The normal
Diff review page demonstrates the default actions.
