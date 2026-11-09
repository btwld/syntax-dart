import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/src/source_line_endings.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'patch_composition_test.dart' show app, copy, select, selection;

void main() {
  test(
    'million-line fallback reads only requested context and keeps a cursor',
    () {
      final lines = _CountedLines(List.filled(1000000, 'alpha'));
      final endings = SourceLineEndings('alpha\r\n' * 1000000, lines);
      expect(lines.reads, 0);
      expect(endings.endingAt(1), '\r\n');
      expect(lines.reads, 1);
      expect(endings.endingAt(2), '\r\n');
      expect(lines.reads, 2);
      expect(endings.endingAt(2), '\r\n');
      expect(lines.reads, 2);
      expect(endings.endingAt(1), '\r\n');
      expect(lines.reads, 3);
    },
  );

  test(
    'lazy context cursor preserves mixed terminators and backward queries',
    () {
      final endings = SourceLineEndings('a\r\nb\nc\rd', ['a', 'b', 'c', 'd']);
      expect(endings.endingAt(3), '\r');
      expect(endings.endingAt(1), '\r\n');
      expect(endings.endingAt(2), '\n');
      expect(endings.endingAt(4), '\n');
    },
  );

  testWidgets(
    'two-character copy in million-line full source needs no ending',
    (tester) async {
      final lines = _CountedLines(List.filled(1000000, 'alpha'));
      final source = 'alpha\r\n' * lines.length;
      final file = FileDiff(
        oldPath: 'a.txt',
        newPath: 'a.txt',
        kind: FileDiffKind.modified,
        oldText: source,
        newText: source,
        oldLines: lines,
        newLines: lines,
        hunks: const [
          DiffHunk(
            oldStart: 900000,
            oldCount: 1,
            newStart: 900000,
            newCount: 1,
            lines: [
              DiffLine(
                DiffLineKind.context,
                'alpha',
                oldNumber: 900000,
                newNumber: 900000,
                sourceLineEnding: '\r\n',
              ),
            ],
          ),
        ],
      );
      final pending = Completer<HighlightWindowResult>();
      await tester.pumpWidget(
        app(
          PatchView(
            files: [file],
            theme: githubDarkTheme,
            highlighter: Highlighter(),
            executor:
                (
                  request, {
                  required highlighter,
                  required theme,
                  required cancellation,
                }) => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final native = selection(tester);
      final rows = DiffLayout([file]);
      var textReads = 0;
      var endingReads = 0;
      native.configure(
        source: Object(),
        rowCount: rows.length,
        split: false,
        textAt: (row, side) {
          textReads++;
          return row == rows.rowForLine(0, 900000) ? 'alpha' : null;
        },
        identity: (row) => row,
        endingAt: (row, side) {
          endingReads++;
          return '\r\n';
        },
      );
      lines.reads = 0;
      await select(tester, 'alpha', 1, 'alpha', 3);
      await copy(tester, 'lp');
      expect(
        endingReads,
        0,
        reason: 'no separator is copied from a single source row',
      );
      expect(textReads, lessThan(100));
      expect(lines.reads, lessThan(100));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'far hunk metadata avoids scanning source prefix for multiline copy',
    (tester) async {
      final sourceLines = List.filled(1000000, 'alpha');
      sourceLines[900000] = 'beta';
      final source = sourceLines.join('\r\n');
      final lines = _CountedLines(sourceLines);
      final file = FileDiff(
        oldPath: 'a.txt',
        newPath: 'a.txt',
        kind: FileDiffKind.modified,
        oldText: source,
        newText: source,
        oldLines: lines,
        newLines: lines,
        hunks: const [
          DiffHunk(
            oldStart: 900000,
            oldCount: 2,
            newStart: 900000,
            newCount: 2,
            lines: [
              DiffLine(
                DiffLineKind.context,
                'alpha',
                oldNumber: 900000,
                newNumber: 900000,
                sourceLineEnding: '\r\n',
              ),
              DiffLine(
                DiffLineKind.context,
                'beta',
                oldNumber: 900001,
                newNumber: 900001,
                sourceLineEnding: '\r\n',
              ),
            ],
          ),
        ],
      );
      final pending = Completer<HighlightWindowResult>();
      await tester.pumpWidget(
        app(
          PatchView(
            files: [file],
            theme: githubDarkTheme,
            highlighter: Highlighter(),
            executor:
                (
                  request, {
                  required highlighter,
                  required theme,
                  required cancellation,
                }) => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      lines.reads = 0;
      await select(tester, 'alpha', 1, 'beta', 2);
      await copy(tester, 'lpha\r\nbe');
      expect(
        lines.reads,
        lessThan(100),
        reason: 'hunk line endings are already recorded',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _CountedLines extends ListBase<String> {
  _CountedLines(this.source);
  final List<String> source;
  int reads = 0;
  @override
  Iterator<String> get iterator => source.iterator;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  String operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('immutable');
}
