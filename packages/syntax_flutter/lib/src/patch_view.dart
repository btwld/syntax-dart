import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:syntax_core/syntax.dart';

import 'chrome.dart';
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
  }) : controller = null,
       _mode = mode,
       _files = files,
       _patch = null,
       _texts = null;

  /// Shows caller-owned patch state, rebuilding when the controller changes.
  ///
  /// The controller owns mode, file/hunk folding, context expansion and reveal.
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
  }) : _mode = DiffMode.unified,
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

  @override
  State<PatchView<T>> createState() => _PatchViewState<T>();
}

const _sliceBudget = Duration(milliseconds: 6);

class _PatchViewState<T> extends State<PatchView<T>> {
  late ScrollController _scroll;
  int _stickyFile = 0;
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
  final _shrinkRevealKey = GlobalKey();
  (Object, int, int?)? _shrinkRevealRequest;

  void _revealShrinkWrapped() {
    final controller = widget.controller;
    final request = controller == null
        ? null
        : (controller, controller.revealRequest, controller.revealRow);
    if (request == _shrinkRevealRequest) return;
    _shrinkRevealRequest = request;
    if (controller?.revealRow == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _shrinkRevealRequest) return;
      final row = _shrinkRevealKey.currentContext;
      if (row == null) return;
      final target = row.findRenderObject()!;
      var object = target;
      var scrollable = Scrollable.maybeOf(row);
      while (scrollable != null) {
        if (scrollable.position.axis == Axis.vertical) {
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
    });
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
    _files = switch (key) {
      (final files?, _, _) => files,
      (_, final patch?, _) => parsePatch(patch),
      (_, _, (final before, final after, final path, final context)?) => [
        diffTexts(before, after, path: path, contextLines: context),
      ],
      _ => const [],
    };
    _stickyFile = 0;
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

  void _controllerChanged() {
    setState(_syncSource);
  }

  @override
  void initState() {
    super.initState();
    _scroll = widget.scrollController ?? ScrollController();
    _syncSource();
    widget.controller?.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(PatchView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_controllerChanged);
      widget.controller?.addListener(_controllerChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) _scroll.dispose();
      _scroll = widget.scrollController ?? ScrollController();
    }
    _syncSource();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_controllerChanged);
    _windows?.dispose();
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
    if (shrinkControlled) {
      _revealShrinkWrapped();
    } else {
      _shrinkRevealRequest = null;
    }
    Widget buildRow(BuildContext context, int index) {
      if (rows.isEmpty) {
        return PatchNoticeBar(text: labels.noFiles, palette: palette);
      }
      final row = windows.retain(
        () => _buildRow(rows[index], palette, highlighter, labels),
      );
      return index > 0 && rows[index - 1].file != rows[index].file
          ? Padding(padding: const EdgeInsets.only(top: 16), child: row)
          : row;
    }

    Widget list = widget.shrinkWrap
        ? ListView.builder(
            controller: _scroll,
            padding: widget.padding,
            shrinkWrap: true,
            physics: widget.physics,
            itemCount: shrinkControlled
                ? 1
                : rows.isEmpty
                ? 1
                : rows.length,
            itemBuilder: shrinkControlled
                ? (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < (rows.isEmpty ? 1 : rows.length); i++)
                        KeyedSubtree(
                          key: ValueKey(
                            rows.isEmpty ? 'empty' : _identity(rows[i]),
                          ),
                          child: KeyedSubtree(
                            key: i == widget.controller!.revealRow
                                ? _shrinkRevealKey
                                : null,
                            child: buildRow(context, i),
                          ),
                        ),
                    ],
                  )
                : buildRow,
          )
        : IndexedCodeViewport(
            controller: _scroll,
            count: rows.isEmpty ? 1 : rows.length,
            builder: buildRow,
            revealRow: widget.controller?.revealRow,
            revealRequest: widget.controller?.revealRequest ?? 0,
            layoutKey: (
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
            ),
            identity: (index) =>
                rows.isEmpty ? 'empty' : _identity(rows[index]),
            indexOf: (key) => _indexOf(key, rows),
            padding: widget.padding,
            physics: widget.physics,
            estimatedHeight: palette.lineHeight,
            onFirstRow: (index) {
              if (!widget.stickyHeaders || rows.isEmpty) return;
              final file = rows[index.clamp(0, rows.length - 1)].file;
              if (file != _stickyFile && mounted) {
                setState(() => _stickyFile = file);
              }
            },
          );

    if (widget.stickyHeaders && _files.isNotEmpty) {
      final index = _stickyFile.clamp(0, _files.length - 1);
      final stickyHeader = _buildRow(
        DiffFileHeaderRow(
          index,
          collapsed:
              widget.controller?.isCollapsed(_files[index].id) ??
              widget.collapsed.contains(index),
        ),
        palette,
        highlighter,
        labels,
      );
      list = widget.shrinkWrap
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [stickyHeader, list],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                stickyHeader,
                Expanded(child: list),
              ],
            );
    }
    if (widget.selectable) {
      list = SyntaxSelectableRegion(
        theme: widget.theme,
        chrome: widget.selectionChrome,
        child: list,
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
            color: palette.background,
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
    DiffLabels labels,
  ) {
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
        return SelectionContainer.disabled(child: header);
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
        return PatchUnifiedLine(
          line: line,
          spans: _spans(file, line, highlighter, palette),
          gutterWidth: palette.gutterWidth(_files[file]),
          palette: palette,
          labels: labels,
        );
      case DiffPairRow(:final file, :final left, :final right):
        return PatchSplitLine(
          left: left,
          right: right,
          leftSpans: left == null
              ? null
              : _spans(file, left, highlighter, palette),
          rightSpans: right == null
              ? null
              : _spans(file, right, highlighter, palette),
          gutterWidth: palette.gutterWidth(_files[file]),
          palette: palette,
          labels: labels,
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
