import 'dart:async';
import '../edit/editor.dart';
import '../edit/text_document.dart';
import '../highlighter.dart';
import '../theme/theme.dart';
import 'executor.dart';

/// Coordinates viewport requests and rejects obsolete worker results.
///
/// The application owns [executor], which can be shared by many views. A theme
/// change restyles a ready snapshot from its scopes without rerunning grammars.
final class PresentationController extends SyntaxObservable {
  /// Starts a presentation session over [editor]'s current revision.
  PresentationController({
    required this.editor,
    required this.highlighter,
    required SyntaxTheme theme,
    required this.executor,
    this.language,
    this.overscan = 30,
  }) : _theme = theme {
    RangeError.checkNotNegative(overscan, 'overscan');
    editor.document.addListener(_invalidate);
  }

  /// Persistent source state.
  final EditorController editor;

  /// Grammar definitions serialized to the executor.
  final Highlighter highlighter;

  /// Shared bounded executor or pool; this controller does not dispose it.
  final HighlightExecutor executor;

  /// Optional grammar override independent of the file's display path.
  final String? language;

  /// Extra source lines included before and after the viewport.
  final int overscan;
  SyntaxTheme _theme;

  /// Palette applied to ready and future snapshots.
  SyntaxTheme get theme => _theme;
  set theme(SyntaxTheme value) {
    if (identical(_theme, value)) return;
    _theme = value;
    _snapshot = _snapshot?.retheme(value);
    notifyListeners();
  }

  HighlightResult? _snapshot;

  /// Most recently accepted presentation data, or null while none is ready.
  HighlightResult? get snapshot => _snapshot;

  /// Last non-cancellation worker error; a later request can retry.
  Object? error;
  CancellationToken? _cancellation;
  Timer? _timer;
  int _start = 0, _end = 1, _generation = 0, _grammarRevision = -1;

  /// Whether a request is queued or executing.
  bool get isLoading => _cancellation != null || _timer != null;

  /// Requests a half-open logical line range, coalescing changes in this turn.
  void setViewport(int start, int end) {
    checkAlive();
    RangeError.checkValidRange(start, end, editor.document.lineCount);
    if (_start == start &&
        _end == end &&
        _grammarRevision == highlighter.revision &&
        (_snapshot != null || isLoading)) {
      return;
    }
    _start = start;
    _end = end;
    _invalidate();
  }

  void _invalidate() {
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    _timer?.cancel();
    _snapshot = null;
    _timer = Timer(Duration.zero, () {
      _timer = null;
      unawaited(flush());
    });
    notifyListeners();
  }

  /// Returns a ready absolute source line without creating offscreen spans.
  List<ThemedToken>? line(int index) {
    final ready = _snapshot;
    if (ready == null ||
        index < ready.startLine ||
        index >= ready.startLine + ready.lines.length) {
      return null;
    }
    return ready.lines[index - ready.startLine];
  }

  /// Immediately executes the latest requested viewport.
  Future<void> flush() async {
    checkAlive();
    _timer?.cancel();
    _timer = null;
    _cancellation?.cancel();
    final cancellation = _cancellation = CancellationToken();
    final generation = ++_generation;
    final grammarRevision = _grammarRevision = highlighter.revision;
    final length = editor.document.lineCount;
    final source = editor.file;
    final file = SourceFile(
      id: source.id,
      path: source.path,
      text: source.text,
      revision: source.revision,
      language:
          language ??
          source.language ??
          highlighter.languageForPath(source.path)?.name,
    );
    error = null;
    notifyListeners();
    try {
      final result = await executor.highlight(
        HighlightRequest(
          file: file,
          languages: [
            for (final name in highlighter.languages)
              highlighter.language(name)!,
          ],
          theme: theme,
          maxLineLength: highlighter.maxLineLength,
          startLine: (_start - overscan).clamp(0, length),
          endLine: (_end + overscan).clamp(0, length),
        ),
        cancellation: cancellation,
      );
      if (isDisposed ||
          cancellation.isCancelled ||
          generation != _generation ||
          file.revision != editor.document.revision ||
          grammarRevision != highlighter.revision) {
        return;
      }
      _snapshot = result.retheme(theme);
    } on OperationCancelled {
      // Superseded viewport or disposed session.
    } on Object catch (failure) {
      if (!isDisposed && generation == _generation) error = failure;
    } finally {
      if (!isDisposed && generation == _generation) {
        _cancellation = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _cancellation?.cancel();
    editor.document.removeListener(_invalidate);
    _snapshot = null;
    super.dispose();
  }
}
