import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import '../edit/editor.dart';
import '../edit/text_document.dart';
import '../grammar/grammar.dart';
import '../grammar/scope_stack.dart';
import '../highlighter.dart';
import '../theme/theme.dart';

/// Fully serializable input; compiled grammars never cross isolate boundaries.
final class HighlightRequest {
  /// Captures serializable source, grammars, palette and viewport options.
  HighlightRequest({
    required this.file,
    required Iterable<Language> languages,
    required this.theme,
    this.maxLineLength = 20000,
    this.startLine = 0,
    this.endLine,
  }) : languages = List.unmodifiable(languages);

  /// Current source snapshot, including stable identity and document revision.
  final SourceFile file;

  /// Raw registered language definitions needed by the request.
  final List<Language> languages;

  /// Palette used to resolve token scopes into presentation styles.
  final SyntaxTheme theme;

  /// Tokenization limit in UTF-16 units per line; zero removes the limit.
  final int maxLineLength;

  /// First output line; preceding lines advance grammar state without spans.
  final int startLine;

  /// Exclusive output limit, or the end of the document.
  final int? endLine;

  /// Encodes portable data for storage or transport to another executor.
  Map<String, Object?> toJson() => {
    'id': file.id,
    'path': file.path,
    'text': file.text,
    'revision': file.revision,
    'language': file.language,
    'maxLineLength': maxLineLength,
    'startLine': startLine,
    'endLine': endLine,
    'theme': theme.json,
    'themeName': theme.name,
    'languages': [
      for (final l in languages)
        {
          'name': l.name,
          'aliases': l.aliases,
          'injectTo': l.injectTo,
          'grammar': l.grammar,
        },
    ],
  };

  /// Restores a value from its portable serialized representation.
  factory HighlightRequest.fromJson(Map<String, Object?> json) =>
      HighlightRequest(
        file: SourceFile(
          id: json['id'] as String,
          path: json['path'] as String,
          text: json['text'] as String,
          revision: json['revision'] as int,
          language: json['language'] as String?,
        ),
        theme: SyntaxTheme.fromJson(
          Map<String, Object?>.from(json['theme'] as Map),
          name: json['themeName'] as String,
        ),
        maxLineLength: json['maxLineLength'] as int,
        startLine: json['startLine'] as int? ?? 0,
        endLine: json['endLine'] as int?,
        languages: [
          for (final entry in json['languages'] as List)
            (() {
              final e = Map<String, Object?>.from(entry as Map);
              return Language.fromJson(
                Map<String, Object?>.from(e['grammar'] as Map),
                name: e['name'] as String,
                aliases: (e['aliases'] as List).cast<String>(),
                injectTo: (e['injectTo'] as List).cast<String>(),
              );
            })(),
        ],
      );

  /// Complete serialized request identity, including content and options.
  late final String cacheKey = jsonEncode(toJson());
}

/// A reusable presentation snapshot. Tokens retain scope information for hover
/// and bracket interactions as well as colors and font styles.
final class HighlightResult {
  /// Creates a reusable snapshot of styled tokens for a source revision.
  HighlightResult({
    required this.fileId,
    required this.revision,
    required Iterable<List<ThemedToken>> lines,
    this.startLine = 0,
  }) : lines = List.unmodifiable(lines.map(List<ThemedToken>.unmodifiable));

  /// Stable application-supplied identity of the associated file.
  final String fileId;

  /// Monotonically increasing content revision for rejecting obsolete work.
  final int revision;

  /// Tokens for consecutive output lines beginning at startLine.
  final List<List<ThemedToken>> lines;

  /// Absolute zero-based index of the first stored line.
  final int startLine;

  /// Reuses scopes to change palettes without tokenizing again.
  HighlightResult retheme(SyntaxTheme theme) => HighlightResult(
    fileId: fileId,
    revision: revision,
    startLine: startLine,
    lines: [
      for (final line in lines)
        [
          for (final token in line)
            ThemedToken(
              token.text,
              token.offset,
              theme.styleFor(token.scopes),
              token.scopes,
            ),
        ],
    ],
  );

  /// Encodes portable data for storage or transport to another executor.
  Map<String, Object?> toJson() => {
    'id': fileId,
    'revision': revision,
    'startLine': startLine,
    'lines': [
      for (final line in lines)
        [
          for (final t in line)
            [
              t.text,
              t.offset,
              t.style.foreground,
              t.style.background,
              t.style.fontStyle,
              t.scopes.scopes,
            ],
        ],
    ],
  };

  /// Restores a value from its portable serialized representation.
  factory HighlightResult.fromJson(Map<String, Object?> json) =>
      HighlightResult(
        fileId: json['id'] as String,
        revision: json['revision'] as int,
        startLine: json['startLine'] as int? ?? 0,
        lines: [
          for (final line in json['lines'] as List)
            [
              for (final value in line as List)
                (() {
                  final t = value as List;
                  final scopes = (t[5] as List).cast<String>();
                  var stack = ScopeStack.root(scopes.first);
                  for (final scope in scopes.skip(1)) {
                    stack = stack.push(scope);
                  }
                  return ThemedToken(
                    t[0] as String,
                    t[1] as int,
                    TokenStyle(
                      foreground: t[2] as int,
                      background: t[3] as int?,
                      fontStyle: t[4] as int,
                    ),
                    stack,
                  );
                })(),
            ],
        ],
      );
}

/// Executes serializable highlighting requests with explicit lifetime ownership.
abstract interface class HighlightExecutor {
  /// Computes presentation data; cancellation and disposal reject pending work.
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  });

  /// Cancels pending work and releases retained resources; the object must not be reused.
  void dispose();
}

/// Stateless synchronous work, also used by native and browser workers.
HighlightResult computeHighlight(HighlightRequest request) {
  final highlighter = Highlighter(
    languages: request.languages,
    maxLineLength: request.maxLineLength,
  );
  final language =
      request.file.language ??
      highlighter.languageForPath(request.file.path)?.name;
  final document = TextDocument(request.file.text);
  final grammar = language == null || highlighter.language(language) == null
      ? null
      : highlighter.grammar(language);
  StateStack? state;
  final lines = <List<ThemedToken>>[];
  try {
    RangeError.checkValidRange(
      request.startLine,
      request.endLine ?? document.lineCount,
      document.lineCount,
    );
    for (var i = 0; i < (request.endLine ?? document.lineCount); i++) {
      final text = document.lineText(i);
      if (grammar == null) {
        if (i < request.startLine) continue;
        lines.add([
          ThemedToken(
            text,
            0,
            TokenStyle(foreground: request.theme.foreground),
            ScopeStack.root('text.plain'),
          ),
        ]);
      } else {
        final tokens = grammar.tokenizeLine(text, state);
        state = tokens.endState;
        if (i >= request.startLine) {
          lines.add([
            for (final token in tokens.tokens)
              ThemedToken(
                text.substring(token.start, token.end),
                token.start,
                request.theme.styleFor(token.scopes),
                token.scopes,
              ),
          ]);
        }
      }
    }
    return HighlightResult(
      fileId: request.file.id,
      revision: request.file.revision,
      startLine: request.startLine,
      lines: lines,
    );
  } finally {
    document.dispose();
  }
}

/// Runs highlighting on the caller isolate without yielding between lines.
final class SynchronousHighlightExecutor implements HighlightExecutor {
  bool _disposed = false;
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) async {
    if (_disposed) throw StateError('Executor is disposed');
    cancellation?.throwIfCancelled();
    return computeHighlight(request);
  }

  @override
  void dispose() => _disposed = true;
}

/// Yields between bounded groups of lines so other work can proceed.
final class CooperativeHighlightExecutor implements HighlightExecutor {
  /// Yields between bounded groups of lines so other work can proceed.
  CooperativeHighlightExecutor({this.sliceLines = 100}) {
    if (sliceLines < 1) throw ArgumentError.value(sliceLines, 'sliceLines');
  }

  /// Maximum lines processed between cooperative scheduling yields.
  final int sliceLines;
  bool _disposed = false;
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) async {
    final highlighter = Highlighter(
      languages: request.languages,
      maxLineLength: request.maxLineLength,
    );
    final language =
        request.file.language ??
        highlighter.languageForPath(request.file.path)?.name;
    final grammar = language == null || highlighter.language(language) == null
        ? null
        : highlighter.grammar(language);
    final doc = TextDocument(request.file.text);
    StateStack? state;
    final lines = <List<ThemedToken>>[];
    try {
      RangeError.checkValidRange(
        request.startLine,
        request.endLine ?? doc.lineCount,
        doc.lineCount,
      );
      for (var i = 0; i < (request.endLine ?? doc.lineCount); i++) {
        if (_disposed) throw const OperationCancelled();
        cancellation?.throwIfCancelled();
        final text = doc.lineText(i);
        if (grammar == null) {
          if (i < request.startLine) continue;
          lines.add([
            ThemedToken(
              text,
              0,
              TokenStyle(foreground: request.theme.foreground),
              ScopeStack.root('text.plain'),
            ),
          ]);
        } else {
          final result = grammar.tokenizeLine(text, state);
          state = result.endState;
          if (i >= request.startLine) {
            lines.add([
              for (final token in result.tokens)
                ThemedToken(
                  text.substring(token.start, token.end),
                  token.start,
                  request.theme.styleFor(token.scopes),
                  token.scopes,
                ),
            ]);
          }
        }
        if ((i + 1) % sliceLines == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      cancellation?.throwIfCancelled();
      return HighlightResult(
        fileId: request.file.id,
        revision: request.file.revision,
        startLine: request.startLine,
        lines: lines,
      );
    } finally {
      doc.dispose();
    }
  }

  @override
  void dispose() => _disposed = true;
}

/// Current queue, cache and completed-request counters.
final class ExecutorStats {
  /// Current queue, cache and completed-request counters.
  const ExecutorStats(this.active, this.queued, this.cached, this.completed);

  /// Executing jobs, waiting jobs, cached results and completed backend requests.
  final int active, queued, cached, completed;
}

final class _Task {
  _Task(this.request, this.generation, this.fileGeneration);
  final int generation, fileGeneration;
  final cancellation = CancellationToken();
  final HighlightRequest request;
  final result = Completer<HighlightResult>();
  int consumers = 0;
  bool running = false;
}

/// Bounded queue and LRU cache. Cancellation belongs to each consumer so one
/// cancelled view cannot cancel an identical request still needed elsewhere.
final class HighlightPool extends SyntaxObservable
    implements HighlightExecutor {
  /// Bounds concurrency, pending requests and cached results across an executor.
  HighlightPool({
    required this.executor,
    this.concurrency = 2,
    this.cacheSize = 16,
    this.queueSize = 64,
    this.timeout = const Duration(seconds: 30),
  }) {
    if (concurrency < 1 || queueSize < 1 || cacheSize < 0) {
      throw ArgumentError('Invalid pool limits');
    }
  }

  /// Owned backend, disposed when this pool is disposed.
  final HighlightExecutor executor;

  /// Limits for active jobs, cached results and queued distinct requests.
  final int concurrency, cacheSize, queueSize;

  /// Maximum duration of a backend request before cancellation.
  final Duration timeout;
  final _cache = <String, HighlightResult>{};
  final Map<String, _Task> _pending = {};
  final Queue<_Task> _queue = Queue();
  int _active = 0, _completed = 0, _generation = 0;
  final Map<String, int> _fileGenerations = {};

  /// Current bounded-resource usage and completed backend count.
  ExecutorStats get stats =>
      ExecutorStats(_active, _queue.length, _cache.length, _completed);
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) async {
    checkAlive();
    cancellation?.throwIfCancelled();
    final key = request.cacheKey;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    var task = _pending[key];
    if (task == null) {
      if (_queue.length >= queueSize) {
        throw StateError('Highlight queue is full');
      }
      task = _Task(
        request,
        _generation,
        _fileGenerations[request.file.id] ?? 0,
      );
      _pending[key] = task;
      _queue.add(task);
    }
    task.consumers++;
    _pump();
    try {
      final result =
          await (cancellation?.bind(task.result.future) ?? task.result.future);
      cancellation?.throwIfCancelled();
      return result;
    } finally {
      task.consumers--;
      if (task.consumers == 0 && !task.result.isCompleted) {
        task.cancellation.cancel();
        if (identical(_pending[key], task)) _pending.remove(key);
        if (!task.running) {
          _queue.remove(task);
          task.result.completeError(const OperationCancelled());
          _pump();
        }
      }
    }
  }

  void _pump() {
    while (!isDisposed && _active < concurrency && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      task.running = true;
      _active++;
      unawaited(_run(task));
    }
    if (!isDisposed) notifyListeners();
  }

  Future<void> _run(_Task task) async {
    try {
      final result = await task.cancellation
          .bind(
            executor.highlight(task.request, cancellation: task.cancellation),
          )
          .timeout(
            timeout,
            onTimeout: () {
              task.cancellation.cancel();
              throw TimeoutException('Highlight request timed out', timeout);
            },
          );
      if (!isDisposed &&
          cacheSize > 0 &&
          task.generation == _generation &&
          task.fileGeneration ==
              (_fileGenerations[task.request.file.id] ?? 0)) {
        while (_cache.length >= cacheSize) {
          _cache.remove(_cache.keys.first);
        }
        _cache[task.request.cacheKey] = result;
      }
      if (!task.result.isCompleted) task.result.complete(result);
    } on Object catch (error, stack) {
      if (!task.result.isCompleted) task.result.completeError(error, stack);
    } finally {
      _active--;
      _completed++;
      if (identical(_pending[task.request.cacheKey], task)) {
        _pending.remove(task.request.cacheKey);
      }
      _pump();
    }
  }

  /// Invalidates cached and in-flight cache entries for a file identity.
  void evict(String fileId) {
    _fileGenerations[fileId] = (_fileGenerations[fileId] ?? 0) + 1;
    _cache.removeWhere((_, result) => result.fileId == fileId);
  }

  /// Clears cached results and prevents earlier requests from repopulating them.
  void clearCache() {
    _generation++;
    _cache.clear();
    _fileGenerations.clear();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    for (final task in _pending.values) {
      task.cancellation.cancel();
      if (!task.result.isCompleted) {
        task.result.completeError(const OperationCancelled());
      }
    }
    _queue.clear();
    _pending.clear();
    _cache.clear();
    executor.dispose();
    super.dispose();
  }
}
