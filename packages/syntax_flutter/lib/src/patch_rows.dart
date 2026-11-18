import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

import 'chrome_action.dart';
import 'chrome_glyph.dart';
import 'chrome_scope.dart';
import 'horizontal_scroll.dart';
import 'selection_chrome.dart';
import 'styles.dart';

/// Colors and text styles derived from the theme, shared by every row of a
/// [PatchView].
final class PatchPalette {
  /// Computes diff colors and text styles for [theme], [textStyle] and
  /// [scaler].
  PatchPalette(
    this.theme,
    this.textStyle,
    this.scaler, {
    this.wrap = true,
    this.backgrounds = true,
    this.indicators = DiffIndicators.classic,
    this.lineNumbers = true,
  }) : styles = TokenTextStyles(theme, base: textStyle),
       diff = DiffColors.of(theme);

  /// Whether long lines wrap instead of scrolling horizontally.
  final bool wrap;

  /// Whether added and removed lines paint tinted backgrounds.
  final bool backgrounds;

  /// Whether old and new line numbers are shown in the gutter.
  final bool lineNumbers;

  /// Change indicator style in the gutter.
  final DiffIndicators indicators;

  /// The syntax theme.
  final SyntaxTheme theme;

  /// The base text style.
  final TextStyle textStyle;

  /// The active text scaler.
  final TextScaler scaler;

  /// Cached token text styles.
  final TokenTextStyles styles;

  /// Diff chrome and line colors from [theme].
  final DiffColors diff;

  /// Accent color for additions.
  Color get inserted => Color(diff.inserted);

  /// Accent color for removals.
  Color get removed => Color(diff.removed);

  /// Background color of an added line.
  Color get insertedLine => Color(diff.insertedLine);

  /// Background color of a removed line.
  Color get removedLine => Color(diff.removedLine);

  /// Background color of changed words in an added line.
  Color get insertedText => Color(diff.insertedText);

  /// Background color of changed words in a removed line.
  Color get removedText => Color(diff.removedText);

  /// Background color of a file header.
  Color get headerBackground => Color(diff.fileHeader);

  /// Background color of a hunk header, notice or collapsed gap.
  Color get hunkBackground => Color(diff.hunkHeader);

  /// Background color of an empty side in split view.
  Color get emptySide => Color(diff.emptySide);

  /// Divider color between split panes and neutral diff stat blocks.
  Color get divider => Color(diff.divider);

  /// Muted label color for headers, notices and gaps.
  Color get label => Color(diff.muted);

  /// Editor background color.
  Color get background => theme.backgroundColor;

  /// Editor foreground color.
  Color get foreground => theme.foregroundColor;

  /// Line-number foreground color.
  Color get muted => theme.lineNumberColor;

  /// Base code text style.
  TextStyle get code => styles.base;

  /// Style for line numbers in the gutter.
  late final TextStyle numberText = code.copyWith(color: muted);

  /// Style for muted labels in headers, notices and gaps.
  late final TextStyle mutedText = code.copyWith(color: label);

  /// Gutter background color for a line of [kind].
  Color gutterBackground(DiffLineKind kind) => !backgrounds
      ? background
      : switch (kind) {
          DiffLineKind.added => insertedLine,
          DiffLineKind.removed => removedLine,
          DiffLineKind.context => const Color(0x00000000),
        };

  /// Line background color for a line of [kind].
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

  /// Height of one line of code.
  double get lineHeight => _digitMetrics.$1;
  // A palette outlives source revisions; measured widths must not retain them.
  final _gutterWidths = Expando<double>();

  /// Width of one line-number column, sized for [file]'s largest line number
  /// using the widest digit (`0`–`9`).
  double gutterWidth(FileDiff file) => _gutterWidths[file] ??= (() {
    final digits = '${math.max(file.maxLineNumber, 1)}'.length;
    final painter = _measure(_digitMetrics.$2 * digits);
    final width = painter.width + 16;
    painter.dispose();
    return width;
  })();
}

/// A notice row shown when there are no files or a file has no lines.
class PatchNoticeBar extends StatelessWidget {
  /// Creates a notice bar with [text].
  const PatchNoticeBar({super.key, required this.text, required this.palette});

  /// Notice message.
  final String text;

  /// Shared palette.
  final PatchPalette palette;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Container(
      color: palette.hunkBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text, style: palette.mutedText),
    ),
  );
}

/// Header bar for a single [FileDiff].
class PatchFileHeaderBar extends StatelessWidget {
  /// Creates a file header bar.
  const PatchFileHeaderBar({
    super.key,
    required this.file,
    required this.collapsed,
    required this.palette,
    required this.labels,
    required this.onToggle,
  });

  /// The file being summarized.
  final FileDiff file;

  /// Whether the file's lines are collapsed.
  final bool collapsed;

  /// Shared palette.
  final PatchPalette palette;

  /// Labels for status and accessibility.
  final DiffLabels labels;

  /// Callback when the header is tapped.
  final VoidCallback? onToggle;

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
    return Container(
      decoration: BoxDecoration(
        color: palette.headerBackground,
        borderRadius: radius,
      ),
      child: buildSyntaxAction(
        context,
        SyntaxChromeScope.of(context),
        SyntaxChromeAction(
          kind: SyntaxChromeActionKind.toggleFile,
          label: labels.fileHeader(file),
          onInvoke: onToggle,
          expanded: !collapsed,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 12, 7),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final counts = !file.isBinary && width >= 180;
              return Row(
                children: [
                  SyntaxGlyph(
                    kind: collapsed
                        ? SyntaxGlyphKind.collapsed
                        : SyntaxGlyphKind.expanded,
                    size: 18,
                    color: palette.muted,
                  ),
                  const SizedBox(width: 4),
                  if (label != null && width >= 260) ...[
                    PatchStatusBadge(label: label, color: color, style: code),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: PatchPathText(file: file, palette: palette),
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
                    PatchDiffStat(file: file, palette: palette),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Displays a file's path, or `oldPath → newPath` for renames and copies.
class PatchPathText extends StatelessWidget {
  /// Creates a path text widget.
  const PatchPathText({super.key, required this.file, required this.palette});

  /// The file whose path is shown.
  final FileDiff file;

  /// Shared palette.
  final PatchPalette palette;

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

/// Status badge shown in a file header (e.g. `Added`, `Renamed`).
class PatchStatusBadge extends StatelessWidget {
  /// Creates a status badge.
  const PatchStatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.style,
  });

  /// Badge text.
  final String label;

  /// Accent color.
  final Color color;

  /// Base text style.
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
class PatchDiffStat extends StatelessWidget {
  /// Creates a diff stat bar.
  const PatchDiffStat({super.key, required this.file, required this.palette});

  /// The file whose change blocks are shown.
  final FileDiff file;

  /// Shared palette.
  final PatchPalette palette;

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

/// Hunk header row (`@@ ... @@`).
class PatchHunkHeaderBar extends StatelessWidget {
  /// Creates a hunk header bar.
  const PatchHunkHeaderBar({
    super.key,
    required this.hunk,
    required this.palette,
    this.style = HunkSeparatorStyle.lineInfo,
  });

  /// The hunk this header starts.
  final DiffHunk hunk;

  /// Shared palette.
  final PatchPalette palette;

  /// Separator presentation style.
  final HunkSeparatorStyle style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = palette.mutedText;
    final header = style != HunkSeparatorStyle.compact || hunk.section.isEmpty
        ? hunk.header
        : hunk.section;
    final sectionStart = header.length - hunk.section.length;
    return Container(
      color: palette.hunkBackground,
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: style == HunkSeparatorStyle.compact ? 2 : 3,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: header.substring(0, sectionStart), style: baseStyle),
            TextSpan(
              text: header.substring(sectionStart),
              style: baseStyle.copyWith(color: palette.foreground),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Expandable bar representing hidden unchanged context lines.
class PatchGapBar extends StatelessWidget {
  /// Creates a gap bar.
  const PatchGapBar({
    super.key,
    required this.text,
    required this.palette,
    required this.onExpand,
    this.style = HunkSeparatorStyle.lineInfo,
  });

  /// Separator presentation style.
  final HunkSeparatorStyle style;

  /// Label describing the hidden line count.
  final String text;

  /// Shared palette.
  final PatchPalette palette;

  /// Callback when the gap bar is tapped.
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.hunkBackground,
    child: buildSyntaxAction(
      context,
      SyntaxChromeScope.of(context),
      SyntaxChromeAction(
        kind: SyntaxChromeActionKind.expandGap,
        label: text,
        onInvoke: onExpand,
      ),
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: style == HunkSeparatorStyle.compact ? 1 : 4,
        ),
        child: Row(
          children: [
            SyntaxGlyph(
              kind: SyntaxGlyphKind.gap,
              size: 16,
              color: palette.muted,
            ),
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
  );
}

/// The code cell of a diff line, with optional horizontal scrolling and
/// missing-final-newline marker.
class PatchCodeCell extends StatelessWidget {
  /// Creates a code cell for [line].
  const PatchCodeCell({
    super.key,
    required this.line,
    required this.spans,
    required this.palette,
    required this.labels,
  });

  /// The diff line.
  final DiffLine line;

  /// Highlighted spans.
  final List<InlineSpan> spans;

  /// Shared palette.
  final PatchPalette palette;

  /// Labels for accessibility.
  final DiffLabels labels;

  @override
  Widget build(BuildContext context) {
    Widget text = Text.rich(
      TextSpan(style: palette.code, children: spans),
      // Text's root style must match its spans: older Flutter versions use it
      // for caret metrics and otherwise hide the end handle outside the row.
      style: palette.code,
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
                  child: PatchNoNewlineMarker(
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
class PatchNoNewlineMarker extends StatelessWidget {
  /// Creates a missing-newline marker.
  const PatchNoNewlineMarker({
    super.key,
    required this.palette,
    required this.message,
  });

  /// Shared palette.
  final PatchPalette palette;

  /// Accessible description of the missing line break.
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Semantics(
      container: true,
      label: message,
      excludeSemantics: true,
      child:
          SyntaxChromeScope.of(
            context,
          ).noNewlineMarkerBuilder?.call(context, message) ??
          SizedBox(
            height: palette.lineHeight,
            child: Center(
              child: SyntaxGlyph(
                kind: SyntaxGlyphKind.noNewline,
                size: palette.lineHeight * 0.6,
                color: palette.removed,
              ),
            ),
          ),
    ),
  );
}
