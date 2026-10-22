import 'package:syntax/syntax.dart';
import 'package:test/test.dart';

ReviewThread discussion(String id, {bool resolved = false}) => ReviewThread(
  id: id,
  resolved: resolved,
  comments: [ReviewComment(id: id, author: 'Reviewer', body: id)],
);

void main() {
  test(
    'file ranges use UTF-16 half-open boundaries and independent anchors',
    () {
      final editor = EditorController(
        file: const SourceFile(
          id: 'f',
          path: 'f.txt',
          text: '😀a\r\nb\rc\n\nend',
        ),
      );
      editor.setAnnotations([
        LineAnnotation(
          id: 'range',
          start: 2,
          end: 7,
          data: discussion('range'),
        ),
        LineAnnotation(
          id: 'point',
          start: 9,
          end: 9,
          data: discussion('point'),
        ),
      ]);
      final nav = CommentNavigationController.file(
        editor,
        annotationLine: (a) => editor.document.positionAt(a.end).line,
      );
      addTearDown(() {
        nav.dispose();
        editor.dispose();
      });
      nav.select('f', 'range');
      expect(nav.current!.line, 2);
      expect(nav.current!.sourceRange!.start, const DocumentPosition(0, 2));
      expect(
        [for (var i = 0; i < 5; i++) nav.isSourceLineActive('f', i)],
        [true, true, false, false, false],
      );
      expect(nav.isSourceLineActive('other', 0), isFalse);
      expect(nav.isSourceLineActive('f', 0, side: DiffSide.old), isFalse);
      expect(nav.isSourceLineActive('f', 0, sourceRevision: 99), isFalse);
      nav.select('f', 'point');
      expect(nav.isSourceLineActive('f', 3), isTrue);
      expect(nav.isSourceLineActive('f', 2), isFalse);
      nav.filter = CommentThreadFilter.resolved;
      expect(nav.isSourceLineActive('f', 3), isFalse);
    },
  );

  test('edited file annotations remap without painting obsolete revisions', () {
    final editor = EditorController(
      file: const SourceFile(id: 'f', path: 'f.txt', text: 'one\ntwo\nthree'),
    );
    editor.setAnnotations([
      LineAnnotation(id: 'a', start: 4, end: 7, data: discussion('a')),
    ]);
    final nav = CommentNavigationController.file(editor);
    addTearDown(() {
      nav.dispose();
      editor.dispose();
    });
    nav.select('f', 'a');
    editor.applyEdits([const OffsetEdit(0, 0, 'zero\n')]);
    expect(nav.current, isNull);
    nav.select('f', 'a');
    expect(nav.isSourceLineActive('f', 1), isFalse);
    expect(nav.isSourceLineActive('f', 2, sourceRevision: 1), isTrue);
    expect(nav.isSourceLineActive('f', 2, sourceRevision: 0), isFalse);
    editor.setAnnotations([]);
    expect(nav.isSourceLineActive('f', 2), isFalse);
  });

  for (final mode in DiffMode.values) {
    test(
      'diff ranges retain sides and direction in $mode without selecting',
      () async {
        final patch = PatchController([
          diffTexts(
            'a\nb\nc\nd\ne',
            'a\nx\ny\nz\nd\ne',
            id: 'f',
            path: 'f.txt',
          ),
        ], mode: mode);
        const ranges = [
          DiffSelection('f', DiffSide.newer, 4, 2),
          DiffSelection('f', DiffSide.old, 2, 4, activeSide: DiffSide.newer),
          DiffSelection('f', DiffSide.newer, 4, 2, activeSide: DiffSide.old),
        ];
        patch.setAnnotations([
          for (var i = 0; i < ranges.length; i++)
            ReviewAnnotation(
              id: '$i',
              fileId: 'f',
              side: DiffSide.newer,
              line: 4,
              sourceSelection: ranges[i],
              data: discussion('$i'),
            ),
          ReviewAnnotation(
            id: 'anchor',
            fileId: 'f',
            side: DiffSide.old,
            line: 5,
            data: discussion('anchor', resolved: true),
          ),
        ]);
        final nav = CommentNavigationController.patch(patch);
        addTearDown(() {
          nav.dispose();
          patch.dispose();
        });
        for (var i = 0; i < ranges.length; i++) {
          nav.select('f', '$i');
          expect(patch.selection, isNull);
          for (final side in DiffSide.values) {
            final actual = [
              for (var line = 0; line < 6; line++)
                nav.isSourceLineActive('f', line, side: side),
            ];
            expect(
              actual,
              side == DiffSide.old
                  ? (i == 0
                        ? [false, false, false, false, false, false]
                        : [false, true, true, false, false, false])
                  : [false, true, true, true, false, false],
            );
          }
        }
        patch.select(const DiffSelection('f', DiffSide.newer, 5, 6));
        final copied = patch.selectedText(), selection = patch.selection;
        await nav.next();
        expect(nav.current!.annotationId, 'anchor');
        expect(nav.isSourceLineActive('f', 4, side: DiffSide.old), isTrue);
        expect(nav.isSourceLineActive('f', 4, side: DiffSide.newer), isFalse);
        expect(patch.selectedText(), copied);
        expect(patch.selection, same(selection));
        nav.filter = CommentThreadFilter.unresolved;
        expect(nav.isSourceLineActive('f', 4, side: DiffSide.old), isFalse);
      },
    );
  }

  test('invalid annotation ranges are rejected atomically', () {
    final patch = PatchController([diffTexts('a', 'b', id: 'f', path: 'f')]);
    addTearDown(patch.dispose);
    final original = patch.annotations;
    for (final range in [
      const DiffSelection('other', DiffSide.newer, 1, 1),
      const DiffSelection('f', DiffSide.newer, 0, 1),
    ]) {
      expect(
        () => patch.setAnnotations([
          ReviewAnnotation(
            id: 'a',
            fileId: 'f',
            side: DiffSide.newer,
            line: 1,
            sourceSelection: range,
            data: discussion('a'),
          ),
        ]),
        throwsArgumentError,
      );
      expect(patch.annotations, same(original));
    }
  });
}
