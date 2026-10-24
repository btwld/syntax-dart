import 'package:flutter/painting.dart';
import 'package:syntax_core/syntax.dart';

/// A monospace style that resolves on every platform.
const TextStyle defaultCodeTextStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: [
    'Menlo',
    'SF Mono',
    'Consolas',
    'Roboto Mono',
    'DejaVu Sans Mono',
    'Courier New',
  ],
  fontSize: 14,
  height: 1.5,
);

/// Flutter colors for a [SyntaxTheme]'s editor chrome.
extension SyntaxThemeColors on SyntaxTheme {
  /// The editor background.
  Color get backgroundColor => Color(background);

  /// The default text color.
  Color get foregroundColor => Color(foreground);

  /// An editor color from the theme's `colors` map, such as
  /// `editorLineNumber.foreground`.
  Color? editorColorOf(String key) {
    final value = editorColor(key);
    return value == null ? null : Color(value);
  }

  /// The line number color.
  Color get lineNumberColor => Color(lineNumberForeground);

  /// The selected text background.
  Color get selectionColor => Color(selectionBackground);

  /// The cursor color.
  Color get cursorColor => Color(cursorForeground);
}

/// Converts [TokenStyle]s to [TextStyle]s and caches the results. Create
/// one per theme and base style.
final class TokenTextStyles {
  /// Styles for [theme] on top of [base], which defaults to
  /// [defaultCodeTextStyle].
  TokenTextStyles(this.theme, {TextStyle? base})
    : base = (base ?? defaultCodeTextStyle).copyWith(
        color: Color(theme.foreground),
      );

  /// The theme token styles come from.
  final SyntaxTheme theme;

  /// The style every token style is applied on top of.
  final TextStyle base;

  final Map<TokenStyle, TextStyle> _cache = {};

  /// The text style for a token. It only sets what the token changes, so
  /// it inherits from [base] in a span tree.
  TextStyle operator [](TokenStyle style) => _cache.putIfAbsent(style, () {
    final decorations = [
      if (style.underline) TextDecoration.underline,
      if (style.strikethrough) TextDecoration.lineThrough,
    ];
    return TextStyle(
      color: Color(style.foreground),
      backgroundColor: style.background == null
          ? null
          : Color(style.background!),
      fontStyle: style.italic ? FontStyle.italic : null,
      fontWeight: style.bold ? FontWeight.bold : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
    );
  });
}

/// Builds a [TextSpan] tree for highlighted lines, one child per token and
/// a `\n` between lines.
TextSpan highlightedTextSpan(
  List<List<ThemedToken>> lines,
  TokenTextStyles styles,
) {
  final children = <InlineSpan>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) children.add(const TextSpan(text: '\n'));
    for (final token in lines[i]) {
      children.add(TextSpan(text: token.text, style: styles[token.style]));
    }
  }
  return TextSpan(style: styles.base, children: children);
}
