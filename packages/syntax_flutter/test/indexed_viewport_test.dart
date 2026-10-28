import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

/// Counts how often each row's state is created and how many are alive.
final class _Probe {
  final inits = <int>[];
  final alive = <int>{};
}

final class _ProbeRow extends StatefulWidget {
  const _ProbeRow({
    super.key,
    required this.index,
    required this.height,
    required this.probe,
  });

  final int index;
  final double height;
  final _Probe probe;

  @override
  State<_ProbeRow> createState() => _ProbeRowState();
}

final class _ProbeRowState extends State<_ProbeRow> {
  @override
  void initState() {
    super.initState();
    widget.probe.inits.add(widget.index);
    widget.probe.alive.add(widget.index);
  }

  @override
  void dispose() {
    widget.probe.alive.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: widget.height, child: Text('Line ${widget.index}'));
}

/// Every tenth row is twice as tall, so positions only add up when the
/// viewport lays rows out where they really are.
double mixed(int index) => index % 10 == 0 ? 48 : 24;
double uniform(int index) => 24;

const viewportHeight = 300.0;

void main() {
  for (final (fixed, start, direction) in [
    (false, 0.0, 1),
    (true, 0.0, 1),
    (false, 12000.0, -1),
  ]) {
    testWidgets(
      'retains only requested endpoints and releases them (fixed=$fixed, direction=$direction)',
      (tester) async {
        final scroll = ScrollController(initialScrollOffset: start);
        addTearDown(scroll.dispose);
        final probe = _Probe();
        final endpoints = start == 0 ? [5, 8] : [500, 508];
        var retained = endpoints.toSet().cast<Object>();
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              height: viewportHeight,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return IndexedCodeViewport(
                    controller: scroll,
                    count: 1000,
                    fixedHeight: fixed,
                    retainedRows: retained,
                    layoutKey: 1000,
                    identity: (index) => index,
                    indexOf: (identity) => identity as int,
                    builder: (context, index) =>
                        _ProbeRow(index: index, height: 24, probe: probe),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var step = 1; step <= 60; step++) {
          scroll.jumpTo(start + step * 40 * direction);
          await tester.pump();
          expect(probe.alive, containsAll(endpoints));
          expect(probe.alive.length, lessThan(100));
        }
        update(() => retained = {});
        await tester.pumpAndSettle();
        scroll.jumpTo(start + 2440 * direction);
        await tester.pumpAndSettle();
        for (final endpoint in endpoints) {
          expect(probe.alive, isNot(contains(endpoint)));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  double offsetOf(int row, double Function(int) height) {
    var offset = 0.0;
    for (var i = 0; i < row; i++) {
      offset += height(i);
    }
    return offset;
  }

  /// Pumps a viewport and returns its scroll controller, its probe and a
  /// function that requests a reveal of a row.
  Future<(ScrollController, _Probe, void Function(int))> pump(
    WidgetTester tester, {
    int count = 1000,
    double Function(int) height = uniform,
    void Function(int, int)? onVisibleRange,
    ValueChanged<int>? onFirstRow,
  }) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final probe = _Probe();
    int? reveal;
    var request = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            height: viewportHeight,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return IndexedCodeViewport(
                  controller: scroll,
                  count: count,
                  layoutKey: count,
                  identity: (index) => index,
                  indexOf: (identity) => identity as int,
                  revealRow: reveal,
                  revealRequest: request,
                  onVisibleRange: onVisibleRange,
                  onFirstRow: onFirstRow,
                  builder: (context, index) => _ProbeRow(
                    key: ValueKey('row-$index'),
                    index: index,
                    height: height(index),
                    probe: probe,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      scroll,
      probe,
      (int row) => update(() {
        reveal = row;
        request++;
      }),
    );
  }

  testWidgets('rows already built keep their elements and states while '
      'scrolling a few rows at a time', (tester) async {
    final (scroll, probe, _) = await pump(tester);
    scroll.jumpTo(2000);
    await tester.pumpAndSettle();
    // Row 92 stays in view for the first 200 px, so it is built on every
    // supported Flutter, whatever each builds in the cache extent.
    final row = find.byKey(const ValueKey('row-92'));
    final kept = tester.state(row);
    probe.inits.clear();
    for (var i = 0; i < 5; i++) {
      scroll.jumpTo(scroll.offset + 40);
      await tester.pump();
    }
    expect(
      tester.state(row),
      same(kept),
      reason: 'a row that stayed built keeps its state',
    );
    for (var i = 0; i < 15; i++) {
      scroll.jumpTo(scroll.offset + 40);
      await tester.pump();
    }
    // 800 px of new rows at 24 px each come into the cache extent, about 34
    // rows; nothing already built is created again.
    expect(probe.inits.length, lessThanOrEqualTo(40));
    expect(probe.inits.toSet().length, probe.inits.length);
  });

  testWidgets('scrolling back up re-creates at most the rows it reaches', (
    tester,
  ) async {
    final (scroll, probe, _) = await pump(tester);
    scroll.jumpTo(6000);
    await tester.pumpAndSettle();
    probe.inits.clear();
    Map<int, State> mountedRows() => {
      for (final state in tester.stateList<_ProbeRowState>(
        find.byType(_ProbeRow),
      ))
        state.widget.index: state,
    };
    var previous = mountedRows();
    for (var i = 0; i < 40; i++) {
      scroll.jumpTo(scroll.offset - 40);
      await tester.pump();
      final current = mountedRows();
      expect(current.length, lessThanOrEqualTo(80));
      for (final entry in previous.entries) {
        if (current.containsKey(entry.key)) {
          expect(
            current[entry.key],
            same(entry.value),
            reason: 'row ${entry.key} at step $i',
          );
        }
      }
      previous = current;
    }
    // Moved-child placeholders can build extra offscreen rows, but no row
    // that stays mounted may lose its state when the list extends upward.
    expect(probe.inits.length, lessThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a far jump builds only the rows around its target', (
    tester,
  ) async {
    final (scroll, probe, _) = await pump(tester, count: 10000);
    probe.inits.clear();
    scroll.jumpTo(5000 * 24);
    await tester.pump();
    expect(probe.inits, isNotEmpty);
    expect(probe.inits.reduce((a, b) => a < b ? a : b), greaterThan(4950));
    expect(probe.inits.length, lessThanOrEqualTo(60));
    expect(probe.alive.reduce((a, b) => a < b ? a : b), greaterThan(4950));
  });

  testWidgets('rows sit where their heights put them, scrolling down and up, '
      'without scroll corrections', (tester) async {
    final (scroll, _, _) = await pump(tester, height: mixed);
    // Measure every row once, as a reader scrolling through would.
    for (var offset = 0.0; offset < 4000; offset += 200) {
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
    }
    final top = tester.getTopLeft(find.byType(IndexedCodeViewport)).dy;
    Future<void> expectRowsInPlace(double offset) async {
      scroll.jumpTo(offset);
      await tester.pump();
      expect(scroll.offset, offset, reason: 'no scroll correction');
      for (final row in [for (var r = 0; r < 200; r++) r]) {
        final finder = find.byKey(ValueKey('row-$row'));
        if (finder.evaluate().isEmpty) continue;
        final y = tester.getTopLeft(finder).dy - top;
        if (y < -100 || y > viewportHeight + 100) continue;
        expect(
          y,
          closeTo(offsetOf(row, mixed) - offset, .5),
          reason: 'row $row at offset $offset',
        );
      }
    }

    for (var offset = 1200.0; offset < 2000; offset += 40) {
      await expectRowsInPlace(offset);
    }
    for (var offset = 2000.0; offset > 400; offset -= 40) {
      await expectRowsInPlace(offset);
    }
  });

  testWidgets('a reveal request puts its row at the top', (tester) async {
    final (scroll, _, reveal) = await pump(tester, count: 5000);
    reveal(3000);
    await tester.pumpAndSettle();
    expect(scroll.offset, 3000 * 24);
    final top = tester.getTopLeft(find.byType(IndexedCodeViewport)).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey('row-3000'))).dy, top);
  });

  testWidgets('the visible range and first row follow scrolling', (
    tester,
  ) async {
    (int, int)? range;
    int? first;
    final (scroll, _, _) = await pump(
      tester,
      onVisibleRange: (start, end) => range = (start, end),
      onFirstRow: (row) => first = row,
    );
    scroll.jumpTo(100 * 24);
    await tester.pumpAndSettle();
    expect(first, 100);
    // Rows 100 to 112 show in 300 px of 24 px rows.
    expect(range, (100, 113));
    scroll.jumpTo(100 * 24 + 40);
    await tester.pumpAndSettle();
    expect(first, 101);
  });

  testWidgets('a row that changes height while scrolled away leaves the rows '
      'above it where their heights put them', (tester) async {
    // The reviewer's probe: the caller changes a row's height without a new
    // layout key while the row is out of view, then the reader scrolls back.
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var tall = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            height: viewportHeight,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return IndexedCodeViewport(
                  controller: scroll,
                  count: 400,
                  layoutKey: 400,
                  identity: (index) => index,
                  indexOf: (identity) => identity as int,
                  builder: (context, index) => SizedBox(
                    key: ValueKey('row-$index'),
                    height: index == 50 && tall ? 124 : 24,
                    child: Text('Line $index'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Scrolled down past row 50, which the list keeps no element for.
    for (var offset = 0.0; offset <= 3000; offset += 100) {
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
    }
    update(() => tall = true);
    await tester.pumpAndSettle();
    for (var offset = 3000.0; offset > 1000; offset -= 40) {
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
    }
    final top = tester.getTopLeft(find.byType(IndexedCodeViewport)).dy;
    double y(int row) =>
        tester.getTopLeft(find.byKey(ValueKey('row-$row'))).dy - top;

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(y(0), 0);

    scroll.jumpTo(40 * 24);
    await tester.pumpAndSettle();
    expect(scroll.offset, 40 * 24);
    expect(y(40), 0);
    expect(y(50), 50 * 24 - 40 * 24);
    expect(tester.getSize(find.byKey(const ValueKey('row-50'))).height, 124);
  });

  testWidgets('scrolling up after a far jump measures new rows without '
      'starting the list again for each', (tester) async {
    // The reviewer's probe: rows first measured on the way up, after a jump,
    // grow forward from the list's first row, so they need the usual
    // correction but no new list.
    final (scroll, probe, _) = await pump(tester, count: 3000, height: mixed);
    scroll.jumpTo(offsetOf(2500, mixed));
    await tester.pumpAndSettle();
    probe.inits.clear();
    final lists = <Element>{};
    void noteList() {
      lists.add(
        tester.element(
          find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_RowList',
          ),
        ),
      );
    }

    noteList();
    for (var i = 0; i < 100; i++) {
      scroll.jumpTo(scroll.offset - 40);
      await tester.pump();
      noteList();
    }
    await tester.pumpAndSettle();
    // 4,000 px up passes about 150 rows. A new list a screen higher, about
    // every 300 px, builds about 50 rows each: 13 lists here, counting the
    // first, with 678 rows created (810 on Flutter 3.35, which builds no
    // rows in the cache above the viewport). Starting a new list for every
    // correction made 31 lists and 1,419 rows (1,765 on 3.35).
    expect(probe.inits.length, lessThanOrEqualTo(1000));
    expect(lists.length, lessThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });

  group('a layout change keeps the rows on screen where they were', () {
    // As in a review whose "Load diff" adds a file's rows. The patch view's
    // estimate changes once it has measured a header, while the first rows
    // are on screen; the reader then scrolls into the list and the layout
    // changes again. Rows' real heights differ from the estimate, so the
    // rows kept through the first change must be measured again, or every
    // row after them lands off by what their estimates miss.
    late List<String> ids;
    late Object layoutKey;
    late double estimate;
    late double width;
    late bool fixed;
    late Map<String, double> grown;
    late StateSetter update;
    double heightOf(String id) =>
        grown[id] ??
        (id.startsWith('n')
            ? 21
            : int.parse(id.substring(1)) % 7 == 1
            ? 64
            : 21);

    Future<ScrollController> pumpRows(WidgetTester tester) async {
      ids = [for (var i = 0; i < 400; i++) 'r$i'];
      layoutKey = 0;
      estimate = 24;
      width = 600;
      fixed = false;
      grown = {};
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SizedBox(
                  width: width,
                  height: viewportHeight,
                  child: IndexedCodeViewport(
                    controller: scroll,
                    count: ids.length,
                    layoutKey: layoutKey,
                    estimatedHeight: estimate,
                    fixedHeight: fixed,
                    identity: (index) => ids[index],
                    indexOf: (identity) {
                      final index = ids.indexOf(identity as String);
                      return index < 0 ? null : index;
                    },
                    builder: (context, index) => SizedBox(
                      height: heightOf(ids[index]),
                      child: Text(ids[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => estimate = 30);
      await tester.pumpAndSettle();
      // Into the list, not so far that it starts a new one.
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      return scroll;
    }

    /// The top of every row on screen, by id.
    Map<String, double> onScreen(WidgetTester tester) => {
      for (final element in find.byType(Text).evaluate())
        if (tester.getTopLeft(find.byWidget(element.widget)).dy case final top
            when top > -60 && top < viewportHeight)
          (element.widget as Text).data!: top,
    };

    /// Lets the change settle, then checks that the first visible row and
    /// every row after it still on screen are where they were before it.
    Future<void> expectStill(
      WidgetTester tester,
      Map<String, double> before,
    ) async {
      // Frame by frame, recording how far a row strays on the way.
      var worst = 0.0;
      for (
        var frame = 0;
        frame < 20 && tester.binding.hasScheduledFrame;
        frame++
      ) {
        await tester.pump();
        final now = onScreen(tester);
        for (final MapEntry(key: id, value: top) in before.entries) {
          if (now[id] case final moved?) {
            worst = math.max(worst, (moved - top).abs());
          }
        }
      }
      await tester.pumpAndSettle();
      debugPrint('largest move on the way: ${worst.toStringAsFixed(1)} px');
      final settled = onScreen(tester);
      final first = before.entries
          .where((entry) => entry.value >= 0)
          .reduce((a, b) => a.value <= b.value ? a : b);
      expect(settled[first.key], closeTo(first.value, .5), reason: first.key);
      for (final MapEntry(key: id, value: top) in before.entries) {
        expect(settled[id], closeTo(top, .5), reason: id);
      }
      expect(tester.takeException(), isNull);
    }

    testWidgets('a new layout key', (tester) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      expect(before.length, greaterThan(5));
      update(() => layoutKey = 1);
      await expectStill(tester, before);
    });

    testWidgets('rows added below the middle of the screen', (tester) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      final ordered = before.keys.toList()
        ..sort((a, b) => before[a]!.compareTo(before[b]!));
      final middle = ordered[ordered.length ~/ 2];
      update(() {
        ids.insertAll(ids.indexOf(middle) + 1, [
          for (var i = 0; i < 40; i++) 'n$i',
        ]);
      });
      // Only rows at or above the insertion keep their place.
      await expectStill(tester, {
        for (final id in ordered.take(ordered.indexOf(middle) + 1))
          id: before[id]!,
      });
    });

    /// The row the top of the viewport is in: the first visible row.
    String firstVisible(Map<String, double> before) => before.entries
        .where((entry) => entry.value <= 0)
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    List<String> newRows(int count) => [for (var i = 0; i < count; i++) 'n$i'];

    testWidgets('five rows added above the first visible row', (tester) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      final first = ids.indexOf(firstVisible(before));
      update(() => ids.insertAll(first - 3, newRows(5)));
      await expectStill(tester, before);
    });

    testWidgets('five rows added at the first visible row', (tester) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      final first = ids.indexOf(firstVisible(before));
      update(() => ids.insertAll(first, newRows(5)));
      await expectStill(tester, before);
    });

    testWidgets('five rows removed above the first visible row and five '
        'below it', (tester) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      final first = ids.indexOf(firstVisible(before));
      final kept = ids.sublist(first, first + 3);
      update(() {
        ids
          ..removeRange(first + 3, first + 8)
          ..removeRange(first - 8, first - 3);
      });
      // The rows from the first visible one down to the removal stay put.
      await expectStill(tester, {for (final id in kept) id: before[id]!});
    });

    testWidgets('a narrower viewport whose rows keep their wrap', (
      tester,
    ) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      update(() => width = 400);
      await expectStill(tester, before);
    });

    testWidgets('fixed heights turned on, then off again', (tester) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      update(() => fixed = true);
      await tester.pumpAndSettle();
      update(() => fixed = false);
      await expectStill(tester, before);
    });

    testWidgets('a second change of the estimate', (tester) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      update(() => estimate = 26);
      await expectStill(tester, before);
    });

    testWidgets('a row built above the first visible row grows', (
      tester,
    ) async {
      await pumpRows(tester);
      final before = onScreen(tester);
      final above = ids[ids.indexOf(firstVisible(before)) - 3];
      update(() => grown[above] = heightOf(above) + 40);
      await expectStill(tester, before);
    });
  });
}
