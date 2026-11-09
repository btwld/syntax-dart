import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// Builds the plain mobile loupe used by syntax selection controls.
Widget? buildSyntaxMagnifier(
  BuildContext context,
  MagnifierController controller,
  ValueNotifier<MagnifierInfo> magnifierInfo,
) {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return null;
  }
  return ValueListenableBuilder<MagnifierInfo>(
    valueListenable: magnifierInfo,
    builder: (context, info, _) {
      final overlay =
          Overlay.of(context, rootOverlay: true).context.findRenderObject()!
              as RenderBox;
      final size = Size(
        math.min(110, overlay.size.width),
        math.min(50, overlay.size.height),
      );
      // MagnifierInfo uses global coordinates; Positioned uses overlay-local
      // coordinates, including when the root overlay is offset in the view.
      final focalPoint = overlay.globalToLocal(info.caretRect.center);
      final lens = MagnifierController.shiftWithinBounds(
        rect:
            Offset(
              focalPoint.dx - size.width / 2,
              focalPoint.dy - size.height - 18,
            ) &
            size,
        bounds: Offset.zero & overlay.size,
      );
      return Positioned(
        left: lens.left,
        top: lens.top,
        child: IgnorePointer(
          child: RawMagnifier(
            size: size,
            magnificationScale: 1.5,
            focalPointOffset: focalPoint - lens.center,
            clipBehavior: Clip.hardEdge,
            decoration: MagnifierDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color:
                      DefaultSelectionStyle.of(context).cursorColor ??
                      const Color(0xff808080),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
