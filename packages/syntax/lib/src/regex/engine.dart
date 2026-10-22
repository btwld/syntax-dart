import 'runtime_web.dart' if (dart.library.io) 'runtime_native.dart';
import 'onig_translator.dart';

/// A regex backend for the tokenizer.
///
/// Patterns are Oniguruma sources, exactly as they appear in a grammar. The
/// default [DartRegexEngine] translates them to Dart [RegExp]s. An engine
/// that runs Oniguruma directly can implement this interface instead.
abstract interface class RegexEngine {
  /// Compiles [patterns] into a scanner that returns the leftmost match
  /// across all of them.
  Scanner createScanner(List<String> patterns);
}

/// Finds the earliest match among a fixed list of patterns.
abstract interface class Scanner {
  /// Returns the leftmost match at or after [start] in [line], breaking ties
  /// by pattern order. Returns `null` if no pattern matches.
  ///
  /// [allowA] says whether `\A` may match (only on a document's first
  /// line). [allowG] says whether `\G` may match at [start]. Both follow
  /// vscode-textmate.
  ScanMatch? findNextMatch(
    String line,
    int start, {
    required bool allowA,
    required bool allowG,
  });
}

/// One scanner match. Offsets are UTF-16 code unit indices into the line.
/// A group that did not take part in the match reports `-1`.
abstract interface class ScanMatch {
  /// Which of the scanner's patterns matched.
  int get patternIndex;

  /// Where the match starts.
  int get start;

  /// Where the match ends, exclusive.
  int get end;

  /// Number of capture groups in the matched pattern, excluding group 0.
  int get groupCount;

  /// Where [group] starts, or `-1`.
  int captureStart(int group);

  /// Where [group] ends, or `-1`.
  int captureEnd(int group);

  /// Text of [group], or `null` if it did not take part in the match.
  String? captureText(int group);
}

/// Called for a pattern that the engine cannot compile. Such a pattern never
/// matches, and the rest of the grammar keeps working.
typedef UnsupportedPatternCallback =
    void Function(String pattern, Object error);

/// The default engine. It translates Oniguruma to ECMAScript and runs Dart's
/// built-in [RegExp], which is the browser's native engine on the web.
final class DartRegexEngine implements RegexEngine {
  /// An engine that reports patterns it can't run to
  /// [onUnsupportedPattern].
  DartRegexEngine({this.onUnsupportedPattern, this.combinePatterns = true});

  /// Called once for each pattern that can't be translated, with an
  /// [UnsupportedPatternException].
  final UnsupportedPatternCallback? onUnsupportedPattern;

  /// Search all of a scanner's patterns with one alternation regex instead
  /// of one regex each. Leftmost-first alternation gives the same winner
  /// as the per-pattern search, with far fewer regex calls. Dart 3.9 native
  /// runtimes use equivalent individual scans to avoid a RegExp JIT crash.
  final bool combinePatterns;

  /// Compiled patterns shared by every scanner, keyed by Oniguruma source.
  /// Patterns built from end backreferences are dynamic, so the cache is
  /// cleared once it grows past [_maxCachedPatterns].
  final Map<String, _CompiledPattern> _patterns = {};
  static const _maxCachedPatterns = 10000;

  @override
  Scanner createScanner(List<String> patterns) {
    final compiled = [for (final p in patterns) _compile(p)];
    final scanner = _DartScanner(compiled);
    final combinable = compiled.every((p) => p.translated?.combinable ?? true);
    return supportsCombinedRegex &&
            combinePatterns &&
            combinable &&
            compiled.length > 1
        ? _CombinedScanner(compiled, scanner)
        : scanner;
  }

  _CompiledPattern _compile(String source) {
    final cached = _patterns[source];
    if (cached != null) return cached;
    if (_patterns.length >= _maxCachedPatterns) _patterns.clear();
    TranslatedPattern? translated;
    try {
      translated = translateOnigPattern(source);
    } on UnsupportedPatternException catch (e) {
      onUnsupportedPattern?.call(source, e);
    }
    return _patterns[source] = _CompiledPattern(translated, this);
  }
}

// Variant bits: which anchors may match, and whether word classes need
// their Unicode meaning because the line is not pure ASCII.
const _allowABit = 1;
const _allowGBit = 2;
const _unicodeBit = 4;

final class _CompiledPattern {
  _CompiledPattern(this.translated, this.engine);

  final TranslatedPattern? translated;
  final DartRegexEngine engine;
  final Map<int, RegExp?> _search = {};
  final Map<int, RegExp?> _indexed = {};
  bool _reported = false;

  bool get hasG => translated?.hasG ?? false;

  /// Results only depend on the line, not the search start, when `\G` is
  /// disabled and there is no `\K`.
  bool cacheable({required bool allowG}) =>
      !(translated?.hasKeep ?? false) && (!hasG || !allowG);

  /// The number of code points before [start], when the regex for this
  /// search depends on it, otherwise -1.
  int _positionFor(String line, int start, int variant) {
    final t = translated!;
    final positionalG = t.hasG && !t.leadingG && variant & _allowGBit != 0;
    return positionalG || t.hasKeep ? _codePointCount(line, start) : -1;
  }

  /// The bits of the variant this pattern needs for a search. Bits that
  /// make no difference to this pattern are left out, so variants share
  /// compiled regexes.
  int variantKey({
    required bool allowA,
    required bool allowG,
    required bool unicode,
  }) {
    final t = translated;
    if (t == null) return 0;
    return (t.hasA && allowA ? _allowABit : 0) |
        (t.hasG && allowG ? _allowGBit : 0) |
        (t.usesWordClasses && unicode ? _unicodeBit : 0);
  }

  /// The match of this pattern anchored at [start], or `null`. Only used by
  /// [_CombinedScanner], so `\G` is disabled and there is no `\K`.
  _DartMatch? matchAt(String line, int start, int patternIndex, int variant) {
    if (translated == null) return null;
    const position = -1;
    final m = indexedMatch(line, start, variant, position);
    if (m == null) return null;
    return _DartMatch(this, patternIndex, line, m, variant, position, true);
  }

  _DartMatch? search(String line, int start, int patternIndex, int variant) {
    final t = translated;
    if (t == null) return null;
    final position = _positionFor(line, start, variant);
    if (t.leadingG) {
      if (variant & _allowGBit == 0) return null;
      final m = indexedMatch(line, start, variant, position);
      if (m == null) return null;
      return _DartMatch(this, patternIndex, line, m, variant, position, true);
    }
    final regex = _regex(variant, position, indexed: false);
    final m = regex?.allMatches(line, start).firstOrNull;
    if (m == null) return null;
    return _DartMatch(this, patternIndex, line, m, variant, position, false);
  }

  /// The match of the indexed variant anchored at [matchStart]. Anchored
  /// matches use it directly, so their capture offsets need no second run.
  RegExpMatch? indexedMatch(
    String line,
    int matchStart,
    int variant,
    int position,
  ) {
    final regex = _regex(variant, position, indexed: true);
    return regex?.matchAsPrefix(line, matchStart) as RegExpMatch?;
  }

  RegExp? _regex(int variant, int position, {required bool indexed}) {
    final t = translated!;
    // Without hidden groups both variants have the same source.
    final hidden = indexed && !t.indexedIsSearch;
    final cache = hidden ? _indexed : _search;
    final key = variant | (position + 1) << 3;
    // Position-specific variants accumulate on long lines.
    if (cache.length >= _maxVariants && !cache.containsKey(key)) cache.clear();
    return cache.putIfAbsent(key, () {
      final unicode = variant & _unicodeBit != 0;
      var src = hidden
          ? t.indexedSource(unicodeWords: unicode)
          : t.searchSource(unicodeWords: unicode);
      if (t.hasA) {
        src = src.replaceAll(
          aMarker,
          variant & _allowABit != 0 ? r'(?<![\s\S])' : neverMatch,
        );
      }
      if (t.hasG) {
        src = src.replaceAll(gMarker, switch ((
          variant & _allowGBit != 0,
          t.leadingG,
        )) {
          (false, _) => neverMatch,
          (true, true) => '',
          // Exactly `position` code points before the current index.
          (true, false) =>
            position == 0
                ? r'(?<![\s\S])'
                : '(?<![\\s\\S]{${position + 1}})(?<=[\\s\\S]{$position})',
        });
      }
      if (t.hasKeep) {
        // At least `position` code points before the start of the `\K`
        // prefix, so it does not begin before the search start.
        src = src.replaceAll(
          keepMarker,
          position <= 0 ? '' : '(?<=[\\s\\S]{$position})',
        );
      }
      try {
        return RegExp(
          src,
          multiLine: true,
          unicode: true,
          caseSensitive: !t.caseInsensitive,
        );
      } on FormatException catch (e) {
        if (!_reported) {
          _reported = true;
          engine.onUnsupportedPattern?.call(t.source, e);
        }
        return null;
      }
    });
  }

  static const _maxVariants = 64;

  static int _codePointCount(String s, int end) {
    var count = end;
    for (var i = 0; i < end - 1; i++) {
      final unit = s.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        final next = s.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          count--;
          i++;
        }
      }
    }
    return count;
  }
}

final class _DartMatch implements ScanMatch {
  _DartMatch(
    this._pattern,
    this.patternIndex,
    this._line,
    this._match,
    this._variant,
    this._position,
    this._indexed,
  );

  final _CompiledPattern _pattern;
  @override
  final int patternIndex;
  final String _line;
  final RegExpMatch _match;
  final int _variant;
  final int _position;

  /// Whether [_match] is a match of the indexed variant.
  final bool _indexed;

  @override
  int get start => _match.start;

  @override
  int get end => _match.end;

  @override
  int get groupCount => _pattern.translated!.groupCount;

  late final List<int> _offsets = _computeOffsets();

  /// Start and end offsets for groups 1..n. A match only gives group text,
  /// so this adds up the lengths of the groups that measure each start in
  /// a match of the indexed variant. A search match is re-run as one,
  /// anchored at the match start, unless both variants are the same.
  List<int> _computeOffsets() {
    final t = _pattern.translated!;
    final offsets = List<int>.filled(2 * (t.groupCount + 1), -1);
    offsets[0] = start;
    offsets[1] = end;
    if (t.groupCount == 0) return offsets;
    final m = _indexed || t.indexedIsSearch
        ? _match
        : _pattern.indexedMatch(_line, start, _variant, _position);
    // The indexed variant only adds capture groups, so it matches wherever
    // the search regex did.
    assert(m != null, 'indexed regex did not match: ${t.source}');
    if (m == null) return offsets;
    final lengths = List<int>.filled(m.groupCount + 1, -1);
    int length(int group) {
      final cached = lengths[group];
      if (cached >= 0) return cached;
      final text = m.group(group);
      assert(text != null, 'offset group $group did not match: ${t.source}');
      return lengths[group] = text?.length ?? 0;
    }

    for (var g = 1; g <= t.groupCount; g++) {
      final text = m.group(t.indexedTextGroup(g));
      final terms = t.offsetTerms(g);
      if (text == null || terms == null) continue;
      var offset = start;
      for (final term in terms) {
        offset += term > 0 ? length(term) : -length(-term);
      }
      offsets[2 * g] = offset;
      offsets[2 * g + 1] = offset + text.length;
    }
    return offsets;
  }

  @override
  int captureStart(int group) =>
      group == 0 ? start : (group <= groupCount ? _offsets[2 * group] : -1);

  @override
  int captureEnd(int group) =>
      group == 0 ? end : (group <= groupCount ? _offsets[2 * group + 1] : -1);

  @override
  String? captureText(int group) {
    if (group == 0) return _match.group(0);
    if (group > groupCount) return null;
    final t = _pattern.translated!;
    final emitted = _indexed ? t.indexedTextGroup(group) : t.textGroup(group);
    return emitted < 0 ? null : _match.group(emitted);
  }
}

final class _DartScanner implements Scanner {
  _DartScanner(this._patterns)
    : _cacheLine = List.filled(_patterns.length, null),
      _cacheFrom = List.filled(_patterns.length, 0),
      _cacheVariant = List.filled(_patterns.length, 0),
      _cacheResult = List.filled(_patterns.length, null);

  final List<_CompiledPattern> _patterns;

  // Per-pattern memo of the last search. A search from `from` that found
  // its leftmost match at `s` also answers any search from `from..s`.
  final List<String?> _cacheLine;
  final List<int> _cacheFrom;
  final List<int> _cacheVariant;
  final List<_DartMatch?> _cacheResult;

  String? _unicodeLine;
  bool _isUnicode = false;
  static final RegExp _asciiOnly = RegExp(r'^[\x00-\x7F]*$');

  @override
  ScanMatch? findNextMatch(
    String line,
    int start, {
    required bool allowA,
    required bool allowG,
  }) {
    if (!identical(line, _unicodeLine)) {
      _unicodeLine = line;
      _isUnicode = !_asciiOnly.hasMatch(line);
    }
    _DartMatch? best;
    for (var i = 0; i < _patterns.length; i++) {
      final pattern = _patterns[i];
      final variant = pattern.variantKey(
        allowA: allowA,
        allowG: allowG,
        unicode: _isUnicode,
      );
      _DartMatch? m;
      final cached = _cacheResult[i];
      if (pattern.cacheable(allowG: allowG) &&
          identical(_cacheLine[i], line) &&
          _cacheVariant[i] == variant &&
          _cacheFrom[i] <= start &&
          (cached == null || cached.start >= start)) {
        m = cached;
      } else {
        m = pattern.search(line, start, i, variant);
        _cacheLine[i] = line;
        _cacheFrom[i] = start;
        _cacheVariant[i] = variant;
        _cacheResult[i] = m;
      }
      if (m == null) continue;
      if (best == null || m.start < best.start) {
        best = m;
        if (m.start == start) break;
      }
    }
    return best;
  }
}

/// Searches all patterns with a single alternation regex.
///
/// Each pattern becomes one capture-wrapped alternative. ECMAScript tries
/// alternatives left to right at each position, so the first wrapper that
/// matched is the scanner's winner: the leftmost match, ties broken by
/// pattern order. The winner is then re-run alone, anchored, to get its
/// own groups.
///
/// Searches with `\G` enabled fall back to [_DartScanner], because the
/// position assertion would make the combined regex differ per offset.
final class _CombinedScanner implements Scanner {
  _CombinedScanner(this._patterns, this._fallback)
    : _anyA = _patterns.any((p) => p.translated?.hasA ?? false),
      _anyG = _patterns.any((p) => p.hasG),
      _anyWords = _patterns.any((p) => p.translated?.usesWordClasses ?? false);

  final List<_CompiledPattern> _patterns;
  final _DartScanner _fallback;
  final bool _anyA;
  final bool _anyG;
  final bool _anyWords;
  final Map<int, _Combined?> _combined = {};

  String? _unicodeLine;
  bool _isUnicode = false;

  @override
  ScanMatch? findNextMatch(
    String line,
    int start, {
    required bool allowA,
    required bool allowG,
  }) {
    if (allowG && _anyG) {
      return _fallback.findNextMatch(
        line,
        start,
        allowA: allowA,
        allowG: allowG,
      );
    }
    if (!identical(line, _unicodeLine)) {
      _unicodeLine = line;
      _isUnicode = !_DartScanner._asciiOnly.hasMatch(line);
    }
    // Expanding Unicode word classes across a large alternation can exceed
    // native RegExp compiler limits on older supported VMs. Individual
    // patterns preserve the same earliest-match precedence without that
    // compilation hazard. ASCII lines retain the combined fast path.
    if (_isUnicode) {
      return _fallback.findNextMatch(
        line,
        start,
        allowA: allowA,
        allowG: allowG,
      );
    }
    final key =
        (_anyA && allowA ? _allowABit : 0) |
        (_anyWords && _isUnicode ? _unicodeBit : 0);
    final combined = _combined.putIfAbsent(key, () => _build(key));
    if (combined == null) {
      return _fallback.findNextMatch(
        line,
        start,
        allowA: allowA,
        allowG: allowG,
      );
    }
    final m = combined.regex.allMatches(line, start).firstOrNull;
    if (m == null) return null;
    for (var i = 0; i < combined.wrappers.length; i++) {
      final wrapper = combined.wrappers[i];
      if (wrapper < 0 || m.group(wrapper) == null) continue;
      final pattern = _patterns[i];
      final variant = pattern.variantKey(
        allowA: allowA,
        allowG: false,
        unicode: _isUnicode,
      );
      return pattern.matchAt(line, m.start, i, variant);
    }
    return null;
  }

  _Combined? _build(int key) {
    final unicode = key & _unicodeBit != 0;
    final allowA = key & _allowABit != 0;
    final alternatives = <String>[];
    final wrappers = <int>[];
    var groups = 0;
    for (final pattern in _patterns) {
      final t = pattern.translated;
      if (t == null) {
        wrappers.add(-1);
        continue;
      }
      final wrapper = ++groups;
      final alt = t.combinedSource(unicodeWords: unicode, groupOffset: wrapper);
      groups += alt.groupCount;
      var src = alt.source;
      if (t.hasA) {
        src = src.replaceAll(aMarker, allowA ? r'(?<![\s\S])' : neverMatch);
      }
      if (t.hasG) src = src.replaceAll(gMarker, neverMatch);
      alternatives.add('($src)');
      wrappers.add(wrapper);
    }
    try {
      return _Combined(
        RegExp(alternatives.join('|'), multiLine: true, unicode: true),
        wrappers,
      );
    } on FormatException {
      // A pattern that fails alone also fails here. The per-pattern scanner
      // reports it and treats it as never matching.
      return null;
    }
  }
}

final class _Combined {
  _Combined(this.regex, this.wrappers);
  final RegExp regex;

  /// The wrapper group of each pattern, or -1 for a pattern that never
  /// matches.
  final List<int> wrappers;
}
