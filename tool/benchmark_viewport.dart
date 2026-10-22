import 'dart:convert';
import 'dart:io';
import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';

// Run from the workspace: flutter pub run tool/benchmark_viewport.dart
Future<void> main() async {
  final file = SourceFile(
    id: 'viewport-benchmark',
    path: 'events.dart',
    text: List.generate(
      100000,
      (i) => 'final event$i = Event(id: $i, status: "ready");',
    ).join('\n'),
  );
  final executor = CooperativeHighlightExecutor();
  final measurements = <String, Object?>{
    'sdk': Platform.version.split('\n').first,
  };
  Future<void> measure(String name, int start, int end) async {
    final before = executor.stats.tokenizedLines;
    final watch = Stopwatch()..start();
    final result = await executor.highlight(
      HighlightRequest(
        file: file,
        languages: [dartLanguage],
        theme: githubDarkTheme,
        startLine: start,
        endLine: end,
      ),
    );
    measurements[name] = {
      'ms': watch.elapsedMicroseconds / 1000,
      'newlyTokenizedLines': executor.stats.tokenizedLines - before,
      'returnedLines': result.lines.length,
    };
    if (result.startLine != start || result.lines.length != end - start) {
      throw StateError('Incorrect viewport');
    }
  }

  await measure('initialViewport', 0, 80);
  await measure('coldDistantViewport', 90000, 90080);
  await measure('adjacentViewport', 90020, 90100);
  await measure('revisitViewport', 90000, 90080);
  measurements['cachedTokenLines'] = executor.stats.cachedLines;
  measurements['grammarCheckpoints'] = executor.stats.checkpoints;
  if (executor.stats.cachedLines > 512 || executor.stats.checkpoints > 2048) {
    throw StateError('Cache exceeded its bounds');
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(measurements));
  executor.dispose();
}
