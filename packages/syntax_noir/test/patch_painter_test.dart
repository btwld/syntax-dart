import 'package:noir/noir.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_noir/syntax_noir.dart';
import 'package:test/test.dart';

final highlighter = syntax.Highlighter(languages: [dartLanguage]);

const patch = '''
diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,3 @@ class A {
 class A {
-  int count = 0;
+  int total = 0;
 }
diff --git a/old.txt b/new.txt
similarity index 100%
rename from old.txt
rename to new.txt
''';

PatchPainter painterFor(
  List<syntax.FileDiff> files, {
  syntax.Highlighter? using,
  syntax.SyntaxTheme theme = githubDarkTheme,
  syntax.DiffLabels labels = const syntax.DiffLabels(),
}) => PatchPainter(
  files: files,
  highlights: syntax.DiffHighlightCache(
    highlighter: using ?? highlighter,
    theme: theme,
  ),
  labels: labels,
);

/// The painted text of every row.
List<String> paintAll(
  List<syntax.FileDiff> files, {
  syntax.DiffMode mode = syntax.DiffMode.unified,
  int width = 60,
  Set<syntax.DiffGapId> expanded = const {},
}) {
  final painter = painterFor(files);
  return [
    for (final row in syntax.layoutDiff(files, mode: mode, expanded: expanded))
      painter.paint(row, width: width).toPlainText(),
  ];
}

/// The spans of a painted row.
List<TextSpan> spansOf(TextSpan line) => line.children.cast<TextSpan>();

void main() {
  final files = syntax.parsePatch(patch);

  test('every row fills exactly the width, unified and split', () {
    final before = [for (var i = 1; i <= 30; i++) 'final v$i = $i;'];
    final after = [...before]..[14] = 'final v15 = 1500; // a much longer line';
    final texts = syntax.diffTexts(before.join('\n'), after.join('\n'));
    final all = {
      for (var h = 0; h <= texts.hunks.length; h++) (file: 0, hunk: h),
    };
    for (final width in [20, 41, 80]) {
      for (final mode in syntax.DiffMode.values) {
        for (final source in [
          files,
          [texts],
        ]) {
          for (final line in paintAll(
            source,
            mode: mode,
            width: width,
            expanded: all,
          )) {
            expect(terminalStringWidth(line), width, reason: '$mode: $line');
          }
        }
      }
    }
  });

  test('headers, hunks and lines read like a diff', () {
    final lines = paintAll(files).map((l) => l.trimRight()).toList();
    expect(lines, [
      ' ▾ lib/a.dart  +1 −1 ■■■■■',
      ' @@ -1,3 +1,3 @@ class A {',
      ' 1 1   class A {',
      ' 2   −   int count = 0;',
      '   2 +   int total = 0;',
      ' 3 3   }',
      ' ▾ Renamed old.txt → new.txt  +0 −0 ■■■■■',
      ' File renamed without changes',
    ]);
  });

  test('split rows keep the divider in one column', () {
    final lines = paintAll(files, mode: syntax.DiffMode.split, width: 41);
    final pairs = [
      for (final l in lines)
        if (l.contains('│')) l,
    ];
    expect(pairs, isNotEmpty);
    final column = terminalStringWidth(pairs.first.split('│').first);
    for (final l in pairs) {
      expect(terminalStringWidth(l.split('│').first), column);
    }
    expect(pairs.firstWhere((l) => l.contains('count')), contains('total'));
  });

  test('changed words replace a token background', () {
    // A theme that gives every Dart token a background.
    final shaded = syntax.SyntaxTheme.fromJson({
      'type': 'dark',
      'colors': {
        'editor.background': '#000000',
        'editor.foreground': '#ffffff',
      },
      'tokenColors': [
        {
          'scope': 'source.dart',
          'settings': {'background': '#202020'},
        },
      ],
    });
    final painter = painterFor(files, theme: shaded);
    final added = syntax
        .layoutDiff(files)
        .whereType<syntax.DiffLineRow>()
        .firstWhere((r) => r.line.kind == syntax.DiffLineKind.added);
    final spans = spansOf(painter.paint(added, width: 60));
    final colors = syntax.DiffColors.of(shaded);
    final line = syntax.alphaBlend(colors.insertedLine, shaded.background);
    expect(
      spans.firstWhere((s) => s.text == 'total').style!.backgroundColor,
      noirColor(syntax.alphaBlend(colors.insertedText, line)),
    );
    // Unchanged words keep the token's own background.
    expect(
      spans
          .firstWhere((s) => s.text?.contains('int') ?? false)
          .style!
          .backgroundColor,
      noirColor(0xFF202020),
    );
  });

  test('a language added later is used on the next paint', () {
    final late = syntax.Highlighter();
    final painter = painterFor(files, using: late);
    final row = syntax.layoutDiff(files)[2];
    Color? colorOf(String word) => spansOf(
      painter.paint(row, width: 60),
    ).firstWhere((s) => s.text?.contains(word) ?? false).style!.color;
    final plain = colorOf('class');
    late.addLanguage(dartLanguage);
    expect(colorOf('class'), isNot(plain));
  });

  test('a selected row is marked', () {
    final row = syntax.layoutDiff(files)[2];
    expect(
      painterFor(files).paint(row, width: 30, selected: true).toPlainText(),
      startsWith('▌'),
    );
  });

  test('nothing shows past a wide character that is cut', () {
    // The gutter and marker take 7 cells, `x ` 2 more, leaving one cell
    // that `漢` doesn't fit. The changed `z` after it must not appear.
    final diff = syntax.diffTexts('x 漢 y\n', 'x 漢 z\n');
    final added = syntax
        .layoutDiff([diff])
        .whereType<syntax.DiffLineRow>()
        .firstWhere((r) => r.line.kind == syntax.DiffLineKind.added);
    final text = painterFor([diff]).paint(added, width: 10).toPlainText();
    expect(terminalStringWidth(text), 10);
    expect(text, endsWith('x  '));
    expect(text, isNot(contains('z')));
  });

  test('control characters never reach the terminal', () {
    final diff = syntax.diffTexts('a\n', 'b\x1b[31mred\x07\n');
    final text = paintAll([diff]).join('\n');
    expect(text, isNot(contains('\x1b')));
    expect(text, isNot(contains('\x07')));
    expect(text, contains('b\uFFFD[31mred\uFFFD'));
  });

  test('labels, empty state and a missing final newline', () {
    final spanish = painterFor(files, labels: const _Spanish());
    final gaps = syntax.diffTexts(
      [for (var i = 0; i < 12; i++) 'l$i'].join('\n'),
      [for (var i = 0; i < 12; i++) i == 8 ? 'L$i' : 'l$i'].join('\n'),
    );
    final gap = syntax.layoutDiff([gaps]).whereType<syntax.DiffGapRow>().first;
    expect(
      painterFor([gaps]).paint(gap, width: 40).toPlainText(),
      contains('Show 5 unchanged lines'),
    );
    expect(
      spanish.paint(syntax.layoutDiff(files).last, width: 40).toPlainText(),
      contains('Renombrado sin cambios'),
    );
    expect(spanish.empty(width: 20).toPlainText().trim(), 'Sin cambios');
    final noNewline = syntax.diffTexts('a\n', 'b');
    expect(paintAll([noNewline]).last, contains('b ⊘'));
  });
}

final class _Spanish extends syntax.DiffLabels {
  const _Spanish();

  @override
  String get noFiles => 'Sin cambios';

  @override
  String notice(syntax.DiffNotice notice) =>
      notice == syntax.DiffNotice.renamedWithoutChanges
      ? 'Renombrado sin cambios'
      : super.notice(notice);
}
