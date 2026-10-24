// Translates and compiles every regex in every grammar JSON in a directory
// and lists the ones the Dart engine cannot run. Usage:
//   dart run tool/coverage.dart ../../tool/node_modules/tm-grammars/grammars
import 'dart:convert';
import 'dart:io';

import 'package:syntax_darts/src/regex/onig_translator.dart';

void main(List<String> args) {
  final dir = Directory(args.single);
  var total = 0;
  final reasons = <String, int>{};
  final perLang = <String, int>{};
  for (final file in dir.listSync().whereType<File>().where(
    (f) => f.path.endsWith('.json'),
  )) {
    final lang = file.uri.pathSegments.last.replaceAll('.json', '');
    void visit(Object? node) {
      if (node is Map) {
        for (final e in node.entries) {
          if (const {'match', 'begin', 'end', 'while'}.contains(e.key) &&
              e.value is String) {
            total++;
            var src = e.value as String;
            if (e.key == 'end' || e.key == 'while') {
              src = src.replaceAll(RegExp(r'\\(\d+)'), 'x');
            }
            try {
              final t = translateOnigPattern(src);
              for (final s in [
                t.searchSource(),
                t.indexedSource(),
                t.searchSource(unicodeWords: true),
                t.indexedSource(unicodeWords: true),
              ]) {
                RegExp(
                  s.replaceAll(gMarker, '').replaceAll(aMarker, ''),
                  multiLine: true,
                  unicode: true,
                  caseSensitive: !t.caseInsensitive,
                );
              }
            } on UnsupportedPatternException catch (err) {
              reasons.update(err.reason, (v) => v + 1, ifAbsent: () => 1);
              perLang.update(lang, (v) => v + 1, ifAbsent: () => 1);
            } on FormatException catch (err) {
              final key = 'FormatException: ${err.message}';
              reasons.update(key, (v) => v + 1, ifAbsent: () => 1);
              perLang.update(lang, (v) => v + 1, ifAbsent: () => 1);
              if ((reasons[key] ?? 0) <= 2) {
                stderr.writeln('[$lang] $key\n   $src');
              }
            }
          } else {
            visit(e.value);
          }
        }
      } else if (node is List) {
        node.forEach(visit);
      }
    }

    visit(jsonDecode(file.readAsStringSync()));
  }
  final failed = reasons.values.fold(0, (a, b) => a + b);
  print(
    '$total patterns in ${dir.listSync().length} grammars; $failed failed '
    '(${(100 * (total - failed) / total).toStringAsFixed(2)}% ok)',
  );
  print('By reason: $reasons');
  print('By grammar: $perLang');
}
