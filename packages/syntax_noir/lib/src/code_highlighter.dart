import 'package:noir/noir.dart';
import 'package:syntax_darts/syntax.dart' as syntax;

import 'colors.dart';

/// A noir [CodeHighlighter] backed by syntax, for noir's `CodeView`.
///
/// ```dart
/// CodeView(
///   code: source,
///   language: 'dart',
///   highlighter: SyntaxCodeHighlighter(highlighter, githubDarkTheme),
/// )
/// ```
///
/// It keeps one document per language, so highlighting again after an
/// edit only re-tokenizes the lines the edit affects. A language the
/// highlighter doesn't know, or none, stays plain.
///
/// Don't pass it to noir's `DiffView`: that view highlights its rendered
/// text, line numbers and `+`/`-` markers included, which no grammar reads
/// correctly. Use this package's `PatchView` for diffs.
final class SyntaxCodeHighlighter implements CodeHighlighter {
  /// Highlights with [highlighter]'s languages in [theme]'s colors.
  SyntaxCodeHighlighter(this.highlighter, this.theme);

  /// Provides the grammars.
  final syntax.Highlighter highlighter;

  /// Provides the colors.
  final syntax.SyntaxTheme theme;

  final Map<String, syntax.TokenizedDocument> _documents = {};

  @override
  List<StyledTextRange> highlight(String source, {String? language}) {
    final lang = language == null ? null : highlighter.language(language);
    if (lang == null) return const [];
    final grammar = highlighter.grammar(lang.scopeName);
    final document = _documents[lang.scopeName] ??= syntax.TokenizedDocument(
      grammar,
    );
    document
      ..grammar = grammar
      ..update(source);
    return [
      for (final range in document.ranges(theme))
        StyledTextRange(
          start: range.start,
          end: range.end,
          style: noirTextStyle(range.style, background: theme.background),
        ),
    ];
  }
}
