import 'dart:math';

import 'package:syntax_darts/langs/dart.dart';
import 'package:syntax_darts/langs/json.dart';
import 'package:syntax_darts/syntax.dart';
import 'package:syntax_darts/themes/github_dark.dart';
import 'package:syntax_darts/themes/github_light.dart';
import 'package:test/test.dart';

final highlighter = Highlighter(languages: [dartLanguage, jsonLanguage]);

String describe(List<List<Token>> lines) => [
  for (final line in lines)
    line.map((t) => '${t.start}-${t.end}:${t.scopes}').join(' | '),
].join('\n');

List<List<Token>> tokensOf(TokenizedDocument document) => [
  for (final line in document.lines) line.tokens,
];

void main() {
  group('TokenizedDocument', () {
    test('incremental tokens always equal a full re-tokenize', () {
      final document = TokenizedDocument(highlighter.grammar('dart'));
      var text = 'class A {\n  // hi\n  final s = "x";\n}\n';
      document.update(text);
      final random = Random(7);
      const inserts = ['/*', '*/', '"', "'''", '\n', 'var y = 1;', '}', '{'];
      for (var step = 0; step < 300; step++) {
        final at = random.nextInt(text.length + 1);
        if (random.nextBool() && text.isNotEmpty) {
          final end = min(text.length, at + random.nextInt(4) + 1);
          text = text.replaceRange(min(at, end), end, '');
        } else {
          text = text.replaceRange(
            at,
            at,
            inserts[random.nextInt(inserts.length)],
          );
        }
        document.update(text);
        expect(
          describe(tokensOf(document)),
          describe(highlighter.tokenize(text, language: 'dart')),
          reason: 'after step $step:\n$text',
        );
      }
    });

    test('a budget tokenizes from the top, at least a line at a time', () {
      final document = TokenizedDocument(highlighter.grammar('dart'));
      final text = List.filled(50, 'final x = 1;').join('\n');
      expect(document.update(text, budget: Duration.zero), isFalse);
      expect(document.lines, hasLength(1));
      expect(document.isComplete, isFalse);
      expect(document.tokenize(budget: Duration.zero), isFalse);
      expect(document.lines, hasLength(2));
      // The same text continues where it stopped.
      expect(document.update(text, budget: Duration.zero), isFalse);
      expect(document.lines, hasLength(3));
      expect(document.tokenize(), isTrue);
      expect(document.lines, hasLength(50));
      expect(document.isComplete, isTrue);
    });

    test('budgeted updates are right at every step, even when interrupted '
        'by the next edit', () {
      final document = TokenizedDocument(highlighter.grammar('dart'));
      var text = 'class A {\n  // hi\n  final s = "x";\n}\n' * 10;
      final random = Random(11);
      const inserts = ['/*', '*/', '"', "'''", '\n', 'var y = 1;', '}', '{'];
      for (var step = 0; step < 200; step++) {
        final at = random.nextInt(text.length + 1);
        text = random.nextBool() && text.isNotEmpty
            ? text.replaceRange(at, min(text.length, at + 3), '')
            : text.replaceRange(at, at, inserts[random.nextInt(8)]);
        final expected = highlighter.tokenize(text, language: 'dart');
        var done = document.update(text, budget: Duration.zero);
        // Lines tokenized so far are already right.
        expect(
          describe(tokensOf(document)),
          describe(expected.take(document.lines.length).toList()),
          reason: 'after step $step:\n$text',
        );
        // Otherwise the next edit arrives first.
        if (random.nextInt(3) == 0) continue;
        while (!done) {
          done = document.tokenize(budget: Duration.zero);
        }
        expect(
          describe(tokensOf(document)),
          describe(expected),
          reason: 'after step $step:\n$text',
        );
      }
    });

    test('unchanged lines keep their objects', () {
      final document = TokenizedDocument(highlighter.grammar('dart'))
        ..update('var a = 1;\nvar b = 2;\nvar c = 3;');
      final [first, _, last] = document.lines;
      document.update('var a = 1;\nvar b = 22;\nvar c = 3;');
      expect(document.lines.first, same(first));
      expect(document.lines.last, same(last));
    });

    test('the same grammar keeps lines; theming is cached per theme', () {
      final grammar = highlighter.grammar('dart');
      final document = TokenizedDocument(grammar)..update('var a = 1;');
      final line = document.lines.single;
      document.grammar = grammar;
      expect(document.lines.single, same(line));
      final themed = line.themed(githubDarkTheme);
      expect(line.themed(githubDarkTheme), same(themed));
      expect(line.themed(githubLightTheme), isNot(same(themed)));
      expect(() => document.lines.clear(), throwsUnsupportedError);
    });

    test('long lines are left untokenized by default', () {
      final long = 'var x = ${'1 + ' * 5000}1;';
      expect(long.length, greaterThan(20000));
      final limited = TokenizedDocument(highlighter.grammar('dart'))
        ..update(long);
      expect(limited.lines.single.tokens, hasLength(1));
      final unlimited = Highlighter(
        languages: [dartLanguage],
        maxLineLength: 0,
      );
      final full = TokenizedDocument(unlimited.grammar('dart'))..update(long);
      expect(full.lines.single.tokens.length, greaterThan(1));
    });

    test('a new grammar re-tokenizes everything', () {
      final document = TokenizedDocument(highlighter.grammar('dart'))
        ..update('{"a": 1}');
      final before = document.lines.single;
      document.grammar = highlighter.grammar('json');
      document.update('{"a": 1}');
      expect(document.lines.single, isNot(same(before)));
      expect(
        document.lines.single.tokens.first.scopes.scopes.first,
        'source.json',
      );
    });
  });

  group('ranges', () {
    // Mixed line endings, an empty line and a trailing break.
    const code = 'final a = 1;\r\n\r\n// note\nvar b = "x";\r\n';

    test('cover every token, at offsets into the whole text', () {
      final ranges = highlighter.highlightRanges(
        code,
        language: 'dart',
        theme: githubDarkTheme,
      );
      final lines = highlighter.highlight(
        code,
        language: 'dart',
        theme: githubDarkTheme,
      );
      expect(
        [for (final r in ranges) code.substring(r.start, r.end)],
        [
          for (final line in lines)
            for (final token in line)
              if (token.text.isNotEmpty) token.text,
        ],
      );
      expect(
        [for (final r in ranges) r.style],
        [
          for (final line in lines)
            for (final token in line)
              if (token.text.isNotEmpty) token.style,
        ],
      );
    });

    test('are ordered, non-empty and never touch a line break', () {
      final ranges = highlighter.highlightRanges(
        code,
        language: 'dart',
        theme: githubDarkTheme,
      );
      var previousEnd = 0;
      for (final range in ranges) {
        expect(range.start, greaterThanOrEqualTo(previousEnd));
        expect(range.end, greaterThan(range.start));
        expect(range.end, lessThanOrEqualTo(code.length));
        expect(code.substring(range.start, range.end), isNot(contains('\n')));
        expect(code.substring(range.start, range.end), isNot(contains('\r')));
        previousEnd = range.end;
      }
    });

    test('follow edits through the document', () {
      final document = TokenizedDocument(highlighter.grammar('dart'))
        ..update(code);
      final edited = code.replaceFirst('var b', 'final bb');
      document.update(edited);
      expect(
        document.ranges(githubDarkTheme),
        highlighter.highlightRanges(
          edited,
          language: 'dart',
          theme: githubDarkTheme,
        ),
      );
    });
  });
}
