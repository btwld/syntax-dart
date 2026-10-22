import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'interaction_test.dart' show app, row, gutter;

const commentLabel = 'Comment on selected lines';
Finder get comment => find.byTooltip(commentLabel);

Future<void> shortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier, {
  LogicalKeyboardKey key = LogicalKeyboardKey.keyM,
  bool shift = true,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets(
    'switching between owned and supplied review state keeps source identity correct',
    (tester) async {
      final highlighter = Highlighter();
      final review = PatchController([
        diffTexts(
          'external old',
          'external new',
          id: 'external',
          path: 'b.txt',
        ),
      ]);
      DiffSelectionDetails? result;
      Widget view({bool controlled = false}) => app(
        controlled
            ? PatchView.controlled(
                controller: review,
                highlighter: highlighter,
                theme: githubDarkTheme,
                onComment: (value) => result = value,
              )
            : PatchView.fromTexts(
                oldText: 'local old',
                newText: 'local new',
                path: 'a.txt',
                highlighter: highlighter,
                theme: githubDarkTheme,
                onComment: (value) => result = value,
              ),
      );
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      await tester.tapAt(gutter(tester, 'local new'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(view(controlled: true));
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      await tester.tapAt(gutter(tester, 'external new'));
      await tester.pumpAndSettle();
      await tester.tap(comment);
      expect(result!.file.id, 'external');
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      expect(find.text('local new', findRichText: true), findsOneWidget);
      expect(comment, findsNothing);
      await tester.tapAt(gutter(tester, 'local new'));
      await tester.pumpAndSettle();
      await tester.tap(comment);
      expect(result!.file.path, 'a.txt');
      await tester.pumpWidget(const SizedBox());
      review.dispose();
    },
  );
  testWidgets(
    'file collections forward comment customization and retain range notes across collapse',
    (tester) async {
      final files = FileListController([
        const SourceFile(id: 'a', path: 'a.txt', text: 'one\ntwo'),
      ]);
      await tester.pumpWidget(
        app(
          SyntaxFileList(
            controller: files,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            selectionActionStyle: const SelectionActionStyle(
              tooltip: 'Discuss file range',
            ),
            onComment: (details) =>
                files.sessions.peek(details.file.id)!.setAnnotations([
                  LineAnnotation(
                    id: 'note',
                    start: details.selection.start,
                    end: details.selection.end,
                    data: 'saved',
                  ),
                ]),
            annotationBuilder: (_, note) =>
                Text('Custom annotation: ${note.data}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = files.sessions.peek('a')!;
      editor.selectLines(0, 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Discuss file range'));
      await tester.pumpAndSettle();
      expect(find.text('Custom annotation: saved'), findsOneWidget);
      files.toggle('a');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Discuss file range'), findsNothing);
      files.toggle('a');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Discuss file range'), findsOneWidget);
      expect(find.text('Custom annotation: saved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      files.dispose();
    },
  );
  testWidgets(
    'file drag shows a comment action without moving rows or losing its range',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(
          id: 'a',
          path: 'a.txt',
          text: 'one😀\r\ntwo\r\nthree\r\nfour',
          revision: 7,
        ),
      );
      FileSelectionDetails? result;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            onComment: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      final before = tester.getRect(row('one😀'));
      final gesture = await tester.startGesture(
        gutter(tester, 'three'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(gutter(tester, 'one😀'));
      await tester.pump();
      expect(
        comment,
        findsOneWidget,
      ); // Visible while dragging, as well as after release.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(row('one😀')), before);
      expect(tester.getRect(comment).top, before.top);
      expect(find.bySemanticsLabel(commentLabel), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.ancestor(of: comment, matching: find.byType(IconButton)),
      );
      final foreground = button.style!.foregroundColor!
          .resolve({})!
          .computeLuminance();
      final background = button.style!.backgroundColor!
          .resolve({})!
          .computeLuminance();
      final contrast = foreground > background
          ? (foreground + .05) / (background + .05)
          : (background + .05) / (foreground + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      final selected = editor.selections.single;
      await tester.tap(comment);
      await tester.pumpAndSettle();
      expect(editor.selections.single, selected);
      expect(result!.selection, selected);
      expect(result!.anchorLine, 2);
      expect(result!.activeLine, 0);
      expect(result!.startLine, 0);
      expect(result!.endLine, 2);
      expect(result!.selectedText, 'one😀\r\ntwo\r\nthree');
      expect(result!.file.revision, 7);
      editor.applyEdits([const OffsetEdit(0, 3, 'changed')]);
      expect(
        result!.selectedText,
        'one😀\r\ntwo\r\nthree',
      ); // Immutable snapshot.
      editor.setSelections([]);
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      editor.dispose();
    },
  );

  testWidgets(
    'empty line comments are explicit and do not turn idle carets into actions',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(id: 'a', path: 'a.txt', text: '\nnext'),
      );
      FileSelectionDetails? result;
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            onComment: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      final firstRow = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Line 1',
      );
      await tester.tapAt(tester.getTopLeft(firstRow) + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(comment, findsOneWidget);
      await tester.tap(comment);
      expect(result!.activeLine, 0);
      expect(result!.selectedText, '');
      editor.setSelections([]);
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );

  testWidgets(
    'comment shortcuts support both platforms, remapping and disabling',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(id: 'a', path: 'a.txt', text: 'one\ntwo'),
      );
      final highlighter = Highlighter();
      var calls = 0;
      Future<void> show(SelectionActionStyle style) async {
        await tester.pumpWidget(
          app(
            SyntaxFileView(
              controller: editor,
              highlighter: highlighter,
              theme: githubDarkTheme,
              onComment: (_) => calls++,
              selectionActionStyle: style,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(const SelectionActionStyle());
      await tester.tapAt(gutter(tester, 'one') + const Offset(24, 0));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.controlLeft);
      await shortcut(tester, LogicalKeyboardKey.metaLeft);
      expect(calls, 2);
      await show(
        const SelectionActionStyle(
          shortcuts: [SingleActivator(LogicalKeyboardKey.keyR, alt: true)],
        ),
      );
      await shortcut(tester, LogicalKeyboardKey.controlLeft);
      expect(calls, 2);
      await shortcut(
        tester,
        LogicalKeyboardKey.altLeft,
        key: LogicalKeyboardKey.keyR,
        shift: false,
      );
      expect(calls, 3);
      await show(const SelectionActionStyle(shortcuts: []));
      await shortcut(
        tester,
        LogicalKeyboardKey.altLeft,
        key: LogicalKeyboardKey.keyR,
        shift: false,
      );
      expect(calls, 3);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );

  testWidgets(
    'applications replace or hide actions and control their style and placement',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(id: 'a', path: 'a.txt', text: 'one\ntwo'),
      );
      editor.selectLines(0, 1);
      final highlighter = Highlighter();
      var called = false;
      FileSelectionDetails? details;
      const style = SelectionActionStyle(
        tooltip: 'Discuss range',
        icon: Icon(Icons.forum),
        alignment: Alignment.topRight,
        gutterWidth: 0,
        buttonStyle: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.purple),
        ),
      );
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
            selectionActionStyle: style,
            onComment: (_) => called = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byTooltip('Discuss range');
      expect(tester.getRect(action).right, tester.getRect(row('two')).right);
      expect(find.byIcon(Icons.forum), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.ancestor(of: action, matching: find.byType(IconButton)),
      );
      expect(button.style!.backgroundColor!.resolve({}), Colors.purple);
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
            onComment: (_) => called = true,
            selectionActionBuilder: (_, value) {
              details = value;
              return IconButton(
                tooltip: 'Custom range action',
                onPressed: () => called = true,
                icon: const Icon(Icons.flag),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      expect(details!.selectedText, 'one\ntwo');
      await tester.tap(find.byTooltip('Custom range action'));
      expect(called, isTrue);
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
            onComment: (_) {},
            selectionActionBuilder: (_, _) => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      expect(find.byTooltip('Custom range action'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );

  testWidgets(
    'split range action follows the active side without replacing the selection',
    (tester) async {
      final review = PatchController([
        diffTexts('one\nold\nthree', 'one\nnew\nthree', id: 'a', path: 'a.txt'),
      ], mode: DiffMode.split);
      DiffSelectionDetails? result;
      await tester.pumpWidget(
        app(
          PatchView.controlled(
            controller: review,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            onComment: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        gutter(tester, 'old'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(gutter(tester, 'new', right: true));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(review.selection!.crossesSides, isTrue);
      final rect = tester.getRect(row('new'));
      expect(tester.getRect(comment).left, closeTo(rect.center.dx, 1));
      final selected = review.selection;
      await tester.tap(comment);
      expect(identical(review.selection, selected), isTrue);
      expect(result!.selection.side, DiffSide.old);
      expect(result!.selection.activeSide, DiffSide.newer);
      expect(review.selectedText(), 'old\nnew');
      review.select(
        const DiffSelection(
          'a',
          DiffSide.newer,
          2,
          2,
          activeSide: DiffSide.old,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(comment).left, rect.left);
      await tester.tap(comment);
      expect(result!.selection.activeSide, DiffSide.old);
      review.toggleFile('a');
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      review.toggleFile('a');
      await tester.pumpAndSettle();
      expect(comment, findsOneWidget);
      review.setFiles([diffTexts('other', 'changed', id: 'a', path: 'a.txt')]);
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      await tester.pumpWidget(const SizedBox());
      review.dispose();
    },
  );

  testWidgets(
    'unified context shows old-side annotations and its selection action',
    (tester) async {
      final review = PatchController([
        diffTexts('one\nold\nthree', 'one\nnew\nthree', id: 'a', path: 'a.txt'),
      ]);
      review.select(const DiffSelection('a', DiffSide.old, 1, 3));
      review.setAnnotations([
        const ReviewAnnotation(
          id: 'note',
          fileId: 'a',
          side: DiffSide.old,
          line: 3,
          data: 'Old context note',
        ),
      ]);
      DiffSelectionDetails? result;
      await tester.pumpWidget(
        app(
          PatchView.controlled(
            controller: review,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            onComment: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old context note'), findsOneWidget);
      expect(comment, findsOneWidget);
      await tester.tap(comment);
      expect(result!.selection.activeSide, DiffSide.old);
      expect(result!.selection.active, 3);
      await tester.pumpWidget(const SizedBox());
      review.dispose();
    },
  );

  testWidgets(
    'empty split panes cannot select or comment on the other source',
    (tester) async {
      final review = PatchController([
        diffTexts('old\nextra', 'new', id: 'a', path: 'a.txt'),
      ], mode: DiffMode.split);
      await tester.pumpWidget(
        app(
          PatchView.controlled(
            controller: review,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            onComment: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(gutter(tester, 'extra', right: true));
      await tester.pumpAndSettle();
      expect(review.selection, isNull);
      expect(comment, findsNothing);
      await tester.tapAt(gutter(tester, 'extra'));
      await tester.pumpAndSettle();
      expect(review.selection!.activeSide, DiffSide.old);
      expect(comment, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      review.dispose();
    },
  );

  testWidgets(
    'standalone diff views offer comment actions and reset them with their source',
    (tester) async {
      DiffSelectionDetails? result;
      final highlighter = Highlighter();
      Future<void> show(String after) async {
        await tester.pumpWidget(
          app(
            PatchView.fromTexts(
              oldText: 'old',
              newText: after,
              path: 'a.txt',
              highlighter: highlighter,
              theme: githubDarkTheme,
              onComment: (value) => result = value,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show('new');
      await tester.tapAt(gutter(tester, 'old'));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.controlLeft);
      expect(result!.file.oldText, 'old');
      expect(result!.selection.activeSide, DiffSide.old);
      await tester.tap(comment);
      expect(result!.selection.active, 1);
      await show('replacement');
      expect(comment, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'selection actions stay attached to virtual source rows with annotations',
    (tester) async {
      final editor = EditorController(
        file: SourceFile(
          id: 'a',
          path: 'a.txt',
          text: List.generate(1000, (i) => 'row $i').join('\n'),
        ),
      );
      editor.selectLines(1, 2);
      editor.setAnnotations([
        const LineAnnotation(id: 'note', start: 12, end: 17, data: 'review'),
      ]);
      final scroll = ScrollController();
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            scrollController: scroll,
            onComment: (_) {},
            annotationBuilder: (_, _) =>
                const SizedBox(height: 100, child: Text('Review note')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(comment).top, tester.getRect(row('row 2')).top);
      scroll.jumpTo(10000);
      await tester.pumpAndSettle();
      expect(comment, findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(comment, findsOneWidget);
      expect(editor.selections.single.end, 17);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
      scroll.dispose();
    },
  );
}
