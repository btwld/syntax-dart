import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';
import 'package:syntax_flutter/src/code_rows.dart';

Widget _app(Widget child) => MaterialApp(home: child);

HighlightedCode _view(CodeViewController controller, {bool wrap = false}) =>
    HighlightedCode.controlled(
      controller: controller,
      language: 'text',
      theme: githubDarkTheme,
      highlighter: Highlighter(),
      lineNumbers: true,
      softWrap: wrap,
    );

Finder _text(String value) => find.text(value, findRichText: true);
Finder _row(String value) =>
    find.ancestor(of: _text(value), matching: find.byType(ColoredBox)).first;

Offset _at(WidgetTester tester, String line, int offset) {
  final paragraph = tester.renderObject<RenderParagraph>(_text(line));
  return paragraph.localToGlobal(
    paragraph.getOffsetForCaret(TextPosition(offset: offset), Rect.zero) +
        const Offset(0, 10),
  );
}

void main() {
  for (final (controlled, separator, reverse) in [
    for (final controlled in [true, false])
      for (final separator in ['\n', '\r\n'])
        for (final reverse in [false, true]) (controlled, separator, reverse),
  ]) {
    testWidgets(
      'native boundary copy includes separator '
      '(controlled=$controlled, CRLF=${separator.length == 2}, reverse=$reverse)',
      (tester) async {
        final controller = CodeViewController(
          sourceId: 'a',
          code: 'alpha${separator}last',
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            controlled
                ? _view(controller)
                : HighlightedCode(
                    controller.code,
                    language: 'text',
                    theme: githubDarkTheme,
                    highlighter: Highlighter(),
                    lineBackgroundBuilder: (_) => null,
                  ),
          ),
        );
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          _at(tester, reverse ? 'last' : 'alpha', 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(_at(tester, reverse ? 'alpha' : 'last', 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(copied, 'alpha$separator');
      },
    );
  }

  testWidgets('collapsed click copies nothing and preserves the clipboard', (
    tester,
  ) async {
    final controller = CodeViewController(
      sourceId: 'a',
      code: 'alpha\nbeta\nlast',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_view(controller)));
    await tester.pumpAndSettle();
    await tester.tapAt(_at(tester, 'last', 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final delegate = tester
        .widgetList<SelectionContainer>(find.byType(SelectionContainer))
        .map((container) => container.delegate)
        .whereType<CodeSelectionDelegate>()
        .single;
    expect(delegate.getSelectedContent(), isNull);
    var clipboard = 'keep me';
    var writes = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
          writes++;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Actions.invoke(tester.element(_text('last')), CopySelectionTextIntent.copy);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(writes, 0);
    expect(clipboard, 'keep me');
  });

  testWidgets(
    'a genuine separator-only drag remains copyable before a collapsed click',
    (tester) async {
      final controller = CodeViewController(
        sourceId: 'a',
        code: 'alpha\nbeta\nlast',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(_view(controller)));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        _at(tester, 'alpha', 5),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(_at(tester, 'beta', 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final delegate = tester
          .widgetList<SelectionContainer>(find.byType(SelectionContainer))
          .map((container) => container.delegate)
          .whereType<CodeSelectionDelegate>()
          .single;
      expect(delegate.getSelectedContent()?.plainText, '\n');
      await tester.tapAt(_at(tester, 'last', 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(delegate.getSelectedContent(), isNull);
    },
  );

  testWidgets(
    'vertical reveal crosses external horizontal viewports without scrolling them',
    (tester) async {
      final lines = List.generate(150, (i) => 'line $i ${'long ' * 100}');
      final controller = CodeViewController(
        sourceId: 'a',
        code: lines.join('\n'),
      )..revealLine(100);
      final outer = ScrollController();
      final sideways = ScrollController(initialScrollOffset: 30);
      addTearDown(controller.dispose);
      addTearDown(outer.dispose);
      addTearDown(sideways.dispose);
      const outerKey = Key('outer');
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            key: outerKey,
            controller: outer,
            child: Column(
              children: [
                const SizedBox(height: 180),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: sideways,
                  child: SizedBox(width: 1000, child: _view(controller)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(outer.offset, greaterThan(180));
      final viewport = tester.getRect(find.byKey(outerKey));
      final line = tester.getRect(_row(lines[100]));
      expect(line.top, greaterThanOrEqualTo(viewport.top));
      expect(line.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(sideways.offset, 30);
      final horizontal = tester.stateList<ScrollableState>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(
        horizontal.map((state) => state.position.pixels).toList()..sort(),
        [0, 30],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nested vertical reveal leaves horizontal scroll unchanged', (
    tester,
  ) async {
    final lines = List.generate(150, (i) => 'line $i ${'long ' * 100}');
    final controller = CodeViewController(sourceId: 'a', code: lines.join('\n'))
      ..revealLine(100);
    addTearDown(controller.dispose);
    const outerKey = Key('outer');
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          key: outerKey,
          child: Column(
            children: [const SizedBox(height: 180), _view(controller)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final horizontal = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    );
    expect(horizontal.position.pixels, 0);
    final viewport = tester.getRect(find.byKey(outerKey));
    final line = tester.getRect(_row(lines[100]));
    expect(viewport.contains(line.center), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gutter drag scrolls the effective enclosing vertical viewport', (
    tester,
  ) async {
    final controller = CodeViewController(
      sourceId: 'a',
      code: List.generate(150, (i) => 'line $i').join('\n'),
    );
    final outer = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(outer.dispose);
    const outerKey = Key('outer');
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          key: outerKey,
          controller: outer,
          child: Column(
            children: [const SizedBox(height: 60), _view(controller)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = tester.getRect(_row('line 1'));
    final bounds = tester.getRect(find.byKey(outerKey));
    final gesture = await tester.startGesture(
      Offset(row.left + 8, row.top + 10),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(Offset(row.left + 8, bounds.bottom - 4));
    await tester.pump();
    final active = controller.selection!.active;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(outer.offset, greaterThan(0));
    expect(controller.selection!.active, greaterThan(active));
    await gesture.up();
    await tester.pumpAndSettle();
    final stopped = outer.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(outer.offset, stopped);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrapped continuation gutter selects its source line', (
    tester,
  ) async {
    final long = 'long prose ' * 30;
    final controller = CodeViewController(
      sourceId: 'a',
      code: 'first\n$long\nlast',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_view(controller, wrap: true)));
    await tester.pumpAndSettle();
    final bounds = tester.getRect(_row(long));
    expect(bounds.height, greaterThan(42));
    await tester.tapAt(Offset(bounds.left + 8, bounds.top + 35));
    await tester.pumpAndSettle();
    expect(controller.selection, (anchor: 1, active: 1));
    expect(controller.selectedText, long);
    expect(tester.getTopLeft(find.text('2')).dy, bounds.top);
  });
}
