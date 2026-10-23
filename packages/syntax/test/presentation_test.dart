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
