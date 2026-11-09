import 'dart:math' as math;

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
import 'selectable_region.dart';
import 'selection_chrome.dart';
import 'styles.dart';

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
    this.mode = DiffMode.unified,
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
  }) : _files = files,
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
    this.mode = DiffMode.unified,
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
  }) : _files = null,
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
    this.mode = DiffMode.unified,
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
  }) : _files = null,
       _patch = null,
       _texts = (oldText, newText, path, contextLines);

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
  final DiffMode mode;

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

  /// Application-owned row payloads; stale file revisions are never rendered.
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
  List<DiffRow> _layout = const [];
  final _annotationsByLine =
      <(String, DiffSide, int), List<DiffAnnotation<T>>>{};
  void _rebuild(VoidCallback callback) => setState(callback);
  DiffSelection? _selection;
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
    final key = (widget._files, widget._patch, widget._texts);
    if (key == _sourceKey) return;
    _sourceKey = key;
    // Keep bounded ready output for revisits, but abandon queued work for the
    // previous snapshot immediately. A late executor still settles serially.
    _windows?.clear();
    _files = switch (key) {
      (final files?, _, _) => files,
      (_, final patch?, _) => parsePatch(patch),
      (_, _, (final before, final after, final path, final context)?) => [
        diffTexts(before, after, path: path, contextLines: context),
      ],
      _ => const [],
    };
    _stickyFile = widget.leading == null ? 0 : null;
    if (_selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selection == null) {
          widget.onSelectionChanged?.call(null);
        }
      });
    }
    _selection = null;
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

  @override
  void initState() {
    super.initState();
    _scroll = widget.scrollController ?? ScrollController();
    _nativeSelection.onBegin = () => _setSelection(null);
    _syncSource();
  }

  @override
  void didUpdateWidget(PatchView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) _scroll.dispose();
      _scroll = widget.scrollController ?? ScrollController();
    }
    _syncSource();
  }

  @override
  void dispose() {
    _autoScroll.dispose();
    _nativeSelection.dispose();
    _lineFocus.dispose();
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
      return rows.rowForLine(file, key.$3, oldSide: key.$2 == 'old');
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
    final rows = layoutDiff(
      _files,
      mode: widget.mode,
      collapsed: widget.collapsed,
      expanded: widget.expanded,
    );

    final windows = _windowsFor(highlighter);
    _layout = rows;
    _annotationsByLine.clear();
    final revisions = {for (final file in _files) file.id: file.revision};
    for (final annotation in widget.annotations) {
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
        _sourceKey,
        widget.mode,
        Object.hashAllUnordered(widget.collapsed),
        Object.hashAllUnordered(widget.expanded),
      ),
      rowCount: rows.length,
      split: widget.mode == DiffMode.split,
      textAt: (index, side) => _textAt(rows[index], side)?.text,
      endingAt: (index, side) =>
          _textAt(rows[index], side)?.sourceLineEnding ?? '\n',
      identity: (index) => _identity(rows[index]),
    );
    final leadingCount = widget.leading == null ? 0 : 1;
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
            itemCount: (rows.isEmpty ? 1 : rows.length) + leadingCount,
            itemBuilder: buildRow,
          )
        : ValueListenableBuilder<Set<Object>>(
            valueListenable: _nativeSelection.retainedRows,
            builder: (_, retained, _) => IndexedCodeViewport(
              controller: _scroll,
              count: (rows.isEmpty ? 1 : rows.length) + leadingCount,
              builder: buildRow,
              layoutKey: (
                _files,
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
              ),
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

    Widget list = viewport();
    if (widget.stickyHeaders && _files.isNotEmpty) {
      final index = (_stickyFile ?? 0).clamp(0, _files.length - 1);
      final header = _section(
        _buildRow(
          DiffFileHeaderRow(index, collapsed: widget.collapsed.contains(index)),
          palette,
          highlighter,
          labels,
        ),
        first: true,
        last: widget.collapsed.contains(index),
      );
      if (widget.shrinkWrap) {
        list = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, list],
        );
      } else {
        list = Stack(
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
                    right: widget.padding.resolve(TextDirection.ltr).right,
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
    DiffLabels labels,
  ) {
    switch (row) {
      case DiffFileHeaderRow(:final file, :final collapsed):
        void toggle() => widget.onToggleFile?.call(file);
        final header = widget.headerBuilder != null
            ? widget.headerBuilder!(context, _files[file], collapsed, toggle)
            : PatchFileHeaderBar(
                file: _files[file],
                collapsed: collapsed,
                palette: palette,
                labels: labels,
                onToggle: widget.onToggleFile == null ? null : toggle,
              );
        final label = widget.fileLabelBuilder?.call(context, _files[file]);
        return SelectionContainer.disabled(
          child: label == null
              ? header
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, label],
                ),
        );
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
            onExpand: widget.onExpandGap == null
                ? null
                : () => widget.onExpandGap!(id),
          ),
        );
      case DiffLineRow(:final file, :final line):
        return _sourceLine(file, line, null, palette, highlighter, labels);
      case DiffPairRow(:final file, :final left, :final right):
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: left == null
                    ? ColoredBox(color: palette.emptySide)
                    : _sourceLine(
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
