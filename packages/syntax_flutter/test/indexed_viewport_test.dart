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
    // Row 105 is in the cache extent below the viewport now and will be in
    // the one above it after 800 px.
    final row = find.byKey(const ValueKey('row-105'), skipOffstage: false);
    final kept = tester.state(row);
    probe.inits.clear();
    for (var i = 0; i < 20; i++) {
      scroll.jumpTo(scroll.offset + 40);
      await tester.pump();
    }
    // 800 px of new rows at 24 px each come into the cache extent, about 34
    // rows; nothing already built is created again.
    expect(probe.inits.length, lessThanOrEqualTo(40));
    expect(probe.inits.toSet().length, probe.inits.length);
    expect(
      tester.state(row),
      same(kept),
      reason: 'a row that stayed in the cache extent keeps its state',
    );
  });

  testWidgets('scrolling back up re-creates at most the rows it reaches', (
    tester,
  ) async {
    final (scroll, probe, _) = await pump(tester);
    scroll.jumpTo(6000);
    await tester.pumpAndSettle();
    probe.inits.clear();
    for (var i = 0; i < 40; i++) {
      scroll.jumpTo(scroll.offset - 40);
      await tester.pump();
    }
    // Scrolling up past the list's first row starts a new list a screen
    // higher, so 1,600 px upwards builds about one 50-row list per 300 px
    // screen. A window rebuilt whenever its first row changes would create
    // about 37 rows every frame, over 1,400 here.
    expect(probe.inits.length, lessThanOrEqualTo(400));
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
}
