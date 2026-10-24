import 'dart:math' as math;

import '../document.dart';
import '../grammar/grammar.dart';
import '../grammar/scope_stack.dart';
import '../highlighter.dart';
import '../theme/theme.dart';
import 'file_diff.dart';
import 'word_diff.dart';

/// Syntax colors for both sides of a [FileDiff].
///
/// Removed lines are highlighted as part of the old file and the other
/// lines as part of the new one. With the full texts, both files are
/// tokenized from the top, so highlighting is exact and costs time in
/// proportion to the files, not the hunks. A parsed patch only has its
/// hunks, so each hunk is tokenized from a fresh state, which is what
/// GitHub does too. A construct that opens before a hunk, such as a block
/// comment, may be colored wrongly inside it.
final class HighlightedDiff {
  HighlightedDiff._(
    this._theme,
    this._old,
    this._new, {
    TokenizedDocument? oldDocument,
    TokenizedDocument? newDocument,
    _LineText? oldPlain,
    _LineText? newPlain,
  }) : _oldDocument = oldDocument,
       _newDocument = newDocument,
       _oldPlain = oldPlain,
       _newPlain = newPlain;

  /// Highlights [diff]. The language comes from [language] if given,
  /// otherwise from the file extension. Unknown languages stay plain.
  ///
  /// With a [budget], full texts are tokenized for at most that long, and
  /// [tokenize] continues. Lines not tokenized yet are plain.
  factory HighlightedDiff.of(
    FileDiff diff, {
    required Highlighter highlighter,
    required SyntaxTheme theme,
    String? language,
    Duration? budget,
  }) {
    final grammar = _grammarFor(diff, highlighter, language);
    if (grammar == null) {
      // Plain: each line is one token, made when it's asked for.
      return HighlightedDiff._(
        theme,
        const {},
        const {},
        oldPlain: _textOf(diff, old: true),
        newPlain: _textOf(diff, old: false),
      );
    }
    final oldLines = diff.oldLines;
    final newLines = diff.newLines;
    if (oldLines != null && newLines != null) {
      final highlighted = HighlightedDiff._(
        theme,
        const {},
        const {},
        oldDocument: TokenizedDocument(grammar),
        newDocument: TokenizedDocument(grammar),
      );
      final clock = Stopwatch()..start();
      highlighted._newDocument!.update(newLines.join('\n'), budget: budget);
      highlighted._oldDocument!.update(
        oldLines.join('\n'),
        budget: _left(budget, clock),
      );
      return highlighted;
    }

    final old = <int, List<ThemedToken>>{};
    final newer = <int, List<ThemedToken>>{};
    void tokenize(
      Iterable<(int, String)> numbered,
      Map<int, List<ThemedToken>> out,
    ) {
      StateStack? state;
      for (final (number, text) in numbered) {
        final tokens = grammar.tokenizeLine(text, state);
        state = tokens.endState;
        out[number] = themeTokens(text, tokens.tokens, theme);
      }
    }

    for (final hunk in diff.hunks) {
      tokenize([
        for (final l in hunk.lines)
          if (_onSide(l, old: true)) (l.oldNumber!, l.text),
      ], old);
      tokenize([
        for (final l in hunk.lines)
          if (_onSide(l, old: false)) (l.newNumber!, l.text),
      ], newer);
    }
    return HighlightedDiff._(theme, old, newer);
  }

  /// Whether [line] is in the old file, or the new one.
  static bool _onSide(DiffLine line, {required bool old}) => old
      ? line.oldNumber != null && line.kind != DiffLineKind.added
      : line.newNumber != null && line.kind != DiffLineKind.removed;

  /// Looks up the text of a line of [diff]'s old or new file by number.
  static _LineText _textOf(FileDiff diff, {required bool old}) {
    final lines = old ? diff.oldLines : diff.newLines;
    if (lines != null) {
      return (n) => n >= 1 && n <= lines.length ? lines[n - 1] : null;
    }
    final byNumber = {
      for (final hunk in diff.hunks)
        for (final l in hunk.lines)
          if (_onSide(l, old: old)) (old ? l.oldNumber! : l.newNumber!): l.text,
    };
    return (n) => byNumber[n];
  }

  /// What's left of [budget] after [clock], or `null` for no budget.
  static Duration? _left(Duration? budget, Stopwatch clock) {
    if (budget == null) return null;
    final left = budget - clock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether every line has its colors.
  bool get isComplete =>
      (_newDocument?.isComplete ?? true) && (_oldDocument?.isComplete ?? true);

  /// Continues highlighting that [HighlightedDiff.of] left unfinished, the
  /// new file first, for at most [budget]. Returns [isComplete].
  bool tokenize({Duration? budget}) {
    final clock = Stopwatch()..start();
    for (final document in [?_newDocument, ?_oldDocument]) {
      if (document.isComplete) continue;
      if (!document.tokenize(budget: _left(budget, clock))) break;
    }
    return isComplete;
  }

  /// The grammar for [diff], or `null` for plain text.
  static Grammar? _grammarFor(
    FileDiff diff,
    Highlighter highlighter,
    String? language,
  ) {
    final effectiveLanguage = language ?? diff.language;
    final lang = effectiveLanguage != null
        ? highlighter.language(effectiveLanguage)
        : highlighter.languageForPath(diff.path);
    return lang == null ? null : highlighter.grammar(lang.scopeName);
  }

  static final ScopeStack _plainScopes = ScopeStack.root('text.plain');

  final SyntaxTheme _theme;

  /// Tokens per line number, for diffs tokenized by hunk or plain.
  final Map<int, List<ThemedToken>> _old;
  final Map<int, List<ThemedToken>> _new;

  /// The full texts, for diffs that have them and a grammar.
  final TokenizedDocument? _oldDocument;
  final TokenizedDocument? _newDocument;

  /// Line texts, for diffs without a grammar.
  final _LineText? _oldPlain;
  final _LineText? _newPlain;

  late final TokenStyle _plain = TokenStyle(foreground: _theme.foreground);

  /// Tokens for a line of the diff: removed lines from the old file, added
  /// and context lines from the new one.
  List<ThemedToken> tokensFor(DiffLine line) =>
      line.kind == DiffLineKind.removed
      ? _line(_oldDocument, _oldPlain, _old, line.oldNumber)
      : _line(_newDocument, _newPlain, _new, line.newNumber);

  /// Tokens for line [number] of the old file. Lines outside the hunks are
  /// only available when the diff has the full texts.
  List<ThemedToken> oldLine(int number) =>
      _line(_oldDocument, _oldPlain, _old, number);

  /// Tokens for line [number] of the new file. Lines outside the hunks are
  /// only available when the diff has the full texts.
  List<ThemedToken> newLine(int number) =>
      _line(_newDocument, _newPlain, _new, number);

  List<ThemedToken> _line(
    TokenizedDocument? document,
    _LineText? plain,
    Map<int, List<ThemedToken>> byNumber,
    int? number,
  ) {
    if (number == null) return const [];
    if (plain != null) {
      final text = plain(number);
      return text == null
          ? const []
          : [ThemedToken(text, 0, _plain, _plainScopes)];
    }
    if (document == null) return byNumber[number] ?? const [];
    final lines = document.lines;
    return number >= 1 && number <= lines.length
        ? lines[number - 1].themed(_theme)
        : const [];
  }

  /// [line] as styled segments, ready to paint. With [words], the segments
  /// are split where the line's changed words start and end, and those are
  /// marked [DiffSegment.changed]. A line without tokens, such as an
  /// expanded line of a parsed patch, is one plain segment.
  List<DiffSegment> segmentsFor(DiffLine line, [WordChanges? words]) {
    if (line.text.isEmpty) return const [];
    var tokens = tokensFor(line);
    // Not tokenized yet, or outside the hunks: one plain token, so changed
    // words are still marked.
    if (tokens.isEmpty) {
      tokens = [ThemedToken(line.text, 0, _plain, _plainScopes)];
    }
    final ranges = words?.rangesFor(line) ?? const <CharRange>[];
    final segments = <DiffSegment>[];
    var r = 0;
    for (final token in tokens) {
      final end = token.offset + token.text.length;
      var pos = token.offset;
      while (pos < end) {
        while (r < ranges.length && ranges[r].end <= pos) {
          r++;
        }
        final inRange = r < ranges.length && ranges[r].start <= pos;
        final next = inRange
            ? math.min(end, ranges[r].end)
            : (r < ranges.length ? math.min(end, ranges[r].start) : end);
        segments.add(
          DiffSegment(
            token.text.substring(pos - token.offset, next - token.offset),
            token.style,
            changed: inRange,
          ),
        );
        pos = next;
      }
    }
    return segments;
  }
}

/// The highlighting and word changes a diff view needs per file, computed
/// the first time a file is asked for.
///
/// A file is highlighted again when its grammar changes, as after
/// [Highlighter.addLanguage]. Create a new cache when the highlighter,
/// theme or language changes. Files are matched by identity.
final class DiffHighlightCache {
  /// A cache that highlights with [highlighter] in [theme], in [language]
  /// or the language of each file's path.
  DiffHighlightCache({
    required this.highlighter,
    required this.theme,
    this.language,
    this.inlineDiffMode = InlineDiffMode.mergedWords,
  });

  /// Provides the grammars.
  final Highlighter highlighter;

  /// Provides the colors.
  final SyntaxTheme theme;

  /// The language of every file, or `null` to guess from each path.
  final String? language;

  /// Inline comparison used by all consumers of this cache.
  final InlineDiffMode inlineDiffMode;

  final Map<FileDiff, (Grammar?, HighlightedDiff)> _highlights = Map.identity();
  final Map<FileDiff, WordChanges> _words = Map.identity();

  /// [file]'s highlighting.
  ///
  /// With a [budget], a file not highlighted yet gets at most that long,
  /// and [tokenize] finishes it. Without one, the file is finished now.
  HighlightedDiff highlighted(FileDiff file, {Duration? budget}) {
    final grammar = HighlightedDiff._grammarFor(file, highlighter, language);
    if (_highlights[file] case (
      final cached,
      final highlighted,
    ) when identical(cached, grammar)) {
      if (budget == null) highlighted.tokenize();
      return highlighted;
    }
    final highlighted = HighlightedDiff.of(
      file,
      highlighter: highlighter,
      theme: theme,
      language: language,
      budget: budget,
    );
    _highlights[file] = (grammar, highlighted);
    return highlighted;
  }

  /// Continues highlighting the files [highlighted] left unfinished, in
  /// the order they were first asked for, for at most [budget]. Returns
  /// whether every file is finished.
  bool tokenize({Duration? budget}) {
    final clock = Stopwatch()..start();
    for (final (_, highlighted) in _highlights.values) {
      if (highlighted.isComplete) continue;
      final left = HighlightedDiff._left(budget, clock);
      if (!highlighted.tokenize(budget: left)) return false;
    }
    return true;
  }

  /// [file]'s changed words.
  WordChanges words(FileDiff file) =>
      _words[file] ??= WordChanges.of(file, mode: inlineDiffMode);

  /// [line] of [file] as styled segments, with its changed words marked.
  List<DiffSegment> segmentsFor(FileDiff file, DiffLine line) =>
      highlighted(file).segmentsFor(line, words(file));
}

/// A piece of a diff line with one style. [changed] marks the words that
/// differ from the paired line, which views give a stronger background.
final class DiffSegment {
  /// Creates a segment of [text] painted with [style].
  const DiffSegment(this.text, this.style, {this.changed = false});

  /// The segment's text.
  final String text;

  /// The token style to paint [text] with.
  final TokenStyle style;

  /// Whether [text] is part of a word that changed.
  final bool changed;

  @override
  bool operator ==(Object other) =>
      other is DiffSegment &&
      other.text == text &&
      other.style == style &&
      other.changed == changed;

  @override
  int get hashCode => Object.hash(text, style, changed);

  @override
  String toString() => changed ? '[$text]' : text;
}

/// The colors a diff view uses, from a theme's `diffEditor.*` and
/// `editorGutter.*` colors, with fallbacks for themes that leave them out.
/// Colors are ARGB integers. Line and word backgrounds are translucent, to
/// paint over the editor background; the chrome colors are opaque.
final class DiffColors {
  /// Colors given directly. [DiffColors.of] reads them from a theme.
  const DiffColors({
    required this.insertedLine,
    required this.removedLine,
    required this.insertedText,
    required this.removedText,
    required this.inserted,
    required this.removed,
    required this.fileHeader,
    required this.hunkHeader,
    required this.emptySide,
    required this.divider,
    required this.muted,
  });

  /// Reads the colors from [theme]. A theme without them gets GitHub's
  /// green and red, with line backgrounds at half the strength of
  /// changed-word backgrounds.
  factory DiffColors.of(SyntaxTheme theme) {
    final dark = theme.isDark;
    final inserted =
        theme.editorColor('editorGutter.addedBackground') ??
        (dark ? 0xFF3FB950 : 0xFF1A7F37);
    final removed =
        theme.editorColor('editorGutter.deletedBackground') ??
        (dark ? 0xFFF85149 : 0xFFCF222E);
    final insertedText =
        theme.editorColor('diffEditor.insertedTextBackground') ??
        _withAlpha(inserted, 0x4D);
    final removedText =
        theme.editorColor('diffEditor.removedTextBackground') ??
        _withAlpha(removed, 0x4D);
    // Chrome is the foreground mixed into the background.
    int tint(double share) => alphaBlend(
      (share * 0xFF).round() << 24 | theme.foreground & 0xFFFFFF,
      theme.background,
    );
    return DiffColors(
      fileHeader: tint(0.06),
      hunkHeader: tint(0.035),
      emptySide: tint(0.02),
      divider: tint(0.12),
      muted: tint(0.62),
      insertedLine:
          theme.editorColor('diffEditor.insertedLineBackground') ??
          _withAlpha(insertedText, _alpha(insertedText) ~/ 2),
      removedLine:
          theme.editorColor('diffEditor.removedLineBackground') ??
          _withAlpha(removedText, _alpha(removedText) ~/ 2),
      insertedText: insertedText,
      removedText: removedText,
      inserted: inserted,
      removed: removed,
    );
  }

  /// Background of an added line.
  final int insertedLine;

  /// Background of a removed line.
  final int removedLine;

  /// Background of the changed words in an added line.
  final int insertedText;

  /// Background of the changed words in a removed line.
  final int removedText;

  /// Accent for additions: markers, counts and status.
  final int inserted;

  /// Accent for removals.
  final int removed;

  /// Background of a file's header.
  final int fileHeader;

  /// Background of `@@` lines, notices and collapsed unchanged lines.
  final int hunkHeader;

  /// Background of the empty side of a split row.
  final int emptySide;

  /// Lines between parts, such as the two sides of a split view.
  final int divider;

  /// Text that matters less than code, such as `@@` lines and notices.
  final int muted;

  @override
  bool operator ==(Object other) =>
      other is DiffColors &&
      other.insertedLine == insertedLine &&
      other.removedLine == removedLine &&
      other.insertedText == insertedText &&
      other.removedText == removedText &&
      other.inserted == inserted &&
      other.removed == removed &&
      other.fileHeader == fileHeader &&
      other.hunkHeader == hunkHeader &&
      other.emptySide == emptySide &&
      other.divider == divider &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(
    insertedLine,
    removedLine,
    insertedText,
    removedText,
    inserted,
    removed,
    fileHeader,
    hunkHeader,
    emptySide,
    divider,
    muted,
  );

  static int _alpha(int argb) => (argb >> 24) & 0xFF;
  static int _withAlpha(int argb, int alpha) =>
      (alpha & 0xFF) << 24 | (argb & 0xFFFFFF);
}

/// The text of a line by its number, or `null` if the diff doesn't have it.
typedef _LineText = String? Function(int number);
