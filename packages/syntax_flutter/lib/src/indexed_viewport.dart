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
  Object? get _anchor => _measuredLayout.reader;
  double _within = 0;
  bool _programmaticScroll = false;
  ({int row, double within})? _restoringAnchor;

  bool get _hasPendingReveal {
    final row = widget.revealRow;
    return _activeReveal != null ||
        (row != null && _lastReveal != (widget.revealRequest, row));
  }

  void _restoreAnchor(int row, double within) {
    _restoringAnchor = (row: row, within: within);
    _queueLayout();
  }

  (int, int)? _lastReveal;
  _IndexedReveal? _activeReveal;
  bool _layoutQueued = false;
  // Retain measured provenance across resets, but capture the current reader
  // synchronously with the anchor. There is only one reader identity, so a
  // scroll before the next post-frame callback cannot leave continuity stale.
  ({Object? key, Object? reader}) _measuredLayout = (key: null, reader: null);

  bool get _hasPriorGeometry {
    final measured = _measuredLayout;
    if (measured.key == null) return false;
    if (measured.key == widget.layoutKey) return true;
    final reader = _anchor;
    final row = reader == null ? null : widget.indexOf(reader);
    return row != null && row >= 0 && row < widget.count;
  }

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

  double get _paddingTop => widget.padding.resolve(TextDirection.ltr).top;
  double _rowOffset(int row) => _paddingTop + _heights.offsetFor(row);
  int _rowAt(double offset) =>
      _heights.rowAt(math.max(0, offset - _paddingTop));

  void _range() {
    if (widget.count == 0) {
      _visible = _base = 0;
      return;
    }
    final offset = _offset;
    _visible = _rowAt(offset);
    final first = _rowAt(offset - _cache);
    // A jump past everything built starts a new list at the target instead
    // of building every row in between.
    final jumped = (offset - _rangeOffset).abs() > _extent + 2 * _cache;
    if (_rebase || jumped || _base >= widget.count) {
      _base = first;
    } else if (first < _base) {
      // Extend a screen upward. The sliver remaps its retained children and
      // their local offsets instead of replacing the list and every row.
      _base = _rowAt(offset - _cache - _extent);
    }
    _rebase = false;
    _rangeOffset = offset;
    _measuredLayout = (
      key: _hasPriorGeometry ? _measuredLayout.key : null,
      reader: widget.identity(_visible),
    );
    _within = _offset - _rowOffset(_visible);
    _queueLayout();
  }

  // The sole post-layout owner of measurements, motion and notifications.
  // Scroll listeners collect input; they never settle another operation.
  void _queueLayout() {
    if (_layoutQueued) return;
    _layoutQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutQueued = false;
      if (mounted) _finishLayout();
    });
  }

  void _finishLayout() {
    final changed = _flushMeasurements();
    if (widget.count > 0 && (widget.fixedHeight || _laidOut.isNotEmpty)) {
      _measuredLayout = (key: widget.layoutKey, reader: _anchor);
    }
    final restoring = _restoringAnchor;
    var moved = false;
    if (restoring != null && !_hasPendingReveal) {
      final before = _offset;
      _jump(restoring.row, restoring.within);
      moved = before != _offset;
    }
    final command = _activeReveal;
    if (command != null && widget.controller.hasClients) {
      if (widget.layoutKey != command.key ||
          widget.controller != command.controller ||
          widget.revealRow != command.row ||
          widget.revealRequest != command.request) {
        _completeReveal();
      } else if (!command.positioned) {
        command.positioned = true;
        final before = _offset;
        _setOffset(
          _revealOffset(command.row, command.header, command.inset).clamp(
            widget.controller.position.minScrollExtent,
            widget.controller.position.maxScrollExtent,
          ),
        );
        moved = before != _offset;
        setState(_range);
      }
    }
    widget.onLayout?.call(
      IndexedViewportLayout._(
        _heights,
        _laidOut,
        _measure,
        widget.padding.resolve(TextDirection.ltr).top,
        _extent,
      ),
    );
    if (!changed && !moved && _measurements.isEmpty) {
      _restoringAnchor = null;
      if (_activeReveal?.positioned ?? false) _completeReveal();
    }
    final end = (_rowAt(_offset + _extent) + 1).clamp(0, widget.count);
    final range = (_visible, end);
    if (range != _reportedRange) {
      _reportedRange = range;
      widget.onVisibleRange?.call(range.$1, range.$2);
    }
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
    _queueLayout();
  }

  bool _flushMeasurements() {
    if (_measurements.isEmpty) return false;
    final reveal = (_activeReveal?.positioned ?? false) ? _activeReveal : null;
    final before = reveal == null
        ? null
        : _revealOffset(reveal.row, reveal.header, reveal.inset);
    var restoring = _restoringAnchor;
    final anchor = _rowAt(_offset);
    final within = _offset - _rowOffset(anchor);
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
    // Restoration uses an absolute row offset below, after all measurements.
    // First-layout estimates have never described the reader's position.
    if (restoring != null || (!_hasPriorGeometry && reveal == null)) {
      correction = 0;
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
    return true;
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
    final command = _IndexedReveal(
      request: widget.revealRequest,
      row: row,
      header: widget.revealHeaderRow,
      inset: widget.revealHeaderInset,
      key: widget.layoutKey,
      controller: widget.controller,
    );
    _activeReveal = command;
    _queueLayout();
  }

  double _revealOffset(int row, int? header, double inset) {
    final clearance = header == null
        ? 0.0
        : math.max(
            0.0,
            _heights.offsetFor(header + 1) - _heights.offsetFor(header) - inset,
          );
    return _rowOffset(row) - clearance;
  }

  void _jump(int index, [double within = 0]) {
    if (widget.count == 0 || !widget.controller.hasClients) return;
    final value = _rowOffset(index.clamp(0, widget.count - 1)) + within;
    final offset = value.clamp(0.0, widget.controller.position.maxScrollExtent);
    if ((_offset - offset).abs() < .1) return;
    _setOffset(offset);
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
      final established = _hasPriorGeometry;
      final anchor = _anchor;
      final within = _within;
      final index = anchor == null ? null : widget.indexOf(anchor);
      final height = oldWidget.count == 0
          ? null
          : _heights.offsetFor(_visible + 1) - _heights.offsetFor(_visible);
      _reset();
      if (!widget.fixedHeight && index != null && height != null) {
        _heights.measure(index, height);
      }
      _range();
      if (established && index != null && !_hasPendingReveal) {
        // A removed row navigates to its replacement header. Keep leading
        // padding visible when that header is the first row in the viewport.
        _restoreAnchor(
          index,
          widget.identity(index) == anchor
              ? within
              : index == 0
              ? -_paddingTop
              : 0,
        );
      }
    }
    _requestReveal();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_width != null && _width != constraints.maxWidth) {
        final established = _hasPriorGeometry;
        final anchor = _restoringAnchor?.row ?? _visible;
        final within = _restoringAnchor?.within ?? _within;
        final height = widget.count == 0
            ? null
            : _heights.offsetFor(anchor + 1) - _heights.offsetFor(anchor);
        _reset();
        if (!widget.fixedHeight && height != null) {
          _heights.measure(anchor, height);
        }
        if (established && !_hasPendingReveal) _restoreAnchor(anchor, within);
      }
      _width = constraints.maxWidth;
      _extent = constraints.maxHeight.isFinite ? constraints.maxHeight : 600;
      _range();
      final activeCount = widget.count - _base;
      final retainedBeforeBase = <int>[];
      if (!widget.fixedHeight) {
        for (final identity in widget.retainedRows) {
          final index = widget.indexOf(identity);
          if (index != null &&
              index >= 0 &&
              index < _base &&
              index < widget.count &&
              widget.identity(index) == identity) {
            retainedBeforeBase.add(index);
          }
        }
        retainedBeforeBase.sort();
      }
      final padding = widget.padding.resolve(Directionality.of(context));
      final scrollView = CustomScrollView(
        controller: widget.controller,
        physics: widget.physics,
        // Supported by the package's minimum Flutter SDK.
        // ignore: deprecated_member_use
        cacheExtent: _cache,
        slivers: [
          // Keep the spacer and row list as viewport siblings. Older
          // SliverMainAxisGroup versions discard the leading cache origin
          // after a spacer, causing retained rows to drift on a distant rebase.
          if (!widget.fixedHeight)
            SliverPadding(
              padding: EdgeInsets.only(top: padding.top),
              sliver: SliverToBoxAdapter(
                child: SizedBox(height: _heights.offsetFor(_base)),
              ),
            ),
          SliverPadding(
            padding: widget.fixedHeight
                ? widget.padding
                : EdgeInsets.only(
                    left: padding.left,
                    right: padding.right,
                    bottom: padding.bottom,
                  ),
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
                : _RowList(
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
          ),
        ],
      );
      final header = _activeReveal?.header;
      final lastCached = _rowAt(_offset + _extent + _cache);
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

// A reveal owns its phase; notification callbacks cannot retire a queued jump.
class _IndexedReveal {
  _IndexedReveal({
    required this.request,
    required this.row,
    required this.header,
    required this.inset,
    required this.key,
    required this.controller,
  });
  final int request;
  final int row;
  final int? header;
  final double inset;
  final Object key;
  final ScrollController controller;
  bool positioned = false;
}
