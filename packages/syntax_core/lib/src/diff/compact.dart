import 'dart:math';

import 'myers.dart';

/// Regroups the changes in [edits], an edit script from [a] to [b], the
/// way git does after its own diff, in xdiff's `xdl_change_compact`.
///
/// A run of changed lines can often move up or down without changing the
/// result, when the line it gives up equals the line it takes in. Each run
/// first slides up as far as it can, merging with any run it meets, then
/// down as far as it can. If somewhere along that path it sits next to a
/// change on the other side, it moves back up to the lowest such spot, so
/// a replaced line pairs with its replacement. Otherwise, if [aLines] and
/// [bLines], the texts of the lines of [a] and [b], are given, it moves to
/// the spot git's indent heuristic picks from the indents and blank lines
/// around each edge, which tends to keep whole blocks of code together.
/// Without them it stays at the bottom, as in
/// `git diff --no-indent-heuristic`. The old side is compacted first, then
/// the new side. Within each block, deletes come before inserts.
List<Edit> compactEdits(
  List<Edit> edits,
  List<int> a,
  List<int> b, {
  List<String>? aLines,
  List<String>? bLines,
}) {
  assert((aLines == null) == (bLines == null), 'Pass both texts or neither');
  final before = _Lines(a, aLines);
  final after = _Lines(b, bLines);
  for (final e in edits) {
    switch (e.kind) {
      case EditKind.delete:
        before.changed[e.oldIndex] = true;
      case EditKind.insert:
        after.changed[e.newIndex] = true;
      case EditKind.equal:
    }
  }
  _compact(before, after);
  _compact(after, before);

  final result = <Edit>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (!before.changed[i] && !after.changed[j]) {
      result.add((kind: EditKind.equal, oldIndex: i++, newIndex: j++));
      continue;
    }
    while (before.changed[i]) {
      result.add((kind: EditKind.delete, oldIndex: i++, newIndex: -1));
    }
    while (after.changed[j]) {
      result.add((kind: EditKind.insert, oldIndex: -1, newIndex: j++));
    }
  }
  return result;
}

/// Slides each run of changed lines in [lines], keeping [other] in step.
void _compact(_Lines lines, _Lines other) {
  // Groups match up one to one between the sides: group k is the run,
  // possibly empty, just before the k-th unchanged line.
  final g = _Group(lines);
  final go = _Group(other);
  while (true) {
    if (g.end != g.start) {
      int size;
      int earliestEnd;
      int? endNextToOther;
      // Merging with a neighbour can open up more room, so repeat until
      // the run stops growing.
      do {
        size = g.end - g.start;
        endNextToOther = null;
        while (g.slideUp()) {
          go.previous();
        }
        earliestEnd = g.end;
        if (go.end != go.start) endNextToOther = g.end;
        while (g.slideDown()) {
          go.next();
          if (go.end != go.start) endNextToOther = g.end;
        }
      } while (size != g.end - g.start);
      if (g.end == earliestEnd) {
        // It can't move.
      } else if (endNextToOther != null) {
        while (go.end == go.start) {
          g.slideUp();
          go.previous();
        }
      } else if (lines.text != null) {
        final end = _bestEnd(lines.indents, earliestEnd, g.end, size);
        while (g.end > end) {
          g.slideUp();
          go.previous();
        }
      }
    }
    if (!g.next()) break;
    go.next();
  }
}

/// Where git's indent heuristic ends a run of [size] changed lines that can
/// end anywhere from [earliestEnd] down to [latestEnd], in a file whose
/// lines have [indents]. Each spot is scored by its two edges, the split
/// above the run and the split below it. On a tie the lower spot wins.
int _bestEnd(List<int> indents, int earliestEnd, int latestEnd, int size) {
  // Like git, try at most the bottom size + 2 spots, and none more than
  // _maxSlide lines up.
  var end = max(earliestEnd, max(latestEnd - size - 1, latestEnd - _maxSlide));
  var bestEnd = end;
  _SplitScore? best;
  for (; end <= latestEnd; end++) {
    final score = _SplitScore()
      ..add(indents, end)
      ..add(indents, end - size);
    if (best == null || score.compareTo(best) <= 0) {
      best = score;
      bestEnd = end;
    }
  }
  return bestEnd;
}

// Git's indent heuristic weights, from xdiff/xdiffi.c. A higher penalty
// makes a split less likely.

/// MAX_INDENT: indents are capped here.
const _maxIndent = 200;

/// MAX_BLANKS: runs of blank lines are counted up to here.
const _maxBlanks = 20;

/// INDENT_HEURISTIC_MAX_SLIDING: how far up the heuristic looks.
const _maxSlide = 100;

/// INDENT_WEIGHT: what a smaller sum of indents at the splits is worth.
const _indentWeight = 60;

/// START_OF_FILE_PENALTY: no non-blank line above the split.
const _startOfFilePenalty = 1;

/// END_OF_FILE_PENALTY: no line below the split.
const _endOfFilePenalty = 21;

/// TOTAL_BLANK_WEIGHT: per blank line around the split.
const _totalBlankWeight = -30;

/// POST_BLANK_WEIGHT: per blank line below the split.
const _postBlankWeight = 6;

/// RELATIVE_INDENT_PENALTY: the line below the split is indented more than
/// the line above it.
const _relativeIndentPenalty = -4;
const _relativeIndentWithBlankPenalty = 10;

/// RELATIVE_OUTDENT_PENALTY: it is indented less than the line above and
/// the line after it, so it likely starts a block.
const _relativeOutdentPenalty = 24;
const _relativeOutdentWithBlankPenalty = 17;

/// RELATIVE_DEDENT_PENALTY: it is indented less than the line above but
/// not the line after it, so it likely ends a block.
const _relativeDedentPenalty = 23;
const _relativeDedentWithBlankPenalty = 17;

/// How bad it looks to split a file at some lines, as git's indent
/// heuristic scores it. Lower is better for both [effectiveIndent] and
/// [penalty], and [compareTo] weighs one against the other.
final class _SplitScore {
  var effectiveIndent = 0;
  var penalty = 0;

  /// Adds the score of splitting the file just above line [split], given
  /// the [indents] of its lines. Git's `measure_split` and
  /// `score_add_split`.
  void add(List<int> indents, int split) {
    final endOfFile = split >= indents.length;
    final indent = endOfFile ? -1 : indents[split];

    // The blank lines just above the split, and the indent of the line
    // above them.
    var preBlank = 0;
    var preIndent = -1;
    for (var i = split - 1; i >= 0; i--) {
      preIndent = indents[i];
      if (preIndent != -1) break;
      if (++preBlank == _maxBlanks) {
        preIndent = 0;
        break;
      }
    }

    // The same for the lines after the one just below the split.
    var postBlank = 0;
    var postIndent = -1;
    for (var i = split + 1; i < indents.length; i++) {
      postIndent = indents[i];
      if (postIndent != -1) break;
      if (++postBlank == _maxBlanks) {
        postIndent = 0;
        break;
      }
    }

    if (preIndent == -1 && preBlank == 0) penalty += _startOfFilePenalty;
    if (endOfFile) penalty += _endOfFilePenalty;

    // Blank lines below the split, counting the one just below it.
    final blanksBelow = indent == -1 ? 1 + postBlank : 0;
    final blanks = preBlank + blanksBelow;
    penalty += _totalBlankWeight * blanks + _postBlankWeight * blanksBelow;

    final lineIndent = indent != -1 ? indent : postIndent;
    effectiveIndent += lineIndent;
    if (lineIndent == -1 || preIndent == -1 || lineIndent == preIndent) {
      // No adjustment.
    } else if (lineIndent > preIndent) {
      penalty += blanks != 0
          ? _relativeIndentWithBlankPenalty
          : _relativeIndentPenalty;
    } else if (postIndent != -1 && postIndent > lineIndent) {
      penalty += blanks != 0
          ? _relativeOutdentWithBlankPenalty
          : _relativeOutdentPenalty;
    } else {
      penalty += blanks != 0
          ? _relativeDedentWithBlankPenalty
          : _relativeDedentPenalty;
    }
  }

  /// Negative when this score is better than [other], zero when they tie.
  /// Git's `score_cmp`.
  int compareTo(_SplitScore other) =>
      _indentWeight * effectiveIndent.compareTo(other.effectiveIndent) +
      penalty -
      other.penalty;
}

/// The indent of [line], counting a tab as up to the next multiple of 8
/// columns and capped at [_maxIndent], or -1 if it is blank. Like git, only
/// tab, space, `\r` and `\n` count as white space.
int _indentOf(String line) {
  var indent = 0;
  for (var i = 0; i < line.length; i++) {
    switch (line.codeUnitAt(i)) {
      case 0x20:
        indent++;
      case 0x09:
        indent += 8 - indent % 8;
      case 0x0A || 0x0D:
        continue;
      default:
        return indent;
    }
    if (indent >= _maxIndent) return _maxIndent;
  }
  return -1;
}

/// One side of a diff: its line keys and which lines are changed.
final class _Lines {
  _Lines(this.keys, this.text) : changed = List.filled(keys.length + 1, false);

  final List<int> keys;

  /// The text of each line, if the indent heuristic should run.
  final List<String>? text;

  /// One flag per line, plus an unchanged sentinel after the last line.
  final List<bool> changed;

  /// Each line's indent, or -1 for a blank line.
  late final List<int> indents = [for (final line in text!) _indentOf(line)];

  bool changedAt(int i) => i >= 0 && changed[i];
}

/// A run of changed lines, from [start] up to but not including [end].
final class _Group {
  _Group(this.lines) {
    while (lines.changed[end]) {
      end++;
    }
  }

  final _Lines lines;
  var start = 0;
  var end = 0;

  /// Moves to the next group, unless this is the last one.
  bool next() {
    if (end == lines.keys.length) return false;
    start = end = end + 1;
    while (lines.changed[end]) {
      end++;
    }
    return true;
  }

  /// Moves to the previous group, unless this is the first one.
  bool previous() {
    if (start == 0) return false;
    start = end = start - 1;
    while (lines.changedAt(start - 1)) {
      start--;
    }
    return true;
  }

  /// Shifts the run down one line if the line below equals its first line,
  /// taking in any run it then touches.
  bool slideDown() {
    final keys = lines.keys;
    if (end == keys.length || keys[start] != keys[end]) return false;
    lines.changed[start++] = false;
    lines.changed[end++] = true;
    while (lines.changed[end]) {
      end++;
    }
    return true;
  }

  /// Shifts the run up one line if the line above equals its last line,
  /// taking in any run it then touches.
  bool slideUp() {
    final keys = lines.keys;
    if (start == 0 || keys[start - 1] != keys[end - 1]) return false;
    lines.changed[--start] = true;
    lines.changed[--end] = false;
    while (lines.changedAt(start - 1)) {
      start--;
    }
    return true;
  }
}
