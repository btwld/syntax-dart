import 'package:flutter/widgets.dart';
import 'package:syntax/syntax.dart';

/// Provides a [Highlighter] to [HighlightedCode] widgets below it, so the
/// compiled grammars are shared.
///
/// ```dart
/// HighlighterScope(
///   highlighter: Highlighter(languages: [dartLanguage, yamlLanguage]),
///   child: MyApp(),
/// )
/// ```
class HighlighterScope extends InheritedWidget {
  /// Provides [highlighter] to [child] and its descendants.
  const HighlighterScope({
    super.key,
    required this.highlighter,
    required super.child,
  });

  /// The highlighter descendants use.
  final Highlighter highlighter;

  /// The nearest [Highlighter], or `null` if there is no scope.
  static Highlighter? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HighlighterScope>()
      ?.highlighter;

  /// The nearest [Highlighter]. Throws if there is no [HighlighterScope].
  static Highlighter of(BuildContext context) {
    final highlighter = maybeOf(context);
    if (highlighter == null) {
      throw FlutterError(
        'No HighlighterScope found.\n'
        'Wrap your app in a HighlighterScope, or pass a highlighter '
        'directly to the widget.',
      );
    }
    return highlighter;
  }

  @override
  bool updateShouldNotify(HighlighterScope oldWidget) =>
      highlighter != oldWidget.highlighter;
}
