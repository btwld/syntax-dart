import 'dart:io';
import 'dart:math';

import 'package:syntax/langs/dart.dart';
import 'package:syntax/langs/diff.dart';
import 'package:syntax/langs/html.dart';
import 'package:syntax/langs/markdown.dart';
import 'package:syntax/langs/shellscript.dart';
import 'package:syntax/langs/xml.dart';
import 'package:syntax/langs/yaml.dart';
import 'package:syntax/src/diff/myers.dart';
import 'package:syntax/syntax.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/light_plus.dart';
import 'package:test/test.dart';

String fixture(String name) =>
    File('test/fixtures/diff/$name').readAsStringSync();

/// A hunk as git prints it, for comparing diffs from different sources.
String render(DiffHunk hunk) =>
    [hunk.header, ...hunk.lines.map((l) => '$l')].join('\n');

void main() {
  group('parsePatch', () {
    // Produced by `git diff --cached -M` in a scratch repository.
    final files = parsePatch(fixture('multi.patch'));
    FileDiff file(String path) => files.firstWhere((f) => f.path == path);

    test('reads every file and its kind', () {
      expect(
        [for (final f in files) (f.path, f.kind)],
        [
          ('added.md', FileDiffKind.added),
          ('gone.sh', FileDiffKind.deleted),
          ('lib.dart', FileDiffKind.modified),
          ('logo.png', FileDiffKind.modified),
          ('new_name.yaml', FileDiffKind.renamed),
          ('noeol.txt', FileDiffKind.modified),
        ],
      );
      expect(file('added.md').oldPath, isNull);
      expect(file('gone.sh').newPath, isNull);
      expect(file('new_name.yaml').oldPath, 'old_name.yaml');
    });

    test('binary files and pure renames have no hunks', () {
      expect(file('logo.png').isBinary, isTrue);
      expect(file('logo.png').hunks, isEmpty);
      expect(file('new_name.yaml').hunks, isEmpty);
    });

    test('hunks keep line numbers, sections and counts', () {
      final lib = file('lib.dart');
      expect(lib.hunks.map((h) => h.header), [
        '@@ -1,13 +1,14 @@',
        '@@ -32,7 +33,6 @@ class Counter {',
      ]);
      expect((lib.additions, lib.deletions), (2, 2));
      final changed = lib.hunks.first.lines.firstWhere(
        (l) => l.kind == DiffLineKind.added,
      );
      expect((changed.text, changed.newNumber), ('  line 03 total = 3;', 4));
    });

    test('marks a missing final newline', () {
      final lines = file('noeol.txt').hunks.single.lines;
      expect(lines.where((l) => l.noNewlineAtEnd).map((l) => '$l'), ['+c']);
    });

    test('handles plain diff -u output and a leading commit message', () {
      final parsed = parsePatch('''
commit message line

--- a/one.txt\t2026-10-19 10:00:00.000000000 +0000
+++ b/one.txt\t2026-10-19 10:01:00.000000000 +0000
@@ -1 +1 @@
-old
+new
--- "a/two words.txt"
+++ "b/two words.txt"
@@ -1,2 +1,2 @@
 same
-x
+y
''');
      expect(parsed.map((f) => f.path), ['one.txt', 'two words.txt']);
      expect(parsed.first.hunks.single.header, '@@ -1 +1 @@');
      expect(render(parsed.last.hunks.single), '''
@@ -1,2 +1,2 @@
 same
-x
+y''');
    });

    group('edge cases from git', () {
      // `git diff --cached -M -C --find-copies-harder` in a scratch repo.
      final edge = parsePatch(fixture('edge.patch'));
      FileDiff edgeFile(String path) => edge.firstWhere((f) => f.path == path);

      test('quoted, non-ASCII and space-containing paths', () {
        expect(
          [for (final f in edge) (f.oldPath, f.newPath, f.kind)],
          [
            ('café.png', 'café.png', FileDiffKind.modified),
            ('source.txt', 'copy.txt', FileDiffKind.copied),
            ('crlf.txt', 'crlf.txt', FileDiffKind.modified),
            ('old name.txt', 'nové jméno.txt', FileDiffKind.renamed),
            ('run.sh', 'run.sh', FileDiffKind.modified),
            ('x b/y.txt', 'x b/y.txt', FileDiffKind.modified),
          ],
        );
        expect(edgeFile('café.png').isBinary, isTrue);
      });

      test('a mode change has no hunks', () {
        expect(edgeFile('run.sh').hunks, isEmpty);
      });

      test('CRLF content loses its carriage returns', () {
        final lines = edgeFile('crlf.txt').hunks.single.lines;
        expect(lines.map((l) => '$l'), [
          '-line 1',
          '-line 2',
          '+line 1',
          '+line 2',
        ]);
      });
    });

    test('a path containing " b/" splits in the middle', () {
      final file = parsePatch('''
diff --git a/x b/y.txt b/x b/y.txt
old mode 100644
new mode 100755
''').single;
      expect((file.oldPath, file.newPath), ('x b/y.txt', 'x b/y.txt'));
      expect(file.kind, FileDiffKind.modified);
    });

    test('plain diff -u between two names is not a rename', () {
      final file = parsePatch('''
--- before.txt
+++ after.txt
@@ -1 +1 @@
-a
+b
''').single;
      expect((file.oldPath, file.newPath), ('before.txt', 'after.txt'));
      expect(file.kind, FileDiffKind.modified);
    });

    test('malformed input is read as far as possible', () {
      expect(parsePatch(''), isEmpty);
      expect(parsePatch('not a patch\n\\ No newline at end of file'), isEmpty);
      final truncated = parsePatch('''
--- a/t.txt
+++ b/t.txt
@@ -1,5 +1,5 @@
 one
-two
''').single;
      expect(truncated.hunks.single.lines.map((l) => '$l'), [' one', '-two']);
      final huge = parsePatch('''
--- a/t.txt
+++ b/t.txt
@@ -99999999999999999999 +1 @@
-x
+y
''').single;
      expect(huge.hunks, isEmpty);
      // Ten digits: dropped on every platform, not only where it overflows.
      final long = parsePatch('''
--- a/t.txt
+++ b/t.txt
@@ -1234567890 +1 @@
-x
+y
''').single;
      expect(long.hunks, isEmpty);
    });

    test('marks a missing final newline on removed and context lines', () {
      final file = parsePatch('''
--- a/t.txt
+++ b/t.txt
@@ -1,2 +1,2 @@
-a
-b
\\ No newline at end of file
+a
+b
\\ No newline at end of file
--- a/u.txt
+++ b/u.txt
@@ -1,2 +1,2 @@
-x
+y
 last
\\ No newline at end of file
''');
      expect(
        [
          for (final f in file)
            for (final l in f.hunks.single.lines)
              if (l.noNewlineAtEnd) '$l',
        ],
        ['-b', '+b', ' last'],
      );
    });
  });

  group('myersDiff', () {
    // Equal and inserted elements, in order, rebuild the new list.
    List<int> apply(List<Edit> edits, List<int> a, List<int> b) => [
      for (final e in edits)
        if (e.kind == EditKind.equal)
          a[e.oldIndex]
        else if (e.kind == EditKind.insert)
          b[e.newIndex],
    ];

    test('rebuilds the target from random inputs', () {
      final random = Random(42);
      for (var run = 0; run < 300; run++) {
        final a = [
          for (var i = 0; i < random.nextInt(30); i++) random.nextInt(5),
        ];
        final b = [
          for (var i = 0; i < random.nextInt(30); i++) random.nextInt(5),
        ];
        final edits = myersDiff(a, b);
        expect(apply(edits, a, b), b, reason: '$a -> $b');
        expect(
          edits
              .where((e) => e.kind != EditKind.insert)
              .map((e) => a[e.oldIndex]),
          a,
        );
      }
    });

    test('is minimal on a known case', () {
      // ABCABBA -> CBABAC needs 5 edits.
      final edits = myersDiff([1, 2, 3, 1, 2, 2, 1], [3, 2, 1, 2, 1, 3]);
      expect(edits.where((e) => e.kind != EditKind.equal), hasLength(5));
    });

    test('falls back to replacing the middle past maxEdits', () {
      final edits = myersDiff([0, 1, 2, 9], [0, 3, 4, 9], maxEdits: 1);
      expect(edits.map((e) => e.kind), [
        EditKind.equal,
        EditKind.delete,
        EditKind.delete,
        EditKind.insert,
        EditKind.insert,
        EditKind.equal,
      ]);
    });
  });

  group('diffTexts', () {
    test('matches git on the same change', () {
      final ours = diffTexts(
        fixture('lib.before.txt'),
        fixture('lib.after.txt'),
        path: 'lib.dart',
      );
      final git = parsePatch(fixture('lib.patch')).single;
      expect(ours.hunks.map(render), git.hunks.map(render));
    });

    test('results cannot be changed', () {
      final diff = diffTexts('a\n', 'b\n');
      expect(() => diff.hunks.add(diff.hunks.first), throwsUnsupportedError);
      expect(() => diff.hunks.first.lines.clear(), throwsUnsupportedError);
      expect(() => diff.newLines!.add('c'), throwsUnsupportedError);
      final parsed = parsePatch(fixture('lib.patch')).single;
      expect(() => parsed.hunks.first.lines.clear(), throwsUnsupportedError);
    });

    test('identical texts have no hunks', () {
      expect(diffTexts('a\nb\n', 'a\nb\n').hunks, isEmpty);
    });

    test('empty sides', () {
      final added = diffTexts('', 'a\nb\n');
      expect(added.hunks.single.header, '@@ -0,0 +1,2 @@');
      final removed = diffTexts('a\n', '');
      expect(removed.hunks.single.header, '@@ -1 +0,0 @@');
    });

    test('converting CRLF to LF is a change, shown without the \\r', () {
      final diff = diffTexts('a\r\nb\r\n', 'a\nb\n');
      expect(render(diff.hunks.single), '''
@@ -1,2 +1,2 @@
-a
-b
+a
+b''');
      expect(diff.oldLines, ['a', 'b']);
    });

    test('a context line can be the last line without a newline', () {
      final line = diffTexts('x\nlast', 'y\nlast').hunks.single.lines.last;
      expect(('$line', line.noNewlineAtEnd), (' last', true));
    });

    test('negative context is rejected', () {
      expect(() => diffTexts('a', 'b', contextLines: -1), throwsRangeError);
    });

    test('a removed final newline is a change', () {
      final diff = diffTexts('a\nb\n', 'a\nb');
      expect(render(diff.hunks.single), '''
@@ -1,2 +1,2 @@
 a
-b
+b''');
      expect(diff.hunks.single.lines.last.noNewlineAtEnd, isTrue);
    });

    test('far apart changes get separate hunks, close ones merge', () {
      final old = [for (var i = 0; i < 30; i++) 'l$i'].join('\n');
      String change(List<int> at) => [
        for (var i = 0; i < 30; i++) at.contains(i) ? 'X$i' : 'l$i',
      ].join('\n');
      expect(diffTexts(old, change([2, 25])).hunks, hasLength(2));
      expect(diffTexts(old, change([2, 8])).hunks, hasLength(1));
      expect(
        diffTexts(old, change([2, 25]), contextLines: 0).hunks,
        hasLength(2),
      );
    });

    // Expected outputs are from `git diff`, the same with or without
    // `--no-indent-heuristic` unless a test says otherwise. A plain Myers
    // diff finds other, equally short scripts for each of these.
    group('groups changes like git', () {
      String diff(String a, String b) => render(diffTexts(a, b).hunks.single);

      test('a deletion split by an equal line becomes one block', () {
        expect(diff('x\na\na\nb\n', 'a\nb\ny\n'), '''
@@ -1,4 +1,3 @@
-x
-a
 a
 b
+y''');
      });

      test('an insertion among equal lines slides to the last spot', () {
        expect(diff('b\na\nb\n', 'a\nb\nb\n'), '''
@@ -1,3 +1,3 @@
-b
 a
 b
+b''');
      });

      test('a sliding insertion lines up with a deletion', () {
        expect(diff('x\nb\na\na\n', 'b\nb\na\ny\n'), '''
@@ -1,4 +1,4 @@
-x
+b
 b
 a
-a
+y''');
      });

      group('a function added between functions', () {
        const before = '''
import 'dart:math';

/// Returns a number.
int a() {
  return 1;
}

/// Returns a number.
int c() {
  return 3;
}
''';
        const after = '''
import 'dart:math';

/// Returns a number.
int a() {
  return 1;
}

/// Returns a number.
int b() {
  return 2;
}

/// Returns a number.
int c() {
  return 3;
}
''';

        test('is shown whole, by the indent heuristic', () {
          expect(
            diff(before, after),
            [
              '@@ -5,6 +5,11 @@ int a() {',
              '   return 1;',
              ' }',
              ' ',
              '+/// Returns a number.',
              '+int b() {',
              '+  return 2;',
              '+}',
              '+',
              ' /// Returns a number.',
              ' int c() {',
              '   return 3;',
            ].join('\n'),
          );
        });

        test('slides to the bottom without the heuristic', () {
          final diff = diffTexts(before, after, indentHeuristic: false);
          expect(
            render(diff.hunks.single),
            [
              '@@ -6,6 +6,11 @@ int a() {',
              ' }',
              ' ',
              ' /// Returns a number.',
              '+int b() {',
              '+  return 2;',
              '+}',
              '+',
              '+/// Returns a number.',
              ' int c() {',
              '   return 3;',
              ' }',
            ].join('\n'),
          );
        });
      });
    });
  });

  group('WordChanges', () {
    FileDiff edit(String a, String b) => diffTexts('$a\n', '$b\n');

    test('marks the changed words of an edited line', () {
      final diff = edit('final count = 1;', 'final total = 1;');
      final lines = diff.hunks.single.lines;
      final changes = WordChanges.of(diff);
      expect(changes.rangesFor(lines[0]), [(start: 6, end: 11)]);
      expect(changes.rangesFor(lines[1]), [(start: 6, end: 11)]);
    });

    test('ranges are UTF-16 offsets and merge across spaces', () {
      final emoji = edit('😀 count = 1;', '😀 total = 1;');
      final added = emoji.hunks.single.lines.last;
      expect(WordChanges.of(emoji).rangesFor(added), [(start: 3, end: 8)]);

      final spaced = edit('final a b = compute(1);', 'final x y = compute(1);');
      final line = spaced.hunks.single.lines.last;
      expect(WordChanges.of(spaced).rangesFor(line), [(start: 6, end: 9)]);
    });

    test('rewritten lines get no word ranges', () {
      final diff = edit('return a + b;', 'throw StateError();');
      final changes = WordChanges.of(diff);
      for (final line in diff.hunks.single.lines) {
        expect(changes.rangesFor(line), isEmpty);
      }
    });
  });

  group('HighlightedDiff', () {
    final highlighter = Highlighter(
      languages: [
        dartLanguage,
        yamlLanguage,
        markdownLanguage,
        shellscriptLanguage,
        diffLanguage,
        htmlLanguage,
        xmlLanguage,
      ],
    );

    test('picks the language from the path', () {
      expect(highlighter.languageForPath('lib/main.dart'), same(dartLanguage));
      expect(highlighter.languageForPath('pubspec.yml'), same(yamlLanguage));
      expect(highlighter.languageForPath('README.md'), same(markdownLanguage));
      expect(
        highlighter.languageForPath('deploy.sh'),
        same(shellscriptLanguage),
      );
      expect(highlighter.languageForPath('notes.unknown'), isNull);
      expect(
        highlighter.languageForPath(r'lib\src\a.dart'),
        same(dartLanguage),
      );
      expect(highlighter.languageForPath('.sh'), isNull);
      expect(highlighter.languageForPath('fix.patch'), same(diffLanguage));
      expect(highlighter.languageForPath('index.htm'), same(htmlLanguage));
      expect(highlighter.languageForPath('logo.svg'), same(xmlLanguage));
    });

    test('with full texts, state carries into later hunks', () {
      final before = [
        '/*',
        for (var i = 0; i < 20; i++) 'still comment $i',
        '*/',
      ].join('\n');
      final after = before.replaceFirst('still comment 15', 'changed 15');
      final diff = diffTexts(before, after, path: 'a.dart');
      final highlighted = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      final added = diff.hunks.single.lines.firstWhere(
        (l) => l.kind == DiffLineKind.added,
      );
      final token = highlighted.tokensFor(added).single;
      expect(token.scopes.scopes, contains('comment.block.dart'));
    });

    test('a parsed patch highlights each side of each hunk', () {
      final diff = parsePatch('''
--- a/a.dart
+++ b/a.dart
@@ -10,2 +10,2 @@
 // context
-final a = 1;
+var a = 1;
''').single;
      final highlighted = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      final [context, removed, added] = diff.hunks.single.lines;
      expect(
        highlighted.tokensFor(context).single.scopes.scopes,
        contains('comment.line.double-slash.dart'),
      );
      expect(highlighted.tokensFor(removed).first.text, 'final');
      expect(highlighted.oldLine(11).first.text, 'final');
      expect(highlighted.newLine(11).first.text, 'var');
      expect(highlighted.newLine(1), isEmpty);
    });

    test('a language override wins over the path', () {
      final diff = diffTexts('a\n', 'b: 1\n', path: 'config');
      final highlighted = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
        language: 'yaml',
      );
      expect(
        highlighted.newLine(1).first.scopes.scopes,
        contains('source.yaml'),
      );
    });

    test('unknown languages stay plain', () {
      final diff = diffTexts('a\n', 'b\n', path: 'x.unknown');
      final highlighted = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      for (final line in diff.hunks.single.lines) {
        expect(highlighted.tokensFor(line).single.text, line.text);
      }
    });
  });

  group('layoutDiff', () {
    String describe(DiffRow row) => switch (row) {
      DiffFileHeaderRow(:final file, :final collapsed) =>
        'file $file${collapsed ? ' collapsed' : ''}',
      DiffNoticeRow(:final notice) => 'notice ${notice.name}',
      DiffHunkHeaderRow(:final hunk) => hunk.header,
      DiffGapRow(:final count) => 'gap $count',
      DiffLineRow(:final line) => '$line',
      DiffPairRow(:final left, :final right) =>
        '${left ?? '.'} | ${right ?? '.'}',
    };

    test('a patch: headers, hunks, lines and notices', () {
      final files = parsePatch('''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old
+new
diff --git a/old.txt b/new.txt
similarity index 100%
rename from old.txt
rename to new.txt
''');
      expect(layoutDiff(files).map(describe), [
        'file 0',
        '@@ -1,2 +1,2 @@',
        ' keep',
        '-old',
        '+new',
        'file 1',
        'notice renamedWithoutChanges',
      ]);
      expect(layoutDiff(files, collapsed: {0}).map(describe), [
        'file 0 collapsed',
        'file 1',
        'notice renamedWithoutChanges',
      ]);
      expect(layoutDiff(const []), isEmpty);
    });

    test('split pairs removed with added lines and pads the rest', () {
      final diff = diffTexts('keep\na\nb\n', 'keep\nx\n');
      expect(layoutDiff([diff], mode: DiffMode.split).map(describe), [
        '@@ -1,3 +1,2 @@',
        ' keep |  keep',
        '-a | +x',
        '-b | .',
      ]);
    });

    test('texts get gaps; expanding one drops the header below it', () {
      final before = [for (var i = 1; i <= 12; i++) 'l$i'].join('\n');
      final diff = diffTexts(before, before.replaceFirst('l8', 'L8'));
      expect(layoutDiff([diff]).map(describe), [
        'gap 4',
        '@@ -5,7 +5,7 @@ l4',
        ' l5',
        ' l6',
        ' l7',
        '-l8',
        '+L8',
        ' l9',
        ' l10',
        ' l11',
        'gap 1',
      ]);
      final expanded = layoutDiff([diff], expanded: {(file: 0, hunk: 0)});
      expect(expanded.take(6).map(describe), [
        ' l1',
        ' l2',
        ' l3',
        ' l4',
        ' l5',
        ' l6',
      ]);
    });

    test('expanding every gap shows both files in order', () {
      final random = Random(11);
      for (var run = 0; run < 200; run++) {
        String text() => [
          for (var i = 0; i < random.nextInt(30); i++)
            ['a', 'b', 'c', '}'][random.nextInt(4)],
        ].join('\n');
        final before = text();
        final after = random.nextBool() ? text() : '$before\nextra\n';
        final diff = diffTexts(before, after, contextLines: random.nextInt(4));
        final all = {
          for (var h = 0; h <= diff.hunks.length; h++) (file: 0, hunk: h),
        };
        final lines = [
          for (final row in layoutDiff([diff], expanded: all))
            if (row case DiffLineRow(:final line)) line,
        ];
        expect(
          [
            for (final l in lines)
              if (l.kind != DiffLineKind.added) '${l.oldNumber} ${l.text}',
          ],
          [for (final (i, l) in diff.oldLines!.indexed) '${i + 1} $l'],
          reason: 'run $run',
        );
        expect(
          [
            for (final l in lines)
              if (l.kind != DiffLineKind.removed) '${l.newNumber} ${l.text}',
          ],
          [for (final (i, l) in diff.newLines!.indexed) '${i + 1} $l'],
          reason: 'run $run',
        );
      }
    });

    test('notices say why a file has no lines', () {
      DiffNotice? noticeOf(FileDiff file) =>
          layoutDiff([file]).whereType<DiffNoticeRow>().singleOrNull?.notice;
      expect(noticeOf(diffTexts('a', 'a')), DiffNotice.noChanges);
      final edge = parsePatch(fixture('edge.patch'));
      expect(
        noticeOf(edge.firstWhere((f) => f.path == 'run.sh')),
        DiffNotice.noContentChanges,
      );
      expect(
        noticeOf(edge.firstWhere((f) => f.path == 'café.png')),
        DiffNotice.binary,
      );
    });

    test('a diff without a path has no header and is never collapsed', () {
      final rows = layoutDiff([diffTexts('a\n', 'b\n')], collapsed: {0});
      expect(rows.first, isA<DiffHunkHeaderRow>());
      expect(rows, hasLength(3));
    });

    test('rows name their file; notices cover empty and copied files', () {
      const copied = FileDiff(
        oldPath: 'a.txt',
        newPath: 'b.txt',
        kind: FileDiffKind.copied,
        hunks: [],
      );
      const empty = FileDiff(
        oldPath: null,
        newPath: 'e.txt',
        kind: FileDiffKind.added,
        hunks: [],
      );
      final rows = layoutDiff([copied, empty, diffTexts('a', 'b', path: 'c')]);
      // Header and notice for each empty file, then header, hunk header and
      // two lines for the last.
      expect(rows.map((r) => r.file), [0, 0, 1, 1, 2, 2, 2, 2]);
      expect(rows.whereType<DiffNoticeRow>().map((r) => r.notice), [
        DiffNotice.copiedWithoutChanges,
        DiffNotice.emptyFile,
      ]);
    });

    test('split mode shows expanded lines on both sides', () {
      final before = [for (var i = 1; i <= 12; i++) 'l$i'].join('\n');
      final diff = diffTexts(before, before.replaceFirst('l1\n', ''));
      final all = {
        for (var h = 0; h <= diff.hunks.length; h++) (file: 0, hunk: h),
      };
      final pairs = layoutDiff(
        [diff],
        mode: DiffMode.split,
        expanded: all,
      ).whereType<DiffPairRow>();
      expect(
        [
          for (final p in pairs)
            if (p.left case final l?) l.oldNumber,
        ],
        [for (var i = 1; i <= 12; i++) i],
      );
      expect(
        [
          for (final p in pairs)
            if (p.right case final r?) r.newNumber,
        ],
        [for (var i = 1; i <= 11; i++) i],
      );
    });

    test('change blocks give each kind of change at least one', () {
      FileDiff withCounts(int added, int removed) => diffTexts(
        [for (var i = 0; i < removed; i++) 'old $i'].join('\n'),
        [for (var i = 0; i < added; i++) 'new $i'].join('\n'),
      );
      expect(withCounts(0, 0).changeBlocks(), (added: 0, removed: 0));
      expect(withCounts(3, 0).changeBlocks(), (added: 5, removed: 0));
      expect(withCounts(99, 1).changeBlocks(), (added: 4, removed: 1));
      expect(withCounts(1, 99).changeBlocks(), (added: 1, removed: 4));
      expect(withCounts(2, 2).changeBlocks(), (added: 3, removed: 2));
      // Too few squares for both kinds: the larger kind gets the one.
      expect(withCounts(3, 1).changeBlocks(1), (added: 1, removed: 0));
      expect(withCounts(1, 3).changeBlocks(1), (added: 0, removed: 1));
      expect(withCounts(3, 1).changeBlocks(0), (added: 0, removed: 0));
      expect(() => withCounts(1, 1).changeBlocks(-1), throwsRangeError);
    });

    test('grammarFor follows languages added later', () {
      final highlighter = Highlighter();
      final diff = diffTexts('a\n', 'b\n', path: 'a.dart');
      expect(
        HighlightedDiff.grammarFor(diff, highlighter: highlighter),
        isNull,
      );
      highlighter.addLanguage(dartLanguage);
      expect(
        HighlightedDiff.grammarFor(diff, highlighter: highlighter),
        same(highlighter.grammar('dart')),
      );
    });

    test('labels default to English with plurals', () {
      const labels = DiffLabels();
      final file = diffTexts('a\n', 'b\n', path: 'a.txt');
      expect(
        labels.fileHeader(file),
        'Modified, a.txt, 1 addition, 1 deletion',
      );
      expect(labels.showUnchangedLines(1), 'Show 1 unchanged line');
      expect(labels.showUnchangedLines(3), 'Show 3 unchanged lines');
      expect(labels.notice(DiffNotice.binary), 'Binary file not shown');
      expect(labels.status(FileDiffKind.modified), isNull);
    });

    test('maxLineNumber covers both files', () {
      final diff = diffTexts(
        [for (var i = 0; i < 12; i++) 'x$i'].join('\n'),
        'x0\n',
      );
      expect(diff.maxLineNumber, 12);
      expect(parsePatch(fixture('lib.patch')).single.maxLineNumber, 38);
    });
  });

  group('segmentsFor', () {
    final highlighter = Highlighter(languages: [dartLanguage]);

    test('splits tokens at changed words and marks them', () {
      final diff = diffTexts('final count = 1;\n', 'final total = 1;\n');
      final highlighted = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
        language: 'dart',
      );
      final added = diff.hunks.single.lines.last;
      final segments = highlighted.segmentsFor(added, WordChanges.of(diff));
      expect(segments.join(), 'final [total] = 1;');
      expect(segments.map((s) => s.text).join(), added.text);
      expect(highlighted.segmentsFor(added).any((s) => s.changed), isFalse);
    });

    test('a line without tokens is one plain segment', () {
      final diff = diffTexts('a\n', 'b\n', path: 'a.dart');
      final highlighted = HighlightedDiff.of(
        diff,
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      const outside = DiffLine(DiffLineKind.context, 'x', newNumber: 99);
      expect(highlighted.segmentsFor(outside), [
        DiffSegment('x', TokenStyle(foreground: githubDarkTheme.foreground)),
      ]);
    });
  });

  group('DiffColors', () {
    test('chrome colors are opaque mixes of the theme colors', () {
      final colors = DiffColors.of(githubDarkTheme);
      for (final c in [
        colors.fileHeader,
        colors.hunkHeader,
        colors.emptySide,
        colors.divider,
        colors.muted,
      ]) {
        expect(c >> 24 & 0xFF, 0xFF);
      }
      expect(alphaBlend(0x80FFFFFF, 0xFF000000), 0xFF808080);
      expect(alphaBlend(0xFF123456, 0xFF000000), 0xFF123456);
      expect(alphaBlend(0x00FFFFFF, 0xFF102030), 0xFF102030);
    });

    test('equal colors compare equal', () {
      expect(DiffColors.of(githubDarkTheme), DiffColors.of(githubDarkTheme));
      expect(
        const DiffLine(DiffLineKind.added, 'x', newNumber: 1),
        const DiffLine(DiffLineKind.added, 'x', newNumber: 1),
      );
    });

    test('theme colors win', () {
      final colors = DiffColors.of(githubDarkTheme);
      expect(
        colors.insertedText,
        githubDarkTheme.editorColor('diffEditor.insertedTextBackground'),
      );
    });

    test('fallbacks keep word highlights stronger than lines', () {
      final colors = DiffColors.of(lightPlusTheme);
      expect(
        lightPlusTheme.editorColor('editorGutter.addedBackground'),
        isNull,
      );
      expect(colors.inserted, 0xFF1A7F37);
      expect(colors.insertedText, 0x4D1A7F37);
      int alpha(int argb) => argb >> 24 & 0xFF;
      expect(
        alpha(colors.insertedText),
        greaterThan(alpha(colors.insertedLine)),
      );
      expect(alpha(colors.removedText), greaterThan(alpha(colors.removedLine)));
    });
  });

  test('bash, sh and zsh resolve to the shell grammar', () {
    final highlighter = Highlighter(
      languages: [shellscriptLanguage, markdownLanguage],
    );
    for (final name in ['bash', 'sh', 'zsh', 'shell', 'shellscript']) {
      expect(highlighter.language(name), same(shellscriptLanguage));
    }
    final line = highlighter.tokenize(r'echo "$HOME"', language: 'bash').single;
    expect(
      line.first.scopes.scopes,
      contains('support.function.builtin.shell'),
    );
    final fence = highlighter.tokenize('```bash\nls -la\n```', language: 'md');
    expect(fence[1].first.scopes.scopes, [
      ...['text.html.markdown', 'markup.fenced_code.block.markdown'],
      'meta.embedded.block.shellscript',
      ...['meta.statement.shell', 'meta.statement.command.shell'],
      'meta.statement.command.name.shell',
      'entity.name.function.call.shell',
      'entity.name.command.shell',
    ]);
  });
}
