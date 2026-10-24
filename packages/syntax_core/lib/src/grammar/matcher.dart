// Internal: not exported from package:syntax.
// ignore_for_file: public_member_api_docs

// Scope selectors for injections, a port of vscode-textmate's `matcher.ts`.
//
// A selector such as `L:source.js -comment, text.html (meta.tag | string)`
// becomes one matcher per comma-separated alternative. `L:` raises the
// priority of an alternative and `R:` lowers it.

typedef ScopeMatcher = bool Function(List<String> scopes);

final class PrioritizedMatcher {
  const PrioritizedMatcher(this.matcher, this.priority);

  final ScopeMatcher matcher;

  /// -1 for `L:`, 1 for `R:`, otherwise 0. Lower wins.
  final int priority;
}

List<PrioritizedMatcher> parseScopeSelector(String selector) =>
    _SelectorParser(selector).parse();

/// Whether [scopes] contain every identifier in order, each matching a
/// scope exactly or as a dot-separated prefix.
bool _matchesName(List<String> identifiers, List<String> scopes) {
  if (scopes.length < identifiers.length) return false;
  var lastIndex = 0;
  return identifiers.every((identifier) {
    for (var i = lastIndex; i < scopes.length; i++) {
      if (_scopesMatch(scopes[i], identifier)) {
        lastIndex = i + 1;
        return true;
      }
    }
    return false;
  });
}

bool _scopesMatch(String scope, String identifier) {
  if (scope.isEmpty) return false;
  if (scope == identifier) return true;
  final len = identifier.length;
  return scope.length > len &&
      scope.startsWith(identifier) &&
      scope.codeUnitAt(len) == 0x2E;
}

final class _SelectorParser {
  _SelectorParser(String selector)
    : _tokens = _tokenPattern
          .allMatches(selector)
          .map((m) => m.group(0)!)
          .toList();

  static final RegExp _tokenPattern = RegExp(
    r'([LR]:|[\w.:][\w.:\-]*|[,|\-()])',
  );
  static final RegExp _identifier = RegExp(r'[\w.:]+');

  final List<String> _tokens;
  int _index = 0;
  String? get _token => _index < _tokens.length ? _tokens[_index] : null;
  void _next() => _index++;

  List<PrioritizedMatcher> parse() {
    final results = <PrioritizedMatcher>[];
    while (_token != null) {
      var priority = 0;
      final token = _token!;
      if (token.length == 2 && token[1] == ':') {
        priority = switch (token[0]) {
          'R' => 1,
          'L' => -1,
          _ => 0,
        };
        _next();
      }
      results.add(PrioritizedMatcher(_parseConjunction(), priority));
      if (_token != ',') break;
      _next();
    }
    return results;
  }

  bool _isIdentifier(String? token) =>
      token != null && _identifier.hasMatch(token);

  ScopeMatcher? _parseOperand() {
    if (_token == '-') {
      _next();
      final negated = _parseOperand();
      return (scopes) => negated != null && !negated(scopes);
    }
    if (_token == '(') {
      _next();
      final inner = _parseInnerExpression();
      if (_token == ')') _next();
      return inner;
    }
    if (_isIdentifier(_token)) {
      final identifiers = <String>[];
      do {
        identifiers.add(_token!);
        _next();
      } while (_isIdentifier(_token));
      return (scopes) => _matchesName(identifiers, scopes);
    }
    return null;
  }

  ScopeMatcher _parseConjunction() {
    final matchers = <ScopeMatcher>[];
    for (var m = _parseOperand(); m != null; m = _parseOperand()) {
      matchers.add(m);
    }
    return (scopes) => matchers.every((m) => m(scopes));
  }

  ScopeMatcher _parseInnerExpression() {
    final matchers = <ScopeMatcher>[];
    var matcher = _parseConjunction();
    while (true) {
      matchers.add(matcher);
      if (_token == '|' || _token == ',') {
        do {
          _next();
        } while (_token == '|' || _token == ',');
      } else {
        break;
      }
      matcher = _parseConjunction();
    }
    return (scopes) => matchers.any((m) => m(scopes));
  }
}
