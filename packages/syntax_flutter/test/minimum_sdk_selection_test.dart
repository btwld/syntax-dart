import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app, caret, copy, selection;

void main() {
  testWidgets('late-mounted native endpoint retains its CRLF separator', (
    tester,
  ) async {
    final lines = List.generate(200, (i) => 'source line $i;');
    final scroll = ScrollController();
    await tester.pumpWidget(
      app(
        PatchView.fromTexts(
          oldText: '',
          newText: lines.join('\r\n'),
          path: 'a.txt',
          theme: githubDarkTheme,
          highlighter: Highlighter(),
          scrollController: scroll,
          wrap: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(2000);
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(IndexedCodeViewport));
    final paragraphs = find.byType(RichText).evaluate().where((element) {
      final text = (element.widget as RichText).text.toPlainText();
      final box = element.renderObject! as RenderBox;
      final top = box.localToGlobal(Offset.zero).dy;
      return text.startsWith('source line ') &&
          top > viewport.top + 40 &&
          top + box.size.height < viewport.bottom - 40;
    }).toList();
    final start = (paragraphs[paragraphs.length ~/ 2].widget as RichText).text
        .toPlainText();
    final gesture = await tester.startGesture(
      caret(tester, start, start.length),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await gesture.moveTo(
        Offset(viewport.right - 20, viewport.top - 40 - i % 2),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final selected = selection(tester).getSelectedContent()!.plainText;
    final numbers = RegExp(
      r'source line (\d+);',
    ).allMatches(selected).map((match) => int.parse(match[1]!)).toList();
    expect(numbers.length, greaterThan(10));
    expect(
      selected,
      '\r\n${lines.sublist(numbers.first, numbers.last + 1).join('\r\n')}',
    );
    await copy(tester, selected);
    // Rebuilding the visible window after the drag must not move the endpoint.
    scroll.jumpTo(scroll.offset + 300);
    await tester.pumpAndSettle();
    expect(selection(tester).getSelectedContent()!.plainText, selected);
    expectPlainTree(tester);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
