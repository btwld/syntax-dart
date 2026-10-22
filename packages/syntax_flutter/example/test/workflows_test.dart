import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_example/workflows.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
  testWidgets(
    'workflow wrapping reaches files and streams, and streams restart',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const style = TextStyle(fontFamily: 'Example Mono', fontSize: 15);
      await tester.pumpWidget(
        MaterialApp(home: WorkflowsDemo(textStyle: style)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrap'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Files'));
      await tester.pumpAndSettle();
      for (final editor in tester.widgetList<SyntaxEditor>(
        find.byType(SyntaxEditor),
      )) {
        expect(editor.wrap, isFalse);
        expect(editor.textStyle, style);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Streaming'));
      await tester.pumpAndSettle();
      final first = tester
          .widget<StreamingCodeView>(find.byType(StreamingCodeView))
          .controller;
      expect(
        tester.widget<SyntaxFileView>(find.byType(SyntaxFileView)).wrap,
        isFalse,
      );
      expect(
        tester.widget<SyntaxFileView>(find.byType(SyntaxFileView)).textStyle,
        style,
      );
      await tester.tap(find.text('Start stream'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(first.editor.document.text, isNotEmpty);
      await tester.tap(find.text('Cancel stream'));
      await tester.pumpAndSettle();
      expect(first.isCancelled, isTrue);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Start stream'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Reset stream'));
      await tester.pumpAndSettle();
      final next = tester
          .widget<StreamingCodeView>(find.byType(StreamingCodeView))
          .controller;
      expect(next, isNot(same(first)));
      expect(next.editor.document.text, isEmpty);
      await tester.tap(find.text('Start stream'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(next.editor.document.text, startsWith('final streamed0 = 0;'));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
