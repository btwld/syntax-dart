import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax_noir/syntax_noir.dart';
import 'package:test/test.dart';

void main() {
  test('ARGB maps to noir channels', () {
    final c = noirColor(0x80FF0000);
    expect((c.r, c.g, c.b), (1.0, 0.0, 0.0));
    expect(c.a, closeTo(0.5, 0.01));
  });

  test('translucent colors are painted over a background', () {
    final c = noirColor(0x80FFFFFF, over: 0xFF000000);
    expect(c.a, 1);
    expect(c.r, closeTo(0.5, 0.01));
  });

  test('token styles keep their flags and only their own background', () {
    const background = 0xFF0D1117;
    final plain = noirTextStyle(
      const syntax.TokenStyle(foreground: 0xFFFFFFFF),
      background: background,
    );
    expect(plain.backgroundColor, isNull);
    expect(plain.fontWeight, isNull);

    final styled = noirTextStyle(
      const syntax.TokenStyle(
        foreground: 0xFFFF0000,
        background: 0xFF00FF00,
        fontStyle:
            syntax.TokenFontStyle.bold |
            syntax.TokenFontStyle.italic |
            syntax.TokenFontStyle.underline,
      ),
      background: background,
    );
    expect(styled.color, noirColor(0xFFFF0000));
    expect(styled.backgroundColor, noirColor(0xFF00FF00));
    expect(styled.fontWeight, FontWeight.bold);
    expect(styled.fontStyle, FontStyle.italic);
    expect(styled.decoration, TextDecoration.underline);
  });
}
