import 'package:syntax/langs/all.dart';
import 'package:syntax/src/regex/onig_translator.dart';
import 'package:test/test.dart';

void main() {
  // The conformance samples only reach some rules. This checks that every
  // regex in every bundled grammar translates and compiles, in every
  // variant the engine can build.
  for (final MapEntry(key: name, value: language) in bundledLanguages.entries) {
    test('$name: every pattern compiles', () {
      final failures = <String>[];
      void visit(Object? node) {
        if (node is Map) {
          for (final MapEntry(:key, :value) in node.entries) {
            if (value is String &&
                const {'match', 'begin', 'end', 'while'}.contains(key)) {
              // End and while patterns get begin captures substituted in.
              final source = key == 'end' || key == 'while'
                  ? value.replaceAll(RegExp(r'\\(\d+)'), 'x')
                  : value;
              try {
                final t = translateOnigPattern(source);
                for (final unicode in [false, true]) {
                  for (final src in [
                    t.searchSource(unicodeWords: unicode),
                    t.indexedSource(unicodeWords: unicode),
                  ]) {
                    RegExp(
                      src
                          .replaceAll(gMarker, '')
                          .replaceAll(aMarker, '')
                          .replaceAll(keepMarker, ''),
                      multiLine: true,
                      unicode: true,
                      caseSensitive: !t.caseInsensitive,
                    );
                  }
                }
              } on Object catch (e) {
                failures.add('$e');
              }
            } else {
              visit(value);
            }
          }
        } else if (node is List) {
          node.forEach(visit);
        }
      }

      visit(language.grammar);
      expect(failures, isEmpty);
    });
  }
}
