// Tokenizes a large Dart file and reports throughput.
//   dart run benchmark/tokenize.dart <file.dart>
//   dart compile exe benchmark/tokenize.dart -o /tmp/bench && /tmp/bench <file>
import 'dart:io';

import 'package:syntax_core/syntax.dart';
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/themes/github_dark.dart';

void main(List<String> args) {
  final code = File(args.single).readAsStringSync();
  final kb = code.length / 1024;

  var sw = Stopwatch()..start();
  var highlighter = Highlighter(languages: [dartLanguage]);
  highlighter.highlight(code, language: 'dart', theme: githubDarkTheme);
  final cold = sw.elapsedMilliseconds;

  const runs = 5;
  sw = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    highlighter.highlight(code, language: 'dart', theme: githubDarkTheme);
  }
  final warm = sw.elapsedMilliseconds / runs;
  final lines = '\n'.allMatches(code).length + 1;
  print(
    '${kb.toStringAsFixed(0)} KB, $lines lines: cold ${cold}ms, '
    'warm ${warm.toStringAsFixed(1)}ms '
    '(${(kb / 1024 / (warm / 1000)).toStringAsFixed(2)} MB/s)',
  );
}
