import 'dart:math' as math;

import 'file_diff.dart';
import 'myers.dart';

/// A half-open range of UTF-16 offsets within a line.
typedef CharRange = ({int start, int end});

/// Inline comparison policy, independent of the surrounding line diff.
/// Granularity of bounded inline change highlighting.
enum InlineDiffMode {
  /// Compare individual word and punctuation tokens.
  word,

  /// Merge adjacent changed word regions.
  mergedWords,

  /// Highlight one region from the first to the last difference.
  changedSpan,

  /// Compare Unicode characters.
  character,

  /// Disable inline emphasis while keeping line changes.
  none,
}

/// The changed words within edited lines, for highlighting what changed
/// inside a line rather than only which lines changed.
///
/// Within each block of removed lines followed by added lines, the n-th
/// removed line is paired with the n-th added line, like GitHub does.
/// Pairs that share too little are treated as rewritten lines and get no
/// word ranges.
final class WordChanges {
  WordChanges._(this._ranges);

  final Map<DiffLine, List<CharRange>> _ranges;

  /// The changed ranges in [line], or an empty list.
  List<CharRange> rangesFor(DiffLine line) => _ranges[line] ?? const [];

  /// Computes word changes for every hunk in [diff].
  factory WordChanges.of(
    FileDiff diff, {
    InlineDiffMode mode = InlineDiffMode.mergedWords,
    int maxLineLength = 10000,
  }) {
    final ranges = Map<DiffLine, List<CharRange>>.identity();
    for (final hunk in diff.hunks) {
      final lines = hunk.lines;
      var i = 0;
      while (i < lines.length) {
        final removedStart = i;
        while (i < lines.length && lines[i].kind == DiffLineKind.removed) {
          i++;
        }
        final addedStart = i;
        while (i < lines.length && lines[i].kind == DiffLineKind.added) {
          i++;
        }
        final pairs = (addedStart - removedStart) < (i - addedStart)
            ? addedStart - removedStart
            : i - addedStart;
        for (var p = 0; p < pairs; p++) {
          final removed = lines[removedStart + p];
          final added = lines[addedStart + p];
          if (mode == InlineDiffMode.none ||
              (maxLineLength > 0 &&
                  (removed.text.length > maxLineLength ||
                      added.text.length > maxLineLength))) {
            continue;
          }
          final (oldRanges, newRanges) = _compare(
            removed.text,
            added.text,
            mode,
          );
          if (oldRanges.isNotEmpty) ranges[removed] = oldRanges;
          if (newRanges.isNotEmpty) ranges[added] = newRanges;
        }
        if (i == removedStart) i++; // a context line
      }
    }
    return WordChanges._(ranges);
  }
}

final RegExp _word = RegExp(r'[\p{L}\p{N}_]+|\s+|.', unicode: true);

/// Below this share of unchanged non-space text, a pair counts as
/// rewritten and gets no word ranges.
const _minSimilarity = 0.5;

(List<CharRange>, List<CharRange>) _compare(
  String a,
  String b,
  InlineDiffMode mode,
) {
  final pattern = mode == InlineDiffMode.character
      ? RegExp(r'[\s\S]', unicode: true)
      : _word;
  final aTokens = pattern.allMatches(a).toList();
  final bTokens = pattern.allMatches(b).toList();
  final ids = <String, int>{};
  int id(Match m) => ids.putIfAbsent(m.group(0)!, () => ids.length);
  final edits = myersDiff(
    [for (final t in aTokens) id(t)],
    [for (final t in bTokens) id(t)],
    maxEdits: 200,
  );

  var shared = 0;
  final oldChanged = <CharRange>[];
  final newChanged = <CharRange>[];
  for (final e in edits) {
    switch (e.kind) {
      case EditKind.equal:
        shared += _visibleLength(aTokens[e.oldIndex].group(0)!);
      case EditKind.delete:
        final t = aTokens[e.oldIndex];
        oldChanged.add((start: t.start, end: t.end));
      case EditKind.insert:
        final t = bTokens[e.newIndex];
        newChanged.add((start: t.start, end: t.end));
    }
  }

  final longest = math.max(_visibleLength(a), _visibleLength(b));
  if (longest == 0 || shared / longest < _minSimilarity) {
    return (const [], const []);
  }
  List<CharRange> finish(List<CharRange> ranges, String text) {
    if (ranges.isEmpty) return const [];
    if (mode == InlineDiffMode.changedSpan) {
      return [(start: ranges.first.start, end: ranges.last.end)];
    }
    return mode == InlineDiffMode.mergedWords ? _merge(ranges, text) : ranges;
  }

  return (finish(oldChanged, a), finish(newChanged, b));
}

final RegExp _space = RegExp(r'\s');

int _visibleLength(String s) => s.replaceAll(_space, '').length;

/// Joins ranges that touch or are separated only by whitespace.
List<CharRange> _merge(List<CharRange> ranges, String line) {
  final merged = <CharRange>[];
  for (final r in ranges) {
    if (merged.isNotEmpty &&
        line.substring(merged.last.end, r.start).trim().isEmpty) {
      merged.last = (start: merged.last.start, end: r.end);
    } else {
      merged.add(r);
    }
  }
  return merged;
}
