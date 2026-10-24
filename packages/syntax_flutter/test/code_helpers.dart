import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_flutter/src/code_rows.dart';

/// The lines [CodeBlock]s show, by line index, as their spans.
Map<int, TextSpan> shownLines(WidgetTester tester) {
  final lines = <int, TextSpan>{};
  for (final block in tester.widgetList<CodeBlock>(find.byType(CodeBlock))) {
    var line = block.index * linesPerBlock;
    for (final child in block.span.children!.cast<TextSpan>()) {
      if (child.text == '\n' && child.style == null) {
        line++;
      } else {
        lines[line] = child;
      }
    }
  }
  return lines;
}
