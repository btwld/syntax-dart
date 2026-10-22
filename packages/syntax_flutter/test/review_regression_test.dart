import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('file collection rebinds sessions when its controller changes', (
    tester,
  ) async {
    final first = FileListController([
      const SourceFile(id: 'same', path: 'old.dart', text: 'old source'),
    ], sessionLimit: 0);
    final second = FileListController([
      const SourceFile(id: 'same', path: 'new.dart', text: 'new source'),
    ], sessionLimit: 0);
    Widget view(FileListController controller) => app(
      SyntaxFileList(
        controller: controller,
        highlighter: highlighter,
        theme: githubDarkTheme,
      ),
    );
    await tester.pumpWidget(view(first));
    await tester.pumpAndSettle();
    final old = first.sessions.peek('same')!;
    await tester.pumpWidget(view(second));
    await tester.pumpAndSettle();
    expect(find.text('new source', findRichText: true), findsWidgets);
    expect(find.text('old source', findRichText: true), findsNothing);
    expect(old.isDisposed, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(second.sessions.peek('same'), isNull);
    first.dispose();
    second.dispose();
  });

  testWidgets(
    'source conflicts keep drafts until reload is explicitly chosen',
    (tester) async {
      final files = FileListController([
        const SourceFile(id: 'f', path: 'a.dart', text: 'original'),
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
      await tester.pumpAndSettle();
      final editor = files.sessions.peek('f')!;
      editor.insertText('draft ');
      files.setFiles([
        const SourceFile(
          id: 'f',
          path: 'a.dart',
          text: 'external',
          revision: 5,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(editor.document.text, 'draft original');
      await tester.tap(find.text('Source changed — reload latest source'));
      await tester.pumpAndSettle();
      expect(editor.document.text, 'external');
      expect(editor.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
      files.dispose();
    },
  );

  testWidgets('repeating a collection reveal scrolls the retained file again', (
    tester,
  ) async {
    final files = FileListController([
      SourceFile(
        id: 'f',
        path: '',
        text: List.generate(300, (i) => 'source $i').join('\n'),
      ),
    ]);
    await tester.pumpWidget(
      app(
        SyntaxFileList(
          controller: files,
          highlighter: highlighter,
          theme: githubDarkTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();
    const range = DocumentRange(
      DocumentPosition(250, 0),
      DocumentPosition(251, 0),
    );
    files.reveal('f', range);
    await tester.pumpAndSettle();
    final editor = files.sessions.peek('f')!;
    final request = editor.revealRequest;
    final inner = tester
        .widgetList<CustomScrollView>(find.byType(CustomScrollView))
        .last
        .controller!;
    inner.jumpTo(0);
    await tester.pumpAndSettle();
    files.reveal('f', range);
    await tester.pumpAndSettle();
    expect(editor.revealRequest, greaterThan(request));
    expect(inner.offset, greaterThan(1000));
    await tester.pumpWidget(const SizedBox());
    files.dispose();
  });

  testWidgets('native backspace removes whole graphemes at every caret', (
    tester,
  ) async {
    final editor = EditorController(
      file: const SourceFile(id: 'f', path: '', text: '😀 👨‍👩‍👧‍👦'),
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
    editor.setSelections([
      const DocumentSelection.collapsed(2),
      DocumentSelection.collapsed(editor.document.length),
    ]);
    final input = tester.widget<TextField>(find.byType(TextField)).controller!;
    input.value = const TextEditingValue(
      text: ' 👨‍👩‍👧‍👦',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.pumpAndSettle();
    expect(editor.document.text, ' ');
    editor.undo();
    expect(editor.document.text, '😀 👨‍👩‍👧‍👦');
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
  });

  testWidgets('replacing a grammar refreshes an existing file viewport', (
    tester,
  ) async {
    Language grammar(String scope) => Language.fromJson({
      'scopeName': 'source.custom',
      'patterns': [
        {'match': 'foo', 'name': scope},
      ],
    }, name: 'custom');
    final highlighter = Highlighter(languages: [grammar('keyword')]);
    final editor = EditorController(
      file: const SourceFile(
        id: 'f',
        path: '',
        text: 'foo',
        language: 'custom',
      ),
    );
    Widget view() => app(
      SyntaxFileView(
        controller: editor,
        highlighter: highlighter,
        theme: githubDarkTheme,
      ),
    );
    Color? color() {
      final tokens = <TextSpan>[];
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == 'foo') tokens.add(span);
          for (final child in span.children ?? const <InlineSpan>[]) {
            visit(child);
          }
        }
      }

      for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
        visit(text.text);
      }
      return tokens.first.style!.color;
    }

    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    final before = color();
    highlighter.addLanguage(grammar('string'));
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(color(), isNot(before));
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
  });
}
