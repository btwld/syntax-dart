import 'editor.dart';
import 'text_document.dart';

/// A flat collection of files with retained editor sessions and view state.
///
/// Identity is supplied by the application. This controller performs no path
/// traversal, filesystem access, or tree management.
final class FileListController extends SyntaxObservable {
  /// Retains up to [sessionLimit] inactive sessions, plus sessions in use.
  FileListController(Iterable<SourceFile> files, {int sessionLimit = 32})
    : sessions = SessionStore<EditorController>(
        capacity: sessionLimit,
        onEvict: (session) => session.dispose(),
      ) {
    setFiles(files);
  }

  /// Drafts remain available after their views release them.
  final SessionStore<EditorController> sessions;
  List<SourceFile> _files = const [];
  final Set<String> _collapsed = {};
  final Map<String, SourceFile> _bases = {};

  /// Files in display order, independent of retained session order.
  List<SourceFile> get files => _files;

  /// A requested file and zero-based line range to bring into view.
  (String, DocumentRange)? revealTarget;

  /// Sequence number of explicit reveal requests, including repeat targets.
  int revealRequest = 0;

  /// Replaces the collection, preserving state for identities still present.
  void setFiles(Iterable<SourceFile> values) {
    checkAlive();
    final next = List<SourceFile>.unmodifiable(values);
    final ids = next.map((file) => file.id).toSet();
    if (ids.length != next.length) throw ArgumentError('Duplicate file ID');
    for (final file in _files) {
      if (!ids.contains(file.id) && sessions.remove(file.id)) {
        _bases.remove(file.id);
      }
    }
    _files = next;
    for (final source in next) {
      final session = sessions.peek(source.id), base = _bases[source.id];
      if (session != null &&
          base != null &&
          !_sameSource(base, source) &&
          session.document.text == base.text) {
        _bases[source.id] = source;
        session.replaceSource(source);
      }
    }
    if (revealTarget != null && !ids.contains(revealTarget!.$1)) {
      revealTarget = null;
    }
    _collapsed.retainAll(ids);
    notifyListeners();
  }

  /// The latest application supplied file for an identity.
  SourceFile file(String id) => files.firstWhere((file) => file.id == id);

  /// Whether the file body is hidden.
  bool isCollapsed(String id) => _collapsed.contains(id);

  /// Collapses or expands a file without discarding its draft.
  void toggle(String id) {
    file(id);
    if (!_collapsed.remove(id)) _collapsed.add(id);
    notifyListeners();
  }

  /// Claims a session. Each mounted view must release its claim.
  EditorController acquire(String id) => sessions.acquire(id, () {
    final source = file(id);
    _bases[id] = source;
    return EditorController(file: source);
  });

  /// Whether a retained draft was based on a source the application replaced.
  bool hasSourceConflict(String id) {
    final base = _bases[id];
    return base != null &&
        sessions.peek(id) != null &&
        !_sameSource(base, file(id));
  }

  /// Discards a retained draft and reloads the latest application source.
  void reload(String id) {
    checkAlive();
    final source = file(id);
    _bases[id] = source;
    sessions.peek(id)?.replaceSource(source);
    notifyListeners();
  }

  /// Releases a view's session claim while keeping its draft in the cache.
  void release(String id) {
    sessions.release(id);
    if (!files.any((file) => file.id == id) && sessions.remove(id)) {
      _bases.remove(id);
    }
  }

  /// Requests that renderers reveal a source range and unfold its file.
  void reveal(String id, DocumentRange range) {
    file(id);
    _collapsed.remove(id);
    revealTarget = (id, range);
    revealRequest++;
    notifyListeners();
  }

  /// Offers the current draft to the application, installing it on acceptance.
  Future<bool> complete(
    String id,
    EditorController session,
    Future<bool> Function(SourceFile result) accept,
  ) async {
    checkAlive();
    if (!identical(sessions.peek(id), session) || hasSourceConflict(id)) {
      throw StateError(
        'File changed during editing; reload the source before completing',
      );
    }
    final original = file(id);
    final result = session.file;
    if (!await accept(result) ||
        isDisposed ||
        session.isDisposed ||
        !files.any((file) => identical(file, original)) ||
        session.document.revision != result.revision) {
      return false;
    }
    _bases[id] = result;
    setFiles([for (final source in files) source.id == id ? result : source]);
    return true;
  }

  @override
  void dispose() {
    sessions.clear(includeActive: true);
    _bases.clear();
    super.dispose();
  }
}

bool _sameSource(SourceFile a, SourceFile b) =>
    a.id == b.id &&
    a.revision == b.revision &&
    a.path == b.path &&
    a.language == b.language &&
    a.text == b.text;

/// Prefix sums for measured row heights. Updates and lookup are logarithmic.
///
/// Renderers supply measurements for wrapping and annotations. Unmeasured
/// rows use the estimate, allowing distant scrolling before widgets exist.
final class RowHeightIndex {
  /// Initializes [length] rows with [estimatedHeight].
  RowHeightIndex(this.length, {this.estimatedHeight = 24})
    : _tree = List.filled(length + 1, 0) {
    RangeError.checkNotNegative(length, 'length');
    if (!estimatedHeight.isFinite || estimatedHeight <= 0) {
      throw ArgumentError.value(estimatedHeight, 'estimatedHeight');
    }
  }

  /// Number of addressable logical rows.
  final int length;

  /// Initial height of an unmeasured row.
  final double estimatedHeight;
  final List<double> _tree;
  final Map<int, double> _measured = {};

  /// Number of rows for which the renderer has supplied a measurement.
  int get measuredCount => _measured.length;

  /// Sets an actual row height and returns its change in pixels or cells.
  double measure(int row, double height) {
    RangeError.checkValidIndex(row, _tree, 'row', length);
    if (!height.isFinite || height <= 0) throw ArgumentError.value(height);
    final delta = height - (_measured[row] ?? estimatedHeight);
    _measured[row] = height;
    for (var index = row + 1; index <= length; index += index & -index) {
      _tree[index] += delta;
    }
    return delta;
  }

  /// Distance from the beginning to the top of [row].
  double offsetFor(int row) {
    RangeError.checkValueInInterval(row, 0, length, 'row');
    var offset = row * estimatedHeight;
    for (var index = row; index > 0; index -= index & -index) {
      offset += _tree[index];
    }
    return offset;
  }

  /// Row containing [offset], clamped to the addressable rows.
  int rowAt(double offset) {
    if (length == 0) return 0;
    var low = 0, high = length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (offsetFor(middle) <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
}
