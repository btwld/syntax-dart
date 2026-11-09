import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app;

// Controlled layout contract (all offsets/heights are viewport-local):
//
// * Exactly one visible file header. Pin only after the complete in-list
//   header/label leaves the bounded viewport, also after adding/removing leading.
//   sticky_header_followup_test.dart: "one controlled sticky header ...";
//   layout_reveal_parity_test.dart: "review 4", "bounded shrink leading ...".
//   Unbounded content uses its ancestor's viewport and its in-list header.
// * Queued and repeated reveals expose the whole target below the visible pinned
//   header, using actual custom header/label heights and zero-height rows.
//   merge_followup_test.dart: sticky queued/repeated and parent-scroll cases;
//   sticky_header_followup_test.dart: "reveals use each pinned header height";
//   layout_reveal_parity_test.dart: zero leading and ancestor propagation cases.
// * Transform.scale never mixes global distances with local offsets.
//   layout_reveal_followup_test.dart: both "scaled ..." cases and cold wrapping
//   header-width measurement. Unbounded transformed propagation is below.
// * User scrolling cancels an active reveal: no idle frames, retry on rebuild,
//   or later stale jump. layout_reveal_followup_test.dart: "scrolling away ...".
// * Revealing a mounted row preserves rowBelow State and FocusNode/focus.
//   layout_reveal_followup_test.dart: both "mounted draft ..." cases.
// * Preserve logical anchors through font/width/fixed-height changes, whether
//   geometry/range callbacks exist or not; completed reveals do not disable it.
//   layout_reveal_parity_test.dart: retained-code and patch font/width cases,
//   source-replacement cancellation. indexed_viewport_test.dart covers insertion,
//   removal, remeasurement and fixed-height mode changes. Gaps are below.
// * Initial scroll offsets belong to the caller. Never restore an anchor from
//   purely estimated geometry. Measurement precedes restoration, active reveal
//   precedes visible-range notification, and unrelated callbacks cannot retire
//   either operation. These ordering/initialization gaps are below.
// * Native selection survives an equal-list rebuild, clears on real replacement;
//   no per-cell layout scans. merge_followup_test.dart covers both diff modes,
//   counted indexed source builds and zero scans for 2,000 shrink-wrapped rows.
// * Keep the stable row/measurement structure and remain Material-free.
//
// This file supplies missing cases; the referenced tests remain authoritative
// parts of the contract and must run unchanged with this file in the full suite.

FileDiff _file() => diffTexts(
  '',
  List.generate(300, (i) => 'line ${i + 1} alpha beta gamma delta').join('\n'),
  path: 'contract.txt',
);

void main() {
  for (final range in [false, true]) {
    for (final layout in [false, true]) {
      testWidgets('fixed-height anchor range=$range layout=$layout', (
        tester,
      ) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        var height = 24.0;
        late StateSetter update;
        final notifications = <(double, int)>[];
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return IndexedCodeViewport(
                  controller: scroll,
                  count: 300,
                  fixedHeight: true,
                  estimatedHeight: height,
                  layoutKey: height,
                  identity: (i) => i,
                  indexOf: (id) => id as int,
                  builder: (_, i) =>
                      SizedBox(height: height, child: Text('$i')),
                  onLayout: layout ? (_) {} : null,
                  onVisibleRange: range
                      ? (start, end) =>
                            notifications.add((scroll.offset, start))
                      : null,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        scroll.jumpTo(1200);
        await tester.pumpAndSettle();
        notifications.clear();
        update(() => height = 48);
        await tester.pumpAndSettle();
        expect(scroll.offset, 2400);
        expect(tester.getTopLeft(find.text('50')).dy, closeTo(0, .1));
        if (range) {
          expect(notifications, isNotEmpty);
          expect(notifications.every((n) => n == (2400.0, 50)), isTrue);
        }
        expectPlainTree(tester);
      });
    }
  }

  for (final shrink in [false, true]) {
    testWidgets('initial offset survives first measurement shrink=$shrink', (
      tester,
    ) async {
      final controller = PatchController<void>([_file()]);
      final scroll = ScrollController(initialScrollOffset: 50);
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        app(
          PatchView<void>.controlled(
            controller: controller,
            scrollController: scroll,
            theme: githubDarkTheme,
            highlighter: Highlighter(),
            shrinkWrap: shrink,
            padding: EdgeInsets.zero,
            leading: const SizedBox(height: 300),
            onVisibleRange: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, 50);
      expectPlainTree(tester);
    });
  }

  // Existing patch resize tests omit notifications. Exercise both callbacks
  // together here: onLayout drives sticky geometry, onVisibleRange observes it.
  for (final shrink in [false, true]) {
    for (final widthChange in [false, true]) {
      testWidgets(
        'notified patch anchor ${widthChange ? 'width' : 'font'} shrink=$shrink',
        (tester) async {
          final file = _file();
          final controller = PatchController<void>([file]);
          final scroll = ScrollController();
          addTearDown(controller.dispose);
          addTearDown(scroll.dispose);
          var width = 600.0;
          var font = 14.0;
          late StateSetter update;
          final ranges = <(int, int)>[];
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
                        scrollController: scroll,
                        highlighter: Highlighter(),
                        theme: githubDarkTheme,
                        shrinkWrap: shrink,
                        stickyHeaders: true,
                        headerBuilder: (_, _, _, _) =>
                            const SizedBox(height: 60, child: Text('Header')),
                        padding: EdgeInsets.zero,
                        textStyle: TextStyle(fontSize: font, height: 1.5),
                        onVisibleRange: (start, end) =>
                            ranges.add((start, end)),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          controller.revealLine(file.id, DiffSide.newer, 100, revision: 0);
          await tester.pumpAndSettle();
          final target = find.text(
            'line 100 alpha beta gamma delta',
            findRichText: true,
          );
          // Establish the reader at the source row, beyond the pinned header.
          scroll.jumpTo(scroll.offset + tester.getTopLeft(target).dy);
          await tester.pumpAndSettle();
          ranges.clear();
          update(() {
            if (widthChange) {
              width = 250;
            } else {
              font = 28;
            }
          });
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(target).dy, closeTo(0, .1));
          expect(tester.getBottomLeft(target).dy, lessThanOrEqualTo(260));
          expect(ranges, isNotEmpty);
          final row = controller.layout.rowForLine(0, 100)!;
          expect(ranges.last.$1, row);
          expect(ranges.last.$2, greaterThan(row));
          expectPlainTree(tester);
        },
      );
    }
  }

  for (final widthChange in [false, true]) {
    testWidgets(
      'unbounded logical anchor after ${widthChange ? 'width' : 'font'} change',
      (tester) async {
        final file = _file();
        final controller = PatchController<void>([file]);
        final outer = ScrollController(initialScrollOffset: 50);
        addTearDown(controller.dispose);
        addTearDown(outer.dispose);
        var width = 600.0;
        var font = 14.0;
        late StateSetter update;
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              controller: outer,
              child: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: PatchView<void>.controlled(
                        controller: controller,
                        highlighter: Highlighter(),
                        theme: githubDarkTheme,
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        leading: const SizedBox(height: 300),
                        textStyle: TextStyle(fontSize: font, height: 1.5),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(outer.offset, 50);
        controller.revealLine(file.id, DiffSide.newer, 100, revision: 0);
        await tester.pumpAndSettle();
        final target = find.text(
          'line 100 alpha beta gamma delta',
          findRichText: true,
        );
        final before = tester.getTopLeft(target).dy;
        update(() {
          if (widthChange) {
            width = 250;
          } else {
            font = 28;
          }
        });
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(target).dy, closeTo(before, .1));
        expect(tester.getBottomLeft(target).dy, lessThanOrEqualTo(260));
        expectPlainTree(tester);
      },
    );
  }

  testWidgets(
    'ancestor scrolling cancels bounded reveal between layout phases',
    (tester) async {
      final file = _file();
      final controller = PatchController<void>([file]);
      final inner = ScrollController();
      final outer = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(inner.dispose);
      addTearDown(outer.dispose);
      late StateSetter update;
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            controller: outer,
            child: Column(
              children: [
                const SizedBox(height: 600),
                SizedBox(
                  height: 200,
                  child: StatefulBuilder(
                    builder: (_, setState) {
                      update = setState;
                      return PatchView<void>.controlled(
                        controller: controller,
                        scrollController: inner,
                        theme: githubDarkTheme,
                        highlighter: Highlighter(),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
      await tester.pump();
      expect(inner.offset, greaterThan(0));
      expect(outer.offset, 0);
      outer.jumpTo(100); // Interrupt before the ancestor phase's layout.
      await tester.pumpAndSettle();
      update(() {});
      await tester.pumpAndSettle();
      expect(outer.offset, 100);
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
      expectPlainTree(tester);
    },
  );

  testWidgets(
    'unbounded scaled queued and repeated reveals, zero leading, stable focus and idle cancellation',
    (tester) async {
      final file = _file();
      final controller = PatchController<void>([file]);
      final outer = ScrollController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(outer.dispose);
      addTearDown(focus.dispose);
      controller.revealLine(file.id, DiffSide.newer, 100, revision: 0);
      late StateSetter update;
      await tester.pumpWidget(
        app(
          Transform.scale(
            scale: 1.5,
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              controller: outer,
              child: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return PatchView<void>.controlled(
                    controller: controller,
                    highlighter: Highlighter(),
                    theme: githubDarkTheme,
                    shrinkWrap: true,
                    stickyHeaders: true,
                    padding: EdgeInsets.zero,
                    leading: const SizedBox.shrink(),
                    headerBuilder: (_, _, _, _) =>
                        const SizedBox(height: 80, child: Text('Header')),
                    fileLabelBuilder: (_, _) =>
                        const SizedBox(height: 24, child: Text('Label')),
                    rowBelowBuilder: (_, row) =>
                        row.row is DiffLineRow &&
                            (row.row as DiffLineRow).line.newNumber == 100
                        ? _Draft(key: const ValueKey('draft'), focus: focus)
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final draft = tester.state(find.byType(_Draft));
      focus.requestFocus();
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        controller.revealLine(file.id, DiffSide.newer, 100, revision: 0);
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.text('line 100 alpha beta gamma delta', findRichText: true),
        );
        expect(rect.top, greaterThanOrEqualTo(-.1));
        expect(rect.bottom, lessThanOrEqualTo(260 * 1.5));
        expect(tester.state(find.byType(_Draft)), same(draft));
        expect(focus.hasFocus, isTrue);
      }
      controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
      await tester.pump();
      outer.jumpTo(0);
      await tester.pumpAndSettle();
      update(() {});
      await tester.pumpAndSettle();
      expect(outer.offset, 0);
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
      expect(find.text('Header'), findsOneWidget);
      expectPlainTree(tester);
    },
  );
}

class _Draft extends StatefulWidget {
  const _Draft({super.key, required this.focus});
  final FocusNode focus;
  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.focus, child: const SizedBox(height: 20));
}
