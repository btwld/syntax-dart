import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;

import 'colors.dart';

/// Paints the rows from syntax's `layoutDiff` as noir text, one terminal
/// line per row.
///
/// Every line is cut or padded to exactly the given width, so line
/// backgrounds fill the row. In split mode each side gets half. Colors are
/// opaque, painted over the theme's background, and control characters
/// are shown as `�` so diff text can't send escape sequences to the
/// terminal.
final class PatchPainter {
  /// A painter for [files], highlighted by [highlights], which a view can
  /// keep across painters so files are only highlighted once.
  PatchPainter({
    required this.files,
    required this.highlights,
    this.labels = const syntax.DiffLabels(),
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
  }) {
    final out = _LineBuilder(width);
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
      case syntax.DiffHunkHeaderRow(:final hunk):
        final header = hunk.header;
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
            backgroundColor: noirColor(theme.background),
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
    final digits = _digits[file] ??=
        '${math.max(files[file].maxLineNumber, 1)}'.length;
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

  int _lineBackground(syntax.DiffLineKind kind) => switch (kind) {
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

/// Collects spans up to a fixed number of terminal cells.
final class _LineBuilder {
  _LineBuilder(this.width);

  final int width;
  final List<InlineSpan> _spans = [];
  int _used = 0;

  /// Set once text was cut, so nothing later shows past the cut.
  bool _full = false;

  /// Adds [text], cut at the width.
  void add(String text, TextStyle style) {
    if (text.isEmpty || _full) return;
    final safe = text.replaceAll(_control, '�');
    final fits = sliceByCells(safe, width - _used);
    // A wide character that doesn't fit in the last cell ends the line too.
    if (fits.length < safe.length) _full = true;
    if (fits.isEmpty) return;
    _spans.add(TextSpan(text: fits, style: style));
    _used += terminalStringWidth(fits);
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
