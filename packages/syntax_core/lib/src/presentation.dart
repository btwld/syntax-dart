import 'diff/diff_highlight.dart';
import 'diff/diff_layout.dart';
import 'diff/file_diff.dart';
import 'diff/word_diff.dart';
import 'highlighter.dart';
import 'theme/theme.dart';

/// Safe token decoration for static HTML output. Text and attributes are escaped.
final class HtmlDecoration {
  /// Adds a CSS class, tooltip, and plain text around one token.
  const HtmlDecoration({
    this.className = '',
    this.title,
    this.before = '',
    this.after = '',
  });

  /// Additional CSS class names.
  final String className;

  /// Optional browser tooltip.
  final String? title;

  /// Escaped text before the source token.
  final String before;

  /// Escaped text after the source token.
  final String after;
}

/// Renders a static file patch with unified or aligned split rows.
String renderDiffHtml(
  Iterable<FileDiff> files, {
  required Highlighter highlighter,
  required Map<String, SyntaxTheme> themes,
  DiffMode mode = DiffMode.unified,
  InlineDiffMode inlineDiffMode = InlineDiffMode.mergedWords,
  bool expandAll = false,
  bool wrap = false,
  HtmlDecoration? Function(FileDiff file, DiffLine line)? decorateLine,
}) {
  final list = files.toList();
  final output = _HtmlOutput(themes, wrap: wrap);
  final caches = {
    for (final entry in themes.entries)
      entry.key: DiffHighlightCache(
        highlighter: highlighter,
        theme: entry.value,
        inlineDiffMode: inlineDiffMode,
      ),
  };
  String lineHtml(FileDiff file, DiffLine? line, {bool old = false}) {
    if (line == null) return '<td class="empty"></td>';
    // Split tokens wherever any theme's style or inline-diff state changes.
    final segmentsByTheme = {
      for (final entry in caches.entries)
        entry.key: entry.value.segmentsFor(file, line),
    };
    final indices = {for (final key in themes.keys) key: 0};
    final ends = {
      for (final entry in segmentsByTheme.entries)
        entry.key: entry.value.isEmpty ? 0 : entry.value.first.text.length,
    };
    var pos = 0;
    final code = StringBuffer();
    while (pos < line.text.length) {
      var next = line.text.length;
      for (final entry in segmentsByTheme.entries) {
        final key = entry.key;
        final segs = entry.value;
        var index = indices[key]!;
        while (index < segs.length && ends[key]! <= pos) {
          index++;
          if (index < segs.length) {
            ends[key] = ends[key]! + segs[index].text.length;
          }
        }
        indices[key] = index;
        if (index < segs.length && ends[key]! < next) {
          next = ends[key]!;
        }
      }
      final changed =
          segmentsByTheme.values.first[indices[themes.keys.first]!].changed;
      code.write(
        output.token(line.text.substring(pos, next), {
          for (final entry in segmentsByTheme.entries)
            entry.key: entry.value[indices[entry.key]!].style,
        }, changed ? const HtmlDecoration(className: 'changed') : null),
      );
      pos = next;
    }
    final decoration = decorateLine?.call(file, line);
    final number = old ? line.oldNumber : line.newNumber ?? line.oldNumber;
    return '<td class="${line.kind.name} ${_escape(decoration?.className ?? '')}"${decoration?.title == null ? '' : ' title="${_escape(decoration!.title!)}"'}>'
        '<span class="gutter" aria-hidden="true">${number ?? ''} ${line.kind == DiffLineKind.added
            ? '+'
            : line.kind == DiffLineKind.removed
            ? '−'
            : ' '}</span>'
        '${_escape(decoration?.before ?? '')}<code>$code</code>${_escape(decoration?.after ?? '')}</td>';
  }

  final body = StringBuffer('<table class="diff"><tbody>');
  final columns = mode == DiffMode.split ? 2 : 1;
  for (final row in DiffLayout(list, mode: mode, expandAll: expandAll)) {
    final file = list[row.file];
    body.write('<tr data-file="${_escape(file.id)}">');
    switch (row) {
      case DiffFileHeaderRow():
        body.write('<th colspan="$columns">${_escape(file.path)}</th>');
      case DiffHunkHeaderRow(:final hunk):
        body.write(
          '<td class="separator" colspan="$columns">${_escape(hunk.header)}</td>',
        );
      case DiffGapRow(:final count):
        body.write(
          '<td class="separator" colspan="$columns">$count unchanged lines</td>',
        );
      case DiffNoticeRow(:final notice):
        body.write('<td colspan="$columns">${_escape(notice.name)}</td>');
      case DiffLineRow(:final line):
        body.write(lineHtml(file, line));
      case DiffPairRow(:final left, :final right):
        body
          ..write(lineHtml(file, left, old: true))
          ..write(lineHtml(file, right));
    }
    body.write('</tr>');
  }
  body.write('</tbody></table>');
  return output.finish(body.toString());
}

final class _HtmlOutput {
  _HtmlOutput(this.themes, {required this.wrap}) {
    if (themes.isEmpty) throw ArgumentError('At least one theme is required');
    for (final key in themes.keys) {
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(key)) {
        throw ArgumentError('Invalid palette key: $key');
      }
    }
  }
  final Map<String, SyntaxTheme> themes;
  final bool wrap;
  final Map<String, String> _classes = {};
  final List<(String, String, String)> _rules = [];
  String token(
    String text,
    Map<String, TokenStyle> styles,
    HtmlDecoration? decoration,
  ) {
    final key = styles.entries
        .map((e) => '${e.key}:${_css(e.value)}')
        .join('|');
    final name = _classes.putIfAbsent(key, () {
      final name = 's${_classes.length}';
      for (final entry in styles.entries) {
        _rules.add((entry.key, name, _css(entry.value)));
      }
      return name;
    });
    return '${_escape(decoration?.before ?? '')}<span class="$name ${_escape(decoration?.className ?? '')}"${decoration?.title == null ? '' : ' title="${_escape(decoration!.title!)}"'}>${_escape(text)}</span>${_escape(decoration?.after ?? '')}';
  }

  String finish(String body) {
    final scope = _scopeFor(body);
    final selector = '.syntax-code[data-scope="$scope"]';
    final css = StringBuffer(
      '$selector{background:var(--syntax-background);color:var(--syntax-foreground);overflow:auto}$selector pre{margin:0}$selector code{font-family:monospace;white-space:${wrap ? 'pre-wrap' : 'pre'}}$selector .gutter{display:inline-block;min-width:4ch;padding-right:1ch;color:var(--syntax-muted);user-select:none}$selector .diff{width:100%;border-collapse:collapse;table-layout:fixed}$selector td{vertical-align:top}$selector th{text-align:left}$selector .added{background:var(--syntax-added)}$selector .removed{background:var(--syntax-removed)}$selector .added .changed{background:var(--syntax-added-word)}$selector .removed .changed{background:var(--syntax-removed-word)}$selector .separator{user-select:none;color:var(--syntax-muted)}',
    );
    for (final entry in themes.entries) {
      final colors = DiffColors.of(entry.value);
      css.write(
        '$selector[data-theme="${entry.key}"]{--syntax-background:${colorToHex(entry.value.background)};--syntax-foreground:${colorToHex(entry.value.foreground)};--syntax-muted:${colorToHex(colors.muted)};--syntax-added:${colorToHex(colors.insertedLine)};--syntax-removed:${colorToHex(colors.removedLine)};--syntax-added-word:${colorToHex(colors.insertedText)};--syntax-removed-word:${colorToHex(colors.removedText)}}',
      );
    }
    for (final (themeKey, name, rule) in _rules) {
      css.write('$selector[data-theme="$themeKey"] .$name{$rule}');
    }
    return '<style>$css</style><section class="syntax-code" data-scope="$scope" data-theme="${themes.keys.first}">$body</section>';
  }

  String _scopeFor(String body) {
    var hash = 0x811c9dc5;
    void mix(String text) {
      for (var i = 0; i < text.length; i++) {
        hash = ((hash ^ text.codeUnitAt(i)) * 0x01000193) & 0xffffffff;
      }
    }

    mix(wrap ? '1' : '0');
    for (final entry in themes.entries) {
      mix('${entry.key}:${entry.value.background}:${entry.value.foreground};');
    }
    for (final (themeKey, name, rule) in _rules) {
      mix('$themeKey:$name:$rule;');
    }
    mix(body);
    return 'f${hash.toRadixString(16).padLeft(8, '0')}';
  }
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
String _css(TokenStyle style) =>
    'color:${colorToHex(style.foreground)};${style.background == null ? '' : 'background:${colorToHex(style.background!)};'}font-weight:${style.bold ? 'bold' : 'normal'};font-style:${style.italic ? 'italic' : 'normal'};text-decoration:${[if (style.underline) 'underline', if (style.strikethrough) 'line-through', if (!style.underline && !style.strikethrough) 'none'].join(' ')}';
