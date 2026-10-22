/// Flutter widgets for [syntax](https://pub.dev/packages/syntax): syntax
/// highlighting with TextMate grammars and VS Code themes.
///
/// - [HighlightedCode] shows read-only, highlighted code.
/// - [SyntaxTextEditingController] highlights a `TextField` as you type.
/// - [PatchView] shows a diff or patch, unified or split.
/// - [HighlighterScope] shares one [Highlighter] across the widget tree.
///
/// This library re-exports `package:syntax/syntax.dart`. Import grammars and
/// themes from `package:syntax/langs/...` and `package:syntax/themes/...`.
library;

export 'package:syntax/syntax.dart';

export 'src/highlighted_code.dart';
export 'src/highlighter_scope.dart';
export 'src/patch_view.dart';
export 'src/styles.dart';
export 'src/syntax_text_controller.dart';
export 'src/editor.dart';
export 'src/file_view.dart';
export 'src/selection_actions.dart';
export 'src/comment_composer.dart';
export 'src/comment_thread.dart';
export 'src/comment_navigation.dart'
    show
        CommentNavigationLabels,
        CommentNavigationDetails,
        SyntaxCommentCount,
        SyntaxCommentNavigation;
export 'src/comment_thread_controller.dart';
export 'src/comment_shortcuts.dart';
export 'src/comment_highlight.dart'
    show
        CommentThreadHighlightStyle,
        CommentThreadHighlightDetails,
        CommentSourceHighlightStyle,
        CommentSourceHighlightDetails,
        SyntaxCommentHighlightTheme;
