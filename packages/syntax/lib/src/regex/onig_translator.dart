/// Translates Oniguruma (Ruby syntax) patterns, the dialect TextMate grammars
/// are written in, into ECMAScript patterns that Dart's [RegExp] understands.
///
/// Dart silently misreads several Oniguruma constructs (`\h`, `\A` and `\z`
/// parse as literal letters), so every pattern goes through a real parser
/// and is re-emitted, rather than patched with string replacements.
///
/// Emulated constructs:
/// - `\A` `\z` `\Z` `\G` `\h` `\H` `\R` `\N` `\O` `\X`, and `\K` at the
///   top level
/// - `^`, which unlike ECMAScript's does not match after a final newline
/// - Unicode `\w` `\b` `\d`, which ECMAScript defines over ASCII
/// - possessive quantifiers and atomic groups, via `(?=(…))\n`
/// - `(?i)` `(?x)` `(?m)` flag groups, including the Oniguruma rule that an
///   isolated `(?i)` spans the rest of the enclosing group
/// - POSIX brackets, nested classes and `&&` intersections
/// - `\x{…}`, octal escapes, and Oniguruma property names for `\p{…}`
/// - `\g<…>` subroutine calls, expanded to a fixed depth
///
/// Patterns that cannot be expressed throw [UnsupportedPatternException].
/// Examples are conditionals `(?(…))`, absent groups `(?~…)` and `\K` under
/// alternation. The scanner treats such a pattern as one that never matches.
///
/// Known gap: a backreference under `(?i)` is case-sensitive unless the
/// whole pattern is case-insensitive, because ECMAScript cannot scope the
/// flag.
library;

part 'onig_ast.dart';
part 'onig_emitter.dart';
part 'onig_parser.dart';
part 'unicode_properties.dart';

/// Emitted in place of `\G`. The scanner replaces it per search, because `\G`
/// can only match at the anchor position.
const String gMarker = '\uE000';

/// Emitted in place of `\A`, which may only match on the first line.
const String aMarker = '\uE001';

/// Emitted where the text before a `\K` begins. The scanner replaces it with
/// an assertion that this position is not before the search start, which
/// Oniguruma guarantees and a plain lookbehind does not.
const String keepMarker = '\uE004';

const String _backrefOpen = '\uE002';
const String _backrefClose = '\uE003';

/// Maximum depth for `\g<…>` recursion. Deeper calls never match.
const int _subroutineDepthLimit = 5;

/// An Oniguruma pattern that has no ECMAScript equivalent, such as one
/// using absent operators.
final class UnsupportedPatternException implements Exception {
  /// An exception for [pattern], explained by [reason].
  UnsupportedPatternException(this.pattern, this.reason);

  /// The Oniguruma pattern.
  final String pattern;

  /// Why it can't be translated.
  final String reason;

  @override
  String toString() => 'Unsupported Oniguruma pattern ($reason): $pattern';
}

/// An Oniguruma pattern translated to ECMAScript.
///
/// Capture groups keep their Oniguruma numbering at this API boundary. The
/// translated source may contain extra hidden groups, and [textGroup] and
/// [indexedTextGroup] map original group numbers to emitted ones.
final class TranslatedPattern {
  TranslatedPattern._(this._ast, this.source, this._ascii);

  final _Ast _ast;

  /// The Oniguruma source this was translated from.
  final String source;
  final _Emitted _ascii;

  /// Number of capture groups in the original pattern.
  int get groupCount => _ast.groupCount;

  /// Whether the whole pattern is case-insensitive, for example under a
  /// leading `(?i)`. Then the [RegExp] flag is used instead of expansion.
  bool get caseInsensitive => _ast.globalCi;

  /// Whether the pattern contains [aMarker].
  bool get hasA => _ast.hasA;

  /// Whether the pattern contains [gMarker].
  bool get hasG => _ast.hasG;

  /// Whether every top-level alternative starts with `\G` and `\G` appears
  /// nowhere else. Such a pattern only matches *at* the anchor, so it can be
  /// run with `matchAsPrefix` after stripping the marker.
  bool get leadingG => _ast.leadingG;

  /// Whether the pattern contains [keepMarker].
  bool get hasKeep => _ast.hasKeep;

  /// Whether the pattern can join a combined alternation regex. That regex
  /// has no case-insensitive flag and no per-search position, so patterns
  /// that need either are searched on their own.
  bool get combinable => !hasKeep && !(caseInsensitive && _ast.hasBackrefs);

  /// Whether the pattern uses `\w`, `\b`, `\d` or their negations.
  /// Oniguruma defines these over Unicode and ECMAScript over ASCII. They
  /// agree on ASCII text, so a Unicode variant is only needed for lines
  /// with other characters.
  bool get usesWordClasses => _ast.usesWords;

  late final _Emitted _unicode = usesWordClasses
      ? _Emitter(_ast, indexed: false, unicodeWords: true).run()
      : _ascii;
  late final _Emitted _asciiIndexed = _Emitter(_ast, indexed: true).run();
  late final _Emitted _unicodeIndexed = usesWordClasses
      ? _Emitter(_ast, indexed: true, unicodeWords: true).run()
      : _asciiIndexed;

  /// Source for one alternative of a combined scanner regex. Backreferences
  /// are shifted by [groupOffset], and case-insensitivity is expanded so it
  /// does not depend on the [RegExp] flag.
  ({String source, int groupCount}) combinedSource({
    required bool unicodeWords,
    required int groupOffset,
  }) {
    final e = _Emitter(
      _ast,
      indexed: false,
      unicodeWords: unicodeWords && usesWordClasses,
      groupOffset: groupOffset,
      expandCase: true,
    ).run();
    return (source: e.source, groupCount: e.groupCount);
  }

  /// ECMAScript source without the groups that measure capture offsets.
  /// Use it to find matches.
  String searchSource({bool unicodeWords = false}) =>
      (unicodeWords ? _unicode : _ascii).source;

  /// The emitted group that holds the text of original group [index].
  int textGroup(int index) => index == 0 ? 0 : _ascii.textGroups[index] ?? -1;

  /// ECMAScript source with hidden groups that measure where each original
  /// capture group starts. Run it anchored at a known match start, then
  /// use [offsetTerms]. Dart's `RegExpMatch` only gives group text, not
  /// offsets.
  String indexedSource({bool unicodeWords = false}) =>
      (unicodeWords ? _unicodeIndexed : _asciiIndexed).source;

  /// Whether [indexedSource] is [searchSource], because no group needs a
  /// hidden group to measure where it starts.
  late final bool indexedIsSearch = _asciiIndexed.source == _ascii.source;

  /// In [indexedSource], the group holding the text of original group [index].
  int indexedTextGroup(int index) =>
      index == 0 ? 0 : _asciiIndexed.textGroups[index] ?? -1;

  /// Where original group [index] starts in a match of [indexedSource]: the
  /// match start plus the length of each listed group, or minus it for a
  /// negated group number. Every listed group took part whenever [index]
  /// did. `null` for a group that never takes part, such as one in a
  /// negative lookaround.
  ///
  /// The cost is the length of those groups, which stay within the text
  /// the match examined, so it does not grow with the match position.
  List<int>? offsetTerms(int index) => _asciiIndexed.offsetTerms[index];
}

/// Translates [pattern]. Throws [UnsupportedPatternException] if the pattern
/// cannot be expressed as an ECMAScript regex.
TranslatedPattern translateOnigPattern(String pattern) {
  try {
    final ast = _Parser(pattern).parse();
    final ascii = _Emitter(ast, indexed: false).run();
    return TranslatedPattern._(ast, pattern, ascii);
  } on UnsupportedPatternException catch (e) {
    throw UnsupportedPatternException(pattern, e.reason);
  }
}
