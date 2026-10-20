// The TextMate tokenizer, a port of vscode-textmate's `grammar.ts` and
// `tokenizeString.ts`, including injections.

import '../regex/engine.dart';
import 'matcher.dart';
import 'rules.dart';
import 'scope_stack.dart';

part 'state_stack.dart';

/// A run of text with the scopes that apply to it.
final class Token {
  /// A token from [start] to [end] with [scopes].
  const Token(this.start, this.end, this.scopes);

  /// Start offset in the line, in UTF-16 code units.
  final int start;

  /// End offset in the line, exclusive.
  final int end;

  /// The scopes that apply, innermost last.
  final ScopeStack scopes;

  @override
  String toString() => '[$start, $end) $scopes';
}

/// The tokens of one line, and the state to pass to the next line.
final class LineTokens {
  /// The [tokens] of a line and the [endState] after it.
  const LineTokens(this.tokens, this.endState);

  /// The line's tokens, covering it from start to end.
  final List<Token> tokens;

  /// Pass to `Grammar.tokenizeLine` for the next line.
  final StateStack endState;
}

/// Looks up grammars by scope name, for `include: "source.other"`.
typedef GrammarLookup = Map<String, Object?>? Function(String scopeName);

/// Scope names of grammars that inject into [scopeName] through their
/// `injectionSelector`, such as a SQL-in-template-strings grammar for
/// `source.js`.
typedef InjectionLookup = List<String> Function(String scopeName);

final class _Injection {
  _Injection(this.matcher, this.ruleId, this.priority);
  final ScopeMatcher matcher;
  final int ruleId;
  final int priority;
}

/// Splits [code] into lines on `\n`, dropping a `\r` before each break.
List<String> splitLines(String code) => [
  for (final line in code.split('\n'))
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
];

/// A compiled TextMate grammar.
///
/// Rules and scanners are compiled lazily on first use.
final class Grammar {
  /// Compiles [rawGrammar] for [engine]. [lookup] finds grammars it
  /// includes by scope name and [injections] the grammars injected into
  /// it. `Highlighter.grammar` sets these up; create a [Grammar] directly
  /// only to manage grammars yourself.
  Grammar(
    Map<String, Object?> rawGrammar, {
    required RegexEngine engine,
    GrammarLookup? lookup,
    InjectionLookup? injections,
    this.maxLineLength = 20000,
  }) : _engine = engine,
       _lookup = lookup,
       _injectionLookup = injections,
       _source = rawGrammar,
       scopeName = _scopeNameOf(rawGrammar) {
    _raw = _initGrammar(rawGrammar, null);
    _factory = RuleFactory(_RuleTable(this));
  }

  static String _scopeNameOf(Map<String, Object?> grammar) {
    final scopeName = grammar['scopeName'];
    if (scopeName is String) return scopeName;
    throw ArgumentError.value(
      grammar['name'] ?? grammar.keys.take(3).toList(),
      'rawGrammar',
      'A TextMate grammar needs a "scopeName" string',
    );
  }

  final RegexEngine _engine;
  final GrammarLookup? _lookup;
  final InjectionLookup? _injectionLookup;

  /// The grammar's root scope, for example `source.dart`.
  final String scopeName;

  /// Lines longer than this many UTF-16 code units are not tokenized. They
  /// become one token in the current scope. 0 means no limit. See
  /// [Highlighter.maxLineLength].
  final int maxLineLength;

  final Map<String, Object?> _source;
  late final Map<String, Object?> _raw;
  late final RuleFactory _factory;
  final List<Rule?> _rules = [null]; // rule ids start at 1
  final Map<String, Map<String, Object?>> _included = {};
  final Map<int, CompiledRule> _compiled = {};

  // Keyed by the end or while pattern after backreference substitution, so
  // every heredoc tag or fence adds an entry. Cleared past
  // [_maxResolvedScanners].
  final Map<(int, String), CompiledRule> _compiledWithEnd = {};
  final Map<(int, String?), CompiledRule> _compiledWhile = {};
  static const _maxResolvedScanners = 256;

  late final int _rootId = _factory.compiledRuleId(
    _asMap(_asMap(_raw['repository'])[r'$self']),
    _asMap(_raw['repository']),
  );

  /// Builds the repository with the synthetic `$self` and `$base` entries.
  static Map<String, Object?> _initGrammar(
    Map<String, Object?> grammar,
    Map<String, Object?>? base,
  ) {
    final self = <String, Object?>{
      'patterns': grammar['patterns'],
      'name': grammar['scopeName'],
    };
    return {
      ...grammar,
      'repository': {
        ..._asMap(grammar['repository']),
        r'$self': self,
        r'$base': base ?? self,
      },
    };
  }

  Rule _rule(int id) => _rules[id]!;

  Map<String, Object?>? _externalGrammar(
    String scopeName,
    Map<String, Object?>? repository,
  ) {
    final cached = _included[scopeName];
    if (cached != null) return cached;
    final raw =
        _lookup?.call(scopeName) ??
        (scopeName == this.scopeName ? _source : null);
    if (raw == null) return null;
    return _included[scopeName] = _initGrammar(
      raw,
      repository == null ? null : _asMap(repository[r'$base']),
    );
  }

  /// Injections from this grammar's `injections` map and from grammars
  /// that inject into it, sorted by priority.
  late final List<_Injection> _injections = () {
    final result = <_Injection>[];
    void collect(
      String selector,
      Map<String, Object?> rule,
      Map<String, Object?> repository,
    ) {
      final ruleId = _factory.compiledRuleId(rule, repository);
      for (final m in parseScopeSelector(selector)) {
        result.add(_Injection(m.matcher, ruleId, m.priority));
      }
    }

    final repository = _asMap(_raw['repository']);
    final own = _raw['injections'];
    if (own is Map) {
      for (final MapEntry(:key, :value) in _asMap(own).entries) {
        if (value is Map) collect(key, _asMap(value), repository);
      }
    }
    for (final scope in _injectionLookup?.call(scopeName) ?? const <String>[]) {
      final injector = _externalGrammar(scope, null);
      final selector = injector?['injectionSelector'];
      if (injector != null && selector is String) {
        collect(selector, injector, _asMap(injector['repository']));
      }
    }
    // A stable sort, like Array.prototype.sort in vscode-textmate.
    return _stableSort(result, (a, b) => a.priority - b.priority);
  }();

  static List<T> _stableSort<T>(List<T> list, int Function(T, T) compare) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1 - b.$1;
    });
    return [for (final (_, item) in indexed) item];
  }

  late final StateStack _initialState = () {
    final rootScopes = ScopeStack.root(
      _rule(_rootId).nameFor(null) ?? 'unknown',
    );
    return StateStack._(
      this,
      null,
      _rootId,
      -1,
      -1,
      false,
      null,
      rootScopes,
      rootScopes,
    );
  }();

  /// Tokenizes one [line], which must not contain a line break. Pass the
  /// previous line's [LineTokens.endState] as [state], or `null` for the
  /// first line of a document.
  ///
  /// Throws [ArgumentError] if [state] came from a different [Grammar].
  LineTokens tokenizeLine(String line, [StateStack? state]) {
    if (state != null && !identical(state._grammar, this)) {
      throw ArgumentError.value(
        state,
        'state',
        'Produced by a different Grammar. States are only valid for the '
            'grammar that returned them',
      );
    }
    final isFirstLine = state == null;
    final start = state ?? _initialState;
    if (maxLineLength > 0 && line.length > maxLineLength) {
      return LineTokens([
        Token(0, line.length, start._contentNameScopes),
      ], start);
    }
    final text = '$line\n';
    final tokens = _LineTokenBuilder();
    final end = _tokenizeString(text, isFirstLine, 0, start, tokens, true);
    return LineTokens(tokens.finish(line.length), end._reset());
  }

  /// Tokenizes a whole document, split with [splitLines].
  List<List<Token>> tokenize(String code) {
    final result = <List<Token>>[];
    StateStack? state;
    for (final line in splitLines(code)) {
      final lineTokens = tokenizeLine(line, state);
      result.add(lineTokens.tokens);
      state = lineTokens.endState;
    }
    return result;
  }

  CompiledRule _compile(int ruleId, String? endRule) {
    final rule = _rule(ruleId);
    if (rule is BeginEndRule && rule.endHasBackReferences && endRule != null) {
      if (_compiledWithEnd.length >= _maxResolvedScanners) {
        _compiledWithEnd.clear();
      }
      return _compiledWithEnd[(ruleId, endRule)] ??= _buildScanner(
        rule,
        endRule,
      );
    }
    return _compiled[ruleId] ??= _buildScanner(rule, null);
  }

  CompiledRule _buildScanner(Rule rule, String? endRule) {
    final sources = <String>[];
    final ids = <int>[];
    void add(String source, int id) {
      sources.add(source);
      ids.add(id);
    }

    List<int> patterns;
    switch (rule) {
      case BeginEndRule():
        patterns = rule.patterns;
        if (!rule.applyEndPatternLast) add(endRule ?? rule.end, endRuleId);
      case BeginWhileRule():
        patterns = rule.patterns;
      case IncludeOnlyRule():
        patterns = rule.patterns;
      case MatchRule() || CaptureRule():
        patterns = const [];
    }
    final visited = <int>{};
    for (final id in patterns) {
      _collectPatterns(id, add, visited);
    }
    if (rule is BeginEndRule && rule.applyEndPatternLast) {
      add(endRule ?? rule.end, endRuleId);
    }
    return CompiledRule(_engine.createScanner(sources), ids);
  }

  /// Flattens include-only rules into the regexes of the rules they hold.
  /// [visited] guards against include cycles.
  void _collectPatterns(
    int id,
    void Function(String, int) add,
    Set<int> visited,
  ) {
    final rule = _rule(id);
    switch (rule) {
      case MatchRule():
        add(rule.match, id);
      case BeginEndRule():
        add(rule.begin, id);
      case BeginWhileRule():
        add(rule.begin, id);
      case IncludeOnlyRule():
        if (!visited.add(id)) return;
        for (final child in rule.patterns) {
          _collectPatterns(child, add, visited);
        }
      case CaptureRule():
        break;
    }
  }

  CompiledRule _compileWhile(BeginWhileRule rule, String? whilePattern) {
    if (_compiledWhile.length >= _maxResolvedScanners) _compiledWhile.clear();
    return _compiledWhile[(rule.id, whilePattern)] ??= CompiledRule(
      _engine.createScanner([whilePattern ?? rule.whilePattern]),
      const [whileRuleId],
    );
  }

  StateStack _tokenizeString(
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    _LineTokenBuilder lineTokens,
    bool checkWhileConditions,
  ) {
    final lineLength = lineText.length;
    var anchorPosition = -1;

    if (checkWhileConditions) {
      final r = _checkWhileConditions(
        lineText,
        isFirstLine,
        linePos,
        stack,
        lineTokens,
      );
      stack = r.stack;
      linePos = r.linePos;
      isFirstLine = r.isFirstLine;
      anchorPosition = r.anchorPosition;
    }

    while (true) {
      final result = _matchRuleOrInjections(
        lineText,
        isFirstLine,
        linePos,
        stack,
        anchorPosition,
      );
      if (result == null) {
        lineTokens.produce(stack, lineLength);
        return stack;
      }

      final (match, matchedRuleId) = result;
      final hasAdvanced = match.end > linePos;

      if (matchedRuleId == endRuleId) {
        final poppedRule = _rule(stack._ruleId) as BeginEndRule;
        lineTokens.produce(stack, match.start);
        stack = stack._withContentNameScopes(stack._nameScopes);
        _handleCaptures(
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          poppedRule.endCaptures,
          match,
        );
        lineTokens.produce(stack, match.end);

        final popped = stack;
        stack = stack._parent!;
        anchorPosition = popped._anchorPos;

        if (!hasAdvanced && popped._enterPos == linePos) {
          // The grammar pushed and popped a rule without advancing.
          stack = popped;
          lineTokens.produce(stack, lineLength);
          return stack;
        }
      } else {
        final rule = _rule(matchedRuleId);
        lineTokens.produce(stack, match.start);
        final beforePush = stack;
        final nameScopes = stack._contentNameScopes.push(rule.nameFor(match));
        stack = stack._push(
          matchedRuleId,
          linePos,
          anchorPosition,
          match.end == lineLength,
          nameScopes,
          nameScopes,
        );

        switch (rule) {
          case BeginEndRule():
            _handleCaptures(
              lineText,
              isFirstLine,
              stack,
              lineTokens,
              rule.beginCaptures,
              match,
            );
            lineTokens.produce(stack, match.end);
            anchorPosition = match.end;
            stack = stack._withContentNameScopes(
              nameScopes.push(rule.contentNameFor(match)),
            );
            if (rule.endHasBackReferences) {
              stack = stack._withEndRule(rule.resolveEnd(match));
            }
            if (!hasAdvanced && beforePush._hasSameRuleAs(stack)) {
              // The grammar keeps pushing the same rule without advancing.
              stack = stack._pop()!;
              lineTokens.produce(stack, lineLength);
              return stack;
            }
          case BeginWhileRule():
            _handleCaptures(
              lineText,
              isFirstLine,
              stack,
              lineTokens,
              rule.beginCaptures,
              match,
            );
            lineTokens.produce(stack, match.end);
            anchorPosition = match.end;
            stack = stack._withContentNameScopes(
              nameScopes.push(rule.contentNameFor(match)),
            );
            if (rule.whileHasBackReferences) {
              stack = stack._withEndRule(rule.resolveWhile(match));
            }
            if (!hasAdvanced && beforePush._hasSameRuleAs(stack)) {
              stack = stack._pop()!;
              lineTokens.produce(stack, lineLength);
              return stack;
            }
          case MatchRule():
            _handleCaptures(
              lineText,
              isFirstLine,
              stack,
              lineTokens,
              rule.captures,
              match,
            );
            lineTokens.produce(stack, match.end);
            // A match rule pops immediately.
            stack = stack._pop()!;
            if (!hasAdvanced) {
              stack = stack._safePop();
              lineTokens.produce(stack, lineLength);
              return stack;
            }
          case IncludeOnlyRule() || CaptureRule():
            throw StateError('Rule $matchedRuleId cannot be matched directly');
        }
      }

      if (match.end > linePos) {
        linePos = match.end;
        isFirstLine = false;
      }
    }
  }

  (ScanMatch, int)? _matchRuleOrInjections(
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    int anchorPosition,
  ) {
    final allowG = linePos == anchorPosition;
    final compiled = _compile(stack._ruleId, stack._endRule);
    final match = compiled.scanner.findNextMatch(
      lineText,
      linePos,
      allowA: isFirstLine,
      allowG: allowG,
    );
    final ruleMatch = match == null
        ? null
        : (match, compiled.ruleIds[match.patternIndex]);
    if (_injections.isEmpty) return ruleMatch;

    // The injection with the leftmost match wins. Injections are sorted by
    // priority, so on a tie the earlier one is kept.
    ScanMatch? best;
    var bestRuleId = 0;
    var bestPriority = 0;
    final scopes = stack._contentNameScopes.scopes;
    for (final injection in _injections) {
      if (!injection.matcher(scopes)) continue;
      final injected = _compile(injection.ruleId, null);
      final m = injected.scanner.findNextMatch(
        lineText,
        linePos,
        allowA: isFirstLine,
        allowG: allowG,
      );
      if (m == null || (best != null && m.start >= best.start)) continue;
      best = m;
      bestRuleId = injected.ruleIds[m.patternIndex];
      bestPriority = injection.priority;
      if (m.start == linePos) break;
    }
    if (best == null) return ruleMatch;
    if (ruleMatch == null) return (best, bestRuleId);
    // An `L:` injection also wins a tie with the grammar's own rules.
    if (best.start < ruleMatch.$1.start ||
        bestPriority == -1 && best.start == ruleMatch.$1.start) {
      return (best, bestRuleId);
    }
    return ruleMatch;
  }

  ({StateStack stack, int linePos, int anchorPosition, bool isFirstLine})
  _checkWhileConditions(
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    _LineTokenBuilder lineTokens,
  ) {
    var anchorPosition = stack._beginRuleCapturedEOL ? 0 : -1;
    final whileRules = <(BeginWhileRule, StateStack)>[];
    for (StateStack? node = stack; node != null; node = node._parent) {
      final rule = _rule(node._ruleId);
      if (rule is BeginWhileRule) whileRules.add((rule, node));
    }
    for (final (rule, node) in whileRules.reversed) {
      final allowG = anchorPosition == linePos;
      final compiled = _compileWhile(rule, node._endRule);
      final match = compiled.scanner.findNextMatch(
        lineText,
        linePos,
        allowA: isFirstLine,
        allowG: allowG,
      );
      if (match == null) {
        stack = node._pop()!;
        break;
      }
      lineTokens.produce(node, match.start);
      _handleCaptures(
        lineText,
        isFirstLine,
        node,
        lineTokens,
        rule.whileCaptures,
        match,
      );
      lineTokens.produce(node, match.end);
      anchorPosition = match.end;
      if (match.end > linePos) {
        linePos = match.end;
        isFirstLine = false;
      }
    }
    return (
      stack: stack,
      linePos: linePos,
      anchorPosition: anchorPosition,
      isFirstLine: isFirstLine,
    );
  }

  void _handleCaptures(
    String lineText,
    bool isFirstLine,
    StateStack stack,
    _LineTokenBuilder lineTokens,
    List<CaptureRule?> captures,
    ScanMatch match,
  ) {
    if (captures.isEmpty) return;
    final count = captures.length < match.groupCount + 1
        ? captures.length
        : match.groupCount + 1;
    final localStack = <(ScopeStack, int)>[];
    final maxEnd = match.end;

    for (var i = 0; i < count; i++) {
      final captureRule = captures[i];
      if (captureRule == null) continue;
      final start = match.captureStart(i);
      final end = match.captureEnd(i);
      if (start < 0 || end <= start) continue; // empty or absent
      if (start > maxEnd) break; // captured inside a lookahead, past the match

      while (localStack.isNotEmpty && localStack.last.$2 <= start) {
        lineTokens.produceScopes(localStack.last.$1, localStack.last.$2);
        localStack.removeLast();
      }
      if (localStack.isNotEmpty) {
        lineTokens.produceScopes(localStack.last.$1, start);
      } else {
        lineTokens.produce(stack, start);
      }

      if (captureRule.retokenizeCapturedWithRuleId != 0) {
        // The capture has its own patterns: tokenize the captured text.
        final nameScopes = stack._contentNameScopes.push(
          captureRule.nameFor(match),
        );
        final contentScopes = nameScopes.push(
          captureRule.contentNameFor(match),
        );
        final nested = stack._push(
          captureRule.retokenizeCapturedWithRuleId,
          start,
          -1,
          false,
          nameScopes,
          contentScopes,
        );
        _tokenizeString(
          lineText.substring(0, end),
          isFirstLine && start == 0,
          start,
          nested,
          lineTokens,
          false,
        );
        continue;
      }

      final scopeName = captureRule.nameFor(match);
      if (scopeName != null) {
        final base = localStack.isNotEmpty
            ? localStack.last.$1
            : stack._contentNameScopes;
        localStack.add((base.push(scopeName), end));
      }
    }

    while (localStack.isNotEmpty) {
      lineTokens.produceScopes(localStack.last.$1, localStack.last.$2);
      localStack.removeLast();
    }
  }
}

final class _LineTokenBuilder {
  final List<Token> _tokens = [];
  int _lastEnd = 0;

  void produce(StateStack stack, int endIndex) =>
      produceScopes(stack._contentNameScopes, endIndex);

  void produceScopes(ScopeStack scopes, int endIndex) {
    if (_lastEnd >= endIndex) return;
    _tokens.add(Token(_lastEnd, endIndex, scopes));
    _lastEnd = endIndex;
  }

  /// Clips tokens to the line without its synthetic `\n` and drops empty
  /// ones.
  List<Token> finish(int lineLength) {
    final result = <Token>[];
    for (final token in _tokens) {
      if (token.start >= lineLength) break;
      final end = token.end > lineLength ? lineLength : token.end;
      if (end > token.start) result.add(Token(token.start, end, token.scopes));
    }
    return result;
  }
}

Map<String, Object?> _asMap(Object? value) => value is Map<String, Object?>
    ? value
    : value is Map
    ? value.cast<String, Object?>()
    : const {};

/// Gives the rule factory access to the grammar's rule table without making
/// it part of [Grammar]'s public API.
final class _RuleTable implements RuleRegistry {
  _RuleTable(this._grammar);

  final Grammar _grammar;

  @override
  int registerRule(Rule Function(int id) factory) {
    final rules = _grammar._rules;
    final id = rules.length;
    rules.add(null);
    rules[id] = factory(id);
    return id;
  }

  @override
  Rule? ruleOrNull(int id) {
    final rules = _grammar._rules;
    return id > 0 && id < rules.length ? rules[id] : null;
  }

  @override
  Map<String, Object?>? externalGrammar(
    String scopeName,
    Map<String, Object?>? repository,
  ) => _grammar._externalGrammar(scopeName, repository);
}
