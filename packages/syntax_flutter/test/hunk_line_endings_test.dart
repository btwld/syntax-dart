import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_flutter/src/diff_text_selection.dart';
import 'package:syntax_flutter/src/patch_line_endings.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'patch_composition_test.dart' show app;

const _hunks = 10000;
const _selectedLines = _hunks * 2;
final _comparisonLimit =
    _selectedLines * ((math.log(_hunks) / math.ln2).ceil() + 1);

void main() {
  testWidgets('native 20000-line copy indexes 10000 hunks logarithmically', (
    tester,
  ) async {
    final fixture = _fixture();
    final endings = PatchLineEndings(fixture.file);
    final native = DiffTextSelection();
    native.configure(
      source: fixture.file,
      rowCount: _selectedLines,
      split: false,
      identity: (row) => row,
      textAt: (row, side) => fixture.newer[row],
      endingAt: (row, side) =>
          endings.endingAt(_synthetic(row, DiffSide.newer), side),
    );
    await tester.pumpWidget(
      app(SelectionContainer(delegate: native, child: const SizedBox())),
    );
    native.dispatchSelectionEvent(const SelectAllSelectionEvent());
    expect(native.getSelectedContent()!.plainText, fixture.expectedNew);
    expect(endings.rangeComparisons, lessThanOrEqualTo(_comparisonLimit));
    debugPrint(
      'native: ${endings.rangeComparisons} hunk-range comparisons for $_selectedLines lines / $_hunks hunks',
    );
    await tester.pumpWidget(const SizedBox());
    native.dispose();
  });

  for (final side in DiffSide.values) {
    test('gutter 20000-line copy uses shared hunk index on $side', () {
      final fixture = _fixture();
      final endings = PatchLineEndings(fixture.file);
      final source = side == DiffSide.old ? fixture.older : fixture.newer;
      final copied = StringBuffer();
      for (var i = 0; i < _selectedLines; i++) {
        copied.write(source[i]);
        if (i + 1 < _selectedLines) {
          copied.write(endings.endingAt(_synthetic(i, side), side));
        }
      }
      expect(
        copied.toString(),
        side == DiffSide.old ? fixture.expectedOld : fixture.expectedNew,
      );
      expect(endings.rangeComparisons, lessThanOrEqualTo(_comparisonLimit));
      debugPrint(
        'gutter $side: ${endings.rangeComparisons} hunk-range comparisons for $_selectedLines lines / $_hunks hunks',
      );
      // Backward/random requests use the same bound without restarting a scan.
      final before = endings.rangeComparisons;
      for (var i = _selectedLines - 1; i >= 0; i--) {
        expect(endings.endingAt(_synthetic(i, side), side), _ending(i));
      }
      expect(
        endings.rangeComparisons - before,
        lessThanOrEqualTo(_comparisonLimit),
      );
    });
  }

  test(
    'interleaved sides retain original metadata across ranges inside a hunk',
    () {
      const lines = [
        DiffLine(
          DiffLineKind.context,
          'a',
          oldNumber: 1,
          newNumber: 1,
          sourceLineEnding: '\r\n',
        ),
        DiffLine(
          DiffLineKind.removed,
          'old',
          oldNumber: 2,
          sourceLineEnding: '\r',
        ),
        DiffLine(
          DiffLineKind.added,
          'new',
          newNumber: 2,
          sourceLineEnding: '\n',
        ),
        DiffLine(
          DiffLineKind.context,
          'b',
          oldNumber: 3,
          newNumber: 3,
          sourceLineEnding: '\r\n',
        ),
        DiffLine(
          DiffLineKind.removed,
          'old2',
          oldNumber: 4,
          sourceLineEnding: '\n',
        ),
        DiffLine(
          DiffLineKind.added,
          'new2',
          newNumber: 4,
          sourceLineEnding: '\r',
        ),
      ];
      final endings = PatchLineEndings(
        const FileDiff(
          oldPath: 'a',
          newPath: 'a',
          kind: FileDiffKind.modified,
          oldText: 'a\r\nold\rb\r\nold2\n',
          newText: 'a\r\nnew\nb\r\nnew2\r',
          hunks: [
            DiffHunk(
              oldStart: 1,
              oldCount: 4,
              newStart: 1,
              newCount: 4,
              lines: lines,
            ),
          ],
        ),
      );
      for (final side in DiffSide.values) {
        for (var i = 0; i < 4; i++) {
          final expected = side == DiffSide.old
              ? ['\r\n', '\r', '\r\n', '\n']
              : ['\r\n', '\n', '\r\n', '\r'];
          expect(endings.endingAt(_synthetic(i, side), side), expected[i]);
        }
      }
    },
  );
}

DiffLine _synthetic(int index, DiffSide side) => DiffLine(
  DiffLineKind.context,
  '',
  oldNumber: side == DiffSide.old ? index + 1 : null,
  newNumber: side == DiffSide.newer ? index + 1 : null,
);

String _ending(int index) => ['\r\n', '\n', '\r'][index % 3];

({
  FileDiff file,
  List<String> older,
  List<String> newer,
  String expectedOld,
  String expectedNew,
})
_fixture() {
  final older = List.generate(_selectedLines, (i) => 'old$i');
  final newer = List.generate(_selectedLines, (i) => 'new$i');
  final hunks = [
    for (var h = 0; h < _hunks; h++)
      DiffHunk(
        oldStart: h * 2 + 1,
        oldCount: 2,
        newStart: h * 2 + 1,
        newCount: 2,
        lines: [
          for (var i = h * 2; i < h * 2 + 2; i++)
            DiffLine(
              DiffLineKind.removed,
              older[i],
              oldNumber: i + 1,
              sourceLineEnding: _ending(i),
            ),
          for (var i = h * 2; i < h * 2 + 2; i++)
            DiffLine(
              DiffLineKind.added,
              newer[i],
              newNumber: i + 1,
              sourceLineEnding: _ending(i),
            ),
        ],
      ),
  ];
  String text(List<String> source) => [
    for (var i = 0; i < source.length; i++)
      '${source[i]}${i + 1 < source.length ? _ending(i) : ''}',
  ].join();
  final expectedOld = text(older), expectedNew = text(newer);
  return (
    file: FileDiff(
      oldPath: 'a',
      newPath: 'a',
      kind: FileDiffKind.modified,
      oldText: expectedOld,
      newText: expectedNew,
      oldLines: older,
      newLines: newer,
      hunks: hunks,
    ),
    older: older,
    newer: newer,
    expectedOld: expectedOld,
    expectedNew: expectedNew,
  );
}
