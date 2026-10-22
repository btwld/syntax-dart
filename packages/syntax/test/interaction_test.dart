import 'package:syntax/syntax.dart';
import 'package:test/test.dart';

void main() {
  FileDiff source() => diffTexts(
    'one\r\nold\r\nthree\r\nfour\r\nfive\r\n',
    'one\r\nnew\r\nextra\r\nthree\r\nfour\r\nfive\r\n',
    id: 'f',
    path: 'a.dart',
    contextLines: 1,
  );
  test(
    'reverse line selection includes both whole endpoints and exact endings',
    () {
      final editor = EditorController(
        file: const SourceFile(
          id: 'a',
          path: 'a.dart',
          text: 'one\r\ntwo🙂\r\nthree\r\n',
        ),
      );
      addTearDown(editor.dispose);
      editor.selectLines(2, 0);
      final range = editor.selections.single;
      expect(range.anchor, greaterThan(range.active));
      expect(
        editor.document.text.substring(range.start, range.end),
        'one\r\ntwo🙂\r\nthree',
      );
      editor.selectLines(0, 2);
      expect(editor.selections.single.start, range.start);
      expect(editor.selections.single.end, range.end);
    },
  );
  test('cross-side ranges copy source in diff order in both display modes', () {
    final review = PatchController([source()]);
    addTearDown(review.dispose);
    for (final mode in DiffMode.values) {
      review.mode = mode;
      for (final selected in [
        const DiffSelection(
          'f',
          DiffSide.old,
          2,
          3,
          activeSide: DiffSide.newer,
        ),
        const DiffSelection(
          'f',
          DiffSide.newer,
          3,
          2,
          activeSide: DiffSide.old,
        ),
      ]) {
        review.select(selected);
        expect(review.selectedText(), 'old\r\nnew\r\nextra');
        expect(review.isLineSelected('f', DiffSide.old, 2), isTrue);
        expect(review.isLineSelected('f', DiffSide.newer, 3), isTrue);
        expect(review.isLineSelected('f', DiffSide.newer, 4), isFalse);
      }
    }
    review.select(null);
    expect(review.selectedText(), isEmpty);
  });
  test(
    'folded sections retain review state and reveal reopens the target',
    () async {
      final review = PatchController([source()], foldableHunks: true);
      addTearDown(review.dispose);
      review.select(const DiffSelection('f', DiffSide.newer, 2, 3));
      final selected = review.selectedText();
      review.setAnnotations([
        const ReviewAnnotation(
          id: 'note',
          fileId: 'f',
          side: DiffSide.newer,
          line: 2,
          data: 'Check this',
        ),
      ]);
      review.toggleHunk('f', 0);
      expect(
        review.layout.whereType<DiffHunkHeaderRow>().single.collapsed,
        isTrue,
      );
      expect(review.layout.rowForLine(0, 2), isNull);
      expect(review.selectedText(), selected);
      expect(review.annotations.single.data, 'Check this');
      review.mode = DiffMode.split;
      expect(review.isHunkCollapsed('f', 0), isTrue);
      expect(await review.revealLine('f', 2), isNotNull);
      expect(review.isHunkCollapsed('f', 0), isFalse);
      review.setHunksCollapsed(true);
      review.updateFile(source().copyWith(revision: 1));
      expect(review.isHunkCollapsed('f', 0), isFalse);
    },
  );
  test('context can be collapsed independently of source selection', () {
    final review = PatchController([source()], foldableHunks: true);
    addTearDown(review.dispose);
    final count = review.layout.length;
    review.select(const DiffSelection('f', DiffSide.newer, 2, 3));
    review.expandAll();
    expect(review.layout.length, greaterThan(count));
    review.collapseContext();
    expect(review.layout.length, count);
    expect(review.selectedText(), 'new\r\nextra');
  });
}
