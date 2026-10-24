// VS Code color themes, resolved the way vscode-textmate's `theme.ts` does.

import '../grammar/scope_stack.dart';

/// Font style flags. They can be combined, for example
/// `TokenFontStyle.bold | TokenFontStyle.italic`.
abstract final class TokenFontStyle {
  /// No styling.
  static const int none = 0;

  /// Italic text.
  static const int italic = 1;

  /// Bold text.
  static const int bold = 2;

  /// Underlined text.
  static const int underline = 4;

  /// Struck-through text.
  static const int strikethrough = 8;
}

/// The resolved look of a token. Colors are ARGB integers, as
/// `0xAARRGGBB`.
final class TokenStyle {
  /// A style with a [foreground] color and optional [background] and
  /// [fontStyle].
  const TokenStyle({
    required this.foreground,
    this.background,
    this.fontStyle = TokenFontStyle.none,
  });

  /// Text color.
  final int foreground;

  /// Background color. `null` means the editor background.
  final int? background;

  /// A combination of [TokenFontStyle] flags.
  final int fontStyle;

  /// Whether [fontStyle] includes [TokenFontStyle.italic].
  bool get italic => fontStyle & TokenFontStyle.italic != 0;

  /// Whether [fontStyle] includes [TokenFontStyle.bold].
  bool get bold => fontStyle & TokenFontStyle.bold != 0;

  /// Whether [fontStyle] includes [TokenFontStyle.underline].
  bool get underline => fontStyle & TokenFontStyle.underline != 0;

  /// Whether [fontStyle] includes [TokenFontStyle.strikethrough].
  bool get strikethrough => fontStyle & TokenFontStyle.strikethrough != 0;

  @override
  bool operator ==(Object other) =>
      other is TokenStyle &&
      other.foreground == foreground &&
      other.background == background &&
      other.fontStyle == fontStyle;

  @override
  int get hashCode => Object.hash(foreground, background, fontStyle);

  @override
  String toString() =>
      'TokenStyle(${colorToHex(foreground)}, bg: ${background == null ? '-' : colorToHex(background!)}, fontStyle: $fontStyle)';
}

/// Paints [foreground] over [background] and returns the opaque result,
/// like Flutter's `Color.alphaBlend`. Both are ARGB integers. For renderers
/// that can't blend, such as terminals.
int alphaBlend(int foreground, int background) {
  final alpha = (foreground >> 24) & 0xFF;
  if (alpha == 0xFF) return foreground;
  int channel(int shift) {
    final f = (foreground >> shift) & 0xFF;
    final b = (background >> shift) & 0xFF;
    return (f * alpha + b * (0xFF - alpha) + 0x7F) ~/ 0xFF;
  }

  return 0xFF000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
}

/// A VS Code color theme: the JSON of a `*-color-theme.json` file.
///
/// The constructor is `const`, so bundled themes cost nothing until they
/// are used. Parsing happens on first use and is cached per [json] map,
/// so [json] must not change after the theme is first used.
final class SyntaxTheme {
  /// A theme called [name] from its decoded [json].
  const SyntaxTheme({required this.name, required this.json});

  /// Parses a theme from decoded JSON. If [name] is omitted, it comes from
  /// the JSON's `name` field.
  factory SyntaxTheme.fromJson(Map<String, Object?> json, {String? name}) {
    final jsonName = json['name'];
    return SyntaxTheme(
      name: name ?? (jsonName is String ? jsonName : 'theme'),
      json: json,
    );
  }

  /// The theme's name, such as `github-dark`.
  final String name;

  /// The theme's decoded JSON.
  final Map<String, Object?> json;

  /// Two themes are equal when they wrap the same JSON object, so caches
  /// keyed on a theme survive rebuilding the wrapper.
  @override
  bool operator ==(Object other) =>
      other is SyntaxTheme && other.name == name && identical(other.json, json);

  @override
  int get hashCode => Object.hash(name, identityHashCode(json));

  static final Expando<_ParsedTheme> _parsedCache = Expando();
  _ParsedTheme get _parsed => _parsedCache[json] ??= _ParsedTheme(json);

  /// Whether this is a dark theme, from its `type` field or the background
  /// luminance.
  bool get isDark => _parsed.isDark;

  /// The default text color (`editor.foreground`).
  int get foreground => _parsed.foreground;

  /// The editor background color (`editor.background`).
  int get background => _parsed.background;

  /// An editor color from the theme's `colors` map, such as
  /// `editorLineNumber.foreground`. Returns `null` if absent or not a
  /// hex color.
  int? editorColor(String key) {
    final value = _asMap(json['colors'])[key];
    return value is String ? parseHexColor(value) : null;
  }

  /// Line number color (`editorLineNumber.foreground`), or [foreground] at
  /// 40% opacity.
  int get lineNumberForeground =>
      editorColor('editorLineNumber.foreground') ??
      (0x66 << 24 | foreground & 0xFFFFFF);

  /// Selected text background (`editor.selectionBackground`), or VS Code's
  /// default for a dark or light theme.
  int get selectionBackground =>
      editorColor('editor.selectionBackground') ??
      (isDark ? 0x66264F78 : 0x66ADD6FF);

  /// Cursor color (`editorCursor.foreground`), or [foreground].
  int get cursorForeground =>
      editorColor('editorCursor.foreground') ?? foreground;

  /// The style for a token with the given scopes.
  TokenStyle styleFor(ScopeStack scopes) => _parsed.styleFor(scopes);
}

const _notSet = -1;

final class _ParsedRule {
  _ParsedRule(
    this.scope,
    this.parentScopes,
    this.index,
    this.fontStyle,
    this.foreground,
    this.background,
  );
  final String scope;
  final List<String>? parentScopes;
  final int index;
  final int fontStyle;
  final int? foreground;
  final int? background;
}

final class _TrieRule {
  _TrieRule(
    this.scopeDepth,
    this.parentScopes,
    this.fontStyle,
    this.foreground,
    this.background,
  );

  int scopeDepth;
  final List<String>? parentScopes;
  int fontStyle;
  int? foreground;
  int? background;

  _TrieRule clone() =>
      _TrieRule(scopeDepth, parentScopes, fontStyle, foreground, background);

  void acceptOverwrite(int depth, int fontStyle, int? fg, int? bg) {
    if (scopeDepth <= depth) scopeDepth = depth;
    if (fontStyle != _notSet) this.fontStyle = fontStyle;
    if (fg != null) foreground = fg;
    if (bg != null) background = bg;
  }
}

/// One node per scope segment. Children inherit their parent's rules when
/// created, so a node holds the merged result of every less specific
/// selector.
final class _TrieNode {
  _TrieNode(this._mainRule, this._rulesWithParentScopes);

  final _TrieRule _mainRule;
  final List<_TrieRule> _rulesWithParentScopes;
  final Map<String, _TrieNode> _children = {};
  List<_TrieRule>? _sorted;

  List<_TrieRule> match(String scope) {
    _TrieNode node = this;
    var rest = scope;
    while (rest.isNotEmpty) {
      final dot = rest.indexOf('.');
      final head = dot < 0 ? rest : rest.substring(0, dot);
      final child = node._children[head];
      if (child == null) break;
      node = child;
      rest = dot < 0 ? '' : rest.substring(dot + 1);
    }
    return node._sorted ??= [...node._rulesWithParentScopes, node._mainRule]
      ..sort(_compareBySpecificity);
  }

  void insert(
    int depth,
    String scope,
    List<String>? parentScopes,
    int fontStyle,
    int? fg,
    int? bg,
  ) {
    if (scope.isEmpty) {
      _insertHere(depth, parentScopes, fontStyle, fg, bg);
      return;
    }
    final dot = scope.indexOf('.');
    final head = dot < 0 ? scope : scope.substring(0, dot);
    final tail = dot < 0 ? '' : scope.substring(dot + 1);
    final child = _children[head] ??= _TrieNode(_mainRule.clone(), [
      for (final r in _rulesWithParentScopes) r.clone(),
    ]);
    child.insert(depth + 1, tail, parentScopes, fontStyle, fg, bg);
  }

  void _insertHere(
    int depth,
    List<String>? parentScopes,
    int fontStyle,
    int? fg,
    int? bg,
  ) {
    if (parentScopes == null) {
      _mainRule.acceptOverwrite(depth, fontStyle, fg, bg);
      return;
    }
    for (final rule in _rulesWithParentScopes) {
      if (_compareLists(rule.parentScopes, parentScopes) == 0) {
        rule.acceptOverwrite(depth, fontStyle, fg, bg);
        return;
      }
    }
    _rulesWithParentScopes.add(
      _TrieRule(
        depth,
        parentScopes,
        fontStyle == _notSet ? _mainRule.fontStyle : fontStyle,
        fg ?? _mainRule.foreground,
        bg ?? _mainRule.background,
      ),
    );
  }

  static int _compareBySpecificity(_TrieRule a, _TrieRule b) {
    if (a.scopeDepth != b.scopeDepth) return b.scopeDepth - a.scopeDepth;
    final ap = a.parentScopes ?? const [];
    final bp = b.parentScopes ?? const [];
    var ai = 0;
    var bi = 0;
    while (true) {
      // The child combinator does not affect specificity.
      if (ai < ap.length && ap[ai] == '>') ai++;
      if (bi < bp.length && bp[bi] == '>') bi++;
      if (ai >= ap.length || bi >= bp.length) break;
      final diff = bp[bi].length - ap[ai].length;
      if (diff != 0) return diff;
      ai++;
      bi++;
    }
    return bp.length - ap.length;
  }
}

final class _ParsedTheme {
  _ParsedTheme(Map<String, Object?> json) {
    final type = json['type'];
    final colors = _asMap(json['colors']);
    final rawSettings = json['settings'] ?? json['tokenColors'];
    final settings = [
      for (final s in rawSettings is List ? rawSettings : const []) _asMap(s),
    ];

    // Editor colors, normalized as Shiki does.
    bool falsy(Object? v) => v == null || v == '';
    bool isGlobal(Map<String, Object?> s) =>
        falsy(s['scope']) && falsy(s['name']);
    final global = settings.where(isGlobal).firstOrNull;
    final globalSettings = _asMap(global?['settings']);
    var fg =
        _hex(globalSettings['foreground']) ?? _hex(colors['editor.foreground']);
    var bg =
        _hex(globalSettings['background']) ?? _hex(colors['editor.background']);
    final light =
        type == 'light' ||
        type != 'dark' && bg != null && _luminance(parseHexColor(bg)!) > 0.5;
    fg ??= light ? '#333333' : '#bbbbbb';
    bg ??= light ? '#fffffe' : '#1e1e1e';
    isDark = !light;
    if (settings.isEmpty ||
        settings.first['settings'] == null ||
        !falsy(settings.first['scope'])) {
      settings.insert(0, {
        'settings': {'foreground': fg, 'background': bg},
      });
    }

    final rules = _parseRules(settings)
      ..sort((a, b) {
        final byScope = a.scope.compareTo(b.scope);
        if (byScope != 0) return byScope;
        final byParents = _compareLists(a.parentScopes, b.parentScopes);
        if (byParents != 0) return byParents;
        return a.index - b.index;
      });

    var defaultFontStyle = TokenFontStyle.none;
    var defaultFg = 0xFF000000;
    var defaultBg = 0xFFFFFFFF;
    var i = 0;
    for (; i < rules.length && rules[i].scope.isEmpty; i++) {
      final r = rules[i];
      if (r.fontStyle != _notSet) defaultFontStyle = r.fontStyle;
      if (r.foreground != null) defaultFg = r.foreground!;
      if (r.background != null) defaultBg = r.background!;
    }
    foreground = defaultFg;
    background = defaultBg;
    // Tokens draw on the editor background, so a token without its own
    // background reports `null` rather than the default.
    _rootStyle = TokenStyle(foreground: defaultFg, fontStyle: defaultFontStyle);

    _root = _TrieNode(_TrieRule(0, null, _notSet, null, null), []);
    for (; i < rules.length; i++) {
      final r = rules[i];
      _root.insert(
        0,
        r.scope,
        r.parentScopes,
        r.fontStyle,
        r.foreground,
        r.background,
      );
    }
  }

  late final bool isDark;
  late final int foreground;
  late final int background;
  late final TokenStyle _rootStyle;
  late final _TrieNode _root;
  final Expando<TokenStyle> _styles = Expando();

  TokenStyle styleFor(ScopeStack scopes) {
    final cached = _styles[scopes];
    if (cached != null) return cached;
    final parent = scopes.parent;
    final base = parent == null ? _rootStyle : styleFor(parent);
    final rule = _match(scopes);
    final style = rule == null
        ? base
        : TokenStyle(
            foreground: rule.foreground ?? base.foreground,
            background: rule.background ?? base.background,
            fontStyle: rule.fontStyle == _notSet
                ? base.fontStyle
                : rule.fontStyle,
          );
    return _styles[scopes] = style;
  }

  _TrieRule? _match(ScopeStack scopes) {
    for (final rule in _root.match(scopes.scope)) {
      if (_matchesParentScopes(scopes.parent, rule.parentScopes)) return rule;
    }
    return null;
  }

  static bool _matchesParentScopes(ScopeStack? path, List<String>? parents) {
    if (parents == null || parents.isEmpty) return true;
    for (var index = 0; index < parents.length; index++) {
      var pattern = parents[index];
      var mustMatch = false;
      if (pattern == '>') {
        if (index == parents.length - 1) return false;
        pattern = parents[++index];
        mustMatch = true;
      }
      while (path != null) {
        if (_matchesScope(path.scope, pattern)) break;
        if (mustMatch) return false;
        path = path.parent;
      }
      if (path == null) return false;
      path = path.parent;
    }
    return true;
  }

  static bool _matchesScope(String scope, String pattern) =>
      scope == pattern ||
      scope.startsWith(pattern) && scope.codeUnitAt(pattern.length) == 0x2E;

  static List<_ParsedRule> _parseRules(List<Map<String, Object?>> settings) {
    final result = <_ParsedRule>[];
    for (var i = 0; i < settings.length; i++) {
      final entry = settings[i];
      final style = _asMap(entry['settings']);
      if (entry['settings'] == null) continue;
      final rawScope = entry['scope'];
      final List<String> scopes;
      if (rawScope is String) {
        scopes = rawScope
            .replaceAll(RegExp(r'^,+'), '')
            .replaceAll(RegExp(r',+$'), '')
            .split(',');
      } else if (rawScope is List) {
        scopes = [for (final s in rawScope) '$s'];
      } else {
        scopes = const [''];
      }

      var fontStyle = _notSet;
      final rawFontStyle = style['fontStyle'];
      if (rawFontStyle is String) {
        fontStyle = TokenFontStyle.none;
        for (final segment in rawFontStyle.split(' ')) {
          fontStyle |= switch (segment) {
            'italic' => TokenFontStyle.italic,
            'bold' => TokenFontStyle.bold,
            'underline' => TokenFontStyle.underline,
            'strikethrough' => TokenFontStyle.strikethrough,
            _ => 0,
          };
        }
      }
      final fg = parseHexColor(_hex(style['foreground']));
      final bg = parseHexColor(_hex(style['background']));

      for (final scope in scopes) {
        final segments = scope.trim().split(' ');
        final parents = segments.length > 1
            ? segments.sublist(0, segments.length - 1).reversed.toList()
            : null;
        result.add(_ParsedRule(segments.last, parents, i, fontStyle, fg, bg));
      }
    }
    return result;
  }

  static String? _hex(Object? value) =>
      value is String && _hexColor.hasMatch(value) ? value : null;

  static double _luminance(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  }
}

final RegExp _hexColor = RegExp(
  r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
);

/// Parses `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa` to ARGB. Returns `null`
/// for anything else.
int? parseHexColor(String? hex) {
  if (hex == null || !_hexColor.hasMatch(hex)) return null;
  var digits = hex.substring(1);
  if (digits.length <= 4) {
    digits = digits.split('').map((d) => '$d$d').join();
  }
  final rgb = int.parse(digits.substring(0, 6), radix: 16);
  final alpha = digits.length == 8
      ? int.parse(digits.substring(6), radix: 16)
      : 0xFF;
  return alpha << 24 | rgb;
}

/// Formats an ARGB color as `#rrggbb`, or `#rrggbbaa` if not opaque.
String colorToHex(int argb) {
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = (argb >> 24) & 0xFF;
  return alpha == 0xFF
      ? '#$rgb'
      : '#$rgb${alpha.toRadixString(16).padLeft(2, '0')}';
}

int _compareLists(List<String>? a, List<String>? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a.length != b.length) return a.length - b.length;
  for (var i = 0; i < a.length; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

Map<String, Object?> _asMap(Object? value) => value is Map<String, Object?>
    ? value
    : value is Map
    ? value.cast<String, Object?>()
    : const {};
