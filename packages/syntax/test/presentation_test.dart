import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:test/test.dart';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);

  test('distinguishes transport CRLF from source CRLF and git headers', () {
    const lfPatch =
        'diff --git a/f b/f\nindex abc123..def456 100644\n--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n-one\r\n+one\n two\r\n';
    final lfParsed = parsePatch(lfPatch).single;
    expect(lfParsed.patchLineEnding, '\n');
    expect(lfParsed.oldObjectId, 'abc123');
    expect(lfParsed.newObjectId, 'def456');
    expect(lfParsed.oldMode, '100644');
    expect(lfParsed.newMode, '100644');
    expect(
      lfParsed.hunks.single.lines.map((l) => (l.text, l.sourceLineEnding)),
      [('one', '\r\n'), ('one', '\n'), ('two', '\r\n')],
    );

    final crlfPatch = lfPatch.replaceAll('\n', '\r\n');
    final crlfParsed = parsePatch(crlfPatch).single;
    expect(crlfParsed.patchLineEnding, '\r\n');
    expect(
      crlfParsed.hunks.single.lines.map((l) => (l.text, l.sourceLineEnding)),
      [('one', '\r\n'), ('one', '\n'), ('two', '\r\n')],
    );

    final bareModes = parsePatch(
      'diff --git a/add b/add\nnew file mode\n--- /dev/null\n+++ b/add\n@@ -0,0 +1 @@\n+a\n'
      'diff --git a/del b/del\ndeleted file mode\n--- a/del\n+++ /dev/null\n@@ -1 +0,0 @@\n-a\n',
    );
    expect(bareModes.map((f) => (f.kind, f.oldMode, f.newMode)), [
      (FileDiffKind.added, null, null),
      (FileDiffKind.deleted, null, null),
    ]);
  });

  test('splits lone CR lines, preserves metadata and compares endings', () {
    final diff = diffTexts(
      'a\rb\r',
      'a\rB\r',
      path: 'a.dart',
      id: 'custom-id',
      revision: 7,
      language: 'dart',
    );
    expect(diff.id, 'custom-id');
    expect(diff.revision, 7);
    expect(diff.language, 'dart');
    expect(diff.oldLines, ['a', 'b']);
    expect(diff.newLines, ['a', 'B']);
    expect(diff.hunks.single.lines.map((l) => ('$l', l.sourceLineEnding)), [
      (' a', '\r'),
      ('-b', '\r'),
      ('+B', '\r'),
    ]);
    expect(
      const DiffLine(
        DiffLineKind.added,
        'x',
        newNumber: 1,
        sourceLineEnding: '\r\n',
      ),
      isNot(const DiffLine(DiffLineKind.added, 'x', newNumber: 1)),
    );
  });

  test('supports inline diff modes and skips lines over 10k characters', () {
    FileDiff edit(String a, String b) => diffTexts('$a\n', '$b\n');
    final diff = edit('final a b = compute(1);', 'final x y = compute(1);');
    final added = diff.hunks.single.lines.last;
    expect(WordChanges.of(diff, mode: InlineDiffMode.word).rangesFor(added), [
      (start: 6, end: 7),
      (start: 8, end: 9),
    ]);
    expect(
      WordChanges.of(diff, mode: InlineDiffMode.changedSpan).rangesFor(added),
      [(start: 6, end: 9)],
    );
    expect(
      WordChanges.of(diff, mode: InlineDiffMode.character).rangesFor(added),
      [(start: 6, end: 7), (start: 8, end: 9)],
    );
    expect(
      WordChanges.of(diff, mode: InlineDiffMode.none).rangesFor(added),
      isEmpty,
    );

    final prefix = 'a' * 10000;
    final overLimit = edit('${prefix}x', '${prefix}y');
    expect(
      WordChanges.of(overLimit).rangesFor(overLimit.hunks.single.lines.last),
      isEmpty,
    );
  });

  test('DiffLayout indexes rows, files, lines and folded hunks', () {
    final file = diffTexts(
      'a\nb\nc\nd\ne\nf\ng\nh\n',
      'a\nB\nc\nd\ne\nf\nG\nh\n',
      path: 'a.dart',
      contextLines: 1,
    );
    final layout = DiffLayout(
      [file],
      expansions: const {(file: 0, hunk: 1): (before: 1, after: 0)},
      collapsedHunks: const {(file: 0, hunk: 1)},
    );
    expect(layout.rowForFile(0), 0);
    expect(layout.rowForLine(0, 2), isNotNull);
    expect(layout.rowForLine(0, 4), isNotNull);
    expect(layout.rowForLine(0, 7), isNull);
    expect(layout.whereType<DiffHunkHeaderRow>().last.collapsed, isTrue);

    final heights = RowHeightIndex(5, estimatedHeight: 20);
    expect(heights.offsetFor(3), 60);
    expect(heights.measure(1, 50), 30);
    expect(heights.offsetFor(3), 90);
    expect(heights.rowAt(65), 1);
    expect(heights.rowAt(70), 2);
  });

  test('renderDiffHtml renders unified and split diffs and escapes HTML', () {
    final file = diffTexts(
      'final oldName = "<script>";\n',
      'final newName = "<script>";\n',
      path: '<x>.dart',
      id: 'a"',
    );
    final unified = renderDiffHtml(
      [file],
      highlighter: highlighter,
      themes: {'light': githubLightTheme, 'dark': githubDarkTheme},
      decorateLine: (_, _) => const HtmlDecoration(
        className: 'custom"',
        title: '"><script>',
        before: '<b>',
        after: '</b>',
      ),
    );
    expect(unified, contains('--syntax-background:'));
    expect(unified, contains('data-theme="light"'));
    expect(unified, contains('data-file="a&quot;"'));
    expect(unified, contains('&lt;x&gt;.dart'));
    expect(unified, isNot(contains('<script>')));
    expect(unified, contains('&lt;b&gt;'));
    expect(unified, contains('&lt;/b&gt;'));
    expect(unified, contains('changed'));

    final split = renderDiffHtml(
      [file],
      highlighter: highlighter,
      themes: {'dark': githubDarkTheme},
      mode: DiffMode.split,
      inlineDiffMode: InlineDiffMode.character,
      wrap: true,
    );
    expect(split, contains('class="removed '));
    expect(split, contains('class="added '));
    expect(split, contains('white-space:pre-wrap'));
  });

  test(
    'renderDiffHtml splits tokens where any theme changes style and scopes fragments',
    () {
      // Theme A colors only keywords (`final`); Theme B colors only numbers (`1`).
      // In Theme A, ` x = 1;` is merged into one token; in Theme B, `final x = `
      // is merged into one token and `1` is separate.
      final themeA = SyntaxTheme.fromJson({
        'type': 'dark',
        'colors': {
          'editor.foreground': '#aaaaaa',
          'editor.background': '#000000',
        },
        'tokenColors': [
          {
            'scope': 'storage',
            'settings': {'foreground': '#ff0000'},
          },
        ],
      });
      final themeB = SyntaxTheme.fromJson({
        'type': 'dark',
        'colors': {
          'editor.foreground': '#aaaaaa',
          'editor.background': '#000000',
        },
        'tokenColors': [
          {
            'scope': 'constant.numeric',
            'settings': {'foreground': '#00ff00'},
          },
        ],
      });
      final file1 = diffTexts('', 'final x = 1;\n', path: 'a.dart');
      final html1 = renderDiffHtml(
        [file1],
        highlighter: highlighter,
        themes: {'a': themeA, 'b': themeB},
      );
      expect(html1, contains('>final</span>'));
      expect(html1, contains('>1</span>'));
      expect(html1, contains('color:#ff0000'));
      expect(html1, contains('color:#00ff00'));

      final file2 = diffTexts('', '123;\n', path: 'b.dart');
      final html2 = renderDiffHtml(
        [file2],
        highlighter: highlighter,
        themes: {'a': themeA, 'b': themeB},
      );
      final scopePattern = RegExp(r'data-scope="(f[0-9a-f]{8})"');
      final scope1 = scopePattern.firstMatch(html1)!.group(1)!;
      final scope2 = scopePattern.firstMatch(html2)!.group(1)!;
      expect(scope1, isNot(scope2));
      expect(
        html1,
        contains('.syntax-code[data-scope="$scope1"][data-theme="a"] .s0{'),
      );
      expect(
        html2,
        contains('.syntax-code[data-scope="$scope2"][data-theme="a"] .s0{'),
      );
    },
  );

  test('renderDiffHtml validates palette keys', () {
    final file = diffTexts('a\n', 'b\n', path: 'a.dart');
    expect(
      () => renderDiffHtml([file], highlighter: highlighter, themes: const {}),
      throwsArgumentError,
    );
    expect(
      () => renderDiffHtml(
        [file],
        highlighter: highlighter,
        themes: {'bad key': githubDarkTheme},
      ),
      throwsArgumentError,
    );
  });
}
