import 'compact.dart';
import 'file_diff.dart';
import 'myers.dart';

/// Compares two versions of a file line by line, like `git diff`.
///
/// When a change could sit in more than one place, such as a line added
/// among identical lines, it goes where `git diff` puts it. Like git, that
/// uses the indent heuristic, which looks at the indents and blank lines
/// around each spot so that, for example, an added function shows as the
/// whole function. With [indentHeuristic] false, changes go where
/// `git diff --no-indent-heuristic` puts them.
///
/// Hunks get [contextLines] unchanged lines on each side, and hunks whose
/// context would touch are merged. The result keeps both full texts in
/// [FileDiff.oldLines] and [FileDiff.newLines], so a viewer can expand the
/// unchanged regions between hunks. [path] names the file, and also picks
/// the language for highlighting. The result is always
/// [FileDiffKind.modified] with both paths set to [path]: an empty text is
/// an empty file, not a missing one.
///
/// Lines are compared with their line endings, so converting CRLF to LF is
/// a change, but [DiffLine.text] never includes the `\r`. Texts that differ
/// in more than about a thousand places, after any shared lines at the
/// start and end, are shown as one block that replaces the old lines with
/// the new ones.
FileDiff diffTexts(
  String oldText,
  String newText, {
  String path = '',
  int contextLines = 3,
  bool indentHeuristic = true,
}) {
  RangeError.checkNotNegative(contextLines, 'contextLines');
  final before = _Text(oldText);
  final after = _Text(newText);

  // Compare lines as ints. The last line's key includes whether it ends
  // with a line break, so adding or removing a final newline is a change.
  final ids = <String, int>{};
  List<int> keys(_Text t) => [
    for (var i = 0; i < t.raw.length; i++)
      ids.putIfAbsent(
        t.isLastWithoutNewline(i) ? '${t.raw[i]}\u0000' : t.raw[i],
        () => ids.length,
      ),
  ];
  final oldKeys = keys(before);
  final newKeys = keys(after);
  final edits = compactEdits(
    myersDiff(oldKeys, newKeys),
    oldKeys,
    newKeys,
    aLines: indentHeuristic ? before.raw : null,
    bLines: indentHeuristic ? after.raw : null,
  );

  final hunks = <DiffHunk>[];
  var i = 0;
  while (true) {
    while (i < edits.length && edits[i].kind == EditKind.equal) {
      i++;
    }
    if (i == edits.length) break;
    final start = i - contextLines < 0 ? 0 : i - contextLines;
    // Take in later changes while the unchanged gap is small enough that
    // their context would touch.
    var end = i;
    while (true) {
      while (end < edits.length && edits[end].kind != EditKind.equal) {
        end++;
      }
      var next = end;
      while (next < edits.length && edits[next].kind == EditKind.equal) {
        next++;
      }
      if (next < edits.length && next - end <= 2 * contextLines) {
        end = next;
        continue;
      }
      end = end + contextLines < edits.length
          ? end + contextLines
          : edits.length;
      break;
    }
    hunks.add(_hunk(edits, start, end, before, after));
    i = end;
  }

  return FileDiff(
    oldPath: path,
    newPath: path,
    kind: FileDiffKind.modified,
    hunks: List.unmodifiable(hunks),
    oldLines: List.unmodifiable(before.lines),
    newLines: List.unmodifiable(after.lines),
  );
}

DiffHunk _hunk(
  List<Edit> edits,
  int start,
  int end,
  _Text before,
  _Text after,
) {
  final lines = <DiffLine>[
    for (final e in edits.sublist(start, end))
      switch (e.kind) {
        EditKind.equal => DiffLine(
          DiffLineKind.context,
          after.lines[e.newIndex],
          oldNumber: e.oldIndex + 1,
          newNumber: e.newIndex + 1,
          noNewlineAtEnd: after.isLastWithoutNewline(e.newIndex),
        ),
        EditKind.delete => DiffLine(
          DiffLineKind.removed,
          before.lines[e.oldIndex],
          oldNumber: e.oldIndex + 1,
          noNewlineAtEnd: before.isLastWithoutNewline(e.oldIndex),
        ),
        EditKind.insert => DiffLine(
          DiffLineKind.added,
          after.lines[e.newIndex],
          newNumber: e.newIndex + 1,
          noNewlineAtEnd: after.isLastWithoutNewline(e.newIndex),
        ),
      },
  ];

  // Lines on each side before the hunk. Git starts an empty side at the
  // line before the hunk, and a non-empty side at its first line.
  int linesBefore(int Function(Edit) index) {
    for (var j = start - 1; j >= 0; j--) {
      if (index(edits[j]) >= 0) return index(edits[j]) + 1;
    }
    return 0;
  }

  final oldCount = lines.where((l) => l.kind != DiffLineKind.added).length;
  final newCount = lines.where((l) => l.kind != DiffLineKind.removed).length;
  final oldBefore = linesBefore((e) => e.oldIndex);
  final newBefore = linesBefore((e) => e.newIndex);
  return DiffHunk(
    oldStart: oldCount == 0 ? oldBefore : oldBefore + 1,
    oldCount: oldCount,
    newStart: newCount == 0 ? newBefore : newBefore + 1,
    newCount: newCount,
    section: _section(before.lines, oldBefore),
    lines: List.unmodifiable(lines),
  );
}

/// The hunk's section heading, found the way git does by default: the
/// closest line above the hunk that starts with a letter, `_` or `$`.
String _section(List<String> lines, int before) {
  for (var i = before - 1; i >= 0; i--) {
    final line = lines[i];
    if (line.isNotEmpty && _sectionStart.hasMatch(line)) {
      return (line.length > 80 ? line.substring(0, 80) : line).trimRight();
    }
  }
  return '';
}

final RegExp _sectionStart = RegExp(r'^[A-Za-z_$]');

/// A file split into lines the way `git diff` sees them.
final class _Text {
  factory _Text(String text) {
    if (text.isEmpty) return _Text._(const [], const [], false);
    final raw = text.split('\n');
    final noFinalNewline = !text.endsWith('\n');
    if (!noFinalNewline) raw.removeLast();
    final lines = text.contains('\r')
        ? [
            for (final line in raw)
              line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
          ]
        : raw;
    return _Text._(raw, lines, noFinalNewline);
  }

  _Text._(this.raw, this.lines, this._noFinalNewline);

  /// Lines with any trailing `\r`, for comparing.
  final List<String> raw;

  /// Lines without a trailing `\r`, for showing.
  final List<String> lines;
  final bool _noFinalNewline;

  bool isLastWithoutNewline(int index) =>
      _noFinalNewline && index == lines.length - 1;
}
