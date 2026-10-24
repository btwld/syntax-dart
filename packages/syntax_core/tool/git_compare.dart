// Compares parsePatch and diffTexts with `git diff --no-index` on random
// edits: parsed hunks must rebuild the new text and print git's exact `@@`
// lines, and diffTexts must rebuild the new text too. It also counts how
// often diffTexts matches git line for line, once with the indent heuristic
// off (against `git diff --no-indent-heuristic`) and once with it on, as
// in plain `git diff` (against `git diff --indent-heuristic`), and how
// often it matches both where those two differ. The parsePatch checks use
// the `--no-indent-heuristic` output.
//
// It runs two corpora. Random text (seed 7) seldom leaves a change free to
// slide. At 1000 runs diffTexts matches git in 971 of 973 cases in both
// modes, and git's modes differ in only 5, all matched. At 10000 runs it
// matches 9734 of 9752 without the heuristic and 9733 with it, and 44 of
// the 45 where git's modes differ.
//
// Code blocks (seed 1) nest `void f() {` blocks indented with 2 or 4
// spaces, tabs or a mix, among blank, white-space-only and comment lines,
// with LF or CRLF line endings and sometimes no final newline. Edits copy
// blocks next to themselves, delete blocks, add blocks and add blank lines,
// so changes can often slide. At 1000 runs diffTexts matches git in 959 of
// 977 cases in both modes, and 102 of the 105 where git's modes differ. At
// 10000 runs it matches 9627 of 9793 without the heuristic and 9625 with
// it, and 1093 of the 1112 where git's modes differ.
//
// The misses are other diffs no longer than git's: git's own diff core
// sometimes keeps a different one of several equal lines, or splits a run
// of changes differently, which sliding can't undo (3 times in 10000 code
// cases git's diff is two lines longer). Where our run is split and git's
// isn't, sliding without the heuristic merges the pieces as git has them,
// but with it each piece stays where git would put it alone. So a few
// cases match only without the heuristic. Needs git on PATH. Usage:
//   dart run tool/git_compare.dart [runs]
import 'dart:io';
import 'dart:math';

import 'package:syntax_core/syntax.dart';

/// Rebuilds the new text by applying [diff] to [old].
String apply(String old, FileDiff diff) {
  final oldNoNl = old.isNotEmpty && !old.endsWith('\n');
  final oldLines = old.isEmpty ? <String>[] : old.split('\n');
  if (!oldNoNl && old.isNotEmpty) oldLines.removeLast();
  final out = <String>[];
  var cursor = 0; // index into oldLines
  var lastNoNl = false;
  for (final h in diff.hunks) {
    final firstOld = h.oldCount == 0 ? h.oldStart : h.oldStart - 1;
    if (firstOld < cursor) throw 'hunk overlaps: ${h.header}';
    while (cursor < firstOld) {
      out.add(oldLines[cursor++]);
      lastNoNl = oldNoNl && cursor == oldLines.length;
    }
    var o = 0, n = 0;
    for (final l in h.lines) {
      switch (l.kind) {
        case DiffLineKind.context:
          if (oldLines[cursor] != l.text) throw 'context mismatch ${h.header}';
          if (l.oldNumber != cursor + 1) throw 'old number ${l.oldNumber}';
          cursor++;
          out.add(l.text);
          o++;
          n++;
        case DiffLineKind.removed:
          if (oldLines[cursor] != l.text) throw 'removed mismatch ${h.header}';
          if (l.oldNumber != cursor + 1) throw 'old number ${l.oldNumber}';
          cursor++;
          o++;
          continue;
        case DiffLineKind.added:
          out.add(l.text);
          n++;
      }
      if (l.newNumber != out.length) {
        throw 'new number ${l.newNumber} != ${out.length} in ${h.header}';
      }
      lastNoNl = l.noNewlineAtEnd;
    }
    if (o != h.oldCount || n != h.newCount) throw 'counts ${h.header}';
  }
  while (cursor < oldLines.length) {
    out.add(oldLines[cursor++]);
    lastNoNl = oldNoNl && cursor == oldLines.length;
  }
  if (out.isEmpty) return '';
  return out.join('\n') + (lastNoNl ? '' : '\n');
}

String randomText(Random r) {
  const words = ['alpha', 'beta', 'gamma', '  inner', '  other', '}', ''];
  final lines = [
    for (var i = 0; i < r.nextInt(25); i++)
      r.nextInt(6) == 0 ? 'fn f$i() {' : words[r.nextInt(words.length)],
  ];
  if (lines.isEmpty) return '';
  return lines.join('\n') + (r.nextInt(5) == 0 ? '' : '\n');
}

String mutate(Random r, String text) {
  final lines = text.isEmpty ? <String>[] : text.split('\n');
  final noNl = text.isNotEmpty && !text.endsWith('\n');
  if (!noNl && text.isNotEmpty) lines.removeLast();
  for (var k = 0; k < 1 + r.nextInt(4); k++) {
    final at = lines.isEmpty ? 0 : r.nextInt(lines.length + 1);
    switch (r.nextInt(3)) {
      case 0:
        lines.insertAll(at, ['new ${r.nextInt(99)}', if (r.nextBool()) 'more']);
      case 1:
        if (lines.isNotEmpty) {
          lines.removeRange(
            min(at, lines.length - 1),
            min(lines.length, at + 1 + r.nextInt(3)),
          );
        }
      case 2:
        if (lines.isNotEmpty) lines[min(at, lines.length - 1)] = 'changed $k';
    }
  }
  if (lines.isEmpty) return '';
  final flip = r.nextInt(6) == 0;
  return lines.join('\n') + ((noNl != flip) ? '' : '\n');
}

/// Random text and a random edit of it.
(String, String) textCase(Random r) {
  final old = randomText(r);
  return (old, mutate(r, old));
}

const indentSteps = ['  ', '    ', '\t'];

/// A blank line, sometimes holding only white space.
String blankLine(Random r, String indent) =>
    ['', '', ' ', '\t', indent][r.nextInt(5)];

/// A `void f() {` block at [indent], nesting up to [depth] more blocks. A
/// null [step] picks the indent step of each block at random.
List<String> codeBlock(Random r, String indent, String? step, int depth) {
  final inner = indent + (step ?? indentSteps[r.nextInt(indentSteps.length)]);
  final body = <String>[];
  for (var i = 0, n = 1 + r.nextInt(4); i < n; i++) {
    switch (r.nextInt(depth > 0 ? 5 : 4)) {
      case 0:
        body.add('${inner}x = ${r.nextInt(3)};');
      case 1:
        body.add('$inner// note ${r.nextInt(3)}');
      case 2:
        body.add(blankLine(r, inner));
      case 3:
        body.add('${inner}return;');
      case _:
        body.addAll(codeBlock(r, inner, step, depth - 1));
    }
  }
  return ['${indent}void f${r.nextInt(3)}() {', ...body, '$indent}'];
}

/// Top-level blocks, comments and blank lines.
List<String> codeLines(Random r, String? step) {
  final lines = <String>[];
  for (var i = 0, n = 1 + r.nextInt(5); i < n; i++) {
    switch (r.nextInt(4)) {
      case 0:
        lines.add('// comment ${r.nextInt(3)}');
      case 1:
        lines.add(blankLine(r, ''));
      case _:
        lines.addAll(codeBlock(r, '', step, 2));
        if (r.nextBool()) lines.add('');
    }
  }
  return lines;
}

/// The `[start, end)` line ranges of the `{ ... }` blocks in [lines].
List<(int, int)> blocks(List<String> lines) {
  final found = <(int, int)>[], open = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.endsWith('{')) open.add(i);
    if (line == '}' && open.isNotEmpty) found.add((open.removeLast(), i + 1));
  }
  return found;
}

/// Copies blocks next to themselves, deletes blocks, adds new blocks and adds
/// blank lines: edits whose changed lines can often slide.
List<String> mutateCode(Random r, List<String> old, String? step) {
  final lines = [...old];
  bool blankAt(int i) => i >= 0 && i < lines.length && lines[i].trim().isEmpty;
  for (var k = 0, n = 1 + r.nextInt(3); k < n; k++) {
    final found = blocks(lines);
    if (found.isEmpty) {
      lines.insertAll(r.nextInt(lines.length + 1), codeBlock(r, '', step, 1));
      continue;
    }
    final (start, end) = found[r.nextInt(found.length)];
    // The block, sometimes with the blank lines next to it.
    final from = r.nextBool() && blankAt(start - 1) ? start - 1 : start;
    final to = r.nextBool() && blankAt(end) ? end + 1 : end;
    switch (r.nextInt(4)) {
      case 0:
        lines.insertAll(to, lines.sublist(from, to));
      case 1:
        lines.removeRange(from, to);
      case 2:
        final indent = RegExp(r'^\s*').stringMatch(lines[start])!;
        lines.insertAll(r.nextBool() ? from : to, [
          if (r.nextBool()) '',
          ...codeBlock(r, indent, step, 1),
          if (r.nextBool()) '',
        ]);
      case _:
        lines.insertAll(r.nextInt(lines.length + 1), [
          blankLine(r, ''),
          if (r.nextBool()) '',
        ]);
    }
  }
  return lines;
}

/// Nested code blocks and a block-shaped edit of them, with LF or CRLF line
/// endings and sometimes no final newline.
(String, String) codeCase(Random r) {
  final style = r.nextInt(indentSteps.length + 1);
  final step = style < indentSteps.length ? indentSteps[style] : null;
  final old = codeLines(r, step);
  final neu = mutateCode(r, old, step);
  final eol = r.nextInt(4) == 0 ? '\r\n' : '\n';
  final finalNewline = r.nextInt(6) != 0;
  String join(List<String> lines, bool newline) =>
      lines.isEmpty ? '' : lines.join(eol) + (newline ? eol : '');
  return (
    join(old, finalNewline),
    join(neu, finalNewline != (r.nextInt(8) == 0)),
  );
}

void main(List<String> args) {
  final runs = args.isEmpty ? 300 : int.parse(args.first);
  final dir = Directory.systemTemp.createTempSync('fuzz');
  compare('random text, seed 7', Random(7), runs, dir, textCase);
  compare('code blocks, seed 1', Random(1), runs, dir, codeCase);
  dir.deleteSync(recursive: true);
}

/// Diffs [runs] cases from [makeCase] with git and with diffTexts in [dir],
/// and prints the counts.
void compare(
  String name,
  Random r,
  int runs,
  Directory dir,
  (String, String) Function(Random) makeCase,
) {
  var parseOk = 0, headerOk = 0, oursApply = 0, compared = 0;
  var sameAsGit = 0, sameAsGitIndent = 0;
  var modesDiffer = 0, sameWhereModesDiffer = 0;
  final differences = <String>[];
  // DiffLine.text never holds the `\r` of a CRLF line ending.
  String lf(String text) => text.replaceAll('\r\n', '\n');
  for (var i = 0; i < runs; i++) {
    final (old, neu) = makeCase(r);
    if (old == neu) continue;
    final ctx = r.nextInt(4);
    File('${dir.path}/a.txt').writeAsStringSync(old);
    File('${dir.path}/b.txt').writeAsStringSync(neu);
    String gitDiff(String indentHeuristic) =>
        Process.runSync('git', [
              'diff',
              '--no-index',
              indentHeuristic,
              '--no-color',
              '-U$ctx',
              'a.txt',
              'b.txt',
            ], workingDirectory: dir.path).stdout
            as String;
    final git = gitDiff('--no-indent-heuristic');
    compared++;

    final parsed = parsePatch(git);
    final file = parsed.single;
    try {
      if (apply(lf(old), file) == lf(neu)) parseOk++;
    } catch (e) {
      differences.add('parse apply #$i: $e');
    }
    final rawHeaders = git
        .split('\n')
        .where((l) => l.startsWith('@@'))
        .toList();
    if ('${file.hunks.map((h) => h.header).toList()}' == '$rawHeaders') {
      headerOk++;
    } else {
      differences.add(
        'header #$i: ${file.hunks.map((h) => h.header).toList()} vs $rawHeaders',
      );
    }

    String render(FileDiff d) => [
      for (final h in d.hunks) ...[h.header, ...h.lines.map((l) => '$l')],
    ].join('\n');
    final withIndent = parsePatch(gitDiff('--indent-heuristic')).single;
    var rebuilt = true, sameInBoth = true;
    for (final (indentHeuristic, want) in [(false, file), (true, withIndent)]) {
      final ours = diffTexts(
        old,
        neu,
        contextLines: ctx,
        indentHeuristic: indentHeuristic,
      );
      final mode = indentHeuristic
          ? '--indent-heuristic'
          : '--no-indent-heuristic';
      try {
        if (apply(lf(old), ours) != lf(neu)) rebuilt = false;
      } catch (e) {
        rebuilt = false;
        differences.add('ours apply #$i ctx=$ctx $mode: $e');
      }
      if (render(ours) != render(want)) {
        sameInBoth = false;
        if (differences.length < 12) {
          differences.add(
            'differs from git $mode #$i ctx=$ctx\n--- git\n${render(want)}\n--- ours\n${render(ours)}',
          );
        }
      } else if (indentHeuristic) {
        sameAsGitIndent++;
      } else {
        sameAsGit++;
      }
    }
    if (rebuilt) oursApply++;
    if (render(file) != render(withIndent)) {
      modesDiffer++;
      if (sameInBoth) sameWhereModesDiffer++;
    }
  }
  print('$name:');
  print('  cases: $compared');
  print('  parsePatch rebuilds new text: $parseOk');
  print('  header getter equals git @@ line: $headerOk');
  print('  diffTexts rebuilds new text, in both modes: $oursApply');
  print('  diffTexts identical to git --no-indent-heuristic: $sameAsGit');
  print('  diffTexts identical to git --indent-heuristic: $sameAsGitIndent');
  print(
    "  git's two modes differ: $modesDiffer, "
    'diffTexts identical to git in both of them: $sameWhereModesDiffer',
  );
  for (final d in differences.take(6)) {
    print('\n$d');
  }
}
