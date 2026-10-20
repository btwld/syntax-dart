import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/langs/json.dart';
import 'package:syntax/langs/markdown.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:test/test.dart';

void main() {
  final highlighter = Highlighter(
    languages: [dartLanguage, jsonLanguage, markdownLanguage],
  );

  test('tokens cover every line exactly', () {
    const code = "void main() {\n  print('hi \$name');\n}\n";
    final lines = highlighter.tokenize(code, language: 'dart');
    expect(lines, hasLength(4));
    final source = code.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].map((t) => source[i].substring(t.start, t.end));
      expect(text.join(), source[i]);
    }
    final interpolation = lines[1].firstWhere(
      (t) => source[1].substring(t.start, t.end) == 'name',
    );
    expect(
      interpolation.scopes.scopes,
      contains('string.interpolated.single.dart'),
    );
  });

  test('themed tokens merge runs with the same style', () {
    final lines = highlighter.highlight(
      '{"a": 1}',
      language: 'json',
      theme: githubDarkTheme,
    );
    expect(lines.single.map((t) => t.text).join(), '{"a": 1}');
    for (var i = 1; i < lines.single.length; i++) {
      expect(lines.single[i].style, isNot(lines.single[i - 1].style));
    }
  });

  test('state carries across lines and converges', () {
    final grammar = highlighter.grammar('dart');
    final a = grammar.tokenizeLine('/* open');
    final b = grammar.tokenizeLine('still comment', a.endState);
    expect(b.tokens.single.scopes.scopes, contains('comment.block.dart'));
    final c = grammar.tokenizeLine('done */', b.endState);
    final fresh = grammar.tokenizeLine('var x = 1;');
    expect(c.endState, equals(fresh.endState));
    expect(c.endState.hashCode, fresh.endState.hashCode);
    expect(b.endState, isNot(equals(fresh.endState)));
    expect(b.endState.scopes.scopes, contains('comment.block.dart'));
  });

  test('empty input, blank lines and CRLF', () {
    expect(highlighter.tokenize('', language: 'dart'), [isEmpty]);
    final lines = highlighter.tokenize('a\r\n\r\nb', language: 'dart');
    expect(lines, hasLength(3));
    expect(lines[0].single.end, 1); // the \r is not part of the line
    expect(lines[1], isEmpty);
  });

  test('a state is rejected by a different grammar', () {
    final dartState = highlighter.grammar('dart').tokenizeLine('/*').endState;
    expect(
      () => highlighter.grammar('json').tokenizeLine('{}', dartState),
      throwsArgumentError,
    );
  });

  group('addLanguage', () {
    Map<String, Object?> grammar(String scope, String keyword) => {
      'scopeName': scope,
      'patterns': [
        {'match': keyword, 'name': 'keyword.$keyword'},
        {'include': 'source.other'},
      ],
    };

    test('keeps unaffected grammars and their states', () {
      final h = Highlighter(languages: [dartLanguage]);
      final dart = h.grammar('dart');
      final state = dart.tokenizeLine('/* open').endState;
      h.addLanguage(jsonLanguage);
      expect(h.grammar('dart'), same(dart));
      final next = h.grammar('dart').tokenizeLine('still', state);
      expect(next.tokens.single.scopes.scopes, contains('comment.block.dart'));
    });

    test('rebuilds a grammar that was missing an include', () {
      final h = Highlighter(
        languages: [Language.fromJson(grammar('source.a', 'one'), name: 'a')],
      );
      final before = h.grammar('a');
      expect(before.tokenizeLine('two').tokens.single.scopes.scopes, [
        'source.a',
      ]);
      h.addLanguage(
        Language.fromJson(grammar('source.other', 'two'), name: 'o'),
      );
      final after = h.grammar('a');
      expect(after, isNot(same(before)));
      expect(after.tokenizeLine('two').tokens.single.scopes.scopes, [
        'source.a',
        'keyword.two',
      ]);
    });

    test('replacing a language drops its old names', () {
      final h = Highlighter(
        languages: [
          Language.fromJson(
            grammar('source.a', 'one'),
            name: 'a',
            aliases: ['x'],
          ),
        ],
      );
      h.addLanguage(Language.fromJson(grammar('source.a', 'two'), name: 'b'));
      expect(h.language('a'), isNull);
      expect(h.language('x'), isNull);
      expect(h.languages, ['b']);
    });

    test('injections from another language apply', () {
      final h = Highlighter(
        languages: [
          Language.fromJson(grammar('source.a', 'one'), name: 'a'),
          Language.fromJson(
            {
              'scopeName': 'todo.injection',
              'injectionSelector': 'L:source.a',
              'patterns': [
                {'match': 'TODO', 'name': 'keyword.todo'},
              ],
            },
            name: 'todo',
            injectTo: ['source.a'],
          ),
        ],
      );
      final tokens = h.grammar('a').tokenizeLine('one TODO').tokens;
      expect(tokens.last.scopes.scopes, ['source.a', 'keyword.todo']);
    });

    test('rebuilds a grammar when an included language is replaced', () {
      final h = Highlighter(
        languages: [
          Language.fromJson(grammar('source.a', 'one'), name: 'a'),
          Language.fromJson(grammar('source.other', 'two'), name: 'o'),
        ],
      );
      expect(h.grammar('a').tokenizeLine('two').tokens.single.scopes.scopes, [
        'source.a',
        'keyword.two',
      ]);
      h.addLanguage(
        Language.fromJson(grammar('source.other', 'three'), name: 'o'),
      );
      expect(h.grammar('a').tokenizeLine('three').tokens.single.scopes.scopes, [
        'source.a',
        'keyword.three',
      ]);
    });

    test('an injection added later reaches built grammars and sub-scopes', () {
      final h = Highlighter(
        languages: [
          Language.fromJson(grammar('source.a', 'one'), name: 'a'),
          Language.fromJson(grammar('source.a.tags', 'one'), name: 'tags'),
        ],
      );
      for (final name in ['a', 'tags']) {
        h.grammar(name).tokenizeLine('one TODO');
      }
      h.addLanguage(
        Language.fromJson(
          {
            'scopeName': 'todo.injection',
            'injectionSelector': 'L:source.a',
            'patterns': [
              {'match': 'TODO', 'name': 'keyword.todo'},
            ],
          },
          name: 'todo',
          injectTo: ['source.a'],
        ),
      );
      for (final name in ['a', 'tags']) {
        final tokens = h.grammar(name).tokenizeLine('one TODO').tokens;
        expect(tokens.last.scopes.scopes.last, 'keyword.todo', reason: name);
      }
    });

    test('a grammar without scopeName is rejected clearly', () {
      expect(
        () => Language.fromJson({'patterns': []}, name: 'broken'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('"broken"'),
          ),
        ),
      );
    });
  });

  test('Markdown fences highlight embedded languages', () {
    final lines = highlighter.tokenize(
      '```dart\nfinal x = 1;\n```',
      language: 'markdown',
    );
    expect(lines[1].first.scopes.scopes, contains('meta.embedded.block.dart'));
    expect(lines[1].first.scopes.scopes, contains('storage.modifier.dart'));
  });

  test('aliases and scope names resolve', () {
    expect(highlighter.language('md'), same(markdownLanguage));
    expect(highlighter.language('source.dart'), same(dartLanguage));
    expect(() => highlighter.grammar('cobol'), throwsArgumentError);
  });

  test('long lines can be skipped', () {
    final limited = Highlighter(languages: [dartLanguage], maxLineLength: 10);
    final grammar = limited.grammar('dart');
    final open = grammar.tokenizeLine('/*');
    final skipped = grammar.tokenizeLine(
      'final someLongName = 1;',
      open.endState,
    );
    expect(skipped.tokens.single.scopes.scopes, contains('comment.block.dart'));
    expect(skipped.endState, open.endState);
  });

  group('renderers', () {
    test('HTML escapes text and uses inline styles', () {
      final html = highlighter.toHtml(
        'a < b && "c"',
        language: 'dart',
        theme: githubDarkTheme,
      );
      expect(html, startsWith('<pre class="syntax github-dark"'));
      expect(html, contains('&lt;'));
      expect(html, contains('&amp;&amp;'));
      expect(html, contains('style="color:#'));
    });

    test('ANSI uses 24-bit color and resets', () {
      final ansi = highlighter.toAnsi(
        'final x = 1;',
        language: 'dart',
        theme: githubDarkTheme,
      );
      expect(ansi, contains('\x1B[38;2;'));
      expect(ansi, endsWith('\x1B[0m'));
    });

    test('ANSI neutralizes control characters in the code', () {
      final ansi = highlighter.toAnsi(
        'x = "\x1B[2J";',
        language: 'dart',
        theme: githubDarkTheme,
      );
      expect(ansi, isNot(contains('\x1B[2J')));
      expect(ansi, contains('\uFFFD[2J'));
    });

    test('ANSI background paints whole rows', () {
      final ansi = highlighter.toAnsi(
        'a\n\nb',
        language: 'dart',
        theme: githubDarkTheme,
        background: true,
      );
      expect('\x1B[K'.allMatches(ansi), hasLength(3));
    });

    test('HTML escapes the theme name', () {
      final theme = SyntaxTheme.fromJson({'name': '"><x'});
      expect(
        highlighter.toHtml('1', language: 'dart', theme: theme),
        startsWith('<pre class="syntax &quot;&gt;&lt;x"'),
      );
    });
  });

  group('themes', () {
    test('custom JSON themes resolve specificity and parent scopes', () {
      final theme = SyntaxTheme.fromJson({
        'type': 'dark',
        'colors': {
          'editor.foreground': '#ffffff',
          'editor.background': '#000000',
        },
        'tokenColors': [
          {
            'scope': 'string',
            'settings': {'foreground': '#ff0000'},
          },
          {
            'scope': 'string.quoted',
            'settings': {'fontStyle': 'italic'},
          },
          {
            'scope': 'meta.embedded string.quoted',
            'settings': {'foreground': '#00ff00'},
          },
        ],
      });
      ScopeStack stack(String scopes) => scopes
          .split(' ')
          .skip(1)
          .fold(ScopeStack.root(scopes.split(' ').first), (s, x) => s.push(x));

      final quoted = theme.styleFor(stack('source.x string.quoted.double'));
      expect(quoted.foreground, 0xFFFF0000); // inherited from `string`
      expect(quoted.italic, isTrue);
      // Same depth, so the rule with a parent scope is more specific.
      final embedded = theme.styleFor(
        stack('source.x meta.embedded.x string.quoted'),
      );
      expect(embedded.foreground, 0xFF00FF00);
      expect(embedded.italic, isTrue);
      final plain = theme.styleFor(stack('source.x'));
      expect(plain.foreground, 0xFFFFFFFF);
      expect(theme.background, 0xFF000000);
      expect(theme.isDark, isTrue);
    });

    test('chrome colors come from the theme or sensible defaults', () {
      expect(
        githubDarkTheme.lineNumberForeground,
        githubDarkTheme.editorColor('editorLineNumber.foreground'),
      );
      final bare = SyntaxTheme.fromJson({
        'type': 'light',
        'colors': {'editor.foreground': '#102030'},
      });
      expect(bare.lineNumberForeground, 0x66102030);
      expect(bare.selectionBackground, 0x66ADD6FF);
      expect(bare.cursorForeground, 0xFF102030);
    });

    test('editor colors and equality', () {
      expect(
        githubDarkTheme.editorColor('editor.background'),
        githubDarkTheme.background,
      );
      expect(githubDarkTheme.editorColor('no.such.key'), isNull);
      final json = <String, Object?>{'name': 'a'};
      expect(SyntaxTheme.fromJson(json), SyntaxTheme.fromJson(json));
      expect(
        SyntaxTheme.fromJson(json),
        isNot(SyntaxTheme.fromJson({...json})),
      );
    });

    test('hex colors parse and format', () {
      expect(parseHexColor('#abc'), 0xFFAABBCC);
      expect(parseHexColor('#11223344'), 0x44112233);
      expect(parseHexColor('red'), isNull);
      expect(colorToHex(0xFFAABBCC), '#aabbcc');
      expect(colorToHex(0x44112233), '#11223344');
    });
  });
}
