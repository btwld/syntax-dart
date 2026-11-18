import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

import 'highlight_scheduler.dart';
import 'mounted_window_highlights.dart';
import 'patch_change_index.dart';
import 'window_source.dart';

/// View-owned, bounded source indexes and visible-line word comparisons.
class PatchWindowHighlights {
  /// Uses a scheduler shared by every file and side in the view.
  PatchWindowHighlights(this.scheduler);

  /// Serializes source windows and bounds their retained results.
  final HighlightWindowScheduler scheduler;
  final _sources = MountedResourceCache<WindowSource>(
    maxCodeUnits: 1024 * 1024,
    codeUnits: (source) => source.codeUnits,
  );
  final _words = <_WordPair, WordChanges>{};
  int _wordUnits = 0;
  final _output = MountedWindowHighlights();
  var _changeIndexes = Expando<PatchChangeIndex>();
  final _hunkIndexes = Expando<_HunkIndex>();

  /// Retains output requested by mounted rows, including unbounded layouts.
  Widget retain(
    Widget Function() builder, {
    List<MountedResourceCache<Object>> also = const [],
  }) => _output.retain(builder, also: [_sources, ...also]);

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
    _output.remember(key, result.ranges);
  }

  /// Drops derived indexes and word changes when the source changes.
  void clear() {
    _sources.clear();
    _words.clear();
    _wordUnits = 0;
    _output.clear();
    _changeIndexes = Expando();
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
    final compareWords =
        mode != InlineDiffMode.none && line.kind != DiffLineKind.context;
    final hunkIndex = number != null && (full == null || compareWords)
        ? (_hunkIndexes[file] ??= _HunkIndex(file.hunks)).find(number, old: old)
        : -1;
    final hunk = hunkIndex < 0 ? null : file.hunks[hunkIndex];
    final sourceHunk = full == null ? hunkIndex : -1;
    final snapshot = _identities[file] ??= _nextIdentity++;
    final key = (snapshot, old, sourceHunk);
    final source = _sources.resourceFor(
      key,
      () => WindowSource.lines(
        full ??
            [
              for (final l in hunk?.lines ?? const <DiffLine>[])
                if (old
                    ? l.kind != DiffLineKind.added
                    : l.kind != DiffLineKind.removed)
                  l.text,
            ],
      ),
    )!;
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
    final id = '${file.id}:$snapshot:$sourceHunk:$old';
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
      ranges = _output.rangesFor(
        readyKey,
        () => source.ranges(
          index,
          id,
          file.revision,
          effectiveLanguage,
          scheduler,
        ),
      );
    }
    return windowSegments(
      line.text,
      index < 0 || index >= source.offsets.length ? 0 : source.offsets[index],
      ranges,
      TokenStyle(foreground: theme.foreground),
      compareWords && hunk != null ? _changes(hunk, line, mode) : const [],
    );
  }

  List<CharRange> _changes(DiffHunk hunk, DiffLine line, InlineDiffMode mode) {
    final pair = (_changeIndexes[hunk] ??= PatchChangeIndex(
      hunk.lines,
    )).pairFor(line);
    if (pair == null) return const [];
    final (before, after) = pair;
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

typedef _HunkRange = ({int start, int end, int index});

final class _HunkIndex {
  _HunkIndex(List<DiffHunk> hunks)
    : _hunks = hunks,
      _old = _ranges(hunks, old: true),
      _new = _ranges(hunks, old: false);

  final List<DiffHunk> _hunks;
  final List<_HunkRange>? _old, _new;

  static List<_HunkRange>? _ranges(List<DiffHunk> hunks, {required bool old}) {
    final ranges = <_HunkRange>[];
    for (var index = 0; index < hunks.length; index++) {
      final hunk = hunks[index];
      final start = old ? hunk.oldStart : hunk.newStart;
      final count = old ? hunk.oldCount : hunk.newCount;
      if (count <= 0) continue;
      final last = ranges.lastOrNull;
      if (last != null && start < last.end) return null;
      ranges.add((start: start, end: start + count, index: index));
    }
    return ranges;
  }

  int find(int number, {required bool old}) {
    final ranges = old ? _old : _new;
    if (ranges == null) {
      // Caller-supplied or recovered hunks can be out of order or overlap.
      // Keep the first matching hunk for these inputs.
      return _hunks.indexWhere((hunk) {
        final start = old ? hunk.oldStart : hunk.newStart;
        final count = old ? hunk.oldCount : hunk.newCount;
        return number >= start && number < start + count;
      });
    }
    var low = 0;
    var high = ranges.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final range = ranges[mid];
      if (number < range.start) {
        high = mid;
      } else if (number >= range.end) {
        low = mid + 1;
      } else {
        return range.index;
      }
    }
    return -1;
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
