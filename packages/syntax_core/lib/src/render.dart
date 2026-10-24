import 'highlighter.dart';
import 'theme/theme.dart';

/// Renders highlighted lines as a `<pre>` block with inline styles, in the
/// same shape as Shiki's `codeToHtml`.
String renderHtml(List<List<ThemedToken>> lines, SyntaxTheme theme) {
  final out = StringBuffer()
    ..write('<pre class="syntax ${_escape(theme.name)}" style="')
    ..write('background-color:${colorToHex(theme.background)};')
    ..write('color:${colorToHex(theme.foreground)}"><code>');
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) out.write('\n');
    out.write('<span class="line">');
    for (final token in lines[i]) {
      out
        ..write('<span style="')
        ..write(_css(token.style))
        ..write('">')
        ..write(_escape(token.text))
        ..write('</span>');
    }
    out.write('</span>');
  }
  out.write('</code></pre>');
  return out.toString();
}

String _css(TokenStyle style) {
  final css = StringBuffer('color:${colorToHex(style.foreground)}');
  if (style.background != null) {
    css.write(';background-color:${colorToHex(style.background!)}');
  }
  if (style.italic) css.write(';font-style:italic');
  if (style.bold) css.write(';font-weight:bold');
  final decorations = [
    if (style.underline) 'underline',
    if (style.strikethrough) 'line-through',
  ];
  if (decorations.isNotEmpty) {
    css.write(';text-decoration:${decorations.join(' ')}');
  }
  return css.toString();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Renders highlighted lines with 24-bit ANSI escape codes, for terminals.
/// Set [background] to paint the theme's background across each full row.
///
/// Control characters in the code, other than tab, are replaced with
/// U+FFFD, so the code cannot emit its own escape sequences.
String renderAnsi(
  List<List<ThemedToken>> lines,
  SyntaxTheme theme, {
  bool background = false,
}) {
  final out = StringBuffer();
  final bg = background ? _sgrColor(48, theme.background) : '';
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) out.write('\n');
    // Erase to the end of the row in the background color.
    if (background) out.write('\x1B[0m$bg\x1B[K');
    for (final token in lines[i]) {
      final style = token.style;
      out
        ..write('\x1B[0m')
        ..write(bg)
        ..write(_sgrColor(38, style.foreground));
      if (style.background != null) out.write(_sgrColor(48, style.background!));
      if (style.bold) out.write('\x1B[1m');
      if (style.italic) out.write('\x1B[3m');
      if (style.underline) out.write('\x1B[4m');
      if (style.strikethrough) out.write('\x1B[9m');
      out.write(token.text.replaceAll(_controlChars, '\uFFFD'));
    }
    out.write('\x1B[0m');
  }
  return out.toString();
}

/// C0 and C1 controls except tab. ESC and CSI start terminal sequences.
final RegExp _controlChars = RegExp(r'[\x00-\x08\x0B-\x1F\x7F-\x9F]');

String _sgrColor(int code, int argb) =>
    '\x1B[$code;2;${(argb >> 16) & 0xFF};${(argb >> 8) & 0xFF};${argb & 0xFF}m';

/// One-call rendering helpers.
extension HighlighterRendering on Highlighter {
  /// Highlights [code] and renders it as HTML. See [renderHtml].
  String toHtml(
    String code, {
    required String language,
    required SyntaxTheme theme,
  }) => renderHtml(highlight(code, language: language, theme: theme), theme);

  /// Highlights [code] and renders it for a terminal. See [renderAnsi].
  String toAnsi(
    String code, {
    required String language,
    required SyntaxTheme theme,
    bool background = false,
  }) => renderAnsi(
    highlight(code, language: language, theme: theme),
    theme,
    background: background,
  );
}
