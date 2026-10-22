import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';
import 'package:syntax_flutter/src/line_selection.dart';

Finder row(String text) => find.ancestor(
  of: find.text(text, findRichText: true),
  matching: find.byType(LineSelectionTarget),
);
Offset gutter(WidgetTester tester, String text, {bool right = false}) {
  final rect = tester.getRect(row(text));
  return Offset(rect.left + (right ? rect.width / 2 : 0) + 8, rect.center.dy);
}

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));
Future<void> expectKeyboardCopy(WidgetTester tester, String expected) async {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    },
  );
  try {
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      copied = null;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(copied, expected);
    }
  } finally {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  }
}

void main() {
  testWidgets(
    'gutter drag selects complete lines upward and copies exact source',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(
          id: 'a',
          path: 'a.txt',
          text: 'one\r\ntwo\r\nthree\r\nfour',
        ),
      );
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        gutter(tester, 'three'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(gutter(tester, 'one'));
      await gesture.up();
      await tester.pumpAndSettle();
      final selection = editor.selections.single;
      expect(selection.anchor, greaterThan(selection.active));
      expect(
        editor.document.text.substring(selection.start, selection.end),
        'one\r\ntwo\r\nthree',
      );
      await expectKeyboardCopy(tester, 'one\r\ntwo\r\nthree');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(gutter(tester, 'four'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        editor.document.text.substring(
          editor.selections.single.start,
          editor.selections.single.end,
        ),
        'three\r\nfour',
      );
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );
  testWidgets(
    'patch drag crosses sides and selection survives layout changes',
    (tester) async {
      final review = PatchController([
        diffTexts('one\nold\nthree', 'one\nnew\nthree', path: 'a.txt', id: 'a'),
      ]);
      await tester.pumpWidget(
        app(
          PatchView.controlled(
            controller: review,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        gutter(tester, 'old'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(gutter(tester, 'new'));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(review.selection!.crossesSides, isTrue);
      expect(review.selectedText(), 'old\nnew');
      await expectKeyboardCopy(tester, 'old\nnew');
      review.mode = DiffMode.split;
      await tester.pumpAndSettle();
      expect(review.selectedText(), 'old\nnew');
      review.select(null);
      await tester.tapAt(gutter(tester, 'new', right: true));
      expect(review.selection!.side, DiffSide.newer);
      expect(review.selectedText(), 'new');
      await tester.pumpWidget(const SizedBox());
      review.dispose();
    },
  );
  testWidgets('gutter drag autoscrolls a virtual file and stops on release', (
    tester,
  ) async {
    final editor = EditorController(
      file: SourceFile(
        id: 'long',
        path: 'a.txt',
        text: List.generate(500, (i) => 'row $i').join('\n'),
      ),
    );
    final scroll = ScrollController();
    await tester.pumpWidget(
      app(
        SyntaxFileView(
          controller: editor,
          highlighter: Highlighter(),
          theme: githubDarkTheme,
          wrap: false,
          scrollController: scroll,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      gutter(tester, 'row 1'),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(8, tester.view.physicalSize.height - 4));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    expect(
      editor.document.positionAt(editor.selections.single.active).line,
      greaterThan(20),
    );
    await gesture.up();
    final stopped = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, stopped);
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
    scroll.dispose();
  });
  testWidgets(
    'section header folds, announces its action, and reveal reopens it',
    (tester) async {
      final source = diffTexts('old', 'new', path: 'a.txt', id: 'a');
      final h = source.hunks.single;
      final review = PatchController([
        source.copyWith(
          hunks: [
            DiffHunk(
              oldStart: h.oldStart,
              oldCount: h.oldCount,
              newStart: h.newStart,
              newCount: h.newCount,
              lines: h.lines,
              section: 'run()',
            ),
          ],
        ),
      ], foldableHunks: true);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          PatchView.controlled(
            controller: review,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Collapse section run()'), findsOneWidget);
      await tester.tap(find.text('run()'));
      await tester.pumpAndSettle();
      expect(find.text('new', findRichText: true), findsNothing);
      expect(find.bySemanticsLabel('Expand section run()'), findsOneWidget);
      await review.revealLine('a', 1);
      await tester.pumpAndSettle();
      expect(find.text('new', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      review.dispose();
    },
  );
}
