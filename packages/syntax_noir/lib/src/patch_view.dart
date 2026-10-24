import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;

import 'colors.dart';
import 'patch_painter.dart';

/// A syntax-highlighted view of code changes for the terminal.
///
/// Show a `git diff` with [PatchView.fromPatch], compare two versions of a
/// file with [PatchView.fromTexts], or pass `FileDiff`s directly. Rows are
/// laid out by syntax's `layoutDiff`, so they match `syntax_flutter`'s
/// `PatchView`: file headers with change counts, `@@` lines, old and new
/// line numbers, highlighted changed words, and collapsed unchanged lines.
///
/// Each row is one terminal line unless [wrap] is set; long lines end in
/// `…` when not wrapped. Arrow keys move the selection, Alt+Left/Right
/// scrolls horizontally, and Enter on a file header calls [onToggleFile] or
/// on collapsed lines calls [onExpandGap].
class PatchView extends StatefulWidget {
  /// Shows [files] as they are, with [collapsed] files and [expanded] gaps
  /// owned by the caller.
  const PatchView({
    required List<syntax.FileDiff> files,
    required this.highlighter,
    required this.theme,
    this.language,
    this.mode = syntax.DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
    this.labels = const syntax.DiffLabels(),
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.inlineDiffMode = syntax.InlineDiffMode.mergedWords,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.wrap = false,
    this.headerBuilder,
    this.hunkBuilder,
    super.key,
  }) : _files = files,
       _patch = null,
       _texts = null;

  /// Shows a unified diff, such as the output of `git diff`.
  const PatchView.fromPatch(
    String patch, {
    required this.highlighter,
    required this.theme,
    this.language,
    this.mode = syntax.DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
    this.labels = const syntax.DiffLabels(),
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.inlineDiffMode = syntax.InlineDiffMode.mergedWords,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.wrap = false,
    this.headerBuilder,
    this.hunkBuilder,
    super.key,
  }) : _files = null,
       _patch = patch,
       _texts = null;

  /// Shows the changes from [oldText] to [newText], with [contextLines]
  /// unchanged lines around each change. [path] names the file and, unless
  /// [language] is set, picks the language.
  const PatchView.fromTexts({
    required String oldText,
    required String newText,
    required this.highlighter,
    required this.theme,
    String path = '',
    int contextLines = 3,
    this.language,
    this.mode = syntax.DiffMode.unified,
    this.collapsed = const {},
    this.expanded = const {},
    this.onToggleFile,
    this.onExpandGap,
    this.labels = const syntax.DiffLabels(),
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.inlineDiffMode = syntax.InlineDiffMode.mergedWords,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.wrap = false,
    this.headerBuilder,
    this.hunkBuilder,
    super.key,
  }) : _files = null,
       _patch = null,
       _texts = (oldText, newText, path, contextLines);

  final List<syntax.FileDiff>? _files;
  final String? _patch;
  final (String, String, String, int)? _texts;

  /// Provides the grammars.
  final syntax.Highlighter highlighter;

  /// Colors for code, line backgrounds and changed words.
  final syntax.SyntaxTheme theme;

  /// The language of every file. Defaults to guessing from each path.
  final String? language;

  /// Whether changes are shown in one column or side by side.
  final syntax.DiffMode mode;

  /// Zero-based indices of files whose lines are hidden.
  final Set<int> collapsed;

  /// Context gaps whose unchanged lines are shown.
  final Set<syntax.DiffGapId> expanded;

  /// Called when Enter is pressed on a file header.
  final void Function(int file)? onToggleFile;

  /// Called when Enter is pressed on a collapsed context gap.
  final void Function(syntax.DiffGapId id)? onExpandGap;

  /// The words the view shows. Extend `DiffLabels` to translate them.
  final syntax.DiffLabels labels;

  /// Rows of terminal height. Defaults to the height available.
  final int? height;

  /// Controls keyboard focus. One is created if null.
  final FocusNode? focusNode;

  /// Whether the view takes focus when it first appears.
  final bool autofocus;

  /// Inline comparison algorithm.
  final syntax.InlineDiffMode inlineDiffMode;

  /// Paints changed-line backgrounds.
  final bool showBackgrounds;

  /// Displays addition and deletion markers.
  final bool showChangeIndicators;

  /// Marker style independent of line backgrounds.
  final syntax.DiffIndicators indicators;

  /// Shows source numbers in the terminal gutters.
  final bool showLineNumbers;

  /// Presentation of context gaps and section metadata.
  final syntax.HunkSeparatorStyle hunkSeparatorStyle;

  /// Displays the selected file's header above the viewport.
  final bool stickyHeaders;

  /// Wraps source by terminal cells instead of clipping long lines.
  final bool wrap;

  /// Custom fixed-height file header.
  final Widget Function(BuildContext, syntax.FileDiff, bool)? headerBuilder;

  /// Custom fixed-height hunk separator.
  final Widget Function(BuildContext, syntax.FileDiff, syntax.DiffHunk)?
  hunkBuilder;

  @override
  State<PatchView> createState() => _PatchViewState();
}

class _PatchViewState extends State<PatchView> {
  int _horizontal = 0;
  syntax.RowHeightIndex? _heights;
  Object? _heightKey;
  Object? _sourceKey;
  List<syntax.FileDiff> _files = const [];
  int _selected = 0, _selectedSubrow = 0;

  Object? _highlightsKey;
  syntax.DiffHighlightCache? _highlights;
  Object? _painterKey;
  PatchPainter? _painter;

  void _syncSource() {
    final key = (widget._files, widget._patch, widget._texts);
    if (key == _sourceKey) return;
    _sourceKey = key;
    _files = switch (key) {
      (final files?, _, _) => files,
      (_, final patch?, _) => syntax.parsePatch(patch),
      (_, _, (final before, final after, final path, final context)?) => [
        syntax.diffTexts(before, after, path: path, contextLines: context),
      ],
      _ => const [],
    };
    _selected = 0;
    _selectedSubrow = 0;
  }

  List<syntax.DiffRow> _layout() => syntax.layoutDiff(
    _files,
    mode: widget.mode,
    collapsed: widget.collapsed,
    expanded: widget.expanded,
  );

  PatchPainter _painterFor() {
    // Keyed on the files, not the layout, so collapsing a file or showing
    // lines keeps what was already highlighted. Labels only renew the
    // painter, not the highlighting.
    final highlightsKey = (
      _files,
      widget.highlighter,
      widget.theme,
      widget.language,
      widget.inlineDiffMode,
    );
    if (highlightsKey != _highlightsKey || _highlights == null) {
      _highlightsKey = highlightsKey;
      _highlights = syntax.DiffHighlightCache(
        highlighter: widget.highlighter,
        theme: widget.theme,
        language: widget.language,
        inlineDiffMode: widget.inlineDiffMode,
      );
    }
    final painterKey = (
      _highlights,
      widget.labels,
      widget.showBackgrounds,
      widget.showChangeIndicators,
      widget.indicators,
      widget.showLineNumbers,
      widget.hunkSeparatorStyle,
    );
    if (painterKey != _painterKey || _painter == null) {
      _painterKey = painterKey;
      _painter = PatchPainter(
        files: _files,
        highlights: _highlights!,
        labels: widget.labels,
        showBackgrounds: widget.showBackgrounds,
        showChangeIndicators: widget.showChangeIndicators,
        indicators: widget.indicators,
        showLineNumbers: widget.showLineNumbers,
        hunkSeparatorStyle: widget.hunkSeparatorStyle,
      );
    }
    return _painter!;
  }

  void _activate(syntax.DiffRow row) {
    switch (row) {
      case syntax.DiffFileHeaderRow(:final file):
        widget.onToggleFile?.call(file);
      case syntax.DiffGapRow(:final id):
        widget.onExpandGap?.call(id);
      default:
    }
  }

  int _codeWidth(syntax.DiffRow row, int width) {
    final digits = widget.showLineNumbers
        ? '${math.max(_files[row.file].maxLineNumber, 1)}'.length
        : -1;
    return math.max(
      1,
      row is syntax.DiffPairRow
          ? (width - 2) ~/ 2 - digits - 3
          : width - digits * 2 - 5,
    );
  }

  int _visualRows(syntax.DiffRow row, int width) {
    if (!widget.wrap) return 1;
    final lines = switch (row) {
      syntax.DiffLineRow(:final line) => [line],
      syntax.DiffPairRow(:final left, :final right) => [?left, ?right],
      _ => <syntax.DiffLine>[],
    };
    var count = 1;
    for (final line in lines) {
      count = math.max(
        count,
        (terminalStringWidth(line.text.replaceAll('\t', '    ')) /
                _codeWidth(row, width))
            .ceil(),
      );
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    _syncSource();
  }

  @override
  void didUpdateWidget(PatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSource();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rows = _layout();
      final painter = _painterFor();
      final width = constraints.maxWidth ?? 80;
      final key = (
        _files,
        widget.mode,
        Object.hashAllUnordered(widget.collapsed),
        Object.hashAllUnordered(widget.expanded),
        width,
        widget.wrap,
        widget.showLineNumbers,
      );
      if (_heightKey != key) {
        _heightKey = key;
        _heights = syntax.RowHeightIndex(rows.length, estimatedHeight: 1);
        if (widget.wrap) {
          for (var i = 0; i < rows.length; i++) {
            _heights!.measure(i, _visualRows(rows[i], width).toDouble());
          }
        }
      }
      final heights = _heights!;
      _selected = _selected.clamp(0, math.max(0, rows.length - 1));
      final selected = rows.isEmpty ? null : rows[_selected];
      final file = selected == null ? null : _files[selected.file];
      final totalHeight = widget.height ?? constraints.maxHeight ?? 20;
      final height = math.max(
        1,
        totalHeight - (widget.stickyHeaders && file != null ? 1 : 0),
      );
      Widget view = ListView(
        itemCount: math.max(heights.offsetFor(rows.length).toInt(), 1),
        height: height,
        selectedIndex: rows.isEmpty
            ? null
            : heights.offsetFor(_selected).toInt() +
                  _selectedSubrow.clamp(
                    0,
                    _visualRows(rows[_selected], width) - 1,
                  ),
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        backgroundColor: noirColor(widget.theme.background),
        selectedBackgroundColor: noirColor(widget.theme.background),
        onChanged: (visual) {
          _selected = heights.rowAt(visual.toDouble());
          _selectedSubrow = visual - heights.offsetFor(_selected).toInt();
        },
        onSelect: (visual) {
          if (rows.isNotEmpty) {
            _activate(rows[heights.rowAt(visual.toDouble())]);
          }
        },
        itemBuilder: (context, visual, active) {
          if (rows.isEmpty) {
            return RichText(
              text: painter.empty(width: width),
              softWrap: false,
              maxLines: 1,
            );
          }
          final index = heights.rowAt(visual.toDouble());
          final row = rows[index];
          if (row is syntax.DiffFileHeaderRow && widget.headerBuilder != null) {
            return widget.headerBuilder!(
              context,
              _files[row.file],
              row.collapsed,
            );
          }
          if (row is syntax.DiffHunkHeaderRow && widget.hunkBuilder != null) {
            return widget.hunkBuilder!(context, _files[row.file], row.hunk);
          }
          final offset = widget.wrap
              ? (visual - heights.offsetFor(index).toInt()) *
                    _codeWidth(row, width)
              : _horizontal;
          return RichText(
            text: painter.paint(
              row,
              width: width,
              selected: active,
              codeOffset: offset,
              ellipsis: !widget.wrap,
            ),
            softWrap: false,
            maxLines: 1,
          );
        },
      );
      view = Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          if (!event.isPress || selected == null) return KeyEventResult.ignored;
          if (event.isAltPressed &&
              (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight)) {
            setState(() {
              _horizontal = math.max(
                0,
                _horizontal +
                    (event.logicalKey == LogicalKeyboardKey.arrowRight
                        ? 8
                        : -8),
              );
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: view,
      );
      if (!widget.stickyHeaders || file == null) return view;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.headerBuilder?.call(
                context,
                file,
                widget.collapsed.contains(selected!.file),
              ) ??
              Text(file.path),
          view,
        ],
      );
    },
  );
}
