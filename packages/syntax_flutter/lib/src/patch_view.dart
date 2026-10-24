import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:syntax_core/syntax.dart';

import 'chrome.dart';
import 'highlighter_scope.dart';
import 'horizontal_scroll.dart';
import 'indexed_viewport.dart';
import 'patch_rows.dart';
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
class PatchView extends StatefulWidget {
  /// Shows [files] as they are, with [collapsed] files and [expanded] gaps
  /// owned by the caller.
  const PatchView({
    super.key,
    required List<FileDiff> files,
    required this.theme,
    this.highlighter,
    this.language,
    this.mode = DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
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
    this.stickyHeaders = false,
    this.headerBuilder,
    this.hunkBuilder,
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
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
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
    this.stickyHeaders = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.scrollController,
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
    this.language,
    this.mode = DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
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
    this.stickyHeaders = false,
    this.headerBuilder,
    this.hunkBuilder,
    this.scrollController,
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
  State<PatchView> createState() => _PatchViewState();
}

const _sliceBudget = Duration(milliseconds: 6);

class _PatchViewState extends State<PatchView> {
  late ScrollController _scroll;
  int _stickyFile = 0;
  Object? _sourceKey, _highlightKey;
  List<FileDiff> _files = const [];
  final _horizontal = HorizontalCodeGroup();
  DiffHighlightCache? _highlights;
  bool _slicing = false;
  PatchPalette? _palette;

  void _syncSource() {
    final key = (widget._files, widget._patch, widget._texts);
    if (key == _sourceKey) return;
    _sourceKey = key;
    _files = switch (key) {
      (final files?, _, _) => files,
      (_, final patch?, _) => parsePatch(patch),
      (_, _, (final before, final after, final path, final context)?) => [
        diffTexts(before, after, path: path, contextLines: context),
      ],
      _ => const [],
    };
    _stickyFile = 0;
    _highlights = null;
  }

  DiffHighlightCache _highlightsFor(Highlighter highlighter) {
    final key = (
      widget.theme,
      highlighter,
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
    _syncSource();
  }

  @override
  void didUpdateWidget(PatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) _scroll.dispose();
      _scroll = widget.scrollController ?? ScrollController();
    }
    _syncSource();
  }

  @override
  void dispose() {
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

    Widget buildRow(BuildContext context, int index) {
      if (rows.isEmpty) {
        return PatchNoticeBar(text: labels.noFiles, palette: palette);
      }
      final row = _buildRow(rows[index], palette, highlighter, labels);
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
            itemCount: rows.isEmpty ? 1 : rows.length,
            itemBuilder: buildRow,
          )
        : IndexedCodeViewport(
            controller: _scroll,
            count: rows.isEmpty ? 1 : rows.length,
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
        DiffFileHeaderRow(index, collapsed: widget.collapsed.contains(index)),
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
    if (widget.selectable) list = SelectionArea(child: list);
    return SyntaxChrome(
      theme: widget.theme,
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
            onExpand: widget.onExpandGap == null
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
    final highlights = _highlightsFor(highlighter);
    final diff = _files[file];
    final highlighted = highlights.highlighted(diff, budget: _sliceBudget);
    if (!highlighted.isComplete) _finishLater();
    return [
      for (final segment in highlighted.segmentsFor(
        line,
        highlights.words(diff),
      ))
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
