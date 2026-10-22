import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);
  Widget app(Widget child, {bool dark = false}) => MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: Scaffold(body: child),
  );
  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool shift = false,
    bool alt = false,
  }) async {
    final modifier = meta
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(key);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets(
    'proposal preview keeps language, typography and visible changes',
    (tester) async {
      const source = '// context\nclass Example {\n  final value = 1;\n}\n';
      final offset = source.indexOf('1');
      final editor = EditorController(
        file: const SourceFile(
          id: 'proposal',
          path: 'example.dart',
          text: source,
        ),
        proposalProvider: (_) async => [OffsetEdit(offset, offset + 1, '42')],
      );
      const style = TextStyle(
        fontFamily: 'Example Mono',
        fontSize: 13.5,
        height: 1.72,
      );
      await tester.pumpWidget(
        app(
          SyntaxEditor(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
            textStyle: style,
            wrap: false,
          ),
        ),
      );
      await editor.requestProposal();
      await tester.pumpAndSettle();
      final patch = tester.widget<PatchView>(find.byType(PatchView));
      expect(patch.language, 'dart');
      expect(patch.textStyle, style);
      expect(patch.wrap, isFalse);
      final changed = find.textContaining(
        'final value = 42;',
        findRichText: true,
      );
      expect(changed.hitTestable(), findsOneWidget);
      final rich = tester.widget<RichText>(changed);
      bool hasKeyword(InlineSpan span) =>
          span is TextSpan &&
          (((span.text?.contains('final') ?? false) &&
                  span.style?.color != null &&
                  span.style!.color != githubDarkTheme.foregroundColor) ||
              (span.children?.any(hasKeyword) ?? false));
      expect(hasKeyword(rich.text), isTrue);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );

  testWidgets('diff editing preserves preview typography and wrapping', (
    tester,
  ) async {
    final review = PatchController([
      diffTexts('final n = 1;', 'final n = 2;', path: 'a.dart', id: 'a'),
    ]);
    const style = TextStyle(fontFamily: 'Example Mono', fontSize: 16);
    await tester.pumpWidget(
      app(
        PatchView.controlled(
          controller: review,
          highlighter: highlighter,
          theme: githubDarkTheme,
          textStyle: style,
          wrap: false,
          showReviewActions: true,
          onEditComplete: (_) async => true,
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final editor = tester.widget<SyntaxEditor>(find.byType(SyntaxEditor));
    expect(editor.textStyle, style);
    expect(editor.wrap, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    review.dispose();
  });

  for (final meta in [false, true]) {
    testWidgets(
      '${meta ? 'Cmd' : 'Ctrl'} editing shortcuts are scoped to code input',
      (tester) async {
        final editor = EditorController(
          file: const SourceFile(
            id: 'keys',
            path: 'a.dart',
            text: 'final answer = 1;',
          ),
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
        await tester.enterText(find.byType(TextField), 'final answer = 42;');
        await chord(tester, LogicalKeyboardKey.keyZ, meta: meta);
        expect(editor.document.text, 'final answer = 1;');
        await chord(tester, LogicalKeyboardKey.keyZ, meta: meta, shift: true);
        expect(editor.document.text, 'final answer = 42;');
        await chord(tester, LogicalKeyboardKey.slash, meta: meta);
        expect(editor.document.text, startsWith('//'));
        await chord(tester, LogicalKeyboardKey.keyF, meta: meta);
        final search = find.widgetWithText(TextField, 'Find');
        expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
        final source = editor.document.text;
        await tester.enterText(search, 'answer');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(editor.document.text, source);
        await tester.tap(search);
        await chord(tester, LogicalKeyboardKey.slash, meta: meta);
        expect(editor.document.text, source);
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
      },
    );
  }

  testWidgets(
    'indentation, line movement and custom shortcuts stay active in code',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(id: 'lines', path: 'a.dart', text: 'one\ntwo'),
      );
      await tester.pumpWidget(
        app(
          SyntaxEditor(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.f6):
                  EditorCommand.toggleComment,
            },
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      editor.setSelections(const [DocumentSelection(0, 3)]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(editor.document.text, startsWith('  one'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(editor.document.text, 'one\ntwo');
      editor.setSelections(const [DocumentSelection(4, 7)]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(editor.document.text, 'two\none');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(editor.document.text, 'two\ntwo\none');
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(editor.document.text, contains('//'));
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );

  testWidgets(
    'replace finds a match and never inserts into unrelated selections',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(
          id: 'find',
          path: 'a.dart',
          text: 'final answer = 42;',
        ),
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
      await tester.tap(find.byTooltip('Find and replace'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Replace'),
        'result',
      );
      final replace = find.widgetWithText(TextButton, 'Replace');
      await tester.tap(replace);
      expect(editor.document.text, 'final answer = 42;');
      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'absent');
      await tester.tap(replace);
      expect(editor.document.text, 'final answer = 42;');
      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'answer');
      await tester.tap(replace);
      await tester.pump();
      expect(editor.document.text, 'final result = 42;');
      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'result');
      await tester.enterText(find.widgetWithText(TextField, 'Replace'), 'item');
      editor.setSelections(const [
        DocumentSelection(6, 12),
        DocumentSelection(15, 17),
      ]);
      await tester.tap(replace);
      await tester.pump();
      expect(editor.document.text, 'final item = 42;');
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );

  for (final theme in [githubDarkTheme, githubLightTheme]) {
    testWidgets(
      '${theme.name} annotations and native controls use the code palette',
      (tester) async {
        final editor = EditorController(
          file: const SourceFile(
            id: 'colors',
            path: 'a.dart',
            text: 'final value = 1;',
          ),
        );
        editor.setAnnotations([
          const LineAnnotation(
            id: 'note',
            start: 0,
            end: 1,
            data: 'Review note',
          ),
        ]);
        editor.setDiagnostics([
          const Diagnostic(
            start: 0,
            end: 1,
            message: 'Information',
            severity: DiagnosticSeverity.information,
          ),
        ]);
        await tester.pumpWidget(
          app(
            SyntaxEditor(
              controller: editor,
              highlighter: highlighter,
              theme: theme,
            ),
            dark: theme == githubLightTheme,
          ),
        );
        await tester.pumpAndSettle();
        final note = tester.widget<RichText>(
          find.textContaining('Review note', findRichText: true),
        );
        expect(note.text.style!.color, theme.foregroundColor);
        final searchTheme = Theme.of(
          tester.element(find.byTooltip('Find and replace')),
        );
        expect(
          searchTheme.iconButtonTheme.style!.foregroundColor!.resolve({}),
          theme.foregroundColor,
        );
        expect(
          searchTheme.textSelectionTheme.selectionColor,
          theme.selectionColor,
        );
        expect(
          tester.widget<Icon>(find.byIcon(Icons.info_outline)).color,
          theme.diagnosticColor(DiagnosticSeverity.information),
        );
        await tester.pumpWidget(
          app(
            SyntaxFileView(
              controller: editor,
              highlighter: highlighter,
              theme: theme,
            ),
            dark: theme == githubLightTheme,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RichText>(find.text('Review note', findRichText: true))
              .text
              .style!
              .color,
          theme.foregroundColor,
        );
        expect(
          tester.widget<Text>(find.text('Information')).style!.color,
          theme.diagnosticColor(DiagnosticSeverity.information),
        );
        final patch = PatchController([
          diffTexts(
            'final value = 1;',
            'final value = 2;',
            id: 'p',
            path: 'a.dart',
          ),
        ]);
        patch.setAnnotations([
          const ReviewAnnotation(
            id: 'review',
            fileId: 'p',
            side: DiffSide.newer,
            line: 1,
            data: 'Patch note',
          ),
        ]);
        await tester.pumpWidget(
          app(
            PatchView.controlled(
              controller: patch,
              highlighter: highlighter,
              theme: theme,
            ),
            dark: theme == githubLightTheme,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RichText>(find.text('Patch note', findRichText: true))
              .text
              .style!
              .color,
          theme.foregroundColor,
        );
        await tester.pumpWidget(const SizedBox());
        patch.dispose();
        editor.dispose();
      },
    );
  }
}
