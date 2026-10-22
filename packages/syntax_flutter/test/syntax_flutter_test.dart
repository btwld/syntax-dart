import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/langs/json.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'code_helpers.dart';

final highlighter = Highlighter(languages: [dartLanguage, jsonLanguage]);

/// Flattens a span tree into (text, color) runs, resolving inherited color.
List<(String, Color?)> runs(InlineSpan span, [Color? inherited]) {
  final color = span.style?.color ?? inherited;
  if (span is! TextSpan) return const [];
  return [
    if (span.text != null) (span.text!, color),
    for (final child in span.children ?? const <InlineSpan>[])
      ...runs(child, color),
  ];
}

Color? colorOf(InlineSpan span, String text) =>
    runs(span).firstWhere((r) => r.$1 == text).$2;

void main() {
  group('HighlightedCode', () {
    testWidgets('paints tokens in theme colors on the theme background', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HighlighterScope(
            highlighter: highlighter,
            child: const HighlightedCode(
              'final answer = 42;',
              language: 'dart',
              theme: githubDarkTheme,
            ),
          ),
        ),
      );
      final span = shownLines(tester).values.single;
      expect(runs(span).map((r) => r.$1).join(), 'final answer = 42;');
      // Keywords and numbers get different colors in GitHub Dark.
      expect(colorOf(span, 'final'), isNot(colorOf(span, '42')));
      final box = tester.widget<Container>(find.byType(Container).first);
      expect(
        (box.decoration! as BoxDecoration).color,
        githubDarkTheme.backgroundColor,
      );
    });

    testWidgets('shows line numbers', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HighlightedCode(
            '{\n  "a": 1\n}',
            language: 'json',
            theme: githubLightTheme,
            highlighter: highlighter,
            lineNumbers: true,
          ),
        ),
      );
      expect(find.text('1\n2\n3'), findsOneWidget);
    });

    testWidgets('re-highlights when the code changes', (tester) async {
      Widget build(String code) => MaterialApp(
        home: HighlightedCode(
          code,
          language: 'dart',
          theme: githubDarkTheme,
          highlighter: highlighter,
        ),
      );
      await tester.pumpWidget(build('var x = 1;\n// note\nvar y = 2;'));
      // Opening a string on the first line changes how the rest reads.
      const code = 'var x = "1;\n// note\nvar y = 2;';
      await tester.pumpWidget(build(code));
      final shown = shownLines(tester).values;
      expect(shown.map((s) => s.toPlainText()).join('\n'), code);
      final fresh = highlighter.highlight(
        code,
        language: 'dart',
        theme: githubDarkTheme,
      );
      expect(
        [for (final line in shown) runs(line).map((r) => r.$1).toList()],
        [
          for (final line in fresh) [for (final token in line) token.text],
        ],
      );
    });

    testWidgets('re-highlights when the theme changes', (tester) async {
      Widget build(SyntaxTheme theme) => MaterialApp(
        home: HighlightedCode(
          'var x = 1;',
          language: 'dart',
          theme: theme,
          highlighter: highlighter,
        ),
      );
      await tester.pumpWidget(build(githubDarkTheme));
      final dark = colorOf(shownLines(tester).values.single, 'var');
      await tester.pumpWidget(build(githubLightTheme));
      final light = colorOf(shownLines(tester).values.single, 'var');
      expect(dark, isNot(light));
    });

    testWidgets('an unknown language shows plain text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HighlightedCode(
            'MOVE 1 TO X.',
            language: 'cobol',
            theme: githubDarkTheme,
            highlighter: highlighter,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('MOVE 1 TO X.'), findsOneWidget);
    });

    testWidgets('code reads left to right in a right-to-left app', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HighlightedCode(
              'var x = 1;',
              language: 'dart',
              theme: githubDarkTheme,
              highlighter: highlighter,
              lineNumbers: true,
            ),
          ),
        ),
      );
      final code = tester.element(find.text('var x = 1;'));
      expect(Directionality.of(code), TextDirection.ltr);
      // The line numbers stay on the left.
      expect(
        tester.getTopLeft(find.text('1')).dx,
        lessThan(tester.getTopLeft(find.text('var x = 1;')).dx),
      );
    });

    testWidgets('line numbers are not read out', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: HighlightedCode(
            'a\nb',
            language: 'dart',
            theme: githubDarkTheme,
            highlighter: highlighter,
            lineNumbers: true,
          ),
        ),
      );
      expect(find.bySemanticsLabel('1\n2'), findsNothing);
      expect(find.bySemanticsLabel('a\nb'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('explains a missing HighlighterScope', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HighlightedCode('x', language: 'dart', theme: githubDarkTheme),
        ),
      );
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('No HighlighterScope found'));
    });

    testWidgets('selectable wraps the code in a SelectionArea', (tester) async {
      Widget build({required bool selectable}) => MaterialApp(
        home: HighlightedCode(
          'var x;',
          language: 'dart',
          theme: githubDarkTheme,
          highlighter: highlighter,
          selectable: selectable,
        ),
      );
      await tester.pumpWidget(build(selectable: true));
      expect(find.byType(SelectionArea), findsOneWidget);
      await tester.pumpWidget(build(selectable: false));
      expect(find.byType(SelectionArea), findsNothing);
    });
  });

  group('SyntaxTextEditingController', () {
    testWidgets('highlights a TextField and underlines composing text', (
      tester,
    ) async {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: 'final value = 1;',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller, maxLines: null),
          ),
        ),
      );
      final context = tester.element(find.byType(TextField));
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 6, end: 11),
      );
      final span = controller.buildTextSpan(
        context: context,
        withComposing: true,
      );
      expect(runs(span).map((r) => r.$1).join(), 'final value = 1;');
      expect(colorOf(span, 'final'), isNot(githubDarkTheme.foregroundColor));
      final composed = (span.children!).whereType<TextSpan>().firstWhere(
        (s) => s.text == 'value',
      );
      expect(composed.style!.decoration, TextDecoration.underline);
    });

    testWidgets('spans cover the text and are reused for unchanged lines', (
      tester,
    ) async {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: 'final a = 1;\n\n// note\nvar b;',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller, maxLines: null),
          ),
        ),
      );
      final context = tester.element(find.byType(TextField));
      TextSpan build() =>
          controller.buildTextSpan(context: context, withComposing: false);

      final first = build();
      expect(runs(first).map((r) => r.$1).join(), controller.text);
      final lastLineSpan = first.children!.last;

      controller.text = 'final a = 2;\n\n// note\nvar b;';
      final second = build();
      expect(runs(second).map((r) => r.$1).join(), controller.text);
      expect(identical(second.children!.last, lastLineSpan), isTrue);
    });

    testWidgets('textStyle is merged onto the field style', (tester) async {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: 'var a;',
        textStyle: const TextStyle(fontFamily: 'Mono'),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(SizedBox)),
        style: const TextStyle(fontSize: 21),
        withComposing: false,
      );
      expect(span.style!.fontFamily, 'Mono');
      expect(span.style!.fontSize, 21);
    });

    test('changing the language re-tokenizes', () {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: '{"a": 1}',
      );
      expect(controller.tokens.single.first.scopes.scopes.first, 'source.dart');
      controller.language = 'json';
      expect(controller.tokens.single.first.scopes.scopes.first, 'source.json');
    });

    testWidgets('CRLF text keeps its carriage returns in the spans', (
      tester,
    ) async {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: 'final a = 1;\r\nvar b;\r\n',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));
      final plain = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );
      expect(plain.toPlainText(), controller.text);
      expect(controller.tokens.first.last.end, 'final a = 1;'.length);

      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 14, end: 17),
      );
      final composed = controller.buildTextSpan(
        context: context,
        withComposing: true,
      );
      expect(composed.toPlainText(), controller.text);
    });

    test('a new highlighter re-tokenizes the same text', () {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: 'var a;',
      );
      final before = controller.tokens.single;
      controller.highlighter = Highlighter(languages: [dartLanguage]);
      expect(identical(controller.tokens.single, before), isFalse);
      expect(controller.tokens.single.length, before.length);
    });

    testWidgets('a new theme or textStyle restyles the spans', (tester) async {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: 'var a;',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));
      TextSpan build() =>
          controller.buildTextSpan(context: context, withComposing: false);

      final dark = colorOf(build(), 'var');
      controller.theme = githubLightTheme;
      expect(colorOf(build(), 'var'), isNot(dark));
      controller.textStyle = const TextStyle(fontFamily: 'Mono');
      expect(build().style!.fontFamily, 'Mono');
    });

    test('changing the theme keeps tokens and notifies', () {
      final controller = SyntaxTextEditingController(
        highlighter: highlighter,
        language: 'dart',
        theme: githubDarkTheme,
        text: 'var a;',
      );
      final before = controller.tokens;
      var notified = false;
      controller.addListener(() => notified = true);
      controller.theme = githubLightTheme;
      expect(notified, isTrue);
      expect(identical(controller.tokens.single, before.single), isTrue);
    });
  });
}
