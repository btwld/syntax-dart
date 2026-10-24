import 'package:syntax_core/syntax.dart';
import 'package:test/test.dart';

/// Every scan through both scanner implementations, so the combined
/// alternation regex is checked against the per-pattern search.
List<Object?>? scanBoth(
  List<String> patterns,
  String line, {
  int start = 0,
  bool allowA = false,
  bool allowG = false,
}) {
  List<Object?>? run(bool combine) {
    // No size limit, so the combined path is tested whatever the default.
    final m =
        DartRegexEngine(combinePatterns: combine, combineMaxSource: 1 << 30)
            .createScanner(patterns)
            .findNextMatch('$line\n', start, allowA: allowA, allowG: allowG);
    if (m == null) return null;
    return [
      m.patternIndex,
      m.start,
      m.end,
      for (var g = 1; g <= m.groupCount; g++)
        [m.captureStart(g), m.captureEnd(g)],
    ];
  }

  final combined = run(true);
  expect(combined, run(false), reason: 'combined and per-pattern differ');
  return combined;
}

void main() {
  test('the leftmost match wins', () {
    expect(scanBoth(['b', 'a'], 'xab'), [1, 1, 2]);
  });

  test('ties go to the earlier pattern', () {
    expect(scanBoth(['ab', 'a'], 'ab'), [0, 0, 2]);
    expect(scanBoth(['a', 'ab'], 'ab'), [0, 0, 1]);
  });

  test('capture offsets come from the winning pattern', () {
    expect(scanBoth([r'(x)y', r'a(b)(c)?'], 'zab'), [
      1,
      1,
      3,
      [2, 3],
      [-1, -1],
    ]);
  });

  test('capture offsets after variable-length text', () {
    expect(scanBoth([r'zzz', r'\s*(\w+)\s*=\s*(\d+)'], '  ab = 12'), [
      1,
      0,
      9,
      [2, 4],
      [7, 9],
    ]);
    expect(scanBoth([r'zzz', r'(?:(\w)-)+'], 'a-b-c-'), [
      1,
      0,
      6,
      [4, 5],
    ]);
  });

  test(r'\A and \G follow allowA and allowG', () {
    expect(scanBoth([r'\Ax', 'y'], 'xy'), [1, 1, 2]);
    expect(scanBoth([r'\Ax', 'y'], 'xy', allowA: true), [0, 0, 1]);
    expect(scanBoth([r'\Gb', 'b'], 'ab', start: 1, allowG: true), [0, 1, 2]);
    expect(scanBoth([r'\Gb', 'b'], 'ab', start: 1), [1, 1, 2]);
  });

  test('a case-insensitive pattern with a backreference', () {
    expect(scanBoth([r'(?i)(a)\1', 'zzz'], 'aA'), [
      0,
      0,
      2,
      [0, 1],
    ]);
  });

  test('repeated searches on one line agree with fresh scanners', () {
    const patterns = [r'\bfoo\b', r'\d+', r'"[^"]*"'];
    const line = 'foo 12 "s" foo 3';
    final scanner = DartRegexEngine().createScanner(patterns);
    for (var start = 0; start <= line.length; start++) {
      final reused = scanner.findNextMatch(
        '$line\n',
        start,
        allowA: false,
        allowG: false,
      );
      final fresh = scanBoth(patterns, line, start: start);
      expect(
        reused == null ? null : [reused.patternIndex, reused.start, reused.end],
        fresh?.take(3).toList(),
        reason: 'from $start',
      );
    }
  });

  test('an unsupported pattern is reported once and never matches', () {
    final reported = <String>[];
    final engine = DartRegexEngine(
      onUnsupportedPattern: (pattern, _) => reported.add(pattern),
    );
    final scanner = engine.createScanner([r'(?(1)a|b)', 'b']);
    final m = scanner.findNextMatch('ab\n', 0, allowA: false, allowG: false);
    expect([m?.patternIndex, m?.start], [1, 1]);
    engine.createScanner([r'(?(1)a|b)']);
    expect(reported, [r'(?(1)a|b)']);
  });
}
