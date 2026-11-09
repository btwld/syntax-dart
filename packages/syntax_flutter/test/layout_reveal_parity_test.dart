import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app;

String line(int n, {bool long = false}) =>
    long ? 'line $n alpha beta gamma delta' : 'line $n';
FileDiff file({int count = 300, bool long = false}) => diffTexts(
  '',
  List.generate(count, (i) => line(i + 1, long: long)).join('\n'),
  path: 'a.txt',
);

void visible(WidgetTester tester, Finder target, {double height = 260}) {
  expect(target, findsOneWidget);
  final rect = tester.getRect(target);
  debugPrint('visible target: $rect');
  expect(rect.top, greaterThanOrEqualTo(-.1));
  expect(rect.bottom, lessThanOrEqualTo(height + .1));
}

Future<void> codeResize(
  WidgetTester tester, {
  required bool widthChange,
}) async {
  final controller = CodeViewController(
    sourceId: 'a',
    code: List.generate(300, (i) => line(i + 1, long: widthChange)).join('\n'),
  );
  addTearDown(controller.dispose);
  final highlighter = Highlighter();
  late StateSetter update;
  var font = 14.0;
  var width = 600.0;
  await tester.pumpWidget(
    app(
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 260,
              child: HighlightedCode.controlled(
                controller: controller,
                language: 'text',
                theme: githubDarkTheme,
                highlighter: highlighter,
                softWrap: widthChange,
                padding: EdgeInsets.zero,
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: font,
                  height: 1.5,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.revealLine(99);
  await tester.pumpAndSettle();
  final target = find.text(line(100, long: widthChange), findRichText: true);
  visible(tester, target);
  update(() {
    if (widthChange) {
      width = 280;
    } else {
      font = 28;
    }
  });
  await tester.pumpAndSettle();
  visible(tester, target);
  expectPlainTree(tester);
}

Future<void> zeroLeading(WidgetTester tester, bool shrinkWrap) async {
  final source = file();
  final controller = PatchController<void>([source]);
  addTearDown(controller.dispose);
  controller.revealLine(source.id, DiffSide.newer, 200, revision: 0);
  await tester.pumpWidget(
    app(
      PatchView<void>.controlled(
        controller: controller,
        highlighter: Highlighter(),
        theme: githubDarkTheme,
        padding: EdgeInsets.zero,
        shrinkWrap: shrinkWrap,
        leading: const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final target = find.text('line 200', findRichText: true);
  visible(tester, target);
  expect(tester.getTopLeft(target).dy, closeTo(0, .1));
  expectPlainTree(tester);
}

Future<void> ancestor(
  WidgetTester tester, {
  required bool listView,
  bool distant = false,
}) async {
  final source = file(count: distant ? 300 : 3);
  final controller = PatchController<void>([source]);
  final outer = ScrollController();
  addTearDown(controller.dispose);
  addTearDown(outer.dispose);
  final children = [
    const SizedBox(height: 600),
    SizedBox(
      height: 200,
      child: PatchView<void>.controlled(
        controller: controller,
        highlighter: Highlighter(),
        theme: githubDarkTheme,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
      ),
    ),
    const SizedBox(height: 600),
  ];
  await tester.pumpWidget(
    app(
      listView
          ? ListView(controller: outer, children: children)
          : SingleChildScrollView(
              controller: outer,
              child: Column(children: children),
            ),
      height: 600,
    ),
  );
  await tester.pumpAndSettle();
  expect(
    find.text('line 3', findRichText: true, skipOffstage: false),
    findsOneWidget,
  );
  controller.revealLine(
    source.id,
    DiffSide.newer,
    distant ? 200 : 3,
    revision: 0,
  );
  await tester.pumpAndSettle();
  expect(outer.offset, greaterThan(0));
  visible(
    tester,
    find.text(distant ? 'line 200' : 'line 3', findRichText: true),
    height: 600,
  );
  expectPlainTree(tester);
}

Future<void> leadingChange(WidgetTester tester, bool shrinkWrap) async {
  final controller = PatchController<void>([file()]);
  final scroll = ScrollController();
  addTearDown(controller.dispose);
  addTearDown(scroll.dispose);
  var leading = false;
  late StateSetter update;
  await tester.pumpWidget(
    app(
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return PatchView<void>.controlled(
            controller: controller,
            scrollController: scroll,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            shrinkWrap: shrinkWrap,
            stickyHeaders: true,
            padding: EdgeInsets.zero,
            leading: leading ? const SizedBox(height: 300) : null,
            headerBuilder: (_, _, _, _) => const SizedBox(
              key: ValueKey('header'),
              height: 80,
              child: Text('Header'),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle(); // Prime the file-header row cache.
  update(() => leading = true);
  await tester.pumpAndSettle();
  scroll.jumpTo(330);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('header')), findsOneWidget);
  expect(
    tester.getTopLeft(find.byKey(const ValueKey('header'))).dy,
    closeTo(-30, .1),
  );
  update(() => leading = false);
  await tester.pumpAndSettle();
  scroll.jumpTo(30);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('header')), findsOneWidget);
  expect(
    tester.getTopLeft(find.byKey(const ValueKey('header'))).dy,
    closeTo(-30, .1),
  );
  expectPlainTree(tester);
}

Future<void> patchResize(
  WidgetTester tester,
  bool shrinkWrap,
  bool widthChange,
) async {
  final source = file(long: widthChange);
  final controller = PatchController<void>([source]);
  addTearDown(controller.dispose);
  final highlighter = Highlighter();
  var font = 14.0;
  var width = 600.0;
  late StateSetter update;
  await tester.pumpWidget(
    app(
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 260,
              child: PatchView<void>.controlled(
                controller: controller,
                highlighter: highlighter,
                theme: githubDarkTheme,
                shrinkWrap: shrinkWrap,
                padding: EdgeInsets.zero,
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: font,
                  height: 1.5,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.revealLine(source.id, DiffSide.newer, 100, revision: 0);
  await tester.pumpAndSettle();
  final target = find.text(line(100, long: widthChange), findRichText: true);
  visible(tester, target);
  update(() {
    if (widthChange) {
      width = 280;
    } else {
      font = 28;
    }
  });
  await tester.pumpAndSettle();
  visible(tester, target);
  expectPlainTree(tester);
}

void main() {
  testWidgets(
    'review 1: retained code reveal restores line 100 after doubled font',
    (tester) => codeResize(tester, widthChange: false),
  );
  testWidgets(
    'review 2: empty leading has exact shrink-wrapped reveal offset',
    (tester) => zeroLeading(tester, true),
  );
  testWidgets(
    'review 3: bounded shrink reveal propagates past spacer to ancestor',
    (tester) => ancestor(tester, listView: false),
  );
  testWidgets(
    'review 4: adding leading invalidates indexed header row cache',
    (tester) => leadingChange(tester, false),
  );

  group('parent behavior parity', () {
    testWidgets('source replacement cancels pending anchor restoration', (
      tester,
    ) async {
      final source = file(long: true);
      final controller = PatchController<void>([source]);
      addTearDown(controller.dispose);
      var width = 600.0;
      late StateSetter update;
      final highlighter = Highlighter();
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 260,
                  child: PatchView<void>.controlled(
                    controller: controller,
                    theme: githubDarkTheme,
                    highlighter: highlighter,
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.revealLine(source.id, DiffSide.newer, 100, revision: 0);
      await tester.pumpAndSettle();
      update(() => width = 280);
      await tester.pump();
      controller.setFiles([diffTexts('', 'replacement', path: 'b.txt')]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('replacement', findRichText: true), findsOneWidget);
    });
    testWidgets(
      'retained code reveal restores anchor after width change',
      (tester) => codeResize(tester, widthChange: true),
    );
    for (final shrinkWrap in [false, true]) {
      for (final widthChange in [false, true]) {
        testWidgets(
          'patch anchor after ${widthChange ? 'width' : 'font'} change shrink=$shrinkWrap',
          (tester) => patchResize(tester, shrinkWrap, widthChange),
        );
      }
    }
    testWidgets(
      'indexed zero-height leading',
      (tester) => zeroLeading(tester, false),
    );
    testWidgets(
      'bounded shrink leading added and removed',
      (tester) => leadingChange(tester, true),
    );
    testWidgets(
      'bounded shrink reveal propagates through ListView',
      (tester) => ancestor(tester, listView: true),
    );
    testWidgets(
      'bounded shrink reveal propagates after an inner jump',
      (tester) => ancestor(tester, listView: false, distant: true),
    );
  });
}
