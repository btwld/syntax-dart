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

  /// The grammar lines are tokenized with. Setting a different grammar
  /// drops every cached line, since states from another grammar can't be
  /// reused.
  Grammar get grammar => _grammar;
  set grammar(Grammar value) {
    if (identical(value, _grammar)) return;
    _grammar = value;
    _text = null;
    _lines = const [];
  }

  /// The lines of the text last passed to [update], split on `\n`.
  List<DocumentLine> get lines => UnmodifiableListView(_lines);

  /// Brings [lines] up to date with [text].
  void update(String text) {
    if (identical(text, _text)) return;

    final newLines = text.split('\n');
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

    final result = <DocumentLine>[...old.take(prefix)];
    var state = prefix == 0 ? null : old[prefix - 1].endState;
    final shift = old.length - newLines.length;
    for (var i = prefix; i < newLines.length; i++) {
      final oldIndex = i + shift;
      if (i >= newLines.length - suffix && old[oldIndex].startState == state) {
        result.addAll(old.skip(oldIndex));
        break;
      }
      final line = DocumentLine._tokenize(_grammar, newLines[i], state);
      result.add(line);
      state = line.endState;
    }
    _lines = result;
    // Set last, so a failed update is retried by the next call.
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
