import 'package:syntax_core/syntax.dart';

/// A one-based source coordinate offered to a patch gutter builder.
final class DiffLineContext {
  /// Addresses [line] on [side] of [file].
  const DiffLineContext({
    required this.file,
    required this.side,
    required this.line,
  });

  /// The current file, including its stable identity and source revision.
  final FileDiff file;

  /// The source version addressed by [line].
  final DiffSide side;

  /// One-based source line number.
  final int line;
}

/// A rendered source row and its current, revision-checked annotations.
final class DiffRowContext<T> {
  /// Creates a context with an immutable snapshot of [annotations].
  DiffRowContext({
    required this.file,
    required this.row,
    required List<DiffAnnotation<T>> annotations,
  }) : annotations = List.unmodifiable(annotations);

  /// The current file.
  final FileDiff file;

  /// The source row; a split row can address both sides.
  final DiffRow row;

  /// Application payloads anchored to this row in the current file revision.
  final List<DiffAnnotation<T>> annotations;
}

/// A directed gutter selection and the source it would copy.
final class DiffSelectionDetails {
  /// Describes [selection] in [file].
  const DiffSelectionDetails({
    required this.file,
    required this.selection,
    required this.selectedText,
  });

  /// The file containing the selection.
  final FileDiff file;

  /// Inclusive source endpoints, with their original direction and sides.
  final DiffSelection selection;

  /// Source text in diff order, excluding presentation widgets.
  final String selectedText;
}
