import 'package:flutter/widgets.dart';

import 'selection_chrome.dart';

/// Internal inheritance for controls built by patch rows.
class SyntaxChromeScope extends InheritedWidget {
  /// Provides [chrome] to descendant row controls.
  const SyntaxChromeScope({
    super.key,
    required this.chrome,
    required super.child,
  });

  /// Selection and action rendering.
  final SyntaxSelectionChrome chrome;

  /// Finds the nearest controls, or the plain defaults.
  static SyntaxSelectionChrome of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyntaxChromeScope>()?.chrome ??
      SyntaxSelectionChrome.plain;

  @override
  bool updateShouldNotify(SyntaxChromeScope oldWidget) =>
      chrome != oldWidget.chrome;
}
