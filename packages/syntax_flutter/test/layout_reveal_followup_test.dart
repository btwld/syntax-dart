import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app;

FileDiff source({int count = 300}) => diffTexts(
  '',
  List.generate(count, (i) => 'line ${i + 1}').join('\n'),
  path: 'a.txt',
);

void main() {
  testWidgets('scrolling away cancels reveal without scheduling idle frames', (
    tester,
  ) async {
    final file = source();
    final controller = PatchController<void>([file]);
    final scroll = ScrollController();
    final pending = Completer<HighlightWindowResult>();
    final highlighter = Highlighter();
    late StateSetter rebuild;
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return PatchView<void>.controlled(
              controller: controller,
              scrollController: scroll,
              theme: githubDarkTheme,
              highlighter: highlighter,
              stickyHeaders: true,
              headerBuilder: (_, _, _, _) =>
                  const SizedBox(height: 80, child: Text('Header')),
              executor:
                  (
                    request, {
                    required highlighter,
                    required theme,
                    required cancellation,
                  }) => pending.future,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
    await tester.pump(); // The indexed jump has run; completion has not.
    scroll.jumpTo(0);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final idle = !SchedulerBinding.instance.hasScheduledFrame;
    rebuild(() {});
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final idleAfterRebuild = !SchedulerBinding.instance.hasScheduledFrame;
    final offset = scroll.offset;
    await tester.pumpWidget(const SizedBox());
    expect(offset, 0);
    expect(idleAfterRebuild, isTrue);
    expect(
      idle,
      isTrue,
      reason: 'A cancelled reveal must not request more frames',
    );
  });

  for (final shrinkWrap in [false, true]) {
    testWidgets(
      'mounted draft state and focus survive reveal shrink=$shrinkWrap',
      (tester) async {
        final file = source(count: 30);
        final controller = PatchController<void>([file]);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            PatchView<void>.controlled(
              controller: controller,
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              stickyHeaders: true,
              shrinkWrap: shrinkWrap,
              headerBuilder: (_, _, _, _) =>
                  const SizedBox(height: 60, child: Text('Header')),
              rowBelowBuilder: (_, row) =>
                  row.row is DiffLineRow &&
                      (row.row as DiffLineRow).line.newNumber == 2
                  ? const _Draft()
                  : null,
            ),
            height: 400,
          ),
        );
        await tester.pumpAndSettle();
        final before = tester.state<_DraftState>(find.byType(_Draft));
        before.focus.requestFocus();
        await tester.pump();
        expect(before.focus.hasFocus, isTrue);
        controller.revealLine(file.id, DiffSide.newer, 2, revision: 0);
        await tester.pumpAndSettle();
        expect(tester.state<_DraftState>(find.byType(_Draft)), same(before));
        expect(before.focus.hasFocus, isTrue);
        controller.select(
          DiffSelection(
            fileId: file.id,
            revision: 0,
            side: DiffSide.newer,
            anchor: 2,
            active: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.state<_DraftState>(find.byType(_Draft)), same(before));
        expect(before.focus.hasFocus, isTrue);
        expectPlainTree(tester);
      },
    );

    testWidgets(
      'scaled reveal uses viewport-local offsets shrink=$shrinkWrap',
      (tester) async {
        final file = source();
        final controller = PatchController<void>([file]);
        addTearDown(controller.dispose);
        controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
        await tester.pumpWidget(
          app(
            Align(
              alignment: Alignment.topLeft,
              child: Transform.scale(
                scale: 2,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const ValueKey('viewport'),
                  width: 280,
                  height: 200,
                  child: PatchView<void>.controlled(
                    controller: controller,
                    theme: githubDarkTheme,
                    highlighter: Highlighter(),
                    stickyHeaders: true,
                    shrinkWrap: shrinkWrap,
                    headerBuilder: (_, _, _, _) => const SizedBox(
                      key: ValueKey('header'),
                      height: 120,
                      child: Text('Header'),
                    ),
                  ),
                ),
              ),
            ),
            height: 500,
          ),
        );
        await tester.pumpAndSettle();
        final viewport = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('viewport')),
        );
        Rect localRect(Finder finder) {
          final box = tester.renderObject<RenderBox>(finder);
          return MatrixUtils.transformRect(
            box.getTransformTo(viewport),
            Offset.zero & box.size,
          );
        }

        final header = localRect(
          find.byKey(const ValueKey('header')).hitTestable(),
        );
        final target = localRect(find.text('line 200', findRichText: true));
        debugPrint('scaled shrink=$shrinkWrap: header=$header target=$target');
        expect(target.top, greaterThanOrEqualTo(header.bottom));
        expect(target.bottom, lessThanOrEqualTo(200));
        expectPlainTree(tester);
      },
    );
  }

  testWidgets('cold header is measured at the source row width', (
    tester,
  ) async {
    final a = source(count: 300);
    final b = source(count: 300).copyWith(identity: 'b');
    final controller = PatchController<void>([a, b]);
    addTearDown(controller.dispose);
    final widths = <double>{};
    controller.revealLine(b.id, DiffSide.newer, 200, revision: 0);
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 280,
            height: 260,
            child: PatchView<void>.controlled(
              controller: controller,
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              stickyHeaders: true,
              headerBuilder: (_, file, _, _) => LayoutBuilder(
                builder: (_, constraints) {
                  if (file.id == b.id) widths.add(constraints.maxWidth);
                  return const SizedBox(height: 80, child: Text('Header'));
                },
              ),
              fileLabelBuilder: (_, file) =>
                  Text('wrapped label ' * 8, key: ValueKey('label-${file.id}')),
            ),
          ),
        ),
        height: 400,
      ),
    );
    await tester.pumpAndSettle();
    expect(widths, {256.0});
    final label = tester.getRect(
      find.byKey(ValueKey('label-${b.id}')).hitTestable(),
    );
    final targets = find.text('line 200', findRichText: true).hitTestable();
    final target = tester.getRect(targets);
    expect(target.top, greaterThanOrEqualTo(label.bottom));
    expect(target.bottom, lessThanOrEqualTo(260));
  });
}

class _Draft extends StatefulWidget {
  const _Draft();
  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final focus = FocusNode();
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    child: const SizedBox(height: 40, child: Text('Draft')),
  );
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }
}
