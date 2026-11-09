import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

import 'chrome.dart';
import 'diff_context.dart';
import 'diff_text_selection.dart';
import 'highlighter_scope.dart';
import 'highlight_scheduler.dart';
import 'patch_highlights.dart';
import 'horizontal_scroll.dart';
import 'indexed_viewport.dart';
import 'patch_rows.dart';
import 'patch_controller.dart';
import 'selectable_region.dart';
import 'selection_chrome.dart';
import 'styles.dart';
import 'patch_line_endings.dart';

part 'patch_composition.dart';
part 'patch_selection.dart';

/// A syntax-highlighted view of code changes.
///
/// Show a `git diff` with [PatchView.fromPatch], compare two versions of a
/// file with [PatchView.fromTexts], or pass [FileDiff]s directly. Each file
/// with a path gets a header with its status and change counts, which
/// reports [onToggleFile] when tapped. Lines show old and new line numbers,
/// the changed words inside edited lines are highlighted, and colors come
/// from [theme]'s diff colors. Long lines wrap unless [wrap] is false. Code
/// reads left to right even in a right-to-left app.
class PatchView<T> extends StatefulWidget {
  /// Shows [files] as they are, with [collapsed] files and [expanded] gaps
  /// owned by the caller.
  const PatchView({
    super.key,
    required List<FileDiff> files,
    required this.theme,
    this.highlighter,
    this.executor,
    this.language,
    DiffMode mode = DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
    this.textStyle,
    this.selectable = true,
    this.selectionChrome,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(12),
    this.labels = const DiffLabels(),
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.wrap = true,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.scrollController,
    this.leading,
    this.canvasColor,
    this.sectionDecoration,
    this.fileLabelBuilder,
    this.fileFooterBuilder,
    this.rowBelowBuilder,
    this.gutterBuilder,
    this.selectionActionBuilder,
    this.onSelectionChanged,
    this.onVisibleRange,
    this.annotations = const [],
  }) : controller = null,
       _mode = mode,
       _files = files,
       _patch = null,
       _texts = null;

  /// Shows caller-owned patch state, rebuilding when the controller changes.
  ///
  /// The controller owns mode, file/hunk folding, context expansion, selection,
  /// annotations and reveal.
  /// Caller-owned folding parameters belong to the source constructors only.
  /// The owner must dispose the controller after the view stops using it.
  const PatchView.controlled({
    super.key,
    required PatchController<T> this.controller,
    required this.theme,
    this.highlighter,
    this.executor,
    this.language,
    this.textStyle,
    this.selectable = true,
    this.selectionChrome,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(12),
    this.labels = const DiffLabels(),
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.wrap = true,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.scrollController,
    this.leading,
    this.canvasColor,
    this.sectionDecoration,
    this.fileLabelBuilder,
    this.fileFooterBuilder,
    this.rowBelowBuilder,
    this.gutterBuilder,
    this.selectionActionBuilder,
    this.onSelectionChanged,
    this.onVisibleRange,
  }) : annotations = const [],
       _mode = DiffMode.unified,
       collapsed = const {},
       expanded = const {},
       onToggleFile = null,
       onExpandGap = null,
       _files = null,
       _patch = null,
       _texts = null;

  /// Shows a unified diff, such as the output of `git diff`.
  const PatchView.fromPatch(
    String patch, {
    super.key,
    required this.theme,
    this.highlighter,
    this.executor,
    this.language,
    DiffMode mode = DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
    this.textStyle,
    this.selectable = true,
    this.selectionChrome,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(12),
    this.labels = const DiffLabels(),
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.wrap = true,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.scrollController,
    this.leading,
    this.canvasColor,
    this.sectionDecoration,
    this.fileLabelBuilder,
    this.fileFooterBuilder,
    this.rowBelowBuilder,
    this.gutterBuilder,
    this.selectionActionBuilder,
    this.onSelectionChanged,
    this.onVisibleRange,
    this.annotations = const [],
  }) : controller = null,
       _mode = mode,
       _files = null,
       _patch = patch,
       _texts = null;

  /// Shows the changes from [oldText] to [newText], with [contextLines]
  /// unchanged lines around each change.
  const PatchView.fromTexts({
    super.key,
    required String oldText,
    required String newText,
    String path = '',
    int contextLines = 3,
    required this.theme,
    this.highlighter,
    this.executor,
    this.language,
    DiffMode mode = DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
    this.textStyle,
    this.selectable = true,
    this.selectionChrome,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(12),
    this.labels = const DiffLabels(),
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.wrap = true,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.scrollController,
    this.leading,
    this.canvasColor,
    this.sectionDecoration,
    this.fileLabelBuilder,
    this.fileFooterBuilder,
    this.rowBelowBuilder,
    this.gutterBuilder,
    this.selectionActionBuilder,
    this.onSelectionChanged,
    this.onVisibleRange,
    this.annotations = const [],
  }) : controller = null,
       _mode = mode,
       _files = null,
       _patch = null,
       _texts = (oldText, newText, path, contextLines);

  /// Caller-owned state for a controlled view, or null for source constructors.
  final PatchController<T>? controller;

  final List<FileDiff>? _files;
  final String? _patch;
  final (String, String, String, int)? _texts;

  /// Colors for code, line backgrounds and changed words.
  final SyntaxTheme theme;

  /// Defaults to the nearest [HighlighterScope].
  final Highlighter? highlighter;

  /// Optional executor for visible syntax windows, such as a worker isolate.
  /// Calls are serialized across files and both sides of parsed/full diffs.
  /// Without one, large files use cooperative window highlighting.
  final HighlightExecutor? executor;

  /// The language of every file, by name or alias, or `null` to guess from path.
  final String? language;

  /// Whether changes are shown in one column or side by side.
  DiffMode get mode => controller?.mode ?? _mode;
  final DiffMode _mode;

  /// Zero-based indices of files whose lines are hidden.
  final Set<int> collapsed;

  /// Context gaps whose unchanged lines are shown.
  final Set<DiffGapId> expanded;

  /// Called when a file header is tapped or activated.
  final ValueChanged<int>? onToggleFile;

  /// Called when a collapsed context gap is tapped or activated.
  final ValueChanged<DiffGapId>? onExpandGap;

  /// Base style for code and line numbers. Defaults to [defaultCodeTextStyle].
  final TextStyle? textStyle;

  /// Allows selecting and copying code. Line numbers and markers are excluded.
  final bool selectable;

  /// Selection handles, menus, row actions and missing-newline markers.
  ///
  /// Defaults to widgets-only controls that need no app theme or icon font.
  final SyntaxSelectionChrome? selectionChrome;

  /// Sizes the view to its content, for use inside another scroll view.
  final bool shrinkWrap;

  /// Passed to the underlying scroll view.
  final ScrollPhysics? physics;

  /// Space around the files, inside the scroll view.
  final EdgeInsetsGeometry padding;

  /// The words the view shows and announces. Extend [DiffLabels] to translate.
  final DiffLabels labels;

  /// Algorithm for highlighting inline changes.
  final InlineDiffMode inlineDiffMode;

  /// Wraps long lines; false enables synchronized horizontal scrolling.
  final bool wrap;

  /// Paints added and removed line backgrounds.
  final bool showBackgrounds;

  /// Displays addition and removal markers in gutters.
  final bool showChangeIndicators;

  /// Marker style; [showChangeIndicators] can disable every marker.
  final DiffIndicators indicators;

  /// Shows old/new source numbers in gutters.
  final bool showLineNumbers;

  /// Built-in styling for unchanged gaps and section metadata.
  final HunkSeparatorStyle hunkSeparatorStyle;

  /// Keeps the current file header visible above the scroll viewport.
  final bool stickyHeaders;

  /// Replaces a file header; invoke the supplied callback to fold the file.
  final Widget Function(BuildContext, FileDiff, bool, VoidCallback)?
  headerBuilder;

  /// Replaces a hunk separator.
  final Widget Function(BuildContext, FileDiff, DiffHunk)? hunkBuilder;

  /// Optional controller for the underlying vertical viewport.
  final ScrollController? scrollController;

  /// Introduction that scrolls before the first file and its pinned header.
  final Widget? leading;

  /// Color behind file sections and the introduction.
  final Color? canvasColor;

  /// Decoration sliced across individual rows, preserving virtualization.
  ///
  /// Borders and corner radii join at file boundaries and pinned headers.
  /// Gradients and images are painted separately for each row.
  final BoxDecoration? sectionDecoration;

  /// Optional label below the file's header content, including pinned copies.
  final Widget? Function(BuildContext, FileDiff)? fileLabelBuilder;

  /// Optional content after every file, including collapsed and binary files.
  final Widget? Function(BuildContext, FileDiff, bool)? fileFooterBuilder;

  /// Optional application content below a source row, outside copied code.
  ///
  /// The source row's stable identity owns the slot and its measured height.
  /// Drafts can be annotation payloads independent of the current selection.
  final Widget? Function(BuildContext, DiffRowContext<T>)? rowBelowBuilder;

  /// Optional marker reserving 24 pixels even when it returns null.
  ///
  /// Unified context rows offer the newer side; split rows offer each side.
  final Widget? Function(BuildContext, DiffLineContext)? gutterBuilder;

  /// Optional action below the active endpoint of a directed line selection.
  final Widget? Function(BuildContext, DiffSelectionDetails)?
  selectionActionBuilder;

  /// Reports directed gutter selections and clearing by native text selection.
  final ValueChanged<DiffSelection?>? onSelectionChanged;

  /// Visible logical rows, half-open, forwarded from [IndexedCodeViewport].
  /// Includes a leading row when [leading] is supplied.
  final void Function(int start, int end)? onVisibleRange;

  /// Application-owned row payloads for source constructors. Controlled views
  /// use [PatchController.annotations]. Stale revisions are never rendered.
  final List<DiffAnnotation<T>> annotations;

  @override
  State<PatchView<T>> createState() => _PatchViewState<T>();
}

const _sliceBudget = Duration(milliseconds: 6);

class _PatchViewState<T> extends State<PatchView<T>>
    with SingleTickerProviderStateMixin {
  late ScrollController _scroll;
  int? _stickyFile;
  final _nativeSelection = DiffTextSelection();
  final _lineFocus = FocusNode();
  final _gutterCells = <(int, DiffSide, int), BuildContext>{};
  final _annotationsByLine =
      <(String, DiffSide, int), List<DiffAnnotation<T>>>{};
  void _rebuild(VoidCallback callback) => setState(callback);
  DiffSelection? _localSelection;
  DiffSelection? get _selection => widget.controller == null
      ? _localSelection
      : widget.controller!.selection;
  DiffSelection? _reportedSelection;

  bool _isCollapsed(int index) =>
      widget.controller?.isCollapsed(_files[index].id) ??
      widget.collapsed.contains(index);
  (FileDiff, DiffSelection)? _crossKey;
  ({DiffLayout layout, int start, int end})? _crossBounds;
  DiffSelection? _copiedSelection;
  String? _copiedText;
  final _lineEndings = <FileDiff, PatchLineEndings>{};
  DiffLineContext? _dragAnchor;
  Offset? _pointer;
  late final Ticker _autoScroll = createTicker(_scrollTick);
  Duration _lastTick = Duration.zero;
  Object? _sourceKey, _highlightKey;
  List<FileDiff> _files = const [];
  final _horizontal = HorizontalCodeGroup();
  DiffHighlightCache? _highlights;
  bool _slicing = false;
  PatchPalette? _palette;
  HighlightWindowScheduler? _windows;
  PatchWindowHighlights? _windowHighlights;
  Object? _windowKey;
  bool _repaintScheduled = false;
  List<DiffRow> _geometryRows = const [];
  int _leadingCount = 0;
  final _headerRows = <int, int?>{};
  IndexedViewportLayout? _indexedLayout;
  int? _pinnedFile;
  bool _stickyBounded = false;
  bool _ownShrinkScroll = false;
  bool _shrinkLayoutQueued = false;
  // Only this key has actual shrink-row measurements. Rebuilding the index
  // does not erase history or turn its new estimates into measured geometry.
  Object? _shrinkMeasuredLayoutKey;
  (int, int)? _shrinkReportedRange;
  Object? _shrinkLayoutKey;
  RowHeightIndex _shrinkHeights = RowHeightIndex(0);
  int _shrinkGeneration = 0;
  final _shrinkMeasurements = <int, double>{};
  final _shrinkContexts = <int, BuildContext>{};
  _ShrinkAnchor? _shrinkAnchor;

  _ShrinkAnchor? _captureShrinkAnchor() {
    if (_shrinkMeasuredLayoutKey == null ||
        _shrinkMeasuredLayoutKey != _shrinkLayoutKey ||
        !_scroll.hasClients ||
        _shrinkHeights.length == 0 ||
        _geometryRows.isEmpty) {
      return null;
    }
    ScrollableState? ancestor;
    var position = _scroll.position;
    var localOffset = _scroll.offset;
    var scale = 1.0;
    if (!_stickyBounded) {
      ancestor = Scrollable.maybeOf(context, axis: Axis.vertical);
      final first = _shrinkContexts[0]?.findRenderObject();
      final viewport = RenderAbstractViewport.maybeOf(
        context.findRenderObject()!,
      );
      if (ancestor == null || first == null || viewport is! RenderBox) {
        return null;
      }
      position = ancestor.position;
      final transform = first.getTransformTo(viewport);
      scale =
          MatrixUtils.transformPoint(transform, const Offset(0, 1)).dy -
          MatrixUtils.transformPoint(transform, Offset.zero).dy;
      if (scale <= 0 || !scale.isFinite) return null;
      localOffset =
          _topPadding -
          MatrixUtils.transformPoint(transform, Offset.zero).dy / scale;
    }
    final row = _shrinkHeights.rowAt(math.max(0, localOffset - _topPadding));
    final source = row - _leadingCount;
    if (source >= _geometryRows.length) return null;
    return (
      identity: source < 0 ? 'leading' : _identity(_geometryRows[source]),
      within: localOffset - _shrinkOffset(row),
      owner: ancestor ?? _scroll,
      pixels: position.pixels,
      localOffset: localOffset,
      scale: scale,
    );
  }

  void _restoreShrinkAnchor() {
    final anchor = _shrinkAnchor;
    _shrinkAnchor = null;
    if (anchor == null || !_scroll.hasClients || _shrinkReveal != null) {
      return;
    }
    final row = anchor.identity == 'leading'
        ? (_leadingCount == 1 ? 0 : null)
        : switch (_indexOf(anchor.identity, _geometryRows)) {
            final source? => source + _leadingCount,
            _ => null,
          };
    if (row == null) return;
    // Scrollable may replace its position when physics changes in this build.
    // Resolve from the owner after layout, never from a detached snapshot.
    final position = switch (anchor.owner) {
      ScrollController controller when controller.hasClients =>
        controller.position,
      ScrollableState scrollable when scrollable.mounted => scrollable.position,
      _ => null,
    };
    if (position == null ||
        !position.hasPixels ||
        position.pixels != anchor.pixels) {
      return;
    }
    final height = _shrinkHeight(row);
    final within = anchor.within >= height
        ? math.max(0.0, height - position.viewportDimension / anchor.scale)
        : anchor.within;
    final destination =
        anchor.pixels +
        (_shrinkOffset(row) + within - anchor.localOffset) * anchor.scale;
    _ownShrinkScroll = true;
    try {
      if ((destination - position.pixels).abs() >= .1) {
        position.jumpTo(
          destination.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
    } finally {
      _ownShrinkScroll = false;
    }
  }

  bool get _controlledSticky =>
      widget.controller != null && widget.stickyHeaders;

  int? _headerForFile(int file) => _headerRows.putIfAbsent(file, () {
    final rows = _geometryRows;
    if (rows is! DiffLayout) return null;
    final row = rows.rowForFile(file);
    return row != null && rows[row] is DiffFileHeaderRow
        ? row + _leadingCount
        : null;
  });

  int? _headerForRow(int row) {
    final source = row - _leadingCount;
    return source < 0 || source >= _geometryRows.length
        ? null
        : _headerForFile(_geometryRows[source].file);
  }

  double _headerInset(int row) => row > _leadingCount ? 16 : 0;

  void _updatePinned(
    int Function(double) rowAt,
    double Function(int) offsetFor,
    double Function(int) heightFor,
  ) {
    if (!_controlledSticky ||
        !_stickyBounded ||
        !_scroll.hasClients ||
        _geometryRows.isEmpty) {
      return;
    }
    final row = rowAt(_scroll.offset);
    final header = _headerForRow(row);
    final source = row - _leadingCount;
    final pinned =
        header != null &&
            _scroll.offset >= offsetFor(header) + heightFor(header)
        ? _geometryRows[source].file
        : null;
    if (_pinnedFile != pinned) setState(() => _pinnedFile = pinned);
  }

  void _indexedGeometry(IndexedViewportLayout layout) {
    _indexedLayout = layout;
    _updatePinned(layout.rowAt, layout.offsetFor, layout.heightFor);
  }

  void _recordShrinkHeight(int row, double height) {
    if (row >= _shrinkHeights.length || !height.isFinite || height < 0) return;
    if ((_shrinkHeight(row) - height).abs() < .1) return;
    _shrinkMeasurements[row] = height;
    _queueShrinkLayout();
  }

  double get _topPadding => widget.padding.resolve(TextDirection.ltr).top;
  double _shrinkOffset(int row) => _topPadding + _shrinkHeights.offsetFor(row);
  double _shrinkHeight(int row) =>
      _shrinkHeights.offsetFor(row + 1) - _shrinkHeights.offsetFor(row);

  // One post-layout pipeline: measure -> restore -> reveal -> notify.
  // Initial estimates never establish a reader anchor.
  void _finishShrinkLayout() {
    if (_shrinkMeasurements.isNotEmpty && _shrinkReveal == null) {
      _shrinkAnchor ??= _captureShrinkAnchor();
    }
    for (final entry in _shrinkMeasurements.entries) {
      _shrinkHeights.measure(entry.key, entry.value);
    }
    _shrinkMeasurements.clear();
    _shrinkMeasuredLayoutKey = _shrinkLayoutKey;
    _restoreShrinkAnchor();
    _runShrinkReveal();
    _updatePinned(
      (offset) => _shrinkHeights.rowAt(math.max(0, offset - _topPadding)),
      _shrinkOffset,
      _shrinkHeight,
    );
    if (_scroll.hasClients && _stickyBounded) {
      final start = _shrinkHeights.rowAt(
        math.max(0, _scroll.offset - _topPadding),
      );
      final end =
          (_shrinkHeights.rowAt(
                    math.max(
                      0,
                      _scroll.offset +
                          _scroll.position.viewportDimension -
                          _topPadding,
                    ),
                  ) +
                  1)
              .clamp(0, _shrinkHeights.length);
      final range = (start, end);
      if (_shrinkReportedRange != range) {
        _shrinkReportedRange = range;
        widget.onVisibleRange?.call(start, end);
      }
    }
  }

  void _queueShrinkLayout() {
    if (_shrinkLayoutQueued) return;
    _shrinkLayoutQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shrinkLayoutQueued = false;
      if (mounted && widget.shrinkWrap && widget.controller != null) {
        _finishShrinkLayout();
      }
    });
  }

  void _scrollChanged() {
    if (!widget.shrinkWrap) return;
    if (!_ownShrinkScroll) {
      _shrinkAnchor = null;
      final token = _shrinkReveal?.token;
      if (token != null) _completeReveal(token);
    }
    _queueShrinkLayout();
  }

  void _completeReveal(int token) {
    if (token != _revealToken) return;
    _shrinkReveal = null;
    _completedRevealToken = token;
  }

  PatchController<T>? _revealController;
  int? _controllerRevealRequest;
  int _revealToken = 0;
  _ShrinkReveal? _shrinkReveal;
  int? _completedRevealToken;

  int? _pendingRevealRow() {
    final controller = widget.controller;
    final request = controller?.revealRequest ?? 0;
    // Serials belong to each controller; a replacement needs a fresh token
    // even when it requests the same row with the same controller serial.
    if (!identical(controller, _revealController) ||
        request != _controllerRevealRequest) {
      _revealController = controller;
      _controllerRevealRequest = request;
      _revealToken++;
    }
    // A completed command must not become navigation again when folding or
    // reordering changes its layout-dependent row index.
    return _completedRevealToken == _revealToken ? null : controller?.revealRow;
  }

  void _scheduleShrinkReveal(int row) {
    if (_shrinkReveal?.token == _revealToken) return;
    _shrinkReveal = _ShrinkReveal(
      _revealToken,
      row,
      _geometryRows,
      _scroll,
      _ancestorOffsets(_shrinkContexts[row] ?? context),
    );
    _shrinkAnchor = null;
    _queueShrinkLayout();
  }

  void _runShrinkReveal() {
    final command = _shrinkReveal;
    if (command == null) return;
    final token = command.token;
    final row = command.row;
    final sourceRow = row - _leadingCount;
    final target = _shrinkContexts[row];
    if (token != _revealToken ||
        !identical(command.rows, _geometryRows) ||
        command.controller != _scroll ||
        widget.controller?.revealRow != sourceRow ||
        target == null ||
        !target.mounted) {
      _completeReveal(token);
      return;
    }
    if (command.ancestorOffsets.entries.any((e) => e.key.pixels != e.value)) {
      _completeReveal(token);
      return;
    }
    _ownShrinkScroll = true;
    try {
      if (!command.positioned && _stickyBounded) {
        final header = _controlledSticky ? _headerForRow(row) : null;
        final clearance = header == null
            ? 0.0
            : math.max(0.0, _shrinkHeight(header) - _headerInset(header));
        final position = _scroll.position;
        final destination = (_shrinkOffset(row) - clearance).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((destination - position.pixels).abs() >= .1) {
          position.jumpTo(destination);
          final ancestors = _ancestorOffsets(target);
          if (ancestors.isNotEmpty) {
            // The next layout supplies current geometry to ancestor scrolling.
            command.positioned = true;
            _queueShrinkLayout();
            return;
          }
        }
      }
      _revealAncestors(target, skipInner: _stickyBounded);
    } finally {
      _ownShrinkScroll = false;
    }
    _completeReveal(token);
  }

  Map<ScrollPosition, double> _ancestorOffsets(BuildContext context) {
    final offsets = <ScrollPosition, double>{};
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final position = scrollable.position;
      if (position.axis == Axis.vertical &&
          !(_scroll.hasClients && identical(position, _scroll.position))) {
        offsets[position] = position.pixels;
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return offsets;
  }

  void _revealAncestors(BuildContext context, {required bool skipInner}) {
    final target = context.findRenderObject()!;
    var object = target;
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      if (scrollable.position.axis == Axis.vertical &&
          !(skipInner && identical(scrollable.position, _scroll.position))) {
        scrollable.position.ensureVisible(object, targetRenderObject: target);
      }
      final viewport = RenderAbstractViewport.maybeOf(object);
      final vertical = Scrollable.maybeOf(
        scrollable.context,
        axis: Axis.vertical,
      );
      final shared =
          viewport is RenderTwoDimensionalViewport &&
          identical(viewport.horizontalOffset, scrollable.position) &&
          identical(viewport.verticalOffset, vertical?.position);
      if (!shared) object = scrollable.context.findRenderObject()!;
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  void _highlightChanged() {
    if (!mounted || _repaintScheduled) return;
    _repaintScheduled = true;
    // Rebuild in the next frame's build phase, rather than waiting until its
    // end and leaving ready syntax colors plain for another frame.
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _repaintScheduled = false;
      if (mounted) setState(() {});
    });
  }

  PatchWindowHighlights _windowsFor(Highlighter highlighter) {
    final key = (
      highlighter,
      highlighter.revision,
      widget.theme,
      widget.language,
      widget.inlineDiffMode,
      widget.executor,
    );
    _windows ??= HighlightWindowScheduler(
      highlighter: highlighter,
      theme: widget.theme,
      executor: widget.executor ?? highlightWindowInFrames,
      onChanged: _highlightChanged,
      onResult: (result) => _windowHighlights?.accept(result),
    );
    _windowHighlights ??= PatchWindowHighlights(_windows!);
    if (key != _windowKey) {
      _windowKey = key;
      _windowHighlights!.clear();
      _windows!.configure(
        highlighter: highlighter,
        theme: widget.theme,
        executor: widget.executor ?? highlightWindowInFrames,
      );
    }
    return _windowHighlights!;
  }

  void _syncSource() {
    final key = (
      widget.controller?.files ?? widget._files,
      widget._patch,
      widget._texts,
    );
    if (key == _sourceKey) return;
    _sourceKey = key;
    // Parent rebuilds often supply a fresh list of the same source objects.
    // Preserve mounted windows rather than cancelling/restarting their work.
    if (key.$1 != null && listEquals(key.$1, _files)) return;
    // Release derived source indexes and abandon queued work for the previous
    // snapshot immediately. A late executor still settles serially.
    _windowHighlights?.clear();
    _highlights = null;
    _lineEndings.clear();
    _crossKey = null;
    _crossBounds = null;
    _copiedSelection = null;
    _copiedText = null;
    _files = switch (key) {
      (final files?, _, _) => files,
      (_, final patch?, _) => parsePatch(patch),
      (_, _, (final before, final after, final path, final context)?) => [
        diffTexts(before, after, path: path, contextLines: context),
      ],
      _ => const [],
    };
    _stickyFile = widget.leading == null ? 0 : null;
    _pinnedFile = null;
    _headerRows.clear();
    _geometryRows = const [];
    _indexedLayout = null;
    _shrinkLayoutKey = null;
    _shrinkMeasuredLayoutKey = null;
    _shrinkReportedRange = null;
    _shrinkAnchor = null;
    _shrinkMeasurements.clear();
    _shrinkContexts.clear();
    _localSelection = null;
    _stopDrag();
    _gutterCells.clear();
  }

  DiffHighlightCache _highlightsFor(Highlighter highlighter) {
    final key = (
      widget.theme,
      highlighter,
      highlighter.revision,
      widget.language,
      widget.inlineDiffMode,
    );
    if (key != _highlightKey || _highlights == null) {
      _highlightKey = key;
      _highlights = DiffHighlightCache(
        highlighter: highlighter,
        theme: widget.theme,
        language: widget.language,
        inlineDiffMode: widget.inlineDiffMode,
        maxEntries: 8,
        maxCodeUnits: 1024 * 1024,
      );
    }
    return _highlights!;
  }

  void _finishLater() {
    if (_slicing) return;
    _slicing = true;
    SchedulerBinding.instance
      ..addPostFrameCallback(_slice)
      ..ensureVisualUpdate();
  }

  void _slice(Duration _) {
    if (!mounted) return;
    final done = _highlights?.tokenize(budget: _sliceBudget) ?? true;
    setState(() {});
    if (done) {
      _slicing = false;
    } else {
      SchedulerBinding.instance.addPostFrameCallback(_slice);
    }
  }

  PatchPalette _paletteFor(BuildContext context) {
    final textStyle = widget.textStyle ?? defaultCodeTextStyle;
    final scaler = MediaQuery.textScalerOf(context);
    final effectiveIndicators = widget.showChangeIndicators
        ? widget.indicators
        : DiffIndicators.none;
    if (_palette case final p?
        when p.theme == widget.theme &&
            p.textStyle == textStyle &&
            p.scaler == scaler &&
            p.wrap == widget.wrap &&
            p.backgrounds == widget.showBackgrounds &&
            p.indicators == effectiveIndicators &&
            p.lineNumbers == widget.showLineNumbers) {
      return p;
    }
    return _palette = PatchPalette(
      widget.theme,
      textStyle,
      scaler,
      wrap: widget.wrap,
      backgrounds: widget.showBackgrounds,
      indicators: effectiveIndicators,
      lineNumbers: widget.showLineNumbers,
    );
  }

  void _reportSelection() {
    final selection = _selection;
    if (_reportedSelection == selection) return;
    _reportedSelection = selection;
    if (selection != null) _nativeSelection.beginGutter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reportedSelection == selection) {
        widget.onSelectionChanged?.call(selection);
      }
    });
  }

  void _controllerChanged() {
    setState(_syncSource);
    _reportSelection();
  }

  @override
  void initState() {
    super.initState();
    _scroll = widget.scrollController ?? ScrollController();
    _scroll.addListener(_scrollChanged);
    _nativeSelection.onBegin = () => _setSelection(null);
    _syncSource();
    widget.controller?.addListener(_controllerChanged);
    _reportSelection();
  }

  @override
  void didUpdateWidget(PatchView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_controllerChanged);
      widget.controller?.addListener(_controllerChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      _scroll.removeListener(_scrollChanged);
      if (oldWidget.scrollController == null) _scroll.dispose();
      _scroll = widget.scrollController ?? ScrollController();
      _scroll.addListener(_scrollChanged);
    }
    _syncSource();
    _reportSelection();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_controllerChanged);
    _autoScroll.dispose();
    _nativeSelection.dispose();
    _lineFocus.dispose();
    _windows?.dispose();
    _scroll.removeListener(_scrollChanged);
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  Object _identity(DiffRow row) {
    final id = _files[row.file].id;
    return switch (row) {
      DiffFileHeaderRow() => (id, 'file', 0),
      DiffHunkHeaderRow(:final hunk) => (id, 'hunk', hunk.newStart),
      DiffGapRow(:final id) => (_files[id.file].id, 'gap', id.hunk),
      DiffNoticeRow() => (id, 'notice', 0),
      DiffLineRow(:final line) => (
        id,
        line.kind == DiffLineKind.removed ? 'old' : 'new',
        line.kind == DiffLineKind.removed ? line.oldNumber! : line.newNumber!,
      ),
      DiffPairRow(:final left, :final right) => (
        id,
        right == null ? 'old' : 'new',
        right?.newNumber ?? left!.oldNumber!,
      ),
    };
  }

  int? _indexOf(Object key, List<DiffRow> rows) {
    if (key is! (String, String, int) || rows is! DiffLayout) return null;
    final file = _files.indexWhere((file) => file.id == key.$1);
    if (file < 0) return null;
    if (key.$2 == 'old' || key.$2 == 'new') {
      final line = rows.rowForLine(file, key.$3, oldSide: key.$2 == 'old');
      if (line != null || widget.controller == null) return line;
      if (widget.controller!.isCollapsed(_files[file].id)) {
        return rows.rowForFile(file);
      }
      for (final hunk in _files[file].hunks) {
        final start = key.$2 == 'old' ? hunk.oldStart : hunk.newStart;
        final count = key.$2 == 'old' ? hunk.oldCount : hunk.newCount;
        if (key.$3 >= start && key.$3 < start + count) {
          return rows.rowForSection(file, hunk.newStart);
        }
      }
      return null;
    }
    if (key.$2 == 'hunk') {
      return rows.rowForSection(file, key.$3) ?? rows.rowForLine(file, key.$3);
    }
    if (key.$2 == 'gap') {
      final hunks = _files[file].hunks;
      final hunk = key.$3;
      final prev = hunk > 0 && hunk <= hunks.length ? hunks[hunk - 1] : null;
      final firstNew = prev == null
          ? 1
          : (prev.newCount == 0
                ? prev.newStart
                : prev.newStart + prev.newCount);
      final expandedRow = rows.rowForLine(file, firstNew);
      if (expandedRow != null) return expandedRow;
      if (prev != null) {
        final prevEnd =
            rows.rowForLine(file, firstNew - 1) ??
            rows.rowForLine(
              file,
              prev.oldStart + math.max(prev.oldCount - 1, 0),
              oldSide: true,
            );
        if (prevEnd != null && prevEnd + 1 < rows.length) return prevEnd + 1;
      }
      final fileRow = rows.rowForFile(file);
      if (fileRow == null) return null;
      return _files[file].path.isNotEmpty && fileRow + 1 < rows.length
          ? fileRow + 1
          : fileRow;
    }
    return rows.rowForFile(file);
  }

  @override
  Widget build(BuildContext context) {
    final highlighter = widget.highlighter ?? HighlighterScope.of(context);
    final palette = _paletteFor(context);
    final labels = widget.labels;
    final rows =
        widget.controller?.layout ??
        layoutDiff(
          _files,
          mode: widget.mode,
          collapsed: widget.collapsed,
          expanded: widget.expanded,
        );

    final windows = _windowsFor(highlighter);
    final shrinkControlled = widget.shrinkWrap && widget.controller != null;
    final revealRow = _pendingRevealRow();

    _annotationsByLine.clear();
    final revisions = {for (final file in _files) file.id: file.revision};
    for (final annotation
        in widget.controller?.annotations ?? widget.annotations) {
      if (revisions[annotation.fileId] != annotation.revision) continue;
      (_annotationsByLine[(
                annotation.fileId,
                annotation.side,
                annotation.line,
              )] ??=
              [])
          .add(annotation);
    }
    _nativeSelection.configure(
      source: (
        _files,
        widget.controller?.layout,
        widget.mode,
        Object.hashAllUnordered(widget.collapsed),
        Object.hashAllUnordered(widget.expanded),
      ),
      rowCount: rows.length,
      split: widget.mode == DiffMode.split,
      textAt: (index, side) => _textAt(rows[index], side)?.text,
      endingAt: (index, side) {
        final row = rows[index];
        final line = _textAt(row, side);
        return line == null ? '\n' : _lineEnding(_files[row.file], line, side);
      },
      identity: (index) => _identity(rows[index]),
    );
    final leadingCount = widget.leading == null ? 0 : 1;
    final reader = shrinkControlled && revealRow == null
        ? _captureShrinkAnchor()
        : null;
    if (!identical(_geometryRows, rows) || _leadingCount != leadingCount) {
      _headerRows.clear();
    }
    _geometryRows = rows;
    _leadingCount = leadingCount;
    final layoutKey = (
      widget.controller?.layout ?? _files,
      widget.mode,
      Object.hashAllUnordered(widget.collapsed),
      Object.hashAllUnordered(widget.expanded),
      widget.wrap,
      widget.textStyle,
      widget.showLineNumbers,
      widget.showChangeIndicators,
      widget.indicators,
      widget.hunkSeparatorStyle,
      leadingCount,
      widget.gutterBuilder != null,
      widget.sectionDecoration,
    );
    if (shrinkControlled) {
      if (_shrinkLayoutKey != layoutKey) {
        _shrinkAnchor ??= reader;
        _shrinkLayoutKey = layoutKey;
        _shrinkReportedRange = null;
        _shrinkHeights = RowHeightIndex(
          (rows.isEmpty ? 1 : rows.length) + leadingCount,
          estimatedHeight: palette.lineHeight,
        );
        _shrinkMeasurements.clear();
        _shrinkGeneration++;
      }
      if (revealRow != null) _scheduleShrinkReveal(revealRow + leadingCount);
    }

    Widget buildRow(BuildContext context, int index) {
      if (leadingCount == 1 && index == 0) {
        return SelectionContainer.disabled(child: widget.leading!);
      }
      index -= leadingCount;
      if (rows.isEmpty) {
        return PatchNoticeBar(text: labels.noFiles, palette: palette);
      }
      Widget row = windows.retain(
        () => _composedRow(context, index, rows, palette, highlighter, labels),
      );
      if (index > 0 && rows[index - 1].file != rows[index].file) {
        row = Padding(padding: const EdgeInsets.only(top: 16), child: row);
      }
      return row;
    }

    Widget viewport() => widget.shrinkWrap
        ? ListView.builder(
            controller: _scroll,
            padding: widget.padding,
            shrinkWrap: true,
            physics: widget.physics,
            itemCount: shrinkControlled
                ? 1
                : rows.isEmpty
                ? 1 + leadingCount
                : rows.length + leadingCount,
            itemBuilder: shrinkControlled
                ? (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var i = 0;
                        i < ((rows.isEmpty ? 1 : rows.length) + leadingCount);
                        i++
                      )
                        KeyedSubtree(
                          key: ValueKey(
                            i < leadingCount
                                ? 'leading'
                                : rows.isEmpty
                                ? 'empty'
                                : _identity(rows[i - leadingCount]),
                          ),
                          child: MeasuredCodeRow(
                            generation: _shrinkGeneration,
                            onSize: (size) =>
                                _recordShrinkHeight(i, size.height),
                            child: Builder(
                              builder: (rowContext) {
                                _shrinkContexts[i] = rowContext;
                                return buildRow(rowContext, i);
                              },
                            ),
                          ),
                        ),
                    ],
                  )
                : buildRow,
          )
        : ValueListenableBuilder<Set<Object>>(
            valueListenable: _nativeSelection.retainedRows,
            builder: (_, retained, _) => IndexedCodeViewport(
              controller: _scroll,
              count: (rows.isEmpty ? 1 : rows.length) + leadingCount,
              builder: buildRow,
              revealRow: revealRow == null ? null : revealRow + leadingCount,
              revealRequest: _revealToken,
              layoutKey: layoutKey,
              revealHeaderRow: _controlledSticky && revealRow != null
                  ? _headerForRow(revealRow + leadingCount)
                  : null,
              revealHeaderInset: _controlledSticky && revealRow != null
                  ? switch (_headerForRow(revealRow + leadingCount)) {
                      final header? => _headerInset(header),
                      _ => 0.0,
                    }
                  : 0.0,
              onRevealComplete: _completeReveal,
              onLayout: _controlledSticky ? _indexedGeometry : null,
              identity: (index) => index < leadingCount
                  ? 'leading'
                  : rows.isEmpty
                  ? 'empty'
                  : _identity(rows[index - leadingCount]),
              indexOf: (key) => key == 'leading'
                  ? (leadingCount == 1 ? 0 : null)
                  : switch (_indexOf(key, rows)) {
                      final index? => index + leadingCount,
                      _ => null,
                    },
              retainedRows: retained,
              padding: widget.padding,
              physics: widget.physics,
              estimatedHeight: palette.lineHeight,
              onVisibleRange: widget.onVisibleRange,
              onFirstRow: (index) {
                final sourceIndex = index - leadingCount;
                final file = sourceIndex < 0 || rows.isEmpty
                    ? null
                    : rows[sourceIndex.clamp(0, rows.length - 1)].file;
                if (widget.stickyHeaders && file != _stickyFile && mounted) {
                  setState(() => _stickyFile = file);
                }
              },
            ),
          );

    Widget list = widget.shrinkWrap && widget.controller != null
        ? LayoutBuilder(
            builder: (context, constraints) {
              _stickyBounded = constraints.hasBoundedHeight;
              _queueShrinkLayout();
              return viewport();
            },
          )
        : viewport();
    if (widget.stickyHeaders && _files.isNotEmpty) {
      Widget headerFor(int index) => _section(
        _buildRow(
          DiffFileHeaderRow(index, collapsed: _isCollapsed(index)),
          palette,
          highlighter,
          labels,
        ),
        first: true,
        last: _isCollapsed(index),
      );
      if (_controlledSticky) {
        final content = list;
        list = LayoutBuilder(
          builder: (context, constraints) {
            _stickyBounded = constraints.hasBoundedHeight;
            if (widget.shrinkWrap) _queueShrinkLayout();
            if (!_stickyBounded) return content;
            return Stack(
              children: [
                content,
                if (_pinnedFile case final index?)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: widget.padding.resolve(TextDirection.ltr).left,
                        right: widget.padding.resolve(TextDirection.ltr).right,
                      ),
                      child: ColoredBox(
                        color: widget.canvasColor ?? palette.background,
                        child: MeasuredCodeRow(
                          generation: 0,
                          onSize: (size) {
                            final row = _headerForFile(index);
                            if (row == null) return;
                            final height = size.height + _headerInset(row);
                            if (widget.shrinkWrap) {
                              _recordShrinkHeight(row, height);
                            } else {
                              _indexedLayout?.measure(row, height);
                            }
                          },
                          child: headerFor(index),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      } else {
        final index = (_stickyFile ?? 0).clamp(0, _files.length - 1);
        final header = headerFor(index);
        list = widget.shrinkWrap
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, list],
              )
            : Stack(
                children: [
                  Positioned.fill(child: list),
                  if (_stickyFile != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: widget.padding.resolve(TextDirection.ltr).left,
                          right: widget.padding
                              .resolve(TextDirection.ltr)
                              .right,
                        ),
                        child: ColoredBox(
                          color: widget.canvasColor ?? palette.background,
                          child: header,
                        ),
                      ),
                    ),
                ],
              );
      }
    }
    if (widget.selectable) {
      list = SyntaxSelectableRegion(
        theme: widget.theme,
        chrome: widget.selectionChrome,
        child: SelectionContainer(delegate: _nativeSelection, child: list),
      );
      list = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
        },
        child: Focus(focusNode: _lineFocus, child: list),
      );
    }
    return SyntaxChrome(
      theme: widget.theme,
      selectionChrome: widget.selectionChrome,
      child: HorizontalCodeScope(
        group: _horizontal,
        child: DefaultSelectionStyle(
          selectionColor: widget.theme.selectionColor,
          child: ColoredBox(
            color: widget.canvasColor ?? palette.background,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: list,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    DiffRow row,
    PatchPalette palette,
    Highlighter highlighter,
    DiffLabels labels, {
    int? index,
  }) {
    switch (row) {
      case DiffFileHeaderRow(:final file, :final collapsed):
        void toggle() {
          final controller = widget.controller;
          if (controller != null) {
            controller.setCollapsed(_files[file].id, !collapsed);
          } else {
            widget.onToggleFile?.call(file);
          }
        }
        final header = widget.headerBuilder != null
            ? widget.headerBuilder!(context, _files[file], collapsed, toggle)
            : PatchFileHeaderBar(
                file: _files[file],
                collapsed: collapsed,
                palette: palette,
                labels: labels,
                onToggle:
                    widget.controller == null && widget.onToggleFile == null
                    ? null
                    : toggle,
              );
        final label = widget.fileLabelBuilder?.call(context, _files[file]);
        final content = SelectionContainer.disabled(
          child: label == null
              ? header
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, label],
                ),
        );
        return content;
      case DiffNoticeRow(:final notice):
        return PatchNoticeBar(text: labels.notice(notice), palette: palette);
      case DiffHunkHeaderRow(:final hunk):
        final header = widget.hunkBuilder != null
            ? widget.hunkBuilder!(context, _files[row.file], hunk)
            : PatchHunkHeaderBar(
                hunk: hunk,
                palette: palette,
                style: widget.hunkSeparatorStyle,
              );
        return SelectionContainer.disabled(child: header);
      case DiffGapRow(:final id, :final count):
        return SelectionContainer.disabled(
          child: PatchGapBar(
            text: labels.showUnchangedLines(count),
            style: widget.hunkSeparatorStyle,
            palette: palette,
            onExpand: widget.controller != null
                ? () => widget.controller!.expandGap(id)
                : widget.onExpandGap == null
                ? null
                : () => widget.onExpandGap!(id),
          ),
        );
      case DiffLineRow(:final file, :final line):
        return _sourceLine(
          index!,
          file,
          line,
          null,
          palette,
          highlighter,
          labels,
        );
      case DiffPairRow(:final file, :final left, :final right):
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: left == null
                    ? ColoredBox(color: palette.emptySide)
                    : _sourceLine(
                        index!,
                        file,
                        left,
                        DiffSide.old,
                        palette,
                        highlighter,
                        labels,
                      ),
              ),
              SizedBox(width: 1, child: ColoredBox(color: palette.divider)),
              Expanded(
                child: right == null
                    ? ColoredBox(color: palette.emptySide)
                    : _sourceLine(
                        index!,
                        file,
                        right,
                        DiffSide.newer,
                        palette,
                        highlighter,
                        labels,
                      ),
              ),
            ],
          ),
        );
    }
  }

  List<InlineSpan> _spans(
    int file,
    DiffLine line,
    Highlighter highlighter,
    PatchPalette palette,
  ) {
    final emphasis = switch (line.kind) {
      DiffLineKind.added => palette.insertedText,
      DiffLineKind.removed => palette.removedText,
      DiffLineKind.context => null,
    };
    final diff = _files[file];
    final large =
        (diff.oldLines?.length ?? 0) + (diff.newLines?.length ?? 0) > 200 ||
        diff.hunks.fold<int>(0, (n, h) => n + h.lines.length) > 200;
    List<DiffSegment> segments;
    if (widget.executor != null || large) {
      segments = _windowsFor(highlighter).segments(
        diff,
        line,
        highlighter,
        widget.theme,
        widget.language,
        widget.inlineDiffMode,
      );
    } else {
      final highlights = _highlightsFor(highlighter);
      final highlighted = highlights.highlighted(diff, budget: _sliceBudget);
      if (!highlighted.isComplete) _finishLater();
      segments = highlighted.segmentsFor(line, highlights.words(diff));
    }
    return [
      for (final segment in segments)
        TextSpan(
          text: segment.text,
          style: segment.changed && emphasis != null
              ? palette.styles[segment.style].copyWith(
                  backgroundColor: emphasis,
                )
              : palette.styles[segment.style],
        ),
    ];
  }
}

// A command has one local-layout phase and, only when necessary, one ancestor
// phase. Scroll cancellation consumes it; no target-availability polling exists.
class _ShrinkReveal {
  _ShrinkReveal(
    this.token,
    this.row,
    this.rows,
    this.controller,
    this.ancestorOffsets,
  );
  final int token;
  final int row;
  final List<DiffRow> rows;
  final ScrollController controller;
  final Map<ScrollPosition, double> ancestorOffsets;
  bool positioned = false;
}

// Geometry is local to the patch. Only the final delta is converted to the
// owning ancestor viewport's units, using its layout transform.
typedef _ShrinkAnchor = ({
  Object identity,
  double within,
  Object owner,
  double pixels,
  double localOffset,
  double scale,
});
