import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:syntax_core/syntax.dart';

/// Runs a window locally, in an isolate, or through an application worker.
///
/// Implementations must echo the request, theme and grammar revision in their
/// result. The scheduler serializes calls even if an executor ignores cancellation.
typedef HighlightExecutor =
    Future<HighlightWindowResult> Function(
      HighlightWindowRequest request, {
      required Highlighter highlighter,
      required SyntaxTheme theme,
      required HighlightCancellation cancellation,
    });

/// Serializes viewport work and bounds retained requests and results.
///
/// Only windows requested through [rangesFor] are processed. Ready windows are
/// reused until evicted. Source, content, grammar, palette and executor changes
/// cancel obsolete work. A stale active call still counts against the limits
/// until it settles. One oversize input is allowed alone; additional requests
/// are retried by the view after [onChanged]. Failures stay plain until cleared.
final class HighlightWindowScheduler {
  /// Creates a scheduler. Limits must be positive.
  HighlightWindowScheduler({
    required Highlighter highlighter,
    required SyntaxTheme theme,
    required this.onChanged,
    HighlightExecutor executor = highlightWindow,
    this.maxEntries = 8,
    this.maxCodeUnits = 1024 * 1024,
    this.onError,
    this.onResult,
  }) : _highlighter = highlighter,
       _theme = theme,
       _executor = executor,
       _revision = highlighter.revision {
    if (maxEntries < 1 || maxCodeUnits < 1) {
      throw ArgumentError('Scheduler limits must be positive');
    }
  }

  /// Notifies a view when work finishes, including an obsolete active call.
  final void Function() onChanged;

  /// Observes accepted output before the repaint notification. A renderer can
  /// retain ranges without retaining the result's complete source request.
  final void Function(HighlightWindowResult)? onResult;

  /// Receives executor failures. Cancellation is not reported as an error.
  final void Function(Object, StackTrace)? onError;

  /// Maximum retained windows, including queued and stale active work.
  final int maxEntries;

  /// Maximum retained request UTF-16 units, except one oversize input alone.
  /// Windows sharing exact source content are charged once.
  final int maxCodeUnits;

  Highlighter _highlighter;
  SyntaxTheme _theme;
  HighlightExecutor _executor;
  int _revision;
  bool _disposed = false, _scheduled = false;
  _Job? _active;
  final _entries = <Object, _Job>{};

  /// Number of retained windows, including inflight calls.
  int get entryCount => _entries.length;

  /// Source size charged to all retained windows.
  int get retainedCodeUnits => _entries.values
      .map((job) => job.request.code)
      .toSet()
      .fold(0, (n, code) => n + code.length);

  /// Active and queued executor calls, including cancelled active work.
  int get pendingCount => _entries.values.where((job) => !job.done).length;

  /// Updates execution configuration, discarding obsolete colors and requests.
  void configure({
    required Highlighter highlighter,
    required SyntaxTheme theme,
    HighlightExecutor executor = highlightWindow,
  }) {
    if (_disposed) return;
    if (identical(highlighter, _highlighter) &&
        theme == _theme &&
        executor == _executor &&
        highlighter.revision == _revision) {
      return;
    }
    clear();
    _highlighter = highlighter;
    _theme = theme;
    _executor = executor;
    _revision = highlighter.revision;
  }

  /// Returns ready colors, or queues the window and returns null for plain text.
  ///
  /// A replacement of the same file invalidates previous revisions and exact
  /// content, including when the caller forgot to advance its revision.
  List<StyledRange>? rangesFor(HighlightWindowRequest request) {
    if (_disposed) return null;
    if (_revision != _highlighter.revision) {
      configure(highlighter: _highlighter, theme: _theme, executor: _executor);
    }
    for (final entry in _entries.entries.toList()) {
      final old = entry.value.request;
      if (old.fileId == request.fileId &&
          (old.revision != request.revision ||
              old.code != request.code ||
              old.language != request.language)) {
        _discard(entry.key);
      }
    }
    final key = (
      request.fileId,
      request.revision,
      request.code,
      request.language,
      request.startLine,
      request.endLine,
      _highlighter,
      _revision,
      _theme,
      _executor,
    );
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing.result?.ranges;
    }
    int additionalUnits() =>
        _entries.values.any((job) => job.request.code == request.code)
        ? 0
        : request.code.length;
    while (_entries.isNotEmpty &&
        (_entries.length >= maxEntries ||
            (additionalUnits() > 0 &&
                retainedCodeUnits + additionalUnits() > maxCodeUnits))) {
      final candidates = _entries.entries.where((e) => e.value != _active);
      if (candidates.isEmpty) return null;
      _discard(candidates.first.key);
    }
    _entries[key] = _Job(request, _highlighter, _theme, _executor, _revision);
    _schedule();
    return null;
  }

  void _discard(Object key) {
    final job = _entries[key]!;
    job.cancellation.cancel();
    if (job != _active) _entries.remove(key);
  }

  /// Discards ready and queued work; an active executor is cancelled but is
  /// awaited before any subsequent call can start.
  void clear() {
    for (final key in _entries.keys.toList()) {
      _discard(key);
    }
  }

  void _schedule() {
    if (_scheduled || _active != null || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_active != null || _disposed) return;
    final pending = _entries.entries.where(
      (e) => !e.value.done && !e.value.cancellation.isCancelled,
    );
    if (pending.isEmpty) return;
    final entry = pending.last;
    final job = entry.value;
    _active = job;
    try {
      final result = await job.executor(
        job.request,
        highlighter: job.highlighter,
        theme: job.theme,
        cancellation: job.cancellation,
      );
      if (!_disposed &&
          !job.cancellation.isCancelled &&
          job.revision == _highlighter.revision &&
          _matches(result, job)) {
        job.result = result;
        onResult?.call(result);
      }
    } catch (error, stack) {
      if (!_disposed &&
          !job.cancellation.isCancelled &&
          error is! HighlightCancelled) {
        onError?.call(error, stack);
      }
    } finally {
      job.done = true;
      _active = null;
      if (job.cancellation.isCancelled) _entries.remove(entry.key);
      if (!_disposed) {
        onChanged();
        _schedule();
      }
    }
  }

  bool _matches(HighlightWindowResult result, _Job job) {
    final a = result.request, b = job.request;
    return a.fileId == b.fileId &&
        a.revision == b.revision &&
        a.code == b.code &&
        a.language == b.language &&
        a.startLine == b.startLine &&
        a.endLine == b.endLine &&
        result.grammarRevision == job.revision &&
        result.theme == job.theme;
  }

  /// Cancels work, releases retained inputs and ignores all late completions.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _entries.values) {
      job.cancellation.cancel();
    }
    _entries.clear();
  }
}

final class _Job {
  _Job(
    this.request,
    this.highlighter,
    this.theme,
    this.executor,
    this.revision,
  );
  final HighlightWindowRequest request;
  final Highlighter highlighter;
  final SyntaxTheme theme;
  final HighlightExecutor executor;
  final int revision;
  final cancellation = HighlightCancellation();
  bool done = false;
  HighlightWindowResult? result;
}

final _frameCache = HighlightWindowCache(yieldControl: _nextFrame);

Future<void> _nextFrame() {
  final done = Completer<void>();
  SchedulerBinding.instance
    ..addPostFrameCallback((_) => done.complete())
    ..ensureVisualUpdate();
  return done.future;
}

/// Internal default executor that yields between Flutter frames.
Future<HighlightWindowResult> highlightWindowInFrames(
  HighlightWindowRequest request, {
  required Highlighter highlighter,
  required SyntaxTheme theme,
  required HighlightCancellation cancellation,
}) => _frameCache.highlight(
  request,
  highlighter: highlighter,
  theme: theme,
  cancellation: cancellation,
);
