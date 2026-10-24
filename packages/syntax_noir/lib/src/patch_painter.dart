import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:syntax_darts/syntax.dart' as syntax;

import 'colors.dart';

/// Paints the rows from syntax's `layoutDiff` as noir text, one terminal
/// line per row.
///
/// Every line is cut or padded to exactly the given width, so line
/// backgrounds fill the row. A cut line ends in `…`, colored like a changed
/// word when it hides one. In split mode each side gets half. Colors are
/// opaque, painted over the theme's background, and control characters
/// are shown as `` so diff text can't send escape sequences to the
/// terminal.
final class PatchPainter {
  /// A painter for [files], highlighted by [highlights], which a view can
  /// keep across painters so files are only highlighted once.
  PatchPainter({
    required this.files,
    required this.highlights,
    this.labels = const syntax.DiffLabels(),
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
  }) : _colors = syntax.DiffColors.of(highlights.theme) {
    final background = theme.background;
    _addedLine = syntax.alphaBlend(_colors.insertedLine, background);
    _removedLine = syntax.alphaBlend(_colors.removedLine, background);
    _addedWord = syntax.alphaBlend(_colors.insertedText, _addedLine);
    _removedWord = syntax.alphaBlend(_colors.removedText, _removedLine);
  }

  /// The files the rows refer to by index.
  final List<syntax.FileDiff> files;

  /// Highlighting and changed words per file.
  final syntax.DiffHighlightCache highlights;

  /// The words shown in headers, notices and collapsed lines.
  final syntax.DiffLabels labels;

  /// Whether changed lines receive a tinted background.
  final bool showBackgrounds;

  /// Whether gutters display addition and deletion markers.
  final bool showChangeIndicators;

  /// Marker style independent of line backgrounds.
  final syntax.DiffIndicators indicators;

  /// Shows source line numbers in gutters.
  final bool showLineNumbers;

  /// Presentation of gaps and section metadata.
  final syntax.HunkSeparatorStyle hunkSeparatorStyle;

  final syntax.DiffColors _colors;
  late final int _addedLine;
  late final int _removedLine;
  late final int _addedWord;
  late final int _removedWord;
  final Map<int, int> _digits = {};

  /// The theme, from [highlights].
  syntax.SyntaxTheme get theme => highlights.theme;

  /// [row] as one line of [width] cells. A [selected] row gets a marker in
  /// its first cell.
  TextSpan paint(
    syntax.DiffRow row, {
    required int width,
    bool selected = false,
    int codeOffset = 0,
    bool ellipsis = true,
  }) {
    final out = _LineBuilder(width, ellipsis: ellipsis);
    final base = switch (row) {
      syntax.DiffFileHeaderRow() => _colors.fileHeader,
      syntax.DiffLineRow(:final line) => _lineBackground(line.kind),
      syntax.DiffPairRow() => theme.background,
      _ => _colors.hunkHeader,
    };
    out.add(
      selected ? '▌' : ' ',
      TextStyle(
        color: noirColor(theme.cursorForeground, over: base),
        backgroundColor: noirColor(base),
      ),
    );
    switch (row) {
      case syntax.DiffFileHeaderRow(:final file, :final collapsed):
        _fileHeader(out, files[file], collapsed);
      case syntax.DiffNoticeRow(:final notice):
        out.add(labels.notice(notice), _muted(base));
      case syntax.DiffHunkHeaderRow(:final hunk, :final collapsed):
        if (collapsed) out.add('▸ ', _muted(base));
        final header =
            hunkSeparatorStyle != syntax.HunkSeparatorStyle.compact ||
                hunk.section.isEmpty
            ? hunk.header
            : hunk.section;
        final sectionStart = header.length - hunk.section.length;
        out
          ..add(header.substring(0, sectionStart), _muted(base))
          ..add(
            header.substring(sectionStart),
            TextStyle(
              color: noirColor(theme.foreground, over: base),
              backgroundColor: noirColor(base),
            ),
          );
      case syntax.DiffGapRow(:final count):
        out.add(
          hunkSeparatorStyle == syntax.HunkSeparatorStyle.minimal
              ? '⋯'
              : '⋯ ${labels.showUnchangedLines(count)}',
          _muted(base),
        );
      case syntax.DiffLineRow(:final file, :final line):
        _gutter(out, file, line, [line.oldNumber, line.newNumber]);
        _code(out, file, line, codeOffset);
      case syntax.DiffPairRow(:final file, :final left, :final right):
        final half = (width - 2) ~/ 2;
        _side(out, file, left, old: true, width: half, codeOffset: codeOffset);
        out.add(
          '│',
          TextStyle(
            color: noirColor(_colors.divider),
            backgroundColor: noirColor(theme.background),
          ),
        );
        _side(
          out,
          file,
          right,
          old: false,
          width: width - 2 - half,
          codeOffset: codeOffset,
        );
    }
    out.fill(TextStyle(backgroundColor: noirColor(base)));
    return out.build();
  }

  /// The line shown when there are no files at all.
  TextSpan empty({required int width}) {
    final base = _colors.hunkHeader;
    return (_LineBuilder(width)
          ..add(' ${labels.noFiles}', _muted(base))
          ..fill(TextStyle(backgroundColor: noirColor(base))))
        .build();
  }

  void _fileHeader(_LineBuilder out, syntax.FileDiff file, bool collapsed) {
    final base = _colors.fileHeader;
    out.add(collapsed ? '▸ ' : '▾ ', _muted(base));
    if (labels.status(file.kind) case final status?) {
      final accent = switch (file.kind) {
        syntax.FileDiffKind.added => _colors.inserted,
        syntax.FileDiffKind.deleted => _colors.removed,
        _ => _colors.muted,
      };
      out.add('$status ', _bold(accent, base));
    }
    if (file.isRenameOrCopy) out.add('${file.oldPath} → ', _muted(base));
    out.add(file.path, _bold(theme.foreground, base));
    if (file.isBinary) return;
    out
      ..add('  +${file.additions}', _bold(_colors.inserted, base))
      ..add(' −${file.deletions} ', _bold(_colors.removed, base));
    final (:added, :removed) = file.changeBlocks();
    for (var i = 0; i < syntax.FileDiff.changeBarSize; i++) {
      final color = i < added
          ? _colors.inserted
          : (i < added + removed ? _colors.removed : _colors.divider);
      out.add('■', _bold(color, base));
    }
  }

  void _side(
    _LineBuilder out,
    int file,
    syntax.DiffLine? line, {
    required bool old,
    required int width,
    int codeOffset = 0,
  }) {
    final side = _LineBuilder(width, ellipsis: out.ellipsis);
    if (line == null) {
      side.fill(TextStyle(backgroundColor: noirColor(_colors.emptySide)));
    } else {
      _gutter(side, file, line, [old ? line.oldNumber : line.newNumber]);
      _code(side, file, line, codeOffset);
      side.fill(
        TextStyle(backgroundColor: noirColor(_lineBackground(line.kind))),
      );
    }
    out.addAll(side);
  }

  /// Line [numbers] and the `+`/`−` marker.
  void _gutter(
    _LineBuilder out,
    int file,
    syntax.DiffLine line,
    List<int?> numbers,
  ) {
    final base = _lineBackground(line.kind);
    final digits = _digits[file] ??=
        '${math.max(files[file].maxLineNumber, 1)}'.length;
    final numberStyle = TextStyle(
      color: noirColor(theme.lineNumberForeground, over: base),
      backgroundColor: noirColor(base),
    );
    for (final n in showLineNumbers ? numbers : <int?>[]) {
      out.add('${(n?.toString() ?? '').padLeft(digits)} ', numberStyle);
    }
    final (marker, color) = switch (line.kind) {
      syntax.DiffLineKind.added => ('+', _colors.inserted),
      syntax.DiffLineKind.removed => ('−', _colors.removed),
      syntax.DiffLineKind.context => (' ', _colors.muted),
    };
    out.add(
      !showChangeIndicators || indicators == syntax.DiffIndicators.none
          ? '  '
          : indicators == syntax.DiffIndicators.bars &&
                line.kind != syntax.DiffLineKind.context
          ? '┃ '
          : '$marker ',
      _bold(color, base),
    );
  }

  void _code(_LineBuilder out, int file, syntax.DiffLine line, int codeOffset) {
    var skipped = 0;
    final base = _lineBackground(line.kind);
    final word = switch (line.kind) {
      syntax.DiffLineKind.added => _addedWord,
      syntax.DiffLineKind.removed => _removedWord,
      syntax.DiffLineKind.context => null,
    };
    for (final segment in highlights.segmentsFor(files[file], line)) {
      final changed = segment.changed && word != null;
      // A changed word's emphasis replaces the token's own background.
      final style = changed
          ? syntax.TokenStyle(
              foreground: segment.style.foreground,
              fontStyle: segment.style.fontStyle,
            )
          : segment.style;
      final background = changed ? word : base;
      final expanded = segment.text.replaceAll('\t', '    ');
      final size = terminalStringWidth(expanded);
      if (skipped + size <= codeOffset) {
        skipped += size;
        continue;
      }
      final skip = math.max(0, codeOffset - skipped);
      final prefix = sliceByCells(expanded, skip);
      final missing = skip - terminalStringWidth(prefix);
      var visible = expanded.substring(prefix.length);
      if (missing > 0 && visible.isNotEmpty) {
        final map = TextIndexMap(visible);
        visible = ' ${visible.substring(map.graphemeToUtf16(1))}';
      }
      skipped += size;
      out.add(
        visible,
        noirTextStyle(style, background: background).copyWith(
          backgroundColor: noirColor(
            style.background ?? background,
            over: background,
          ),
        ),
        changed: changed,
      );
    }
    if (line.noNewlineAtEnd) out.add(' ⊘', _muted(base));
  }

  int _lineBackground(syntax.DiffLineKind kind) => !showBackgrounds
      ? theme.background
      : switch (kind) {
          syntax.DiffLineKind.added => _addedLine,
          syntax.DiffLineKind.removed => _removedLine,
          syntax.DiffLineKind.context => theme.background,
        };

  TextStyle _muted(int background) => TextStyle(
    color: noirColor(_colors.muted),
    backgroundColor: noirColor(background),
  );

  TextStyle _bold(int color, int background) => TextStyle(
    color: noirColor(color, over: background),
    backgroundColor: noirColor(background),
    fontWeight: FontWeight.bold,
  );
}

/// C0 and C1 control characters, which a terminal may act on.
final RegExp _control = RegExp('[\\x00-\\x1F\\x7F-\\x9F]');

/// Collects spans up to a fixed number of terminal cells. Text that doesn't
/// fit is cut, and the last cell shows `…` instead.
final class _LineBuilder {
  _LineBuilder(this.width, {this.ellipsis = true});

  final bool ellipsis;

  final int width;
  final List<TextSpan> _spans = [];
  int _used = 0;

  /// Where `…` is in [_spans] once text was cut. Nothing shows after it.
  int? _cut;
  bool _cutChanged = false;

  /// Adds [text], cut at the width. `…` takes the style of the text it
  /// cut, or of the first [changed] text after it, so a change past the
  /// cut still shows.
  void add(String text, TextStyle style, {bool changed = false}) {
    if (text.isEmpty) return;
    if (_cut case final cut?) {
      if (changed && !_cutChanged) {
        _spans[cut] = TextSpan(text: '…', style: style);
        _cutChanged = true;
      }
      return;
    }
    final safe = text.replaceAll(_control, '\uFFFD');
    final fits = sliceByCells(safe, width - _used);
    if (fits.isNotEmpty) {
      _spans.add(TextSpan(text: fits, style: style));
      _used += terminalStringWidth(fits);
    }
    // A wide character that doesn't fit cuts the line too.
    if (ellipsis && fits.length < safe.length) {
      _cutWith(style, changed: changed);
    }
  }

  /// Ends the line with `…` in its last cell, taking the cell back from the
  /// text before it.
  void _cutWith(TextStyle style, {required bool changed}) {
    var gapStyle = style;
    while (_used >= width && _spans.isNotEmpty) {
      final last = _spans.removeLast();
      final text = last.text!;
      gapStyle = last.style ?? style;
      _used -= terminalStringWidth(text);
      final kept = sliceByCells(text, width - 1 - _used);
      if (kept.isNotEmpty) {
        _spans.add(TextSpan(text: kept, style: last.style));
        _used += terminalStringWidth(kept);
      }
    }
    if (_used >= width) return;
    // Taking back a wide character frees two cells.
    if (_used < width - 1) {
      _spans.add(TextSpan(text: ' ' * (width - 1 - _used), style: gapStyle));
      _used = width - 1;
    }
    _cut = _spans.length;
    _cutChanged = changed;
    _spans.add(TextSpan(text: '…', style: style));
    _used++;
  }

  /// Adds the spans of [other], which must fit.
  void addAll(_LineBuilder other) {
    _spans.addAll(other._spans);
    _used += other._used;
  }

  /// Pads with spaces to the width, also after a cut.
  void fill(TextStyle style) {
    if (_used >= width) return;
    _spans.add(TextSpan(text: ' ' * (width - _used), style: style));
    _used = width;
  }

  TextSpan build() => TextSpan(children: _spans);
}
