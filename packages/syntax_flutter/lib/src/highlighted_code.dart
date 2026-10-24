import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ViewportOffset;
import 'package:flutter/scheduler.dart';
import 'package:syntax_darts/syntax.dart';

import 'code_rows.dart';
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
/// Every line has the height of the base style's line. Given a bounded
/// height, code taller than it scrolls, and long code lays out only the
/// lines on screen. Inside another scroll view, where the height is
/// unbounded, every line is laid out; give a large file a height, for
/// example with [Expanded] or [SizedBox]. Code longer than 200 lines can't
/// report intrinsic sizes, so it can't sit inside [IntrinsicHeight] or an
/// [AlertDialog]'s content.
///
/// When only the lines on screen are laid out, a large file is tokenized
/// a slice at a time between frames, top first, and lines show plain until
/// their colors are ready. Otherwise every line is laid out anyway, so the
/// code is tokenized at once and laid out once.
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

/// How long a frame spends tokenizing: while it builds, and again after
/// it, until the code is done.
const _sliceBudget = Duration(milliseconds: 6);

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
  LineWidths _widths = LineWidths(0, guessBlock: 0);

  /// Built blocks, reused while their lines' spans are the same.
  Object? _blocksKey;
  List<(List<TextSpan>, CodeBlock)?> _blocks = const [];

  final _horizontal = ScrollController();
  final _selection = CodeSelectionDelegate();

  /// Blocks left as they were when their colors arrived, because part of
  /// the selection was in them: a paragraph whose spans change shape loses
  /// its selection. They take their colors once the selection leaves.
  final _held = <int>{};

  @override
  void initState() {
    super.initState();
    _selection.onSelectedBlocksChanged = _releaseHeld;
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  /// A font that loads later, such as one fetched at run time, changes the
  /// line height and widths measured with the fallback font.
  void _fontsChanged() => setState(() => _fonts++);

  /// Bumped when system fonts change, so everything measured is again.
  var _fonts = 0;

  void _releaseHeld() {
    final released = [
      for (final block in _held)
        if (!_selection.isSelected(block)) block,
    ];
    if (released.isEmpty) return;
    _held.removeAll(released);
    // Selection changes arrive during event handling and layout, so the
    // rebuild waits for the frame to end.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) setState(() {});
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _horizontal.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _syncCode() {
    if (widget.code == _code) return;
    _code = widget.code;
    final lines = widget.code.split('\n');
    _lines = [
      for (final line in lines)
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
    // Copies take the code's own line breaks.
    _selection.lines = lines;
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
    // [_list] finishes the rest, now or between frames.
    (_document ??= TokenizedDocument(grammar))
      ..grammar = grammar
      ..update(widget.code, budget: _sliceBudget);
  }

  /// Tokenizes the rest a slice at a time, right after each frame,
  /// rebuilding the blocks on screen as their lines get colors.
  ///
  /// Post-frame callbacks rather than timers, so nothing is left pending
  /// when the code goes away, including in widget tests.
  void _finishLater() {
    if (_slicing) return;
    _slicing = true;
    SchedulerBinding.instance
      ..addPostFrameCallback(_slice)
      ..ensureVisualUpdate();
  }

  void _slice(Duration _) {
    if (!mounted) return;
    final done = _document?.tokenize(budget: _sliceBudget) ?? true;
    setState(() {});
    if (done) {
      _slicing = false;
    } else {
      SchedulerBinding.instance.addPostFrameCallback(_slice);
    }
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
    final metrics = (styles, scaler, _lines, _fonts);
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
    // The widest label: the widest digit, as many times as the last line
    // number has digits. Figures can be proportional.
    var widest = '0';
    var widestWidth = digit.width;
    for (var d = 1; d <= 9; d++) {
      final painter = measure('$d');
      if (painter.width > widestWidth) {
        widest = '$d';
        widestWidth = painter.width;
      }
      painter.dispose();
    }
    final label = measure(widest * '${_lines.length}'.length);
    _gutterWidth = label.width + 16;
    label.dispose();
    // The longest line by characters sets the first guess at the content
    // width, until its block is laid out.
    var longest = 0;
    for (var i = 1; i < _lines.length; i++) {
      if (_lines[i].length > _lines[longest].length) longest = i;
    }
    final line = _lines[longest];
    // A very long line is measured by its start, scaled to its length.
    final sample = line.length <= 1000 ? line : line.substring(0, 1000);
    final painter = measure(_shown(sample));
    _widths = LineWidths(
      sample.isEmpty ? 0 : painter.width * line.length / sample.length,
      guessBlock: longest ~/ linesPerBlock,
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
    // Every block is laid out unless virtualized, and recoloring them a
    // slice at a time would lay them all out again each frame, so they
    // get their colors at once.
    if (_document case final document? when !document.isComplete) {
      virtualize ? _finishLater() : document.tokenize();
    }
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
      _held.clear();
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
      if (_selection.isSelected(index)) {
        _held.add(index);
        return block;
      }
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
