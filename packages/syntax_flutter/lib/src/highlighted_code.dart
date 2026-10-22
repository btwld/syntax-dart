import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ViewportOffset;
import 'package:syntax/syntax.dart';

import 'code_rows.dart';
import 'highlighter_scope.dart';
import 'slices.dart';
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
/// Every line has the height of the base style's line. Given a bounded
/// height, code taller than it scrolls, and long code lays out only the
/// lines on screen. Inside another scroll view, where the height is
/// unbounded, every line is laid out; give a large file a height, for
/// example with [Expanded] or [SizedBox]. Code longer than 200 lines can't
/// report intrinsic sizes, so it can't sit inside [IntrinsicHeight] or an
/// [AlertDialog]'s content.
///
/// A large file is tokenized a slice at a time between frames, top first.
/// Lines show plain until their colors are ready.
///
/// Copying a selection copies the lines between its ends, including lines
/// scrolled out of view.
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

/// Code up to this many lines builds every line, without a
/// [LayoutBuilder], so it keeps intrinsic sizes.
const _buildAllUpTo = 200;

class _HighlightedCodeState extends State<HighlightedCode> {
  /// [HighlightedCode.code] split into lines, without `\r`.
  String? _code;
  List<String> _lines = const [];

  Object? _documentKey;
  TokenizedDocument? _document;
  bool _slicing = false;

  /// Styles and spans for the current theme and text style.
  Object? _stylesKey;
  late TokenTextStyles _styles;
  late StrutStyle _strut;
  late TextStyle _numberStyle;
  late double _lineHeight;
  late double _gutterWidth;
  var _spans = Expando<TextSpan>();

  /// Measurements and plain spans for the current styles and lines.
  Object? _metricsKey;
  List<TextSpan?> _plainSpans = const [];
  LineWidths _widths = LineWidths(0);

  /// Built blocks, reused while their lines' spans are the same.
  Object? _blocksKey;
  List<(List<TextSpan>, CodeBlock)?> _blocks = const [];

  final _horizontal = ScrollController();
  final _selection = CodeSelectionDelegate();

  @override
  void dispose() {
    _horizontal.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _syncCode() {
    if (widget.code == _code) return;
    _code = widget.code;
    _lines = [
      for (final line in widget.code.split('\n'))
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
    _selection.lines = _lines;
  }

  void _syncDocument(Highlighter highlighter) {
    // The grammar, not the highlighter, decides the tokens: registering a
    // language can replace it.
    final known = highlighter.language(widget.language) != null;
    final grammar = known ? highlighter.grammar(widget.language) : null;
    final key = (widget.code, grammar);
    if (key == _documentKey) return;
    _documentKey = key;
    if (grammar == null) {
      _document = null;
      return;
    }
    final document = (_document ??= TokenizedDocument(grammar))
      ..grammar = grammar;
    if (!document.update(widget.code, budget: firstSliceBudget)) {
      _finishLater();
    }
  }

  /// Tokenizes the rest between frames, rebuilding the rows on screen as
  /// their lines get colors.
  void _finishLater() {
    if (_slicing) return;
    _slicing = true;
    tokenizeBetweenFrames(
      slice: (budget) => _document?.tokenize(budget: budget) ?? true,
      stop: () => !mounted,
      onSlice: (_) => setState(() {}),
    ).whenComplete(() => _slicing = false);
  }

  void _syncStyles(BuildContext context) {
    final styles = (widget.theme, widget.textStyle);
    if (styles != _stylesKey) {
      _stylesKey = styles;
      _styles = TokenTextStyles(widget.theme, base: widget.textStyle);
      _strut = StrutStyle.fromTextStyle(_styles.base, forceStrutHeight: true);
      _numberStyle = _styles.base.copyWith(color: widget.theme.lineNumberColor);
      _spans = Expando();
    }
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final metrics = (styles, scaler, _lines);
    if (metrics == _metricsKey) return;
    _metricsKey = metrics;
    _plainSpans = List.filled(_lines.length, null);

    TextPainter measure(String text) => TextPainter(
      text: TextSpan(text: text, style: _styles.base),
      strutStyle: _strut,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final digit = measure('0');
    _lineHeight = digit.height;
    _gutterWidth = '${_lines.length}'.length * digit.width + 16;
    // The longest line by characters sets the first guess at the content
    // width; rows that turn out wider grow it.
    final longest = _lines.reduce((a, b) => b.length > a.length ? b : a);
    // A very long line is measured by its start, scaled to its length.
    final sample = longest.length <= 1000
        ? longest
        : longest.substring(0, 1000);
    final painter = measure(_shown(sample));
    _widths = LineWidths(
      sample.isEmpty ? 0 : painter.width * longest.length / sample.length,
    );
    painter.dispose();
    digit.dispose();
  }

  TextSpan _span(int index, List<DocumentLine> tokenized) {
    if (index < tokenized.length) {
      final line = tokenized[index];
      return _spans[line] ??= TextSpan(
        style: _styles.base,
        children: [
          for (final token in line.themed(widget.theme))
            TextSpan(text: _shown(token.text), style: _styles[token.style]),
        ],
      );
    }
    return _plainSpans[index] ??= TextSpan(
      text: _shown(_lines[index]),
      style: _styles.base,
    );
  }

  /// Characters that start a new line in a paragraph but not in the code.
  static final _breaks = RegExp('[\x0B\x0C\r\x85\u2028\u2029]');

  /// [text] with [_breaks] shown as spaces, so a block's paragraph has one
  /// line per line of code. The length stays the same, so selection
  /// offsets still match the code.
  static String _shown(String text) =>
      text.contains(_breaks) ? text.replaceAll(_breaks, ' ') : text;

  @override
  Widget build(BuildContext context) {
    final highlighter = widget.highlighter ?? HighlighterScope.of(context);
    _syncCode();
    _syncDocument(highlighter);
    _syncStyles(context);
    final theme = widget.theme;

    Widget code = _lines.length <= _buildAllUpTo
        ? _content(virtualize: false)
        : LayoutBuilder(
            builder: (context, constraints) => _content(
              virtualize:
                  constraints.hasBoundedWidth &&
                  constraints.hasBoundedHeight &&
                  _lines.length * _lineHeight > constraints.maxHeight,
            ),
          );
    // Above the scroll views, so a drag selection can scroll them.
    if (widget.selectable) {
      code = SelectionArea(
        child: SelectionContainer(delegate: _selection, child: code),
      );
    }

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

  Widget _content({required bool virtualize}) {
    if (widget.softWrap) return _list(virtualize: virtualize, offset: null);
    // One horizontal scroll for every row; each row shifts its own code,
    // so the line numbers stay put.
    return Scrollable(
      axisDirection: AxisDirection.right,
      controller: _horizontal,
      viewportBuilder: (context, offset) => HorizontalExtent(
        offset: offset,
        widths: _widths,
        gutterWidth: widget.lineNumbers ? _gutterWidth : 0,
        child: _list(virtualize: virtualize, offset: offset),
      ),
    );
  }

  Widget _list({required bool virtualize, required ViewportOffset? offset}) {
    final tokenized = _document?.lines ?? const <DocumentLine>[];
    final count = (_lines.length + linesPerBlock - 1) ~/ linesPerBlock;
    final key = (
      _metricsKey,
      offset,
      widget.lineNumbers && !widget.softWrap,
      widget.softWrap,
      widget.selectable,
    );
    if (key != _blocksKey) {
      _blocksKey = key;
      _blocks = List.filled(count, null);
    }
    if (virtualize) {
      return ListView.builder(
        primary: false,
        padding: EdgeInsets.zero,
        itemExtentBuilder: widget.softWrap
            ? null
            : (index, dimensions) =>
                  index < count ? _linesIn(index) * _lineHeight : null,
        itemCount: count,
        itemBuilder: (context, index) => _block(index, tokenized, offset),
      );
    }
    return SingleChildScrollView(
      primary: false,
      // Short code reads as one block, as one paragraph would.
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < count; i++) _block(i, tokenized, offset),
          ],
        ),
      ),
    );
  }

  int _linesIn(int block) =>
      math.min(linesPerBlock, _lines.length - block * linesPerBlock);

  static const _lineBreak = TextSpan(text: '\n');

  CodeBlock _block(
    int index,
    List<DocumentLine> tokenized,
    ViewportOffset? offset,
  ) {
    final first = index * linesPerBlock;
    final lines = [
      for (var i = 0; i < _linesIn(index); i++) _span(first + i, tokenized),
    ];
    if (_blocks[index] case (final cached, final block)?) {
      var same = cached.length == lines.length;
      for (var i = 0; same && i < lines.length; i++) {
        same = identical(cached[i], lines[i]);
      }
      if (same) return block;
    }
    final numbered = widget.lineNumbers && !widget.softWrap;
    final block = CodeBlock(
      index: index,
      span: TextSpan(
        style: _styles.base,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) _lineBreak,
            lines[i],
          ],
        ],
      ),
      strut: _strut,
      softWrap: widget.softWrap,
      numbers: numbered
          ? TextSpan(
              text: [
                for (var i = 0; i < lines.length; i++) '${first + i + 1}',
              ].join('\n'),
              style: _numberStyle,
            )
          : null,
      gutterWidth: _gutterWidth,
      offset: offset,
      widths: offset == null ? null : _widths,
      selection: widget.selectable ? _selection : null,
    );
    _blocks[index] = (lines, block);
    return block;
  }
}
