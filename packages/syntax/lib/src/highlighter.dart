import 'document.dart';
import 'grammar/grammar.dart';
import 'grammar/scope_stack.dart';
import 'regex/engine.dart';
import 'theme/theme.dart';

/// A language a [Highlighter] can tokenize: a TextMate grammar plus its
/// name and aliases.
///
/// The constructor is `const`, so bundled languages cost nothing until
/// they are used.
final class Language {
  /// A language from a parsed grammar. See also [Language.fromJson].
  const Language({
    required this.name,
    required this.scopeName,
    required this.grammar,
    this.displayName,
    this.aliases = const [],
    this.injectTo = const [],
  });

  /// Creates a language from a decoded `*.tmLanguage.json`.
  ///
  /// Throws [ArgumentError] if the grammar has no `scopeName`.
  factory Language.fromJson(
    Map<String, Object?> grammar, {
    required String name,
    List<String> aliases = const [],
    List<String> injectTo = const [],
  }) {
    final scopeName = grammar['scopeName'];
    if (scopeName is! String) {
      throw ArgumentError.value(
        grammar['name'] ?? grammar.keys.take(3).toList(),
        'grammar',
        'The grammar for "$name" has no "scopeName" string',
      );
    }
    return Language(
      name: name,
      scopeName: scopeName,
      grammar: grammar,
      aliases: aliases,
      injectTo: injectTo,
    );
  }

  /// Identifier used to select the language, for example `dart`.
  final String name;

  /// The grammar's root scope, for example `source.dart`.
  final String scopeName;

  /// A name for people, such as `Shell` for `shellscript`.
  final String? displayName;

  /// Other names that select the language, such as `sh` and `bash`.
  /// [Highlighter.languageForPath] also matches file extensions
  /// against them.
  final List<String> aliases;

  /// Scope names this grammar injects into through its
  /// `injectionSelector`, for example `['source.js']`.
  final List<String> injectTo;

  /// The raw TextMate grammar.
  final Map<String, Object?> grammar;
}

/// A token with its text and resolved style.
final class ThemedToken {
  /// A token of [text] at [offset] painted with [style].
  const ThemedToken(this.text, this.offset, this.style, this.scopes);

  /// The token's text.
  final String text;

  /// Offset of [text] in its line, in UTF-16 code units.
  final int offset;

  /// How to paint [text].
  final TokenStyle style;

  /// Scopes of the first raw token merged into this one.
  final ScopeStack scopes;

  @override
  String toString() => '${colorToHex(style.foreground)} "$text"';
}

/// Applies [theme] to one line's raw [tokens], merging adjacent tokens with
/// the same style. [tokens] must come from tokenizing [line].
List<ThemedToken> themeTokens(
  String line,
  List<Token> tokens,
  SyntaxTheme theme,
) {
  final result = <ThemedToken>[];
  for (final token in tokens) {
    final style = theme.styleFor(token.scopes);
    final text = line.substring(token.start, token.end);
    if (result.isNotEmpty && result.last.style == style) {
      final last = result.removeLast();
      result.add(
        ThemedToken(last.text + text, last.offset, style, last.scopes),
      );
    } else {
      result.add(ThemedToken(text, token.start, style, token.scopes));
    }
  }
  return result;
}

/// Tokenizes and themes code with TextMate grammars.
///
/// ```dart
/// final highlighter = Highlighter(languages: [dartLanguage]);
/// final lines = highlighter.highlight(code,
///     language: 'dart', theme: githubDarkTheme);
/// ```
///
/// Grammars are compiled lazily and cached. Reuse one [Highlighter]
/// instead of creating one per call.
final class Highlighter {
  /// A highlighter for [languages], using [engine] or [DartRegexEngine].
  ///
  /// A highlighter and its grammars belong to the isolate that created
  /// them. To highlight in another isolate, create a highlighter there.
  Highlighter({
    Iterable<Language> languages = const [],
    RegexEngine? engine,
    this.maxLineLength = 20000,
  }) : engine = engine ?? DartRegexEngine() {
    languages.forEach(addLanguage);
  }

  /// The regex engine grammars are compiled for.
  final RegexEngine engine;

  /// Lines longer than this many UTF-16 code units are not tokenized, as
  /// in VS Code, which uses the same default. Each becomes one token in the
  /// current scope. Some grammars have lookaheads that scan to the end of
  /// the line, so on minified code their time grows faster than line
  /// length and a bundle on one line can take seconds. 0 means no limit.
  final int maxLineLength;

  /// Changes when registered grammar definitions or dependencies change.
  int get revision => _revision;
  int _revision = 0;
  final Map<String, Language> _byName = {};
  final Map<String, Language> _byScope = {};
  final Map<String, _CompiledGrammar> _grammars = {};

  /// Registered language names, without aliases.
  List<String> get languages => [for (final l in _byScope.values) l.name];

  /// Registers [language], replacing any language with the same scope name.
  ///
  /// Compiled grammars that this language affects are rebuilt on next use:
  /// one it replaces, one that includes or embeds it, or one it injects
  /// into. A [StateStack] from such a grammar is no longer accepted.
  void addLanguage(Language language) {
    _revision++;
    final replaced = _byScope[language.scopeName];
    if (replaced != null) {
      _byName.removeWhere((_, l) => identical(l, replaced));
    }
    _byName[language.name] = language;
    for (final alias in language.aliases) {
      // File extensions and secondary aliases must not shadow canonical IDs.
      if (_byName[alias]?.name != alias) _byName[alias] = language;
    }
    _byScope[language.scopeName] = language;
    _grammars.removeWhere((_, g) => g.isAffectedBy(language));
  }

  /// Looks up a language by name, alias or scope name.
  Language? language(String nameOrScope) =>
      _byName[nameOrScope] ?? _byScope[nameOrScope];

  /// Guesses the language of a file from its extension or name, using
  /// language names and aliases. `lib/main.dart`, `pubspec.yaml`,
  /// `deploy.sh`, `README.md` and `Dockerfile` all resolve with the bundled
  /// languages. Both `/` and `\` separate directories.
  /// Overrides exact basenames or extensions without changing grammar aliases.
  final Map<String, String> _pathLanguages = {};

  /// Registers an exact basename or an extension (with a leading dot).
  void setLanguageForPath(String nameOrExtension, String language) {
    _pathLanguages[nameOrExtension.toLowerCase()] = language;
    _revision++;
  }

  /// Removes every custom filename and extension mapping.
  void clearPathLanguages() {
    _pathLanguages.clear();
    _revision++;
  }

  /// Detects a registered language using filename overrides, names and extensions.
  Language? languageForPath(String path) {
    final name = path.split(_pathSeparator).last.toLowerCase();
    if (name.isEmpty) return null;
    final exact = _pathLanguages[name];
    if (exact != null) return language(exact);
    for (
      var dot = name.indexOf('.');
      dot >= 0;
      dot = name.indexOf('.', dot + 1)
    ) {
      final override = _pathLanguages[name.substring(dot)];
      if (override != null) return language(override);
    }
    final exactLanguage = _byName[name];
    if (exactLanguage != null) return exactLanguage;
    for (
      var dot = name.indexOf('.', 1);
      dot >= 0;
      dot = name.indexOf('.', dot + 1)
    ) {
      final match = _byName[name.substring(dot + 1)];
      if (match != null) return match;
    }
    return null;
  }

  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  /// The compiled grammar for [language]. Throws [ArgumentError] if the
  /// language is not registered.
  Grammar grammar(String language) {
    final lang = this.language(language);
    if (lang == null) {
      throw ArgumentError.value(
        language,
        'language',
        'Unknown language. Registered: ${languages.join(', ')}',
      );
    }
    return (_grammars[lang.scopeName] ??= _compile(lang)).grammar;
  }

  _CompiledGrammar _compile(Language language) {
    final compiled = _CompiledGrammar(language.scopeName);
    compiled.grammar = Grammar(
      language.grammar,
      engine: engine,
      lookup: (scope) {
        compiled.lookedUp.add(scope);
        return _byScope[scope]?.grammar;
      },
      injections: (scope) {
        compiled.injectionsLookedUp = true;
        return _injectionsFor(scope);
      },
      maxLineLength: maxLineLength,
    );
    return compiled;
  }

  /// Grammars that inject into [scopeName]. Like Shiki, an `injectTo` of
  /// `source.ts` also covers `source.ts.tags`.
  List<String> _injectionsFor(String scopeName) {
    final parts = scopeName.split('.');
    return [
      for (var i = 1; i <= parts.length; i++)
        for (final language in _byScope.values)
          if (language.injectTo.contains(parts.take(i).join('.')))
            language.scopeName,
    ];
  }

  /// Raw tokens per line, without theme information.
  List<List<Token>> tokenize(String code, {required String language}) =>
      grammar(language).tokenize(code);

  /// Styled tokens per line. Adjacent tokens with the same style are
  /// merged.
  List<List<ThemedToken>> highlight(
    String code, {
    required String language,
    required SyntaxTheme theme,
  }) {
    final grammar = this.grammar(language);
    final result = <List<ThemedToken>>[];
    StateStack? state;
    for (final line in splitLines(code)) {
      final tokens = grammar.tokenizeLine(line, state);
      result.add(themeTokens(line, tokens.tokens, theme));
      state = tokens.endState;
    }
    return result;
  }

  /// Styled ranges over the whole of [code], as UTF-16 offsets into it:
  /// the shape renderers that style one string at a time want. To
  /// re-highlight as the code changes, keep a [TokenizedDocument] instead.
  List<StyledRange> highlightRanges(
    String code, {
    required String language,
    required SyntaxTheme theme,
  }) => (TokenizedDocument(grammar(language))..update(code)).ranges(theme);
}

/// A compiled grammar and the scopes it asked the highlighter about, so a
/// later [Highlighter.addLanguage] can tell whether it went stale.
final class _CompiledGrammar {
  _CompiledGrammar(this.scopeName);

  final String scopeName;
  late final Grammar grammar;
  final Set<String> lookedUp = {};
  bool injectionsLookedUp = false;

  bool isAffectedBy(Language language) {
    if (language.scopeName == scopeName) return true;
    if (lookedUp.contains(language.scopeName)) return true;
    return injectionsLookedUp &&
        language.injectTo.any(
          (target) => scopeName == target || scopeName.startsWith('$target.'),
        );
  }
}
