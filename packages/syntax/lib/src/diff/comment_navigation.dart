import 'dart:async';
import '../edit/editor.dart';
import '../edit/file_controller.dart';
import '../edit/text_document.dart';
import 'comment_thread.dart';
import 'diff_layout.dart';
import 'file_diff.dart';
import 'patch_controller.dart';
import 'review.dart';

/// Which review discussions are visible and participate in navigation.
enum CommentThreadFilter {
  /// Every nonempty discussion.
  all,

  /// Discussions still requiring attention.
  unresolved,

  /// Completed discussions only.
  resolved,
}

/// A discussion's current source anchor, independent of its mounted widgets.
final class CommentThreadLocation {
  /// Creates a zero-based source-line anchor. Diff sides are optional for files.
  const CommentThreadLocation({
    required this.fileId,
    required this.annotationId,
    required this.thread,
    required this.line,
    this.side,
    this.sourceRevision = 0,
  });

  /// Stable source and annotation identities; annotation IDs may repeat in files.
  final String fileId, annotationId;

  /// Current discussion snapshot.
  final ReviewThread thread;

  /// Zero-based source line to reveal.
  final int line;

  /// Diff source side, or null for a single document.
  final DiffSide? side;

  /// Source revision used to discard obsolete navigation results.
  final int sourceRevision;

  /// Stable navigation identity, including its containing file.
  (String, String) get key => (fileId, annotationId);
}

/// Shared counts, filtering and navigation for application-owned discussions.
///
/// Binding factories track ReviewThread annotation payloads. Keep this controller
/// outside virtual rows and dispose it before its source controller. Filtering
/// changes presentation only; counts always include hidden discussions.
final class CommentNavigationController extends SyntaxObservable {
  /// Uses application-supplied anchors in navigation order and a reveal callback.
  CommentNavigationController({
    required this.onReveal,
    this.onCancelReveal,
    Iterable<CommentThreadLocation> threads = const [],
    CommentThreadFilter filter = CommentThreadFilter.all,
  }) : _filter = filter {
    setThreads(threads);
  }

  /// Tracks diff annotations and reveals folded files, sections and context.
  factory CommentNavigationController.patch(PatchController source) {
    final result = CommentNavigationController(
      onCancelReveal: source.cancelReveal,
      onReveal: (location) async =>
          await source.revealLine(
            location.fileId,
            location.line + 1,
            side: location.side ?? DiffSide.newer,
          ) !=
          null,
    );
    List<FileDiff>? previousFiles;
    List<ReviewAnnotation<Object?>>? previousAnnotations;
    late DiffLayout order;
    void sync() {
      if (identical(previousFiles, source.files) &&
          identical(previousAnnotations, source.annotations)) {
        return;
      }
      // Loading complete contents preserves source anchors while advancing the
      // patch revision. Do not cancel the reveal that requested that load.
      final current = result.current;
      final old = previousFiles?.where((f) => f.id == current?.fileId);
      final updated = source.files.where((f) => f.id == current?.fileId);
      final hydrated =
          old != null &&
          old.isNotEmpty &&
          updated.isNotEmpty &&
          old.first.isPartial &&
          !updated.first.isPartial &&
          identical(old.first.hunks, updated.first.hunks) &&
          updated.first.revision == old.first.revision + 1 &&
          (old.first.oldText == null ||
              old.first.oldText == updated.first.oldText) &&
          (old.first.newText == null ||
              old.first.newText == updated.first.newText);
      previousAnnotations = source.annotations;
      if (!identical(previousFiles, source.files)) {
        previousFiles = source.files;
        order = DiffLayout(source.files, expandAll: true);
      }
      final files = {
        for (var i = 0; i < source.files.length; i++) source.files[i].id: i,
      };
      final entries = <(CommentThreadLocation, int, int)>[];
      for (final a in source.annotations) {
        final index = files[a.fileId];
        if (index == null || a.line < 1 || a.data is! ReviewThread) continue;
        entries.add((
          CommentThreadLocation(
            fileId: a.fileId,
            annotationId: a.id,
            thread: a.data! as ReviewThread,
            line: a.line - 1,
            side: a.side,
            sourceRevision: source.files[index].revision,
          ),
          index,
          order.rowForLine(index, a.line, oldSide: a.side == DiffSide.old) ??
              a.line,
        ));
      }
      entries.sort((a, b) {
        final file = a.$2.compareTo(b.$2);
        if (file != 0) return file;
        final row = a.$3.compareTo(b.$3);
        return row != 0 ? row : a.$1.annotationId.compareTo(b.$1.annotationId);
      });
      result._setThreads(entries.map((entry) => entry.$1), hydrated: hydrated);
    }

    result._bind(source, sync);
    return result;
  }

  /// Tracks a file's annotations. Match annotationLine to the view's optional
  /// annotationLineBuilder when displaying annotations at a range endpoint.
  factory CommentNavigationController.file(
    EditorController source, {
    int Function(LineAnnotation<Object?>)? annotationLine,
  }) {
    final result = CommentNavigationController(
      onReveal: (location) {
        source.reveal(_range(location.line));
        return true;
      },
    );
    result._bind(
      source,
      () => result.setThreads(_fileThreads(source, annotationLine)),
    );
    return result;
  }

  /// Tracks retained file-list sessions without acquiring or mounting them.
  /// Applications own annotation persistence beyond the session cache lifetime.
  factory CommentNavigationController.files(
    FileListController source, {
    int Function(LineAnnotation<Object?>)? annotationLine,
  }) {
    final result = CommentNavigationController(
      onReveal: (location) {
        source.reveal(location.fileId, _range(location.line));
        return true;
      },
    );
    result._bind(
      source,
      () => result.setThreads([
        for (final file in source.files)
          if (source.sessions.peek(file.id) case final session?)
            ..._fileThreads(session, annotationLine),
      ]),
    );
    return result;
  }

  static DocumentRange _range(int line) =>
      DocumentRange(DocumentPosition(line, 0), DocumentPosition(line, 0));

  static List<CommentThreadLocation> _fileThreads(
    EditorController source,
    int Function(LineAnnotation<Object?>)? annotationLine,
  ) {
    final entries = <CommentThreadLocation>[];
    for (final a in source.annotations) {
      if (a.data is! ReviewThread) continue;
      final line =
          annotationLine?.call(a) ?? source.document.positionAt(a.start).line;
      if (line < 0 || line >= source.document.lineCount) continue;
      entries.add(
        CommentThreadLocation(
          fileId: source.file.id,
          annotationId: a.id,
          thread: a.data! as ReviewThread,
          line: line,
          sourceRevision: source.document.revision,
        ),
      );
    }
    entries.sort((a, b) {
      final line = a.line.compareTo(b.line);
      return line != 0 ? line : a.annotationId.compareTo(b.annotationId);
    });
    return entries;
  }

  /// Application command that reveals an anchor; false indicates unavailable content.
  final FutureOr<bool> Function(CommentThreadLocation) onReveal;

  /// Cancels a pending reveal's scrolling when superseded, filtered or disposed.
  /// Loading may continue to populate the application's cache.
  final void Function()? onCancelReveal;
  List<CommentThreadLocation> _threads = const [];
  Map<(String, String), CommentThreadLocation> _byKey = const {};
  final Map<String?, (int, int)> _counts = {};
  CommentThreadFilter _filter;
  (String, String)? _current;
  (String, String)? _revealTarget;
  void Function()? _unbind;
  int _generation = 0;
  int _revealRequest = 0;
  bool _navigating = false;
  Object? _error;

  /// Source-ordered, immutable nonempty discussions.
  List<CommentThreadLocation> get threads => _threads;

  /// Current filter. Changing it does not mutate discussions or drafts.
  CommentThreadFilter get filter => _filter;
  set filter(CommentThreadFilter value) {
    checkAlive();
    if (_filter == value) return;
    _filter = value;
    _cancel();
    _error = null;
    if (!visible().any((entry) => entry.key == _current)) _current = null;
    notifyListeners();
  }

  /// Most recently requested visible discussion, or null after removal/filtering.
  CommentThreadLocation? get current => _byKey[_current];

  /// Explicit navigation target, distinct from pointer/focus selection.
  CommentThreadLocation? get revealTarget => _byKey[_revealTarget];

  /// Selects a visible discussion by stable identity without scrolling.
  /// Pointer and focus interactions can use this before invoking thread actions.
  bool select(String fileId, String annotationId) {
    checkAlive();
    final key = (fileId, annotationId), entry = _byKey[(fileId, annotationId)];
    if (entry == null || !isVisible(entry.thread)) return false;
    if (_current == key) return true;
    _cancel();
    _current = key;
    _revealTarget = null;
    _error = null;
    notifyListeners();
    return true;
  }

  /// Whether the latest source reveal is pending.
  bool get isNavigating => _navigating;

  /// Latest reveal failure; applications can provide custom error presentation.
  Object? get error => _error;

  /// Sequence of explicit navigation requests, including repeat targets.
  int get revealRequest => _revealRequest;

  /// Whether a payload survives the filter. Non-thread annotations are unaffected.
  bool isVisible(Object? data) =>
      data is! ReviewThread ||
      (data.comments.isNotEmpty &&
          switch (filter) {
            CommentThreadFilter.all => true,
            CommentThreadFilter.unresolved => !data.resolved,
            CommentThreadFilter.resolved => data.resolved,
          });

  /// Filtered navigation entries, optionally restricted to one file.
  List<CommentThreadLocation> visible({String? fileId}) => [
    for (final entry in _threads)
      if ((fileId == null || entry.fileId == fileId) && isVisible(entry.thread))
        entry,
  ];

  /// Number of discussions, independent of the current visibility filter.
  int count({String? fileId, bool? resolved}) =>
      switch ((_counts[fileId] ?? (0, 0), resolved)) {
        (final counts, null) => counts.$1 + counts.$2,
        (final counts, false) => counts.$1,
        (final counts, true) => counts.$2,
      };

  /// Replaces source-ordered anchors while preserving the current stable identity.
  void setThreads(Iterable<CommentThreadLocation> values) =>
      _setThreads(values);

  void _setThreads(
    Iterable<CommentThreadLocation> values, {
    bool hydrated = false,
  }) {
    checkAlive();
    final next = values
        .where((entry) => entry.thread.comments.isNotEmpty)
        .toList();
    if (next.map((entry) => entry.key).toSet().length != next.length) {
      throw ArgumentError(
        'Duplicate comment annotation identity within a file',
      );
    }
    for (final entry in next) {
      RangeError.checkNotNegative(entry.line, 'line');
      RangeError.checkNotNegative(entry.sourceRevision, 'sourceRevision');
    }
    final before = current;
    _threads = List.unmodifiable(next);
    _byKey = {for (final entry in next) entry.key: entry};
    _counts.clear();
    for (final entry in next) {
      for (final key in [null, entry.fileId]) {
        final counts = _counts[key] ?? (0, 0);
        _counts[key] = entry.thread.resolved
            ? (counts.$1, counts.$2 + 1)
            : (counts.$1 + 1, counts.$2);
      }
    }
    final after = current;
    if (before != null &&
        (after == null ||
            !isVisible(after.thread) ||
            before.line != after.line ||
            before.side != after.side ||
            (!hydrated && before.sourceRevision != after.sourceRevision))) {
      _current = null;
      _cancel();
      _error = null;
    }
    notifyListeners();
  }

  /// Reveals a visible anchor using its latest location, rejecting stale results.
  Future<bool> reveal(CommentThreadLocation requested) async {
    checkAlive();
    final matches = visible().where((entry) => entry.key == requested.key);
    if (matches.isEmpty) return false;
    final entry = matches.first;
    _cancel();
    final generation = ++_generation;
    _revealRequest++;
    _current = entry.key;
    _revealTarget = entry.key;
    _navigating = true;
    _error = null;
    notifyListeners();
    try {
      if (isDisposed || generation != _generation) return false;
      final revealed = await onReveal(entry);
      if (isDisposed || generation != _generation) return false;
      if (!revealed) throw StateError('Discussion source is unavailable');
      return true;
    } catch (error) {
      if (!isDisposed && generation == _generation) _error = error;
      return false;
    } finally {
      if (!isDisposed && generation == _generation) {
        _navigating = false;
        notifyListeners();
      }
    }
  }

  /// Moves forward in source order, wrapping at the end.
  Future<bool> next({String? fileId}) => _step(1, fileId);

  /// Moves backward in source order, wrapping at the beginning.
  Future<bool> previous({String? fileId}) => _step(-1, fileId);
  Future<bool> _step(int direction, String? fileId) {
    checkAlive();
    final entries = visible(fileId: fileId);
    if (entries.isEmpty) return Future.value(false);
    final index = entries.indexWhere((entry) => entry.key == _current);
    final next = index < 0
        ? (direction > 0 ? 0 : entries.length - 1)
        : (index + direction) % entries.length;
    return reveal(entries[next]);
  }

  void _bind(SyntaxObservable source, void Function() sync) {
    sync();
    source.addListener(sync);
    _unbind = () => source.removeListener(sync);
  }

  void _cancel() {
    _generation++;
    _revealTarget = null;
    if (_navigating) onCancelReveal?.call();
    _navigating = false;
  }

  @override
  void dispose() {
    _cancel();
    _unbind?.call();
    super.dispose();
  }
}
