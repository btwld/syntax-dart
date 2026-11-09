import 'package:flutter/widgets.dart';

/// Font-independent glyphs used by patch controls.
enum SyntaxGlyphKind {
  /// A collapsed file.
  collapsed,

  /// An expanded file.
  expanded,

  /// Hidden unchanged context.
  gap,

  /// Missing final line break.
  noNewline,
}

/// Paints a small control glyph without an icon font.
class SyntaxGlyph extends StatelessWidget {
  /// Paints [kind] at [size] in [color].
  const SyntaxGlyph({
    super.key,
    required this.kind,
    required this.size,
    required this.color,
  });

  /// Glyph to paint.
  final SyntaxGlyphKind kind;

  /// Square extent in logical pixels.
  final double size;

  /// Stroke color.
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(kind, color),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind, this.color);

  final SyntaxGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width, size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = .1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (kind) {
      case SyntaxGlyphKind.collapsed:
        path.moveTo(.4, .25);
        path.lineTo(.65, .5);
        path.lineTo(.4, .75);
      case SyntaxGlyphKind.expanded:
        path.moveTo(.25, .4);
        path.lineTo(.5, .65);
        path.lineTo(.75, .4);
      case SyntaxGlyphKind.gap:
        path.moveTo(.25, .3);
        path.lineTo(.5, .1);
        path.lineTo(.75, .3);
        path.moveTo(.25, .7);
        path.lineTo(.5, .9);
        path.lineTo(.75, .7);
      case SyntaxGlyphKind.noNewline:
        canvas.drawCircle(const Offset(.5, .5), .4, paint);
        path.moveTo(.3, .5);
        path.lineTo(.7, .5);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}
