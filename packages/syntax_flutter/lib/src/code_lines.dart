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

  void _scrollTick(Duration elapsed) {
    final seconds = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (_pointer == null || !_vertical.hasClients) return;
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(_pointer!).dy;
    final edge = y < 24
        ? y - 24
        : (y > box.size.height - 24 ? y - box.size.height + 24 : 0.0);
    if (edge == 0) return;
    final position = _vertical.position;
    final target = (position.pixels + edge.clamp(-100, 100) * 15 * seconds)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      _vertical.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _extend();
      });
    }
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
    if (!widget.virtualize && controller?.revealTarget != null) {
      final line = controller!.revealTarget!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || reveal != _reveal) return;
        final row = _rows[line];
        if (row != null && row.mounted) Scrollable.ensureVisible(row);
      });
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
      code = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _start(line, event),
            onPointerMove: _move,
            onPointerUp: (_) => _stop(),
            onPointerCancel: (_) => _stop(),
            child: SelectionContainer.disabled(
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
          Expanded(child: code),
        ],
      );
    }
    return ColoredBox(
      color:
          view.lineBackgroundBuilder?.call(line) ??
          (selected ? view.theme.selectionColor : const Color(0x00000000)),
      child: code,
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
