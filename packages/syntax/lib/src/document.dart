import 'dart:collection';

import 'grammar/grammar.dart';
import 'highlighter.dart';
import 'theme/theme.dart';

/// A run of text with one style, as UTF-16 offsets into a whole document.
///
/// Ranges never span a line break and never overlap, and they come in
/// document order. Line breaks, including the `\r` of a CRLF break, are
/// not covered by any range.
final class StyledRange {
  /// A range from [start] to [end] painted with [style].
  const StyledRange(this.start, this.end, this.style);

  /// Inclusive start offset.
  final int start;

  /// Exclusive end offset.
  final int end;

  /// How to paint the range.
  final TokenStyle style;

  @override
  bool operator ==(Object other) =>
      other is StyledRange &&
      other.start == start &&
      other.end == end &&
      other.style == style;

  @override
  int get hashCode => Object.hash(start, end, style);

  @override
  String toString() =>
      'StyledRange($start, $end, ${colorToHex(style.foreground)})';
}

/// A document whose lines stay tokenized as its text changes.
///
/// [update] finds the unchanged lines at the start and end of the new text
/// and re-tokenizes the lines between them, stopping once the tokenizer
/// state matches the state cached for an old line. Typing in a large file
/// therefore re-tokenizes a few lines. An edit that changes how the rest is
/// read, such as opening a block comment, re-tokenizes up to the end of the
/// affected region.
///
/// With a time budget, [update] stops when the budget is spent and
/// [tokenize] continues later, so a large text can be tokenized a slice at
/// a time without blocking a UI thread. [lines] grows from the top as it
/// goes.
///
/// Unchanged lines keep their [DocumentLine] objects across updates, so a
/// renderer can cache its own output per line.
///
/// ```dart
/// final document = TokenizedDocument(highlighter.grammar('dart'));
/// document.update(source);
/// final ranges = document.ranges(githubDarkTheme);
/// ```
final class TokenizedDocument {
  /// An empty document for [grammar]. Call [update] with its text.
  TokenizedDocument(this._grammar);

  Grammar _grammar;
  String? _text;
  List<DocumentLine> _lines = const [];

  /// Work left by an [update] that ran out of budget.
  _Pending? _pending;

  /// The grammar lines are tokenized with. Setting a different grammar
  /// drops every cached line, since states from another grammar can't be
  /// reused.
  Grammar get grammar => _grammar;
  set grammar(Grammar value) {
    if (identical(value, _grammar)) return;
    _grammar = value;
    _text = null;
    _lines = const [];
    _pending = null;
  }

  /// The tokenized lines of the text last passed to [update], split on
  /// `\n`: all of them once [isComplete], otherwise the first ones.
  List<DocumentLine> get lines => UnmodifiableListView(_lines);

  /// Whether every line of the text last passed to [update] is tokenized.
  bool get isComplete => _pending == null;

  /// Brings [lines] up to date with [text], and returns [isComplete].
  ///
  /// With a [budget], it stops once that much time is spent, after at
  /// least one line, and [tokenize] continues from there.
  bool update(String text, {Duration? budget}) {
    if (!identical(text, _text)) _start(text);
    return tokenize(budget: budget);
  }

  /// Continues an [update] that ran out of budget, for at most [budget],
  /// and returns [isComplete].
  bool tokenize({Duration? budget}) {
    final pending = _pending;
    if (pending == null) return true;
    final clock = budget == null ? null : (Stopwatch()..start());
    final lines = pending.newLines;
    final old = pending.old;
    final shift = old.length - lines.length;
    var tokenized = 0;
    while (pending.next < lines.length) {
      if (clock != null && tokenized > 0 && clock.elapsed >= budget!) {
        return false;
      }
      final i = pending.next;
      final oldIndex = i + shift;
      if (i >= pending.suffixStart &&
          old[oldIndex].startState == pending.state) {
        _lines.addAll(old.skip(oldIndex));
        break;
      }
      final line = DocumentLine._tokenize(_grammar, lines[i], pending.state);
      _lines.add(line);
      // Kept current, so a line that throws is retried, not skipped.
      pending
        ..state = line.endState
        ..next = i + 1;
      tokenized++;
    }
    _pending = null;
    return true;
  }

  /// Keeps the unchanged lines before the edit, and leaves the rest to
  /// [tokenize].
  void _start(String text) {
    final newLines = text.split('\n');
    // The lines tokenized so far, which are all of the previous text's
    // unless an update was left unfinished.
    final old = _lines;

    // Lines before the edit are unchanged, along with their state.
    final maxShared = old.length < newLines.length
        ? old.length
        : newLines.length;
    var prefix = 0;
    while (prefix < maxShared && old[prefix].raw == newLines[prefix]) {
      prefix++;
    }
    // Lines after the edit are unchanged too. Their tokens are reusable
    // once the tokenizer state matches again.
    var suffix = 0;
    while (suffix < maxShared - prefix &&
        old[old.length - 1 - suffix].raw ==
            newLines[newLines.length - 1 - suffix]) {
      suffix++;
    }

    _lines = [...old.take(prefix)];
    _pending = _Pending(
      newLines,
      old,
      suffixStart: newLines.length - suffix,
      state: prefix == 0 ? null : old[prefix - 1].endState,
      next: prefix,
    );
    _text = text;
  }

  /// Every token of the document as a [StyledRange] under [theme].
  List<StyledRange> ranges(SyntaxTheme theme) {
    final ranges = <StyledRange>[];
    var offset = 0;
    for (final line in _lines) {
      for (final token in line.themed(theme)) {
        if (token.text.isEmpty) continue;
        final start = offset + token.offset;
        ranges.add(StyledRange(start, start + token.text.length, token.style));
      }
      offset += line.raw.length + 1;
    }
    return ranges;
  }
}

/// One line of a [TokenizedDocument].
final class DocumentLine {
  DocumentLine._(
    this.raw,
    this.text,
    this.startState,
    this.tokens,
    this.endState,
  );

  factory DocumentLine._tokenize(
    Grammar grammar,
    String raw,
    StateStack? state,
  ) {
    final text = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    final result = grammar.tokenizeLine(text, state);
    return DocumentLine._(raw, text, state, result.tokens, result.endState);
  }

  /// The line as it is in the document, including a trailing `\r`.
  final String raw;

  /// The line without a trailing `\r`, as tokenized.
  final String text;

  /// The tokenizer state before this line; `null` for the first line.
  final StateStack? startState;

  /// The tokens of [text].
  final List<Token> tokens;

  /// The tokenizer state after this line, which the next line starts
  /// from.
  final StateStack endState;

  /// Whether [raw] ends with the `\r` of a CRLF line break.
  bool get endsWithCr => raw.length > text.length;

  SyntaxTheme? _themedWith;
  List<ThemedToken> _themed = const [];

  /// [tokens] styled by [theme], cached for the last theme used.
  List<ThemedToken> themed(SyntaxTheme theme) {
    if (theme == _themedWith) return _themed;
    _themedWith = theme;
    return _themed = themeTokens(text, tokens, theme);
  }
}

final class _Pending {
  _Pending(
    this.newLines,
    this.old, {
    required this.suffixStart,
    required this.state,
    required this.next,
  });

  final List<String> newLines;

  /// The lines tokenized before this update, reused where they match.
  final List<DocumentLine> old;

  /// The first new line in the unchanged suffix.
  final int suffixStart;

  /// The state before line [next].
  StateStack? state;

  /// The next line to tokenize.
  int next;
}
