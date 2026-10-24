import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:syntax/syntax.dart';

/// Scrollable list that measures only the rows it builds.
/// Large unmounted ranges occupy estimated sliver space, so jumping to a
/// distant row never requires building all preceding widgets.
class IndexedCodeViewport extends StatefulWidget {
  /// Uses core prefix sums and renderer-provided row measurements.
  const IndexedCodeViewport({
    super.key,
    required this.controller,
    required this.count,
    required this.builder,
    required this.layoutKey,
    required this.identity,
    required this.indexOf,
    this.estimatedHeight = 24,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.revealRow,
    this.revealRequest = 0,
    this.onFirstRow,
    this.onVisibleRange,
    this.fixedHeight = false,
  });

  /// Caller-owned vertical scrolling.
  final ScrollController controller;

  /// Number of logical rows.
  final int count;

  /// Builds one requested row.
  final Widget Function(BuildContext, int) builder;

  /// Changes when source rows or their measurement assumptions change.
  final Object layoutKey;

  /// Stable source identity for a row.
  final Object Function(int) identity;

  /// Resolves a previously visible identity after an insertion or expansion.
  final int? Function(Object) indexOf;

  /// Height used until a row is measured.
  final double estimatedHeight;

  /// Outer viewport padding.
  final EdgeInsetsGeometry padding;

  /// Optional native scroll physics.
  final ScrollPhysics? physics;

  /// Logical target for an explicit scrolling request.
  final int? revealRow;

  /// Increments even when a later command targets the same row.
  final int revealRequest;

  /// Reports the first visible logical row for sticky headers.
  final ValueChanged<int>? onFirstRow;

  /// Reports visible logical rows as a half-open range after layout.
  final void Function(int start, int end)? onVisibleRange;

  /// Uses Flutter's direct indexed sliver when every row has estimatedHeight.
  final bool fixedHeight;
  @override
  State<IndexedCodeViewport> createState() => _IndexedCodeViewportState();
}

class _IndexedCodeViewportState extends State<IndexedCodeViewport> {
  late RowHeightIndex _heights;
  int _first = 0, _last = 0, _visible = 0;
  double _extent = 600;
  double? _width;
  Object? _anchor;
  double _within = 0;
  bool _queued = false;
  bool _rangeQueued = false;
  (int, int)? _reportedRange;
  final Map<int, double> _measurements = {};
  double get _offset => widget.controller.hasClients
      ? widget.controller.offset
      : widget.controller.initialScrollOffset;
  void _reset() {
    _heights = RowHeightIndex(
      widget.count,
      estimatedHeight: widget.estimatedHeight,
    );
    _measurements.clear();
    _reportedRange = null;
  }

  void _range() {
    if (widget.count == 0) {
      _first = _last = 0;
      return;
    }
    _visible = _heights.rowAt(_offset);
    _first = _heights.rowAt(math.max(0, _offset - 300));
    _last = (_heights.rowAt(_offset + _extent + 300) + 1).clamp(
      _first,
      widget.count,
    );
    _anchor = widget.identity(_visible);
    _within = _offset - _heights.offsetFor(_visible);
    _reportRange();
  }

  void _reportRange() {
    if (widget.onVisibleRange == null || _rangeQueued) return;
    _rangeQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rangeQueued = false;
      if (!mounted) return;
      final end = (_heights.rowAt(_offset + _extent) + 1).clamp(
        0,
        widget.count,
      );
      final range = (_visible, end);
      if (range == _reportedRange) return;
      _reportedRange = range;
      widget.onVisibleRange?.call(range.$1, range.$2);
    });
  }

  void _scroll() {
    final previous = (_first, _last);
    _range();
    if (!widget.fixedHeight && (_first, _last) != previous && mounted) {
      setState(() {});
    }
    widget.onFirstRow?.call(_visible);
  }

  void _measure(int index, double height) {
    if (!mounted || index >= widget.count || height <= 0) return;
    if ((_heights.offsetFor(index + 1) - _heights.offsetFor(index) - height)
            .abs() <
        .1) {
      return;
    }
    _measurements[index] = height;
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || _measurements.isEmpty) return;
      final anchor = _heights.rowAt(_offset);
      final within = _offset - _heights.offsetFor(anchor);
      var correction = 0.0;
      for (final entry in _measurements.entries) {
        final delta = _heights.measure(entry.key, entry.value);
        if (entry.key < anchor) correction += delta;
      }
      final anchorHeight =
          _heights.offsetFor(anchor + 1) - _heights.offsetFor(anchor);
      if (_measurements.containsKey(anchor) && within >= anchorHeight) {
        correction += math.max(0, anchorHeight - _extent) - within;
      }
      _measurements.clear();
      setState(_range);
      if (correction != 0 && widget.controller.hasClients) {
        widget.controller.jumpTo(
          (_offset + correction).clamp(0, _heights.offsetFor(widget.count)),
        );
      }
    });
  }

  void _jump(int index, [double within = 0]) {
    if (widget.count == 0 || !widget.controller.hasClients) return;
    final value = _heights.offsetFor(index.clamp(0, widget.count - 1)) + within;
    widget.controller.jumpTo(
      value.clamp(0, widget.controller.position.maxScrollExtent),
    );
    setState(_range);
  }

  @override
  void initState() {
    super.initState();
    _reset();
    _range();
    widget.controller.addListener(_scroll);
    if (widget.revealRow case final target?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jump(target);
      });
    }
  }

  @override
  void didUpdateWidget(IndexedCodeViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scroll);
      widget.controller.addListener(_scroll);
    }
    if (oldWidget.layoutKey != widget.layoutKey ||
        oldWidget.count != widget.count ||
        oldWidget.fixedHeight != widget.fixedHeight ||
        oldWidget.estimatedHeight != widget.estimatedHeight) {
      final anchor = _anchor;
      final within = _within;
      final index = anchor == null ? null : widget.indexOf(anchor);
      final height = oldWidget.count == 0
          ? null
          : _heights.offsetFor(_visible + 1) - _heights.offsetFor(_visible);
      _reset();
      if (index != null && height != null) _heights.measure(index, height);
      _range();
      if (index != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jump(index, within);
        });
      }
    }
    if (widget.revealRow != null &&
        (oldWidget.revealRequest != widget.revealRequest ||
            oldWidget.revealRow != widget.revealRow)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jump(widget.revealRow!);
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_width != null && _width != constraints.maxWidth) {
        final anchor = _visible, within = _within;
        final height = widget.count == 0
            ? null
            : _heights.offsetFor(anchor + 1) - _heights.offsetFor(anchor);
        _reset();
        if (height != null) _heights.measure(anchor, height);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jump(anchor, within);
        });
      }
      _width = constraints.maxWidth;
      _extent = constraints.maxHeight.isFinite ? constraints.maxHeight : 600;
      _range();
      return CustomScrollView(
        controller: widget.controller,
        physics: widget.physics,
        // Supported by the package's minimum Flutter SDK.
        // ignore: deprecated_member_use
        cacheExtent: 300,
        slivers: [
          SliverPadding(
            padding: widget.padding,
            sliver: widget.fixedHeight
                ? SliverFixedExtentList(
                    itemExtent: widget.estimatedHeight,
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => KeyedSubtree(
                        key: ValueKey(widget.identity(index)),
                        child: widget.builder(context, index),
                      ),
                      childCount: widget.count,
                      findChildIndexCallback: (key) =>
                          widget.indexOf((key as ValueKey<Object>).value),
                      addAutomaticKeepAlives: false,
                    ),
                  )
                : SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: _heights.offsetFor(_first)),
                      ),
                      SliverList(
                        // The local sliver indexes restart at zero when the window
                        // moves. Older Flutter versions otherwise apply scroll
                        // corrections from the previous window's child offsets.
                        key: ValueKey(_first),
                        delegate: SliverChildBuilderDelegate(
                          (context, local) {
                            final index = _first + local;
                            return _MeasuredRow(
                              key: ValueKey(widget.identity(index)),
                              onSize: (size) => _measure(index, size.height),
                              child: widget.builder(context, index),
                            );
                          },
                          childCount: _last - _first,
                          addAutomaticKeepAlives: false,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: math.max(
                            0,
                            _heights.offsetFor(widget.count) -
                                _heights.offsetFor(_last),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
  @override
  void dispose() {
    widget.controller.removeListener(_scroll);
    super.dispose();
  }
}

class _MeasuredRow extends SingleChildRenderObjectWidget {
  const _MeasuredRow({super.key, required this.onSize, required super.child});
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) => _MeasureBox(onSize);
  @override
  void updateRenderObject(BuildContext context, _MeasureBox renderObject) {
    renderObject.onSize = onSize;
  }
}

class _MeasureBox extends RenderProxyBox {
  _MeasureBox(this.onSize);
  ValueChanged<Size> onSize;
  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}
