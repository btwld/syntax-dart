import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_darts/langs/dart.dart';
import 'package:syntax_darts/langs/json.dart';
import 'package:syntax_darts/themes/github_dark.dart';
import 'package:syntax_darts/themes/github_light.dart';
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
}
