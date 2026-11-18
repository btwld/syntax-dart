import 'package:syntax_core/syntax.dart';
import 'package:test/test.dart';

void main() {
  test('zero-height rows share prefix offsets and are skipped by lookup', () {
    final heights = RowHeightIndex(4, estimatedHeight: 20);
    heights.measure(0, 0);
    heights.measure(1, 20);
    heights.measure(2, 0);
    heights.measure(3, 10);
    expect(
      [for (var row = 0; row <= 4; row++) heights.offsetFor(row)],
      [0, 0, 20, 20, 30],
    );
    expect(heights.rowAt(0), 1);
    expect(heights.rowAt(19), 1);
    expect(heights.rowAt(20), 3);
    expect(heights.rowAt(30), 3);
    for (final invalid in [-1.0, double.nan, double.infinity]) {
      expect(() => heights.measure(0, invalid), throwsArgumentError);
    }
  });
}
