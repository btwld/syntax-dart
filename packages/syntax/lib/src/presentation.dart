import 'edit/text_document.dart';
import 'diff/file_diff.dart';
import 'diff/diff_highlight.dart';
import 'diff/diff_layout.dart';
import 'diff/word_diff.dart';
import 'grammar/scope_stack.dart';
import 'grammar/grammar.dart';
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

/// Renders a file with reusable classes, multiple palettes and CSS variables.
///
/// Set the root element's `data-theme` attribute to a key in [themes] to switch
/// palettes without retokenizing. [decorate] receives zero-based source lines.
String renderFileHtml(
  SourceFile file, {
  required Highlighter highlighter,
  required Map<String, SyntaxTheme> themes,
  bool lineNumbers = true,
  bool wrap = false,
  HtmlDecoration? Function(int line, ThemedToken token)? decorate,
}) {
  final output = _HtmlOutput(themes, wrap: wrap);
  final language =
      file.language ?? highlighter.languageForPath(file.path)?.name;
  final grammar = language == null || highlighter.language(language) == null
      ? null
      : highlighter.grammar(language);
  final document = TextDocument(file.text);
  StateStack? state;
  final body = StringBuffer('<pre><code>');
  for (var line = 0; line < document.lineCount; line++) {
    final text = document.lineText(line);
    final result = grammar?.tokenizeLine(text, state);
    state = result?.endState;
    final tokens = result == null
        ? [
            ThemedToken(
              text,
              0,
              TokenStyle(foreground: themes.values.first.foreground),
              ScopeStack.root('text.plain'),
            ),
          ]
        : [
            for (final token in result.tokens)
              ThemedToken(
                text.substring(token.start, token.end),
                token.start,
                themes.values.first.styleFor(token.scopes),
                token.scopes,
              ),
          ];
    body.write('<span class="line" data-line="${line + 1}">');
    if (lineNumbers) {
      body.write('<span class="gutter" aria-hidden="true">${line + 1}</span>');
    }
    for (final token in tokens) {
      final decoration = decorate?.call(line, token);
      body.write(
        output.token(token.text, {
          for (final entry in themes.entries)
            entry.key: entry.value.styleFor(token.scopes),
        }, decoration),
      );
    }
    body.write('</span>');
    body.write(
      _escape(
        document.lineText(line, includeTerminator: true).substring(text.length),
      ),
    );
  }
  body.write('</code></pre>');
  document.dispose();
  return output.finish(
    body.toString(),
    title: file.path,
    id: file.id,
    revision: file.revision,
  );
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
        output.token(
          segment.text,
          {
            for (final entry in themes.entries)
              entry.key: entry.value.styleFor(scopes),
          },
          segment.changed ? const HtmlDecoration(className: 'changed') : null,
        ),
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

  String finish(String body, {String? title, String? id, int? revision}) {
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
    return '<style>$css</style><section class="syntax-code" data-theme="${themes.keys.first}"${id == null ? '' : ' data-file="${_escape(id)}"'}${revision == null ? '' : ' data-revision="$revision"'}>${title == null ? '' : '<header>${_escape(title)}</header>'}$body</section>';
  }
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
String _css(TokenStyle style) =>
    'color:${colorToHex(style.foreground)};${style.background == null ? '' : 'background:${colorToHex(style.background!)};'}font-weight:${style.bold ? 'bold' : 'normal'};font-style:${style.italic ? 'italic' : 'normal'};text-decoration:${[if (style.underline) 'underline', if (style.strikethrough) 'line-through', if (!style.underline && !style.strikethrough) 'none'].join(' ')}';

/// Parses ANSI SGR colors without retaining executable terminal controls.
/// OSC hyperlinks, cursor movement and other control sequences are discarded.
List<List<ThemedToken>> parseAnsi(String source, {required SyntaxTheme theme}) {
  final lines = <List<ThemedToken>>[[]];
  final scopes = ScopeStack.root('text.ansi');
  var foreground = theme.foreground;
  int? background;
  var bold = false,
      italic = false,
      underline = false,
      strike = false,
      inverse = false;
  var offset = 0;
  void emit(String text) {
    if (text.isEmpty) return;
    final style = TokenStyle(
      foreground: inverse ? background ?? theme.background : foreground,
      background: inverse ? foreground : background,
      fontStyle:
          (italic ? 1 : 0) |
          (bold ? 2 : 0) |
          (underline ? 4 : 0) |
          (strike ? 8 : 0),
    );
    lines.last.add(ThemedToken(text, offset, style, scopes));
    offset += text.length;
  }

  int indexed(int index) {
    const ansi = [
      0xff000000,
      0xffcd3131,
      0xff0dbc79,
      0xffe5e510,
      0xff2472c8,
      0xffbc3fbc,
      0xff11a8cd,
      0xffe5e5e5,
      0xff666666,
      0xfff14c4c,
      0xff23d18b,
      0xfff5f543,
      0xff3b8eea,
      0xffd670d6,
      0xff29b8db,
      0xffffffff,
    ];
    if (index < 16) return ansi[index.clamp(0, 15)];
    if (index >= 232) {
      final value = 8 + (index.clamp(232, 255) - 232) * 10;
      return 0xff000000 | value << 16 | value << 8 | value;
    }
    final n = index - 16;
    int level(int value) => value == 0 ? 0 : 55 + value * 40;
    return 0xff000000 |
        level(n ~/ 36) << 16 |
        level(n ~/ 6 % 6) << 8 |
        level(n % 6);
  }

  var i = 0, start = 0;
  while (i < source.length) {
    final unit = source.codeUnitAt(i);
    if (unit != 27 &&
        unit != 10 &&
        unit != 13 &&
        (unit >= 32 || unit == 9) &&
        (unit < 127 || unit > 159)) {
      i++;
      continue;
    }
    emit(source.substring(start, i));
    if (unit == 10 || unit == 13) {
      if (unit == 13 &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == 10) {
        i++;
      }
      lines.add([]);
      offset = 0;
      i++;
    } else if (unit == 27 && i + 1 < source.length && source[i + 1] == '[') {
      final match = RegExp(
        r'\x1b\[([0-9;:]*)([ -/]*)([@-~])',
      ).matchAsPrefix(source, i);
      if (match == null) {
        i += 2;
      } else {
        i = match.end;
        if (match[3] == 'm') {
          final codes = match[1]!
              .split(RegExp('[;:]'))
              .map((v) => int.tryParse(v) ?? 0)
              .toList();
          for (var c = 0; c < codes.length; c++) {
            final code = codes[c];
            if (code == 0) {
              foreground = theme.foreground;
              background = null;
              bold = italic = underline = strike = inverse = false;
            } else if (code == 1) {
              bold = true;
            } else if (code == 22) {
              bold = false;
            } else if (code == 3) {
              italic = true;
            } else if (code == 23) {
              italic = false;
            } else if (code == 4) {
              underline = true;
            } else if (code == 24) {
              underline = false;
            } else if (code == 9) {
              strike = true;
            } else if (code == 29) {
              strike = false;
            } else if (code == 7) {
              inverse = true;
            } else if (code == 27) {
              inverse = false;
            } else if (code == 39) {
              foreground = theme.foreground;
            } else if (code == 49) {
              background = null;
            } else if (code >= 30 && code <= 37) {
              foreground = indexed(code - 30);
            } else if (code >= 90 && code <= 97) {
              foreground = indexed(code - 90 + 8);
            } else if (code >= 40 && code <= 47) {
              background = indexed(code - 40);
            } else if (code >= 100 && code <= 107) {
              background = indexed(code - 100 + 8);
            } else if ((code == 38 || code == 48) && c + 2 < codes.length) {
              int? color;
              if (codes[c + 1] == 5) {
                color = indexed(codes[c + 2]);
                c += 2;
              } else if (codes[c + 1] == 2 && c + 4 < codes.length) {
                color =
                    0xff000000 |
                    codes[c + 2].clamp(0, 255) << 16 |
                    codes[c + 3].clamp(0, 255) << 8 |
                    codes[c + 4].clamp(0, 255);
                c += 4;
              }
              if (color != null) {
                if (code == 38) {
                  foreground = color;
                } else {
                  background = color;
                }
              }
            }
          }
        }
      }
    } else if (unit == 27 &&
        i + 1 < source.length &&
        [']', 'P', '^', '_'].contains(source[i + 1])) {
      i += 2;
      while (i < source.length &&
          source.codeUnitAt(i) != 7 &&
          !(source.codeUnitAt(i) == 27 &&
              i + 1 < source.length &&
              source[i + 1] == '\\')) {
        i++;
      }
      i = (i + (i < source.length && source.codeUnitAt(i) == 27 ? 2 : 1)).clamp(
        0,
        source.length,
      );
    } else {
      i++;
    }
    start = i;
  }
  emit(source.substring(start));
  return lines;
}
