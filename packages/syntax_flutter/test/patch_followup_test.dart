import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'patch_composition_test.dart'
    show app, caret, copy, gutter, select, selection;

void main() {
  for (final reverse in [false, true]) {
    testWidgets(
      'native endpoints preserve empty boundary cells reverse=$reverse',
      (tester) async {
        await tester.pumpWidget(
          app(
            PatchView.fromTexts(
              oldText: '',
              newText: 'alpha\nbeta\ngamma',
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              path: 'a.txt',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await select(
          tester,
          reverse ? 'gamma' : 'alpha',
          reverse ? 0 : 2,
          reverse ? 'alpha' : 'gamma',
          reverse ? 2 : 0,
        );
        await copy(tester, 'pha\nbeta\n');
        expect(
          selection(tester).retainedRows.value,
          contains(('a.txt\u0000a.txt', 'new', 3)),
        );
        expect(selection(tester).retainedRows.value, hasLength(2));
        await select(tester, 'alpha', 5, 'gamma', 0);
        await copy(tester, '\nbeta\n');
        await tester.tapAt(caret(tester, 'gamma', 0));
        await tester.pumpAndSettle();
        expect(selection(tester).getSelectedContent(), isNull);
      },
    );
  }

  testWidgets('expanded source and cross-side gutter copy preserve CRLF', (
    tester,
  ) async {
    final file = diffTexts(
      'alpha\r\nbeta\r\ngamma\r\ndelta',
      'alpha\r\nBETA\r\ngamma\r\ndelta',
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    await select(tester, 'gamma', 1, 'delta', 2);
    await copy(tester, 'amma\r\nde');
    await tester.tapAt(gutter(tester, 'alpha', old: true));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(gutter(tester, 'delta'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await copy(tester, 'alpha\r\nbeta\r\nBETA\r\ngamma\r\ndelta');
  });

  testWidgets(
    'section image resolves asynchronously and repaints without rebuilding',
    (tester) async {
      final image = _DelayedImage();
      final boundary = GlobalKey();
      var builds = 0;
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: PatchView.fromTexts(
              oldText: '',
              newText: 'alpha',
              path: 'a.txt',
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              sectionDecoration: BoxDecoration(
                image: DecorationImage(image: image, fit: BoxFit.fill),
              ),
              fileFooterBuilder: (_, _, _) {
                builds++;
                return const SizedBox(height: 30);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final before = builds;
      final footer = tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 30,
        ),
      );
      Future<Color> pixel() async {
        final raster = (await tester.runAsync(
          () => tester
              .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
              .toImage(),
        ))!;
        final data = (await tester.runAsync(
          () => raster.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final offset =
            (footer.center.dy.floor() * raster.width +
                footer.center.dx.floor()) *
            4;
        final color = Color.fromARGB(
          data.getUint8(offset + 3),
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
        );
        raster.dispose();
        return color;
      }

      final initial = await pixel();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xffff00ff), BlendMode.src);
      final picture = recorder.endRecording();
      image.result.complete(ImageInfo(image: picture.toImageSync(1, 1)));
      picture.dispose();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(builds, before);
      expect(await pixel(), const Color(0xffff00ff));
      expect(initial, isNot(const Color(0xffff00ff)));
      await tester.pumpWidget(const SizedBox());
      image.dispose();
    },
  );

  testWidgets(
    '100000-line cross-side highlighting only reads mounted source rows',
    (tester) async {
      final lines = List.generate(100000, (i) => 'l$i');
      final source = lines.join('\n');
      final original = diffTexts(
        source,
        '$source\nadded',
        path: 'a.txt',
        contextLines: 0,
      );
      final counted = _CountedLines(original.newLines!);
      final file = original.copyWith(newLines: counted);
      final scroll = ScrollController();
      final pending = Completer<HighlightWindowResult>();
      DiffSelection? selected;
      await tester.pumpWidget(
        app(
          PatchView(
            files: [file],
            theme: githubDarkTheme,
            highlighter: Highlighter(),
            onSelectionChanged: (value) => selected = value,
            scrollController: scroll,
            wrap: false,
            expanded: const {(file: 0, hunk: 0)},
            executor:
                (
                  request, {
                  required highlighter,
                  required theme,
                  required cancellation,
                }) => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.text('1').first));
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent - 150);
      await tester.pumpAndSettle();
      final visible = find.byType(RichText).evaluate().where((element) {
        final text = (element.widget as RichText).text.toPlainText();
        final box = element.renderObject! as RenderBox;
        final y = box.localToGlobal(Offset.zero).dy;
        return RegExp(r'^l\d+$').hasMatch(text) && y > 40 && y < 200;
      }).toList();
      expect(visible, isNotEmpty);
      final last = (visible.last.widget as RichText).text.toPlainText();
      expect(int.parse(last.substring(1)), greaterThan(99000));
      counted.reads = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(
        tester.getCenter(find.text('${int.parse(last.substring(1)) + 1}').last),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(selected!.crossesSides, isTrue);
      debugPrint(
        'source reads during cross-side highlighting: ${counted.reads}',
      );
      expect(
        counted.reads,
        lessThan(1000),
        reason:
            'highlighting must not materialize the selected document per cell',
      );
      expect(find.byType(IndexedCodeViewport), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}

class _DelayedImage extends ImageProvider<_DelayedImage> {
  final result = Completer<ImageInfo>();
  late final stream = OneFrameImageStreamCompleter(result.future);
  ImageStreamCompleterHandle? _handle;
  void dispose() => _handle?.dispose();
  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _DelayedImage key,
    ImageErrorListener handleError,
  ) {
    _handle ??= this.stream.keepAlive();
    stream.setCompleter(this.stream);
  }
}

class _CountedLines extends ListBase<String> {
  _CountedLines(this.source);
  final List<String> source;
  int reads = 0;
  // Syntax window indexing walks the source once. Count random row reads,
  // which detect range materialization through DiffLayout's context factory.
  @override
  Iterator<String> get iterator => source.iterator;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  String operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('immutable');
}
