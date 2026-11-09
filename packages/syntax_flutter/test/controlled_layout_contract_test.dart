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
//   layout_reveal_parity_test.dart: "review 4".
// * Queued and repeated reveals expose the whole target below the visible pinned
//   header, using actual custom header/label heights and zero-height rows.
//   merge_followup_test.dart: sticky queued/repeated cases;
//   sticky_header_followup_test.dart: "reveals use each pinned header height";
//   layout_reveal_parity_test.dart: zero leading cases.
// * Transform.scale never mixes global distances with local offsets.
//   layout_reveal_followup_test.dart: "scaled ..." cases and cold wrapping
//   header-width measurement.
// * User scrolling cancels an active reveal: no idle frames, retry on rebuild,
//   or later stale jump. layout_reveal_followup_test.dart: "scrolling away ...".
// * Revealing a mounted row preserves rowBelow State and FocusNode/focus.
//   layout_reveal_followup_test.dart: "mounted draft ..." cases.
// * Preserve logical anchors through font/width/fixed-height changes, whether
//   geometry/range callbacks exist or not; completed reveals do not disable it.
//   layout_reveal_parity_test.dart: retained-code and patch font/width cases,
//   source-replacement cancellation. indexed_viewport_test.dart covers insertion,
//   removal, remeasurement and fixed-height mode changes. Gaps are below.
// * A width reset combined with count/layout-key changes preserves an already
//   captured logical anchor in both measured-height and fixed-height modes.
// * A positioned reveal retains its logical target through width resets before
//   completion; initial-offset suppression cannot discard its correction.
// * Restoration resolves the owning scrollable's currently attached position.
//   Replacing ScrollPhysics during font/layout changes must never jump a detached
//   ScrollPosition. The follow-up probes below enforce these three rules.
// * Scrolling and source replacement in the same frame validate continuity
//   against the current reader anchor, even when the last measured reader was
//   deleted. Geometry history captures that current identity with the anchor.
//   The follow-up 2 probes cover both measured-height and fixed-height rows.
// * Initial scroll offsets belong to the caller. Never restore an anchor from
//   purely estimated geometry. Measurement precedes restoration, active reveal
//   precedes visible-range notification, and unrelated callbacks cannot retire
//   either operation. These ordering/initialization gaps are below.
// * Native selection survives an equal-list rebuild, clears on real replacement;
//   no per-cell layout scans. merge_followup_test.dart covers both diff modes,
//   counted bounded indexed source builds for 2,000 hunks.
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
  group('follow-up 2', () {
    for (final fixed in [false, true]) {
      testWidgets(
        'same-frame scroll and replacement preserve current reader fixed=$fixed',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          var ids = List.generate(300, (i) => 'row-$i');
          var revision = 0;
          late StateSetter update;
          await tester.pumpWidget(
            app(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return IndexedCodeViewport(
                    controller: scroll,
                    count: ids.length,
                    layoutKey: revision,
                    fixedHeight: fixed,
                    estimatedHeight: 24,
                    identity: (i) => ids[i],
                    indexOf: (id) {
                      final i = ids.indexOf(id as String);
                      return i < 0 ? null : i;
                    },
                    onLayout: (_) {},
                    onVisibleRange: (_, _) {},
                    builder: (_, i) =>
                        SizedBox(height: 24, child: Text(ids[i])),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle(); // Establish measured geometry at row 0.
          expect(tester.getTopLeft(find.text('row-0')).dy, 0);
          scroll.jumpTo(
            1200,
          ); // Current anchor is row 50; no post-frame capture.
          expect(scroll.offset, 1200);
          update(() {
            ids = ids.sublist(10); // Delete row 0, retain the current reader.
            revision++;
          }); // Deliberately no pump between scrolling and source replacement.
          await tester.pumpAndSettle();
          expect(scroll.offset, 960);
          expect(tester.getTopLeft(find.text('row-50')).dy, closeTo(0, .1));
          expectPlainTree(tester);
        },
      );
    }
  });

  group('follow-up 1', () {
    for (final fixed in [false, true]) {
      for (final countChange in [false, true]) {
        testWidgets(
          'combined width and ${countChange ? 'count' : 'layout-key'} preserves anchor fixed=$fixed',
          (tester) async {
            final scroll = ScrollController();
            addTearDown(scroll.dispose);
            final ids = List.generate(300, (i) => 'row-$i');
            var width = 600.0;
            var revision = 0;
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
                        child: IndexedCodeViewport(
                          controller: scroll,
                          count: ids.length,
                          fixedHeight: fixed,
                          layoutKey: revision,
                          estimatedHeight: 24,
                          identity: (i) => ids[i],
                          indexOf: (id) {
                            final i = ids.indexOf(id as String);
                            return i < 0 ? null : i;
                          },
                          onLayout: (_) {},
                          onVisibleRange: (_, _) {},
                          builder: (_, i) =>
                              SizedBox(height: 24, child: Text(ids[i])),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();
            scroll.jumpTo(1200);
            await tester.pumpAndSettle();
            final before = tester.getTopLeft(find.text('row-50')).dy;
            expect(before, 0);
            update(() {
              width = 280;
              ids.insertAll(0, List.generate(10, (i) => 'inserted-$i'));
              if (!countChange) {
                ids.removeRange(300, 310);
                revision++;
              }
            });
            await tester.pumpAndSettle();
            expect(
              tester.getTopLeft(find.text('row-50')).dy,
              closeTo(before, .1),
            );
            expect(scroll.offset, 1440);
            expectPlainTree(tester);
          },
        );
      }
    }

    testWidgets('width reset preserves a positioned reveal before completion', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var width = 600.0;
      int? target;
      var completions = 0;
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
                  child: IndexedCodeViewport(
                    controller: scroll,
                    count: 300,
                    layoutKey: 'source',
                    identity: (i) => i,
                    indexOf: (id) => id as int,
                    estimatedHeight: 24,
                    revealRow: target,
                    revealRequest: 1,
                    onRevealComplete: (_, {bool cancelled = false}) =>
                        completions++,
                    onLayout: (_) {},
                    onVisibleRange: (_, _) {},
                    builder: (_, i) => SizedBox(
                      height: width == 600 ? 24 : 48,
                      child: Text('row-$i'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => target = 150);
      await tester.pump(); // Initial indexed jump; target layout not settled.
      expect(scroll.offset, 3600);
      expect(completions, 0);
      update(() => width = 280);
      await tester.pumpAndSettle();
      expect(find.text('row-150'), findsOneWidget);
      expect(tester.getTopLeft(find.text('row-150')).dy, closeTo(0, .1));
      expect(completions, 1);
      expectPlainTree(tester);
    });
  });

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

  testWidgets('initial offset survives first measurement', (tester) async {
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

  // Existing patch resize tests omit notifications. Exercise both callbacks
  // together here: onLayout drives sticky geometry, onVisibleRange observes it.

  for (final widthChange in [false, true]) {
    testWidgets('notified patch anchor ${widthChange ? 'width' : 'font'}', (
      tester,
    ) async {
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
                    stickyHeaders: true,
                    headerBuilder: (_, _, _, _) =>
                        const SizedBox(height: 60, child: Text('Header')),
                    padding: EdgeInsets.zero,
                    textStyle: TextStyle(fontSize: font, height: 1.5),
                    onVisibleRange: (start, end) => ranges.add((start, end)),
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
    });
  }
}
