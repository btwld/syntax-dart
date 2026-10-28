/// Flutter widgets for [syntax](https://pub.dev/packages/syntax_core): syntax
/// highlighting with TextMate grammars and VS Code themes.
///
/// - [HighlightedCode] shows read-only, highlighted code.
/// - [PatchView] shows a diff or patch, unified or split.
/// - [HighlighterScope] shares one [Highlighter] across the widget tree.
///
/// This library re-exports `package:syntax_core/syntax.dart`. Import grammars and
/// themes from `package:syntax_core/langs/...` and `package:syntax_core/themes/...`.
library;

export 'package:syntax_core/syntax.dart';

export 'src/chrome.dart';
export 'src/code_rows.dart' show RowSelectionDelegate;
export 'src/highlighted_code.dart';
export 'src/highlighter_scope.dart';
export 'src/horizontal_scroll.dart';
export 'src/indexed_viewport.dart';
export 'src/patch_view.dart';
export 'src/styles.dart';
