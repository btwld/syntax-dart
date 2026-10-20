import 'dart:math' as math;

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
}) {
  final rows = <DiffRow>[];
  for (var f = 0; f < files.length; f++) {
    final file = files[f];
    final isCollapsed = file.path.isNotEmpty && collapsed.contains(f);
    if (file.path.isNotEmpty) {
      rows.add(DiffFileHeaderRow(f, collapsed: isCollapsed));
    }
    if (isCollapsed) continue;
    if (file.isBinary) {
      rows.add(DiffNoticeRow(f, DiffNotice.binary));
      continue;
    }
    if (file.hunks.isEmpty) {
      rows.add(DiffNoticeRow(f, _noticeFor(file)));
      continue;
    }
    final hasTexts = file.newLines != null;
    for (var h = 0; h < file.hunks.length; h++) {
      final gap = (file: f, hunk: h);
      if (hasTexts) _addGap(rows, file, gap, mode, expanded.contains(gap));
      if (!expanded.contains(gap)) {
        rows.add(DiffHunkHeaderRow(f, file.hunks[h]));
      }
      _addHunk(rows, f, file.hunks[h], mode);
    }
    if (hasTexts) {
      final gap = (file: f, hunk: file.hunks.length);
      _addGap(rows, file, gap, mode, expanded.contains(gap));
    }
  }
  return rows;
}

DiffNotice _noticeFor(FileDiff file) => switch (file.kind) {
  FileDiffKind.renamed => DiffNotice.renamedWithoutChanges,
  FileDiffKind.copied => DiffNotice.copiedWithoutChanges,
  FileDiffKind.added || FileDiffKind.deleted => DiffNotice.emptyFile,
  FileDiffKind.modified when file.newLines == null =>
    DiffNotice.noContentChanges,
  FileDiffKind.modified => DiffNotice.noChanges,
};

/// Adds the unchanged lines of [gap], collapsed or as context lines.
void _addGap(
  List<DiffRow> rows,
  FileDiff file,
  DiffGapId gap,
  DiffMode mode,
  bool isExpanded,
) {
  final newLines = file.newLines!;
  final previous = gap.hunk == 0 ? null : file.hunks[gap.hunk - 1];
  final next = gap.hunk < file.hunks.length ? file.hunks[gap.hunk] : null;
  final firstNew = previous == null ? 1 : _newEnd(previous) + 1;
  // A hunk without new lines starts after line newStart, not at it.
  final lastNew = next == null
      ? newLines.length
      : (next.newCount == 0 ? next.newStart : next.newStart - 1);
  final count = lastNew - firstNew + 1;
  if (count <= 0) return;
  if (!isExpanded) {
    rows.add(DiffGapRow(gap, count));
    return;
  }
  // Old line numbers in a gap are offset by the changes above it.
  final shift = previous == null ? 0 : _oldEnd(previous) - _newEnd(previous);
  for (var n = firstNew; n <= lastNew; n++) {
    final line = DiffLine(
      DiffLineKind.context,
      newLines[n - 1],
      oldNumber: n + shift,
      newNumber: n,
    );
    rows.add(
      mode == DiffMode.unified
          ? DiffLineRow(gap.file, line)
          : DiffPairRow(gap.file, line, line),
    );
  }
}

/// The last new line a hunk covers; for a hunk without new lines, the line
/// before it.
int _newEnd(DiffHunk h) =>
    h.newCount == 0 ? h.newStart : h.newStart + h.newCount - 1;
int _oldEnd(DiffHunk h) =>
    h.oldCount == 0 ? h.oldStart : h.oldStart + h.oldCount - 1;

void _addHunk(List<DiffRow> rows, int file, DiffHunk hunk, DiffMode mode) {
  final lines = hunk.lines;
  if (mode == DiffMode.unified) {
    for (final line in lines) {
      rows.add(DiffLineRow(file, line));
    }
    return;
  }
  var i = 0;
  while (i < lines.length) {
    if (lines[i].kind == DiffLineKind.context) {
      rows.add(DiffPairRow(file, lines[i], lines[i]));
      i++;
      continue;
    }
    final removed = <DiffLine>[];
    final added = <DiffLine>[];
    while (i < lines.length && lines[i].kind == DiffLineKind.removed) {
      removed.add(lines[i++]);
    }
    while (i < lines.length && lines[i].kind == DiffLineKind.added) {
      added.add(lines[i++]);
    }
    for (var p = 0; p < math.max(removed.length, added.length); p++) {
      rows.add(
        DiffPairRow(
          file,
          p < removed.length ? removed[p] : null,
          p < added.length ? added[p] : null,
        ),
      );
    }
  }
}
