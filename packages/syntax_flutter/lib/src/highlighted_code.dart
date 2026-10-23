import 'package:flutter/material.dart';
import 'package:syntax/syntax.dart';

import 'highlighter_scope.dart';
import 'styles.dart';

/// Read-only, syntax-highlighted code.
///
/// Highlights [code] again only when it, the [language]'s grammar, [theme]
/// or [textStyle] change, and paints the theme's background. When [code]
/// changes, only the lines that changed are tokenized again. Long lines
/// scroll horizontally unless [softWrap] is set. A [language] the
/// highlighter doesn't know shows the code unhighlighted. Code reads left
/// to right even in a right-to-left app.
///
/// ```dart
/// HighlightedCode(
///   "void main() => print('hi');",
///   language: 'dart',
///   theme: githubDarkTheme,
/// )
/// ```
class HighlightedCode extends StatefulWidget {
  /// Shows [code] highlighted as [language] in [theme].
  const HighlightedCode(
    this.code, {
    super.key,
    required this.language,
    required this.theme,
    this.highlighter,
    this.textStyle,
    this.padding = const EdgeInsets.all(16),
    this.lineNumbers = false,
    this.selectable = true,
    this.softWrap = false,
    this.borderRadius,
  });

  /// The code to show.
  final String code;

  /// Language name, alias or scope name, as registered on the highlighter.
  final String language;

  /// Colors for the code and the background.
  final SyntaxTheme theme;

  /// Defaults to the nearest [HighlighterScope].
  final Highlighter? highlighter;

  /// Base text style. Defaults to [defaultCodeTextStyle]. Its color is
  /// replaced by the theme's foreground.
  final TextStyle? textStyle;

  /// Space between the background's edge and the code.
  final EdgeInsetsGeometry padding;

  /// Shows a gutter with line numbers, in the theme's line-number color.
  final bool lineNumbers;

  /// Allows the text to be selected and copied.
  final bool selectable;

  /// Wraps long lines instead of scrolling horizontally. Line numbers are
  /// not shown when wrapping, because wrapped lines would misalign them.
  final bool softWrap;

  /// Rounds the background's corners.
  final BorderRadiusGeometry? borderRadius;

  @override
  State<HighlightedCode> createState() => _HighlightedCodeState();
}

class _HighlightedCodeState extends State<HighlightedCode> {
  TextSpan? _span;
  String _lineNumbers = '';
  Object? _key;
  TokenizedDocument? _document;

  TextSpan _spanFor(Highlighter highlighter) {
    // The grammar, not the highlighter, decides the tokens: registering a
    // language can replace it.
    final known = highlighter.language(widget.language) != null;
    final grammar = known ? highlighter.grammar(widget.language) : null;
    final key = (widget.code, grammar, widget.theme, widget.textStyle);
    if (key == _key && _span != null) return _span!;
    _key = key;
    final styles = TokenTextStyles(widget.theme, base: widget.textStyle);
    final lineCount = '\n'.allMatches(widget.code).length + 1;
    _lineNumbers = [for (var i = 1; i <= lineCount; i++) '$i'].join('\n');
    if (grammar == null) {
      return _span = TextSpan(text: widget.code, style: styles.base);
    }
    final document = (_document ??= TokenizedDocument(grammar))
      ..grammar = grammar
      ..update(widget.code);
    return _span = highlightedTextSpan([
      for (final line in document.lines) line.themed(widget.theme),
    ], styles);
  }

  @override
  Widget build(BuildContext context) {
    final highlighter = widget.highlighter ?? HighlighterScope.of(context);
    final span = _spanFor(highlighter);
    final theme = widget.theme;

    Widget code = Text.rich(span, softWrap: widget.softWrap);
    if (!widget.softWrap) {
      code = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: code,
      );
    }
    if (widget.lineNumbers && !widget.softWrap) {
      code = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numbers are neither copied nor read out with the code.
          SelectionContainer.disabled(
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  _lineNumbers,
                  textAlign: TextAlign.right,
                  style: span.style!.copyWith(color: theme.lineNumberColor),
                ),
              ),
            ),
          ),
          Expanded(child: code),
        ],
      );
    }
    // Above the scroll view, so a drag selection can scroll it.
    if (widget.selectable) code = SelectionArea(child: code);

    return DefaultSelectionStyle(
      selectionColor: theme.selectionColor,
      cursorColor: theme.cursorColor,
      child: Container(
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          borderRadius: widget.borderRadius,
        ),
        padding: widget.padding,
        // Code reads left to right whatever the app's direction.
        child: Directionality(textDirection: TextDirection.ltr, child: code),
      ),
    );
  }
}
