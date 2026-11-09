import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

import 'highlight_scheduler.dart';
import 'window_source.dart';

/// View-owned, bounded source indexes and visible-line word comparisons.
class PatchWindowHighlights {
  /// Uses a scheduler shared by every file and side in the view.
  PatchWindowHighlights(this.scheduler);

  /// Serializes source windows and bounds their retained results.
  final HighlightWindowScheduler scheduler;
  final _sources = <Object, WindowSource>{};
  final _words = <_WordPair, WordChanges>{};
  int _wordUnits = 0;
  final _ready = <Object, List<StyledRange>>{};
  final _unpinnedReady = <Object>{};
  final _pins = <Object, int>{};
  Set<Object>? _building;

  /// Retains output requested by a mounted row, including unbounded layouts.
  /// Only unmounted windows participate in the eight-window output LRU.
  Widget retain(Widget Function() builder) =>
      _RetainedHighlights(cache: this, builder: builder);

  void _updatePins(Set<Object> before, Set<Object> after) {
    for (final key in before.difference(after)) {
      final remaining = _pins[key]! - 1;
      if (remaining == 0) {
        _pins.remove(key);
        if (_ready.containsKey(key)) _unpinnedReady.add(key);
      } else {
        _pins[key] = remaining;
      }
    }
    for (final key in after.difference(before)) {
      _pins.update(key, (count) => count + 1, ifAbsent: () => 1);
      _unpinnedReady.remove(key);
    }
    _trimReady();
  }

  void _trimReady() {
    while (_unpinnedReady.length > 8) {
      final oldest = _unpinnedReady.first;
      _unpinnedReady.remove(oldest);
      _ready.remove(oldest);
    }
  }

  final _identities = Expando<int>();
  int _nextIdentity = 0;

  Object _windowKey(
    String id,
    int revision,
    String language,
    int start,
    int end,
  ) => (id, revision, language, start, end);

  /// Keeps output ranges independently of complete input requests. Oversized
  /// old/new sources can take turns without evicting visible colors.
  void accept(HighlightWindowResult result) {
    final request = result.request;
    final key = _windowKey(
      request.fileId,
      request.revision,
      request.language,
      request.startLine,
      request.endLine,
    );
    _remember(key, result.ranges);
  }

  void _remember(Object key, List<StyledRange> ranges) {
    _ready.remove(key);
    _ready[key] = ranges;
    if (!_pins.containsKey(key)) {
      _unpinnedReady.remove(key);
      _unpinnedReady.add(key);
    }
    _trimReady();
  }

  /// Drops derived indexes and word changes when the source changes.
  void clear() {
    _sources.clear();
    _words.clear();
    _wordUnits = 0;
    _ready.clear();
    _unpinnedReady.clear();
    scheduler.clear();
  }

  /// Requests syntax for this row and compares only its changed-word pair.
  List<DiffSegment> segments(
    FileDiff file,
    DiffLine line,
    Highlighter highlighter,
    SyntaxTheme theme,
    String? language,
    InlineDiffMode mode,
  ) {
    final old = line.kind == DiffLineKind.removed;
    final number = old ? line.oldNumber : line.newNumber;
    final full = old ? file.oldLines : file.newLines;
    DiffHunk? hunk;
    var hunkIndex = -1;
    if (full == null) {
      hunkIndex = file.hunks.indexWhere((h) {
        final start = old ? h.oldStart : h.newStart;
        final count = old ? h.oldCount : h.newCount;
        return number != null && number >= start && number < start + count;
      });
      if (hunkIndex >= 0) hunk = file.hunks[hunkIndex];
    }
    final snapshot = _identities[file] ??= _nextIdentity++;
    final key = (snapshot, old, hunkIndex);
    final source =
        _sources.remove(key) ??
        WindowSource.lines(
          full ??
              [
                for (final l in hunk?.lines ?? const <DiffLine>[])
                  if (old
                      ? l.kind != DiffLineKind.added
                      : l.kind != DiffLineKind.removed)
                    l.text,
              ],
        );
    _sources[key] = source;
    while (_sources.length > 1 &&
        (_sources.length > 8 ||
            _sources.values.fold<int>(0, (n, s) => n + s.codeUnits) >
                1024 * 1024)) {
      _sources.remove(_sources.keys.first);
    }
    final index = number == null
        ? -1
        : full != null
        ? number - 1
        : hunk == null
        ? -1
        : number - (old ? hunk.oldStart : hunk.newStart);
    final effectiveLanguage =
        language ??
        file.language ??
        highlighter.languageForPath(file.path)?.name ??
        '';
    final id = '${file.id}:$snapshot:$hunkIndex:$old';
    List<StyledRange>? ranges;
    if (index >= 0 && index < source.offsets.length) {
      final start = index ~/ 64 * 64;
      final end = start + 64 < source.offsets.length
          ? start + 64
          : source.offsets.length;
      final readyKey = _windowKey(
        id,
        file.revision,
        effectiveLanguage,
        start,
        end,
      );
      _building?.add(readyKey);
      ranges =
          _ready[readyKey] ??
          source.ranges(index, id, file.revision, effectiveLanguage, scheduler);
      if (ranges != null) _remember(readyKey, ranges);
    }
    return windowSegments(
      line.text,
      index < 0 || index >= source.offsets.length ? 0 : source.offsets[index],
      ranges,
      TokenStyle(foreground: theme.foreground),
      _changes(file, line, mode),
    );
  }

  List<CharRange> _changes(FileDiff file, DiffLine line, InlineDiffMode mode) {
    if (mode == InlineDiffMode.none || line.kind == DiffLineKind.context) {
      return const [];
    }
    // Compare only the visible line's pair, instead of computing word changes
    // for every offscreen hunk before the first frame can paint.
    final hunk = file.hunks.where((h) => h.lines.contains(line)).firstOrNull;
    if (hunk == null) return const [];
    final lines = hunk.lines;
    final index = lines.indexOf(line);
    var start = index;
    while (start > 0 && lines[start - 1].kind != DiffLineKind.context) {
      if (lines[start].kind == DiffLineKind.removed &&
          lines[start - 1].kind == DiffLineKind.added) {
        break;
      }
      start--;
    }
    var added = start;
    while (added < lines.length && lines[added].kind == DiffLineKind.removed) {
      added++;
    }
    var end = added;
    while (end < lines.length && lines[end].kind == DiffLineKind.added) {
      end++;
    }
    final pair = line.kind == DiffLineKind.removed
        ? index - start
        : index - added;
    if (pair < 0 || pair >= added - start || pair >= end - added) {
      return const [];
    }
    final before = lines[start + pair], after = lines[added + pair];
    if (before.text.length > 10000 || after.text.length > 10000) {
      return const [];
    }
    final key = _WordPair(before, after, mode);
    final cached = _words.remove(key);
    if (cached == null) _wordUnits += before.text.length + after.text.length;
    final words =
        cached ??
        WordChanges.of(
          FileDiff(
            oldPath: null,
            newPath: null,
            kind: FileDiffKind.modified,
            hunks: [
              DiffHunk(
                oldStart: 1,
                oldCount: 1,
                newStart: 1,
                newCount: 1,
                lines: [before, after],
              ),
            ],
          ),
          mode: mode,
        );
    _words[key] = words;
    while (_words.length > 256 || _wordUnits > 1024 * 1024) {
      final oldest = _words.keys.first;
      _words.remove(oldest);
      _wordUnits -= oldest.before.text.length + oldest.after.text.length;
    }
    return words.rangesFor(line);
  }
}

// WordChanges indexes the original line objects by identity. Value-equal pairs
// from another snapshot must not reuse those identity-indexed ranges.
final class _WordPair {
  _WordPair(this.before, this.after, this.mode);

  final DiffLine before, after;
  final InlineDiffMode mode;

  @override
  bool operator ==(Object other) =>
      other is _WordPair &&
      identical(before, other.before) &&
      identical(after, other.after) &&
      mode == other.mode;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(before), identityHashCode(after), mode);
}

class _RetainedHighlights extends StatefulWidget {
  const _RetainedHighlights({required this.cache, required this.builder});

  final PatchWindowHighlights cache;
  final Widget Function() builder;

  @override
  State<_RetainedHighlights> createState() => _RetainedHighlightsState();
}

class _RetainedHighlightsState extends State<_RetainedHighlights> {
  Set<Object> _keys = {};

  @override
  void didUpdateWidget(_RetainedHighlights oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cache, widget.cache)) {
      oldWidget.cache._updatePins(_keys, const {});
      _keys = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = widget.cache;
    final keys = <Object>{};
    final previous = cache._building;
    cache._building = keys;
    try {
      return widget.builder();
    } finally {
      cache._building = previous;
      cache._updatePins(_keys, keys);
      _keys = keys;
    }
  }

  @override
  void dispose() {
    widget.cache._updatePins(_keys, const {});
    super.dispose();
  }
}
