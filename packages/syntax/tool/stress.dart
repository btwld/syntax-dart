// Compares syntax with the Shiki output recorded by tool/stress.mjs for every
// grammar in tm-grammars. Usage:
//   dart run tool/stress.dart <stressDir> <tm-grammars/grammars dir> [lang]
// With a language name, prints every differing token for that language.
import 'dart:convert';
import 'dart:io';

import 'package:syntax/syntax.dart';

void main(List<String> args) {
  final stressDir = args[0];
  final grammarsDir = args[1];
  final only = args.length > 2 ? args[2] : null;
  final unsupported = <String>[];
  // Shiki has no line-length limit, so neither does the comparison.
  final highlighter = Highlighter(
    maxLineLength: 0,
    engine: DartRegexEngine(
      onUnsupportedPattern: (p, e) => unsupported.add('$e'),
    ),
  );
  final injectTo =
      jsonDecode(File('$stressDir/inject_to.json').readAsStringSync())
          as Map<String, Object?>;
  for (final f in Directory(grammarsDir).listSync().whereType<File>()) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final name = f.uri.pathSegments.last.replaceAll('.json', '');
    highlighter.addLanguage(
      Language.fromJson(
        json,
        name: name,
        injectTo: [
          ...(injectTo[name] as List<Object?>? ?? const []).cast<String>(),
        ],
      ),
    );
  }
  var perfect = 0, total = 0, linesTotal = 0, linesOk = 0;
  final failures = <String>[];
  final goldens =
      Directory('$stressDir/golden').listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final g in goldens) {
    final golden = jsonDecode(g.readAsStringSync()) as Map<String, Object?>;
    final lang = golden['lang'] as String;
    if (only != null && lang != only) continue;
    final code = File('$stressDir/samples/$lang.sample').readAsStringSync();
    final lines = code.split(RegExp(r'\r?\n'));
    final expected = golden['tokens'] as List<Object?>;
    total++;
    var ok = 0;
    String? firstDiff;
    final sw = Stopwatch()..start();
    try {
      final grammar = highlighter.grammar(lang);
      StateStack? state;
      for (var i = 0; i < lines.length; i++) {
        final r = grammar.tokenizeLine(lines[i], state);
        state = r.endState;
        final actual = jsonEncode([
          for (final t in r.tokens) [t.start, t.end, t.scopes.toString()],
        ]);
        if (actual == jsonEncode(expected[i])) {
          ok++;
        } else if (only != null) {
          print('line ${i + 1}: ${jsonEncode(lines[i])}');
          print('  want ${jsonEncode(expected[i])}');
          print('  got  $actual');
        } else {
          firstDiff ??=
              'line ${i + 1}: ${jsonEncode(lines[i].length > 80 ? lines[i].substring(0, 80) : lines[i])}\n'
              '    want ${jsonEncode(expected[i]).substring(0, 300.clamp(0, jsonEncode(expected[i]).length))}\n'
              '    got  ${actual.substring(0, 300.clamp(0, actual.length))}';
        }
      }
    } catch (e) {
      // Report and keep going: one broken grammar should not end the run.
      firstDiff = 'threw $e';
    }
    linesTotal += lines.length;
    linesOk += ok;
    if (ok == lines.length) {
      perfect++;
    } else {
      failures.add(
        '$lang: $ok/${lines.length} lines (${sw.elapsedMilliseconds}ms)\n  $firstDiff',
      );
    }
  }
  print(
    'Grammars matching Shiki exactly: $perfect/$total; '
    'lines: $linesOk/$linesTotal (${(100 * linesOk / linesTotal).toStringAsFixed(2)}%)',
  );
  print('Unsupported patterns hit: ${unsupported.length}');
  for (final f in failures) {
    print(f);
  }
}
