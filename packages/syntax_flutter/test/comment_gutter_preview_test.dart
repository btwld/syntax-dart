import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

ReviewThread discussion(String id, {bool resolved = false}) => ReviewThread(
  id: id,
  resolved: resolved,
  comments: [
    ReviewComment(id: id, author: 'Reviewer $id', body: '$id opening message'),
    ReviewComment(
      id: '$id-reply',
      author: 'Author $id',
      body: '$id latest reply',
    ),
  ],
);

Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  return mouse;
}

class Fixture {
  Fixture({bool resolved = false, String? text}) {
    editor = EditorController(
      file: SourceFile(id: 'f', path: 'f', text: text ?? 'one\ntwo\nthree'),
    );
    session = CommentThreadController(
      thread: discussion('a', resolved: resolved),
    );
    publish(session.thread);
    nav = CommentNavigationController.file(editor);
  }
  late EditorController editor;
  late CommentThreadController session;
  late CommentNavigationController nav;
  void publish(ReviewThread thread) => editor.setAnnotations([
    LineAnnotation(id: 'a', start: 0, end: 0, data: thread),
  ]);
  Widget view({
    ScrollController? scroll,
    bool threadWidget = false,
    bool showHeader = true,
  }) => SyntaxFileView(
    controller: editor,
    highlighter: Highlighter(),
    theme: githubDarkTheme,
    commentNavigation: nav,
    scrollController: scroll,
    showHeader: showHeader,
    annotationBuilder: (_, a) => threadWidget
        ? SyntaxCommentThread(controller: session)
        : const Text('Inline discussion'),
  );
  void dispose() {
    nav.dispose();
    editor.dispose();
    session.dispose();
  }
}

void main() {
  testWidgets(
    'hover is delayed, stays interactive, and opens without changing resolution or selection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final f = Fixture(resolved: true);
      f.editor.selectLines(2, 2);
      final selected = f.editor.selections.single;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: f.view(threadWidget: true))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Open discussion'))
            .getSemanticsData()
            .label,
        'Open discussion',
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Open discussion'))
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.down(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discussion preview'), findsNothing);
      await mouse.up();
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
      await tester.pump(const Duration(milliseconds: 349));
      expect(find.text('Discussion preview'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('a opening message'), findsOneWidget);
      expect(find.text('a latest reply'), findsOneWidget);
      expect(find.text('Resolved · 1 reply'), findsOneWidget);
      expect(f.nav.current, isNull);
      expect(f.session.isCollapsed, isTrue);
      expect(f.editor.selections.single, same(selected));
      await mouse.moveTo(
        tester.getTopRight(find.byTooltip('Open discussion')) +
            const Offset(4, 0),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(tester.getCenter(find.text('Open thread')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Discussion preview'), findsOneWidget);
      await tester.tap(find.text('Open thread'));
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      expect(f.session.isCollapsed, isFalse);
      expect(f.session.thread.resolved, isTrue);
      expect(f.nav.current!.annotationId, 'a');
      expect(f.editor.selections.single, same(selected));
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'Review discussion',
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      semantics.dispose();
    },
  );

  testWidgets(
    'custom previews update live and expose guarded open and close actions',
    (tester) async {
      final f = Fixture();
      CommentGutterPreviewDetails? captured;
      var actions = 0, enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return SyntaxCommentGutterTheme(
                  previewEnabled: enabled,
                  previewStyle: const CommentGutterPreviewStyle(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    width: 310,
                  ),
                  previewBuilder: (_, details, child) {
                    captured = details;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Custom preview'),
                        Flexible(child: child),
                      ],
                    );
                  },
                  previewActionsBuilder: (_, details, target, child) =>
                      TextButton(
                        onPressed: () {
                          actions++;
                          details.close();
                        },
                        child: Text('Act on ${target.thread.id}'),
                      ),
                  child: f.view(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await hover(tester, find.byTooltip('Open discussion'));
      expect(find.text('Custom preview'), findsOneWidget);
      expect(find.text('Open thread'), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is Material && w.color == Colors.amber),
        findsOneWidget,
      );
      f.publish(
        f.session.thread.copyWith(
          comments: [
            const ReviewComment(
              id: 'a',
              author: 'Updated',
              body: 'Edited comment',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edited comment'), findsOneWidget);
      expect(find.text('a opening message'), findsNothing);
      final snapshot = captured!;
      await tester.tap(find.text('Act on a'));
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(find.text('Custom preview'), findsNothing);
      expect(f.nav.current, isNull);
      f.editor.applyEdits([const OffsetEdit(0, 0, 'new\n')]);
      await tester.pumpAndSettle();
      expect(await snapshot.open(), isFalse);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Custom preview'), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'F2 and Escape support keyboard preview; outside click retains input focus',
    (tester) async {
      final f = Fixture(), inputFocus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: inputFocus),
                Expanded(child: f.view()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final focus = Focus.of(
        tester.element(
          find.descendant(
            of: find.byTooltip('Open discussion'),
            matching: find.byIcon(Icons.chat_bubble_outline),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'Discussion preview',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('Discussion preview'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      expect(focus.hasFocus, isTrue);
      final mouse = await hover(tester, find.byTooltip('Open discussion'));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      expect(inputFocus.hasFocus, isTrue);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      inputFocus.dispose();
    },
  );

  testWidgets(
    'filtering, source edits, scrolling and disposal dismiss stale previews',
    (tester) async {
      final f = Fixture(
        resolved: true,
        text: List.filled(500, 'line').join('\n'),
      );
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: f.view(scroll: scroll)),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await hover(tester, find.byTooltip('Open discussion'));
      expect(find.text('Discussion preview'), findsOneWidget);
      f.nav.filter = CommentThreadFilter.unresolved;
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      f.nav.filter = CommentThreadFilter.all;
      await tester.pumpAndSettle();
      Future<void> again() async {
        await mouse.moveTo(Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.text('Discussion preview'), findsOneWidget);
      }

      await again();
      f.editor.applyEdits([const OffsetEdit(2, 2, 'changed')]);
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      await again();
      scroll.jumpTo(20);
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      scroll.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    },
  );

  for (final mode in DiffMode.values) {
    testWidgets(
      '$mode previews distinguish sides and choose colocated threads',
      (tester) async {
        final patch = PatchController([
          diffTexts('old', 'new', id: 'f', path: 'f'),
        ], mode: mode);
        patch.setAnnotations([
          for (final id in ['old', 'first', 'second'])
            ReviewAnnotation(
              id: id,
              fileId: 'f',
              side: id == 'old' ? DiffSide.old : DiffSide.newer,
              line: 1,
              data: discussion(id),
            ),
        ]);
        final nav = CommentNavigationController.patch(patch);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SyntaxCommentGutterTheme(
                labelBuilder: (d) =>
                    d.threads.map((t) => t.annotationId).join(','),
                child: PatchView.controlled(
                  controller: patch,
                  highlighter: Highlighter(),
                  theme: githubDarkTheme,
                  commentNavigation: nav,
                  annotationBuilder: (_, a) => Text('Inline ${a.id}'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mouse = await hover(tester, find.byTooltip('first,second'));
        expect(find.text('2 discussions'), findsOneWidget);
        expect(find.text('first opening message'), findsOneWidget);
        expect(find.text('old opening message'), findsNothing);
        final list = find
            .ancestor(
              of: find.text('first opening message'),
              matching: find.byType(Scrollable),
            )
            .first;
        await mouse.moveTo(
          tester.getCenter(find.text('first opening message')),
        );
        await tester.drag(list, const Offset(0, -250));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open thread').hitTestable().last);
        await tester.pumpAndSettle();
        expect(nav.current!.annotationId, 'second');
        expect(nav.current!.side, DiffSide.newer);
        expect(find.text('2 discussions'), findsNothing);
        expect(patch.selection, isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        nav.dispose();
        patch.dispose();
      },
    );
  }

  testWidgets(
    'preview fits compact viewport; null builders preserve marker actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 280));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = Fixture();
      var suppress = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return Padding(
                  padding: const EdgeInsets.only(top: 100, left: 190),
                  child: SyntaxCommentGutterTheme(
                    previewBuilder: (_, _, child) => suppress ? null : child,
                    child: f.view(showHeader: false),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await hover(tester, find.byTooltip('Open discussion'));
      final surface = find
          .ancestor(
            of: find.text('Discussion preview'),
            matching: find.byType(Material),
          )
          .first;
      final rect = tester.getRect(surface);
      expect(rect.left, greaterThanOrEqualTo(8));
      expect(rect.right, lessThanOrEqualTo(352));
      expect(rect.top, greaterThanOrEqualTo(8));
      expect(rect.bottom, lessThanOrEqualTo(272));
      await mouse.moveTo(const Offset(0, 279));
      await tester.pump(const Duration(milliseconds: 201));
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      update(() => suppress = true);
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      await tester.tap(find.byTooltip('Open discussion'));
      await tester.pumpAndSettle();
      expect(f.nav.current!.annotationId, 'a');
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}
