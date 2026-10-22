import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/src/code_rows.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'code_helpers.dart';

final highlighter = Highlighter(languages: [dartLanguage]);

/// `var v0 = 0;`, `var v1 = 1;`, ...
List<String> numberedLines(int count) => [
  for (var i = 0; i < count; i++) 'var v$i = $i;',
];

/// A widget test that lets the code's tokenizing run out at the end.
void testCode(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

Widget app(Widget child) => MaterialApp(
  home: HighlighterScope(highlighter: highlighter, child: child),
);

HighlightedCode code(
  List<String> lines, {
  bool lineNumbers = false,
  bool softWrap = false,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  BorderRadiusGeometry? borderRadius,
}) => HighlightedCode(
  lines.join('\n'),
  language: 'dart',
  theme: githubDarkTheme,
  lineNumbers: lineNumbers,
  softWrap: softWrap,
  padding: padding,
  borderRadius: borderRadius,
);

Finder block(int index) =>
    find.byWidgetPredicate((w) => w is CodeBlock && w.index == index);

/// The paragraph with a block's code; the gutter's comes first.
Finder codeOf(int index) =>
    find.descendant(of: block(index), matching: find.byType(RichText)).last;

Finder numbersOf(int index) =>
    find.descendant(of: block(index), matching: find.byType(RichText)).first;

List<int> builtLines(WidgetTester tester) =>
    shownLines(tester).keys.toList()..sort();

List<int> builtBlocks(WidgetTester tester) => [
  for (final block in tester.widgetList<CodeBlock>(find.byType(CodeBlock)))
    block.index,
];

ScrollableState scrollable(WidgetTester tester, AxisDirection direction) =>
    tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == direction,
      ),
    );

bool colored(TextSpan span) => span.children?.isNotEmpty ?? false;

/// Records text copied to the clipboard.
String? Function() recordClipboard(WidgetTester tester) {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
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
  return () => copied;
}

SelectableRegionState region(WidgetTester tester) =>
    tester.state<SelectableRegionState>(find.byType(SelectableRegion));

/// Copies the selection as the keyboard shortcut does, which keeps it.
Future<void> copy(WidgetTester tester) async {
  Actions.invoke(
    tester.element(
      find.byWidgetPredicate(
        (w) => w is SelectionContainer && w.delegate is CodeSelectionDelegate,
      ),
    ),
    CopySelectionTextIntent.copy,
  );
  await tester.pump();
}

void jumpToEnd(WidgetTester tester) {
  final position = scrollable(tester, AxisDirection.down).position;
  position.jumpTo(position.maxScrollExtent);
}

/// A point inside character [column] of line [line]. The test font's
/// glyphs are squares as wide as the font size, 14, and lines are 21 px.
Offset at(WidgetTester tester, int line, int column) =>
    tester.getTopLeft(codeOf(line ~/ linesPerBlock)) +
    Offset(column * 14 + 3, line % linesPerBlock * 21 + 10);

void main() {
  group('rows', () {
    testCode('long code builds only the lines on screen', (tester) async {
      await tester.pumpWidget(app(code(numberedLines(2000))));
      final built = builtLines(tester);
      expect(built.first, 0);
      // 600 px of 21 px lines, plus the list's cache, in blocks.
      expect(built.length, lessThanOrEqualTo(4 * linesPerBlock));
      expect(find.byType(ListView), findsOneWidget);
    });

    testCode('inside a scroll view, every line is built', (tester) async {
      await tester.pumpWidget(
        app(SingleChildScrollView(child: code(numberedLines(300)))),
      );
      expect(builtLines(tester).length, 300);
      expect(find.byType(ListView), findsNothing);
    });

    testCode('short code hugs its lines and keeps intrinsic sizes', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          Center(
            child: IntrinsicWidth(
              child: IntrinsicHeight(child: code(numberedLines(3))),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Three 21 px lines and 16 px of padding on each side.
      expect(tester.getSize(find.byType(HighlightedCode)).height, 3 * 21 + 32);
    });

    testCode('short code taller than its box scrolls', (tester) async {
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(height: 100, child: code(numberedLines(50))),
          ),
        ),
      );
      expect(builtLines(tester).length, 50);
      final vertical = scrollable(tester, AxisDirection.down).position;
      expect(vertical.maxScrollExtent, 50 * 21 - (100 - 32));
    });

    testCode('a large file is colored between frames, top first', (
      tester,
    ) async {
      final lines = numberedLines(8000);
      await tester.pumpWidget(app(code(lines)));
      expect(colored(shownLines(tester)[0]!), isTrue);

      jumpToEnd(tester);
      await tester.pump();
      bool lastColored() => colored(shownLines(tester)[7999]!);
      for (var i = 0; i < 1000 && !lastColored(); i++) {
        await tester.pump(Duration.zero);
      }
      expect(lastColored(), isTrue);
    });
  });

  group('line numbers', () {
    /// Each line's number sits on the line's baseline.
    Future<void> expectAligned(WidgetTester tester) async {
      final blocks = builtBlocks(tester);
      expect(blocks, isNotEmpty);
      for (final index in blocks) {
        final code = tester.renderObject<RenderParagraph>(codeOf(index));
        final numbers = tester.renderObject<RenderParagraph>(numbersOf(index));
        final codeText = code.text.toPlainText();
        final numberText = numbers.text.toPlainText();
        final count = '\n'.allMatches(codeText).length + 1;
        final first = index * linesPerBlock;
        expect(
          numberText,
          [for (var i = 0; i < count; i++) '${first + i + 1}'].join('\n'),
        );
        double lineTop(RenderParagraph paragraph, String text, int line) {
          var offset = 0;
          for (var i = 0; i < line; i++) {
            offset = text.indexOf('\n', offset) + 1;
          }
          final caret = paragraph.getOffsetForCaret(
            TextPosition(offset: offset),
            Rect.zero,
          );
          return paragraph.localToGlobal(caret).dy;
        }

        for (var line = 0; line < count; line++) {
          expect(
            lineTop(numbers, numberText, line),
            lineTop(code, codeText, line),
          );
        }
      }
    }

    testCode('stay aligned with their lines', (tester) async {
      await tester.pumpWidget(app(code(numberedLines(20), lineNumbers: true)));
      await expectAligned(tester);
    });

    testCode('stay aligned with their lines after scrolling', (tester) async {
      await tester.pumpWidget(
        app(code(numberedLines(2000), lineNumbers: true)),
      );
      scrollable(tester, AxisDirection.down).position.jumpTo(1234.5 * 21);
      await tester.pump();
      expect(builtLines(tester).first, greaterThan(1000));
      expect(builtLines(tester).first % linesPerBlock, 0);
      await expectAligned(tester);
    });
  });

  group('long lines', () {
    final lines = ['x' * 200, ...numberedLines(3)];

    testCode('scroll sideways under fixed line numbers', (tester) async {
      await tester.pumpWidget(app(code(lines, lineNumbers: true)));
      final numberLeft = tester.getTopLeft(numbersOf(0)).dx;
      final codeLeft = tester.getTopLeft(codeOf(0)).dx;
      final horizontal = scrollable(tester, AxisDirection.right).position;
      // 200 characters, in an 800 px screen less padding and a 1-digit
      // gutter.
      final viewport = 800 - 32 - (14 + 16);
      expect(horizontal.maxScrollExtent, 200 * 14 - viewport);

      await tester.drag(find.byType(HighlightedCode), const Offset(-300, 0));
      await tester.pump();
      expect(horizontal.pixels, greaterThan(0));
      expect(tester.getTopLeft(numbersOf(0)).dx, numberLeft);
      expect(tester.getTopLeft(codeOf(0)).dx, codeLeft - horizontal.pixels);
    });

    testWidgets('grow the scroll when a row is wider than guessed', (
      tester,
    ) async {
      // The guess is the longest line by characters. A line that renders
      // wider, with wide characters, is found when it's laid out.
      final widths = LineWidths(300);
      final horizontal = ScrollController();
      final vertical = ScrollController();
      addTearDown(horizontal.dispose);
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Scrollable(
            axisDirection: AxisDirection.right,
            controller: horizontal,
            viewportBuilder: (context, offset) => HorizontalExtent(
              offset: offset,
              widths: widths,
              gutterWidth: 0,
              child: ListView.builder(
                controller: vertical,
                itemExtent: 20,
                itemCount: 100,
                itemBuilder: (context, index) => ShiftedCode(
                  offset: offset,
                  widths: widths,
                  child: SizedBox(width: index == 99 ? 1500 : 200),
                ),
              ),
            ),
          ),
        ),
      );
      expect(horizontal.position.maxScrollExtent, 0);
      vertical.jumpTo(vertical.position.maxScrollExtent);
      await tester.pump();
      // Picked up in the next frame.
      await tester.pump();
      expect(horizontal.position.maxScrollExtent, 1500 - 800);
    });

    testCode('softWrap wraps them instead', (tester) async {
      await tester.pumpWidget(app(code(lines, softWrap: true)));
      expect(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
        findsNothing,
      );
      // 200 squares of 14 px in 768 px make four lines, and three short
      // lines follow.
      expect(tester.getSize(codeOf(0)).height, (4 + 3) * 21);
    });

    testCode('softWrap wraps long code in a virtualized list', (tester) async {
      await tester.pumpWidget(
        app(code([...lines, ...numberedLines(2000)], softWrap: true)),
      );
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.getSize(codeOf(0)).height, (4 + linesPerBlock - 1) * 21);
    });
  });

  testCode('paints the theme background with padding and corners', (
    tester,
  ) async {
    final radius = BorderRadius.circular(8);
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: code(
            numberedLines(3),
            padding: const EdgeInsets.fromLTRB(24, 12, 8, 4),
            borderRadius: radius,
          ),
        ),
      ),
    );
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(HighlightedCode),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, githubDarkTheme.backgroundColor);
    expect(decoration.borderRadius, radius);
    expect(tester.getTopLeft(codeOf(0)), const Offset(24, 12));
    expect(tester.getSize(find.byType(HighlightedCode)).height, 3 * 21 + 16);
  });

  testCode('code reads left to right in a right-to-left app', (tester) async {
    await tester.pumpWidget(
      app(
        Directionality(
          textDirection: TextDirection.rtl,
          child: code(numberedLines(2000), lineNumbers: true),
        ),
      ),
    );
    expect(Directionality.of(tester.element(codeOf(0))), TextDirection.ltr);
    expect(
      tester.getTopLeft(numbersOf(0)).dx,
      lessThan(tester.getTopLeft(codeOf(0)).dx),
    );
    expect(tester.getTopLeft(codeOf(0)).dx, 16 + 4 * 14 + 16);
  });

  testCode('a change re-tokenizes only the changed line', (tester) async {
    final lines = numberedLines(50);
    await tester.pumpWidget(app(code(lines)));
    final before = shownLines(tester);
    await tester.pumpWidget(app(code([...lines]..[25] = 'final changed = 1;')));
    final after = shownLines(tester);
    expect(after.keys, before.keys);
    for (final MapEntry(key: line, value: span) in after.entries) {
      if (line == 25) {
        expect(span.toPlainText(), 'final changed = 1;');
        expect(identical(span, before[25]), isFalse);
      } else {
        expect(identical(span, before[line]), isTrue);
      }
    }
  });

  testCode('ignores the screen padding a list would add', (tester) async {
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(top: 40, bottom: 30),
          ),
          child: code(numberedLines(2000)),
        ),
      ),
    );
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.getTopLeft(codeOf(0)).dy, 16);
  });

  testCode('characters a paragraph breaks on stay in their line', (
    tester,
  ) async {
    final lines = numberedLines(2000)
      ..[3] = 'a b\u000Cc\rd'
      ..[4] = '';
    await tester.pumpWidget(app(code(lines, lineNumbers: true)));
    final paragraph = tester.renderObject<RenderParagraph>(codeOf(0));
    // The block's last line is where 32 lines of 21 px put it.
    final last = paragraph.text.toPlainText().lastIndexOf('\n') + 1;
    expect(
      paragraph.getOffsetForCaret(TextPosition(offset: last), Rect.zero).dy,
      (linesPerBlock - 1) * 21,
    );
    expect(tester.getSize(codeOf(0)).height, linesPerBlock * 21);
  });

  testCode('stays selectable when line numbers are turned on', (tester) async {
    final copied = recordClipboard(tester);
    final lines = numberedLines(20);
    await tester.pumpWidget(app(code(lines)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(code(lines, lineNumbers: true)));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      at(tester, 1, 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(at(tester, 2, 3));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await copy(tester);
    expect(copied(), '${lines[1].substring(2)}\n${lines[2].substring(0, 3)}');
  });

  testCode('copying text with a separator copies it as it is', (tester) async {
    final copied = recordClipboard(tester);
    await tester.pumpWidget(app(code(['a b', 'c'])));
    await tester.pumpAndSettle();
    region(tester).selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    await copy(tester);
    expect(copied(), 'a b\nc');
  });

  group('copying', () {
    testCode('a drag across lines copies them with line breaks', (
      tester,
    ) async {
      final copied = recordClipboard(tester);
      final lines = numberedLines(10);
      await tester.pumpWidget(app(code(lines, lineNumbers: true)));
      // The selection containers finish registering in later frames.
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        at(tester, 2, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(at(tester, 5, 3));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await copy(tester);
      expect(
        copied(),
        '${lines[2].substring(4)}\n${lines[3]}\n${lines[4]}\n'
        '${lines[5].substring(0, 3)}',
      );
    });

    testCode('select all copies every line of long code', (tester) async {
      final copied = recordClipboard(tester);
      final lines = numberedLines(2000);
      await tester.pumpWidget(app(code(lines)));
      await tester.pumpAndSettle();
      region(tester).selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      await copy(tester);
      expect(copied(), lines.join('\n'));
    });

    testCode('a drag that scrolls copies the lines scrolled past', (
      tester,
    ) async {
      final copied = recordClipboard(tester);
      final lines = numberedLines(2000);
      await tester.pumpWidget(app(code(lines)));
      await tester.pumpAndSettle();
      final vertical = scrollable(tester, AxisDirection.down).position;

      final gesture = await tester.startGesture(
        at(tester, 2, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(at(tester, 3, 2));
      await tester.pump();
      // Holding the pointer below the code scrolls it.
      await gesture.moveTo(const Offset(400, 595));
      for (var i = 0; i < 1000 && vertical.pixels < 1200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(vertical.pixels, greaterThanOrEqualTo(1200));
      final built = builtLines(tester);
      expect(built, isNot(contains(2)));
      final end = built[built.length ~/ 2];
      await gesture.moveTo(at(tester, end, 5));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final expected = [
        lines[2].substring(4),
        ...lines.sublist(3, end),
        lines[end].substring(0, 5),
      ].join('\n');
      await copy(tester);
      expect(copied(), expected);

      // Scrolled away from every selected line, and back to the top.
      for (final offset in [vertical.maxScrollExtent, 0.0]) {
        vertical.jumpTo(offset);
        await tester.pump();
        await copy(tester);
        expect(copied(), expected);
      }
    });
  });
}
