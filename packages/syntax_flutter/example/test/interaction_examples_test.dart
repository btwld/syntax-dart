import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';
import 'package:syntax_example/interaction_examples.dart';

Future<void> launch(
  WidgetTester tester,
  int kind, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InteractionExamples(
          kind: kind,
          theme: githubDarkTheme,
          textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selection presets, source copy and annotations are live', (
    tester,
  ) async {
    await launch(tester, 0);
    final review = tester.widget<PatchView>(find.byType(PatchView)).controller!;
    await tester.tap(find.text('Select across sides'));
    await tester.pumpAndSettle();
    expect(review.selection!.crossesSides, isTrue);
    expect(review.selectedText(), contains('cleaned.isEmpty'));
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Handle missing names');
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(review.annotations.single.data, 'Handle missing names');
    await tester.tap(find.text('Clear selection'));
    await tester.pumpAndSettle();
    expect(review.selection, isNull);
    await tester.tap(find.text('Show file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select lines 2–4'));
    await tester.pumpAndSettle();
    final file = tester
        .widget<SyntaxFileView>(find.byType(SyntaxFileView))
        .controller;
    expect(file.document.positionAt(file.selections.single.start).line, 1);
    expect(file.document.positionAt(file.selections.single.end).line, 3);
    expect(tester.takeException(), isNull);
  });
  testWidgets('named sections fold independently and reveal their function', (
    tester,
  ) async {
    await launch(tester, 1);
    final review = tester.widget<PatchView>(find.byType(PatchView)).controller!;
    expect(review.files.single.hunks.length, 3);
    await tester.tap(find.text('Fold all sections'));
    await tester.pumpAndSettle();
    expect(review.layout.whereType<DiffLineRow>(), isEmpty);
    await tester.tap(find.text('Jump to retryDelay'));
    await tester.pumpAndSettle();
    expect(review.isHunkCollapsed('policy', 0), isTrue);
    expect(review.isHunkCollapsed('policy', 1), isFalse);
    expect(review.isHunkCollapsed('policy', 2), isTrue);
    expect(
      find.textContaining('delay.clamp', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Expand all sections'));
    await tester.pumpAndSettle();
    expect(review.isHunkCollapsed('policy', 0), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('appearance and custom header controls work at compact width', (
    tester,
  ) async {
    await launch(tester, 2, size: const Size(520, 900));
    await tester.tap(find.text('Hide numbers'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatchView>(find.byType(PatchView)).showLineNumbers,
      isFalse,
    );
    await tester.tap(find.text('Hide backgrounds'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatchView>(find.byType(PatchView)).showBackgrounds,
      isFalse,
    );
    await tester.tap(find.text('Markers: classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markers: bars').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatchView>(find.byType(PatchView)).indicators,
      DiffIndicators.bars,
    );
    expect(tester.takeException(), isNull);
    await launch(tester, 4);
    await tester.tap(find.byTooltip('Collapse custom file'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PatchView>(find.byType(PatchView))
          .controller!
          .isCollapsed('policy'),
      isTrue,
    );
    await tester.tap(find.byTooltip('Expand custom file'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'token inspection and arbitrary source comparison produce output',
    (tester) async {
      await launch(tester, 3);
      final tokenText = tester.widget<Text>(
        find
            .descendant(
              of: find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Tooltip &&
                        widget.message!.contains('Changed token'),
                  )
                  .first,
              matching: find.byType(Text),
            )
            .first,
      );
      expect(tokenText.style!.fontFamily, 'monospace');
      expect(tokenText.style!.fontSize, 13);
      await tester.tap(find.text('Inspect selected line'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Line 4:'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip && widget.message!.contains('Changed token'),
        ),
        findsWidgets,
      );
      await launch(tester, 5);
      await tester.enterText(
        find.widgetWithText(TextField, 'Original source'),
        'final value = 1;',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Updated source'),
        'final value = 2;',
      );
      await tester.tap(find.text('Compare sources'));
      await tester.pumpAndSettle();
      final review = tester
          .widget<PatchView>(find.byType(PatchView))
          .controller!;
      expect(review.files.single.newText, 'final value = 2;');
      expect(review.files.single.oldText, 'final value = 1;');
      expect(tester.takeException(), isNull);
      await launch(tester, 3);
      await tester.tap(find.text('Inspect selected line'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Line 4:'), findsOneWidget);
      expect(
        tester
            .widget<PatchView>(find.byType(PatchView))
            .controller!
            .files
            .single
            .path,
        'lib/request_policy.dart',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('appearance preserves supplied fonts and resets locally', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractionExamples(
            kind: 2,
            theme: githubDarkTheme,
            textStyle: const TextStyle(
              fontFamily: 'Gallery Mono',
              fontSize: 13.5,
            ),
            fontStyles: const {
              'Alternate': TextStyle(
                fontFamily: 'Alternate Mono',
                fontSize: 13.5,
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    PatchView view() => tester.widget<PatchView>(find.byType(PatchView));
    expect(view().textStyle!.fontFamily, 'Gallery Mono');
    expect(view().textStyle!.fontSize, 13.5);
    await tester.tap(find.text('Font: Default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Font: Alternate').last);
    await tester.pumpAndSettle();
    expect(view().textStyle!.fontFamily, 'Alternate Mono');
    await tester.tap(find.text('Hide backgrounds'));
    await tester.ensureVisible(find.text('Reset example'));
    await tester.tap(find.text('Reset example'));
    await tester.pumpAndSettle();
    expect(view().showBackgrounds, isTrue);
    expect(view().textStyle!.fontFamily, 'Gallery Mono');
  });
}
