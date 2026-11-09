part of 'highlighted_code.dart';

/// Individual source rows share the block renderer's exact-copy delegate,
/// configured with one source line per paragraph.
class _CodeLines extends StatefulWidget {
  const _CodeLines({
    required this.owner,
    required this.tokenized,
    required this.offset,
    required this.virtualize,
  });

  final _HighlightedCodeState owner;
  final List<DocumentLine> tokenized;
  final ViewportOffset? offset;
  final bool virtualize;

  @override
  State<_CodeLines> createState() => _CodeLinesState();
}

class _CodeLinesState extends State<_CodeLines>
    with SingleTickerProviderStateMixin {
  final _vertical = ScrollController();
  final _focus = FocusNode();
  final _rows = <int, BuildContext>{};
  late final Ticker _autoScroll = createTicker(_scrollTick);
  Duration _lastTick = Duration.zero;
  Offset? _pointer;
  int? _dragAnchor;
  Object? _reveal;
  Object? _selection;
  Object? _source;

  _HighlightedCodeState get owner => widget.owner;
  HighlightedCode get view => owner.widget;
  CodeViewController? get controller => view.controller;

  @override
  void dispose() {
    _autoScroll.dispose();
    _vertical.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _copy() {
    final text =
        owner._selection.getSelectedContent()?.plainText ??
        controller?.selectedText;
    if (text != null) Clipboard.setData(ClipboardData(text: text));
  }

  void _select(int anchor, int active) {
    owner._selection.dispatchSelectionEvent(const ClearSelectionEvent());
    controller!.selectLines(anchor, active);
    _focus.requestFocus();
  }

  void _start(int line, PointerDownEvent event) {
    if (controller == null || !view.selectable || event.buttons != 1) return;
    final anchor = HardwareKeyboard.instance.isShiftPressed
        ? controller!.selection?.anchor ?? line
        : line;
    _dragAnchor = anchor;
    _pointer = event.position;
    _select(anchor, line);
  }

  void _move(PointerMoveEvent event) {
    if (_dragAnchor == null) return;
    _pointer = event.position;
    _extend();
    if (!_autoScroll.isActive) {
      _lastTick = Duration.zero;
      _autoScroll.start();
    }
  }

  void _stop() {
    _dragAnchor = null;
    _pointer = null;
    _autoScroll.stop();
  }

  void _extend() {
    if (_pointer == null || _dragAnchor == null) return;
    int? nearest;
    var distance = double.infinity;
    for (final entry in _rows.entries) {
      if (!entry.value.mounted) continue;
      final box = entry.value.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final y = _pointer!.dy;
      final delta = y < top ? top - y : (y > bottom ? y - bottom : 0.0);
      if (delta < distance) {
        nearest = entry.key;
        distance = delta;
      }
    }
    if (nearest != null && controller!.selection?.active != nearest) {
      _select(_dragAnchor!, nearest);
    }
  }

  Iterable<ScrollableState> _verticalScrollables(BuildContext row) sync* {
    var scrollable = Scrollable.maybeOf(row, axis: Axis.vertical);
    while (scrollable != null) {
      yield scrollable;
      scrollable = Scrollable.maybeOf(scrollable.context, axis: Axis.vertical);
    }
  }

  void _revealVertically(BuildContext row) {
    final target = row.findRenderObject()!;
    var object = target;
    // The indexed viewport owns its measured jump. Only enclosing positions
    // need another reveal once that jump has built the target row.
    final indexedPosition = widget.virtualize && _vertical.hasClients
        ? _vertical.position
        : null;
    // Cross distinct horizontal viewports without scrolling them, but stay
    // inside a shared 2D viewport until its vertical position is processed.
    var scrollable = Scrollable.maybeOf(row);
    while (scrollable != null) {
      if (scrollable.position.axis == Axis.vertical &&
          scrollable.position != indexedPosition) {
        scrollable.position.ensureVisible(object, targetRenderObject: target);
      }
      final viewport = RenderAbstractViewport.maybeOf(object);
      final vertical = Scrollable.maybeOf(
        scrollable.context,
        axis: Axis.vertical,
      );
      final sharedViewport =
          viewport is RenderTwoDimensionalViewport &&
          identical(viewport.horizontalOffset, scrollable.position) &&
          identical(viewport.verticalOffset, vertical?.position);
      if (!sharedViewport) object = scrollable.context.findRenderObject()!;
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  void _scrollTick(Duration elapsed) {
    final seconds = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (_pointer == null) return;
    final row = _rows.values.where((row) => row.mounted).firstOrNull;
    if (row == null) return;
    final scrollables = _verticalScrollables(row).toList();
    for (var i = 0; i < scrollables.length; i++) {
      final position = scrollables[i].position;
      if (!position.hasContentDimensions ||
          position.maxScrollExtent == position.minScrollExtent) {
        continue;
      }
      Rect? bounds;
      // Intersect enclosing viewports so a partially visible nested view uses
      // the edge the reader can actually reach.
      for (final scrollable in scrollables.skip(i)) {
        final box = scrollable.context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        bounds = bounds?.intersect(rect) ?? rect;
      }
      if (bounds == null || bounds.isEmpty) continue;
      final y = _pointer!.dy;
      final edge = y < bounds.top + 24
          ? y - bounds.top - 24
          : (y > bounds.bottom - 24 ? y - bounds.bottom + 24 : 0.0);
      final direction = position.axisDirection == AxisDirection.up ? -1 : 1;
      final target =
          (position.pixels + direction * edge.clamp(-100, 100) * 15 * seconds)
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (target == position.pixels) continue;
      position.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _extend();
      });
      break;
    }
  }

  void _completeReveal(Object reveal, int line, [Rect? previousRect]) {
    if (!mounted || reveal != _reveal) return;
    final row = _rows[line];
    Rect? rect;
    if (row != null && row.mounted) {
      if (widget.virtualize) {
        final box = row.findRenderObject()! as RenderBox;
        final viewport = RenderAbstractViewport.maybeOf(box);
        if (viewport is RenderBox) {
          rect = box.localToGlobal(Offset.zero, ancestor: viewport) & box.size;
        }
      }
      // Measured rows can still shift after the indexed jump builds them.
      // Wait for the target's position in its viewport to settle before
      // aligning that target in the enclosing scroll views.
      if (rect == previousRect) {
        _revealVertically(row);
        return;
      }
    }
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _completeReveal(reveal, line, rect))
      ..ensureVisualUpdate();
  }

  void _syncRequests() {
    if (_source != owner._sourceIdentity) {
      _source = owner._sourceIdentity;
      _stop();
      _rows.clear();
    }
    final selection = (
      controller,
      controller?.revision,
      controller?.selectionRequest,
    );
    if (selection != _selection) {
      _selection = selection;
      if (controller?.selection != null && view.selectable) {
        owner._selection.dispatchSelectionEvent(const ClearSelectionEvent());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      }
    }
    final reveal = (controller, controller?.revealRequest, _source);
    if (reveal == _reveal) return;
    _reveal = reveal;
    if (controller?.revealTarget != null) {
      final line = controller!.revealTarget!;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _completeReveal(reveal, line),
      );
    }
  }

  Widget _row(BuildContext context, int line) {
    _rows.removeWhere((_, value) => !value.mounted);
    _rows[line] = context;
    final selection = controller?.selection;
    final selected =
        selection != null &&
        line >= math.min(selection.anchor, selection.active) &&
        line <= math.max(selection.anchor, selection.active);
    final marker = view.gutterBuilder?.call(context, line);
    final gutter =
        (view.lineNumbers ? owner._gutterWidth : 0.0) +
        (view.gutterBuilder == null ? 0 : 24);
    Widget code = owner._block(line, widget.tokenized, widget.offset);
    if (gutter > 0) {
      code = Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(left: gutter),
            child: code,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: gutter,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _start(line, event),
              onPointerMove: _move,
              onPointerUp: (_) => _stop(),
              onPointerCancel: (_) => _stop(),
              child: SelectionContainer.disabled(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: gutter,
                    height: owner._lineHeight,
                    child: Row(
                      children: [
                        if (view.gutterBuilder != null)
                          SizedBox(width: 24, child: ClipRect(child: marker)),
                        if (view.lineNumbers)
                          SizedBox(
                            width: owner._gutterWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: ExcludeSemantics(
                                child: Text(
                                  '${line + 1}',
                                  style: owner._numberStyle,
                                  strutStyle: owner._strut,
                                  textAlign: TextAlign.right,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ColoredBox(
      color: view.lineBackgroundBuilder?.call(line) ?? const Color(0x00000000),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? view.theme.selectionColor : null,
        ),
        child: code,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncRequests();
    Widget result;
    if (widget.virtualize) {
      result = IndexedCodeViewport(
        key: ValueKey(controller),
        controller: _vertical,
        count: owner._lines.length,
        layoutKey: (
          owner._metricsKey,
          view.softWrap,
          view.lineNumbers,
          view.gutterBuilder != null,
        ),
        estimatedHeight: owner._lineHeight,
        fixedHeight: !view.softWrap,
        identity: (line) => line,
        indexOf: (id) => id is int && id < owner._lines.length ? id : null,
        revealRow: controller?.revealTarget,
        revealRequest: controller?.revealRequest ?? 0,
        retainedRows: owner._selection.selectedEndpoints,
        builder: (_, line) =>
            Builder(builder: (context) => _row(context, line)),
      );
    } else {
      result = SingleChildScrollView(
        controller: _vertical,
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var line = 0; line < owner._lines.length; line++)
              Builder(builder: (context) => _row(context, line)),
          ],
        ),
      );
    }
    return CallbackShortcuts(
      bindings: view.selectable
          ? {
              const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                  _copy,
              const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
            }
          : const {},
      child: Focus(focusNode: _focus, child: result),
    );
  }
}
