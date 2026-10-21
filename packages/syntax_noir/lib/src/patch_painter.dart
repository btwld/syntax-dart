import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;

import 'colors.dart';

/// Paints the rows from syntax's `layoutDiff` as noir text, one terminal
/// line per row.
///
/// Every line is cut or padded to exactly the given width, so line
/// backgrounds fill the row. In split mode each side gets half. A file is
/// highlighted, and its changed words found, the first time one of its
/// rows is painted. Colors are opaque, painted over the theme's background.
final class PatchPainter {
  /// A painter for [files], highlighted with [highlighter] in [theme].
  PatchPainter({
    required this.files,
    required this.highlighter,
    required this.theme,
    this.language,
    this.labels = const syntax.DiffLabels(),
  }) : _colors = syntax.DiffColors.of(theme);

  /// The files the rows refer to by index.
  final List<syntax.FileDiff> files;

  /// Provides the grammars.
  final syntax.Highlighter highlighter;

  /// Provides the colors.
  final syntax.SyntaxTheme theme;

  /// The language of every file. Defaults to guessing from each path.
  final String? language;

  /// The words shown in headers, notices and collapsed lines.
  final syntax.DiffLabels labels;

  final syntax.DiffColors _colors;
  final Map<int, (syntax.Grammar?, syntax.HighlightedDiff)> _highlights = {};
  final Map<int, syntax.WordChanges> _words = {};

  int get _background => theme.background;

  /// [row] as one line of [width] cells. A [selected] row gets a marker in
  /// its first cell.
  TextSpan paint(
    syntax.DiffRow row, {
    required int width,
    bool selected = false,
  }) {
    final out = _LineBuilder(width);
    final base = switch (row) {
      syntax.DiffFileHeaderRow() => _colors.fileHeader,
      syntax.DiffLineRow(:final line) => _lineBackground(line.kind),
      syntax.DiffPairRow() => _background,
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
      case syntax.DiffHunkHeaderRow(:final hunk):
        final header = hunk.header;
        final sectionStart = header.length - hunk.section.length;
        out
          ..add(header.substring(0, sectionStart), _muted(base))
          ..add(header.substring(sectionStart), _plain(base));
      case syntax.DiffGapRow(:final count):
        out.add('⋯ ${labels.showUnchangedLines(count)}', _muted(base));
      case syntax.DiffLineRow(:final file, :final line):
        _gutter(out, file, line, [line.oldNumber, line.newNumber]);
        _code(out, file, line);
      case syntax.DiffPairRow(:final file, :final left, :final right):
        final half = (width - 2) ~/ 2;
        _side(out, file, left, old: true, width: half);
        out.add(
          '│',
          TextStyle(
            color: noirColor(_colors.divider),
            backgroundColor: noirColor(_background),
          ),
        );
        _side(out, file, right, old: false, width: width - 2 - half);
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
    final moved =
        file.kind == syntax.FileDiffKind.renamed ||
        file.kind == syntax.FileDiffKind.copied;
    if (moved) out.add('${file.oldPath} → ', _muted(base));
    out.add(file.path, _bold(theme.foreground, base));
    if (file.isBinary) return;
    out
      ..add('  +${file.additions}', _bold(_colors.inserted, base))
      ..add(' −${file.deletions} ', _bold(_colors.removed, base));
    final (:added, :removed) = file.changeBlocks();
    for (var i = 0; i < 5; i++) {
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
  }) {
    final side = _LineBuilder(width);
    if (line == null) {
      side.fill(TextStyle(backgroundColor: noirColor(_colors.emptySide)));
    } else {
      _gutter(side, file, line, [old ? line.oldNumber : line.newNumber]);
      _code(side, file, line);
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
    final digits = '${math.max(files[file].maxLineNumber, 1)}'.length;
    final numberStyle = TextStyle(
      color: noirColor(theme.lineNumberForeground, over: base),
      backgroundColor: noirColor(base),
    );
    for (final n in numbers) {
      out.add('${(n?.toString() ?? '').padLeft(digits)} ', numberStyle);
    }
    final (marker, color) = switch (line.kind) {
      syntax.DiffLineKind.added => ('+', _colors.inserted),
      syntax.DiffLineKind.removed => ('−', _colors.removed),
      syntax.DiffLineKind.context => (' ', _colors.muted),
    };
    out.add('$marker ', _bold(color, base));
  }

  void _code(_LineBuilder out, int file, syntax.DiffLine line) {
    final highlighted = _highlightFor(file);
    final words = _words[file] ??= syntax.WordChanges.of(files[file]);
    final base = _lineBackground(line.kind);
    final word = switch (line.kind) {
      syntax.DiffLineKind.added => _colors.insertedText,
      syntax.DiffLineKind.removed => _colors.removedText,
      syntax.DiffLineKind.context => null,
    };
    for (final segment in highlighted.segmentsFor(line, words)) {
      final changed = segment.changed && word != null;
      // A changed word's emphasis replaces the token's own background.
      final style = changed
          ? syntax.TokenStyle(
              foreground: segment.style.foreground,
              fontStyle: segment.style.fontStyle,
            )
          : segment.style;
      final background = changed ? syntax.alphaBlend(word, base) : base;
      out.add(
        // Tabs have no fixed width in a terminal.
        segment.text.replaceAll('\t', '    '),
        noirTextStyle(style, background: background).copyWith(
          backgroundColor: noirColor(
            style.background ?? background,
            over: background,
          ),
        ),
      );
    }
    if (line.noNewlineAtEnd) out.add(' ⊘', _muted(base));
  }

  /// The file's highlighting, redone when its grammar changes, such as
  /// after `Highlighter.addLanguage`.
  syntax.HighlightedDiff _highlightFor(int file) {
    final grammar = syntax.HighlightedDiff.grammarFor(
      files[file],
      highlighter: highlighter,
      language: language,
    );
    if (_highlights[file] case (
      final cached,
      final highlighted,
    ) when identical(cached, grammar)) {
      return highlighted;
    }
    final highlighted = syntax.HighlightedDiff.of(
      files[file],
      highlighter: highlighter,
      theme: theme,
      language: language,
    );
    _highlights[file] = (grammar, highlighted);
    return highlighted;
  }

  int _lineBackground(syntax.DiffLineKind kind) => switch (kind) {
    syntax.DiffLineKind.added => syntax.alphaBlend(
      _colors.insertedLine,
      _background,
    ),
    syntax.DiffLineKind.removed => syntax.alphaBlend(
      _colors.removedLine,
      _background,
    ),
    syntax.DiffLineKind.context => _background,
  };

  TextStyle _muted(int background) => TextStyle(
    color: noirColor(_colors.muted),
    backgroundColor: noirColor(background),
  );

  TextStyle _plain(int background) => TextStyle(
    color: noirColor(theme.foreground, over: background),
    backgroundColor: noirColor(background),
  );

  TextStyle _bold(int color, int background) => TextStyle(
    color: noirColor(color, over: background),
    backgroundColor: noirColor(background),
    fontWeight: FontWeight.bold,
  );
}

/// Collects spans up to a fixed number of terminal cells.
final class _LineBuilder {
  _LineBuilder(this.width);

  final int width;
  final List<InlineSpan> _spans = [];
  int _used = 0;

  /// Adds [text], cut at the width.
  void add(String text, TextStyle style) {
    if (text.isEmpty || _used >= width) return;
    final fits = sliceByCells(text, width - _used);
    if (fits.isEmpty) return;
    _spans.add(TextSpan(text: fits, style: style));
    _used += terminalStringWidth(fits);
  }

  /// Adds the spans of [other], which must fit.
  void addAll(_LineBuilder other) {
    _spans.addAll(other._spans);
    _used += other._used;
  }

  /// Pads with spaces to the width.
  void fill(TextStyle style) {
    if (_used < width) add(' ' * (width - _used), style);
  }

  TextSpan build() => TextSpan(children: List.unmodifiable(_spans));
}
