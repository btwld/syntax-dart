import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/src/diff_text_selection.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

Widget app(Widget child, {double height = 260}) => WidgetsApp(
  color: const Color(0xff000000),
  onGenerateRoute: (_) => PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 600, height: height, child: child),
    ),
  ),
);

Offset caret(WidgetTester tester, String text, int column) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(text, findRichText: true),
  );
  return paragraph.localToGlobal(
    paragraph.getOffsetForCaret(TextPosition(offset: column), Rect.zero) +
        const Offset(0, 7),
  );
}

Future<void> select(
  WidgetTester tester,
  String first,
  int from,
  String last,
  int to,
) async {
  final gesture = await tester.startGesture(
    caret(tester, first, from),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(caret(tester, last, to));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

DiffTextSelection selection(WidgetTester tester) => tester
    .widget<DiffSelectableCell>(find.byType(DiffSelectableCell).first)
    .selection;

Future<void> copy(WidgetTester tester, String expected) async {
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
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  expect(copied, expected);
}

Offset gutter(
  WidgetTester tester,
  String text, {
  bool old = false,
  bool split = false,
}) {
  final at = caret(tester, text, 0);
  return Offset(at.dx - (old && !split ? 65 : 35), at.dy);
}

void main() {
  testWidgets(
    'native copy skips introduction, labels, footers, notices and annotations',
    (tester) async {
      final first = diffTexts('', 'alpha one\nbeta two', path: 'first.txt');
      final last = diffTexts('', 'gamma three\ndelta four', path: 'last.txt');
      await tester.pumpWidget(
        app(
          PatchView<String>(
            files: [
              first,
              const FileDiff(
                oldPath: 'image.png',
                newPath: 'image.png',
                kind: FileDiffKind.modified,
                hunks: [],
                isBinary: true,
              ),
              last,
            ],
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            padding: EdgeInsets.zero,
            leading: const Text('Review introduction'),
            hunkBuilder: (_, _, _) => const Text('Hunk header'),
            fileLabelBuilder: (_, _) => const Text('File label'),
            fileFooterBuilder: (_, _, _) => const Text('Load diff'),
            annotations: [
              DiffAnnotation(
                id: 'a',
                fileId: first.id,
                revision: first.revision,
                side: DiffSide.newer,
                line: 1,
                data: 'inline comment',
              ),
            ],
            rowBelowBuilder: (_, row) => row.annotations.isEmpty
                ? null
                : Text(row.annotations.single.data),
            shrinkWrap: true,
          ),
          height: 600,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('inline comment'), findsOneWidget);
      expect(find.text('Load diff'), findsNWidgets(3));
      await select(tester, 'alpha one', 3, 'delta four', 5);
      await copy(tester, 'ha one\nbeta two\ngamma three\ndelta');
    },
  );

  testWidgets('split native selection follows the starting side', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PatchView.fromTexts(
          oldText: 'old alpha\nold beta\nold gamma',
          newText: 'new alpha\nnew beta\nnew gamma',
          path: 'a.txt',
          highlighter: Highlighter(),
          theme: githubDarkTheme,
          mode: DiffMode.split,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await select(tester, 'old alpha', 4, 'old gamma', 7);
    await copy(tester, 'alpha\nold beta\nold gam');
    await select(tester, 'new alpha', 4, 'new gamma', 7);
    expect(selection(tester).activeSide.value, DiffSide.newer);
    await copy(tester, 'alpha\nnew beta\nnew gam');
    await select(tester, 'old alpha', 4, 'new gamma', 7);
    expect(selection(tester).activeSide.value, DiffSide.old);
    expect(
      selection(tester).getSelectedContent()!.plainText,
      isNot(contains('new')),
    );
  });

  for (final upward in [false, true]) {
    testWidgets('native selection crosses virtual screens upward=$upward', (
      tester,
    ) async {
      final lines = List.generate(1500, (i) => 'code row $i;');
      final scroll = ScrollController();
      await tester.pumpWidget(
        app(
          PatchView.fromTexts(
            oldText: '',
            newText: lines.join('\n'),
            path: 'a.txt',
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            scrollController: scroll,
            wrap: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (upward) {
        scroll.jumpTo(10000);
        await tester.pumpAndSettle();
      }
      final viewport = tester.getRect(find.byType(IndexedCodeViewport));
      final initialCells = find
          .byType(DiffSelectableCell, skipOffstage: false)
          .evaluate()
          .length;
      final visible = find.byType(RichText).evaluate().where((e) {
        final text = (e.widget as RichText).text.toPlainText();
        final box = e.renderObject! as RenderBox;
        final y = box.localToGlobal(Offset.zero).dy;
        return text.startsWith('code row ') &&
            y > viewport.top + 40 &&
            y + box.size.height < viewport.bottom - 40;
      }).toList();
      final text = (visible[visible.length ~/ 2].widget as RichText).text
          .toPlainText();
      final startOffset = scroll.offset;
      final gesture = await tester.startGesture(
        caret(tester, text, upward ? text.length : 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var i = 0; i < 100; i++) {
        await gesture.moveTo(
          Offset(
            viewport.right - 20,
            upward ? viewport.top - 40 - i % 2 : viewport.bottom + 40 + i % 2,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        (scroll.offset - startOffset).abs(),
        greaterThan(viewport.height * 3),
      );
      final selected = selection(tester).getSelectedContent()!.plainText;
      final numbers = RegExp(
        r'code row (\d+);',
      ).allMatches(selected).map((m) => int.parse(m[1]!)).toList();
      expect(numbers.length, greaterThan(30));
      expect(
        selected,
        lines.sublist(numbers.first, numbers.last + 1).join('\n'),
      );
      await copy(tester, selected);
      expect(selection(tester).retainedRows.value.length, 2);
      expect(
        find.byType(DiffSelectableCell, skipOffstage: false).evaluate().length,
        lessThanOrEqualTo(initialCells * 2 + 4),
      );
      final middleOffset = (startOffset + scroll.offset) / 2;
      while ((scroll.offset - middleOffset).abs() > .1) {
        scroll.jumpTo(
          scroll.offset + (middleOffset - scroll.offset).clamp(-40, 40),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(selection(tester).getSelectedContent()!.plainText, selected);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    });
  }

  testWidgets(
    'gutter selection retains direction, extends with Shift and crosses sides',
    (tester) async {
      DiffSelection? selected;
      DiffSelectionDetails? details;
      await tester.pumpWidget(
        app(
          PatchView.fromTexts(
            oldText: 'old alpha\nold beta\nold gamma',
            newText: 'new alpha\nnew beta\nnew gamma',
            path: 'a.txt',
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            mode: DiffMode.split,
            onSelectionChanged: (value) => selected = value,
            selectionActionBuilder: (_, value) {
              details = value;
              return const Text('Action');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        gutter(tester, 'old gamma', split: true),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(gutter(tester, 'old alpha', split: true));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected!.side, DiffSide.old);
      expect(selected!.anchor, 3);
      expect(selected!.active, 1);
      await copy(tester, 'old alpha\nold beta\nold gamma');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(gutter(tester, 'new beta', split: true));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(selected!.anchor, 3);
      expect(selected!.active, 2);
      expect(selected!.crossesSides, isTrue);
      expect(details!.selectedText, 'old gamma\nnew alpha\nnew beta');
      await copy(tester, details!.selectedText);
      await select(tester, 'new alpha', 1, 'new gamma', 2);
      expect(selected, isNull);
    },
  );

  testWidgets(
    'draft annotations ignore live selection, reject stale revisions and preserve measured rows',
    (tester) async {
      final file = diffTexts(
        '',
        List.generate(400, (i) => 'line $i').join('\n'),
        path: 'a.txt',
        revision: 4,
      );
      final files = [file];
      final scroll = ScrollController();
      var annotations = <DiffAnnotation<String>>[];
      late StateSetter update;
      var mounted = 0;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return PatchView<String>(
                files: files,
                theme: githubDarkTheme,
                highlighter: Highlighter(),
                scrollController: scroll,
                annotations: annotations,
                gutterBuilder: (_, line) =>
                    line.line == 101 ? const Text('!') : null,
                rowBelowBuilder: (_, row) => row.annotations.isEmpty
                    ? null
                    : _Draft(
                        key: const ValueKey('draft'),
                        onMount: () => mounted++,
                        text: row.annotations.single.data,
                      ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(2000);
      await tester.pumpAndSettle();
      final visible = find
          .byType(RichText)
          .evaluate()
          .where(
            (e) =>
                (e.widget as RichText).text.toPlainText().startsWith('line '),
          )
          .toList();
      final text = (visible[visible.length ~/ 2].widget as RichText).text
          .toPlainText();
      final number = int.parse(text.substring(5)) + 1;
      final y = tester.getTopLeft(find.text(text, findRichText: true)).dy;
      final offset = scroll.offset;
      update(
        () => annotations = [
          DiffAnnotation(
            id: 'draft',
            fileId: file.id,
            revision: 4,
            side: DiffSide.newer,
            line: number,
            data: 'App draft',
          ),
          DiffAnnotation(
            id: 'stale',
            fileId: file.id,
            revision: 3,
            side: DiffSide.newer,
            line: number,
            data: 'stale draft',
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('App draft'), findsOneWidget);
      expect(find.text('stale draft'), findsNothing);
      expect(scroll.offset, closeTo(offset, .1));
      expect(
        tester.getTopLeft(find.text(text, findRichText: true)).dy,
        closeTo(y, .1),
      );
      update(() {});
      await tester.pumpAndSettle();
      expect(mounted, 1);
      await tester.tapAt(gutter(tester, text));
      await tester.pumpAndSettle();
      expect(find.text('App draft'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets('footers include binary and folded files and stay virtual', (
    tester,
  ) async {
    final files = [
      const FileDiff(
        oldPath: 'image.png',
        newPath: 'image.png',
        kind: FileDiffKind.modified,
        hunks: [],
        isBinary: true,
      ),
      for (var i = 0; i < 70; i++) diffTexts('old$i', 'new$i', path: 'f$i'),
    ];
    final scroll = ScrollController();
    await tester.pumpWidget(
      app(
        PatchView(
          files: files,
          collapsed: const {1},
          theme: githubDarkTheme,
          highlighter: Highlighter(),
          scrollController: scroll,
          fileFooterBuilder: (_, file, collapsed) =>
              Text('Footer ${file.path}: $collapsed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Footer image.png: false'), findsOneWidget);
    expect(find.text('Footer f0: true'), findsOneWidget);
    expect(find.text('old0', findRichText: true), findsNothing);
    expect(find.text('Footer f69: false'), findsNothing);
    final viewport = tester.widget<IndexedCodeViewport>(
      find.byType(IndexedCodeViewport),
    );
    final lastRow = layoutDiff(files, collapsed: {1}).length - 1;
    // Use the viewport's existing reveal contract to exercise a distant footer.
    expect(viewport.count, lastRow + 1);
    for (
      var i = 0;
      i < 12 && find.text('Footer f69: false').evaluate().isEmpty;
      i++
    ) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(find.text('Footer f69: false'), findsOneWidget);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Footer f0: true'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('leading content scrolls before a decorated pinned header', (
    tester,
  ) async {
    final scroll = ScrollController();
    final boundary = GlobalKey();
    const canvas = Color(0xff0a0a0a);
    const borderColor = Color(0xffff00ff);
    await tester.pumpWidget(
      app(
        RepaintBoundary(
          key: boundary,
          child: PatchView.fromTexts(
            oldText: '',
            newText: List.generate(200, (i) => 'line $i').join('\n'),
            path: 'a.txt',
            theme: githubDarkTheme,
            highlighter: Highlighter(),
            scrollController: scroll,
            leading: const SizedBox(height: 100, child: Text('Introduction')),
            stickyHeaders: true,
            padding: EdgeInsets.zero,
            canvasColor: canvas,
            sectionDecoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsOneWidget);
    scroll.jumpTo(40);
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsOneWidget);
    scroll.jumpTo(1200);
    await tester.pumpAndSettle();
    final header = find.text('a.txt').hitTestable();
    expect(header, findsOneWidget);
    final image = (await tester.runAsync(
      () => tester
          .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
          .toImage(),
    ))!;
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    Color pixel(int x, int y) {
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        data.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
    }

    expect(pixel(0, 0), canvas);
    expect(pixel(image.width - 1, 0), canvas);
    expect(pixel(image.width ~/ 2, 0), borderColor);
    expect(pixel(0, 20), borderColor);
    expect(pixel(image.width - 1, 20), borderColor);
    image.dispose();
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
  testWidgets('gutter slots reserve width and visible ranges are forwarded', (
    tester,
  ) async {
    var showMarker = false;
    late StateSetter update;
    final ranges = <(int, int)>[];
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return PatchView.fromTexts(
              oldText: '',
              newText: 'alpha\nbeta',
              path: 'a.txt',
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              leading: const SizedBox(height: 30),
              gutterBuilder: (_, line) =>
                  showMarker && line.line == 1 ? const Text('!') : null,
              onVisibleRange: (start, end) => ranges.add((start, end)),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final x = caret(tester, 'alpha', 0).dx;
    update(() => showMarker = true);
    await tester.pumpAndSettle();
    expect(caret(tester, 'alpha', 0).dx, x);
    expect(find.text('!'), findsOneWidget);
    expect(ranges, isNotEmpty);
    final viewport = tester.widget<IndexedCodeViewport>(
      find.byType(IndexedCodeViewport),
    );
    expect(ranges.last.$1, 0);
    expect(ranges.last.$2, viewport.count);
  });

  testWidgets('native and gutter copies preserve CRLF and wrapped source lines', (
    tester,
  ) async {
    const long =
        'a long source line that wraps into several visual rows but stays one source line';
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 280,
          child: PatchView.fromTexts(
            oldText: '',
            newText: '$long\r\nbeta two\r\ngamma three',
            path: 'a.txt',
            theme: githubDarkTheme,
            highlighter: Highlighter(),
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await select(tester, long, 3, 'gamma three', 2);
    await copy(tester, '${long.substring(3)}\r\nbeta two\r\nga');
    final gesture = await tester.startGesture(
      gutter(tester, long),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(gutter(tester, 'gamma three'));
    await gesture.up();
    await tester.pumpAndSettle();
    await copy(tester, '$long\r\nbeta two\r\ngamma three');
  });

  testWidgets(
    'section decoration joins rows, rounds file edges and closes folded headers',
    (tester) async {
      const canvas = Color(0xff0a0a0a);
      const borderColor = Color(0xffff00ff);
      final boundary = GlobalKey();
      final files = [
        diffTexts('', 'alpha\nbeta', path: 'first.txt'),
        diffTexts('', 'gamma\ndelta', path: 'last.txt'),
      ];
      var collapsed = <int>{};
      late StateSetter update;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return RepaintBoundary(
                key: boundary,
                child: PatchView(
                  files: files,
                  theme: githubDarkTheme,
                  highlighter: Highlighter(),
                  padding: EdgeInsets.zero,
                  canvasColor: canvas,
                  collapsed: collapsed,
                  leading: const SizedBox(height: 30),
                  sectionDecoration: BoxDecoration(
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
          ),
          height: 500,
        ),
      );
      await tester.pumpAndSettle();
      Future<Color Function(int, int)> pixels() async {
        final image = (await tester.runAsync(
          () => tester
              .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
              .toImage(),
        ))!;
        final data = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final width = image.width;
        image.dispose();
        return (int x, int y) {
          final i = (y * width + x) * 4;
          return Color.fromARGB(
            data.getUint8(i + 3),
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          );
        };
      }

      var pixel = await pixels();
      final y = tester
          .getRect(find.text('beta', findRichText: true))
          .center
          .dy
          .round();
      expect(pixel(0, y), borderColor);
      expect(pixel(599, y), borderColor);
      expect(pixel(0, 30), canvas);
      expect(pixel(599, 30), canvas);
      expect(pixel(300, 30), borderColor);
      final secondTop = tester.getRect(find.text('last.txt')).top.floor();
      final bottomEdges = [
        for (var at = y + 1; at < secondTop; at++)
          if (pixel(300, at) == borderColor) at,
      ];
      expect(bottomEdges, isNotEmpty);
      expect(pixel(300, bottomEdges.first + 2), canvas);
      expect(pixel(0, bottomEdges.first), canvas);
      update(() => collapsed = {0});
      await tester.pumpAndSettle();
      expect(find.text('alpha', findRichText: true), findsNothing);
      pixel = await pixels();
      final center = tester.getRect(find.text('first.txt')).center.dy.round();
      expect(pixel(0, center), borderColor);
      expect(pixel(599, center), borderColor);
      expect([
        for (var y = center + 1; y < center + 50; y++) pixel(300, y),
      ], contains(borderColor));
    },
  );
  testWidgets('cross-side gutter copy includes expanded context gaps', (
    tester,
  ) async {
    DiffSelectionDetails? details;
    final file = diffTexts(
      'alpha\nbeta\ngamma\ndelta',
      'alpha\nBETA\ngamma\ndelta',
      path: 'a.txt',
      contextLines: 0,
    );
    await tester.pumpWidget(
      app(
        PatchView(
          files: [file],
          theme: githubDarkTheme,
          highlighter: Highlighter(),
          expanded: const {(file: 0, hunk: 0), (file: 0, hunk: 1)},
          selectionActionBuilder: (_, value) {
            details = value;
            return const Text('Action');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(gutter(tester, 'alpha', old: true));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(gutter(tester, 'delta'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(details!.selection.side, DiffSide.old);
    expect(details!.selection.activeSide, DiffSide.newer);
    await copy(tester, 'alpha\nbeta\nBETA\ngamma\ndelta');
  });
}

class _Draft extends StatefulWidget {
  const _Draft({super.key, required this.onMount, required this.text});
  final VoidCallback onMount;
  final String text;
  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 91, child: Text(widget.text));
}
