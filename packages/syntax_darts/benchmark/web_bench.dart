// Tokenizing throughput when compiled to JavaScript, on the same input as
// tokenize.dart:
//   dart compile js -O4 benchmark/web_bench.dart -o /tmp/syntax_bench.js
//   node /tmp/syntax_bench.js path/to/file.dart
import 'dart:js_interop';

import 'package:syntax_darts/langs/dart.dart';
import 'package:syntax_darts/syntax.dart';
import 'package:syntax_darts/themes/github_dark.dart';

@JS('process.argv')
external JSArray<JSString> get _argv;

@JS('process.getBuiltinModule')
external _Fs _module(String name);

extension type _Fs(JSObject _) implements JSObject {
  external String readFileSync(String path, String encoding);
}

void main() {
  final code = _module('fs').readFileSync(_argv.toDart.last.toDart, 'utf8');
  final kb = code.length / 1024;
  for (final combine in [true, false]) {
    final highlighter = Highlighter(
      languages: [dartLanguage],
      engine: DartRegexEngine(combinePatterns: combine),
    );
    var sw = Stopwatch()..start();
    highlighter.highlight(code, language: 'dart', theme: githubDarkTheme);
    final cold = sw.elapsedMilliseconds;
    sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      highlighter.highlight(code, language: 'dart', theme: githubDarkTheme);
    }
    final warm = sw.elapsedMilliseconds / 5;
    print(
      'combinePatterns: $combine  ${kb.toStringAsFixed(0)} KB: cold ${cold}ms, '
      'warm ${warm.toStringAsFixed(1)}ms '
      '(${(kb / 1024 / (warm / 1000)).toStringAsFixed(2)} MB/s)',
    );
  }
}
