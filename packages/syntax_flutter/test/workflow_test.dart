import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));
  testWidgets(
    'native editor input, undo, search and completion use one session',
    (tester) async {
      final controller = EditorController(
        file: const SourceFile(
          id: 'a',
          path: 'a.dart',
          text: 'final answer = 1;',
        ),
      );
      SourceFile? accepted;
      await tester.pumpWidget(
        app(
          SyntaxEditor(
            controller: controller,
            highlighter: highlighter,
            theme: githubDarkTheme,
            onComplete: (result) async {
              accepted = result;
              return true;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'final answer = 42;');
      await tester.pump();
      expect(controller.document.text, 'final answer = 42;');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(controller.document.text, 'final answer = 1;');
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(controller.document.text, 'final answer = 42;');
      await tester.tap(find.byTooltip('Find and replace'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'answer');
      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(
        controller.document.text.substring(
          controller.selections.first.start,
          controller.selections.first.end,
        ),
        'answer',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(accepted?.text, 'final answer = 42;');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('composition keeps exact source and external carets appear', (
    tester,
  ) async {
    final controller = EditorController(
      file: const SourceFile(
        id: 'a',
        path: 'a.dart',
        text: 'final emoji = "😀";\r\nnext\rline',
      ),
    );
    controller.setCarets([
      const RemoteCaret(
        id: 'peer',
        selection: DocumentSelection.collapsed(6),
        color: 0xff00ff00,
      ),
    ]);
    await tester.pumpWidget(
      app(
        SyntaxEditor(
          controller: controller,
          highlighter: highlighter,
          theme: githubDarkTheme,
        ),
      ),
    );
    final editable = tester.widget<TextField>(find.byType(TextField));
    final input = editable.controller!;
    input.value = input.value.copyWith(
      selection: const TextSelection.collapsed(offset: 4),
      composing: const TextRange(start: 0, end: 5),
    );
    await tester.pump();
    final context = tester.element(find.byType(TextField));
    expect(
      input.buildTextSpan(context: context, withComposing: true).toPlainText(),
      controller.document.text,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('controlled patch loads, selects source, annotates and accepts', (
    tester,
  ) async {
    final full = diffTexts('a\nb\nc\n', 'a\nB\nc\n', path: 'a.dart', id: 'a');
    final partial = parsePatch(
      renderPatch(full),
    ).single.copyWith(identity: 'a');
    final controller = PatchController(
      [partial],
      contentsLoader: (_, _) async =>
          (oldText: 'a\nb\nc\n', newText: 'a\nB\nc\n'),
    );
    controller.setAnnotations([
      const ReviewAnnotation(
        id: 'note',
        fileId: 'a',
        side: DiffSide.newer,
        line: 2,
        data: 'Please check this',
      ),
    ]);
    await tester.pumpWidget(
      app(
        PatchView.controlled(
          controller: controller,
          highlighter: highlighter,
          theme: githubDarkTheme,
          showReviewActions: true,
        ),
      ),
    );
    await tester.tap(find.text('Load full contents'));
    await tester.pumpAndSettle();
    expect(controller.files.single.isPartial, isFalse);
    expect(find.text('Please check this'), findsOneWidget);
    controller.select(const DiffSelection('a', DiffSide.newer, 1, 2));
    await tester.pump();
    expect(controller.selectedText(), 'a\nB');
    await tester.tap(find.text('Copy selected lines'));
    await tester.pump();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(controller.files.single.hunks, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'conflicts resolve sequentially and preserve surrounding source',
    (tester) async {
      final merge = MergeController(
        const SourceFile(
          id: 'm',
          path: 'merge.dart',
          text: 'before\n<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\nafter',
        ),
      );
      await tester.pumpWidget(
        app(
          MergeConflictView(
            controller: merge,
            highlighter: highlighter,
            theme: githubDarkTheme,
          ),
        ),
      );
      await tester.tap(find.text('Keep both'));
      await tester.pump();
      expect(merge.file.text, 'before\na\nb\nafter');
      expect(find.text('All conflicts resolved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      merge.dispose();
    },
  );
  testWidgets(
    'large file mounts a bounded window and retained sessions restore drafts',
    (tester) async {
      final files = FileListController([
        SourceFile(
          id: 'large',
          path: 'large.dart',
          text: List.generate(100000, (i) => 'final value$i = $i;').join('\n'),
        ),
      ]);
      await tester.pumpWidget(
        app(
          SyntaxFileList(
            controller: files,
            highlighter: highlighter,
            theme: githubDarkTheme,
            editable: true,
          ),
        ),
      );
      final editor = tester
          .widget<SyntaxEditor>(find.byType(SyntaxEditor))
          .controller;
      editor.setSelections(const [DocumentSelection.collapsed(0)]);
      editor.insertText('// draft\n', autoSurround: false);
      await tester.pump();
      await tester.tap(find.byType(ListTile));
      await tester.pump();
      expect(find.byType(SyntaxEditor), findsNothing);
      await tester.tap(find.byType(ListTile));
      await tester.pump();
      expect(
        tester.widget<SyntaxEditor>(find.byType(SyntaxEditor)).controller,
        same(editor),
      );
      expect(editor.canUndo, isTrue);
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
          ),
        ),
      );
      expect(find.byType(RichText).evaluate().length, lessThan(150));
      await tester.pumpWidget(const SizedBox());
      files.dispose();
    },
  );
  testWidgets('stream appends bytes and suggestions can be accepted', (
    tester,
  ) async {
    final stream = StreamDocumentController(
      const SourceFile(id: 's', path: 's.dart', text: ''),
    );
    await tester.pumpWidget(
      app(
        StreamingCodeView(
          controller: stream,
          highlighter: highlighter,
          theme: githubDarkTheme,
        ),
      ),
    );
    stream.add('final value = ');
    stream.add([52, 50, 59]);
    stream.finish();
    await tester.pump();
    expect(stream.editor.document.text, 'final value = 42;');
    await tester.pumpWidget(const SizedBox());
    stream.dispose();
    final editor = EditorController(
      file: const SourceFile(id: 'a', path: 'a.dart', text: ''),
      proposalDelay: Duration.zero,
      proposalProvider: (_) async => [const OffsetEdit(0, 1, 'suggested')],
    );
    await tester.pumpWidget(
      app(
        SyntaxEditor(
          controller: editor,
          highlighter: highlighter,
          theme: githubDarkTheme,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();
    await tester.pump();
    expect(find.text('Accept suggestion'), findsOneWidget);
    await tester.tap(find.text('Accept suggestion'));
    await tester.pump();
    expect(editor.document.text, 'suggested');
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
  });
  testWidgets('native typing surrounds and edits all logical selections', (
    tester,
  ) async {
    final editor = EditorController(
      file: const SourceFile(id: 'multi', path: '', text: 'one two'),
    );
    await tester.pumpWidget(
      app(
        SyntaxEditor(
          controller: editor,
          highlighter: highlighter,
          theme: githubDarkTheme,
        ),
      ),
    );
    editor.setSelections(const [
      DocumentSelection(0, 3),
      DocumentSelection(4, 7),
    ]);
    final input = tester.widget<TextField>(find.byType(TextField)).controller!;
    input.value = const TextEditingValue(
      text: '( two',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    expect(editor.document.text, '(one) (two)');
    expect(editor.selections, [
      const DocumentSelection(1, 4),
      const DocumentSelection(7, 10),
    ]);
    expect(input.text, editor.document.text);
    editor.undo();
    await tester.pump();
    expect(input.text, 'one two');
    input.value = const TextEditingValue(
      text: ' two',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.pump();
    expect(input.text, ' ');
    expect(editor.document.text, ' ');
    editor.undo();
    expect(editor.document.text, 'one two');
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
  });
  testWidgets(
    'indexed viewport jumps to distant lines with measured annotations',
    (tester) async {
      final editor = EditorController(
        file: SourceFile(
          id: 'indexed',
          path: '',
          text: List.generate(100000, (i) => 'source line $i').join('\n'),
        ),
      );
      editor.setAnnotations([
        const LineAnnotation(id: 'large', start: 0, end: 1, data: 'note'),
      ]);
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
            annotationBuilder: (_, _) =>
                const SizedBox(height: 180, child: Text('Large annotation')),
          ),
        ),
      );
      editor.reveal(
        const DocumentRange(
          DocumentPosition(90000, 0),
          DocumentPosition(90000, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('source line 90000', findRichText: true),
        findsWidgets,
      );
      expect(find.byType(RichText).evaluate().length, lessThan(150));
      editor.reveal(
        const DocumentRange(DocumentPosition(0, 0), DocumentPosition(0, 0)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Large annotation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );
  testWidgets('split panes synchronize native horizontal scrolling', (
    tester,
  ) async {
    final review = PatchController([
      diffTexts('${'a' * 500}\n', '${'b' * 500}\n', id: 'wide'),
    ], mode: DiffMode.split);
    await tester.pumpWidget(
      app(
        PatchView.controlled(
          controller: review,
          highlighter: highlighter,
          theme: githubDarkTheme,
          wrap: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controllers = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where(
          (view) =>
              view.scrollDirection == Axis.horizontal &&
              view.controller!.position.maxScrollExtent > 100,
        )
        .map((view) => view.controller!)
        .toList();
    expect(controllers.length, greaterThanOrEqualTo(2));
    controllers.first.jumpTo(80);
    await tester.pumpAndSettle();
    for (final controller in controllers) {
      expect(controller.offset, 80);
    }
    await tester.pumpWidget(const SizedBox());
    review.dispose();
  });
  testWidgets('source scroll anchor survives insertions before the viewport', (
    tester,
  ) async {
    final editor = EditorController(
      file: SourceFile(
        id: 'anchor',
        path: '',
        text: List.generate(10000, (i) => 'anchor source $i').join('\n'),
      ),
    );
    await tester.pumpWidget(
      app(
        SyntaxFileView(
          controller: editor,
          highlighter: highlighter,
          theme: githubDarkTheme,
        ),
      ),
    );
    editor.reveal(
      const DocumentRange(DocumentPosition(9000, 0), DocumentPosition(9000, 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('anchor source 9000', findRichText: true), findsWidgets);
    editor.applyEdits([OffsetEdit(0, 0, 'inserted\n' * 500)]);
    await tester.pumpAndSettle();
    expect(find.text('anchor source 9000', findRichText: true), findsWidgets);
    expect(find.byType(RichText).evaluate().length, lessThan(150));
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
  });
  testWidgets('file horizontal scroll survives view disposal', (tester) async {
    final editor = EditorController(
      file: SourceFile(id: 'wide', path: '', text: 'wide source ' * 100),
    );
    Widget view() => app(
      SyntaxFileView(
        controller: editor,
        highlighter: highlighter,
        theme: githubDarkTheme,
        wrap: false,
      ),
    );
    ScrollController horizontal() => tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .firstWhere((view) => view.scrollDirection == Axis.horizontal)
        .controller!;
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    horizontal().jumpTo(120);
    await tester.pumpAndSettle();
    expect(editor.horizontalOffset, 120);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(horizontal().offset, 120);
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
  });
  testWidgets(
    'native editor uses background tokens and retains horizontal position',
    (tester) async {
      final editor = EditorController(
        file: SourceFile(
          id: 'background',
          path: '',
          text: 'final wide = "${'x' * 500}";',
        ),
      );
      final pool = HighlightPool(executor: SynchronousHighlightExecutor());
      Widget view() => app(
        SyntaxEditor(
          controller: editor,
          highlighter: highlighter,
          theme: githubDarkTheme,
          language: 'dart',
          executor: pool,
          wrap: false,
        ),
      );
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      final input = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      final span = input.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: false,
      );
      final keyword = span.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'final',
      );
      expect(keyword.style!.color, isNot(Color(githubDarkTheme.foreground)));
      expect(editor.selections.single, const DocumentSelection.collapsed(0));
      ScrollController horizontal() => tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .firstWhere((view) => view.scrollDirection == Axis.horizontal)
          .controller!;
      horizontal().jumpTo(120);
      await tester.pumpAndSettle();
      expect(editor.horizontalOffset, 120);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      expect(horizontal().offset, 120);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
      pool.dispose();
    },
  );
}
