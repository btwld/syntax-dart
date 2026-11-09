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
  final _sources = <Object, WindowSource>{};
  final _words = <_WordPair, WordChanges>{};
  int _wordUnits = 0;
  final _output = MountedWindowHighlights();
  var _changeIndexes = Expando<PatchChangeIndex>();

  /// Retains output requested by mounted rows, including unbounded layouts.
  Widget retain(Widget Function() builder) => _output.retain(builder);

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
    DiffHunk? hunk;
    var hunkIndex = -1;
    if (full == null) {
      hunkIndex = _hunkIndex(file, line);
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
      _changes(file, line, mode),
    );
  }

  int _hunkIndex(FileDiff file, DiffLine line) {
    final old = line.kind == DiffLineKind.removed;
    final number = old ? line.oldNumber : line.newNumber;
    return file.hunks.indexWhere((hunk) {
      final start = old ? hunk.oldStart : hunk.newStart;
      final count = old ? hunk.oldCount : hunk.newCount;
      return number != null && number >= start && number < start + count;
    });
  }

  List<CharRange> _changes(FileDiff file, DiffLine line, InlineDiffMode mode) {
    if (mode == InlineDiffMode.none || line.kind == DiffLineKind.context) {
      return const [];
    }
    final index = _hunkIndex(file, line);
    if (index < 0) return const [];
    final hunk = file.hunks[index];
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
