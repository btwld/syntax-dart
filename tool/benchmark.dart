import 'dart:convert';
import 'dart:io';
import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';

// Run from the workspace: flutter pub run tool/benchmark.dart
void main() {
  final timings = <String, Object?>{
    'sdk': Platform.version.split('\n').first,
    'os': Platform.operatingSystem,
  };
  T measure<T>(String name, T Function() operation) {
    final watch = Stopwatch()..start();
    final result = operation();
    timings[name] = watch.elapsedMicroseconds / 1000;
    return result;
  }

  final text = List.generate(100000, (i) => 'final value$i = $i;').join('\n');
  final document = measure(
    'documentAndIndexMs',
    () => TextDocument(text)..lineStart(99999),
  );
  final highlighter = Highlighter(languages: [dartLanguage]);
  final live = measure(
    'initialViewportMs',
    () =>
        LiveHighlighter(
            document,
            highlighter.grammar('dart'),
            priorityEndLine: 80,
          )
          ..pause()
          ..flush(endLine: 80),
  );
  measure('reachLastViewportMs', () => live.flush());
  final last = live.line(99999);
  measure('editAndIncrementalHighlightMs', () {
    document.applyOffsetEdits([const OffsetEdit(15, 16, '9')]);
    live.flush();
  });
  if (!identical(last, live.line(99999)))
    throw StateError('Untouched line identity changed');
  final largeDiff = diffTexts(
    text,
    '${text.substring(0, 15)}9${text.substring(16)}',
    id: 'large',
    path: 'large.dart',
    contextLines: 3,
  );
  final expanded = measure(
    'index100000RowsMs',
    () => DiffLayout([largeDiff], expandAll: true),
  );
  if (expanded.blockCount > 16)
    throw StateError('Expanded rows allocated eagerly');
  final files = measure(
    'compute1000FilePatchMs',
    () => [
      for (var i = 0; i < 1000; i++)
        diffTexts('old $i\n', 'new $i\n', id: '$i', path: '$i.dart'),
    ],
  );
  final layout = measure('index1000FilesMs', () => DiffLayout(files));
  measure('lookup1000SourceLinesMs', () {
    for (var i = 0; i < files.length; i++) {
      if (layout.rowForLine(i, 1) == null) throw StateError('Missing row');
    }
  });
  final cache = DiffHighlightCache(
    highlighter: highlighter,
    theme: githubDarkTheme,
    capacity: 8,
  );
  measure('highlight1000FilesMs', () {
    for (final file in files) {
      cache.highlighted(file).tokensFor(file.hunks.single.lines.last);
    }
  });
  if (cache.cachedFileCount > 8) throw StateError('Cache exceeded capacity');
  timings.addAll({
    'expandedRows': expanded.length,
    'expandedBlocks': expanded.blockCount,
    'patchRows': layout.length,
    'cachedFiles': cache.cachedFileCount,
    'unchangedLineReused': identical(last, live.line(99999)),
    'residentMemoryMiB': ProcessInfo.currentRss / 1048576,
  });
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(timings));
  live.dispose();
  document.dispose();
}
