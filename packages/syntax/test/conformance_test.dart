// Compares syntax with Shiki on every sample in test/fixtures.
//
// The golden files are produced by tool/golden.mjs, which runs Shiki with
// its Oniguruma WASM engine. That makes them the reference behavior of
// vscode-textmate. Each sample is checked twice: raw scopes per token, and
// the color and font style of every character for several themes.

import 'dart:convert';
import 'dart:io';

import 'package:syntax/syntax.dart';
import 'package:syntax/langs/all.dart';
import 'package:syntax/themes/all.dart';
import 'package:test/test.dart';

void main() {
  final unsupported = <String>{};
  final highlighter = Highlighter(
    languages: bundledLanguages.values,
    engine: DartRegexEngine(
      onUnsupportedPattern: (pattern, error) => unsupported.add('$error'),
    ),
  );
  final goldenDir = Directory('test/fixtures/golden');
  final files = goldenDir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final golden = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final lang = golden['lang'] as String;
    final sample = golden['sample'] as String;
    final code = File('test/fixtures/samples/$sample').readAsStringSync();
    final lines = code.split(RegExp(r'\r?\n'));

    group(sample, () {
      test('scopes match Shiki', () {
        final expected = golden['tokens'] as List<Object?>;
        final grammar = highlighter.grammar(lang);
        StateStack? state;
        final diffs = <String>[];
        for (var i = 0; i < lines.length; i++) {
          final result = grammar.tokenizeLine(lines[i], state);
          state = result.endState;
          final actual = [
            for (final t in result.tokens)
              [t.start, t.end, t.scopes.toString()],
          ];
          final want = expected[i] as List<Object?>;
          if (jsonEncode(actual) != jsonEncode(want)) {
            diffs.add(_describeLineDiff(i, lines[i], want, actual));
          }
        }
        expect(
          diffs,
          isEmpty,
          reason:
              '${diffs.length} of ${lines.length} lines differ:\n'
              '${diffs.take(5).join('\n')}',
        );
      });

      final themes = golden['themes'] as Map<String, Object?>;
      for (final MapEntry(key: themeName, value: expectedRuns)
          in themes.entries) {
        test('colors match Shiki ($themeName)', () {
          final theme = bundledThemes[themeName]!;
          final highlighted = highlighter.highlight(
            code,
            language: lang,
            theme: theme,
          );
          var mismatched = 0;
          var total = 0;
          final examples = <String>[];
          for (var i = 0; i < lines.length; i++) {
            final want = _charStyles(
              lines[i].length,
              (expectedRuns as List<Object?>)[i] as List<Object?>,
            );
            final got = _actualCharStyles(lines[i].length, highlighted[i]);
            for (var c = 0; c < lines[i].length; c++) {
              total++;
              if (want[c] != got[c]) {
                mismatched++;
                if (examples.length < 5) {
                  examples.add(
                    'line ${i + 1} col ${c + 1} '
                    '${jsonEncode(lines[i][c])}: want ${want[c]}, got ${got[c]}',
                  );
                }
              }
            }
          }
          expect(
            mismatched,
            0,
            reason:
                '$mismatched of $total characters differ:\n'
                '${examples.join('\n')}',
          );
        });
      }
    });
  }

  test('no bundled pattern was unsupported', () {
    expect(unsupported, isEmpty);
  });
}

List<String> _charStyles(int length, List<Object?> runs) {
  final result = List.filled(length, '?');
  for (final run in runs.cast<List<Object?>>()) {
    final start = run[0] as int;
    final end = run[1] as int;
    final color = parseHexColor(run[2] as String);
    final style = '${color == null ? run[2] : colorToHex(color)}/${run[3]}';
    for (var c = start; c < end && c < length; c++) {
      result[c] = style;
    }
  }
  return result;
}

List<String> _actualCharStyles(int length, List<ThemedToken> tokens) {
  final result = List.filled(length, '?');
  for (final token in tokens) {
    final style =
        '${colorToHex(token.style.foreground)}/${token.style.fontStyle}';
    for (var c = token.offset; c < token.offset + token.text.length; c++) {
      if (c < length) result[c] = style;
    }
  }
  return result;
}

String _describeLineDiff(
  int index,
  String line,
  List<Object?> want,
  List<Object?> got,
) {
  final buffer = StringBuffer('line ${index + 1}: ${jsonEncode(line)}\n');
  final n = want.length > got.length ? want.length : got.length;
  for (var i = 0; i < n; i++) {
    final w = i < want.length ? jsonEncode(want[i]) : '-';
    final g = i < got.length ? jsonEncode(got[i]) : '-';
    if (w != g) {
      buffer
        ..writeln('  want $w')
        ..writeln('  got  $g');
      break;
    }
  }
  return buffer.toString();
}
