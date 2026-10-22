/// TextMate-grammar syntax highlighting in pure Dart.
///
/// ```dart
/// import 'package:syntax/syntax.dart';
/// import 'package:syntax/langs/dart.dart';
/// import 'package:syntax/themes/github_dark.dart';
///
/// final highlighter = Highlighter(languages: [dartLanguage]);
/// print(highlighter.toAnsi(code, language: 'dart', theme: githubDarkTheme));
/// ```
///
/// Bundled grammars live under `package:syntax/langs/` and themes under
/// `package:syntax/themes/`. Import only the ones you need, so the rest are
/// tree-shaken. Any VS Code grammar or theme JSON can also be loaded at
/// runtime with [Language.fromJson] and [SyntaxTheme.fromJson].
library;

export 'src/edit/text_document.dart';
export 'src/edit/editor.dart';
export 'src/diff/review.dart';
export 'src/diff/comment_thread.dart';
export 'src/diff/merge_colors.dart';
export 'src/diff/patch_controller.dart';
export 'src/highlight_session.dart';
export 'src/theme/catalog.dart';
export 'src/execution/executor.dart';
export 'src/execution/native_stub.dart'
    if (dart.library.io) 'src/execution/native_executor.dart';
export 'src/execution/browser_stub.dart'
    if (dart.library.js_interop) 'src/execution/browser_executor.dart';

export 'src/grammar/grammar.dart'
    show
        Grammar,
        GrammarLookup,
        InjectionLookup,
        LineTokens,
        StateStack,
        Token,
        splitLines;
export 'src/diff/diff_highlight.dart';
export 'src/diff/diff_labels.dart';
export 'src/diff/diff_layout.dart';
export 'src/diff/diff_texts.dart';
export 'src/diff/file_diff.dart';
export 'src/diff/parse_patch.dart';
export 'src/diff/word_diff.dart';
export 'src/document.dart';
export 'src/grammar/scope_stack.dart' show ScopeStack;
export 'src/highlighter.dart';
export 'src/regex/engine.dart'
    show
        DartRegexEngine,
        RegexEngine,
        ScanMatch,
        Scanner,
        UnsupportedPatternCallback;
export 'src/regex/onig_translator.dart' show UnsupportedPatternException;
export 'src/render.dart';
export 'src/theme/theme.dart'
    show
        TokenFontStyle,
        SyntaxTheme,
        TokenStyle,
        alphaBlend,
        colorToHex,
        parseHexColor;
export 'src/edit/file_controller.dart';
export 'src/edit/stream_controller.dart';
export 'src/presentation.dart';
export 'src/execution/presentation_controller.dart';
