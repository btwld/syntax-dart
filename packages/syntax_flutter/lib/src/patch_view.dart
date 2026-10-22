import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor.dart';
import 'indexed_viewport.dart';
import 'horizontal_scroll.dart';
import 'line_selection.dart';
import 'package:syntax/syntax.dart';

import 'highlighter_scope.dart';
import 'styles.dart';

/// A syntax-highlighted view of code changes.
///
/// Show a `git diff` with [PatchView.fromPatch], compare two versions of a
/// file with [PatchView.fromTexts], or pass [FileDiff]s directly. Each file
/// with a path gets a header with its status and change counts, which
/// collapses the file when tapped. Lines show old and new line numbers,
/// the changed words inside edited lines are highlighted, and colors come
/// from [theme]'s diff colors. Long lines wrap. Code reads left to right
/// even in a right-to-left app.
///
/// When the full texts are known, as with [PatchView.fromTexts], the
/// unchanged lines between hunks can be expanded and highlighting is exact.
/// For a parsed patch each hunk is highlighted on its own.
///
/// The patch is parsed, or the texts diffed, whenever the source changes,
/// and each file is highlighted the first time it is shown. For very large
/// inputs, build the [FileDiff]s ahead of time, for example in an isolate,
/// and pass them to the default constructor.
///
/// The view uses Material widgets and icons, so it needs a [MaterialApp]
/// or another ancestor that provides an [Overlay], and an app that bundles
/// the Material icons font. Its words come from [labels].
class PatchView extends StatefulWidget {
  /// Shows [files] as they are. The view resets its collapsed files and
  /// expanded lines when it gets a different list, compared by identity, so
  /// keep the same list across rebuilds.
  const PatchView({
    super.key,
    required List<FileDiff> files,
    required this.theme,
    this.highlighter,
    this.language,
    this.mode = DiffMode.unified,
    this.textStyle,
    this.selectable = true,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(12),
    this.labels = const DiffLabels(),
    this.controller,
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.wrap = true,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = HunkSeparatorStyle.lineInfo,
    this.tokenTooltip,
    this.stickyHeaders = false,
    this.showReviewActions = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.gutterActionBuilder,
    this.onLineTap,
    this.onTokenTap,
    this.onEditComplete,
    this.scrollController,
  }) : _files = files,
       _patch = null,
       _texts = null;

  /// Shows a unified diff, such as the output of `git diff`.
  const PatchView.fromPatch(
    String patch, {
    super.key,
    required this.theme,
    this.highlighter,
    this.language,
    this.mode = DiffMode.unified,
    this.textStyle,
    this.selectable = true,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(12),
    this.labels = const DiffLabels(),
    this.controller,
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.wrap = true,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = HunkSeparatorStyle.lineInfo,
    this.tokenTooltip,
    this.stickyHeaders = false,
    this.showReviewActions = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.gutterActionBuilder,
    this.onLineTap,
    this.onTokenTap,
    this.onEditComplete,
    this.scrollController,
  }) : _files = null,
       _patch = patch,
       _texts = null;

  /// Shows the changes from [oldText] to [newText], with [contextLines]
  /// unchanged lines around each change. [path] names the file in the
  /// header and, unless [language] is set, picks the language from its
  /// extension.
  const PatchView.fromTexts({
    super.key,
    required String oldText,
    required String newText,
    String path = '',
    int contextLines = 3,
    required this.theme,
    this.highlighter,
    this.language,
    this.mode = DiffMode.unified,
    this.textStyle,
    this.selectable = true,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(12),
    this.labels = const DiffLabels(),
    this.controller,
    this.inlineDiffMode = InlineDiffMode.mergedWords,
    this.wrap = true,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = HunkSeparatorStyle.lineInfo,
    this.tokenTooltip,
    this.stickyHeaders = false,
    this.showReviewActions = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.gutterActionBuilder,
    this.onLineTap,
    this.onTokenTap,
    this.onEditComplete,
    this.scrollController,
  }) : _files = null,
       _patch = null,
       _texts = (oldText, newText, path, contextLines);

  /// Uses persistent review state, including partial loading and selections.
  const PatchView.controlled({
    super.key,
    required PatchController this.controller,
    required this.theme,
    this.highlighter,
    this.language,
    this.mode = DiffMode.unified,
    this.textStyle,
    this.selectable = true,
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
    this.tokenTooltip,
    this.stickyHeaders = false,
    this.showReviewActions = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.gutterActionBuilder,
    this.onLineTap,
    this.onTokenTap,
    this.onEditComplete,
    this.scrollController,
  }) : _files = null,
       _patch = null,
       _texts = null;

  /// Shared review state. Its mode takes precedence over [mode].
  final PatchController? controller;

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

  /// Optional hover help. Tokens also expose the tooltip to keyboard focus.
  final String? Function(FileDiff, DiffLine, DiffSegment)? tokenTooltip;

  /// Keeps the current file header visible above the scroll viewport.
  final bool stickyHeaders;

  /// Shows accept, reject, combine, copy, loading and editing controls.
  final bool showReviewActions;

  /// Replaces a file header; invoke the supplied callback to fold the file.
  final Widget Function(BuildContext, FileDiff, bool, VoidCallback)?
  headerBuilder;

  /// Replaces a hunk separator.
  final Widget Function(BuildContext, FileDiff, DiffHunk)? hunkBuilder;

  /// Renders annotations beneath their corresponding source line.
  final Widget Function(BuildContext, ReviewAnnotation<Object?>)?
  annotationBuilder;

  /// Builds an application action beside a source line.
  final Widget Function(BuildContext, FileDiff, DiffSide, int)?
  gutterActionBuilder;

  /// Reports a source-line click after updating the logical selection.
  final void Function(FileDiff, DiffSide, int)? onLineTap;

  /// Reports clicks on highlighted token text.
  final void Function(FileDiff, DiffLine, DiffSegment)? onTokenTap;

  /// Allows applications to accept or decline an edited diff.
  final Future<bool> Function(FileDiff)? onEditComplete;

  /// Optional controller for the underlying vertical viewport.
  final ScrollController? scrollController;

  final List<FileDiff>? _files;
  final String? _patch;
  final (String, String, String, int)? _texts;

  /// Colors for code, line backgrounds and changed words.
  final SyntaxTheme theme;

  /// Defaults to the nearest [HighlighterScope].
  final Highlighter? highlighter;

  /// The language of every file, by name or alias. Defaults to guessing
  /// each file's language from its path.
  final String? language;

  /// Whether changes are shown in one column or side by side.
  final DiffMode mode;

  /// Base style for code and line numbers. Defaults to
  /// [defaultCodeTextStyle].
  final TextStyle? textStyle;

  /// Allows selecting and copying code. Line numbers and markers are left
  /// out of the selection.
  final bool selectable;

  /// Sizes the view to its content, for use inside another scroll view.
  /// This builds every row up front instead of only the visible ones, so
  /// avoid it for long patches.
  final bool shrinkWrap;

  /// Passed to the underlying [ListView].
  final ScrollPhysics? physics;

  /// Space around the files, inside the scroll view.
  final EdgeInsetsGeometry padding;

  /// The words the view shows and announces. Extend [DiffLabels] to
  /// translate them.
  final DiffLabels labels;

  @override
  State<PatchView> createState() => _PatchViewState();
}

class _PatchViewState extends State<PatchView> {
  late ScrollController _scroll;
  int _stickyFile = 0;
  Object? _sourceKey;
  List<FileDiff> _files = const [];
  final Set<int> _collapsed = {};
  final Set<DiffGapId> _expandedGaps = {};

  Object? _highlightKey;
  final _horizontal = HorizontalCodeGroup();
  DiffHighlightCache? _highlights;
  _Palette? _palette;

  void _controllerChanged() {
    if (!mounted) return;
    setState(() {
      _files = widget.controller!.files;
      _layoutVersion++;
    });
  }

  void _syncSource() {
    if (widget.controller case final controller?) {
      _files = controller.files;
      _layoutVersion++;
      return;
    }
    final key = (widget._files, widget._patch, widget._texts);
    if (key == _sourceKey) return;
    _sourceKey = key;
    _files = switch ((widget._files, widget._patch, widget._texts)) {
      (final files?, _, _) => files,
      (_, final patch?, _) => parsePatchDocuments(
        patch,
      ).expand((document) => document.files).toList(),
      (_, _, (final before, final after, final path, final context)?) => [
        diffTexts(before, after, path: path, contextLines: context),
      ],
      _ => const [],
    };
    _collapsed.clear();
    _expandedGaps.clear();
    _highlights = null;
    _layoutVersion++;
  }

  DiffHighlightCache _highlightsFor(Highlighter highlighter) {
    final key = (highlighter, widget.language, widget.inlineDiffMode);
    if (key != _highlightKey || _highlights == null) {
      _highlightKey = key;
      _highlights = DiffHighlightCache(
        highlighter: highlighter,
        theme: widget.theme,
        language: widget.language,
        inlineDiffMode: widget.inlineDiffMode,
      );
    }
    _highlights!.theme = widget.theme;
    return _highlights!;
  }

  _Palette _paletteFor(BuildContext context) {
    final textStyle = widget.textStyle ?? defaultCodeTextStyle;
    final scaler = MediaQuery.textScalerOf(context);
    if (_palette case final p?
        when p.theme == widget.theme &&
            p.textStyle == textStyle &&
            p.scaler == scaler &&
            p.wrap == widget.wrap &&
            p.backgrounds == widget.showBackgrounds &&
            p.indicators ==
                (widget.showChangeIndicators
                    ? widget.indicators
                    : DiffIndicators.none) &&
            p.lineNumbers == widget.showLineNumbers) {
      return p;
    }
    return _palette = _Palette(
      widget.theme,
      textStyle,
      scaler,
      wrap: widget.wrap,
      backgrounds: widget.showBackgrounds,
      indicators: widget.showChangeIndicators
          ? widget.indicators
          : DiffIndicators.none,
      lineNumbers: widget.showLineNumbers,
      onTokenTap: widget.onTokenTap,
    );
  }

  /// Bumped whenever the files, collapsed files or expanded gaps change.
  int _layoutVersion = 0;
  Object? _rowsKey;
  List<DiffRow> _rows = const [];

  List<DiffRow> _layout() {
    if (widget.controller case final c?) return c.layout;
    final key = (_layoutVersion, widget.mode);
    if (key == _rowsKey) return _rows;
    _rowsKey = key;
    return _rows = layoutDiff(
      _files,
      mode: widget.mode,
      collapsed: _collapsed,
      expanded: _expandedGaps,
    );
  }

  /// Changes what is collapsed or expanded, then lays out again.
  void _toggle(VoidCallback change) => setState(() {
    change();
    _layoutVersion++;
  });

  @override
  void initState() {
    super.initState();
    _scroll = widget.scrollController ?? ScrollController();
    widget.controller?.addListener(_controllerChanged);
    _syncSource();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_controllerChanged);
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PatchView oldWidget) {
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
  Widget build(BuildContext context) {
    final highlighter = widget.highlighter ?? HighlighterScope.of(context);
    final palette = _paletteFor(context);
    final labels = widget.labels;
    final rows = _layout();

    Widget buildRow(BuildContext context, int index) {
      if (rows.isEmpty) return _notice(labels.noFiles, palette);
      final model = rows[index];
      Widget source = _buildRow(model, palette, highlighter, labels);
      if (widget.selectable && (model is DiffLineRow || model is DiffPairRow)) {
        source = SelectionArea(child: source);
      }
      final row = _decorateRow(context, model, source, palette, highlighter);
      return index > 0 && rows[index - 1].file != model.file
          ? Padding(padding: const EdgeInsets.only(top: 16), child: row)
          : row;
    }

    Object identity(int index) {
      if (rows.isEmpty) return 'empty';
      final row = rows[index];
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

    int? indexOf(Object key) {
      if (key is! (String, String, int) || rows is! DiffLayout) return null;
      final file = _files.indexWhere((file) => file.id == key.$1);
      if (file < 0) return null;
      if (key.$2 == 'old' || key.$2 == 'new') {
        return rows.rowForLine(file, key.$3, oldSide: key.$2 == 'old');
      }
      if (key.$2 == 'hunk') return rows.rowForSection(file, key.$3);
      return rows.rowForFile(file);
    }

    Widget list = widget.shrinkWrap
        ? ListView.builder(
            controller: _scroll,
            padding: widget.padding,
            shrinkWrap: true,
            physics: widget.physics,
            itemCount: math.max(1, rows.length),
            itemBuilder: buildRow,
          )
        : IndexedCodeViewport(
            controller: _scroll,
            count: math.max(1, rows.length),
            builder: buildRow,
            layoutKey: (
              rows,
              widget.wrap,
              widget.textStyle,
              widget.controller?.annotations,
            ),
            identity: identity,
            indexOf: indexOf,
            padding: widget.padding,
            physics: widget.physics,
            revealRow: widget.controller?.scrollTargetRow,
            revealRequest: widget.controller?.scrollRequest ?? 0,
            estimatedHeight:
                (widget.textStyle?.fontSize ?? 14) *
                (widget.textStyle?.height ?? 1.5),
            onFirstRow: (index) {
              if (!widget.stickyHeaders || rows.isEmpty) return;
              final file = rows[index.clamp(0, rows.length - 1)].file;
              if (file != _stickyFile && mounted) {
                setState(() => _stickyFile = file);
              }
            },
          );

    list = LineSelectionRegion(controller: _scroll, child: list);

    if (widget.stickyHeaders && _files.isNotEmpty) {
      final index = _stickyFile.clamp(0, _files.length - 1);
      list = Column(
        children: [
          _buildRow(
            DiffFileHeaderRow(
              index,
              collapsed:
                  widget.controller?.isCollapsed(_files[index].id) ??
                  _collapsed.contains(index),
            ),
            palette,
            highlighter,
            labels,
          ),
          Expanded(child: list),
        ],
      );
    }
    if (widget.controller case final controller?) {
      list = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
              Clipboard.setData(ClipboardData(text: controller.selectedText())),
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () =>
              Clipboard.setData(ClipboardData(text: controller.selectedText())),
        },
        child: Focus(child: list),
      );
    }
    return HorizontalCodeScope(
      group: _horizontal,
      child: DefaultSelectionStyle(
        selectionColor: widget.theme.selectionColor,
        child: ColoredBox(
          color: palette.background,
          // Code reads left to right whatever the app's direction.
          child: Directionality(textDirection: TextDirection.ltr, child: list),
        ),
      ),
    );
  }

  Widget _buildRow(
    DiffRow row,
    _Palette palette,
    Highlighter highlighter,
    DiffLabels labels,
  ) {
    switch (row) {
      // Headers and notices are not code, so they stay out of selections.
      case DiffFileHeaderRow(:final file, :final collapsed):
        void toggle() {
          if (widget.controller case final c?) {
            c.toggleFile(_files[file].id);
          } else {
            _toggle(() {
              if (!_collapsed.remove(file)) _collapsed.add(file);
            });
          }
        }
        if (widget.headerBuilder case final builder?) {
          return builder(context, _files[file], collapsed, toggle);
        }
        return SelectionContainer.disabled(
          child: _FileHeaderBar(
            file: _files[file],
            collapsed: collapsed,
            palette: palette,
            labels: labels,
            onToggle: toggle,
          ),
        );
      case DiffNoticeRow(:final notice):
        return _notice(labels.notice(notice), palette);
      case DiffHunkHeaderRow(:final hunk, :final collapsed):
        if (widget.hunkBuilder case final builder?) {
          return builder(context, _files[row.file], hunk);
        }
        return SelectionContainer.disabled(
          child: _HunkHeaderBar(
            hunk: hunk,
            palette: palette,
            collapsed: collapsed,
            style: widget.hunkSeparatorStyle,
            onToggle: widget.controller?.foldableHunks == true
                ? () => widget.controller!.toggleHunk(
                    _files[row.file].id,
                    _files[row.file].hunks.indexOf(hunk),
                  )
                : null,
          ),
        );
      case DiffGapRow(:final id, :final count):
        return SelectionContainer.disabled(
          child: _GapBar(
            text: labels.showUnchangedLines(count),
            style: widget.hunkSeparatorStyle,
            palette: palette,
            onExpand: () {
              if (widget.controller case final c?) {
                c.expand(id);
              } else {
                _toggle(() => _expandedGaps.add(id));
              }
            },
          ),
        );
      case DiffLineRow(:final file, :final line):
        return _UnifiedLine(
          line: line,
          spans: _spans(file, line, highlighter, palette),
          gutterWidth: palette.gutterWidth(_files[file]),
          palette: palette,
          labels: labels,
        );
      case DiffPairRow(:final file, :final left, :final right):
        return _SplitLine(
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

  Widget _decorateRow(
    BuildContext context,
    DiffRow row,
    Widget child,
    _Palette palette,
    Highlighter highlighter,
  ) {
    final controller = widget.controller;
    final file = _files[row.file];
    final additions = <Widget>[];
    if (controller != null && widget.showReviewActions) {
      if (row is DiffFileHeaderRow) {
        additions.add(
          Wrap(
            children: [
              if (file.isPartial && controller.contentsLoader != null)
                TextButton(
                  onPressed: controller.isLoading(file.id)
                      ? null
                      : () => controller.loadContents(file.id),
                  child: Text(
                    controller.isLoading(file.id)
                        ? 'Loading…'
                        : 'Load full contents',
                  ),
                ),
              if (!file.isPartial)
                TextButton(
                  onPressed: () => controller.expandAll(file.id),
                  child: const Text('Expand all'),
                ),
              if (!file.isPartial && widget.onEditComplete != null)
                TextButton(
                  onPressed: () => _edit(file, highlighter),
                  child: const Text('Edit'),
                ),
              if (controller.selection?.fileId == file.id)
                TextButton(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: controller.selectedText()),
                  ),
                  child: const Text('Copy selected lines'),
                ),
              if (controller.loadErrors[file.id] case final error?)
                Text('Unable to load: $error'),
            ],
          ),
        );
      }
      if (row is DiffHunkHeaderRow && !file.isPartial) {
        final index = file.hunks.indexOf(row.hunk);
        additions.add(
          Wrap(
            children: [
              for (final (label, resolution) in [
                ('Accept', ChangeResolution.newer),
                ('Reject', ChangeResolution.old),
                ('Combine', ChangeResolution.both),
              ])
                TextButton(
                  onPressed: () =>
                      controller.resolve(file.id, index, resolution),
                  child: Text(label),
                ),
            ],
          ),
        );
      }
      if (row is DiffGapRow) {
        additions.add(
          Wrap(
            children: [
              TextButton(
                onPressed: () => controller.expand(
                  row.id,
                  direction: ExpansionDirection.before,
                ),
                child: const Text('Expand above'),
              ),
              TextButton(
                onPressed: () => controller.expand(
                  row.id,
                  direction: ExpansionDirection.after,
                ),
                child: const Text('Expand below'),
              ),
            ],
          ),
        );
      }
    }
    final lines = switch (row) {
      DiffLineRow(:final line) => [
        (
          line,
          line.kind == DiffLineKind.removed ? DiffSide.old : DiffSide.newer,
        ),
      ],
      DiffPairRow(:final left, :final right) => [
        if (left != null) (left, DiffSide.old),
        if (right != null) (right, DiffSide.newer),
      ],
      _ => <(DiffLine, DiffSide)>[],
    };
    if (lines.isNotEmpty) {
      final lineChild = child;
      void selectAt(double x, double width, bool extend) {
        final (line, side) = lines.length > 1 && x >= width / 2
            ? lines.last
            : lines.first;
        final number = (side == DiffSide.old
            ? line.oldNumber
            : line.newNumber)!;
        final old = controller?.selection;
        final keepAnchor = extend && old?.fileId == file.id;
        controller?.select(
          DiffSelection(
            file.id,
            keepAnchor ? old!.side : side,
            keepAnchor ? old!.anchor : number,
            number,
            activeSide: side,
          ),
        );
        widget.onLineTap?.call(file, side, number);
      }

      final gutter =
          (widget.showLineNumbers
              ? palette.gutterWidth(file) * (row is DiffPairRow ? 1 : 2)
              : 0) +
          20;
      child = LineSelectionTarget(
        isGutter: (x, width) =>
            x < gutter ||
            (row is DiffPairRow && x >= width / 2 && x < width / 2 + gutter),
        onSelect: selectAt,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (event) {
              final x = event.localPosition.dx;
              // Gutter pointer events are already handled by the drag coordinator.
              if (x < gutter ||
                  (row is DiffPairRow &&
                      x >= constraints.maxWidth / 2 &&
                      x < constraints.maxWidth / 2 + gutter)) {
                return;
              }
              selectAt(
                x,
                constraints.maxWidth,
                HardwareKeyboard.instance.isShiftPressed,
              );
            },
            child: lineChild,
          ),
        ),
      );
      for (final (line, side) in lines) {
        final number = (side == DiffSide.old
            ? line.oldNumber
            : line.newNumber)!;
        if (widget.gutterActionBuilder case final builder?) {
          additions.add(builder(context, file, side, number));
        }
        for (final annotation
            in controller?.annotations ?? const <ReviewAnnotation<Object?>>[]) {
          if (annotation.fileId == file.id &&
              annotation.side == side &&
              annotation.line == number) {
            additions.add(
              widget.annotationBuilder?.call(context, annotation) ??
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('${annotation.data}'),
                  ),
            );
          }
        }
        final selection = controller?.selection;
        if (controller?.isLineSelected(file.id, side, number) == true) {
          if (controller != null &&
              widget.showReviewActions &&
              !file.isPartial &&
              number == selection!.active &&
              side == selection.activeSide) {
            final change = controller.changeAt(file.id, number, side: side);
            if (change != null) {
              additions.add(
                Wrap(
                  children: [
                    for (final (label, choice) in [
                      ('Accept change', ChangeResolution.newer),
                      ('Reject change', ChangeResolution.old),
                      ('Combine change', ChangeResolution.both),
                    ])
                      TextButton(
                        onPressed: () => controller.resolve(
                          file.id,
                          change.hunk,
                          choice,
                          changeIndex: change.change,
                        ),
                        child: Text(label),
                      ),
                  ],
                ),
              );
            }
          }
          child = Stack(
            children: [
              child,
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: row is DiffPairRow && side == DiffSide.old
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: row is DiffPairRow ? .5 : 1,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.theme.selectionColor.withValues(
                            alpha: .15,
                          ),
                          border: Border(
                            left: BorderSide(
                              width: 3,
                              color: widget.theme.selectionColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (additions.isNotEmpty)
          SelectionContainer.disabled(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: additions,
            ),
          ),
      ],
    );
  }

  Future<void> _edit(FileDiff file, Highlighter highlighter) async {
    final controller = widget.controller!;
    final editor = controller.beginEdit(file.id);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 900,
          height: 650,
          child: SyntaxEditor(
            controller: editor,
            highlighter: highlighter,
            theme: widget.theme,
            language: widget.language ?? file.language,
            onDismiss: () => Navigator.pop(context),
            onComplete: (_) async {
              final accepted = await controller.completeEdit(
                file.id,
                accept: widget.onEditComplete!,
              );
              if (context.mounted) Navigator.pop(context);
              return accepted;
            },
          ),
        ),
      ),
    );
    if (!controller.isDisposed) controller.releaseEdit(file.id);
  }

  static Widget _notice(String text, _Palette palette) =>
      SelectionContainer.disabled(
        child: Container(
          color: palette.hunkBackground,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(text, style: palette.mutedText),
        ),
      );

  List<InlineSpan> _spans(
    int file,
    DiffLine line,
    Highlighter highlighter,
    _Palette palette,
  ) {
    final emphasis = switch (line.kind) {
      DiffLineKind.added => palette.insertedText,
      DiffLineKind.removed => palette.removedText,
      DiffLineKind.context => null,
    };
    return [
      for (final segment in _highlightsFor(
        highlighter,
      ).segmentsFor(_files[file], line))
        if (widget.onTokenTap != null || widget.tokenTooltip != null)
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Tooltip(
              message:
                  widget.tokenTooltip?.call(_files[file], line, segment) ??
                  segment.text,
              child: InkWell(
                onTap: () =>
                    widget.onTokenTap?.call(_files[file], line, segment),
                child: Text(
                  segment.text,
                  style: palette.code
                      .merge(palette.styles[segment.style])
                      .copyWith(
                        backgroundColor: segment.changed ? emphasis : null,
                      ),
                ),
              ),
            ),
          )
        else
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

/// Colors and text styles derived from the theme, shared by every row.
final class _Palette {
  _Palette(
    this.theme,
    this.textStyle,
    this.scaler, {
    this.wrap = true,
    this.backgrounds = true,
    this.indicators = DiffIndicators.classic,
    this.lineNumbers = true,
    this.onTokenTap,
  }) : styles = TokenTextStyles(theme, base: textStyle) {
    final diff = DiffColors.of(theme);
    inserted = Color(diff.inserted);
    removed = Color(diff.removed);
    insertedLine = Color(diff.insertedLine);
    removedLine = Color(diff.removedLine);
    insertedText = Color(diff.insertedText);
    removedText = Color(diff.removedText);
    headerBackground = Color(diff.fileHeader);
    hunkBackground = Color(diff.hunkHeader);
    emptySide = Color(diff.emptySide);
    divider = Color(diff.divider);
    label = Color(diff.muted);
  }

  final bool wrap, backgrounds, lineNumbers;
  final DiffIndicators indicators;
  final void Function(FileDiff, DiffLine, DiffSegment)? onTokenTap;
  final SyntaxTheme theme;
  final TextStyle textStyle;
  final TextScaler scaler;
  final TokenTextStyles styles;
  late final Color inserted;
  late final Color removed;
  late final Color insertedLine;
  late final Color removedLine;
  late final Color insertedText;
  late final Color removedText;
  late final Color headerBackground;
  late final Color hunkBackground;
  late final Color emptySide;
  late final Color divider;

  /// Labels such as hunk headers need more contrast than line numbers.
  late final Color label;

  Color get background => theme.backgroundColor;
  Color get foreground => theme.foregroundColor;
  Color get muted => theme.lineNumberColor;

  TextStyle get code => styles.base;

  /// Line numbers use the theme's line-number color.
  late final TextStyle numberText = code.copyWith(color: muted);

  late final TextStyle mutedText = code.copyWith(color: label);

  /// Painted over the line background, so a changed line's gutter is
  /// twice as strong as its code area.
  Color gutterBackground(DiffLineKind kind) => !backgrounds
      ? background
      : switch (kind) {
          DiffLineKind.added => insertedLine,
          DiffLineKind.removed => removedLine,
          DiffLineKind.context => const Color(0x00000000),
        };

  Color lineBackground(DiffLineKind kind) => !backgrounds
      ? background
      : switch (kind) {
          DiffLineKind.added => insertedLine,
          DiffLineKind.removed => removedLine,
          DiffLineKind.context => background,
        };

  /// The size of one digit, which is also the height of one line of code.
  late final Size _digit = () {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: code),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }();

  double get lineHeight => _digit.height;

  final Map<FileDiff, double> _gutterWidths = Map.identity();

  /// Width of one line-number column, sized for the file's largest number.
  double gutterWidth(FileDiff file) => _gutterWidths.putIfAbsent(
    file,
    () => '${math.max(file.maxLineNumber, 1)}'.length * _digit.width + 16,
  );
}

class _FileHeaderBar extends StatelessWidget {
  const _FileHeaderBar({
    required this.file,
    required this.collapsed,
    required this.palette,
    required this.labels,
    required this.onToggle,
  });

  final FileDiff file;
  final bool collapsed;
  final _Palette palette;
  final DiffLabels labels;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final code = palette.code;
    final additions = file.additions;
    final deletions = file.deletions;
    final label = labels.status(file.kind);
    final color = switch (file.kind) {
      FileDiffKind.added => palette.inserted,
      FileDiffKind.deleted => palette.removed,
      _ => palette.label,
    };
    final radius = collapsed
        ? BorderRadius.circular(6)
        : const BorderRadius.vertical(top: Radius.circular(6));
    return Material(
      color: palette.headerBackground,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onToggle,
        child: Semantics(
          button: true,
          expanded: !collapsed,
          label: labels.fileHeader(file),
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 12, 7),
            // Narrow headers drop the extras before the path gets too short.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final counts = !file.isBinary && width >= 180;
                return Row(
                  children: [
                    Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 18,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 4),
                    if (label != null && width >= 260) ...[
                      _Badge(label: label, color: color, style: code),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: _PathText(file: file, palette: palette),
                    ),
                    if (counts) ...[
                      const SizedBox(width: 12),
                      Text(
                        '+$additions',
                        style: code.copyWith(
                          color: palette.inserted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '−$deletions',
                        style: code.copyWith(
                          color: palette.removed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (counts && width >= 400) ...[
                      const SizedBox(width: 8),
                      _DiffStat(file: file, palette: palette),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PathText extends StatelessWidget {
  const _PathText({required this.file, required this.palette});

  final FileDiff file;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final style = palette.code.copyWith(fontWeight: FontWeight.w600);
    if (!file.isRenameOrCopy) {
      return Text(
        file.path,
        style: style,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }
    // The old path gets at most 40% of the room, so the new one, which
    // matters more, keeps the rest.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
            child: Text(
              file.oldPath ?? '',
              style: style.copyWith(
                color: palette.label,
                fontWeight: FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: ' → ',
                    style: style.copyWith(color: palette.label),
                  ),
                  TextSpan(text: file.newPath ?? '', style: style),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.style});

  final String label;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        label,
        style: style.copyWith(
          color: color,
          fontSize: (style.fontSize ?? 14) * 0.85,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    ),
  );
}

/// Five blocks showing the share of additions and deletions, like GitHub.
class _DiffStat extends StatelessWidget {
  const _DiffStat({required this.file, required this.palette});

  final FileDiff file;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final (:added, :removed) = file.changeBlocks();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < FileDiff.changeBarSize; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(left: 1.5),
            decoration: BoxDecoration(
              color: i < added
                  ? palette.inserted
                  : (i < added + removed ? palette.removed : palette.divider),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
      ],
    );
  }
}

class _HunkHeaderBar extends StatelessWidget {
  const _HunkHeaderBar({
    required this.hunk,
    required this.palette,
    this.collapsed = false,
    this.onToggle,
    this.style = HunkSeparatorStyle.lineInfo,
  });
  final bool collapsed;
  final VoidCallback? onToggle;
  final HunkSeparatorStyle style;

  final DiffHunk hunk;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final header = hunk.header;
    final text =
        onToggle == null ||
            style == HunkSeparatorStyle.metadata ||
            hunk.section.isEmpty
        ? header
        : hunk.section;
    return Material(
      color: palette.hunkBackground,
      child: InkWell(
        onTap: onToggle,
        child: Semantics(
          button: onToggle != null,
          excludeSemantics: onToggle != null,
          onTap: onToggle,
          label: onToggle == null
              ? null
              : '${collapsed ? 'Expand' : 'Collapse'} section ${hunk.section.isEmpty ? hunk.header : hunk.section}',
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: style == HunkSeparatorStyle.compact ? 2 : 6,
            ),
            child: Row(
              children: [
                if (onToggle != null) ...[
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    text,
                    style: palette.mutedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (collapsed)
                  Text('${hunk.lines.length} lines', style: palette.numberText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GapBar extends StatelessWidget {
  const _GapBar({
    required this.text,
    required this.palette,
    required this.onExpand,
    this.style = HunkSeparatorStyle.lineInfo,
  });

  final HunkSeparatorStyle style;
  final String text;
  final _Palette palette;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.hunkBackground,
    child: Semantics(
      button: true,
      child: InkWell(
        onTap: onExpand,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: style == HunkSeparatorStyle.compact ? 1 : 4,
          ),
          child: Row(
            children: [
              Icon(Icons.unfold_more, size: 16, color: palette.muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  style == HunkSeparatorStyle.minimal ? '⋯' : text,
                  style: palette.mutedText,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Line numbers and the `+`/`−` marker, kept out of text selection.
/// Screen readers hear whether the line was added or removed instead.
class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.numbers,
    required this.kind,
    required this.width,
    required this.palette,
    required this.labels,
  });

  /// The old and new numbers in the unified view, one of them when split.
  final List<int?> numbers;
  final DiffLineKind kind;
  final double width;
  final _Palette palette;
  final DiffLabels labels;

  @override
  Widget build(BuildContext context) {
    final style = palette.numberText;
    final (marker, markerColor) = switch (kind) {
      DiffLineKind.added => ('+', palette.inserted),
      DiffLineKind.removed => ('−', palette.removed),
      DiffLineKind.context => (' ', palette.muted),
    };
    final number = kind == DiffLineKind.removed ? numbers.first : numbers.last;
    return Semantics(
      // Context lines need no announcement before their code.
      label: kind == DiffLineKind.context
          ? null
          : labels.changedLine(kind, number),
      excludeSemantics: true,
      child: SelectionContainer.disabled(
        child: ColoredBox(
          color: palette.gutterBackground(kind),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (palette.lineNumbers)
                for (final n in numbers)
                  SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        n?.toString() ?? '',
                        textAlign: TextAlign.right,
                        style: style,
                      ),
                    ),
                  ),
              SizedBox(
                width: 20,
                child: Text(
                  palette.indicators == DiffIndicators.classic
                      ? marker
                      : palette.indicators == DiffIndicators.bars &&
                            kind != DiffLineKind.context
                      ? '┃'
                      : ' ',
                  textAlign: TextAlign.center,
                  style: style.copyWith(color: markerColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedLine extends StatelessWidget {
  const _UnifiedLine({
    required this.line,
    required this.spans,
    required this.gutterWidth,
    required this.palette,
    required this.labels,
  });

  final DiffLine line;
  final List<InlineSpan> spans;
  final double gutterWidth;
  final _Palette palette;
  final DiffLabels labels;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.lineBackground(line.kind),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Gutter(
            numbers: [line.oldNumber, line.newNumber],
            kind: line.kind,
            width: gutterWidth,
            palette: palette,
            labels: labels,
          ),
          Expanded(
            child: _Code(
              line: line,
              spans: spans,
              palette: palette,
              labels: labels,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SplitLine extends StatelessWidget {
  const _SplitLine({
    required this.left,
    required this.right,
    required this.leftSpans,
    required this.rightSpans,
    required this.gutterWidth,
    required this.palette,
    required this.labels,
  });

  final DiffLine? left;
  final DiffLine? right;
  final List<InlineSpan>? leftSpans;
  final List<InlineSpan>? rightSpans;
  final double gutterWidth;
  final _Palette palette;
  final DiffLabels labels;

  Widget _side(DiffLine? line, List<InlineSpan>? spans, {required bool old}) {
    if (line == null) return ColoredBox(color: palette.emptySide);
    // In the split view a context line is plain on both sides.
    return ColoredBox(
      color: palette.lineBackground(line.kind),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Gutter(
            numbers: [old ? line.oldNumber : line.newNumber],
            kind: line.kind,
            width: gutterWidth,
            palette: palette,
            labels: labels,
          ),
          Expanded(
            child: _Code(
              line: line,
              spans: spans!,
              palette: palette,
              labels: labels,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _side(left, leftSpans, old: true)),
        SizedBox(width: 1, child: ColoredBox(color: palette.divider)),
        Expanded(child: _side(right, rightSpans, old: false)),
      ],
    ),
  );
}

class _Code extends StatelessWidget {
  const _Code({
    required this.line,
    required this.spans,
    required this.palette,
    required this.labels,
  });

  final DiffLine line;
  final List<InlineSpan> spans;
  final _Palette palette;
  final DiffLabels labels;

  @override
  Widget build(BuildContext context) {
    Widget text = Text.rich(
      TextSpan(style: palette.code, children: spans),
      softWrap: palette.wrap,
    );
    if (!palette.wrap) {
      text = HorizontalCode(child: text);
    }
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: line.noNewlineAtEnd
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: text),
                SelectionContainer.disabled(
                  child: _NoNewlineMarker(
                    palette: palette,
                    message: labels.noNewlineAtEnd,
                  ),
                ),
              ],
            )
          : text,
    );
  }
}

/// Shown after a last line that has no line break, like GitHub does.
class _NoNewlineMarker extends StatelessWidget {
  const _NoNewlineMarker({required this.palette, required this.message});

  final _Palette palette;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Tooltip(
      message: message,
      child: SizedBox(
        height: palette.lineHeight,
        child: Icon(
          Icons.do_not_disturb_on_outlined,
          size: palette.lineHeight * 0.6,
          color: palette.removed,
        ),
      ),
    ),
  );
}
