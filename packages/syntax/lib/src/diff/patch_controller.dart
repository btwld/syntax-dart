import 'dart:async';

import '../edit/editor.dart';
import '../edit/text_document.dart';
import 'diff_layout.dart';
import 'diff_texts.dart';
import 'file_diff.dart';
import 'review.dart';

/// Which ends of an unchanged gap to reveal.
enum ExpansionDirection {
  /// Reveal lines next to the preceding hunk.
  before,

  /// Reveal lines next to the following hunk.
  after,

  /// Reveal lines from both ends.
  both,
}

/// A directed, one-based line range in one file, optionally crossing sides.
final class DiffSelection {
  /// Selects an inclusive source-line interval while retaining its direction.
  const DiffSelection(
    this.fileId,
    this.side,
    this.anchor,
    this.active, {
    DiffSide? activeSide,
  }) : activeSide = activeSide ?? side;

  /// Stable application-supplied identity of the associated file.
  final String fileId;

  /// Source side addressed by this value.
  final DiffSide side;

  /// Source side at the moving endpoint. Defaults to [side].
  final DiffSide activeSide;

  /// Whether the selection crosses from one source to the other.
  bool get crossesSides => side != activeSide;

  /// Fixed and moving endpoints of the directed selection.
  final int anchor, active;

  /// First selected one-based line, inclusive.
  int get start => anchor < active ? anchor : active;

  /// Last selected one-based line, inclusive.
  int get end => anchor > active ? anchor : active;
}

/// Attaches application data to a one-based line on one diff side.
final class ReviewAnnotation<T> {
  /// Attaches application data to a one-based line on one diff side.
  const ReviewAnnotation({
    required this.id,
    required this.fileId,
    required this.side,
    required this.line,
    required this.data,
  });

  /// Stable annotation identity and the identity of its source file.
  final String id, fileId;

  /// Source side addressed by this value.
  final DiffSide side;

  /// One-based source line to which the annotation is attached.
  final int line;

  /// Application-owned annotation payload, passed unchanged to renderers.
  final T data;
}

/// Stable review state shared by Flutter, terminal and static renderers.
final class PatchController extends SyntaxObservable {
  /// Creates review state for uniquely identified files and optional full-content loading.
  PatchController(
    Iterable<FileDiff> files, {
    DiffMode mode = DiffMode.unified,
    this.contextThreshold = 0,
    this.expansionLineCount = 100,
    this.contentsLoader,
    this.sessionLimit = 32,
    this.foldableHunks = false,
  }) : _mode = mode {
    RangeError.checkNotNegative(sessionLimit, 'sessionLimit');
    setFiles(files);
  }
  List<FileDiff> _files = const [];

  /// Files in display order; identity remains independent of this ordering.
  List<FileDiff> get files => _files;
  DiffMode _mode;

  /// Unified or side-by-side presentation of changed source lines.
  DiffMode get mode => _mode;

  /// Unified or side-by-side presentation of changed source lines.
  set mode(DiffMode value) => setMode(value);

  /// Maximum retained inactive edit sessions; active sessions are protected.
  final int sessionLimit;
  final Map<String, int> _activeEditors = {};
  final Map<String, FileDiff> _editingSources = {};

  /// Maximum size of an unchanged gap shown without an expansion action.
  final int contextThreshold;

  /// Default number of unchanged lines revealed by one expansion action.
  final int expansionLineCount;

  /// Keeps section headers visible and enables named section folding controls.
  final bool foldableHunks;

  /// Application callback providing both complete sources for a partial patch.
  final DiffContentsLoader? contentsLoader;
  final Set<String> _collapsed = {};
  final Set<(String, int)> _collapsedHunks = {};
  final Map<(String, int), GapExpansion> _expanded = {};
  final Map<String, CancellationToken> _loading = {};
  final Map<String, Future<bool>> _loadResults = {};
  int _navigationGeneration = 0;
  final Map<String, EditorController> _editors = {};
  final Map<String, int> _editingRevisions = {};

  /// Most recent loading error for each file identity.
  final Map<String, Object> loadErrors = {};

  /// Application annotations positioned against the current document.
  List<ReviewAnnotation<Object?>> annotations = const [];

  /// Directed selection retained independently of mounted views.
  DiffSelection? selection;

  /// Logical row requested by the latest reveal command, or null.
  int? get scrollTargetRow {
    final target = _scrollTarget;
    if (target == null) return null;
    final index = files.indexWhere((file) => file.id == target.$1);
    return index < 0
        ? null
        : layout.rowForLine(
            index,
            target.$2,
            oldSide: target.$3 == DiffSide.old,
          );
  }

  (String, int, DiffSide)? _scrollTarget;

  /// Sequence number of the latest explicit scroll command.
  int scrollRequest = 0;
  DiffLayout? _layout;

  /// Indexes logical diff rows without allocating a list of every row.
  DiffLayout get layout => _layout ??= DiffLayout(
    _files,
    mode: mode,
    contextThreshold: contextThreshold,
    showHunkHeaders: foldableHunks,
    collapsedHunks: {
      for (var i = 0; i < files.length; i++)
        for (var h = 0; h < files[i].hunks.length; h++)
          if (_collapsedHunks.contains((files[i].id, h))) (file: i, hunk: h),
    },
    collapsed: {
      for (var i = 0; i < files.length; i++)
        if (_collapsed.contains(files[i].id)) i,
    },
    expansions: {
      for (var i = 0; i < files.length; i++)
        for (var h = 0; h <= files[i].hunks.length; h++)
          (file: i, hunk: h): ?_expanded[(files[i].id, h)],
    },
  );

  void _changed() {
    _layout = null;
    _selectionLayout = null;
    notifyListeners();
  }

  /// Whether the file body is currently hidden.
  bool isCollapsed(String id) => _collapsed.contains(id);

  /// Whether complete contents are being requested for this file.
  bool isLoading(String id) => _loading.containsKey(id);

  /// Current source snapshot, including stable identity and document revision.
  FileDiff file(String id) => files.firstWhere((f) => f.id == id);

  /// Replaces files and invalidates revision-dependent work for changed identities.
  void setFiles(Iterable<FileDiff> value) {
    checkAlive();
    final next = value.toList();
    final ids = next.map((f) => f.id).toSet();
    if (ids.length != next.length) {
      throw ArgumentError('Each file must have a distinct identity');
    }
    final byId = {for (final source in next) source.id: source};
    final movedLines = <String>{};
    for (final old in files) {
      if (!identical(byId[old.id], old)) {
        final source = byId[old.id];
        if (source == null ||
            !identical(source.hunks, old.hunks) ||
            (old.oldText != null && source.oldText != old.oldText) ||
            (old.newText != null && source.newText != old.newText)) {
          movedLines.add(old.id);
        }
        _loading.remove(old.id)?.cancel();
        _loadResults.remove(old.id);
        _expanded.removeWhere((key, _) => key.$1 == old.id);
        _collapsedHunks.removeWhere((key) => key.$1 == old.id);
        loadErrors.remove(old.id);
      }
    }
    _collapsed.retainAll(ids);
    for (final key in _editors.keys.toList()) {
      if (!ids.contains(key) && !_activeEditors.containsKey(key)) {
        _editors.remove(key)?.dispose();
        _editingRevisions.remove(key);
        _editingSources.remove(key);
        _activeEditors.remove(key);
      }
    }
    if (selection != null && movedLines.contains(selection!.fileId)) {
      selection = null;
    }
    annotations = List.unmodifiable(
      annotations.where((a) => !movedLines.contains(a.fileId)),
    );
    if (_scrollTarget != null && movedLines.contains(_scrollTarget!.$1)) {
      _scrollTarget = null;
    }
    _files = List.unmodifiable(next);
    _changed();
  }

  /// Replaces the file with the same identity, retaining collection order.
  void updateFile(FileDiff value) {
    final index = files.indexWhere((f) => f.id == value.id);
    if (index < 0) throw ArgumentError('Unknown file identity');
    final next = files.toList()..[index] = value;
    setFiles(next);
  }

  /// Updates the display mode and invalidates the indexed layout.
  void setMode(DiffMode value) {
    if (_mode == value) return;
    _mode = value;
    _changed();
  }

  /// Collapses or expands a file without discarding its retained edit session.
  void toggleFile(String id) {
    file(id);
    if (!_collapsed.remove(id)) _collapsed.add(id);
    _changed();
  }

  /// Whether a zero-based hunk is folded. State belongs to this source revision.
  bool isHunkCollapsed(String id, int hunk) =>
      _collapsedHunks.contains((id, hunk));

  /// Folds a section without losing selections, annotations, or edit sessions.
  void toggleHunk(String id, int hunk) {
    checkAlive();
    RangeError.checkValidIndex(hunk, file(id).hunks, 'hunk');
    if (!_collapsedHunks.remove((id, hunk))) _collapsedHunks.add((id, hunk));
    _changed();
  }

  /// Folds or expands every named section, optionally in a single file.
  void setHunksCollapsed(bool collapsed, [String? id]) {
    checkAlive();
    for (final source in files) {
      if (id != null && source.id != id) continue;
      for (var h = 0; h < source.hunks.length; h++) {
        if (collapsed) {
          _collapsedHunks.add((source.id, h));
        } else {
          _collapsedHunks.remove((source.id, h));
        }
      }
    }
    _changed();
  }

  /// Restores the original context gaps without replacing files or review state.
  void collapseContext([String? id]) {
    checkAlive();
    _expanded.removeWhere((key, _) => id == null || key.$1 == id);
    _changed();
  }

  /// Reveals a bounded number of lines at either end of an unchanged gap.
  void expand(
    DiffGapId gap, {
    ExpansionDirection direction = ExpansionDirection.both,
    int? count,
  }) {
    final amount = count ?? expansionLineCount;
    RangeError.checkNotNegative(amount, 'count');
    final key = (files[gap.file].id, gap.hunk);
    final previous = _expanded[key] ?? (before: 0, after: 0);
    _expanded[key] = (
      before:
          previous.before +
          (direction == ExpansionDirection.after ? 0 : amount),
      after:
          previous.after +
          (direction == ExpansionDirection.before ? 0 : amount),
    );
    _changed();
  }

  /// Reveals all available context for one file, or the entire collection.
  void expandAll([String? id]) {
    for (var i = 0; i < files.length; i++) {
      if (id != null && files[i].id != id) continue;
      for (var h = 0; h <= files[i].hunks.length; h++) {
        _expanded[(files[i].id, h)] = (
          before: files[i].newLines?.length ?? 0,
          after: 0,
        );
      }
    }
    _changed();
  }

  /// Loads and validates complete sources; stale or failed loads return false.
  Future<bool> loadContents(String id) {
    checkAlive();
    if (!file(id).isPartial) return Future.value(true);
    final pending = _loadResults[id];
    if (pending != null) return pending;
    final completion = Completer<bool>();
    _loadResults[id] = completion.future;
    Future<void> run() async {
      try {
        completion.complete(await _loadContents(id));
      } on Object catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        if (identical(_loadResults[id], completion.future)) {
          _loadResults.remove(id);
        }
      }
    }

    unawaited(run());
    return completion.future;
  }

  Future<bool> _loadContents(String id) async {
    final loader = contentsLoader;
    if (loader == null || _loading.containsKey(id)) return false;
    final original = file(id);
    if (!original.isPartial) return true;
    final token = _loading[id] = CancellationToken();
    loadErrors.remove(id);
    notifyListeners();
    try {
      token.throwIfCancelled();
      final result = await token.bind(loader(original, token));
      if (isDisposed || token.isCancelled || !identical(file(id), original)) {
        return false;
      }
      final hydrated = hydrateDiff(
        original,
        oldText: result.oldText,
        newText: result.newText,
      );
      _loading.remove(id);
      updateFile(hydrated);
      return true;
    } on Object catch (error) {
      if (!isDisposed && !token.isCancelled) loadErrors[id] = error;
      return false;
    } finally {
      if (identical(_loading[id], token)) _loading.remove(id);
      if (!isDisposed) notifyListeners();
    }
  }

  /// Cancels pending asynchronous reveals without cancelling shared content loads.
  void cancelReveal() {
    checkAlive();
    _navigationGeneration++;
  }

  /// Unfolds and optionally loads a one-based source line, returning its row.
  Future<int?> revealLine(
    String id,
    int line, {
    DiffSide side = DiffSide.newer,
  }) async {
    RangeError.checkNotNegative(line - 1, 'line');
    var index = files.indexWhere((f) => f.id == id);
    final generation = ++_navigationGeneration;
    if (index < 0) throw ArgumentError('Unknown file');
    _collapsed.remove(id);
    // Reveal only the folded section containing the target source line.
    final source = files[index];
    for (var h = 0; h < source.hunks.length; h++) {
      final section = source.hunks[h];
      final start = side == DiffSide.old ? section.oldStart : section.newStart;
      final count = side == DiffSide.old ? section.oldCount : section.newCount;
      if (line >= start && line < start + count) {
        _collapsedHunks.remove((id, h));
      }
    }
    _layout = null;
    var row = layout.rowForLine(index, line, oldSide: side == DiffSide.old);
    if (row == null && file(id).isPartial) {
      if (!await loadContents(id)) {
        if (!isDisposed) notifyListeners();
        return null;
      }
    }
    if (isDisposed || generation != _navigationGeneration) return null;
    index = files.indexWhere((f) => f.id == id);
    if (index < 0) return null;
    if (row == null) {
      expandAll(id);
      row = layout.rowForLine(index, line, oldSide: side == DiffSide.old);
    }
    _scrollTarget = row == null ? null : (id, line, side);
    scrollRequest++;
    notifyListeners();
    return row;
  }

  /// Changes or clears the directed review selection and notifies subscribers.
  void select(DiffSelection? value) {
    checkAlive();
    if (value != null) {
      file(value.fileId);
      RangeError.checkNotNegative(value.start - 1, 'line');
    }
    selection = value;
    notifyListeners();
  }

  DiffLayout? _selectionLayout;
  DiffLayout get _allSelectionRows =>
      _selectionLayout ??= DiffLayout(files, expandAll: true);

  (int, int)? _selectionRows(DiffSelection selected) {
    final index = files.indexWhere((f) => f.id == selected.fileId);
    final a = _allSelectionRows.rowForLine(
      index,
      selected.anchor,
      oldSide: selected.side == DiffSide.old,
    );
    final b = _allSelectionRows.rowForLine(
      index,
      selected.active,
      oldSide: selected.activeSide == DiffSide.old,
    );
    if (a == null || b == null) return null;
    return a < b ? (a, b) : (b, a);
  }

  /// Tests a source line against the selection in either display mode.
  bool isLineSelected(String id, DiffSide side, int number) {
    final selected = selection;
    if (selected == null || selected.fileId != id) return false;
    if (!selected.crossesSides) {
      return selected.side == side &&
          number >= selected.start &&
          number <= selected.end;
    }
    final bounds = _selectionRows(selected);
    if (bounds == null) return false;
    final index = files.indexWhere((f) => f.id == id);
    final row = _allSelectionRows.rowForLine(
      index,
      number,
      oldSide: side == DiffSide.old,
    );
    return row != null && row >= bounds.$1 && row <= bounds.$2;
  }

  /// Replaces annotations and notifies mounted renderers.
  void setAnnotations(Iterable<ReviewAnnotation<Object?>> value) {
    annotations = List.unmodifiable(value);
    notifyListeners();
  }

  /// Copies selected source lines without gutters, annotations or change markers.
  String selectedText() {
    final selected = selection;
    if (selected == null) return '';
    if (selected.crossesSides) {
      final bounds = _selectionRows(selected);
      if (bounds == null) return '';
      final lines = <DiffLine>[];
      for (var i = bounds.$1; i <= bounds.$2; i++) {
        if (_allSelectionRows[i] case DiffLineRow(:final line)) lines.add(line);
      }
      final source = file(selected.fileId);
      final old = source.oldText == null ? null : TextDocument(source.oldText!);
      final newer = source.newText == null
          ? null
          : TextDocument(source.newText!);
      try {
        String ending(DiffLine line) {
          final document = line.kind == DiffLineKind.removed ? old : newer;
          final number = line.kind == DiffLineKind.removed
              ? line.oldNumber
              : line.newNumber;
          if (document != null && number != null) {
            final text = document.lineText(number - 1, includeTerminator: true);
            final eol = text.substring(document.lineText(number - 1).length);
            return eol.isEmpty ? '\n' : eol;
          }
          return line.sourceLineEnding.isEmpty ? '\n' : line.sourceLineEnding;
        }

        return [
          for (var i = 0; i < lines.length; i++)
            '${lines[i].text}${i + 1 == lines.length ? '' : ending(lines[i])}',
        ].join();
      } finally {
        old?.dispose();
        newer?.dispose();
      }
    }
    final source = file(selected.fileId);
    final lines = selected.side == DiffSide.old
        ? source.oldLines
        : source.newLines;
    if (lines != null) {
      final text = selected.side == DiffSide.old
          ? source.oldText
          : source.newText;
      if (text != null && lines.isNotEmpty && selected.start <= lines.length) {
        final document = TextDocument(text);
        try {
          final first = (selected.start - 1).clamp(0, lines.length - 1);
          final last = (selected.end - 1).clamp(first, lines.length - 1);
          return text.substring(
            document.lineStart(first),
            document.lineStart(last) + document.lineText(last).length,
          );
        } finally {
          document.dispose();
        }
      }
      return lines
          .sublist(
            (selected.start - 1).clamp(0, lines.length),
            selected.end.clamp(0, lines.length),
          )
          .join('\n');
    }
    final available = <int, DiffLine>{};
    for (final hunk in source.hunks) {
      for (final line in hunk.lines) {
        final number = selected.side == DiffSide.old
            ? line.oldNumber
            : line.newNumber;
        if (number != null &&
            number >= selected.start &&
            number <= selected.end) {
          available[number] = line;
        }
      }
    }
    final keys = available.keys.toList()..sort();
    return [
      for (var i = 0; i < keys.length; i++)
        '${available[keys[i]]!.text}${i + 1 == keys.length ? '' : available[keys[i]]!.sourceLineEnding}',
    ].join();
  }

  /// Finds the hunk and contiguous change block containing a source line.
  /// Context lines return null. Both indexes are zero-based.
  ({int hunk, int change})? changeAt(
    String id,
    int line, {
    DiffSide side = DiffSide.newer,
  }) {
    final source = file(id);
    for (var h = 0; h < source.hunks.length; h++) {
      var block = -1, changing = false;
      for (final item in source.hunks[h].lines) {
        if (item.kind == DiffLineKind.context) {
          changing = false;
          continue;
        }
        if (!changing) {
          block++;
          changing = true;
        }
        if ((side == DiffSide.old ? item.oldNumber : item.newNumber) == line) {
          return (hunk: h, change: block);
        }
      }
    }
    return null;
  }

  /// Applies a side choice and recomputes the remaining changes.
  void resolve(
    String id,
    int hunk,
    ChangeResolution resolution, {
    int? changeIndex,
  }) => updateFile(
    resolveDiffChange(file(id), hunk, resolution, changeIndex: changeIndex),
  );

  /// Returns a retained editing session, if one exists for this identity.
  EditorController? editorFor(String id) => _editors[id];

  /// Claims a new-side editing session while retaining the original diff regions.
  EditorController beginEdit(
    String id, {
    ProposedEditProvider? proposalProvider,
  }) {
    checkAlive();
    final source = file(id);
    if (source.newText == null || source.oldText == null) {
      throw StateError('Load full contents before editing');
    }
    final retained = _editors.remove(id);
    if (retained != null) {
      _activeEditors[id] = (_activeEditors[id] ?? 0) + 1;
      return _editors[id] = retained;
    }
    return _editors.putIfAbsent(id, () {
      _activeEditors[id] = 1;
      _editingRevisions[id] = source.revision;
      _editingSources[id] = source;
      return EditorController(
        file: SourceFile(
          id: id,
          path: source.path,
          text: source.newText!,
          language: source.language,
          revision: source.revision,
        ),
        proposalProvider: proposalProvider,
      );
    });
  }

  /// Releases a view while preserving its draft, history and selection.
  void releaseEdit(String id) {
    final claims = _activeEditors[id] ?? 0;
    if (claims > 1) {
      _activeEditors[id] = claims - 1;
    } else {
      _activeEditors.remove(id);
    }
    if (!_activeEditors.containsKey(id) &&
        !files.any((file) => file.id == id)) {
      _editors.remove(id)?.dispose();
      _editingRevisions.remove(id);
      _editingSources.remove(id);
    }
    final inactive = _editors.keys
        .where((key) => !_activeEditors.containsKey(key))
        .toList();
    for (final key in inactive.take(
      (inactive.length - sessionLimit).clamp(0, inactive.length),
    )) {
      _editors.remove(key)?.dispose();
      _editingRevisions.remove(key);
      _editingSources.remove(key);
    }
  }

  /// Computes a candidate once. Rejecting leaves the original file untouched.
  Future<bool> completeEdit(
    String id, {
    Future<bool> Function(FileDiff)? accept,
  }) async {
    final editor = _editors[id];
    if (editor == null) return false;
    final original = file(id);
    if (original.revision != _editingRevisions[id] ||
        !identical(original, _editingSources[id])) {
      throw StateError('File changed during editing');
    }
    final revision = editor.document.revision;
    final computed = diffTexts(
      original.oldText!,
      editor.document.text,
      path: original.path,
    );
    final candidate = original.copyWith(
      hunks: computed.hunks,
      newLines: computed.newLines,
      newText: computed.newText,
      revision: original.revision + 1,
    );
    final accepted = accept == null || await accept(candidate);
    if (isDisposed ||
        !identical(_editors[id], editor) ||
        editor.document.revision != revision ||
        !files.any((file) => identical(file, original))) {
      return false;
    }
    if (accepted) {
      _editingRevisions[id] = candidate.revision;
      _editingSources[id] = candidate;
      updateFile(candidate);
    } else {
      notifyListeners();
    }
    return accepted;
  }

  /// Discards the draft while keeping any mounted views bound to a live session.
  void discardEdit(String id) {
    final source = file(id);
    if (_activeEditors.containsKey(id)) {
      _editingRevisions[id] = source.revision;
      _editingSources[id] = source;
      _editors[id]?.replaceSource(
        SourceFile(
          id: id,
          path: source.path,
          text: source.newText!,
          language: source.language,
          revision: source.revision,
        ),
      );
    } else {
      _editors.remove(id)?.dispose();
      _editingRevisions.remove(id);
      _editingSources.remove(id);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final token in _loading.values) {
      token.cancel();
    }
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _loading.clear();
    _loadResults.clear();
    _editors.clear();
    _editingSources.clear();
    _activeEditors.clear();
    super.dispose();
  }
}
