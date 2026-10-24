import 'package:noir/noir.dart';
import 'package:syntax_darts/langs/dart.dart';
import 'package:syntax_darts/syntax.dart' as syntax;
import 'package:syntax_darts/themes/github_dark.dart';
import 'package:syntax_noir/syntax_noir.dart';
import 'package:test/test.dart';

final highlighter = syntax.Highlighter(languages: [dartLanguage]);

/// The rules noir's CodeView checks before painting ranges.
void expectValid(String source, List<StyledTextRange> ranges) {
  var previousEnd = 0;
  for (final r in ranges) {
    expect(r.start, greaterThanOrEqualTo(previousEnd), reason: 'overlap');
    expect(r.end, greaterThan(r.start), reason: 'empty range');
    expect(r.end, lessThanOrEqualTo(source.length), reason: 'out of bounds');
    previousEnd = r.end;
  }
}

void main() {
  const source = 'final a = 1;\r\n// note\nvar b = "x";\n';

  test('ranges are valid for noir and color the right text', () {
    final noirHighlighter = SyntaxCodeHighlighter(highlighter, githubDarkTheme);
    final ranges = noirHighlighter.highlight(source, language: 'dart');
    expectValid(source, ranges);
    final expected = highlighter.highlightRanges(
      source,
      language: 'dart',
      theme: githubDarkTheme,
    );
    expect(
      [for (final r in ranges) source.substring(r.start, r.end)],
      [for (final r in expected) source.substring(r.start, r.end)],
    );
    final keyword = ranges.firstWhere(
      (r) => source.substring(r.start, r.end) == 'final',
    );
    final style = expected.firstWhere(
      (r) => source.substring(r.start, r.end) == 'final',
    );
    expect(keyword.style.color, noirColor(style.style.foreground));
  });

  test('edits re-highlight; unknown or missing languages stay plain', () {
    final noirHighlighter = SyntaxCodeHighlighter(highlighter, githubDarkTheme);
    noirHighlighter.highlight(source, language: 'dart');
    final edited = source.replaceFirst('var b', 'final bb');
    final ranges = noirHighlighter.highlight(edited, language: 'dart');
    expectValid(edited, ranges);
    expect(
      ranges.where((r) => edited.substring(r.start, r.end) == 'final'),
      hasLength(2),
    );
    expect(noirHighlighter.highlight(source, language: 'cobol'), isEmpty);
    expect(noirHighlighter.highlight(source), isEmpty);
  });
}
