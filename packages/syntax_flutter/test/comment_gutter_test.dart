import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

ReviewThread discussion(String id, {bool resolved = false}) => ReviewThread(
  id: id,
  resolved: resolved,
  comments: [ReviewComment(id: id, author: 'Reviewer', body: '$id body')],
);

Finder marker([String label = 'Open discussion']) => find.byTooltip(label);

void main() {
  testWidgets('file collections scope indicators and open retained sessions', (
    tester,
  ) async {
    final files = FileListController([
      const SourceFile(id: 'first', path: 'first', text: 'one'),
      const SourceFile(id: 'second', path: 'second', text: 'two'),
    ]);
    final session = CommentThreadController(
      thread: discussion('note', resolved: true),
    );
    final editor = files.acquire('second');
    editor.setAnnotations([
      LineAnnotation(id: 'note', start: 0, end: 0, data: session.thread),
    ]);
    files.release('second');
    final nav = CommentNavigationController.files(files);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyntaxFileList(
            controller: files,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            commentNavigation: nav,
            fileHeight: 220,
            annotationBuilder: (_, a) =>
                SyntaxCommentThread(controller: session),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await nav.next();
    await tester.pumpAndSettle();
    expect(marker(), findsOneWidget);
    await tester.ensureVisible(marker());
    await tester.tap(marker());
    await tester.pumpAndSettle();
    expect(nav.current!.fileId, 'second');
    expect(session.isCollapsed, isFalse);
    expect(find.text('note body').hitTestable(), findsOneWidget);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'Review discussion');
    await tester.pumpWidget(const SizedBox());
    nav.dispose();
    files.dispose();
    session.dispose();
  });

  testWidgets('remounting an opened thread preserves manual collapse and focus', (
    tester,
  ) async {
    final session = CommentThreadController(
      thread: discussion('note', resolved: true),
    );
    final editor = EditorController(
      file: SourceFile(
        id: 'f',
        path: 'f',
        text: List.filled(500, 'line').join('\n'),
      ),
    );
    editor.setAnnotations([
      LineAnnotation(id: 'a', start: 0, end: 0, data: session.thread),
    ]);
    final nav = CommentNavigationController.file(editor),
        scroll = ScrollController();
    final otherFocus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: otherFocus),
              Expanded(
                child: SyntaxFileView(
                  controller: editor,
                  highlighter: Highlighter(),
                  theme: githubDarkTheme,
                  commentNavigation: nav,
                  scrollController: scroll,
                  annotationBuilder: (_, a) =>
                      SyntaxCommentThread(controller: session),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(marker());
    await tester.pumpAndSettle();
    expect(session.isCollapsed, isFalse);
    session.collapse();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SyntaxFileView), const Offset(0, -1300));
    await tester.pumpAndSettle();
    expect(marker(), findsNothing);
    otherFocus.requestFocus();
    await tester.pump();
    expect(otherFocus.hasFocus, isTrue, reason: 'before remount');
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(marker(), findsOneWidget);
    expect(session.isCollapsed, isTrue);
    expect(
      otherFocus.hasFocus,
      isTrue,
      reason:
          'focus after remount: ${FocusManager.instance.primaryFocus?.debugLabel}, open request ${nav.revealRequest}',
    );
    await tester.pumpWidget(const SizedBox());
    nav.dispose();
    editor.dispose();
    session.dispose();
    otherFocus.dispose();
    scroll.dispose();
  });

  testWidgets(
    'gutter click expands and focuses without selecting or reopening',
    (tester) async {
      final session = CommentThreadController(
        thread: discussion('thread', resolved: true),
      );
      final editor = EditorController(
        file: const SourceFile(id: 'f', path: 'f', text: 'one\ntwo\nthree'),
      );
      editor.setAnnotations([
        LineAnnotation(id: 'a', start: 0, end: 7, data: session.thread),
      ]);
      editor.selectLines(2, 2);
      final selected = editor.selections.single;
      final nav = CommentNavigationController.file(
        editor,
        annotationLine: (a) => editor.document.positionAt(a.end).line,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyntaxFileView(
              controller: editor,
              highlighter: Highlighter(),
              theme: githubDarkTheme,
              commentNavigation: nav,
              annotationLineBuilder: (a) =>
                  editor.document.positionAt(a.end).line,
              annotationBuilder: (_, a) =>
                  SyntaxCommentThread(controller: session),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(marker(), findsOneWidget);
      expect(find.text('thread body'), findsNothing);
      await tester.tap(marker());
      await tester.pumpAndSettle();
      expect(editor.selections.single, same(selected));
      expect(nav.current!.annotationId, 'a');
      expect(session.isCollapsed, isFalse);
      expect(session.thread.resolved, isTrue);
      expect(session.isReplying, isFalse);
      expect(find.text('thread body').hitTestable(), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'Review discussion',
      );
      session.collapse();
      await tester.pumpAndSettle();
      expect(session.isCollapsed, isTrue);
      // Keyboard activation repeats the explicit open request.
      await tester.tap(marker());
      await tester.pumpAndSettle();
      expect(session.isCollapsed, isFalse);
      await tester.pumpWidget(const SizedBox());
      nav.dispose();
      editor.dispose();
      session.dispose();
    },
  );

  for (final mode in DiffMode.values) {
    testWidgets(
      '$mode markers distinguish sides and cycle colocated discussions',
      (tester) async {
        final patch = PatchController([
          diffTexts('same\nold', 'same\nnew\nadded', id: 'f', path: 'f'),
        ], mode: mode);
        final sessions = {
          for (final id in ['old', 'first', 'second', 'context'])
            id: CommentThreadController(thread: discussion(id, resolved: true)),
        };
        patch.setAnnotations([
          for (final id in ['old', 'first', 'second'])
            ReviewAnnotation(
              id: id,
              fileId: 'f',
              side: id == 'old' ? DiffSide.old : DiffSide.newer,
              line: 2,
              data: sessions[id]!.thread,
            ),
          ReviewAnnotation(
            id: 'context',
            fileId: 'f',
            side: DiffSide.old,
            line: 1,
            data: sessions['context']!.thread,
          ),
        ]);
        patch.select(const DiffSelection('f', DiffSide.old, 2, 2));
        final selected = patch.selection, copied = patch.selectedText();
        final nav = CommentNavigationController.patch(patch);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SyntaxCommentGutterTheme(
                labelBuilder: (details) =>
                    details.threads.map((t) => t.annotationId).join(','),
                child: PatchView.controlled(
                  controller: patch,
                  highlighter: Highlighter(),
                  theme: githubDarkTheme,
                  commentNavigation: nav,
                  padding: EdgeInsets.zero,
                  annotationBuilder: (_, a) =>
                      SyntaxCommentThread(controller: sessions[a.id]!),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(marker('context'), findsOneWidget);
        expect(marker('old'), findsOneWidget);
        expect(marker('first,second'), findsOneWidget);
        final oldRect = tester.getRect(marker('old')),
            newRect = tester.getRect(marker('first,second'));
        expect(oldRect.height, greaterThan(0));
        expect(
          newRect.left,
          mode == DiffMode.split ? greaterThan(390) : lessThan(30),
        );
        await tester.tap(marker('first,second'));
        await tester.pumpAndSettle();
        expect(nav.current!.annotationId, 'first');
        expect(sessions['first']!.isCollapsed, isFalse);
        // Revealing the expanded card can scroll its marker offscreen.
        await tester.ensureVisible(marker('first,second'));
        await tester.tap(marker('first,second'));
        await tester.pumpAndSettle();
        expect(nav.current!.annotationId, 'second');
        expect(sessions['second']!.isCollapsed, isFalse);
        expect(sessions['old']!.isCollapsed, isTrue);
        expect(patch.selection, same(selected));
        expect(patch.selectedText(), copied);
        nav.filter = CommentThreadFilter.unresolved;
        await tester.pumpAndSettle();
        expect(marker('first,second'), findsNothing);
        expect(marker('old'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        nav.dispose();
        patch.dispose();
        for (final s in sessions.values) {
          s.dispose();
        }
      },
    );
  }

  testWidgets(
    'custom icons colors labels and actions are public and keyboard accessible',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(id: 'f', path: 'f', text: 'one'),
      );
      editor.setAnnotations([
        LineAnnotation(id: 'a', start: 0, end: 0, data: discussion('a')),
      ]);
      final nav = CommentNavigationController.file(editor);
      CommentGutterDetails? captured;
      var calls = 0, enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return SyntaxCommentGutterTheme(
                  enabled: enabled,
                  style: const CommentGutterStyle(
                    icon: Icons.message,
                    color: Colors.orange,
                    width: 32,
                  ),
                  labelBuilder: (_) => 'Inspect note',
                  onActivate: (details) {
                    calls++;
                    captured = details;
                  },
                  builder: (_, details, child) => DecoratedBox(
                    decoration: const BoxDecoration(),
                    child: child,
                  ),
                  child: SyntaxFileView(
                    controller: editor,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    commentNavigation: nav,
                    showLineNumbers: false,
                    annotationBuilder: (_, a) => const Text('Custom card'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.message), findsOneWidget);
      final button = find.widgetWithIcon(IconButton, Icons.message);
      expect(
        tester.widget<IconButton>(button).style!.foregroundColor!.resolve({}),
        Colors.orange,
      );
      await tester.tap(marker('Inspect note'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(nav.current, isNull);
      Focus.of(tester.element(find.byIcon(Icons.message))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 2);
      await captured!.open();
      await tester.pumpAndSettle();
      expect(nav.current!.annotationId, 'a');
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'Review discussion',
      );
      editor.applyEdits([const OffsetEdit(0, 0, 'new\n')]);
      expect(await captured!.open(), isFalse);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(marker('Inspect note'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      nav.dispose();
      editor.dispose();
    },
  );
}
