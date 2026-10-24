import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:syntax/syntax.dart';

import 'chrome.dart';
import 'highlighter_scope.dart';
import 'horizontal_scroll.dart';
import 'indexed_viewport.dart';
import 'styles.dart';

/// A syntax-highlighted view of code changes.
///
/// Show a `git diff` with [PatchView.fromPatch], compare two versions of a
/// file with [PatchView.fromTexts], or pass [FileDiff]s directly.
class PatchView extends StatefulWidget {
  /// Shows [files] with caller-owned [collapsed] and [expanded] sets.
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
  _Palette? _palette;

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

  _Palette _paletteFor(BuildContext context) {
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
    return _palette = _Palette(
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
    if (key.$2 == 'hunk') return rows.rowForSection(file, key.$3);
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
      if (rows.isEmpty) return _notice(labels.noFiles, palette);
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
      list = Column(
        children: [
          _buildRow(
            DiffFileHeaderRow(
              index,
              collapsed: widget.collapsed.contains(index),
            ),
            palette,
            highlighter,
            labels,
          ),
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
    _Palette palette,
    Highlighter highlighter,
    DiffLabels labels,
  ) {
    switch (row) {
      case DiffFileHeaderRow(:final file, :final collapsed):
        void toggle() => widget.onToggleFile?.call(file);
        final header = widget.headerBuilder != null
            ? widget.headerBuilder!(context, _files[file], collapsed, toggle)
            : _fileHeaderBar(
                _files[file],
                collapsed,
                palette,
                labels,
                widget.onToggleFile == null ? null : toggle,
              );
        return SelectionContainer.disabled(child: header);
      case DiffNoticeRow(:final notice):
        return _notice(labels.notice(notice), palette);
      case DiffHunkHeaderRow(:final hunk):
        if (widget.hunkBuilder case final builder?) {
          return SelectionContainer.disabled(
            child: builder(context, _files[row.file], hunk),
          );
        }
        final baseStyle = palette.mutedText;
        final style = widget.hunkSeparatorStyle;
        final header =
            style != HunkSeparatorStyle.compact || hunk.section.isEmpty
            ? hunk.header
            : hunk.section;
        final sectionStart = header.length - hunk.section.length;
        return SelectionContainer.disabled(
          child: Container(
            color: palette.hunkBackground,
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: style == HunkSeparatorStyle.compact ? 2 : 3,
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: header.substring(0, sectionStart),
                    style: baseStyle,
                  ),
                  TextSpan(
                    text: header.substring(sectionStart),
                    style: baseStyle.copyWith(color: palette.foreground),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      case DiffGapRow(:final id, :final count):
        final style = widget.hunkSeparatorStyle;
        return SelectionContainer.disabled(
          child: Material(
            color: palette.hunkBackground,
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: widget.onExpandGap == null
                    ? null
                    : () => widget.onExpandGap!(id),
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
                          style == HunkSeparatorStyle.minimal
                              ? '⋯'
                              : labels.showUnchangedLines(count),
                          style: palette.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      case DiffLineRow(:final file, :final line):
        return ColoredBox(
          color: palette.lineBackground(line.kind),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _gutterCell(
                  [line.oldNumber, line.newNumber],
                  line.kind,
                  palette.gutterWidth(_files[file]),
                  palette,
                  labels,
                ),
                Expanded(
                  child: _codeCell(file, line, highlighter, palette, labels),
                ),
              ],
            ),
          ),
        );
      case DiffPairRow(:final file, :final left, :final right):
        final gutterWidth = palette.gutterWidth(_files[file]);
        Widget side(DiffLine? line, {required bool old}) {
          if (line == null) return ColoredBox(color: palette.emptySide);
          return ColoredBox(
            color: palette.lineBackground(line.kind),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _gutterCell(
                  [old ? line.oldNumber : line.newNumber],
                  line.kind,
                  gutterWidth,
                  palette,
                  labels,
                ),
                Expanded(
                  child: _codeCell(file, line, highlighter, palette, labels),
                ),
              ],
            ),
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: side(left, old: true)),
              SizedBox(width: 1, child: ColoredBox(color: palette.divider)),
              Expanded(child: side(right, old: false)),
            ],
          ),
        );
    }
  }

  Widget _codeCell(
    int file,
    DiffLine line,
    Highlighter highlighter,
    _Palette palette,
    DiffLabels labels,
  ) {
    Widget text = Text.rich(
      TextSpan(
        style: palette.code,
        children: _spans(file, line, highlighter, palette),
      ),
      softWrap: palette.wrap,
    );
    if (!palette.wrap) text = HorizontalCode(child: text);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: line.noNewlineAtEnd
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: text),
                SelectionContainer.disabled(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Tooltip(
                      message: labels.noNewlineAtEnd,
                      child: SizedBox(
                        height: palette.lineHeight,
                        child: Icon(
                          Icons.do_not_disturb_on_outlined,
                          size: palette.lineHeight * 0.6,
                          color: palette.removed,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : text,
    );
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

final class _Palette {
  _Palette(
    this.theme,
    this.textStyle,
    this.scaler, {
    this.wrap = true,
    this.backgrounds = true,
    this.indicators = DiffIndicators.classic,
    this.lineNumbers = true,
  }) : styles = TokenTextStyles(theme, base: textStyle),
       diff = DiffColors.of(theme);

  final bool wrap, backgrounds, lineNumbers;
  final DiffIndicators indicators;
  final SyntaxTheme theme;
  final TextStyle textStyle;
  final TextScaler scaler;
  final TokenTextStyles styles;
  final DiffColors diff;

  Color get inserted => Color(diff.inserted);
  Color get removed => Color(diff.removed);
  Color get insertedLine => Color(diff.insertedLine);
  Color get removedLine => Color(diff.removedLine);
  Color get insertedText => Color(diff.insertedText);
  Color get removedText => Color(diff.removedText);
  Color get headerBackground => Color(diff.fileHeader);
  Color get hunkBackground => Color(diff.hunkHeader);
  Color get emptySide => Color(diff.emptySide);
  Color get divider => Color(diff.divider);
  Color get label => Color(diff.muted);

  Color get background => theme.backgroundColor;
  Color get foreground => theme.foregroundColor;
  Color get muted => theme.lineNumberColor;
  TextStyle get code => styles.base;
  late final TextStyle numberText = code.copyWith(color: muted);
  late final TextStyle mutedText = code.copyWith(color: label);

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

  TextPainter _measure(String text) => TextPainter(
    text: TextSpan(text: text, style: code),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();

  late final (double height, String widestDigit) _digitMetrics = () {
    final zero = _measure('0');
    final height = zero.height;
    var widest = '0';
    var widestWidth = zero.width;
    zero.dispose();
    for (var d = 1; d <= 9; d++) {
      final painter = _measure('$d');
      if (painter.width > widestWidth) {
        widest = '$d';
        widestWidth = painter.width;
      }
      painter.dispose();
    }
    return (height, widest);
  }();

  double get lineHeight => _digitMetrics.$1;
  final Map<FileDiff, double> _gutterWidths = Map.identity();

  double gutterWidth(FileDiff file) => _gutterWidths.putIfAbsent(file, () {
    final digits = '${math.max(file.maxLineNumber, 1)}'.length;
    final painter = _measure(_digitMetrics.$2 * digits);
    final width = painter.width + 16;
    painter.dispose();
    return width;
  });
}

Widget _fileHeaderBar(
  FileDiff file,
  bool collapsed,
  _Palette palette,
  DiffLabels labels,
  VoidCallback? onToggle,
) {
  final code = palette.code;
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final counts = !file.isBinary && width >= 180;
              final (:added, :removed) = file.changeBlocks();
              final pathStyle = code.copyWith(fontWeight: FontWeight.w600);
              return Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 18,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 4),
                  if (label != null && width >= 260) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        child: Text(
                          label,
                          style: code.copyWith(
                            color: color,
                            fontSize: (code.fontSize ?? 14) * 0.85,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: !file.isRenameOrCopy
                        ? Text(
                            file.path,
                            style: pathStyle,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          )
                        : LayoutBuilder(
                            builder: (context, inner) => Row(
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: inner.maxWidth * 0.4,
                                  ),
                                  child: Text(
                                    file.oldPath ?? '',
                                    style: pathStyle.copyWith(
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
                                          style: pathStyle.copyWith(
                                            color: palette.label,
                                          ),
                                        ),
                                        TextSpan(
                                          text: file.newPath ?? '',
                                          style: pathStyle,
                                        ),
                                      ],
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (counts) ...[
                    const SizedBox(width: 12),
                    Text(
                      '+${file.additions}',
                      style: code.copyWith(
                        color: palette.inserted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '−${file.deletions}',
                      style: code.copyWith(
                        color: palette.removed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (counts && width >= 400) ...[
                    const SizedBox(width: 8),
                    Row(
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
                                  : (i < added + removed
                                        ? palette.removed
                                        : palette.divider),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                      ],
                    ),
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

Widget _gutterCell(
  List<int?> numbers,
  DiffLineKind kind,
  double width,
  _Palette palette,
  DiffLabels labels,
) {
  final style = palette.numberText;
  final (marker, markerColor) = switch (kind) {
    DiffLineKind.added => ('+', palette.inserted),
    DiffLineKind.removed => ('−', palette.removed),
    DiffLineKind.context => (' ', palette.muted),
  };
  final number = kind == DiffLineKind.removed ? numbers.first : numbers.last;
  return Semantics(
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
