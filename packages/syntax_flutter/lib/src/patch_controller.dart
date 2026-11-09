import 'package:flutter/foundation.dart';
import 'package:syntax_core/syntax.dart';

/// Revision-bound selection, folding and navigation for read-only patches.
///
/// Files must have distinct stable IDs. Coordinates are one-based, inclusive.
/// Dispose this caller-owned controller when it is no longer needed.
class PatchController<T> extends ChangeNotifier {
  /// Starts with [files] in display order, optionally in split [mode].
  PatchController(Iterable<FileDiff> files, {DiffMode mode = DiffMode.unified})
    : _mode = mode {
    setFiles(files);
  }

  List<FileDiff> _files = const [];
  Map<String, int> _indices = {};
  final Map<String, DiffLayout> _availableLayouts = {};
  final Set<String> _collapsed = {};
  final Set<(String, int)> _collapsedHunks = {};
  final Set<(String, int)> _expanded = {};
  DiffMode _mode;
  DiffLayout? _layout;
  DiffSelection? _selection;
  List<DiffAnnotation<T>> _annotations = const [];
  ({String fileId, DiffSide side, int line, int revision})? _reveal;
  int _revealRequest = 0;

  /// Immutable files in display order; folding follows IDs across reordering.
  List<FileDiff> get files => _files;

  /// Unified or side-by-side presentation, shared by controlled views.
  DiffMode get mode => _mode;

  /// Changes presentation without clearing selection, annotations or folding.
  set mode(DiffMode value) {
    if (_mode == value) return;
    _mode = value;
    _layoutChanged();
  }

  /// Compact row index, retained across selection and annotation changes.
  DiffLayout get layout => _layout ??= DiffLayout(
    _files,
    mode: _mode,
    collapsed: {for (final id in _collapsed) _indices[id]!},
    collapsedHunks: {
      for (final (id, hunk) in _collapsedHunks)
        (file: _indices[id]!, hunk: hunk),
    },
    expanded: {
      for (final (id, hunk) in _expanded) (file: _indices[id]!, hunk: hunk),
    },
  );

  /// Directed selection, independent of which source rows are mounted or folded.
  DiffSelection? get selection => _selection;

  /// Immutable application annotations matching the current file revisions.
  List<DiffAnnotation<T>> get annotations => _annotations;

  /// Replaces sources and rejects duplicate IDs before changing any state.
  ///
  /// File folding survives replacement. Hunk/context folding, selection,
  /// annotations and pending navigation are cleared for removed or replaced
  /// sources. A new revision or changed source/hunks constitutes replacement;
  /// callers should advance revisions whenever source coordinates change.
  void setFiles(Iterable<FileDiff> files) {
    final next = List<FileDiff>.unmodifiable(files);
    final indices = {for (var i = 0; i < next.length; i++) next[i].id: i};
    if (indices.length != next.length) {
      throw ArgumentError('Each file must have a distinct identity');
    }
    if (listEquals(next, _files)) return;
    final changed = <String>{};
    for (final old in _files) {
      final index = indices[old.id];
      if (index == null || !_sameSource(old, next[index])) changed.add(old.id);
    }
    _collapsed.retainAll(indices.keys);
    _collapsedHunks.removeWhere((key) => changed.contains(key.$1));
    _expanded.removeWhere((key) => changed.contains(key.$1));
    if (changed.contains(_selection?.fileId)) _selection = null;
    if (changed.contains(_reveal?.fileId)) _reveal = null;
    _annotations = List.unmodifiable(
      _annotations.where((a) => !changed.contains(a.fileId)),
    );
    _files = next;
    _indices = indices;
    _availableLayouts.clear();
    _layoutChanged();
  }

  bool _sameSource(FileDiff a, FileDiff b) =>
      identical(a, b) ||
      (a.revision == b.revision &&
          identical(a.hunks, b.hunks) &&
          listEquals(a.oldLines, b.oldLines) &&
          listEquals(a.newLines, b.newLines) &&
          a.oldText == b.oldText &&
          a.newText == b.newText &&
          a.isBinary == b.isBinary);

  /// Whether the file's source rows are hidden.
  bool isCollapsed(String fileId) => _collapsed.contains(fileId);

  /// Hides or shows a known file without discarding selection or annotations.
  /// Throws [ArgumentError] for an unknown ID. Pathless files cannot fold.
  void setCollapsed(String fileId, bool collapsed) {
    final file = _file(fileId);
    if (file.path.isEmpty) return;
    final changed = collapsed
        ? _collapsed.add(fileId)
        : _collapsed.remove(fileId);
    if (changed) _layoutChanged();
  }

  /// Folds a zero-based hunk without discarding selection or annotations.
  /// Throws [ArgumentError] for an unknown file and [RangeError] for a bad hunk.
  void setHunkCollapsed(String fileId, int hunk, bool collapsed) {
    RangeError.checkValidIndex(hunk, _file(fileId).hunks, 'hunk');
    final changed = collapsed
        ? _collapsedHunks.add((fileId, hunk))
        : _collapsedHunks.remove((fileId, hunk));
    if (changed) _layoutChanged();
  }

  /// Replaces annotations, ignoring unavailable lines and obsolete revisions.
  /// Duplicate annotation IDs within a file throw [ArgumentError]. Annotation
  /// updates retain the layout, folding, selection and pending navigation.
  void setAnnotations(Iterable<DiffAnnotation<T>> annotations) {
    final ids = <(String, String)>{};
    final next = <DiffAnnotation<T>>[];
    for (final annotation in annotations) {
      if (!ids.add((annotation.fileId, annotation.id))) {
        throw ArgumentError('Annotation IDs must be distinct within a file');
      }
      if (_available(
        annotation.fileId,
        annotation.revision,
        annotation.side,
        annotation.line,
      )) {
        next.add(annotation);
      }
    }
    if (listEquals(next, _annotations)) return;
    _annotations = List.unmodifiable(next);
    notifyListeners();
  }

  /// Sets a directed selection, including cross-side ranges, or clears it.
  /// Throws [ArgumentError] for stale revisions or unavailable endpoints.
  void select(DiffSelection? selection) {
    if (selection != null &&
        (!_available(
              selection.fileId,
              selection.revision,
              selection.side,
              selection.anchor,
            ) ||
            !_available(
              selection.fileId,
              selection.revision,
              selection.activeSide,
              selection.active,
            ))) {
      throw ArgumentError.value(selection, 'selection', 'Unavailable source');
    }
    if (_selection == selection) return;
    _selection = selection;
    notifyListeners();
  }

  /// Opens the target's file, hunk or context gap and requests viewport reveal.
  /// Returns false for unknown files, stale revisions or unavailable lines
  /// (including omitted context in partial patches), without changing state.
  /// Repeated requests scroll again; a request can precede mounting the view.
  bool revealLine(
    String fileId,
    DiffSide side,
    int line, {
    required int revision,
  }) {
    if (!_available(fileId, revision, side, line)) return false;
    final file = _file(fileId);
    var changed = _collapsed.remove(fileId);
    var inHunk = false;
    for (var h = 0; h < file.hunks.length; h++) {
      final hunk = file.hunks[h];
      final start = side == DiffSide.old ? hunk.oldStart : hunk.newStart;
      final count = side == DiffSide.old ? hunk.oldCount : hunk.newCount;
      if (line >= start && line < start + count) {
        changed = _collapsedHunks.remove((fileId, h)) || changed;
        inHunk = true;
        break;
      }
    }
    if (!inHunk) {
      // Full context is available only for hydrated/text diffs. Find the gap
      // using the same source-coordinate bounds as DiffLayout.
      for (var h = 0; h <= file.hunks.length; h++) {
        final previous = h == 0 ? null : file.hunks[h - 1];
        final next = h == file.hunks.length ? null : file.hunks[h];
        int end(DiffHunk hunk, bool old) {
          final start = old ? hunk.oldStart : hunk.newStart;
          final count = old ? hunk.oldCount : hunk.newCount;
          return start + (count == 0 ? 0 : count - 1);
        }

        final first = previous == null ? 1 : end(previous, false) + 1;
        final last = next == null
            ? file.newLines!.length
            : next.newStart - (next.newCount == 0 ? 0 : 1);
        final shift = side == DiffSide.old && previous != null
            ? end(previous, true) - end(previous, false)
            : 0;
        if (line >= first + shift && line <= last + shift) {
          changed = _expanded.add((fileId, h)) || changed;
          break;
        }
      }
    }
    _reveal = (fileId: fileId, side: side, line: line, revision: revision);
    _revealRequest++;
    if (changed) _layout = null;
    notifyListeners();
    return true;
  }

  /// Latest visible row requested for the indexed viewport.
  @internal
  int? get revealRow {
    final target = _reveal;
    if (target == null) return null;
    final index = _indices[target.fileId];
    return index == null
        ? null
        : layout.rowForLine(
            index,
            target.line,
            oldSide: target.side == DiffSide.old,
          );
  }

  /// Serial that distinguishes repeated reveals of the same source line.
  @internal
  int get revealRequest => _revealRequest;

  /// Expands an indexed context gap activated in a controlled view.
  @internal
  void expandGap(DiffGapId gap) {
    final file = _files[gap.file];
    if (_expanded.add((file.id, gap.hunk))) _layoutChanged();
  }

  FileDiff _file(String id) {
    final index = _indices[id];
    if (index == null) throw ArgumentError.value(id, 'fileId', 'Unknown file');
    return _files[index];
  }

  bool _available(String id, int revision, DiffSide side, int line) {
    final index = _indices[id];
    if (index == null || _files[index].revision != revision || line < 1) {
      return false;
    }
    final available = _availableLayouts.putIfAbsent(
      id,
      () => DiffLayout([_files[index]], expandAll: true),
    );
    return available.rowForLine(0, line, oldSide: side == DiffSide.old) != null;
  }

  void _layoutChanged() {
    _layout = null;
    notifyListeners();
  }
}
