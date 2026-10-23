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
export 'src/presentation.dart';
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
