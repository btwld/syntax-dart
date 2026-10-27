// Time-budget tests for HighlightedDiff. They read no fixtures, so CI runs
// them in Chrome too, on the browser's RegExp engine and clock.
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/syntax.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:test/test.dart';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);

  group('HighlightedDiff with a budget', () {
    test('with a budget, lines get their colors a slice at a time', () {
      final before = [for (var i = 0; i < 40; i++) 'final v$i = $i;'];
      final after = [...before]..[30] = 'final v30 = 3000;';
      final diff = diffTexts(
        before.join('\n'),
        after.join('\n'),
        path: 'a.dart',
      );
      final full = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      final sliced = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
        budget: Duration.zero,
      );
      expect(sliced.isComplete, isFalse);
      final lines = diff.hunks.single.lines;
      final added = lines.firstWhere((l) => l.kind == DiffLineKind.added);
      // Not tokenized yet: plain, but the changed word is still marked.
      expect(sliced.tokensFor(added), isEmpty);
      final segments = sliced.segmentsFor(added, WordChanges.of(diff));
      expect(segments.map((s) => s.text).join(), added.text);
      expect(segments.where((s) => s.changed).map((s) => s.text), ['3000']);

      var done = false;
      while (!done) {
        done = sliced.tokenize(budget: Duration.zero);
      }
      // Numbers outside the file have no tokens, as in the other paths.
      expect(sliced.oldLine(0), isEmpty);
      expect(sliced.newLine(-1), isEmpty);
      expect(sliced.newLine(41), isEmpty);
      for (final line in lines) {
        expect(
          [for (final t in sliced.tokensFor(line)) (t.text, t.style)],
          [for (final t in full.tokensFor(line)) (t.text, t.style)],
        );
      }
    });

    test('the cache finishes files in the order they were asked for', () {
      final cache = DiffHighlightCache(
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      FileDiff file(String path) => diffTexts(
        [for (var i = 0; i < 20; i++) 'var a$i = $i;'].join('\n'),
        [for (var i = 0; i < 20; i++) 'var b$i = $i;'].join('\n'),
        path: path,
      );
      final first = file('a.dart');
      final second = file('b.dart');
      final a = cache.highlighted(first, budget: Duration.zero);
      final b = cache.highlighted(second, budget: Duration.zero);
      expect([a.isComplete, b.isComplete], [false, false]);
      expect(cache.tokenize(budget: Duration.zero), isFalse);
      var done = false;
      while (!a.isComplete) {
        done = cache.tokenize(budget: Duration.zero);
        expect(b.isComplete, isFalse);
      }
      expect(done, isFalse);
      expect(cache.tokenize(), isTrue);
      expect(b.isComplete, isTrue);
      // Asking without a budget finishes a file at once.
      final third = file('c.dart');
      final c = cache.highlighted(third, budget: Duration.zero);
      expect(c.isComplete, isFalse);
      expect(cache.highlighted(third), same(c));
      expect(c.isComplete, isTrue);
    });

    group('a parsed patch with a budget', () {
      // Two hunks; every line has text, so a tokenized line has tokens.
      final diff = parsePatch('''
--- a/a.dart
+++ b/a.dart
@@ -1,6 +1,6 @@
 /*
  still comment
-  old comment line
+  new comment line
  */
 final a = 1;
-final b = 2;
+var b = 2;
@@ -20,3 +20,4 @@
 /* opened in this hunk
-final c = 3;
+var c = 3;
+var d = 4;
''').single;
      List<DiffLine> side({required bool old}) => [
        for (final hunk in diff.hunks)
          for (final line in hunk.lines)
            if (old
                ? line.kind != DiffLineKind.added
                : line.kind != DiffLineKind.removed)
              line,
      ];
      List<ThemedToken> tokens(
        HighlightedDiff highlighted,
        DiffLine line, {
        required bool old,
      }) => old
          ? highlighted.oldLine(line.oldNumber!)
          : highlighted.newLine(line.newNumber!);
      int tokenized(HighlightedDiff highlighted, {required bool old}) => side(
        old: old,
      ).where((l) => tokens(highlighted, l, old: old).isNotEmpty).length;
      List<(String, TokenStyle)> describe(List<ThemedToken> tokens) => [
        for (final t in tokens) (t.text, t.style),
      ];

      final full = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
      );

      test('without one, is complete at once', () {
        expect(full.isComplete, isTrue);
        expect(tokenized(full, old: false), side(old: false).length);
        expect(tokenized(full, old: true), side(old: true).length);
      });

      test('gets its colors a line per zero-budget call, the new side '
          'first, and ends with the unbudgeted tokens', () {
        final sliced = HighlightedDiff.of(
          diff,
          highlighter: highlighter,
          theme: githubDarkTheme,
          budget: Duration.zero,
        );
        // As with full texts, the first call starts each side.
        expect(sliced.isComplete, isFalse);
        expect(tokenized(sliced, old: false), 1);
        expect(tokenized(sliced, old: true), 1);

        final newCount = side(old: false).length;
        var before = 2;
        var done = false;
        while (!done) {
          done = sliced.tokenize(budget: Duration.zero);
          final newDone = tokenized(sliced, old: false);
          final oldDone = tokenized(sliced, old: true);
          // One line per call, or one of each side in the call that
          // finishes the new side, which goes first.
          final progress = newDone + oldDone - before;
          expect(progress, newDone == newCount ? inInclusiveRange(1, 2) : 1);
          if (newDone < newCount) expect(oldDone, 1);
          before += progress;
        }
        expect(sliced.isComplete, isTrue);
        for (final old in [false, true]) {
          for (final line in side(old: old)) {
            expect(
              describe(tokens(sliced, line, old: old)),
              describe(tokens(full, line, old: old)),
            );
          }
        }
      });

      test('keeps a block comment open across slices within a hunk, and '
          'starts each hunk afresh', () {
        final sliced = HighlightedDiff.of(
          diff,
          highlighter: highlighter,
          theme: githubDarkTheme,
          budget: Duration.zero,
        );
        while (!sliced.tokenize(budget: Duration.zero)) {}
        bool inComment(List<ThemedToken> tokens) =>
            tokens.any((t) => t.scopes.scopes.contains('comment.block.dart'));
        // Inside the first hunk's comment, on both sides.
        expect(inComment(sliced.newLine(3)), isTrue);
        expect(inComment(sliced.oldLine(3)), isTrue);
        // The second hunk starts from a fresh state: its first line opens
        // a comment that runs to the end of the hunk.
        expect(inComment(sliced.newLine(20)), isTrue);
        expect(inComment(sliced.newLine(22)), isTrue);
        // The first hunk's last line is code again.
        expect(inComment(sliced.newLine(6)), isFalse);
      });

      test('leaves lines not tokenized yet plain, as full texts do', () {
        final sliced = HighlightedDiff.of(
          diff,
          highlighter: highlighter,
          theme: githubDarkTheme,
          budget: Duration.zero,
        );
        final added = diff.hunks.last.lines.last;
        expect(sliced.tokensFor(added), isEmpty);
        final segments = sliced.segmentsFor(added, WordChanges.of(diff));
        expect(segments.map((s) => s.text).join(), added.text);
      });

      test('bounds the work of each call on a large parsed diff', () {
        const count = 2000;
        final large = FileDiff(
          oldPath: null,
          newPath: 'large.dart',
          kind: FileDiffKind.added,
          hunks: [
            DiffHunk(
              oldStart: 0,
              oldCount: 0,
              newStart: 1,
              newCount: count,
              lines: [
                for (var i = 0; i < count; i++)
                  DiffLine(
                    DiffLineKind.added,
                    'final value$i = "example $i";',
                    newNumber: i + 1,
                  ),
              ],
            ),
          ],
        );
        int done(HighlightedDiff h) => [
          for (var n = 1; n <= count; n++) h.newLine(n),
        ].where((t) => t.isNotEmpty).length;
        final sliced = HighlightedDiff.of(
          large,
          highlighter: highlighter,
          theme: githubDarkTheme,
          budget: Duration.zero,
        );
        expect(sliced.isComplete, isFalse);
        expect(done(sliced), 1);
        for (var call = 2; call <= 4; call++) {
          expect(sliced.tokenize(budget: Duration.zero), isFalse);
          expect(done(sliced), call);
        }
        // A null budget finishes the rest synchronously.
        expect(sliced.tokenize(), isTrue);
        expect(done(sliced), count);
      });

      test('the cache slices parsed files and finishes them without a '
          'budget', () {
        final cache = DiffHighlightCache(
          highlighter: highlighter,
          theme: githubDarkTheme,
        );
        final highlighted = cache.highlighted(diff, budget: Duration.zero);
        expect(highlighted.isComplete, isFalse);
        expect(cache.tokenize(budget: Duration.zero), isFalse);
        expect(cache.highlighted(diff), same(highlighted));
        expect(highlighted.isComplete, isTrue);
      });
    });

    test('starts each hunk of a parsed patch from a fresh state, with or '
        'without a budget', () {
      // The first hunk ends inside a block comment it never closes; the
      // second hunk's first line is code.
      final diff = parsePatch('''
--- a/a.dart
+++ b/a.dart
@@ -1,2 +1,2 @@
 final a = 1;
-/* left open, old
+/* left open, new
@@ -40,2 +40,2 @@
 final code = 2;
-final b = 3;
+var b = 3;
''').single;
      final grammar = highlighter.grammar(dartLanguage.scopeName);
      // Each hunk tokenized on its own, from a fresh state.
      Map<int, List<(String, TokenStyle)>> reference({required bool old}) {
        final out = <int, List<(String, TokenStyle)>>{};
        for (final hunk in diff.hunks) {
          StateStack? state;
          for (final line in hunk.lines) {
            final number = old ? line.oldNumber : line.newNumber;
            final onSide = old
                ? line.kind != DiffLineKind.added
                : line.kind != DiffLineKind.removed;
            if (!onSide || number == null) continue;
            final tokens = grammar.tokenizeLine(line.text, state);
            state = tokens.endState;
            out[number] = [
              for (final t in themeTokens(
                line.text,
                tokens.tokens,
                githubDarkTheme,
              ))
                (t.text, t.style),
            ];
          }
        }
        return out;
      }

      bool comment(List<ThemedToken> tokens) =>
          tokens.any((t) => t.scopes.scopes.contains('comment.block.dart'));
      final sliced = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
        budget: Duration.zero,
      );
      while (!sliced.tokenize(budget: Duration.zero)) {}
      final whole = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      for (final highlighted in [sliced, whole]) {
        // The second hunk's first line is code on both sides, not the
        // comment the first hunk left open.
        expect(comment(highlighted.newLine(40)), isFalse);
        expect(comment(highlighted.oldLine(40)), isFalse);
        expect(comment(highlighted.newLine(2)), isTrue);
        expect(comment(highlighted.oldLine(2)), isTrue);
        for (final old in [false, true]) {
          final expected = reference(old: old);
          expect(expected, isNotEmpty);
          for (final MapEntry(key: number, value: tokens) in expected.entries) {
            final actual = old
                ? highlighted.oldLine(number)
                : highlighted.newLine(number);
            expect(
              [for (final t in actual) (t.text, t.style)],
              tokens,
              reason: '${old ? 'old' : 'new'} line $number',
            );
          }
        }
      }
    });
  });
}
