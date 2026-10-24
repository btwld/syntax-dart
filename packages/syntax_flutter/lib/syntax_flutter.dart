/// Flutter widgets for [syntax](https://pub.dev/packages/syntax_darts): syntax
/// highlighting with TextMate grammars and VS Code themes.
///
/// - [HighlightedCode] shows read-only, highlighted code.
/// - [PatchView] shows a diff or patch, unified or split.
/// - [HighlighterScope] shares one [Highlighter] across the widget tree.
///
/// This library re-exports `package:syntax_darts/syntax.dart`. Import grammars and
/// themes from `package:syntax_darts/langs/...` and `package:syntax_darts/themes/...`.
library;

export 'package:syntax_darts/syntax.dart';

export 'src/chrome.dart';
export 'src/highlighted_code.dart';
export 'src/highlighter_scope.dart';
export 'src/horizontal_scroll.dart';
export 'src/indexed_viewport.dart';
export 'src/patch_view.dart';
export 'src/styles.dart';
