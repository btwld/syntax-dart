import 'dart:ui' show ColorSpace;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

Finder _row(String text) => find
    .ancestor(
      of: find.text(text, findRichText: true),
      matching: find.byType(ColoredBox),
    )
    .first;

Color _background(WidgetTester tester, String text) =>
    tester.widget<ColoredBox>(_row(text)).color;

void _expectSelected(WidgetTester tester, String text, Color background) {
  final row = tester.renderObject(_row(text));
  final rect = Offset.zero & tester.getSize(_row(text));
  expect(_background(tester, text), background);
  expect(
    row,
    paints
      ..rect(rect: rect, color: background)
      ..rect(rect: rect, color: githubDarkTheme.selectionColor),
  );
}

void _expectUnselected(WidgetTester tester, String text, Color background) {
  expect(_background(tester, text), background);
  expect(
    tester.renderObject(_row(text)),
    paintsExactlyCountTimes(#drawRect, 1),
  );
}

Offset _gutter(WidgetTester tester, String text) {
  final row = tester.getRect(_row(text));
  return Offset(row.left + 8, row.top + 10);
}

void main() {
  for (final wrap in [false, true]) {
    testWidgets(
      'gutter selection overlays custom line backgrounds (wrap=$wrap)',
      (tester) async {
        const tint = Color(0xff553322);
        const otherTint = Color(0xff224455);
        final marked = 'marked word ' * 30;
        final source = CodeViewController(
          sourceId: 'a',
          code: 'first\n$marked\nlast',
        );
        addTearDown(source.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: HighlightedCode.controlled(
              controller: source,
              language: 'text',
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              lineNumbers: true,
              softWrap: wrap,
              lineBackgroundBuilder: (line) => switch (line) {
                1 => tint,
                2 => otherTint,
                _ => null,
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_background(tester, marked), tint);
        final gesture = await tester.startGesture(
          _gutter(tester, marked),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(_gutter(tester, 'first'));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(source.selection, (anchor: 1, active: 0));
        _expectSelected(tester, marked, tint);
        _expectSelected(tester, 'first', const Color(0x00000000));
        _expectUnselected(tester, 'last', otherTint);
        if (wrap) expect(tester.getRect(_row(marked)).height, greaterThan(21));
        source.setCode(source.code, revision: 1);
        await tester.pumpAndSettle();
        expect(source.selection, isNull);
        _expectUnselected(tester, 'first', const Color(0x00000000));
        _expectUnselected(tester, marked, tint);
        _expectUnselected(tester, 'last', otherTint);
      },
    );
  }

  testWidgets('virtualized programmatic selection preserves background tints', (
    tester,
  ) async {
    const even = Color(0x80553322);
    const odd = Color(0xff224455);
    final source =
        CodeViewController(
            sourceId: 'large',
            code: List.generate(500, (line) => 'row $line').join('\n'),
          )
          ..selectLines(250, 250)
          ..revealLine(250);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HighlightedCode.controlled(
          controller: source,
          language: 'text',
          theme: githubDarkTheme,
          highlighter: Highlighter(),
          lineBackgroundBuilder: (line) => line.isEven ? even : odd,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IndexedCodeViewport), findsOneWidget);
    _expectSelected(tester, 'row 250', even);
    _expectUnselected(tester, 'row 251', odd);
    source.selectLines(251, 251);
    await tester.pumpAndSettle();
    _expectUnselected(tester, 'row 250', even);
    _expectSelected(tester, 'row 251', odd);
  });
  for (final space in [ColorSpace.displayP3, ColorSpace.extendedSRGB]) {
    testWidgets(
      'selection overlays background in $space without color-space assertions',
      (tester) async {
        final tint = Color.from(
          alpha: .8,
          red: .7,
          green: .2,
          blue: .4,
          colorSpace: space,
        );
        final source = CodeViewController(sourceId: 'a', code: 'marked')
          ..selectLines(0, 0);
        addTearDown(source.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: HighlightedCode.controlled(
              controller: source,
              language: 'text',
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              lineBackgroundBuilder: (_) => tint,
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectSelected(tester, 'marked', tint);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
