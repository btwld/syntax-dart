import 'package:syntax_core/syntax.dart';

/// Change-block boundaries indexed once per immutable hunk.
/// Pair lookup uses source numbers and binary search, never a hunk-line scan.
class PatchChangeIndex {
  /// Scans [lines] once, retaining only boundaries of paired change blocks.
  PatchChangeIndex(List<DiffLine> lines) : _lines = lines {
    var i = 0;
    while (i < lines.length) {
      if (lines[i].kind == DiffLineKind.context) {
        i++;
        continue;
      }
      final removed = i;
      while (i < lines.length && lines[i].kind == DiffLineKind.removed) {
        i++;
      }
      final added = i;
      while (i < lines.length && lines[i].kind == DiffLineKind.added) {
        i++;
      }
      final removedCount = added - removed;
      final addedCount = i - added;
      final pairs = removedCount < addedCount ? removedCount : addedCount;
      if (pairs > 0) {
        _blocks.add(
          _ChangeBlock(
            removed,
            added,
            pairs,
            lines[removed].oldNumber!,
            lines[added].newNumber!,
          ),
        );
      }
    }
  }

  final List<DiffLine> _lines;
  final _blocks = <_ChangeBlock>[];

  /// Returns this changed line's original pair, or null for unpaired lines.
  /// Reads only the two selected lines after O(log change-blocks) lookup.
  (DiffLine, DiffLine)? pairFor(DiffLine line) {
    if (line.kind == DiffLineKind.context) return null;
    final old = line.kind == DiffLineKind.removed;
    final number = old ? line.oldNumber : line.newNumber;
    if (number == null) return null;
    var low = 0, high = _blocks.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final block = _blocks[mid];
      final start = old ? block.oldNumber : block.newNumber;
      if (start <= number) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low == 0) return null;
    final block = _blocks[low - 1];
    final offset = number - (old ? block.oldNumber : block.newNumber);
    if (offset >= block.pairs) return null;
    return (_lines[block.removed + offset], _lines[block.added + offset]);
  }
}

final class _ChangeBlock {
  _ChangeBlock(
    this.removed,
    this.added,
    this.pairs,
    this.oldNumber,
    this.newNumber,
  );
  final int removed, added, pairs, oldNumber, newNumber;
}
