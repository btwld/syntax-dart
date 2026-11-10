import 'dart:async';

import 'document.dart';
import 'grammar/grammar.dart';
import 'highlighter.dart';
import 'theme/theme.dart';

/// Source identity and a zero-based, half-open line window to highlight.
///
/// Lines are split on LF, including an empty final line after a terminator.
/// CR in a CRLF break is excluded from styled ranges, as in
/// [TokenizedDocument]. Exact [code] participates in cache identity even when
/// [fileId] and [revision] are unchanged.
final class HighlightWindowRequest {
  /// Requests lines [startLine] through, but excluding, [endLine].
  const HighlightWindowRequest({
    required this.fileId,
    required this.revision,
    required this.code,
    required this.language,
    required this.startLine,
    required this.endLine,
  });

  /// Caller-owned source identity, independent of its display path.
  final String fileId;

  /// Caller-owned source version.
  final int revision;

  /// Complete source, needed to advance grammar state before the window.
  final String code;

  /// Registered language name, alias or scope name.
  final String language;

  /// Inclusive zero-based first line.
  final int startLine;

  /// Exclusive zero-based last line; must not exceed the source line count.
  final int endLine;
}

/// Cooperative cancellation shared by a caller and its highlighting work.
///
/// Cancellation is checked before each line and after each scheduling yield.
/// An individual synchronous regex match cannot be interrupted.
final class HighlightCancellation {
  /// Creates an uncancelled operation.
  HighlightCancellation();

  bool _cancelled = false;
  final _waits = <Timer, Completer<void>>{};
  final _externalWaits = <Completer<void>>{};

  /// Prevents further work and delivery of its result. Safe to call repeatedly.
  void cancel() {
    _cancelled = true;
    for (final entry in _waits.entries) {
      entry.key.cancel();
      entry.value.complete();
    }
    _waits.clear();
    for (final done in _externalWaits) {
      done.complete();
    }
    _externalWaits.clear();
  }

  Future<void> _yield(Future<void> Function()? yieldControl) {
    throwIfCancelled();
    if (yieldControl != null) {
      final done = Completer<void>();
      _externalWaits.add(done);
      Future<void>.sync(yieldControl).then(
        (_) {
          if (_externalWaits.remove(done)) done.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (_externalWaits.remove(done)) done.completeError(error, stack);
        },
      );
      return done.future;
    }
    final done = Completer<void>();
    late final Timer timer;
    timer = Timer(Duration.zero, () {
      _waits.remove(timer);
      done.complete();
    });
    _waits[timer] = done;
    return done.future;
  }

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Throws [HighlightCancelled] if this operation has been cancelled.
  void throwIfCancelled() {
    if (_cancelled) throw const HighlightCancelled();
  }
}

/// A window operation stopped by [HighlightCancellation].
final class HighlightCancelled implements Exception {
  /// Creates a cancellation exception.
  const HighlightCancelled();

  @override
  String toString() => 'HighlightCancelled';
}

/// Styled ranges and the exact source/configuration identity that made them.
final class HighlightWindowResult {
  /// Creates an immutable result for [request] under [theme].
  HighlightWindowResult({
    required this.request,
    required this.grammarRevision,
    required this.theme,
    required List<StyledRange> ranges,
  }) : ranges = List.unmodifiable(ranges);

  /// Exact source identity and requested line boundaries.
  final HighlightWindowRequest request;

  /// Registration revision of the highlighter when work started.
  final int grammarRevision;

  /// Palette used to style the ranges.
  final SyntaxTheme theme;

  /// Source identity echoed from [request].
  String get fileId => request.fileId;

  /// Source version echoed from [request].
  int get revision => request.revision;

  /// Inclusive first line echoed from [request].
  int get startLine => request.startLine;

  /// Exclusive last line echoed from [request].
  int get endLine => request.endLine;

  /// Non-overlapping UTF-16 ranges into [HighlightWindowRequest.code].
  /// Only the requested lines are included; line breaks are excluded.
  final List<StyledRange> ranges;
}

final _caches = Expando<HighlightWindowCache>();

/// Highlights only a line window, advancing preceding grammar state in
/// cooperative slices without retaining preceding styled output.
///
/// Repeated calls share a bounded cache per [highlighter]. Use a separate
/// [HighlightWindowCache] when explicit retention limits or clearing are needed.
/// Throws [RangeError] for an invalid window and [HighlightCancelled] when
/// cancelled. Unknown languages produce plain ranges.
Future<HighlightWindowResult> highlightWindow(
  HighlightWindowRequest request, {
  required Highlighter highlighter,
  required SyntaxTheme theme,
  required HighlightCancellation cancellation,
}) => (_caches[highlighter] ??= HighlightWindowCache()).highlight(
  request,
  highlighter: highlighter,
  theme: theme,
  cancellation: cancellation,
);

/// Bounded source, raw-token and grammar-checkpoint reuse for window requests.
///
/// No styled output is retained. Theme changes reuse raw tokens. Each source
/// retains at most [maxCachedLines] raw lines and [maxCheckpoints] states.
/// Source identity includes exact content, language, highlighter identity and
/// its registration revision. One oversize source is allowed by itself.
final class HighlightWindowCache {
  /// Creates a cache with positive retention and cooperative slice limits.
  HighlightWindowCache({
    this.maxEntries = 4,
    this.maxCodeUnits = 1024 * 1024,
    this.maxCachedLines = 512,
    this.maxCheckpoints = 2048,
    this.sliceLines = 64,
    this.yieldControl,
  }) {
    for (final value in [
      maxEntries,
      maxCodeUnits,
      maxCachedLines,
      maxCheckpoints,
      sliceLines,
    ]) {
      if (value < 1) throw ArgumentError('Cache limits must be positive');
    }
  }

  /// Maximum retained source snapshots.
  final int maxEntries;

  /// Maximum total source UTF-16 length, except one oversize snapshot.
  final int maxCodeUnits;

  /// Maximum raw token lines per snapshot.
  final int maxCachedLines;

  /// Maximum grammar checkpoints per snapshot.
  final int maxCheckpoints;

  /// Maximum lines between event-loop yields (also limited to six milliseconds).
  final int sliceLines;

  /// Optional scheduling yield, for example a renderer's next frame.
  /// Defaults to a cancellable event-loop timer. Cancellation releases a
  /// pending custom yield too; its late completion is ignored.
  final Future<void> Function()? yieldControl;

  final _entries = <Object, _WindowSource>{};
  int _tokenizedLines = 0;

  /// Number of source snapshots retained by the cache.
  int get entryCount => _entries.length;

  /// Sum of retained source UTF-16 lengths.
  int get retainedCodeUnits =>
      _entries.values.fold(0, (n, e) => n + e.code.length);

  /// Total raw token lines retained across sources.
  int get cachedLines => _entries.values.fold(0, (n, e) => n + e.lines.length);

  /// Total grammar checkpoints retained across sources.
  int get checkpoints => _entries.values.fold(0, (n, e) => n + e.points.length);

  /// Cumulative tokenized lines, including grammar-state advancement.
  int get tokenizedLines => _tokenizedLines;

  /// Releases cached sources, tokens and checkpoints. Inflight work may finish
  /// for its caller, but cannot reinsert its source into this cache.
  void clear() => _entries.clear();

  /// Highlights [request] using the same contract as [highlightWindow].
  Future<HighlightWindowResult> highlight(
    HighlightWindowRequest request, {
    required Highlighter highlighter,
    required SyntaxTheme theme,
    required HighlightCancellation cancellation,
  }) async {
    cancellation.throwIfCancelled();
    if (request.startLine < 0 || request.endLine < request.startLine) {
      throw RangeError('Invalid half-open line window');
    }
    final revision = highlighter.revision;
    final grammar = highlighter.language(request.language) == null
        ? null
        : highlighter.grammar(request.language);
    final key = (
      request.fileId,
      request.revision,
      request.code,
      request.language,
      highlighter,
      revision,
    );
    final source = _entries.remove(key) ?? _WindowSource(request.code);
    _entries[key] = source;
    while (_entries.length > 1 &&
        (_entries.length > maxEntries || retainedCodeUnits > maxCodeUnits)) {
      _entries.remove(_entries.keys.first);
    }
    var point = const _Checkpoint(0, 0, null);
    for (final candidate in source.points.values) {
      if (candidate.line <= request.startLine && candidate.line > point.line) {
        point = candidate;
      }
    }
    var line = point.line, offset = point.offset;
    var state = point.state;
    var sliced = 0;
    final clock = Stopwatch()..start();
    final ranges = <StyledRange>[];
    while (line < request.endLine) {
      cancellation.throwIfCancelled();
      if (offset > request.code.length) {
        throw RangeError('Window exceeds source');
      }
      if (line == request.startLine || line % 64 == 0) {
        source.checkpoint(_Checkpoint(line, offset, state), maxCheckpoints);
      }
      final lf = request.code.indexOf('\n', offset);
      final end = lf < 0 ? request.code.length : lf;
      final raw = request.code.substring(offset, end);
      final text = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final cached = source.lines.remove(line);
      DocumentLine? tokens;
      if (grammar != null) {
        tokens = cached?.$2;
        if (tokens == null || tokens.startState != state) {
          tokens = DocumentLine.tokenize(grammar, raw, state);
          _tokenizedLines++;
        }
        state = tokens.endState;
      }
      if (line >= request.startLine) {
        if (tokens != null) {
          source.lines[line] = (offset, tokens);
          while (source.lines.length > maxCachedLines) {
            source.lines.remove(source.lines.keys.first);
          }
          for (final token in themeTokens(text, tokens.tokens, theme)) {
            if (token.text.isNotEmpty) {
              ranges.add(
                StyledRange(
                  offset + token.offset,
                  offset + token.offset + token.text.length,
                  token.style,
                ),
              );
            }
          }
        } else if (text.isNotEmpty) {
          ranges.add(
            StyledRange(
              offset,
              offset + text.length,
              TokenStyle(foreground: theme.foreground),
            ),
          );
        }
      } else if (cached != null) {
        source.lines[line] = cached;
      }
      line++;
      offset = end + 1;
      if (++sliced >= sliceLines || clock.elapsedMilliseconds >= 6) {
        await cancellation._yield(yieldControl);
        cancellation.throwIfCancelled();
        sliced = 0;
        clock.reset();
      }
    }
    source.checkpoint(_Checkpoint(line, offset, state), maxCheckpoints);
    cancellation.throwIfCancelled();
    return HighlightWindowResult(
      request: request,
      grammarRevision: revision,
      theme: theme,
      ranges: ranges,
    );
  }
}

final class _WindowSource {
  _WindowSource(this.code);
  final String code;
  final lines = <int, (int, DocumentLine)>{};
  final points = <int, _Checkpoint>{};
  void checkpoint(_Checkpoint point, int limit) {
    points.remove(point.line);
    points[point.line] = point;
    while (points.length > limit) {
      points.remove(points.keys.first);
    }
  }
}

final class _Checkpoint {
  const _Checkpoint(this.line, this.offset, this.state);
  final int line, offset;
  final StateStack? state;
}
