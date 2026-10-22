import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

ReviewThread note(String id, {bool resolved = false}) => ReviewThread(
  id: id,
  resolved: resolved,
  comments: [ReviewComment(id: id, author: 'Reviewer', body: id)],
);

void main() {
  testWidgets(
    'file header counts stay live while filters preserve annotations and drafts',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(
          id: 'file',
          path: 'file.txt',
          text: 'one\ntwo\nthree',
        ),
      );
      final open = CommentThreadController(
        thread: note('open'),
        onUpdate: (change) => change.thread.copyWith(resolved: change.resolved),
      );
      final resolved = CommentThreadController(
        thread: note('done', resolved: true),
      );
      void sync() => editor.setAnnotations([
        LineAnnotation(id: 'open', start: 0, end: 2, data: open.thread),
        LineAnnotation(id: 'done', start: 4, end: 6, data: resolved.thread),
        const LineAnnotation(id: 'info', start: 8, end: 10, data: 'diagnostic'),
      ]);
      sync();
      open.addListener(sync);
      final navigation = CommentNavigationController.file(editor);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SyntaxCommentNavigation(controller: navigation),
                Expanded(
                  child: SyntaxFileView(
                    controller: editor,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    commentNavigation: navigation,
                    annotationBuilder: (_, a) => a.data is ReviewThread
                        ? SyntaxCommentThread(
                            controller: a.id == 'open' ? open : resolved,
                          )
                        : Text('${a.data}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 unresolved'), findsNWidgets(2));
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsaved reply');
      navigation.filter = CommentThreadFilter.resolved;
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('diagnostic'), findsOneWidget);
      expect(editor.annotations.length, 3);
      expect(find.text('1 unresolved'), findsNWidgets(2));
      navigation.filter = CommentThreadFilter.unresolved;
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Unsaved reply'), findsOneWidget);
      expect(find.text('Expand discussion'), findsNothing);
      await open.toggleResolved();
      await tester.pumpAndSettle();
      expect(find.byType(SyntaxCommentThread), findsNothing);
      expect(find.text('0 unresolved'), findsNWidgets(2));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_downward),
            )
            .onPressed,
        isNull,
      );
      navigation.filter = CommentThreadFilter.all;
      await tester.pumpAndSettle();
      expect(find.text('Resolved'), findsNWidgets(2));
      expect(open.replyInput.text, 'Unsaved reply');
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
      editor.dispose();
      open.dispose();
      resolved.dispose();
    },
  );

  testWidgets(
    'diff navigation unfolds distant files and reveals individual threads sharing a line',
    (tester) async {
      final patch = PatchController([
        diffTexts('one', 'changed', id: 'a', path: 'a.txt'),
        diffTexts('two', 'updated', id: 'b', path: 'b.txt'),
      ]);
      patch.setAnnotations([
        ReviewAnnotation(
          id: 'first',
          fileId: 'a',
          side: DiffSide.newer,
          line: 1,
          data: note('first'),
        ),
        ReviewAnnotation(
          id: 'second',
          fileId: 'a',
          side: DiffSide.newer,
          line: 1,
          data: note('second'),
        ),
        ReviewAnnotation(
          id: 'third',
          fileId: 'b',
          side: DiffSide.newer,
          line: 1,
          data: note('third', resolved: true),
        ),
      ]);
      patch.toggleFile('b');
      final navigation = CommentNavigationController.patch(patch);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SyntaxCommentNavigation(controller: navigation),
                Expanded(
                  child: PatchView.controlled(
                    controller: patch,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    commentNavigation: navigation,
                    annotationBuilder: (_, a) => SizedBox(
                      height: a.id == 'first' ? 700 : 70,
                      child: Center(child: Text('Thread ${a.id}')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_downward));
      await tester.pumpAndSettle();
      expect(navigation.current?.annotationId, 'first');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_downward));
      await tester.pumpAndSettle();
      expect(find.text('Thread second').hitTestable(), findsOneWidget);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_downward));
      await tester.pumpAndSettle();
      expect(patch.isCollapsed('b'), isFalse);
      expect(find.text('Thread third').hitTestable(), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      navigation.filter = CommentThreadFilter.unresolved;
      await tester.pumpAndSettle();
      expect(find.text('Thread third'), findsNothing);
      expect(navigation.count(resolved: false), 2);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
      await tester.pumpAndSettle();
      expect(find.text('Thread second').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
      patch.dispose();
    },
  );

  testWidgets(
    'file collection headers count retained comments and navigation reveals folded previews',
    (tester) async {
      final files = FileListController([
        const SourceFile(id: 'a', path: 'a.txt', text: 'one'),
        const SourceFile(id: 'b', path: 'b.txt', text: 'two'),
      ]);
      final session = files.acquire('b');
      session.setAnnotations([
        LineAnnotation(id: 'note', start: 0, end: 2, data: note('note')),
      ]);
      files.release('b');
      files.toggle('b');
      final navigation = CommentNavigationController.files(files);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SyntaxCommentNavigation(controller: navigation),
                Expanded(
                  child: SyntaxFileList(
                    controller: files,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    commentNavigation: navigation,
                    fileHeight: 180,
                    commentCountBuilder: (_, details) =>
                        Text('${details.unresolved} to review'),
                    annotationBuilder: (_, a) =>
                        Text((a.data! as ReviewThread).comments.first.body),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 to review'), findsOneWidget);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_downward));
      await tester.pumpAndSettle();
      expect(files.isCollapsed('b'), isFalse);
      expect(find.text('note').hitTestable(), findsOneWidget);
      session.setAnnotations([]);
      await tester.pumpAndSettle();
      expect(find.text('1 to review'), findsNothing);
      expect(navigation.count(), 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
      files.dispose();
    },
  );

  testWidgets(
    'custom controls receive live counts, navigation and filter commands',
    (tester) async {
      var visits = 0;
      final navigation = CommentNavigationController(
        onReveal: (_) {
          visits++;
          return true;
        },
        threads: [
          CommentThreadLocation(
            fileId: 'file',
            annotationId: 'a',
            thread: note('a'),
            line: 0,
          ),
          CommentThreadLocation(
            fileId: 'file',
            annotationId: 'b',
            thread: note('b', resolved: true),
            line: 1,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyntaxCommentNavigation(
              controller: navigation,
              builder: (_, details, child) =>
                  Column(children: [Text('Review ${details.total}'), child]),
              countBuilder: (_, details) =>
                  Text('${details.unresolved} remaining'),
              actionsBuilder: (_, details) => Wrap(
                children: [
                  TextButton(
                    onPressed: details.next,
                    child: const Text('Jump'),
                  ),
                  TextButton(
                    onPressed: () =>
                        details.setFilter(CommentThreadFilter.resolved),
                    child: const Text('Completed'),
                  ),
                  Text('${details.position} of ${details.visible.length}'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jump'));
      await tester.pumpAndSettle();
      expect(visits, 1);
      expect(navigation.current?.annotationId, 'b');
      expect(find.text('1 remaining'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.text('Review 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'default filter controls and counts fit a compact ${dark ? 'dark' : 'light'} view',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        final navigation = CommentNavigationController(
          onReveal: (_) => false,
          threads: [
            CommentThreadLocation(
              fileId: 'file',
              annotationId: 'a',
              thread: note('a'),
              line: 0,
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(
              body: SyntaxCommentNavigation(controller: navigation),
            ),
          ),
        );
        final filter = find.byType(PopupMenuButton<CommentThreadFilter>);
        expect(tester.getSemantics(filter).flagsCollection.isButton, isTrue);
        Focus.of(tester.element(find.text('All threads'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            CheckedPopupMenuItem<CommentThreadFilter>,
            'Resolved only',
          ),
        );
        await tester.pumpAndSettle();
        expect(navigation.filter, CommentThreadFilter.resolved);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.arrow_upward),
              )
              .onPressed,
          isNull,
        );
        navigation.filter = CommentThreadFilter.all;
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_downward));
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not reveal'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        navigation.dispose();
        semantics.dispose();
      },
    );
  }
}
