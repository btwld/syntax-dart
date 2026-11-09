import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

FileDiff source() => diffTexts(
  'before\r\nold\r\nafter\r\ntail\r\n',
  'before\r\nnew\r\nextra\r\nafter\r\ntail\r\n',
  path: 'a.txt',
  contextLines: 0,
).copyWith(identity: 'f');

DiffSelection selection({int revision = 0}) => DiffSelection(
  fileId: 'f',
  revision: revision,
  side: DiffSide.newer,
  anchor: 3,
  active: 2,
);

DiffAnnotation<String> annotation({int revision = 0, String id = 'note'}) =>
    DiffAnnotation(
      id: id,
      fileId: 'f',
      revision: revision,
      side: DiffSide.newer,
      line: 2,
      data: 'Check this',
    );

void main() {
  // Ported from code_review/test/interaction_test.dart:67. Editing and loading
  // are deliberately excluded from the reduced read-only controller.
  test('folded sections retain state and reveal reopens only the target', () {
    final controller = PatchController<String>([source()]);
    addTearDown(controller.dispose);
    final selected = selection();
    controller.select(selected);
    controller.setAnnotations([annotation()]);
    controller.setHunkCollapsed('f', 0, true);
    expect(
      controller.layout.whereType<DiffHunkHeaderRow>().single.collapsed,
      true,
    );
    expect(controller.layout.rowForLine(0, 2), isNull);
    expect(controller.selection, same(selected));
    expect(controller.annotations.single.data, 'Check this');
    controller.mode = DiffMode.split;
    expect(
      controller.layout.whereType<DiffHunkHeaderRow>().single.collapsed,
      true,
    );
    controller.setCollapsed('f', true);
    expect(controller.revealLine('f', DiffSide.newer, 2, revision: 0), true);
    expect(controller.isCollapsed('f'), false);
    expect(controller.layout.rowForLine(0, 2), isNotNull);
    expect(controller.selection, same(selected));
    expect(controller.annotations.single.data, 'Check this');
  });

  test(
    'annotation-only changes retain layout and directed cross-side selection',
    () {
      final controller = PatchController<String>([source()]);
      addTearDown(controller.dispose);
      final selected = DiffSelection(
        fileId: 'f',
        revision: 0,
        side: DiffSide.newer,
        activeSide: DiffSide.old,
        anchor: 3,
        active: 2,
      );
      controller.select(selected);
      final layout = controller.layout;
      controller.setAnnotations([annotation()]);
      expect(controller.layout, same(layout));
      expect(controller.selection, same(selected));
      expect(controller.selection!.crossesSides, true);
      expect(() => controller.files.clear(), throwsUnsupportedError);
      expect(() => controller.annotations.clear(), throwsUnsupportedError);
    },
  );

  test('reordering translates stable file IDs to layout indices', () {
    final a = source();
    final b = source().copyWith(identity: 'b');
    final controller = PatchController<String>([a, b]);
    addTearDown(controller.dispose);
    controller.setCollapsed('f', true);
    controller.setHunkCollapsed('b', 0, true);
    controller.setFiles([b, a]);
    final headers = controller.layout.whereType<DiffFileHeaderRow>().toList();
    expect(headers.map((h) => h.collapsed), [false, true]);
    expect(controller.layout.whereType<DiffHunkHeaderRow>().single.file, 0);
    expect(controller.revealLine('b', DiffSide.old, 2, revision: 0), true);
    expect(controller.layout.rowForLine(0, 2, oldSide: true), isNotNull);
    expect(controller.isCollapsed('f'), true);
  });

  test(
    'revision replacement clears coordinates and hunk folding, keeps file folding',
    () {
      final file = source();
      final controller = PatchController<String>([file]);
      addTearDown(controller.dispose);
      controller.select(selection());
      controller.setAnnotations([annotation()]);
      controller.revealLine('f', DiffSide.newer, 2, revision: 0);
      controller.setHunkCollapsed('f', 0, true);
      controller.setCollapsed('f', true);
      controller.setFiles([file.copyWith(revision: 1)]);
      expect(controller.selection, isNull);
      expect(controller.annotations, isEmpty);
      expect(controller.isCollapsed('f'), true);
      controller.setCollapsed('f', false);
      expect(controller.layout.rowForLine(0, 2), isNotNull);
      expect(controller.revealLine('f', DiffSide.newer, 2, revision: 0), false);
      expect(() => controller.select(selection()), throwsArgumentError);
      controller.setAnnotations([
        annotation(),
        annotation(revision: 1, id: 'current'),
      ]);
      expect(controller.annotations.single.id, 'current');
    },
  );

  // Ported from code_review/test/review_regression_test.dart:480.
  test(
    'removing a revealed file clears its navigation and dependent state',
    () {
      final controller = PatchController<String>([source()]);
      addTearDown(controller.dispose);
      controller.select(selection());
      controller.setAnnotations([annotation()]);
      controller.revealLine('f', DiffSide.newer, 2, revision: 0);
      controller.setFiles([]);
      expect(controller.layout, isEmpty);
      expect(controller.selection, isNull);
      expect(controller.annotations, isEmpty);
      expect(controller.revealLine('f', DiffSide.newer, 2, revision: 0), false);
      controller.setFiles([source()]);
      expect(controller.isCollapsed('f'), false);
    },
  );

  for (final side in DiffSide.values) {
    test('reveal opens only the enclosing context gap on $side', () {
      final controller = PatchController<void>([source()]);
      addTearDown(controller.dispose);
      final line = side == DiffSide.old ? 4 : 5;
      final gaps = controller.layout.whereType<DiffGapRow>().length;
      expect(
        controller.layout.rowForLine(0, line, oldSide: side == DiffSide.old),
        isNull,
      );
      expect(controller.revealLine('f', side, line, revision: 0), true);
      expect(
        controller.layout.rowForLine(0, line, oldSide: side == DiffSide.old),
        isNotNull,
      );
      expect(controller.layout.whereType<DiffGapRow>().length, gaps - 1);
    });
  }

  test(
    'partial patches and unavailable targets fail without changing layout',
    () {
      final file = parsePatch(
        '--- a/f\n+++ b/f\n@@ -10 +10 @@\n-old\n+new\n',
      ).single;
      final controller = PatchController<void>([file]);
      addTearDown(controller.dispose);
      controller.setCollapsed(file.id, true);
      final layout = controller.layout;
      for (final line in [0, 1, 9, 11, 200]) {
        expect(
          controller.revealLine(file.id, DiffSide.old, line, revision: 0),
          false,
        );
      }
      expect(
        controller.revealLine(file.id, DiffSide.old, 10, revision: 1),
        false,
      );
      expect(controller.layout, same(layout));
      expect(controller.isCollapsed(file.id), true);
      expect(
        controller.revealLine(file.id, DiffSide.old, 10, revision: 0),
        true,
      );
      expect(controller.layout.rowForLine(0, 10, oldSide: true), isNotNull);
    },
  );

  test('repeated reveal notifies without replacing an unchanged layout', () {
    final controller = PatchController<void>([source()]);
    addTearDown(controller.dispose);
    controller.revealLine('f', DiffSide.newer, 2, revision: 0);
    final layout = controller.layout;
    var changes = 0;
    controller.addListener(() => changes++);
    controller.revealLine('f', DiffSide.newer, 2, revision: 0);
    controller.revealLine('f', DiffSide.newer, 2, revision: 0);
    expect(controller.layout, same(layout));
    expect(changes, 2);
  });

  test('revealing one hunk leaves other folded sections closed', () {
    final file = diffTexts(
      'old\na\nb\nc\nold',
      'new\na\nb\nc\nnew',
      path: 'f',
      contextLines: 0,
    ).copyWith(identity: 'f');
    final controller = PatchController<void>([file]);
    addTearDown(controller.dispose);
    controller.setHunkCollapsed('f', 0, true);
    controller.setHunkCollapsed('f', 1, true);
    controller.revealLine('f', DiffSide.newer, 5, revision: 0);
    expect(controller.layout.rowForLine(0, 1), isNull);
    expect(controller.layout.rowForLine(0, 5), isNotNull);
    expect(
      controller.layout.whereType<DiffHunkHeaderRow>().map((h) => h.collapsed),
      [true, false],
    );
  });

  test('invalid inputs are atomic and no-op updates do not notify', () {
    final file = source();
    final controller = PatchController<String>([file]);
    addTearDown(controller.dispose);
    var changes = 0;
    controller.addListener(() => changes++);
    expect(() => controller.setFiles([file, file]), throwsArgumentError);
    expect(() => controller.setCollapsed('missing', true), throwsArgumentError);
    expect(() => controller.setHunkCollapsed('f', 10, true), throwsRangeError);
    expect(
      () => controller.setAnnotations([annotation(), annotation()]),
      throwsArgumentError,
    );
    expect(controller.files, [file]);
    controller.setFiles([file]);
    controller.setAnnotations([]);
    controller.select(null);
    controller.mode = DiffMode.unified;
    controller.setCollapsed('f', false);
    expect(changes, 0);
  });
}
