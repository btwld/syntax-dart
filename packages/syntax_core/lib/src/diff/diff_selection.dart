/// @docImport 'file_diff.dart';
library;

/// The source version addressed by a diff coordinate.
enum DiffSide {
  /// The file before the change.
  old,

  /// The file after the change.
  newer,
}

/// A directed, inclusive range of one-based source lines in a file revision.
///
/// A selection can cross sides, for example when copying removed and added
/// lines together. The endpoints retain their sides and direction; resolving
/// their order in the diff requires the corresponding [FileDiff].
final class DiffSelection {
  /// Creates a range with a fixed [anchor] and a moving [active] endpoint.
  ///
  /// [activeSide] defaults to [side]. Use [FileDiff.id] and [FileDiff.revision]
  /// for [fileId] and [revision]. Throws a [RangeError] if either endpoint is
  /// less than one. Line availability is checked by the consumer of the range.
  DiffSelection({
    required this.fileId,
    required this.revision,
    required this.side,
    required this.anchor,
    required this.active,
    DiffSide? activeSide,
  }) : activeSide = activeSide ?? side {
    if (anchor < 1) throw RangeError.range(anchor, 1, null, 'anchor');
    if (active < 1) throw RangeError.range(active, 1, null, 'active');
  }

  /// The stable [FileDiff.id] of the selected file.
  final String fileId;

  /// The [FileDiff.revision] to which the coordinates belong.
  final int revision;

  /// The source side at the fixed [anchor] endpoint.
  final DiffSide side;

  /// The source side at the moving [active] endpoint.
  final DiffSide activeSide;

  /// The fixed one-based source line, inclusive.
  final int anchor;

  /// The moving one-based source line, inclusive.
  final int active;

  /// The smaller endpoint line number, inclusive.
  ///
  /// When [crossesSides] is true, this is a numeric bound, not the first row
  /// in diff order, because the endpoints address different source versions.
  int get start => anchor < active ? anchor : active;

  /// The larger endpoint line number, inclusive.
  ///
  /// When [crossesSides] is true, this is a numeric bound, not the last row
  /// in diff order.
  int get end => anchor > active ? anchor : active;

  /// Whether the endpoints address different source versions.
  bool get crossesSides => side != activeSide;

  @override
  bool operator ==(Object other) =>
      other is DiffSelection &&
      other.fileId == fileId &&
      other.revision == revision &&
      other.side == side &&
      other.activeSide == activeSide &&
      other.anchor == anchor &&
      other.active == active;

  @override
  int get hashCode =>
      Object.hash(fileId, revision, side, activeSide, anchor, active);
}
