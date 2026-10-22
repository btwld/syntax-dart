import 'dart:math' as math;
import 'dart:collection';

import 'file_diff.dart';

/// How a diff view arranges changed lines.
enum DiffMode {
  /// Removed and added lines one after the other, like `git diff`.
  unified,

  /// The old file on the left and the new file on the right.
  split,
}

/// The unchanged lines before hunk `hunk` of file `file`, or after the
/// file's last hunk when `hunk` equals its hunk count.
typedef DiffGapId = ({int file, int hunk});

/// Why a file shows a notice instead of lines. Renderers choose the
/// wording.
enum DiffNotice {
  /// A binary file, which has no lines to show.
  binary,

  /// Renamed with identical content.
  renamedWithoutChanges,

  /// Copied with identical content.
  copiedWithoutChanges,

  /// Added or deleted while empty.
  emptyFile,

  /// A patch that changes something other than content, such as the mode.
  noContentChanges,

  /// Two identical texts.
  noChanges,
}

/// One row of a diff view, as laid out by [layoutDiff].
sealed class DiffRow {
  const DiffRow(this.file);

  /// The index of the row's file in the list given to [layoutDiff].
  final int file;
}

/// A file's header: its path, status and change counts. Only files with a
/// path get one.
final class DiffFileHeaderRow extends DiffRow {
  /// The header of file [file].
  const DiffFileHeaderRow(super.file, {required this.collapsed});

  /// Whether the file's lines are hidden.
  final bool collapsed;

  @override
  String toString() => 'DiffFileHeaderRow($file, collapsed: $collapsed)';
}

/// Shown in place of a file's lines.
final class DiffNoticeRow extends DiffRow {
  /// A [notice] in place of the lines of file [file].
  const DiffNoticeRow(super.file, this.notice);

  /// Why the file has no lines to show.
  final DiffNotice notice;

  @override
  String toString() => 'DiffNoticeRow($file, ${notice.name})';
}

/// The `@@` line that starts a hunk.
final class DiffHunkHeaderRow extends DiffRow {
  /// The header that starts [hunk].
  const DiffHunkHeaderRow(super.file, this.hunk);

  /// The hunk this header starts; its [DiffHunk.header] is the text.
  final DiffHunk hunk;

  @override
  String toString() => 'DiffHunkHeaderRow($file, ${hunk.header})';
}

/// Unchanged lines that are not shown, which a view can offer to expand.
final class DiffGapRow extends DiffRow {
  /// [count] hidden unchanged lines, identified by [id].
  DiffGapRow(this.id, this.count) : super(id.file);

  /// Add this to `expanded` in [layoutDiff] to show the lines.
  final DiffGapId id;

  /// How many lines expanding the gap would show.
  final int count;

  @override
  String toString() => 'DiffGapRow($id, $count)';
}

/// One line in [DiffMode.unified].
final class DiffLineRow extends DiffRow {
  /// [line] in the unified layout.
  const DiffLineRow(super.file, this.line);

  /// The line, with its old and new numbers.
  final DiffLine line;

  @override
  String toString() => 'DiffLineRow($file, $line)';
}

/// One row in [DiffMode.split]. A context line is on both sides; a removed
/// line without an added partner, or the reverse, leaves one side empty.
final class DiffPairRow extends DiffRow {
  /// [left] and [right] side by side.
  const DiffPairRow(super.file, this.left, this.right);

  /// The old side: a removed or context line, or `null` when empty.
  final DiffLine? left;

  /// The new side: an added or context line, or `null` when empty.
  final DiffLine? right;

  @override
  String toString() => 'DiffPairRow($file, $left | $right)';
}

/// Lays out [files] as the rows a diff view shows, top to bottom.
///
/// Each file with a path starts with a [DiffFileHeaderRow], and files
/// whose index is in [collapsed] stop there. A file without a path has no
/// header to expand it again, so it is never collapsed. A file without
/// hunks gets a [DiffNoticeRow]. When a file has its full texts, as from
/// `diffTexts`, the unchanged lines around hunks become [DiffGapRow]s, or
/// context lines when their [DiffGapId] is in [expanded]. The hunk header
/// after an expanded gap is left out, since the code then runs on without
/// a break.
///
/// [collapsed] and [expanded] refer to files by index, so start them
/// afresh when [files] changes. The result is empty only when [files] is.
List<DiffRow> layoutDiff(
  List<FileDiff> files, {
  DiffMode mode = DiffMode.unified,
  Set<int> collapsed = const {},
  Set<DiffGapId> expanded = const {},
}) => DiffLayout(files, mode: mode, collapsed: collapsed, expanded: expanded);

/// Number of context lines revealed from the beginning and end of a gap.
typedef GapExpansion = ({int before, int after});

final class _RowBlock {
  _RowBlock(
    this.start,
    this.count,
    this.row, {
    this.file = -1,
    this.oldStart,
    this.newStart,
    this.oldCount = 0,
    this.newCount = 0,
  });
  final int start, count, file, oldCount, newCount;
  final int? oldStart, newStart;
  final DiffRow Function(int) row;
}

/// Random-access layout storing runs instead of one object per visible line.
/// Constructing and expanding a large context region costs one block, while
/// accessing an individual row takes logarithmic time.
final class DiffLayout extends ListBase<DiffRow> {
  /// Indexes logical diff rows without allocating a list of every row.
  DiffLayout(
    List<FileDiff> files, {
    this.mode = DiffMode.unified,
    Set<int> collapsed = const {},
    Set<DiffGapId> expanded = const {},
    Map<DiffGapId, GapExpansion> expansions = const {},
    int contextThreshold = 0,
    bool expandAll = false,
  }) {
    RangeError.checkNotNegative(contextThreshold, 'contextThreshold');
    for (var f = 0; f < files.length; f++) {
      final file = files[f];
      final closed = file.path.isNotEmpty && collapsed.contains(f);
      if (file.path.isNotEmpty) _one(DiffFileHeaderRow(f, collapsed: closed));
      if (closed) continue;
      if (file.isBinary) {
        _one(DiffNoticeRow(f, DiffNotice.binary));
        continue;
      }
      if (file.hunks.isEmpty) {
        _one(DiffNoticeRow(f, _noticeFor(file)));
        continue;
      }
      for (var h = 0; h <= file.hunks.length; h++) {
        final id = (file: f, hunk: h);
        final full = expandAll || expanded.contains(id);
        final gapHidden = _gap(
          file,
          id,
          full,
          expansions[id],
          contextThreshold,
        );
        if (h == file.hunks.length) break;
        if (gapHidden || (!full && expansions[id] == null)) {
          _one(DiffHunkHeaderRow(f, file.hunks[h]));
        }
        _hunk(f, file.hunks[h]);
      }
    }
  }

  /// Unified or side-by-side presentation of changed source lines.
  final DiffMode mode;
  final List<_RowBlock> _blocks = [];
  int _length = 0;

  /// Number of compact row runs retained by this layout.
  int get blockCount => _blocks.length;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('DiffLayout is immutable');
  @override
  void operator []=(int index, DiffRow value) =>
      throw UnsupportedError('DiffLayout is immutable');
  @override
  DiffRow operator [](int index) {
    RangeError.checkValidIndex(index, this);
    var low = 0, high = _blocks.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (_blocks[mid].start <= index) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final block = _blocks[low];
    return block.row(index - block.start);
  }

  void _one(DiffRow row) => _add(1, (_) => row, file: row.file);
  void _add(
    int count,
    DiffRow Function(int) row, {
    required int file,
    int? oldStart,
    int? newStart,
    int oldCount = 0,
    int newCount = 0,
  }) {
    if (count <= 0) return;
    _blocks.add(
      _RowBlock(
        _length,
        count,
        row,
        file: file,
        oldStart: oldStart,
        newStart: newStart,
        oldCount: oldCount,
        newCount: newCount,
      ),
    );
    _length += count;
  }

  /// Finds a visible one-based source line, or null if it is hidden.
  int? rowForLine(int file, int number, {bool oldSide = false}) {
    for (final block in _blocks) {
      if (block.file != file) continue;
      final start = oldSide ? block.oldStart : block.newStart;
      final count = oldSide ? block.oldCount : block.newCount;
      if (start != null && number >= start && number < start + count) {
        return block.start + number - start;
      }
    }
    return null;
  }

  /// Finds the header row for a zero-based file index.
  int? rowForFile(int file) {
    for (final block in _blocks) {
      if (block.file == file) return block.start;
    }
    return null;
  }

  bool _gap(
    FileDiff file,
    DiffGapId id,
    bool full,
    GapExpansion? expansion,
    int threshold,
  ) {
    final lines = file.newLines;
    if (lines == null) return true;
    final previous = id.hunk == 0 ? null : file.hunks[id.hunk - 1];
    final next = id.hunk == file.hunks.length ? null : file.hunks[id.hunk];
    final first = previous == null ? 1 : _newEnd(previous) + 1;
    final last = next == null
        ? lines.length
        : next.newStart - (next.newCount == 0 ? 0 : 1);
    final count = math.max(0, last - first + 1);
    final shift = previous == null ? 0 : _oldEnd(previous) - _newEnd(previous);
    final before = full || count <= threshold
        ? count
        : (expansion?.before ?? 0).clamp(0, count);
    final after = (expansion?.after ?? 0).clamp(0, count - before);
    void context(int start, int amount) {
      _add(
        amount,
        (index) {
          final n = start + index;
          final line = DiffLine(
            DiffLineKind.context,
            lines[n - 1],
            oldNumber: n + shift,
            newNumber: n,
          );
          return mode == DiffMode.unified
              ? DiffLineRow(id.file, line)
              : DiffPairRow(id.file, line, line);
        },
        file: id.file,
        oldStart: start + shift,
        newStart: start,
        oldCount: amount,
        newCount: amount,
      );
    }

    context(first, before);
    if (before + after < count) _one(DiffGapRow(id, count - before - after));
    context(last - after + 1, after);
    return before + after < count;
  }

  void _hunk(int file, DiffHunk hunk) {
    final lines = hunk.lines;
    var i = 0;
    while (i < lines.length) {
      final start = i;
      final kind = lines[i].kind;
      if (mode == DiffMode.unified || kind == DiffLineKind.context) {
        while (i < lines.length && lines[i].kind == kind) {
          i++;
        }
        final count = i - start;
        _add(
          count,
          (j) => mode == DiffMode.unified
              ? DiffLineRow(file, lines[start + j])
              : DiffPairRow(file, lines[start + j], lines[start + j]),
          file: file,
          oldStart: lines[start].oldNumber,
          newStart: lines[start].newNumber,
          oldCount: kind != DiffLineKind.added ? count : 0,
          newCount: kind != DiffLineKind.removed ? count : 0,
        );
      } else {
        while (i < lines.length && lines[i].kind == DiffLineKind.removed) {
          i++;
        }
        final addedStart = i;
        while (i < lines.length && lines[i].kind == DiffLineKind.added) {
          i++;
        }
        final removed = addedStart - start, added = i - addedStart;
        _add(
          math.max(removed, added),
          (j) => DiffPairRow(
            file,
            j < removed ? lines[start + j] : null,
            j < added ? lines[addedStart + j] : null,
          ),
          file: file,
          oldStart: removed > 0 ? lines[start].oldNumber : null,
          newStart: added > 0 ? lines[addedStart].newNumber : null,
          oldCount: removed,
          newCount: added,
        );
      }
    }
  }
}

DiffNotice _noticeFor(FileDiff file) => switch (file.kind) {
  FileDiffKind.renamed => DiffNotice.renamedWithoutChanges,
  FileDiffKind.copied => DiffNotice.copiedWithoutChanges,
  FileDiffKind.added || FileDiffKind.deleted => DiffNotice.emptyFile,
  FileDiffKind.modified when file.newLines == null =>
    DiffNotice.noContentChanges,
  FileDiffKind.modified => DiffNotice.noChanges,
};

/// The last new line a hunk covers; for a hunk without new lines, the line
/// before it.
int _newEnd(DiffHunk h) =>
    h.newCount == 0 ? h.newStart : h.newStart + h.newCount - 1;
int _oldEnd(DiffHunk h) =>
    h.oldCount == 0 ? h.oldStart : h.oldStart + h.oldCount - 1;
