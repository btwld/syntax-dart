/// @docImport 'file_diff.dart';
library;

import 'diff_selection.dart';

/// Application data attached to a one-based source line in a file revision.
///
/// Equality compares every field, including [data] using its own equality.
/// The payload is retained unchanged; callers should keep its equality and
/// hash code stable while using the annotation as a map key or set element.
final class DiffAnnotation<T> {
  /// Creates an annotation with a stable, nonempty [id].
  ///
  /// Use [FileDiff.id] and [FileDiff.revision] for [fileId] and [revision].
  /// Throws a [RangeError] if [line] is less than one, or an [ArgumentError]
  /// if [id] is empty or [sourceSelection] addresses a different file or
  /// revision. Consumers must also check the revision against the current file
  /// before displaying the annotation; a matching line number is insufficient.
  DiffAnnotation({
    required this.id,
    required this.fileId,
    required this.revision,
    required this.side,
    required this.line,
    required this.data,
    this.sourceSelection,
  }) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty');
    }
    if (line < 1) throw RangeError.range(line, 1, null, 'line');
    final selection = sourceSelection;
    if (selection != null &&
        (selection.fileId != fileId || selection.revision != revision)) {
      throw ArgumentError.value(
        selection,
        'sourceSelection',
        'Must address the same file and revision as the annotation',
      );
    }
  }

  /// The stable annotation identity within the file.
  final String id;

  /// The stable [FileDiff.id] of the annotated file.
  final String fileId;

  /// The [FileDiff.revision] to which the annotation belongs.
  final int revision;

  /// The source side at the display [line].
  final DiffSide side;

  /// The one-based source line at which to display the annotation.
  final int line;

  /// The application-owned payload, passed unchanged to renderers.
  final T data;

  /// The original directed range, independent of the display [line] and [side].
  ///
  /// Both endpoints and their sides are preserved, including cross-side ranges.
  /// Its file identity and revision must match [fileId] and [revision]. A `null`
  /// value associates only [line] on [side].
  final DiffSelection? sourceSelection;

  @override
  bool operator ==(Object other) =>
      other is DiffAnnotation<Object?> &&
      other.id == id &&
      other.fileId == fileId &&
      other.revision == revision &&
      other.side == side &&
      other.line == line &&
      other.data == data &&
      other.sourceSelection == sourceSelection;

  @override
  int get hashCode =>
      Object.hash(id, fileId, revision, side, line, data, sourceSelection);
}
