import 'dart:ui' show SemanticsFlag;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

ReviewThread discussion(String id) => ReviewThread(
  id: id,
  comments: [ReviewComment(id: id, author: 'Reviewer', body: id)],
);

Finder outline(Color color) => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).border ==
          Border.all(color: color, width: 3),
);

void main() {
  testWidgets(
    'custom painting follows one identity without resizing or blocking input',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(
          id: 'file',
          path: 'file.txt',
          text: 'one\ntwo\nthree',
        ),
      );
      editor.setAnnotations([
        for (final id in ['a', 'b'])
          LineAnnotation(id: id, start: 0, end: 0, data: discussion(id)),
      ]);
      final navigation = CommentNavigationController.file(editor);
      final input = TextEditingController();
      final focus = FocusNode();
      var enabled = true;
      late StateSetter update;
      const color = Colors.orange;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SyntaxCommentHighlightTheme(
                  enabled: enabled,
                  style: const CommentThreadHighlightStyle(
                    borderColor: color,
                    backgroundColor: Color(0x22ff8800),
                    borderWidth: 3,
                    inset: EdgeInsets.zero,
                  ),
                  child: SyntaxFileView(
                    controller: editor,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    commentNavigation: navigation,
                    annotationBuilder: (_, a) => SizedBox(
                      key: ValueKey(a.id),
                      height: 80,
                      child: a.id == 'a'
                          ? TextField(controller: input, focusNode: focus)
                          : const Text('Second discussion'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byKey(const ValueKey('a')));
      await navigation.next();
      await tester.pumpAndSettle();
      expect(outline(color), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('a'))), before);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Draft');
      expect(focus.hasFocus, isTrue);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(outline(color), findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(input.text, 'Draft');
      update(() => enabled = true);
      await tester.pumpAndSettle();
      await navigation.next();
      await tester.pumpAndSettle();
      expect(navigation.current?.annotationId, 'b');
      expect(outline(color), findsOneWidget);
      expect(
        tester.getRect(outline(color)),
        tester.getRect(find.byKey(const ValueKey('b'))),
      );
      navigation.filter = CommentThreadFilter.resolved;
      await tester.pumpAndSettle();
      expect(outline(color), findsNothing);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
      editor.dispose();
      input.dispose();
      focus.dispose();
    },
  );

  testWidgets(
    'whole highlight builder receives identities and selected semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final editor = EditorController(
        file: const SourceFile(id: 'file', path: 'file.txt', text: 'one'),
      );
      editor.setAnnotations([
        LineAnnotation(id: 'note', start: 0, end: 0, data: discussion('note')),
      ]);
      final navigation = CommentNavigationController.file(editor);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyntaxCommentHighlightTheme(
              builder: (_, details, child) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${details.fileId}/${details.annotationId}: ${details.isActive}',
                  ),
                  child,
                ],
              ),
              child: SyntaxFileView(
                controller: editor,
                highlighter: Highlighter(),
                theme: githubDarkTheme,
                commentNavigation: navigation,
                annotationBuilder: (_, a) => const Text('Discussion content'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('file/note: false'), findsOneWidget);
      await navigation.next();
      await tester.pumpAndSettle();
      expect(find.text('file/note: true'), findsOneWidget);
      final selected = find.ancestor(
        of: find.text('Discussion content'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
      );
      expect(selected, findsOneWidget);
      expect(
        // Supported by the minimum Flutter SDK.
        // ignore: deprecated_member_use
        tester.getSemantics(selected).hasFlag(SemanticsFlag.isSelected),
        isTrue,
      );
      expect(find.text('Discussion content'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
      editor.dispose();
      semantics.dispose();
    },
  );

  testWidgets('shared navigation reveals each viewport independently', (
    tester,
  ) async {
    final editor = EditorController(
      file: SourceFile(
        id: 'file',
        path: 'file.txt',
        text: List.filled(50, 'line').join('\n'),
      ),
    );
    editor.setAnnotations([
      for (final id in ['a', 'b'])
        LineAnnotation(id: id, start: 50, end: 50, data: discussion(id)),
    ]);
    final navigation = CommentNavigationController.file(editor);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: SyntaxFileView(
                    controller: editor,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    commentNavigation: navigation,
                    annotationBuilder: (_, a) => SizedBox(
                      height: a.id == 'a' ? 700 : 60,
                      child: Text('Thread ${a.id}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await navigation.reveal(navigation.threads.last);
    await tester.pumpAndSettle();
    expect(find.text('Thread b').hitTestable(), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    navigation.dispose();
    editor.dispose();
  });

  for (final keepVisible in [true, false]) {
    testWidgets(
      'file collections reveal through nested viewports (keepVisible=$keepVisible)',
      (tester) async {
        final files = FileListController([
          const SourceFile(id: 'a', path: 'a.txt', text: 'one'),
          const SourceFile(id: 'b', path: 'b.txt', text: 'two'),
        ]);
        final editor = files.acquire('b');
        editor.setAnnotations([
          for (final id in ['first', 'second'])
            LineAnnotation(id: id, start: 0, end: 0, data: discussion(id)),
        ]);
        files.release('b');
        files.toggle('b');
        final navigation = CommentNavigationController.files(files);
        final height = ValueNotifier<double>(400);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: ValueListenableBuilder<double>(
                  valueListenable: height,
                  builder: (_, h, _) => SizedBox(
                    height: h,
                    child: SyntaxCommentHighlightTheme(
                      keepVisible: keepVisible,
                      child: SyntaxFileList(
                        controller: files,
                        highlighter: Highlighter(),
                        theme: githubDarkTheme,
                        commentNavigation: navigation,
                        fileHeight: 220,
                        annotationBuilder: (_, a) => SizedBox(
                          height: a.id == 'first' ? 700 : 60,
                          child: Column(
                            children: [
                              Text('Heading ${a.id}'),
                              const Spacer(),
                              Text('End ${a.id}'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await navigation.reveal(navigation.threads.last);
        await tester.pumpAndSettle();
        expect(files.isCollapsed('b'), isFalse);
        expect(find.text('Heading second').hitTestable(), findsOneWidget);
        if (keepVisible) {
          height.value = 160;
          await tester.pumpAndSettle();
          expect(find.text('Heading second').hitTestable(), findsOneWidget);
          expect(find.text('End second').hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        navigation.dispose();
        files.dispose();
        height.dispose();
      },
    );
  }

  testWidgets(
    'visibility maintenance can be disabled without disabling jumps',
    (tester) async {
      final editor = EditorController(
        file: SourceFile(
          id: 'file',
          path: 'file.txt',
          text: List.filled(50, 'line').join('\n'),
        ),
      );
      editor.setAnnotations([
        LineAnnotation(id: 'a', start: 100, end: 100, data: discussion('a')),
      ]);
      final navigation = CommentNavigationController.file(editor);
      final scroll = ScrollController();
      final height = ValueNotifier<double>(80);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 300,
                child: SyntaxCommentHighlightTheme(
                  keepVisible: false,
                  child: SyntaxFileView(
                    controller: editor,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    scrollController: scroll,
                    commentNavigation: navigation,
                    annotationBuilder: (_, a) => ValueListenableBuilder<double>(
                      valueListenable: height,
                      builder: (_, h, _) => SizedBox(
                        height: h,
                        child: const Text('Thread heading'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await navigation.next();
      await tester.pumpAndSettle();
      expect(find.text('Thread heading').hitTestable(), findsOneWidget);
      final before = scroll.offset;
      height.value = 260;
      await tester.pumpAndSettle();
      expect(scroll.offset, before);
      await navigation.next();
      await tester.pumpAndSettle();
      expect(find.text('Thread heading').hitTestable(), findsOneWidget);
      expect(scroll.offset, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      navigation.dispose();
      editor.dispose();
      scroll.dispose();
      height.dispose();
    },
  );

  for (final mode in ['file', 'unified', 'split']) {
    testWidgets(
      '$mode jumps reveal long thread headings and keep resized discussions visible',
      (tester) async {
        final text = List.generate(100, (i) => 'Line $i').join('\n');
        final editor = EditorController(
          file: SourceFile(id: 'file', path: 'file.txt', text: text),
        );
        final patch = PatchController([
          diffTexts('', text, id: 'file', path: 'file.txt'),
        ], mode: mode == 'split' ? DiffMode.split : DiffMode.unified);
        final notes = [discussion('first'), discussion('second')];
        editor.setAnnotations([
          for (final note in notes)
            LineAnnotation(
              id: note.id,
              start: editor.document.lineStart(20),
              end: editor.document.lineStart(20),
              data: note,
            ),
        ]);
        patch.setAnnotations([
          for (final note in notes)
            ReviewAnnotation(
              id: note.id,
              fileId: 'file',
              side: DiffSide.newer,
              line: 21,
              data: note,
            ),
        ]);
        final navigation = mode == 'file'
            ? CommentNavigationController.file(editor)
            : CommentNavigationController.patch(patch);
        final scroll = ScrollController();
        final height = ValueNotifier<double>(700);
        final viewHeight = ValueNotifier<double>(360);
        Widget annotation(String id) => ValueListenableBuilder<double>(
          valueListenable: height,
          builder: (_, h, _) => SizedBox(
            key: ValueKey(id),
            height: id == 'first' ? h : 80,
            child: Column(
              children: [Text('Heading $id'), const Spacer(), Text('End $id')],
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: ValueListenableBuilder<double>(
                  valueListenable: viewHeight,
                  builder: (_, h, _) => SizedBox(
                    height: h,
                    child: mode == 'file'
                        ? SyntaxFileView(
                            controller: editor,
                            highlighter: Highlighter(),
                            theme: githubDarkTheme,
                            scrollController: scroll,
                            commentNavigation: navigation,
                            annotationBuilder: (_, a) => annotation(a.id),
                          )
                        : PatchView.controlled(
                            controller: patch,
                            highlighter: Highlighter(),
                            theme: githubDarkTheme,
                            scrollController: scroll,
                            commentNavigation: navigation,
                            annotationBuilder: (_, a) => annotation(a.id),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await navigation.reveal(navigation.threads.last);
        await tester.pumpAndSettle();
        expect(find.text('Heading second').hitTestable(), findsOneWidget);
        await navigation.previous();
        await tester.pumpAndSettle();
        expect(find.text('Heading first').hitTestable(), findsOneWidget);
        expect(find.text('End first').hitTestable(), findsNothing);
        height.value = 110;
        await tester.pumpAndSettle();
        expect(find.text('Heading first').hitTestable(), findsOneWidget);
        expect(find.text('End first').hitTestable(), findsOneWidget);
        await navigation.next();
        await tester.pumpAndSettle();
        viewHeight.value = 180;
        await tester.pumpAndSettle();
        expect(find.text('Heading second').hitTestable(), findsOneWidget);
        expect(find.text('End second').hitTestable(), findsOneWidget);
        // A user scroll must remain authoritative even if the active row changes.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
        await tester.pumpAndSettle();
        final manualOffset = scroll.offset;
        height.value = 120;
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThanOrEqualTo(manualOffset - 1));
        expect(find.text('Heading second').hitTestable(), findsNothing);
        await navigation.reveal(navigation.threads.last);
        await tester.pumpAndSettle();
        expect(find.text('Heading second').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        navigation.dispose();
        editor.dispose();
        patch.dispose();
        scroll.dispose();
        height.dispose();
        viewHeight.dispose();
      },
    );
  }
}
