/// Prefix sums for measured row heights. Updates and lookup are logarithmic.
///
/// Renderers supply measurements for wrapping and annotations. Unmeasured
/// rows use the estimate, allowing distant scrolling before widgets exist.
final class RowHeightIndex {
  /// Initializes [length] rows with [estimatedHeight].
  RowHeightIndex(this.length, {this.estimatedHeight = 24})
    : _tree = List.filled(length + 1, 0) {
    RangeError.checkNotNegative(length, 'length');
    if (!estimatedHeight.isFinite || estimatedHeight <= 0) {
      throw ArgumentError.value(estimatedHeight, 'estimatedHeight');
    }
  }

  /// Number of addressable logical rows.
  final int length;

  /// Initial height of an unmeasured row.
  final double estimatedHeight;
  final List<double> _tree;
  final Map<int, double> _measured = {};

  /// Number of rows for which the renderer has supplied a measurement.
  int get measuredCount => _measured.length;

  /// Sets an actual row height and returns its change in pixels or cells.
  double measure(int row, double height) {
    RangeError.checkValidIndex(row, _tree, 'row', length);
    if (!height.isFinite || height <= 0) throw ArgumentError.value(height);
    final delta = height - (_measured[row] ?? estimatedHeight);
    _measured[row] = height;
    for (var index = row + 1; index <= length; index += index & -index) {
      _tree[index] += delta;
    }
    return delta;
  }

  /// Distance from the beginning to the top of [row].
  double offsetFor(int row) {
    RangeError.checkValueInInterval(row, 0, length, 'row');
    var offset = row * estimatedHeight;
    for (var index = row; index > 0; index -= index & -index) {
      offset += _tree[index];
    }
    return offset;
  }

  /// Row containing [offset], clamped to the addressable rows.
  int rowAt(double offset) {
    if (length == 0) return 0;
    var low = 0, high = length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (offsetFor(middle) <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
}
