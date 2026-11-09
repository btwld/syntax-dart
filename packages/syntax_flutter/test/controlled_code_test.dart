import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/src/code_rows.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

Widget app(Widget child) => MaterialApp(home: child);
HighlightedCode view(
  CodeViewController c, {
  bool wrap = false,
  Widget? Function(BuildContext, int)? gutter,
  Color? Function(int)? background,
}) => HighlightedCode.controlled(
  controller: c,
  language: 'text',
  theme: githubDarkTheme,
  highlighter: Highlighter(),
  lineNumbers: true,
  softWrap: wrap,
  gutterBuilder: gutter,
  lineBackgroundBuilder: background,
);
Finder text(String value) => find.text(value, findRichText: true);
Finder row(String value) =>
    find.ancestor(of: text(value), matching: find.byType(ColoredBox)).first;
Offset gutter(WidgetTester tester, String value) {
  final rect = tester.getRect(row(value));
  return Offset(rect.left + 8, rect.top + 10);
}

Future<void> drag(WidgetTester tester, String line, int from, int to) async {
  final p = tester.renderObject<RenderParagraph>(text(line));
  Offset at(int column) => p.localToGlobal(
    p.getOffsetForCaret(TextPosition(offset: column), Rect.zero) +
        const Offset(0, 10),
  );
  final gesture = await tester.startGesture(
    at(from),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(at(to));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<void> expectCopy(WidgetTester tester, String expected) async {
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
  try {
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      copied = null;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(copied, expected);
    }
  } finally {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  }
}

void main() {
  testWidgets('gutter drag selects upward, copies CRLF and shift extends', (
    tester,
  ) async {
    final c = CodeViewController(
      sourceId: 'a',
      code: 'one\r\ntwo\r\nthree\r\nfour',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(app(view(c)));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      gutter(tester, 'three'),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(gutter(tester, 'one'));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.selection, (anchor: 2, active: 0));
    await expectCopy(tester, 'one\r\ntwo\r\nthree');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(gutter(tester, 'four'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(c.selection, (anchor: 2, active: 3));
    await expectCopy(tester, 'three\r\nfour');
  });
  testWidgets('native copy takes precedence over selected lines', (
    tester,
  ) async {
    final c = CodeViewController(
      sourceId: 'a',
      code: 'alpha beta\nsecond line',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(app(view(c)));
    await tester.pumpAndSettle();
    await tester.tapAt(gutter(tester, 'second line'));
    await tester.pumpAndSettle();
    await expectCopy(tester, 'second line');
    await drag(tester, 'alpha beta', 0, 4);
    // Native platform copy on Linux uses Control.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
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
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    expect(copied, 'alph');
    c.selectLines(1, 1);
    await tester.pumpAndSettle();
    await expectCopy(tester, 'second line');
  });
  testWidgets('source replacement clears native and line selections', (
    tester,
  ) async {
    final c = CodeViewController(
      sourceId: 'a',
      code: 'alpha beta\nsecond line',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(app(view(c)));
    await tester.pumpAndSettle();
    await drag(tester, 'alpha beta', 0, 4);
    c.setCode('new bytes', revision: 1);
    await tester.pumpAndSettle();
    expect(c.selection, isNull);
    final delegate = tester
        .widgetList<SelectionContainer>(find.byType(SelectionContainer))
        .map((w) => w.delegate)
        .whereType<CodeSelectionDelegate>()
        .single;
    expect(delegate.getSelectedContent(), isNull);
    expect(text('new bytes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'markers stay in gutters and backgrounds span wrapped source lines',
    (tester) async {
      final long = 'wrapped prose ' * 100;
      final c = CodeViewController(
        sourceId: 'knowledge',
        code: 'first\n$long\nlast',
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          view(
            c,
            wrap: true,
            gutter: (_, line) =>
                line == 1 ? const Text('!', key: Key('finding')) : null,
            background: (line) => line == 1 ? const Color(0xff123456) : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final band = tester.getRect(row(long));
      expect(band.height, greaterThan(21));
      expect(tester.getTopLeft(find.byKey(const Key('finding'))).dy, band.top);
      expect(tester.getRect(row('last')).top, band.bottom);
      expect(
        tester.widget<ColoredBox>(row(long)).color,
        const Color(0xff123456),
      );
      c.selectLines(1, 1);
      await tester.pumpAndSettle();
      await expectCopy(tester, long);
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      await expectCopy(tester, c.code);
    },
  );
  for (final (name, start, end, target) in [
    ('wrapped middle', 100, 200, 500),
    ('very long first line', 0, 1, 100),
  ]) {
    testWidgets('queued reveal passes $name with bounded row work', (
      tester,
    ) async {
      final lines = [
        for (var i = 0; i < 1000; i++)
          i >= start && i < end ? 'wrapped $i ${'long ' * 2000}' : 'line $i',
      ];
      final c = CodeViewController(sourceId: 'large', code: lines.join('\n'))
        ..selectLines(target, target)
        ..revealLine(target);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(
          view(
            c,
            wrap: true,
            gutter: (_, line) =>
                line == target ? const Text('!', key: Key('target')) : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(HighlightedCode));
      expect(
        bounds.contains(tester.getRect(text('line $target')).center),
        isTrue,
      );
      expect(find.byKey(const Key('target')), findsOneWidget);
      expect(find.byType(CodeBlock).evaluate().length, lessThan(100));
      expect(tester.takeException(), isNull);
      c.revealLine(999);
      await tester.pumpAndSettle();
      expect(bounds.overlaps(tester.getRect(text('line 999'))), isTrue);
      c.revealLine(target);
      await tester.pumpAndSettle();
      expect(
        bounds.contains(tester.getRect(text('line $target')).center),
        isTrue,
      );
    });
  }
  testWidgets('repeated reveal and controller replacement are observed', (
    tester,
  ) async {
    final first = CodeViewController(
      sourceId: 'a',
      code: List.generate(5000, (i) => 'line $i').join('\n'),
    )..revealLine(4000);
    final second = CodeViewController(sourceId: 'b', code: 'replacement');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(app(view(first)));
    await tester.pumpAndSettle();
    expect(text('line 4000'), findsOneWidget);
    final viewport = tester.widget<IndexedCodeViewport>(
      find.byType(IndexedCodeViewport),
    );
    viewport.controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(text('line 4000'), findsNothing);
    first.revealLine(4000);
    await tester.pumpAndSettle();
    expect(text('line 4000'), findsOneWidget);
    await tester.pumpWidget(app(view(second)));
    await tester.pumpAndSettle();
    first.selectLines(0, 1);
    await tester.pumpAndSettle();
    expect(text('replacement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('slots also work without a controller and copy exact source', (
    tester,
  ) async {
    const source = 'a\r\nb\u2028c\r\n\r\nlast\r';
    await tester.pumpWidget(
      app(
        HighlightedCode(
          source,
          language: 'text',
          theme: githubDarkTheme,
          highlighter: Highlighter(),
          softWrap: true,
          lineNumbers: true,
          gutterBuilder: (_, line) => const Text('marker'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
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
    Actions.invoke(
      tester.element(find.byType(CodeBlock).first),
      CopySelectionTextIntent.copy,
    );
    await tester.pump();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    expect(copied, source);
  });

  testWidgets(
    'native drag across virtual rows copies offscreen lines exactly',
    (tester) async {
      final lines = List.generate(2000, (i) => 'line $i');
      final c = CodeViewController(sourceId: 'a', code: lines.join('\r\n'));
      addTearDown(c.dispose);
      await tester.pumpWidget(app(view(c)));
      await tester.pumpAndSettle();
      Offset at(int line, int column) {
        final p = tester.renderObject<RenderParagraph>(text(lines[line]));
        return p.localToGlobal(
          p.getOffsetForCaret(TextPosition(offset: column), Rect.zero) +
              const Offset(0, 10),
        );
      }

      final gesture = await tester.startGesture(
        at(2, 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(at(3, 3));
      await tester.pump();
      final scroll = tester
          .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
          .controller;
      await gesture.moveTo(const Offset(400, 595));
      for (var i = 0; i < 1000 && scroll.offset < 1200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, greaterThanOrEqualTo(1200));
      final visible =
          tester
              .widgetList<CodeBlock>(find.byType(CodeBlock))
              .map((b) => b.index)
              .toList()
            ..sort();
      final end = visible[visible.length ~/ 2];
      await gesture.moveTo(at(end, 4));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final expected = [
        lines[2].substring(2),
        ...lines.sublist(3, end),
        lines[end].substring(0, 4),
      ].join('\r\n');
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
      for (final offset in [
        scroll.offset,
        scroll.position.maxScrollExtent,
        0.0,
      ]) {
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        Actions.invoke(
          tester.element(find.byType(CodeBlock).first),
          CopySelectionTextIntent.copy,
        );
        await tester.pump();
        expect(copied, expected);
      }
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      expect(find.byType(CodeBlock).evaluate().length, lessThan(150));
    },
  );

  testWidgets(
    'select-all copies unmounted lines and source revision clears it',
    (tester) async {
      final c = CodeViewController(
        sourceId: 'a',
        code: List.generate(2000, (i) => 'row $i').join('\n'),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(view(c)));
      await tester.pumpAndSettle();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      final delegate = tester
          .widgetList<SelectionContainer>(find.byType(SelectionContainer))
          .map((w) => w.delegate)
          .whereType<CodeSelectionDelegate>()
          .single;
      expect(delegate.getSelectedContent()!.plainText, c.code);
      c.setCode(c.code, revision: 1);
      await tester.pumpAndSettle();
      expect(delegate.getSelectedContent(), isNull);
    },
  );

  testWidgets('unbounded view reveals through the containing scroll view', (
    tester,
  ) async {
    final c = CodeViewController(
      sourceId: 'a',
      code: List.generate(300, (i) => 'line $i').join('\n'),
    )..revealLine(250);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: Column(children: [const SizedBox(height: 180), view(c)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(MaterialApp));
    expect(bounds.contains(tester.getRect(text('line 250')).center), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gutter drag autoscrolls and stops on release', (tester) async {
    final c = CodeViewController(
      sourceId: 'a',
      code: List.generate(500, (i) => 'row $i').join('\n'),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(app(view(c)));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      gutter(tester, 'row 1'),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(const Offset(20, 595));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final scroll = tester
        .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
        .controller;
    expect(scroll.offset, greaterThan(0));
    expect(c.selection!.active, greaterThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    final stopped = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, stopped);
  });
}
