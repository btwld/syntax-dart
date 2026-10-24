import 'package:noir/noir.dart';
import 'package:syntax_core/syntax.dart' as syntax;

/// An ARGB color from syntax as a noir [Color]. Terminals don't blend, so
/// a translucent color is first painted over [over] when given.
Color noirColor(int argb, {int? over}) {
  final c = over == null ? argb : syntax.alphaBlend(argb, over);
  return Color(
    ((c >> 16) & 0xFF) / 255,
    ((c >> 8) & 0xFF) / 255,
    (c & 0xFF) / 255,
    ((c >> 24) & 0xFF) / 255,
  );
}

/// A syntax token style as a noir [TextStyle]. Translucent colors are
/// painted over [background], the color behind the text. The style sets a
/// background only when the token has its own.
TextStyle noirTextStyle(syntax.TokenStyle style, {required int background}) {
  final decorations = [
    if (style.underline) TextDecoration.underline,
    if (style.strikethrough) TextDecoration.lineThrough,
  ];
  final tokenBackground = style.background;
  // The text is painted over the token's own background when it has one.
  final behind = tokenBackground == null
      ? background
      : syntax.alphaBlend(tokenBackground, background);
  return TextStyle(
    color: noirColor(style.foreground, over: behind),
    backgroundColor: tokenBackground == null ? null : noirColor(behind),
    fontWeight: style.bold ? FontWeight.bold : null,
    fontStyle: style.italic ? FontStyle.italic : null,
    decoration: decorations.isEmpty
        ? null
        : TextDecoration.combine(decorations),
  );
}
