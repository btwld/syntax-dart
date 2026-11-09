import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

import 'chrome_scope.dart';
import 'selection_chrome.dart';
import 'styles.dart';

/// Keeps controls legible when the code palette differs from the app.
///
/// Uses only widgets-layer inherited styles and paints the code background.
class SyntaxChrome extends StatelessWidget {
  /// Applies the code palette to inherited controls and text.
  const SyntaxChrome({
    super.key,
    required this.theme,
    required this.child,
    this.selectionChrome,
  });

  /// Palette used by the surrounding code surface.
  final SyntaxTheme theme;

  /// Native controls and code content.
  final Widget child;

  /// Optional selection and action rendering; defaults to plain widgets.
  final SyntaxSelectionChrome? selectionChrome;

  @override
  Widget build(BuildContext context) => SyntaxChromeScope(
    chrome: selectionChrome ?? SyntaxSelectionChrome.plain,
    child: ColoredBox(
      color: theme.backgroundColor,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: theme.foregroundColor),
        child: IconTheme.merge(
          data: IconThemeData(color: theme.foregroundColor),
          child: DefaultSelectionStyle(
            cursorColor: theme.cursorColor,
            selectionColor: theme.selectionColor,
            child: child,
          ),
        ),
      ),
    ),
  );
}
