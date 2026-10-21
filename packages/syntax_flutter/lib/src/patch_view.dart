import 'dart:math' as math;

import 'package:flutter/material.dart';
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
  Object? _sourceKey;
  List<FileDiff> _files = const [];
  final Set<int> _collapsed = {};
  final Set<DiffGapId> _expandedGaps = {};

  Object? _highlightKey;
  DiffHighlightCache? _highlights;
  _Palette? _palette;

  void _syncSource() {
    final key = (widget._files, widget._patch, widget._texts);
    if (key == _sourceKey) return;
    _sourceKey = key;
    _files = switch ((widget._files, widget._patch, widget._texts)) {
      (final files?, _, _) => files,
      (_, final patch?, _) => parsePatch(patch),
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
    final key = (widget.theme, highlighter, widget.language);
    if (key != _highlightKey || _highlights == null) {
      _highlightKey = key;
      _highlights = DiffHighlightCache(
        highlighter: highlighter,
        theme: widget.theme,
        language: widget.language,
      );
    }
    return _highlights!;
  }

  _Palette _paletteFor(BuildContext context) {
    final textStyle = widget.textStyle ?? defaultCodeTextStyle;
    final scaler = MediaQuery.textScalerOf(context);
    if (_palette case final p?
        when p.theme == widget.theme &&
            p.textStyle == textStyle &&
            p.scaler == scaler) {
      return p;
    }
    return _palette = _Palette(widget.theme, textStyle, scaler);
  }

  /// Bumped whenever the files, collapsed files or expanded gaps change.
  int _layoutVersion = 0;
  Object? _rowsKey;
  List<DiffRow> _rows = const [];

  List<DiffRow> _layout() {
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
    _syncSource();
  }

  @override
  void didUpdateWidget(PatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSource();
  }

  @override
  Widget build(BuildContext context) {
    final highlighter = widget.highlighter ?? HighlighterScope.of(context);
    final palette = _paletteFor(context);
    final labels = widget.labels;
    final rows = _layout();

    Widget list = ListView.builder(
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      itemCount: rows.isEmpty ? 1 : rows.length,
      itemBuilder: (context, index) {
        if (rows.isEmpty) return _notice(labels.noFiles, palette);
        final row = _buildRow(rows[index], palette, highlighter, labels);
        // Space between files.
        return index > 0 && rows[index - 1].file != rows[index].file
            ? Padding(padding: const EdgeInsets.only(top: 16), child: row)
            : row;
      },
    );
    if (widget.selectable) list = SelectionArea(child: list);
    return DefaultSelectionStyle(
      selectionColor: widget.theme.selectionColor,
      child: ColoredBox(
        color: palette.background,
        // Code reads left to right whatever the app's direction.
        child: Directionality(textDirection: TextDirection.ltr, child: list),
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
        return SelectionContainer.disabled(
          child: _FileHeaderBar(
            file: _files[file],
            collapsed: collapsed,
            palette: palette,
            labels: labels,
            onToggle: () => _toggle(() {
              _collapsed.contains(file)
                  ? _collapsed.remove(file)
                  : _collapsed.add(file);
            }),
          ),
        );
      case DiffNoticeRow(:final notice):
        return _notice(labels.notice(notice), palette);
      case DiffHunkHeaderRow(:final hunk):
        return SelectionContainer.disabled(
          child: _HunkHeaderBar(hunk: hunk, palette: palette),
        );
      case DiffGapRow(:final id, :final count):
        return SelectionContainer.disabled(
          child: _GapBar(
            text: labels.showUnchangedLines(count),
            palette: palette,
            onExpand: () => _toggle(() => _expandedGaps.add(id)),
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
  _Palette(this.theme, this.textStyle, this.scaler)
    : styles = TokenTextStyles(theme, base: textStyle) {
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
  Color gutterBackground(DiffLineKind kind) => switch (kind) {
    DiffLineKind.added => insertedLine,
    DiffLineKind.removed => removedLine,
    DiffLineKind.context => const Color(0x00000000),
  };

  Color lineBackground(DiffLineKind kind) => switch (kind) {
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
  const _HunkHeaderBar({required this.hunk, required this.palette});

  final DiffHunk hunk;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final style = palette.mutedText;
    final header = hunk.header;
    // The section, such as the enclosing function, ends the header.
    final sectionStart = header.length - hunk.section.length;
    return Container(
      color: palette.hunkBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: header.substring(0, sectionStart), style: style),
            TextSpan(
              text: header.substring(sectionStart),
              style: style.copyWith(color: palette.foreground),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _GapBar extends StatelessWidget {
  const _GapBar({
    required this.text,
    required this.palette,
    required this.onExpand,
  });

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.unfold_more, size: 16, color: palette.muted),
              const SizedBox(width: 8),
              Text(text, style: palette.mutedText),
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
                  marker,
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
    final text = Text.rich(TextSpan(style: palette.code, children: spans));
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
