import 'package:syntax_core/syntax.dart';

import 'source_line_endings.dart';

/// A file's compact index of recorded hunk terminators and lazy context cursors.
class PatchLineEndings {
  /// Indexes [file] once, retaining ranges into the existing hunk line lists.
  PatchLineEndings(this.file) {
    for (final hunk in file.hunks) {
      for (var i = 0; i < hunk.lines.length; i++) {
        final line = hunk.lines[i];
        _append(_old, hunk.lines, i, line.oldNumber);
        _append(_newer, hunk.lines, i, line.newNumber);
      }
    }
    _old.sort((a, b) => a.start.compareTo(b.start));
    _newer.sort((a, b) => a.start.compareTo(b.start));
  }

  /// Immutable source snapshot owned by the view.
  final FileDiff file;
  final _old = <_HunkLineRange>[];
  final _newer = <_HunkLineRange>[];
  final _context = <DiffSide, SourceLineEndings>{};

  /// Number of range comparisons, for counted copy-cost regressions.
  int get rangeComparisons => _rangeComparisons;
  int _rangeComparisons = 0;

  /// Per copied separator: O(log H) hunk-range comparisons and at most one
  /// lazy source-ending lookup for synthesized context, with no document-sized
  /// retained lists. H counts contiguous source ranges in the hunks; indexing
  /// visits hunk lines once. The context cursor advances only as far as needed,
  /// reading each traversed source line once on ascending requests.
  String endingAt(DiffLine line, DiffSide? side) {
    side ??= line.newNumber == null ? DiffSide.old : DiffSide.newer;
    final number = side == DiffSide.old ? line.oldNumber : line.newNumber;
    final source = side == DiffSide.old ? file.oldText : file.newText;
    if (source == null || number == null) return line.sourceLineEnding;
    final ranges = side == DiffSide.old ? _old : _newer;
    var low = 0, high = ranges.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      final range = ranges[mid];
      _rangeComparisons++;
      if (number < range.start) {
        high = mid;
      } else if (number >= range.end) {
        low = mid + 1;
      } else {
        return range
            .lines[range.offset + number - range.start]
            .sourceLineEnding;
      }
    }
    final lines = side == DiffSide.old ? file.oldLines : file.newLines;
    if (lines == null || number > lines.length) return line.sourceLineEnding;
    return (_context[side] ??= SourceLineEndings(
      source,
      lines,
    )).endingAt(number);
  }

  static void _append(
    List<_HunkLineRange> ranges,
    List<DiffLine> lines,
    int offset,
    int? number,
  ) {
    if (number == null) return;
    final last = ranges.lastOrNull;
    if (last != null &&
        identical(last.lines, lines) &&
        last.end == number &&
        last.offset + last.end - last.start == offset) {
      last.end++;
    } else {
      ranges.add(_HunkLineRange(number, offset, lines));
    }
  }
}

// A contiguous side's coordinates point directly into an original hunk list.
// Changes on the opposite side can split one hunk into several compact runs.
class _HunkLineRange {
  _HunkLineRange(this.start, this.offset, this.lines) : end = start + 1;
  final int start, offset;
  int end;
  final List<DiffLine> lines;
}
