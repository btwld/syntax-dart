import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

/// Scrollable list that measures only the rows it builds.
/// Large unmounted ranges occupy estimated sliver space, so jumping to a
/// distant row never requires building all preceding widgets. Rows already
/// built keep their elements and states while the list scrolls.
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
  int _visible = 0;

  /// The row the list of rows starts at. It moves only when the reader jumps
  /// away, scrolls above it, or the layout changes, so scrolling keeps the
  /// rows the list has built.
  int _base = 0;
  bool _rebase = true;

  /// Counts forced restarts, so a restart at the same first row is still a
  /// new list.
  int _restarts = 0;

  /// Rows laid out since the heights were last reset.
  final Set<int> _laidOut = {};

  /// Counts resets of the heights. A row the list keeps through one is laid
  /// out again, so its height is measured anew instead of left at the
  /// estimate.
  int _generation = 0;

  /// Rows laid out before that came back with a different height, waiting
  /// for the measurements to apply.
  final Set<int> _relaidOut = {};
  double _rangeOffset = 0;

  /// How far beyond the viewport rows are built, on each side.
  static const double _cache = 300;
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
    _laidOut.clear();
    _relaidOut.clear();
    _reportedRange = null;
    _rebase = true;
    _generation++;
  }

  void _range() {
    if (widget.count == 0) {
      _visible = _base = 0;
      return;
    }
    final offset = _offset;
    _visible = _heights.rowAt(offset);
    final first = _heights.rowAt(math.max(0, offset - _cache));
    // A jump past everything built starts a new list at the target instead
    // of building every row in between.
    final jumped = (offset - _rangeOffset).abs() > _extent + 2 * _cache;
    if (_rebase || jumped || _base >= widget.count) {
      _base = first;
    } else if (first < _base) {
      // Above the list's first row, a new list starts a screen higher, so
      // scrolling up rebuilds once a screen rather than once a row.
      _base = _heights.rowAt(math.max(0, offset - _cache - _extent));
    }
    _rebase = false;
    _rangeOffset = offset;
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
    final base = _base;
    _range();
    if (!widget.fixedHeight && _base != base && mounted) setState(() {});
    widget.onFirstRow?.call(_visible);
  }

  void _measure(int index, double height) {
    if (!mounted || index >= widget.count || height <= 0) return;
    final seen = !_laidOut.add(index);
    if ((_heights.offsetFor(index + 1) - _heights.offsetFor(index) - height)
            .abs() <
        .1) {
      return;
    }
    _measurements[index] = height;
    if (seen) _relaidOut.add(index);
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || _measurements.isEmpty) return;
      final anchor = _heights.rowAt(_offset);
      final within = _offset - _heights.offsetFor(anchor);
      var correction = 0.0;
      var restart = false;
      for (final entry in _measurements.entries) {
        final delta = _heights.measure(entry.key, entry.value);
        if (entry.key < anchor) {
          correction += delta;
          restart = restart || _relaidOut.contains(entry.key);
        }
      }
      _relaidOut.clear();
      final anchorHeight =
          _heights.offsetFor(anchor + 1) - _heights.offsetFor(anchor);
      if (_measurements.containsKey(anchor) && within >= anchorHeight) {
        correction += math.max(0, anchorHeight - _extent) - within;
      }
      _measurements.clear();
      // The correction assumes rows above the anchor pushed it down by
      // their change, as a row laid out for the first time does: the list
      // builds those forward from its first row. A row laid out before that
      // comes back with a new height may have been put back above rows the
      // list already had, so it grew upward instead; then the list starts
      // again, laying every row out where the heights now put it.
      if (restart) {
        _rebase = true;
        _restarts++;
      }
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
        cacheExtent: _cache,
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
                        child: SizedBox(height: _heights.offsetFor(_base)),
                      ),
                      // A new list, and so new rows, only when its first row
                      // moves. Within one list the rows never change index,
                      // so none is remapped with a stale layout offset.
                      _RowList(
                        key: ValueKey((_base, _restarts)),
                        remainingAfter: (local) =>
                            _heights.offsetFor(widget.count) -
                            _heights.offsetFor(
                              math.min(widget.count, _base + local + 1),
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, local) {
                            final index = _base + local;
                            return _MeasuredRow(
                              key: ValueKey(widget.identity(index)),
                              generation: _generation,
                              onSize: (size) => _measure(index, size.height),
                              child: widget.builder(context, index),
                            );
                          },
                          childCount: widget.count - _base,
                          addAutomaticKeepAlives: false,
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

/// The rows from the list's first row to the end. Only the rows near the
/// viewport are built; the extent of the rest comes from the measured and
/// estimated heights, so the scroll extent stays exact.
class _RowList extends SliverList {
  const _RowList({
    super.key,
    required super.delegate,
    required this.remainingAfter,
  });

  /// Height of the rows after the list's row [local].
  final double Function(int local) remainingAfter;

  @override
  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => trailingScrollOffset + remainingAfter(lastIndex);
}

class _MeasuredRow extends SingleChildRenderObjectWidget {
  const _MeasuredRow({
    super.key,
    required this.generation,
    required this.onSize,
    required super.child,
  });

  /// The viewport's count of height resets; a new one measures the row
  /// again even when nothing else about it changed.
  final int generation;
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureBox(onSize, generation);
  @override
  void updateRenderObject(BuildContext context, _MeasureBox renderObject) {
    renderObject
      ..onSize = onSize
      ..generation = generation;
  }
}

class _MeasureBox extends RenderProxyBox {
  _MeasureBox(this.onSize, this._generation);
  ValueChanged<Size> onSize;

  int _generation;
  set generation(int value) {
    if (value == _generation) return;
    _generation = value;
    // A row kept through a reset reports its height again.
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}
