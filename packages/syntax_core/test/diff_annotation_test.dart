import 'package:syntax_core/syntax.dart';
import 'package:test/test.dart';

void main() {
  DiffSelection selection({String fileId = 'f', int revision = 7}) =>
      DiffSelection(
        fileId: fileId,
        revision: revision,
        side: DiffSide.old,
        anchor: 4,
        active: 2,
        activeSide: DiffSide.newer,
      );

  DiffAnnotation<String> annotation({
    String id = 'note',
    String fileId = 'f',
    int revision = 7,
    DiffSide side = DiffSide.newer,
    int line = 1,
    String data = 'Check this',
    DiffSelection? sourceSelection,
  }) => DiffAnnotation(
    id: id,
    fileId: fileId,
    revision: revision,
    side: side,
    line: line,
    data: data,
    sourceSelection: sourceSelection,
  );

  group('DiffAnnotation', () {
    test('attaches unchanged application data without a source range', () {
      final payload = <String, Object>{'severity': 2};
      final file = diffTexts('old', 'new', id: 'f', revision: 7);
      final note = DiffAnnotation(
        id: 'diagnostic',
        fileId: file.id,
        revision: file.revision,
        side: DiffSide.old,
        line: 1,
        data: payload,
      );
      expect(note.data, same(payload));
      expect((note.fileId, note.revision), (file.id, file.revision));
      expect((note.side, note.line), (DiffSide.old, 1));
      expect(note.sourceSelection, isNull);
    });

    // Ported from code_review/test/comment_source_test.dart. Display placement
    // remains independent of the original directed, possibly cross-side range.
    test('preserves source range independently of display side and line', () {
      final ranges = [
        selection(),
        DiffSelection(
          fileId: 'f',
          revision: 7,
          side: DiffSide.newer,
          anchor: 4,
          active: 2,
        ),
      ];
      for (final range in ranges) {
        for (final side in DiffSide.values) {
          final note = annotation(side: side, line: 10, sourceSelection: range);
          expect(note.sourceSelection, same(range));
          expect((note.side, note.line), (side, 10));
          expect((range.anchor, range.active), (4, 2));
        }
      }
    });

    test('rejects empty annotation IDs and nonpositive display lines', () {
      expect(() => annotation(id: ''), throwsArgumentError);
      for (final invalid in [0, -1]) {
        expect(() => annotation(line: invalid), throwsRangeError);
      }
    });

    test('rejects a source range belonging to another file', () {
      expect(
        () => annotation(sourceSelection: selection(fileId: 'other')),
        throwsArgumentError,
      );
    });

    test(
      'rejects stale and future revisions even at coincident coordinates',
      () {
        for (final revision in [6, 8]) {
          expect(
            () => annotation(sourceSelection: selection(revision: revision)),
            throwsArgumentError,
          );
        }
        final range = selection();
        expect(annotation(sourceSelection: range).sourceSelection, same(range));
      },
    );

    test('value equality includes payload and original selection', () {
      final note = annotation(sourceSelection: selection());
      final equal = annotation(sourceSelection: selection());
      expect(note, equal);
      expect(note.hashCode, equal.hashCode);
      expect({note, equal}, hasLength(1));
      for (final different in [
        annotation(id: 'other', sourceSelection: selection()),
        annotation(fileId: 'other'),
        annotation(revision: 8, sourceSelection: selection(revision: 8)),
        annotation(side: DiffSide.old, sourceSelection: selection()),
        annotation(line: 2, sourceSelection: selection()),
        annotation(data: 'Different', sourceSelection: selection()),
        annotation(),
      ]) {
        expect(note, isNot(different));
      }
      expect(note, isNot('note'));
    });

    test('payload equality is symmetric across generic types', () {
      final narrow = annotation();
      final wide = DiffAnnotation<Object?>(
        id: narrow.id,
        fileId: narrow.fileId,
        revision: narrow.revision,
        side: narrow.side,
        line: narrow.line,
        data: narrow.data,
      );
      expect(narrow == wide, isTrue);
      expect(wide == narrow, isTrue);
      expect(narrow.hashCode, wide.hashCode);
      final nullable = DiffAnnotation<String?>(
        id: 'empty',
        fileId: 'f',
        revision: 0,
        side: DiffSide.newer,
        line: 1,
        data: null,
      );
      expect(nullable.data, isNull);
    });
  });
}
