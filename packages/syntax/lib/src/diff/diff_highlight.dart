import 'dart:math' as math;

import '../grammar/grammar.dart';
import '../grammar/scope_stack.dart';
import '../highlighter.dart';
import '../theme/theme.dart';
import 'file_diff.dart';
import 'word_diff.dart';

/// Syntax colors for both sides of a [FileDiff].
///
/// Removed lines are highlighted as part of the old file and the other
/// lines as part of the new one. With the full texts, grammar state is
/// advanced to each requested line. Checkpoints and a bounded token cache
/// avoid constructing offscreen presentation data. A
/// parsed patch only has its hunks, so each hunk is tokenized from a fresh
/// state, which is what GitHub does too. A construct that opens before a
/// hunk, such as a block comment, may be colored wrongly inside it.
final class HighlightedDiff {
  HighlightedDiff._(this._old, this._new, this._plain);

  /// Highlights [diff]. The language comes from [language] if given,
  /// otherwise from the file extension. Unknown languages stay plain.
  factory HighlightedDiff.of(
    FileDiff diff, {
    required Highlighter highlighter,
    required SyntaxTheme theme,
    String? language,
  }) {
    final grammar = _grammarFor(diff, highlighter, language);

    _DiffLines side(bool old) => _DiffLines(
      grammar,
      theme,
      full: old ? diff.oldLines : diff.newLines,
      hunks: [
        for (final hunk in diff.hunks)
          [
            for (final line in hunk.lines)
              if ((old ? line.oldNumber : line.newNumber) case final number?)
                (number, line.text),
          ],
      ],
    );
    return HighlightedDiff._(
      side(true),
      side(false),
      TokenStyle(foreground: theme.foreground),
    );
  }

  /// Changes colors while retaining grammar checkpoints and raw token scopes.
  void setTheme(SyntaxTheme theme) {
    _plain = TokenStyle(foreground: theme.foreground);
    for (final side in [_old, _new]) {
      side.theme = theme;
      for (final entry in side._cache.entries.toList()) {
        side._cache[entry.key] = [
          for (final token in entry.value)
            ThemedToken(
              token.text,
              token.offset,
              theme.styleFor(token.scopes),
              token.scopes,
            ),
        ];
      }
    }
  }

  /// Number of retained styled lines across both sides, bounded at 1024.
  int get cachedLineCount => _old._cache.length + _new._cache.length;

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

  final _DiffLines _old;
  final _DiffLines _new;
  TokenStyle _plain;

  /// Tokens for a line of the diff: removed lines from the old file, added
  /// and context lines from the new one.
  List<ThemedToken> tokensFor(DiffLine line) =>
      (line.kind == DiffLineKind.removed
          ? _old[line.oldNumber]
          : _new[line.newNumber]) ??
      const [];

  /// Tokens for line [number] of the old file. Lines outside the hunks are
  /// only available when the diff has the full texts.
  List<ThemedToken> oldLine(int number) => _old[number] ?? const [];

  /// Tokens for line [number] of the new file. Lines outside the hunks are
  /// only available when the diff has the full texts.
  List<ThemedToken> newLine(int number) => _new[number] ?? const [];

  /// [line] as styled segments, ready to paint. With [words], the segments
  /// are split where the line's changed words start and end, and those are
  /// marked [DiffSegment.changed]. A line without tokens, such as an
  /// expanded line of a parsed patch, is one plain segment.
  List<DiffSegment> segmentsFor(DiffLine line, [WordChanges? words]) {
    final tokens = tokensFor(line);
    if (tokens.isEmpty) {
      return line.text.isEmpty ? const [] : [DiffSegment(line.text, _plain)];
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

// Retain grammar checkpoints and a bounded set of painted lines. Reaching a
// distant viewport tokenizes intervening lines without constructing their spans.
final class _DiffLines {
  _DiffLines(this.grammar, this.theme, {this.full, required this.hunks});
  final Grammar? grammar;
  SyntaxTheme theme;
  final List<String>? full;
  final List<List<(int, String)>> hunks;
  final Map<int, StateStack?> _states = {1: null};
  final Map<int, List<ThemedToken>> _cache = {};
  static final _plain = ScopeStack.root('text.plain');

  List<ThemedToken>? operator [](int? number) {
    if (number == null || number < 1) return null;
    final cached = _cache.remove(number);
    if (cached != null) {
      _cache[number] = cached;
      return cached;
    }
    final lines = full;
    String text;
    StateStack? state;
    if (lines != null) {
      if (number > lines.length) return null;
      var start = 1;
      for (final key in _states.keys) {
        if (key <= number && key > start) start = key;
      }
      state = _states[start];
      for (var n = start; n < number; n++) {
        state = grammar?.tokenizeLine(lines[n - 1], state).endState;
        if (n % 128 == 0) _states[n + 1] = state;
      }
      text = lines[number - 1];
    } else {
      List<(int, String)>? found;
      for (final hunk in hunks) {
        if (hunk.isNotEmpty &&
            hunk.first.$1 <= number &&
            hunk.last.$1 >= number) {
          found = hunk;
          break;
        }
      }
      if (found == null) return null;
      text = '';
      for (final (n, source) in found) {
        if (n == number) {
          text = source;
          break;
        }
        state = grammar?.tokenizeLine(source, state).endState;
      }
    }
    final result = grammar?.tokenizeLine(text, state);
    final tokens = result == null
        ? [
            ThemedToken(
              text,
              0,
              TokenStyle(foreground: theme.foreground),
              _plain,
            ),
          ]
        : [
            for (final token in result.tokens)
              ThemedToken(
                text.substring(token.start, token.end),
                token.start,
                theme.styleFor(token.scopes),
                token.scopes,
              ),
          ];
    if (lines != null && result != null) {
      // One moving checkpoint makes sequential access linear even between
      // persistent checkpoints. Bound these temporary states with the cache.
      _states[number + 1] = result.endState;
      _states.removeWhere(
        (key, _) => key != 1 && (key - 1) % 128 != 0 && key != number + 1,
      );
    }
    if (_cache.length >= 512) _cache.remove(_cache.keys.first);
    return _cache[number] = tokens;
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
    required SyntaxTheme theme,
    this.language,
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.capacity = 32,
  }) : _theme = theme;

  /// Provides the grammars.
  final Highlighter highlighter;

  /// Provides the colors.
  SyntaxTheme get theme => _theme;
  SyntaxTheme _theme;
  set theme(SyntaxTheme value) {
    if (identical(value, _theme)) return;
    _theme = value;
    for (final entry in _highlights.values) {
      entry.$2.setTheme(value);
    }
  }

  /// The language of every file, or `null` to guess from each path.
  final String? language;

  /// Inline comparison used by all consumers of this cache.
  final InlineDiffMode inlineDiffMode;

  /// Maximum retained file results.
  final int capacity;

  final Map<FileDiff, (Grammar?, HighlightedDiff)> _highlights = Map.identity();
  final Map<FileDiff, WordChanges> _words = Map.identity();

  /// Number of retained file presentations, bounded by capacity.
  int get cachedFileCount => _highlights.length;

  /// [file]'s highlighting.
  HighlightedDiff highlighted(FileDiff file) {
    final grammar = HighlightedDiff._grammarFor(file, highlighter, language);
    if (_highlights[file] case (
      final cached,
      final highlighted,
    ) when identical(cached, grammar)) {
      return highlighted;
    }
    final highlighted = HighlightedDiff.of(
      file,
      highlighter: highlighter,
      theme: theme,
      language: language,
    );
    if (capacity < 1) return highlighted;
    while (_highlights.length >= capacity) {
      final oldest = _highlights.keys.first;
      _highlights.remove(oldest);
      _words.remove(oldest);
    }
    _highlights[file] = (grammar, highlighted);
    return highlighted;
  }

  /// [file]'s changed words.
  WordChanges words(FileDiff file) {
    final cached = _words.remove(file);
    if (cached != null) {
      _words[file] = cached;
      return cached;
    }
    final result = WordChanges.of(file, mode: inlineDiffMode);
    if (capacity > 0) {
      if (_words.length >= capacity) _words.remove(_words.keys.first);
      _words[file] = result;
    }
    return result;
  }

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
