import 'package:flutter/material.dart';
import 'package:syntax_darts/syntax.dart';

import 'styles.dart';

/// Keeps native controls legible when the code palette differs from the app.
class SyntaxChrome extends StatelessWidget {
  /// Applies the code palette to inherited controls and text.
  const SyntaxChrome({super.key, required this.theme, required this.child});

  /// Palette used by the surrounding code surface.
  final SyntaxTheme theme;

  /// Native controls and code content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final parent = Theme.of(context);
    final foreground = theme.foregroundColor;
    final background = theme.backgroundColor;
    final brightness = ThemeData.estimateBrightnessForColor(background);
    final scheme =
        (parent.brightness == brightness
                ? parent.colorScheme
                : ColorScheme.fromSeed(
                    seedColor: theme.cursorColor,
                    brightness: brightness,
                  ))
            .copyWith(surface: background, onSurface: foreground);
    return Theme(
      data: parent.copyWith(
        colorScheme: scheme,
        textTheme: parent.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        iconTheme: parent.iconTheme.copyWith(color: foreground),
        textButtonTheme: TextButtonThemeData(
          style: (parent.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => foreground.withValues(
                alpha: states.contains(WidgetState.disabled) ? .38 : 1,
              ),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: (parent.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => foreground.withValues(
                alpha: states.contains(WidgetState.disabled) ? .38 : 1,
              ),
            ),
          ),
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: theme.cursorColor,
          selectionColor: theme.selectionColor,
          selectionHandleColor: theme.cursorColor,
        ),
      ),
      child: Material(
        color: background,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: child,
          ),
        ),
      ),
    );
  }
}
