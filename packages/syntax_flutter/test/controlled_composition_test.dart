import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'controlled_patch_test.dart' show collectGarbage;
import 'patch_composition_test.dart' show app, copy, gutter, select;

void main() {
  for (final mode in DiffMode.values) {
    testWidgets(
      'controlled slots share selection, folding and revisions $mode',
      (tester) async {
        final file = diffTexts(
          'old alpha\r\nold beta\r\nold gamma',
          'new alpha\r\nnew beta\r\nnew gamma',
          path: 'a.txt',
        );
        final controller = PatchController<String>([file], mode: mode);
        addTearDown(controller.dispose);
        final changes = <DiffSelection?>[];
        DiffSelectionDetails? details;
        controller.setAnnotations([
          DiffAnnotation(
            id: 'draft',
            fileId: file.id,
            revision: 0,
            side: DiffSide.newer,
            line: 2,
            data: 'Draft',
          ),
        ]);
        await tester.pumpWidget(
          app(
            PatchView<String>.controlled(
              controller: controller,
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              leading: const Text('Introduction'),
              canvasColor: const Color(0xff111111),
              sectionDecoration: BoxDecoration(border: Border.all()),
              fileLabelBuilder: (_, _) => const Text('Label'),
              fileFooterBuilder: (_, _, collapsed) =>
                  Text('Folded: $collapsed'),
              rowBelowBuilder: (_, row) => row.annotations.isEmpty
                  ? null
                  : Text(row.annotations.single.data),
              gutterBuilder: (_, line) =>
                  line.line == 2 ? const Text('!') : null,
              onSelectionChanged: changes.add,
              selectionActionBuilder: (_, value) {
                details = value;
                return const Text('Action');
              },
            ),
            height: 600,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Draft'), findsOneWidget);
        expect(find.text('Label'), findsOneWidget);
        // Give the patch keyboard focus before exercising its copy shortcut.
        await tester.tapAt(
          gutter(tester, 'new alpha', split: mode == DiffMode.split),
        );
        await tester.pumpAndSettle();
        final directed = DiffSelection(
          fileId: file.id,
          revision: 0,
          side: DiffSide.newer,
          anchor: 3,
          active: 1,
        );
        controller.select(directed);
        await tester.pumpAndSettle();
        expect(details!.selection, directed);
        expect(changes.last, directed);
        await copy(tester, 'new alpha\r\nnew beta\r\nnew gamma');
        controller.setHunkCollapsed(file.id, 0, true);
        await tester.pumpAndSettle();
        expect(find.text('Action'), findsNothing);
        expect(controller.selection, directed);
        controller.revealLine(file.id, DiffSide.newer, 1, revision: 0);
        await tester.pumpAndSettle();
        expect(find.text('Action'), findsOneWidget);
        expect(find.text('Draft'), findsOneWidget);
        final drag = await tester.startGesture(
          gutter(tester, 'old gamma', old: true, split: mode == DiffMode.split),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveTo(
          gutter(tester, 'old alpha', old: true, split: mode == DiffMode.split),
        );
        await drag.up();
        await tester.pumpAndSettle();
        expect(controller.selection!.anchor, 3);
        expect(controller.selection!.active, 1);
        expect(controller.selection!.side, DiffSide.old);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tapAt(
          gutter(tester, 'new beta', split: mode == DiffMode.split),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(controller.selection!.crossesSides, true);
        expect(details!.selection, controller.selection);
        // The old source has no final terminator; its diff boundary uses LF.
        expect(details!.selectedText, 'old gamma\nnew alpha\r\nnew beta');
        await copy(tester, 'old gamma\nnew alpha\r\nnew beta');
        await select(tester, 'new alpha', 1, 'new gamma', 2);
        expect(controller.selection, isNull);
        expect(changes.last, isNull);
        // Programmatic selection must supersede an existing native range too.
        controller.select(directed);
        await tester.pumpAndSettle();
        await copy(tester, 'new alpha\r\nnew beta\r\nnew gamma');
        controller.setCollapsed(file.id, true);
        await tester.pumpAndSettle();
        expect(find.text('Folded: true'), findsOneWidget);
        controller.setCollapsed(file.id, false);
        controller.setFiles([
          diffTexts(
            'old replacement',
            'new replacement\nsecond',
            path: 'a.txt',
            revision: 1,
          ),
        ]);
        await tester.pumpAndSettle();
        expect(controller.selection, isNull);
        expect(changes.last, isNull);
        expect(find.text('Draft'), findsNothing);
        expect(find.text('Action'), findsNothing);
        controller.select(
          DiffSelection(
            fileId: file.id,
            revision: 1,
            side: DiffSide.newer,
            anchor: 1,
            active: 2,
          ),
        );
        await tester.pumpAndSettle();
        await copy(tester, 'new replacement\nsecond');
        expectPlainTree(tester);
      },
    );
  }

  testWidgets('replacement releases populated copy and cross-side caches', (
    tester,
  ) async {
    final controller = PatchController<String>([]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        PatchView<String>.controlled(
          controller: controller,
          highlighter: Highlighter(),
          theme: githubDarkTheme,
          selectionActionBuilder: (_, details) => Text(details.selectedText),
        ),
      ),
    );
    // Match the existing controlled-patch GC regression: warm the mounted
    // cells before tracking subsequent replaced snapshots.
    _replaceSelected(controller, -1);
    await tester.pumpAndSettle();
    final replaced = <WeakReference<FileDiff>>[];
    for (var revision = 0; revision < 5; revision++) {
      replaced.add(_replaceSelected(controller, revision));
      await tester.pumpAndSettle();
      expect(
        find.text('old $revision\r\nnew $revision\r\ntail'),
        findsOneWidget,
      );
    }
    await tester.runAsync(collectGarbage);
    expect(replaced.take(3).map((file) => file.target), [
      isNull,
      isNull,
      isNull,
    ]);
  });

  for (final shrinkWrap in [false, true]) {
    testWidgets(
      'leading row offsets queued and repeated controlled reveal shrink=$shrinkWrap',
      (tester) async {
        final file = diffTexts(
          '',
          List.generate(300, (i) => 'line ${i + 1}').join('\n'),
          path: 'a.txt',
        );
        final controller = PatchController<void>([file]);
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
        final ranges = <(int, int)>[];
        await tester.pumpWidget(
          app(
            PatchView<void>.controlled(
              controller: controller,
              scrollController: scroll,
              highlighter: Highlighter(),
              theme: githubDarkTheme,
              leading: const SizedBox(height: 100, child: Text('Introduction')),
              shrinkWrap: shrinkWrap,
              onVisibleRange: (start, end) => ranges.add((start, end)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.text('line 200', findRichText: true);
        expect(target, findsOneWidget);
        final y = tester.getTopLeft(target).dy;
        expect(y, inInclusiveRange(0, 260));
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(target).dy, closeTo(y, 1));
        if (!shrinkWrap) expect(ranges, isNotEmpty);
        expectPlainTree(tester);
      },
    );
  }
}

WeakReference<FileDiff> _replaceSelected(
  PatchController<String> controller,
  int revision,
) {
  final file = diffTexts(
    'old $revision\r\ntail',
    'new $revision\r\ntail',
    path: 'a.txt',
    revision: revision,
  );
  controller.setFiles([file]);
  controller.select(
    DiffSelection(
      fileId: file.id,
      revision: revision,
      side: DiffSide.old,
      anchor: 1,
      activeSide: DiffSide.newer,
      active: 2,
    ),
  );
  return WeakReference(file);
}
