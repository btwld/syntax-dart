import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The widest line laid out so far, which sets how far the code scrolls
/// sideways. It starts from an estimate and grows when a row turns out
/// wider, for example a line with wide characters.
final class LineWidths {
  /// Starts from a guess of [max].
  LineWidths(this.max);

  /// The content width the horizontal scroll covers.
  double max;

  RenderHorizontalExtent? _extent;
  bool _scheduled = false;

  void _report(double width) {
    if (width <= max) return;
    max = width;
    final extent = _extent;
    // Rows laid out inside the extent's own layout are picked up by it.
    if (extent == null || extent._layingOut || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_extent case final extent? when extent.attached) {
        extent.markNeedsLayout();
      }
    });
  }
}

/// Gives a horizontal [Scrollable] its extent: the viewport is the width
/// after the gutter, and the content is [widths]' max. The child, the
/// vertical list of rows, keeps the full width; each row shifts its own
/// code with a [ShiftedCode].
class HorizontalExtent extends SingleChildRenderObjectWidget {
  /// Sizes [offset] for [child]'s rows.
  const HorizontalExtent({
    super.key,
    required this.offset,
    required this.widths,
    required this.gutterWidth,
    super.child,
  });

  /// The horizontal scroll offset.
  final ViewportOffset offset;

  /// The content width.
  final LineWidths widths;

  /// The width of the line numbers, which don't scroll sideways.
  final double gutterWidth;

  @override
  RenderHorizontalExtent createRenderObject(BuildContext context) =>
      RenderHorizontalExtent(offset, widths, gutterWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHorizontalExtent renderObject,
  ) {
    renderObject
      ..offset = offset
      ..widths = widths
      ..gutterWidth = gutterWidth;
  }
}

/// The render object of [HorizontalExtent].
class RenderHorizontalExtent extends RenderProxyBox {
  /// Sizes [offset] for its child's rows.
  RenderHorizontalExtent(this._offset, this._widths, this._gutterWidth);

  ViewportOffset _offset;

  /// The horizontal scroll offset.
  set offset(ViewportOffset value) {
    if (identical(value, _offset)) return;
    _offset = value;
    markNeedsLayout();
  }

  LineWidths _widths;

  /// The content width.
  set widths(LineWidths value) {
    if (identical(value, _widths)) return;
    if (attached) {
      _widths._extent = null;
      value._extent = this;
    }
    _widths = value;
    markNeedsLayout();
  }

  double _gutterWidth;

  /// The width of the line numbers.
  set gutterWidth(double value) {
    if (value == _gutterWidth) return;
    _gutterWidth = value;
    markNeedsLayout();
  }

  bool _layingOut = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _widths._extent = this;
  }

  @override
  void detach() {
    if (identical(_widths._extent, this)) _widths._extent = null;
    super.detach();
  }

  @override
  void performLayout() {
    _layingOut = true;
    try {
      super.performLayout();
    } finally {
      _layingOut = false;
    }
    final viewport = math.max(0.0, size.width - _gutterWidth);
    _offset.applyViewportDimension(viewport);
    _offset.applyContentDimensions(0, math.max(0.0, _widths.max - viewport));
  }
}

/// Code that scrolls sideways: lays [child] out at its full width, and
/// paints and hit-tests it moved left by [offset]'s pixels, clipped to its
/// own box.
class ShiftedCode extends SingleChildRenderObjectWidget {
  /// Shifts [child] by [offset], reporting its width to [widths].
  const ShiftedCode({
    super.key,
    required this.offset,
    required this.widths,
    super.child,
  });

  /// The horizontal scroll offset.
  final ViewportOffset offset;

  /// Where the line's width is reported.
  final LineWidths widths;

  @override
  RenderShiftedCode createRenderObject(BuildContext context) =>
      RenderShiftedCode(offset, widths);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderShiftedCode renderObject,
  ) {
    renderObject
      ..offset = offset
      ..widths = widths;
  }
}

/// The render object of [ShiftedCode].
class RenderShiftedCode extends RenderProxyBox {
  /// Shifts its child by [offset], reporting its width to [widths].
  RenderShiftedCode(this._offset, this._widths);

  ViewportOffset _offset;

  /// The horizontal scroll offset.
  set offset(ViewportOffset value) {
    if (identical(value, _offset)) return;
    if (attached) {
      _offset.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _offset = value;
    markNeedsPaint();
  }

  LineWidths _widths;

  /// Where the line's width is reported.
  set widths(LineWidths value) {
    if (identical(value, _widths)) return;
    _widths = value;
    markNeedsLayout();
  }

  double get _shift => _offset.hasPixels ? _offset.pixels : 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _offset.removeListener(markNeedsPaint);
    super.detach();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        minHeight: constraints.minHeight,
        maxHeight: constraints.maxHeight,
      );

  Size _sizeFor(BoxConstraints constraints, Size child) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : child.width,
          child.height,
        ),
      );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _sizeFor(
      constraints,
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    _widths._report(child.size.width);
    size = _sizeFor(constraints, child.size);
  }

  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) =>
          context.paintChild(child, offset.translate(-_shift, 0)),
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null || !(Offset.zero & size).contains(position)) {
      return false;
    }
    return result.addWithPaintOffset(
      offset: Offset(-_shift, 0),
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(-_shift, 0, 0, 1);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => Offset.zero & size;

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

/// A [StaticSelectionContainerDelegate] that asks for a frame when a
/// selectable registers.
///
/// Flutter takes in new selectables after a frame. Containers nested as
/// deep as a row inside two scroll views register after the frame that
/// built them, so without another frame the code can't be selected until
/// something else repaints.
class RowSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  void add(Selectable selectable) {
    super.add(selectable);
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

/// How many lines each row of [HighlightedCode] shows, as one paragraph.
///
/// A paragraph costs a fixed amount to lay out, and much more per style
/// run once it holds thousands; a few dozen lines keep both small, and
/// the rows small enough to build only those on screen.
const linesPerBlock = 32;

/// Selection over blocks of code.
///
/// A [SelectionArea] over separate paragraphs copies them without line
/// breaks, and only the rows that were built. Rows that hold part of the
/// selection stay alive when they scroll away, so the first and last
/// selected blocks are always here; this delegate copies from the first
/// to the last, with line breaks, taking every block between them from
/// [lines]. Select all copies every line, built or not.
final class CodeSelectionDelegate extends RowSelectionDelegate {
  /// The text of every line, without line breaks.
  List<String> lines = const [];

  /// The selection delegates of the blocks that are built, by block.
  final _blocks = <int, RowSelectionDelegate>{};

  /// The built blocks that hold part of the selection.
  final _selected = SplayTreeSet<int>();

  final _listeners = <int, VoidCallback>{};

  /// Everything is selected, including lines that were never built.
  bool _all = false;

  /// Starts tracking the delegate of [block].
  void addBlock(int block, RowSelectionDelegate delegate) {
    removeBlock(block);
    _blocks[block] = delegate;
    void listener() => delegate.value.hasSelection
        ? _selected.add(block)
        : _selected.remove(block);
    _listeners[block] = listener;
    delegate.addListener(listener);
    listener();
  }

  /// Stops tracking [block], if [delegate] is still its delegate.
  void removeBlock(int block, [RowSelectionDelegate? delegate]) {
    final current = _blocks[block];
    if (current == null ||
        (delegate != null && !identical(delegate, current))) {
      return;
    }
    current.removeListener(_listeners.remove(block)!);
    _blocks.remove(block);
    _selected.remove(block);
  }

  String _text(int block) => lines
      .sublist(
        block * linesPerBlock,
        math.min((block + 1) * linesPerBlock, lines.length),
      )
      .join('\n');

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    _all = event is SelectAllSelectionEvent;
    return super.dispatchSelectionEvent(event);
  }

  @override
  SelectedContent? getSelectedContent() {
    if (_all) return SelectedContent(plainText: lines.join('\n'));
    if (_selected.isEmpty) return null;
    final first = _selected.first;
    final last = _selected.last;
    final firstRange = _blocks[first]!.getSelection();
    final lastRange = _blocks[last]!.getSelection();
    if (firstRange == null || lastRange == null) {
      return super.getSelectedContent();
    }
    final start = math.min(firstRange.startOffset, firstRange.endOffset);
    final end = math.max(lastRange.startOffset, lastRange.endOffset);
    final String text;
    if (first == last) {
      text = _text(first).substring(start, end);
    } else {
      text = [
        _text(first).substring(start),
        for (var block = first + 1; block < last; block++) _text(block),
        _text(last).substring(0, end),
      ].join('\n');
    }
    if (text.isEmpty) return null;
    return SelectedContent(plainText: text);
  }

  @override
  void dispose() {
    for (final block in [..._blocks.keys]) {
      removeBlock(block);
    }
    super.dispose();
  }
}

/// A block of [linesPerBlock] lines of [HighlightedCode], the last one
/// maybe fewer: optional line numbers, then the code.
class CodeBlock extends StatefulWidget {
  /// Shows block [index] of the code as [span].
  const CodeBlock({
    super.key,
    required this.index,
    required this.span,
    required this.strut,
    required this.softWrap,
    this.numbers,
    this.gutterWidth = 0,
    this.offset,
    this.widths,
    this.selection,
  });

  /// The block's index; its first line is `index * linesPerBlock`.
  final int index;

  /// The block's code, styled, with a line break between lines.
  final TextSpan span;

  /// Gives every line, and its number, the same height.
  final StrutStyle strut;

  /// Whether lines wrap instead of scrolling sideways.
  final bool softWrap;

  /// The line numbers, one per line, styled; `null` hides the gutter.
  final TextSpan? numbers;

  /// The width of the line numbers, including the space after them.
  final double gutterWidth;

  /// The horizontal scroll offset. `null` when the code wraps.
  final ViewportOffset? offset;

  /// Where the block's width is reported; set with [offset].
  final LineWidths? widths;

  /// Tracks the block's selection; `null` when the code isn't selectable.
  final CodeSelectionDelegate? selection;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  RowSelectionDelegate? _delegate;

  /// Keeps the selection container, and its delegate's context, when line
  /// numbers or wrapping change what wraps it.
  final _containerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(CodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection ||
        oldWidget.index != widget.index) {
      oldWidget.selection?.removeBlock(oldWidget.index, _delegate);
      _register();
    }
  }

  void _register() {
    final selection = widget.selection;
    if (selection == null) return;
    selection.addBlock(widget.index, _delegate ??= RowSelectionDelegate());
  }

  @override
  void dispose() {
    widget.selection?.removeBlock(widget.index, _delegate);
    _delegate?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget code = Text.rich(
      widget.span,
      strutStyle: widget.strut,
      softWrap: widget.softWrap,
    );
    if (_delegate case final delegate? when widget.selection != null) {
      code = SelectionContainer(
        key: _containerKey,
        delegate: delegate,
        child: code,
      );
    }
    if (widget.offset case final offset?) {
      code = ShiftedCode(offset: offset, widths: widget.widths!, child: code);
    }
    final numbers = widget.numbers;
    if (numbers == null) return code;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Numbers are neither copied nor read out with the code.
        SizedBox(
          width: widget.gutterWidth,
          child: SelectionContainer.disabled(
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text.rich(
                  numbers,
                  textAlign: TextAlign.right,
                  strutStyle: widget.strut,
                  softWrap: false,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: code),
      ],
    );
  }
}
