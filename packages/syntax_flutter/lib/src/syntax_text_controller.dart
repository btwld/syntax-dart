import 'package:flutter/widgets.dart';
import 'package:syntax/syntax.dart';

import 'styles.dart';

/// A [TextEditingController] that highlights its text as you type.
///
/// Edits are incremental: the text is kept in a [TokenizedDocument], which
/// re-tokenizes only the lines an edit affects, and spans are cached per
/// line, so typing in a large file restyles a few lines.
///
/// ```dart
/// final controller = SyntaxTextEditingController(
///   highlighter: highlighter,
///   language: 'dart',
///   theme: githubDarkTheme,
///   text: source,
/// );
/// TextField(
///   controller: controller,
///   maxLines: null,
///   style: defaultCodeTextStyle, // a monospace font
/// );
/// ```
///
/// Text takes the theme's foreground color, whatever the field's style
/// says. [language] must be registered on [highlighter], otherwise building
/// the text throws an [ArgumentError].
class SyntaxTextEditingController extends TextEditingController {
  /// A controller for [text] highlighted as [language] in [theme].
  SyntaxTextEditingController({
    super.text,
    required Highlighter highlighter,
    required String language,
    required SyntaxTheme theme,
    TextStyle? textStyle,
  }) : _highlighter = highlighter,
       _language = language,
       _theme = theme,
       _textStyle = textStyle;

  Highlighter _highlighter;
  String _language;
  SyntaxTheme _theme;
  TextStyle? _textStyle;
  TokenTextStyles? _styles;

  TokenizedDocument? _document;

  /// Spans per document line, with the styles they were built with.
  final Expando<(TokenTextStyles, List<InlineSpan>)> _spans = Expando();

  /// Provides the grammar. Setting it re-tokenizes the text.
  Highlighter get highlighter => _highlighter;
  set highlighter(Highlighter value) {
    if (identical(value, _highlighter)) return;
    _highlighter = value;
    notifyListeners();
  }

  /// The language name, alias or scope name. Setting it re-tokenizes the
  /// text.
  String get language => _language;
  set language(String value) {
    if (value == _language) return;
    _language = value;
    notifyListeners();
  }

  /// Colors for the text. Setting it restyles without re-tokenizing.
  SyntaxTheme get theme => _theme;
  set theme(SyntaxTheme value) {
    if (value == _theme) return;
    _theme = value;
    // Token scopes do not depend on the theme, so only the styles change.
    _styles = null;
    notifyListeners();
  }

  /// Merged on top of the style the text field passes in, so set only
  /// what should differ, such as a monospace font.
  TextStyle? get textStyle => _textStyle;
  set textStyle(TextStyle? value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _styles = null;
    notifyListeners();
  }

  /// Raw tokens for every line, kept up to date with [text].
  List<List<Token>> get tokens => [for (final line in _update()) line.tokens];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final lines = _update();
    final base = (style ?? defaultCodeTextStyle).merge(_textStyle);
    var styles = _styles;
    if (styles == null || styles.base != _withThemeColor(base)) {
      styles = _styles = TokenTextStyles(theme, base: base);
    }

    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final children = <InlineSpan>[];
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) {
        children.add(const TextSpan(text: '\n'));
        offset++;
      }
      final line = lines[i];
      final end = offset + line.raw.length;
      if (composing.isValid &&
          composing.start < end &&
          composing.end > offset) {
        _addComposingLine(children, line, offset, styles, composing);
      } else {
        children.addAll(_spansFor(line, styles));
      }
      offset = end;
    }
    return TextSpan(style: styles.base, children: children);
  }

  TextStyle _withThemeColor(TextStyle base) =>
      base.copyWith(color: Color(theme.foreground));

  /// Spans for [line], rebuilt only when [styles] changes.
  List<InlineSpan> _spansFor(DocumentLine line, TokenTextStyles styles) {
    if (_spans[line] case (
      final built,
      final spans,
    ) when identical(built, styles)) {
      return spans;
    }
    final spans = [
      for (final token in line.themed(theme))
        TextSpan(text: token.text, style: styles[token.style]),
      if (line.endsWithCr) const TextSpan(text: '\r'),
    ];
    _spans[line] = (styles, spans);
    return spans;
  }

  /// Builds a line that holds IME composing text, underlining that range.
  void _addComposingLine(
    List<InlineSpan> out,
    DocumentLine line,
    int lineStart,
    TokenTextStyles styles,
    TextRange composing,
  ) {
    for (final token in line.themed(theme)) {
      final style = styles[token.style];
      final text = token.text;
      final start = lineStart + token.offset;
      final a = (composing.start - start).clamp(0, text.length);
      final b = (composing.end - start).clamp(0, text.length);
      if (a > 0) out.add(TextSpan(text: text.substring(0, a), style: style));
      if (b > a) {
        out.add(
          TextSpan(
            text: text.substring(a, b),
            style: style.merge(
              const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        );
      }
      if (b < text.length) {
        out.add(TextSpan(text: text.substring(b), style: style));
      }
    }
    if (line.endsWithCr) out.add(const TextSpan(text: '\r'));
  }

  /// Brings the document up to date with [text] and returns its lines.
  List<DocumentLine> _update() {
    final grammar = _highlighter.grammar(_language);
    final document = _document ??= TokenizedDocument(grammar);
    document
      ..grammar = grammar
      ..update(text);
    return document.lines;
  }
}
