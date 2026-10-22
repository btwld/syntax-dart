import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

ReviewThread discussion(String id) => ReviewThread(
  id: id,
  comments: [ReviewComment(id: id, author: 'Reviewer', body: id)],
);

void main() {
  testWidgets(
    'file source overlays follow navigation and preserve source input',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(
          id: 'f',
          path: 'f.txt',
          text: 'one\ntwo\nthree\nfour',
        ),
      );
      editor.setAnnotations([
        LineAnnotation(id: 'a', start: 0, end: 8, data: discussion('a')),
        LineAnnotation(id: 'b', start: 14, end: 18, data: discussion('b')),
      ]);
      final nav = CommentNavigationController.file(editor);
      final painted = <int, CommentSourceHighlightDetails>{};
      var enabled = true;
      var overlayTaps = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return SyntaxCommentHighlightTheme(
                  sourceEnabled: enabled,
                  sourceBuilder: (_, details) {
                    painted[details.line] = details;
                    return GestureDetector(
                      key: ValueKey('source-${details.line}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => overlayTaps++,
                      child: const Text('Overlay label'),
                    );
                  },
                  child: SyntaxFileView(
                    controller: editor,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    commentNavigation: nav,
                    annotationBuilder: (_, a) => SizedBox(
                      key: ValueKey(a.id),
                      height: 60,
                      child: Text('Thread ${a.id}'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final source = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Line 1',
      );
      final before = tester.getRect(source);
      nav.select('f', 'a');
      await tester.pumpAndSettle();
      expect(painted.keys, unorderedEquals([0, 1]));
      expect(painted[0]!.isFirst, isTrue);
      expect(painted[0]!.isLast, isFalse);
      expect(painted[1]!.isLast, isTrue);
      expect(painted[1]!.side, isNull);
      expect(tester.getRect(source), before);
      final overlay = find.byKey(const ValueKey('source-0'));
      expect(tester.getRect(overlay), before);
      expect(
        tester
            .getRect(overlay)
            .overlaps(tester.getRect(find.byKey(const ValueKey('a')))),
        isFalse,
      );
      await tester.tapAt(tester.getTopLeft(source) + const Offset(10, 8));
      await tester.pumpAndSettle();
      expect(overlayTaps, 0);
      expect(editor.selections, isNotEmpty);
      final selection = editor.selections.single;
      painted.clear();
      await nav.next();
      await tester.pumpAndSettle();
      expect(nav.current!.annotationId, 'b');
      expect(find.byKey(const ValueKey('source-0')), findsNothing);
      expect(find.byKey(const ValueKey('source-3')), findsOneWidget);
      expect(painted[3]!.isFirst && painted[3]!.isLast, isTrue);
      expect(editor.selections.single, same(selection));
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-3')), findsNothing);
      expect(nav.current!.annotationId, 'b');
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox());
      nav.dispose();
      editor.dispose();
    },
  );

  testWidgets(
    'default source styling can hide markers and preserves row geometry',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(id: 'f', path: 'f', text: 'one\ntwo'),
      );
      editor.setAnnotations([
        LineAnnotation(id: 'a', start: 0, end: 7, data: discussion('a')),
      ]);
      final nav = CommentNavigationController.file(editor)..select('f', 'a');
      const tint = Color(0x2246b8d9);
      await tester.pumpWidget(
        MaterialApp(
          home: SyntaxCommentHighlightTheme(
            sourceStyle: const CommentSourceHighlightStyle(
              backgroundColor: tint,
              markerWidth: 0,
            ),
            child: SyntaxFileView(
              controller: editor,
              highlighter: Highlighter(),
              theme: githubDarkTheme,
              commentNavigation: nav,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final overlays = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == tint,
      );
      expect(overlays, findsNWidgets(2));
      for (final widget in tester.widgetList<DecoratedBox>(overlays)) {
        expect(
          ((widget.decoration as BoxDecoration).border! as Border).left,
          BorderSide.none,
        );
      }
      nav.filter = CommentThreadFilter.resolved;
      await tester.pumpAndSettle();
      expect(overlays, findsNothing);
      await tester.pumpWidget(const SizedBox());
      nav.dispose();
      editor.dispose();
    },
  );

  for (final mode in DiffMode.values) {
    testWidgets('$mode overlays preserve cross-side ranges and empty panes', (
      tester,
    ) async {
      final patch = PatchController([
        diffTexts('a\nb\nc\nd', 'a\nx\ny\nz\nd', id: 'f', path: 'f.txt'),
      ], mode: mode);
      const range = DiffSelection(
        'f',
        DiffSide.newer,
        4,
        2,
        activeSide: DiffSide.old,
      );
      patch.setAnnotations([
        ReviewAnnotation(
          id: 'a',
          fileId: 'f',
          side: DiffSide.newer,
          line: 4,
          sourceSelection: range,
          data: discussion('a'),
        ),
        ReviewAnnotation(
          id: 'context',
          fileId: 'f',
          side: DiffSide.old,
          line: 4,
          data: discussion('context'),
        ),
      ]);
      patch.select(const DiffSelection('f', DiffSide.old, 1, 1));
      final copy = patch.selectedText();
      final nav = CommentNavigationController.patch(patch)..select('f', 'a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyntaxCommentHighlightTheme(
              sourceBuilder: (_, details) => ColoredBox(
                key: ValueKey('${details.side!.name}-${details.line}'),
                color: Colors.amber.withValues(alpha: .1),
              ),
              child: PatchView.controlled(
                controller: patch,
                padding: EdgeInsets.zero,
                highlighter: Highlighter(),
                theme: githubDarkTheme,
                commentNavigation: nav,
                showReviewActions: false,
                annotationBuilder: (_, a) =>
                    SizedBox(height: 40, child: Text(a.id)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final (side, line) in [
        (DiffSide.old, 1),
        (DiffSide.old, 2),
        (DiffSide.newer, 1),
        (DiffSide.newer, 2),
        (DiffSide.newer, 3),
      ]) {
        final overlay = find.byKey(ValueKey('${side.name}-$line'));
        expect(overlay, findsOneWidget);
        final rect = tester.getRect(overlay);
        expect(rect.height, greaterThan(0));
        expect(rect.width, mode == DiffMode.split ? 400 : 800);
        expect(
          rect.left,
          mode == DiffMode.split && side == DiffSide.newer ? 400 : 0,
        );
      }
      expect(find.byKey(const ValueKey('old-3')), findsNothing);
      expect(patch.selectedText(), copy);
      await nav.next();
      await tester.pumpAndSettle();
      // The unified context row has both identities; old-side discussions still match.
      expect(find.byKey(const ValueKey('old-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('newer-4')), findsNothing);
      expect(find.byKey(const ValueKey('newer-3')), findsNothing);
      patch.setAnnotations([]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('old-3')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      nav.dispose();
      patch.dispose();
    });
  }

  testWidgets('large source ranges only build overlays for mounted rows', (
    tester,
  ) async {
    final editor = EditorController(
      file: SourceFile(
        id: 'f',
        path: 'f.txt',
        text: List.generate(10000, (i) => 'line $i').join('\n'),
      ),
    );
    editor.setAnnotations([
      LineAnnotation(
        id: 'all',
        start: 0,
        end: editor.document.length,
        data: discussion('all'),
      ),
    ]);
    final nav = CommentNavigationController.file(
      editor,
      annotationLine: (a) => editor.document.positionAt(a.end).line,
    );
    final built = <int>{};
    nav.select('f', 'all');
    await tester.pumpWidget(
      MaterialApp(
        home: SyntaxCommentHighlightTheme(
          sourceBuilder: (_, details) {
            built.add(details.line);
            return const ColoredBox(color: Color(0x22ffffff));
          },
          child: SyntaxFileView(
            controller: editor,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            commentNavigation: nav,
            annotationLineBuilder: (a) =>
                editor.document.positionAt(a.end).line,
            annotationBuilder: (_, a) => const Text('Last thread'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built.length, lessThan(100));
    built.clear();
    await nav.next();
    await tester.pumpAndSettle();
    expect(built, contains(9999));
    expect(built.length, lessThan(100));
    expect(find.text('Last thread').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    nav.dispose();
    editor.dispose();
  });
}
