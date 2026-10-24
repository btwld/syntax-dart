import 'dart:math' as math;

/// The role of a line in a diff.
enum DiffLineKind {
  /// In both files, shown for context.
  context,

  /// Only in the new file.
  added,

  /// Only in the old file.
  removed,
}

/// One line of a hunk.
final class DiffLine {
  /// A line of [kind] with [text]. Context lines have both numbers,
  /// removed lines only [oldNumber] and added lines only [newNumber].
  const DiffLine(
    this.kind,
    this.text, {
    this.oldNumber,
    this.newNumber,
    this.noNewlineAtEnd = false,
    this.sourceLineEnding = '\n',
  });

  /// Whether the line was kept, added or removed.
  final DiffLineKind kind;

  /// The line's text, without the leading `+`, `-` or space.
  final String text;

  /// 1-based line number in the old file. `null` for added lines.
  final int? oldNumber;

  /// 1-based line number in the new file. `null` for removed lines.
  final int? newNumber;

  /// Whether this is the last line of its file and has no line break, as
  /// marked by `\ No newline at end of file`.
  final bool noNewlineAtEnd;

  /// Original source terminator, independent of patch transport line endings.
  /// [noNewlineAtEnd] takes precedence for an unterminated final source line.
  final String sourceLineEnding;

  @override
  bool operator ==(Object other) =>
      other is DiffLine &&
      other.kind == kind &&
      other.text == text &&
      other.oldNumber == oldNumber &&
      other.newNumber == newNumber &&
      other.sourceLineEnding == sourceLineEnding &&
      other.noNewlineAtEnd == noNewlineAtEnd;

  @override
  int get hashCode => Object.hash(
    kind,
    text,
    oldNumber,
    newNumber,
    noNewlineAtEnd,
    sourceLineEnding,
  );

  @override
  String toString() =>
      '${switch (kind) {
        DiffLineKind.context => ' ',
        DiffLineKind.added => '+',
        DiffLineKind.removed => '-',
      }}$text';
}

/// A run of changes with its surrounding context, the part of a patch that
/// starts with `@@ -oldStart,oldCount +newStart,newCount @@`.
final class DiffHunk {
  /// A hunk with its line ranges in the old and new files.
  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
    this.section = '',
  });

  /// The first old line the hunk covers, 1-based. With no old lines,
  /// the line before the hunk, as in git.
  final int oldStart;

  /// How many old lines the hunk covers: its context and removed lines.
  final int oldCount;

  /// The first new line the hunk covers, 1-based. With no new lines,
  /// the line before the hunk, as in git.
  final int newStart;

  /// How many new lines the hunk covers: its context and added lines.
  final int newCount;

  /// Text after the closing `@@`, usually the enclosing function or class.
  final String section;

  /// The hunk's lines, in order.
  final List<DiffLine> lines;

  /// The hunk header as git prints it, for example
  /// `@@ -12,7 +12,9 @@ class Foo`. A count of 1 is left out: `@@ -3 +3 @@`.
  String get header =>
      '@@ -${_range(oldStart, oldCount)} +${_range(newStart, newCount)} @@'
      '${section.isEmpty ? '' : ' $section'}';

  static String _range(int start, int count) =>
      count == 1 ? '$start' : '$start,$count';
}

/// What happened to a file.
enum FileDiffKind {
  /// Changed in place.
  modified,

  /// New in this change.
  added,

  /// Removed in this change.
  deleted,

  /// Moved to [FileDiff.newPath], possibly with changes.
  renamed,

  /// Copied from [FileDiff.oldPath], possibly with changes. Git reports
  /// copies with `--find-copies`.
  copied,
}

/// The changes to one file.
final class FileDiff {
  /// The changes to one file. Only `diffTexts` fills in [oldLines] and
  /// [newLines].
  const FileDiff({
    required this.oldPath,
    required this.newPath,
    required this.kind,
    required this.hunks,
    this.isBinary = false,
    this.oldLines,
    this.newLines,
    this.identity,
    this.revision = 0,
    this.language,
    this.oldText,
    this.newText,
    this.oldObjectId,
    this.newObjectId,
    this.oldMode,
    this.newMode,
    this.patchLineEnding = '\n',
  });

  /// Stable caller-supplied identity; defaults to the pair of paths.
  final String? identity;

  /// Stable key for retained UI state.
  String get id => identity ?? '${oldPath ?? ''}\u0000${newPath ?? ''}';

  /// Content revision for asynchronous operations.
  final int revision;

  /// Explicit language override.
  final String? language;

  /// Complete source texts, including their original line endings.
  final String? oldText;

  /// Complete new-side source, preserving terminators, or null for a partial patch.
  final String? newText;

  /// Object IDs and modes recorded in Git patch headers.
  final String? oldObjectId;

  /// New Git object identifier when present in the patch header.
  final String? newObjectId;

  /// Original Git file mode when supplied by the patch.
  final String? oldMode;

  /// Updated Git file mode when supplied by the patch.
  final String? newMode;

  /// Transport line ending used by the original patch.
  final String patchLineEnding;

  /// Whether unchanged content is unavailable.
  bool get isPartial => oldText == null || newText == null;

  /// Replaces computed data while preserving source metadata and identity.
  /// Changing a known full source invalidates that side's Git object ID.
  FileDiff copyWith({
    List<DiffHunk>? hunks,
    List<String>? oldLines,
    List<String>? newLines,
    String? oldText,
    String? newText,
    int? revision,
    String? patchLineEnding,
    String? language,
    String? identity,
  }) => FileDiff(
    oldPath: oldPath,
    newPath: newPath,
    kind: kind,
    hunks: hunks ?? this.hunks,
    isBinary: isBinary,
    oldLines: oldLines ?? this.oldLines,
    newLines: newLines ?? this.newLines,
    oldText: oldText ?? this.oldText,
    newText: newText ?? this.newText,
    identity: identity ?? this.identity,
    revision: revision ?? this.revision,
    language: language ?? this.language,
    oldObjectId:
        oldText != null && this.oldText != null && oldText != this.oldText
        ? null
        : oldObjectId,
    newObjectId:
        newText != null && this.newText != null && newText != this.newText
        ? null
        : newObjectId,
    oldMode: oldMode,
    newMode: newMode,
    patchLineEnding: patchLineEnding ?? this.patchLineEnding,
  );

  /// Path before the change, or `null` for an added file.
  final String? oldPath;

  /// Path after the change, or `null` for a deleted file.
  final String? newPath;

  /// What happened to the file.
  final FileDiffKind kind;

  /// The changed regions, in file order. Empty for a binary file, a
  /// pure rename or copy, or a mode change.
  final List<DiffHunk> hunks;

  /// Whether the patch marks the file as binary, which has no lines.
  final bool isBinary;

  /// The complete old and new files, when known. Diffs built with
  /// `diffTexts` have them, which lets a viewer show the unchanged lines
  /// between hunks. Parsed patches do not.
  final List<String>? oldLines;

  /// See [oldLines].
  final List<String>? newLines;

  /// The path to show: the new path, or the old one for a deleted file.
  String get path => newPath ?? oldPath ?? '';

  /// How many lines were added.
  int get additions => _count(DiffLineKind.added);

  /// How many lines were removed.
  int get deletions => _count(DiffLineKind.removed);

  /// Whether the file was renamed or copied, so it has an old and a new
  /// path to show.
  bool get isRenameOrCopy =>
      kind == FileDiffKind.renamed || kind == FileDiffKind.copied;

  /// The number of squares in a GitHub-style change bar.
  static const int changeBarSize = 5;

  /// How many of the [changeBarSize] squares go to additions and to
  /// deletions. Each kind of change that happened gets at least one.
  /// Without changes, both are 0.
  ({int added, int removed}) changeBlocks() {
    final total = additions + deletions;
    if (total == 0) return (added: 0, removed: 0);
    final added = (changeBarSize * additions / total).round().clamp(
      additions > 0 ? 1 : 0,
      deletions > 0 ? changeBarSize - 1 : changeBarSize,
    );
    return (added: added, removed: changeBarSize - added);
  }

  /// The largest line number a view of this diff can show, for sizing a
  /// line-number gutter. With the full texts, that includes every line of
  /// both files, since unchanged lines can be expanded.
  int get maxLineNumber {
    var largest = math.max(oldLines?.length ?? 0, newLines?.length ?? 0);
    for (final hunk in hunks) {
      largest = math.max(
        largest,
        math.max(
          hunk.oldStart + math.max(hunk.oldCount - 1, 0),
          hunk.newStart + math.max(hunk.newCount - 1, 0),
        ),
      );
    }
    return largest;
  }

  int _count(DiffLineKind kind) => hunks.fold(
    0,
    (sum, hunk) => sum + hunk.lines.where((l) => l.kind == kind).length,
  );
}
