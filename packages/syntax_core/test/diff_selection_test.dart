import 'package:syntax_core/syntax.dart';
import 'package:test/test.dart';

void main() {
  DiffSelection selection({
    String fileId = 'f',
    int revision = 7,
    DiffSide side = DiffSide.newer,
    int anchor = 4,
    int active = 2,
    DiffSide? activeSide,
  }) => DiffSelection(
    fileId: fileId,
    revision: revision,
    side: side,
    anchor: anchor,
    active: active,
    activeSide: activeSide,
  );

  group('DiffSelection', () {
    test(
      'normalizes inclusive bounds while preserving direction on each side',
      () {
        for (final side in DiffSide.values) {
          final reverse = selection(side: side);
          final forward = selection(side: side, anchor: 2, active: 4);
          expect((reverse.anchor, reverse.active), (4, 2));
          expect((forward.anchor, forward.active), (2, 4));
          expect((reverse.start, reverse.end), (2, 4));
          expect((forward.start, forward.end), (2, 4));
          expect(reverse.activeSide, side);
          expect(reverse.crossesSides, isFalse);
          expect(reverse, isNot(forward));
        }
      },
    );

    test('a single line includes line one', () {
      final range = selection(anchor: 1, active: 1);
      expect((range.start, range.end), (1, 1));
    });

    // Ported from code_review/test/interaction_test.dart:36. Copying itself
    // belongs to the controller; the value must retain both directed endpoints.
    test('preserves cross-side copying endpoints in either direction', () {
      final forward = selection(
        side: DiffSide.old,
        anchor: 2,
        active: 3,
        activeSide: DiffSide.newer,
      );
      final reverse = selection(
        side: DiffSide.newer,
        anchor: 3,
        active: 2,
        activeSide: DiffSide.old,
      );
      expect(forward.crossesSides, isTrue);
      expect(reverse.crossesSides, isTrue);
      expect(
        (forward.side, forward.anchor),
        (reverse.activeSide, reverse.active),
      );
      expect(
        (forward.activeSide, forward.active),
        (reverse.side, reverse.anchor),
      );
      expect((forward.start, forward.end), (reverse.start, reverse.end));
      expect(forward, isNot(reverse));
    });

    test('equal line numbers on different sides still cross sides', () {
      final range = selection(anchor: 2, active: 2, activeSide: DiffSide.old);
      expect(range.crossesSides, isTrue);
      expect((range.start, range.end), (2, 2));
    });

    test('numeric bounds do not reorder cross-side endpoints', () {
      final range = selection(
        side: DiffSide.old,
        anchor: 40,
        active: 2,
        activeSide: DiffSide.newer,
      );
      expect((range.side, range.anchor), (DiffSide.old, 40));
      expect((range.activeSide, range.active), (DiffSide.newer, 2));
      expect((range.start, range.end), (2, 40));
    });

    test('rejects nonpositive endpoints on either side', () {
      for (final side in DiffSide.values) {
        for (final invalid in [0, -1]) {
          expect(
            () => selection(side: side, anchor: invalid),
            throwsRangeError,
          );
          expect(
            () => selection(side: side, active: invalid),
            throwsRangeError,
          );
        }
      }
    });

    test('value equality includes revision, direction and both sides', () {
      final range = selection();
      final explicitSide = selection(activeSide: DiffSide.newer);
      expect(range, explicitSide);
      expect(range.hashCode, explicitSide.hashCode);
      expect({range, explicitSide}, hasLength(1));
      for (final different in [
        selection(fileId: 'other'),
        selection(revision: 8),
        selection(side: DiffSide.old),
        selection(activeSide: DiffSide.old),
        selection(anchor: 5),
        selection(active: 3),
        selection(anchor: 2, active: 4),
      ]) {
        expect(range, isNot(different));
      }
      expect(range, isNot('f'));
    });

    test(
      'reuses FileDiff identity and revision for custom and default IDs',
      () {
        for (final file in [
          diffTexts('old', 'new', path: 'a.dart', revision: 7),
          diffTexts('old', 'new', path: 'a.dart', id: 'custom', revision: 7),
        ]) {
          final range = selection(fileId: file.id, revision: file.revision);
          expect(range.fileId, file.id);
          expect(range.revision, file.revision);
          expect(range, isNot(selection(fileId: file.id, revision: 8)));
        }
      },
    );
  });
}
