import 'package:syntax/src/regex/engine.dart';
import 'package:syntax/src/regex/onig_translator.dart';
import 'package:test/test.dart';

/// Runs [pattern] the way the tokenizer does: on a line with a trailing
/// "\n", searching from [start]. Returns `[start, end, group1, ...]` as
/// offsets, or `null` for no match.
List<Object?>? scan(
  String pattern,
  String line, {
  int start = 0,
  bool allowA = true,
  bool allowG = true,
}) {
  final engine = DartRegexEngine(
    onUnsupportedPattern: (p, e) => fail('Unsupported: $e'),
  );
  final m = engine
      .createScanner([pattern])
      .findNextMatch('$line\n', start, allowA: allowA, allowG: allowG);
  if (m == null) return null;
  return [
    m.start,
    m.end,
    for (var g = 1; g <= m.groupCount; g++)
      [m.captureStart(g), m.captureEnd(g)],
  ];
}

void main() {
  group('anchors', () {
    test(r'^ does not match after the final newline', () {
      expect(scan(r'^\s*$', 'code'), isNull);
      // \s* also takes the appended newline, as in Oniguruma.
      expect(scan(r'^\s*$', ''), [0, 1]);
    });

    test(r'\A only matches on the first line', () {
      expect(scan(r'\Afoo', 'foo'), [0, 3]);
      expect(scan(r'\Afoo', 'foo', allowA: false), isNull);
    });

    test(r'\z and \Z', () {
      // vscode-textmate rewrites \z so it cannot match on a "\n"-terminated
      // line. \Z matches before the final newline.
      expect(scan(r'a\z', 'a'), isNull);
      expect(scan(r'a\Z', 'a'), [0, 1]);
    });

    test(r'\G matches only at the anchor', () {
      expect(scan(r'\Gb', 'ab', start: 1), [1, 2]);
      expect(scan(r'\Gb', 'ab', start: 1, allowG: false), isNull);
      expect(scan(r'\Gb', 'abb', start: 1), [1, 2]);
      // Not a leading \G: needs the positional assertion.
      expect(scan(r'(?:x|\G)b', 'ab', start: 1), [1, 2]);
      expect(scan(r'(?!\G)b', 'abb', start: 1), [2, 3]);
    });
  });

  group('Oniguruma-only syntax', () {
    test(r'\h is a hex digit, not the letter h', () {
      expect(scan(r'\h+', 'zz 1aF'), [3, 6]);
      expect(scan(r'[\h_]+', 'x_af'), [1, 4]);
    });

    test('possessive quantifiers never give back', () {
      expect(scan(r'a++a', 'aaaa'), isNull);
      expect(scan(r'a+a', 'aaaa'), [0, 4]);
    });

    test('atomic groups keep capture numbering', () {
      expect(scan(r'(?>(a+))b(c)', 'aabc'), [
        0,
        4,
        [0, 2],
        [3, 4],
      ]);
    });

    test('reversed interval is possessive', () {
      expect(scan(r'\s+{1,0}x', '  x'), [0, 3]);
    });

    test(
      'isolated (?i) spans the rest of the group, alternatives included',
      () {
        expect(scan(r'a(?i)b|c', 'C'), isNull); // a(?i:b|c)
        expect(scan(r'a(?i)b|c', 'aC'), [0, 2]);
        expect(scan(r'x(?i:abc)', 'xAbC'), [0, 4]);
      },
    );

    test('case-insensitive non-ASCII ranges', () {
      expect(scan(r'x(?i:[а-я]+)', 'xПривет'), [0, 7]);
    });

    test('extended mode strips whitespace and comments', () {
      expect(scan('(?x) a  b # comment\n c', 'abc'), [0, 3]);
    });

    test('POSIX brackets, nested classes and intersections', () {
      expect(scan(r'[[:alpha:]]+', '12abc'), [2, 5]);
      expect(scan(r'[a-z&&[^aeiou]]+', 'aabcde'), [2, 5]);
      expect(scan(r'[a[0-9]]+', 'xa1b'), [1, 3]);
      expect(scan(r'[]a]+', 'x]a'), [1, 3]);
    });

    test(r'\x{} and Unicode properties', () {
      expect(scan(r'\x{1F600}', 'a😀'), [1, 3]);
      expect(scan(r'\p{Greek}+', 'aαβ'), [1, 3]);
      expect(scan(r'\p{^L}', 'ab1'), [2, 3]);
    });

    test(r'\K keeps only what follows', () {
      expect(scan(r'foo\Kbar', 'foobar'), [3, 6]);
    });

    test('subroutine calls expand to a fixed depth', () {
      expect(scan(r'(?<p>\((?:[^()]|\g<p>)*\))', 'f((a)(b))'), [
        1,
        9,
        [1, 9],
      ]);
    });

    test(r'Unicode \w and \b on non-ASCII lines', () {
      expect(scan(r'\b\w+\b', 'Функция'), [0, 7]);
      expect(scan(r'\b\w+\b', 'plain'), [0, 5]);
    });

    test('captures report offsets, including inside lookaheads', () {
      expect(scan(r'(a)(?=(b))', 'xab'), [
        1,
        2,
        [1, 2],
        [2, 3],
      ]);
      expect(scan(r'(a)|(b)', 'b'), [
        0,
        1,
        [-1, -1],
        [0, 1],
      ]);
    });
  });

  group('capture offsets', () {
    test('after variable-length text', () {
      expect(scan(r'\s*(\w+)\s*=\s*(\d+)', '  ab = 12'), [
        0,
        9,
        [2, 4],
        [7, 9],
      ]);
      expect(scan(r'(a)\1(b)', 'aab'), [
        0,
        3,
        [0, 1],
        [2, 3],
      ]);
    });

    test('in repeated groups, from the last iteration', () {
      expect(scan(r'(?:(\w)-)+', 'a-b-c-'), [
        0,
        6,
        [4, 5],
      ]);
      expect(scan(r'(\w)+', 'abc'), [
        0,
        3,
        [2, 3],
      ]);
      expect(scan(r'(\d)+?;', '123;'), [
        0,
        4,
        [2, 3],
      ]);
      expect(scan(r'((a)(b)+)c', 'xabbc'), [
        1,
        5,
        [1, 4],
        [1, 2],
        [3, 4],
      ]);
    });

    test('in lookbehinds and lookaheads', () {
      expect(scan(r'(?<=(a|bc)d)e', 'bcde'), [
        3,
        4,
        [0, 2],
      ]);
      expect(scan(r'a+(?=\s*(b))', 'aa  b'), [
        0,
        2,
        [4, 5],
      ]);
      expect(scan(r'(?!(x))(a)', 'a'), [
        0,
        1,
        [-1, -1],
        [0, 1],
      ]);
    });

    test('in atomic groups, possessive repeats and alternations', () {
      expect(scan(r'(?>(a+))b', 'aab'), [
        0,
        3,
        [0, 2],
      ]);
      expect(scan(r'(?:(x)y)++z', 'xyxyz'), [
        0,
        5,
        [2, 3],
      ]);
      expect(scan(r'(?:a(b)|c(d))e', 'cde'), [
        0,
        3,
        [-1, -1],
        [1, 2],
      ]);
    });

    test('far into a long line', () {
      final line = '${'x ' * 50000}key = 1';
      expect(scan(r'(\w+)\s*(=)', line, start: 100000), [
        100000,
        100005,
        [100000, 100003],
        [100004, 100005],
      ]);
    });
  });

  group('fixes from review', () {
    test(r'\K does not let the prefix start before the search start', () {
      expect(scan(r'foo\Kbar', 'foobar', start: 3), isNull);
      expect(scan(r'foo\Kbar', 'xfoobar', start: 1), [4, 7]);
    });

    test(r'\K after \G, after astral characters and after captures', () {
      expect(scan(r'\Gfoo\Kbar', 'foobar'), [3, 6]);
      expect(scan(r'😀\Kx', 'a😀x'), [3, 4]);
      expect(scan(r'(f)oo\K(bar)', 'foobar'), [
        3,
        6,
        [0, 1],
        [3, 6],
      ]);
    });

    test(r'Unicode \w counts all numbers, [[:word:]] only decimal digits', () {
      // Both match Oniguruma: ² is a Number but not a Decimal_Number.
      expect(scan(r'\w+', 'x²'), [0, 2]);
      expect(scan(r'[[:word:]]+', 'x²'), [0, 1]);
    });

    test('a case-insensitive backreference matches either case', () {
      expect(scan(r'(?i)(a)\1', 'aA'), [
        0,
        2,
        [0, 1],
      ]);
    });

    test('references to groups defined later resolve', () {
      expect(scan(r'\g<x>?(?<x>a)', 'aa'), [
        0,
        2,
        [1, 2],
      ]);
    });

    test('parentheses inside (?x) comments are not groups', () {
      // Counting the comment's "(" would point \k<n> at a group 2.
      expect(scan('(?x) \\k<n>? # (comment\n (?<n>a)', 'a'), [
        0,
        1,
        [0, 1],
      ]);
    });
  });

  test(
    'recursion past the depth limit never matches, in a quantifiable way',
    () {
      // Older engines reject `(?:(?!))*`, so the cut-off must be a class.
      final source = translateOnigPattern(
        r'(?<p>\((?:[^()]|\g<p>)*\))',
      ).searchSource(unicodeWords: false);
      expect(source, contains(neverMatch));
      expect(source, isNot(contains('(?!)')));
      expect(scan(r'(?<p>\((?:[^()]|\g<p>)*\))', '(((x)))'), isNotNull);
    },
  );

  test('unsupported constructs are reported, not mistranslated', () {
    expect(
      () => translateOnigPattern(r'(?(1)a|b)'),
      throwsA(isA<UnsupportedPatternException>()),
    );
    expect(
      () => translateOnigPattern(r'(?~|abc)'),
      throwsA(isA<UnsupportedPatternException>()),
    );
    // Out of the Unicode range: rejected instead of throwing RangeError.
    expect(
      () => translateOnigPattern(r'\x{110000}'),
      throwsA(isA<UnsupportedPatternException>()),
    );
  });
}
