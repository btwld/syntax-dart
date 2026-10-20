import 'diff_layout.dart';
import 'file_diff.dart';

/// The words a diff view shows, and announces to screen readers.
///
/// Every label has an English default. To translate a view, extend this
/// class, override what you need, and pass an instance to the view.
class DiffLabels {
  /// The English labels.
  const DiffLabels();

  /// Shown when there are no files at all.
  String get noFiles => 'No changes';

  /// Shown in place of a file's lines.
  String notice(DiffNotice notice) => switch (notice) {
    DiffNotice.binary => 'Binary file not shown',
    DiffNotice.renamedWithoutChanges => 'File renamed without changes',
    DiffNotice.copiedWithoutChanges => 'File copied without changes',
    DiffNotice.emptyFile => 'Empty file',
    DiffNotice.noContentChanges => 'No content changes',
    DiffNotice.noChanges => 'No changes',
  };

  /// The badge for a file's status. `null` shows no badge.
  String? status(FileDiffKind kind) => switch (kind) {
    FileDiffKind.added => 'Added',
    FileDiffKind.deleted => 'Deleted',
    FileDiffKind.renamed => 'Renamed',
    FileDiffKind.copied => 'Copied',
    FileDiffKind.modified => null,
  };

  /// The bar that shows [count] hidden unchanged lines.
  String showUnchangedLines(int count) =>
      count == 1 ? 'Show 1 unchanged line' : 'Show $count unchanged lines';

  /// What screen readers announce for a file's header.
  String fileHeader(FileDiff file) {
    final moved =
        file.kind == FileDiffKind.renamed || file.kind == FileDiffKind.copied;
    final additions = file.additions;
    final deletions = file.deletions;
    return [
      status(file.kind) ?? 'Modified',
      if (moved) '${file.oldPath} to ${file.newPath}' else file.path,
      if (file.isBinary)
        'binary'
      else ...[
        additions == 1 ? '1 addition' : '$additions additions',
        deletions == 1 ? '1 deletion' : '$deletions deletions',
      ],
    ].join(', ');
  }

  /// What screen readers announce before an added or removed line.
  /// [number] is its line number in the new or the old file.
  String changedLine(DiffLineKind kind, int? number) => switch (kind) {
    DiffLineKind.added => 'Added line $number',
    DiffLineKind.removed => 'Removed line $number',
    DiffLineKind.context => 'Line $number',
  };

  /// The tooltip on a last line that has no line break.
  String get noNewlineAtEnd => 'No newline at end of file';
}
