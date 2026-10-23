import 'diff/diff_highlight.dart';
import 'diff/diff_layout.dart';
import 'diff/file_diff.dart';
import 'diff/word_diff.dart';
import 'grammar/scope_stack.dart';
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
    final tokens = caches.values.first.highlighted(file).tokensFor(line);
    // Use raw scope boundaries consistently across themes rather than assuming
    // different themes merge the same adjacent tokens.
    final segments = caches.values.first.segmentsFor(file, line);
    var offset = 0;
    final code = StringBuffer();
    for (final segment in segments) {
      final at = offset;
      final scopes =
          tokens
              .where((t) => t.offset <= at && t.offset + t.text.length > at)
              .firstOrNull
              ?.scopes ??
          ScopeStack.root('text.plain');
      code.write(
        output.token(segment.text, {
          for (final entry in themes.entries)
            entry.key: entry.value.styleFor(scopes),
        }, segment.changed ? const HtmlDecoration(className: 'changed') : null),
      );
      offset += segment.text.length;
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
  final List<String> _rules = [];
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
        _rules.add(
          '.syntax-code[data-theme="${entry.key}"] .$name{${_css(entry.value)}}',
        );
      }
      return name;
    });
    return '${_escape(decoration?.before ?? '')}<span class="$name ${_escape(decoration?.className ?? '')}"${decoration?.title == null ? '' : ' title="${_escape(decoration!.title!)}"'}>${_escape(text)}</span>${_escape(decoration?.after ?? '')}';
  }

  String finish(String body) {
    final css = StringBuffer(
      '.syntax-code{background:var(--syntax-background);color:var(--syntax-foreground);overflow:auto}.syntax-code pre{margin:0}.syntax-code code{font-family:monospace;white-space:${wrap ? 'pre-wrap' : 'pre'}}.syntax-code .gutter{display:inline-block;min-width:4ch;padding-right:1ch;color:var(--syntax-muted);user-select:none}.syntax-code .diff{width:100%;border-collapse:collapse;table-layout:fixed}.syntax-code td{vertical-align:top}.syntax-code th{text-align:left}.syntax-code .added{background:var(--syntax-added)}.syntax-code .removed{background:var(--syntax-removed)}.syntax-code .added .changed{background:var(--syntax-added-word)}.syntax-code .removed .changed{background:var(--syntax-removed-word)}.syntax-code .separator{user-select:none;color:var(--syntax-muted)}',
    );
    for (final entry in themes.entries) {
      final colors = DiffColors.of(entry.value);
      css.write(
        '.syntax-code[data-theme="${entry.key}"]{--syntax-background:${colorToHex(entry.value.background)};--syntax-foreground:${colorToHex(entry.value.foreground)};--syntax-muted:${colorToHex(colors.muted)};--syntax-added:${colorToHex(colors.insertedLine)};--syntax-removed:${colorToHex(colors.removedLine)};--syntax-added-word:${colorToHex(colors.insertedText)};--syntax-removed-word:${colorToHex(colors.removedText)}}',
      );
    }
    css.writeAll(_rules);
    return '<style>$css</style><section class="syntax-code" data-theme="${themes.keys.first}">$body</section>';
  }
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
String _css(TokenStyle style) =>
    'color:${colorToHex(style.foreground)};${style.background == null ? '' : 'background:${colorToHex(style.background!)};'}font-weight:${style.bold ? 'bold' : 'normal'};font-style:${style.italic ? 'italic' : 'normal'};text-decoration:${[if (style.underline) 'underline', if (style.strikethrough) 'line-through', if (!style.underline && !style.strikethrough) 'none'].join(' ')}';
