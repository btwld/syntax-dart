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
viewport with it. Put larger forms in annotations, dialogs or an overlay.

Shortcuts invoke `onComment` independently of a custom builder; pass
`shortcuts: []` to disable them, or supply your own `ShortcutActivator`s. Omit
both the callback and builder to disable selection actions entirely. The
**Line selection** gallery page demonstrates default and custom actions in
both file and diff views.
