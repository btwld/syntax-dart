import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

/// Local row geometry published by an indexed viewport after layout.
///
/// Offsets include the viewport's top padding. Measurements can be supplied
/// for a header laid out in an overlay or outside the visible row window.
class IndexedViewportLayout {
  IndexedViewportLayout._(
    this._heights,
    this._measured,
    this._measure,
    this.paddingTop,
    this.extent,
  );
  final RowHeightIndex _heights;
  final Set<int> _measured;
  final void Function(int, double) _measure;

  /// Top inset in logical viewport pixels.
  final double paddingTop;

  /// Viewport height in logical pixels.
  final double extent;

  /// Content offset of a row, including top padding.
  double offsetFor(int row) => paddingTop + _heights.offsetFor(row);

  /// Measured or estimated height of a row.
  double heightFor(int row) =>
      _heights.offsetFor(row + 1) - _heights.offsetFor(row);

  /// Logical row at a local scroll offset.
  int rowAt(double offset) => _heights.rowAt(math.max(0, offset - paddingTop));

  /// Whether a row has been laid out in this layout generation.
  bool isMeasured(int row) => _measured.contains(row);

  /// Records an independently laid-out row's local height.
  void measure(int row, double height) => _measure(row, height);
}

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
    this.revealHeaderRow,
    this.revealHeaderInset = 0,
    this.onRevealComplete,
    this.onLayout,
    this.onFirstRow,
    this.onVisibleRange,
    this.fixedHeight = false,
    this.retainedRows = const {},
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

  /// Header row whose height clears an explicit reveal destination.
  final int? revealHeaderRow;

  /// Non-header spacing included in [revealHeaderRow], such as a file gap.
  final double revealHeaderInset;

  /// Reports a settled or cancelled request. Neither is retried.
  final ValueChanged<int>? onRevealComplete;

  /// Publishes local row geometry after layout and scrolling.
  final ValueChanged<IndexedViewportLayout>? onLayout;

  /// Reports the first visible logical row for sticky headers.
  final ValueChanged<int>? onFirstRow;

  /// Reports visible logical rows as a half-open range after layout.
  final void Function(int start, int end)? onVisibleRange;

  /// Uses Flutter's direct indexed sliver when every row has estimatedHeight.
  final bool fixedHeight;

  /// Row identities kept alive during ordinary scrolling, such as the two
  /// endpoints of a text selection. Clear on source changes or explicit jumps.
  final Set<Object> retainedRows;
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
  bool _programmaticScroll = false;
  bool _revealIssued = false;
  ({int row, double within})? _restoringAnchor;

  bool get _hasPendingReveal {
    final row = widget.revealRow;
    return _activeReveal != null ||
        (row != null && _lastReveal != (widget.revealRequest, row));
  }

  void _restoreAnchor(int row, double within) {
    _restoringAnchor = (row: row, within: within);
    final generation = _generation;
    final command = (widget.revealRequest, widget.revealRow);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          _restoringAnchor == null ||
          _hasPendingReveal ||
          command != (widget.revealRequest, widget.revealRow)) {
        return;
      }
      _jump(row, within);
    });
  }

  (int, int)? _lastReveal;
  ({
    int request,
    int row,
    int? header,
    double inset,
    Object key,
    ScrollController controller,
  })?
  _activeReveal;
  bool _queued = false;
  bool _rangeQueued = false;
  (int, int)? _reportedRange;
  final Map<int, double> _measurements = {};
  double get _offset => widget.controller.hasClients
      ? widget.controller.offset
      : widget.controller.initialScrollOffset;
  void _reset() {
    _restoringAnchor = null;
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
      // Extend a screen upward. The sliver remaps its retained children and
      // their local offsets instead of replacing the list and every row.
      _base = _heights.rowAt(math.max(0, offset - _cache - _extent));
    }
    _rebase = false;
    _rangeOffset = offset;
    _anchor = widget.identity(_visible);
    _within = _offset - _heights.offsetFor(_visible);
    _reportRange();
  }

  void _reportRange() {
    if ((widget.onVisibleRange == null &&
            widget.onLayout == null &&
            !_revealIssued &&
            _restoringAnchor == null) ||
        _rangeQueued) {
      return;
    }
    _rangeQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rangeQueued = false;
      if (!mounted) return;
      widget.onLayout?.call(
        IndexedViewportLayout._(
          _heights,
          _laidOut,
          _measure,
          widget.padding.resolve(TextDirection.ltr).top,
          _extent,
        ),
      );
      if (_measurements.isEmpty && !_queued) {
        if (_revealIssued) _completeReveal();
        _restoringAnchor = null;
      }
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
    if (!_programmaticScroll) {
      _completeReveal();
      _restoringAnchor = null;
    }
    final base = _base;
    _range();
    if (!widget.fixedHeight && _base != base && mounted) setState(() {});
    widget.onFirstRow?.call(_visible);
  }

  void _measure(int index, double height) {
    if (!mounted || index >= widget.count || !height.isFinite || height < 0) {
      return;
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushMeasurements());
  }

  void _flushMeasurements() {
    _queued = false;
    if (!mounted || _measurements.isEmpty) return;
    final reveal = _revealIssued ? _activeReveal : null;
    final before = reveal == null
        ? null
        : _revealOffset(reveal.row, reveal.header, reveal.inset);
    var restoring = _restoringAnchor;
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
    if (restoring != null && _measurements.containsKey(restoring.row)) {
      final height =
          _heights.offsetFor(restoring.row + 1) -
          _heights.offsetFor(restoring.row);
      if (restoring.within >= height) {
        restoring = (
          row: restoring.row,
          within: math.max(0.0, height - _extent),
        );
        _restoringAnchor = restoring;
      }
    }
    _measurements.clear();
    if (reveal != null) {
      // While layout settles, the command's logical target is the anchor.
      // Wrapped rows can change the prefix between the viewport and target.
      correction =
          _revealOffset(reveal.row, reveal.header, reveal.inset) - before!;
    }
    if (reveal == null && restoring != null) {
      correction =
          _heights.offsetFor(restoring.row) + restoring.within - _offset;
    }
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
      _setOffset(
        (_offset + correction).clamp(0, _heights.offsetFor(widget.count)),
      );
    }
  }

  void _setOffset(double offset) {
    _programmaticScroll = true;
    try {
      widget.controller.jumpTo(offset);
    } finally {
      _programmaticScroll = false;
    }
  }

  void _completeReveal() {
    final command = _activeReveal;
    if (command == null) return;
    _activeReveal = null;
    _revealIssued = false;
    widget.onRevealComplete?.call(command.request);
  }

  void _requestReveal() {
    final row = widget.revealRow;
    if (row == null) {
      _completeReveal();
      return;
    }
    final key = (widget.revealRequest, row);
    if (_lastReveal == key) return;
    _completeReveal();
    _lastReveal = key;
    _restoringAnchor = null;
    final command = (
      request: widget.revealRequest,
      row: row,
      header: widget.revealHeaderRow,
      inset: widget.revealHeaderInset,
      key: widget.layoutKey,
      controller: widget.controller,
    );
    _activeReveal = command;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeReveal != command) return;
      if (widget.layoutKey != command.key ||
          widget.controller != command.controller ||
          widget.revealRow != command.row ||
          widget.revealRequest != command.request) {
        _completeReveal();
        return;
      }
      // All rows laid out this frame, including a needed offscreen header,
      // contribute to this one command before its offset is computed.
      _flushMeasurements();
      final offset = _revealOffset(command.row, command.header, command.inset);
      _revealIssued = true;
      _setOffset(
        offset.clamp(
          widget.controller.position.minScrollExtent,
          widget.controller.position.maxScrollExtent,
        ),
      );
      setState(_range);
    });
  }

  double _revealOffset(int row, int? header, double inset) {
    final clearance = header == null
        ? 0.0
        : math.max(
            0.0,
            _heights.offsetFor(header + 1) - _heights.offsetFor(header) - inset,
          );
    return widget.padding.resolve(TextDirection.ltr).top +
        _heights.offsetFor(row) -
        clearance;
  }

  void _jump(int index, [double within = 0]) {
    if (widget.count == 0 || !widget.controller.hasClients) return;
    final value = _heights.offsetFor(index.clamp(0, widget.count - 1)) + within;
    _setOffset(value.clamp(0, widget.controller.position.maxScrollExtent));
    setState(_range);
  }

  @override
  void initState() {
    super.initState();
    _reset();
    _range();
    widget.controller.addListener(_scroll);
    _requestReveal();
  }

  @override
  void didUpdateWidget(IndexedCodeViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _completeReveal();
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
      if (index != null && !_hasPendingReveal) _restoreAnchor(index, within);
    }
    _requestReveal();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_width != null && _width != constraints.maxWidth) {
        final anchor = _restoringAnchor?.row ?? _visible;
        final within = _restoringAnchor?.within ?? _within;
        final height = widget.count == 0
            ? null
            : _heights.offsetFor(anchor + 1) - _heights.offsetFor(anchor);
        _reset();
        if (height != null) _heights.measure(anchor, height);
        if (!_hasPendingReveal) _restoreAnchor(anchor, within);
      }
      _width = constraints.maxWidth;
      _extent = constraints.maxHeight.isFinite ? constraints.maxHeight : 600;
      _range();
      final activeCount = widget.count - _base;
      final retainedBeforeBase = <int>[
        if (!widget.fixedHeight)
          for (final identity in widget.retainedRows)
            if (widget.indexOf(identity) case final index?
                when index >= 0 &&
                    index < _base &&
                    index < widget.count &&
                    widget.identity(index) == identity)
              index,
      ]..sort();
      final scrollView = CustomScrollView(
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
                      (context, index) => _RetainedRow(
                        key: ValueKey(widget.identity(index)),
                        index: index,
                        retained: widget.retainedRows.contains(
                          widget.identity(index),
                        ),
                        child: widget.builder(context, index),
                      ),
                      childCount: widget.count,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<Object>) return null;
                        final identity = key.value;
                        final index = widget.indexOf(identity);
                        return index == null ||
                                index < 0 ||
                                index >= widget.count ||
                                widget.identity(index) != identity
                            ? null
                            : index;
                      },
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                      addSemanticIndexes: false,
                    ),
                  )
                : SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: _heights.offsetFor(_base)),
                      ),
                      _RowList(
                        key: ValueKey(_restarts),
                        firstRow: _base,
                        activeCount: activeCount,
                        offsetFor: (local) =>
                            _heights.offsetFor(_base + local) -
                            _heights.offsetFor(_base),
                        remainingAfter: (local) =>
                            _heights.offsetFor(widget.count) -
                            _heights.offsetFor(
                              math.min(widget.count, _base + local + 1),
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, local) {
                            final index = local < activeCount
                                ? _base + local
                                : retainedBeforeBase[local - activeCount];
                            return _RetainedRow(
                              key: ValueKey(widget.identity(index)),
                              index: index,
                              retained: widget.retainedRows.contains(
                                widget.identity(index),
                              ),
                              child: MeasuredCodeRow(
                                generation: _generation,
                                onSize: (size) => _measure(index, size.height),
                                child: widget.builder(context, index),
                              ),
                            );
                          },
                          childCount: activeCount + retainedBeforeBase.length,
                          findChildIndexCallback: (key) {
                            if (key is! ValueKey<Object>) return null;
                            final identity = key.value;
                            final index = widget.indexOf(identity);
                            // indexOf may return a nearby reveal anchor when a
                            // row disappeared. Only an exact match can reuse
                            // the element; fallback anchors may collide.
                            if (index == null ||
                                index < 0 ||
                                index >= widget.count ||
                                widget.identity(index) != identity) {
                              return null;
                            }
                            if (index >= _base) return index - _base;
                            final parked = retainedBeforeBase.indexOf(index);
                            return parked < 0 ? null : activeCount + parked;
                          },
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          addSemanticIndexes: false,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
      final header = _activeReveal?.header;
      final lastCached = _heights.rowAt(_offset + _extent + _cache);
      final needsHeader =
          header != null &&
          !_laidOut.contains(header) &&
          (header < _base || header > lastCached);
      return Stack(
        children: [
          scrollView,
          if (needsHeader)
            Offstage(
              child: Padding(
                padding: EdgeInsets.only(
                  left: widget.padding.resolve(TextDirection.ltr).left,
                  right: widget.padding.resolve(TextDirection.ltr).right,
                ),
                child: MeasuredCodeRow(
                  generation: _generation,
                  onSize: (size) => _measure(header, size.height),
                  child: widget.builder(context, header),
                ),
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
    required this.firstRow,
    required this.activeCount,
    required this.offsetFor,
  });

  final int firstRow;
  final int activeCount;
  final double Function(int local) offsetFor;

  @override
  RenderSliverList createRenderObject(BuildContext context) => _IndexedRowList(
    childManager: context as SliverMultiBoxAdaptorElement,
    firstRow: firstRow,
    activeCount: activeCount,
    offsetFor: offsetFor,
  );

  @override
  void updateRenderObject(BuildContext context, _IndexedRowList renderObject) {
    renderObject
      ..offsetFor = offsetFor
      ..activeCount = activeCount
      ..firstRow = firstRow
      ..refreshOffsets();
  }

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

/// SliverList remaps children by key but clears their old local offsets when
/// the base changes. Restore those offsets from the shared height index before
/// layout, so extending the list upward can keep its existing row elements.
class _IndexedRowList extends RenderSliverList {
  _IndexedRowList({
    required super.childManager,
    required int firstRow,
    required int activeCount,
    required this.offsetFor,
  }) : _firstRow = firstRow,
       _activeCount = activeCount;

  int _firstRow;
  int _activeCount;
  bool _reanchor = false;
  double Function(int) offsetFor;

  /// Measurements can change the prefix even without moving the first row.
  void refreshOffsets() {
    _reanchor = true;
    markNeedsLayout();
  }

  set firstRow(int value) {
    if (value == _firstRow) return;
    _firstRow = value;
    _reanchor = true;
    markNeedsLayout();
  }

  set activeCount(int value) {
    if (value == _activeCount) return;
    _activeCount = value;
    markNeedsLayout();
  }

  @override
  bool addInitialChild({int index = 0, double layoutOffset = 0.0}) {
    if (index >= _activeCount) return false;
    return super.addInitialChild(index: index, layoutOffset: layoutOffset);
  }

  @override
  RenderBox? insertAndLayoutChild(
    BoxConstraints childConstraints, {
    required RenderBox? after,
    bool parentUsesSize = false,
  }) {
    final nextIndex = after == null ? 0 : indexOf(after) + 1;
    if (nextIndex >= _activeCount) return null;
    return super.insertAndLayoutChild(
      childConstraints,
      after: after,
      parentUsesSize: parentUsesSize,
    );
  }

  @override
  void performLayout() {
    var trailingParked = 0;
    for (
      var child = lastChild;
      child != null && indexOf(child) >= _activeCount;
      child = childBefore(child)
    ) {
      trailingParked++;
    }
    if (trailingParked > 0) {
      collectGarbage(0, trailingParked);
    }
    if (_reanchor) {
      for (var child = firstChild; child != null; child = childAfter(child)) {
        final data = child.parentData! as SliverMultiBoxAdaptorParentData;
        data.layoutOffset = offsetFor(indexOf(child));
      }
      _reanchor = false;
    }
    super.performLayout();
  }
}

class _RetainedRow extends StatelessWidget {
  const _RetainedRow({
    super.key,
    required this.index,
    required this.retained,
    required this.child,
  });

  final int index;
  final bool retained;
  final Widget child;

  @override
  Widget build(BuildContext context) => KeepAlive(
    keepAlive: retained,
    // AutomaticKeepAlive also inserts Flutter's selection registrar, which
    // would retain every selected row. This viewport owns retention explicitly.
    child: IndexedSemantics(
      index: index,
      child: RepaintBoundary(child: child),
    ),
  );
}

/// A stable layout measurement boundary; it does not depend on reveal state.
class MeasuredCodeRow extends SingleChildRenderObjectWidget {
  /// Reports a child's local layout size for each layout generation.
  const MeasuredCodeRow({
    super.key,
    required this.generation,
    required this.onSize,
    required super.child,
  });

  /// The viewport's count of height resets; a new one measures the row
  /// again even when nothing else about it changed.
  final int generation;

  /// Receives the untransformed local size.
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureBox(onSize, generation);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _MeasureBox)
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
