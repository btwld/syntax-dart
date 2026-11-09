import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show neutralApp, expectPlainTree;

class _TrackedController extends PatchController<String> {
  _TrackedController(super.files);
  bool get observed => hasListeners;
}

FileDiff added(String id, {int count = 300, int revision = 0}) => diffTexts(
  '',
  List.generate(count, (i) => '$id ${i + 1}').join('\n'),
  path: '$id.txt',
).copyWith(identity: id, revision: revision);

Widget view(
  PatchController<String> controller,
  ScrollController scroll, {
  HighlightExecutor? executor,
}) => neutralApp(
  PatchView<String>.controlled(
    controller: controller,
    scrollController: scroll,
    theme: githubDarkTheme,
    highlighter: Highlighter(languages: []),
    executor: executor,
    textStyle: const TextStyle(fontSize: 14, height: 1.5),
  ),
);

WeakReference<FileDiff> replace(
  PatchController<String> controller,
  int revision,
) {
  final file = added(
    'revision $revision',
    count: 4,
    revision: revision,
  ).copyWith(identity: 'a');
  controller.setFiles([file]);
  return WeakReference(file);
}

Future<void> collectGarbage() async {
  final barrier = reachabilityBarrier;
  final storage = <List<int>>[];
  while (reachabilityBarrier < barrier + 2) {
    await Future<void>.delayed(Duration.zero);
    storage.add(List.generate(30000, (n) => n));
    if (storage.length > 100) storage.removeAt(0);
  }
}

void main() {
  // Ported from code_review_flutter/test/review_patch_view_test.dart:225,243.
  for (final foldCurrent in [true, false]) {
    testWidgets(
      'folding ${foldCurrent ? 'the current file' : 'above the viewport'} retains the reader',
      (tester) async {
        final controller = PatchController<String>([added('a'), added('b')]);
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(view(controller, scroll));
        await tester.pumpAndSettle();
        controller.revealLine(
          foldCurrent ? 'a' : 'b',
          DiffSide.newer,
          150,
          revision: 0,
        );
        await tester.pumpAndSettle();
        final line = find.text(
          '${foldCurrent ? 'a' : 'b'} 150',
          findRichText: true,
        );
        expect(line, findsOneWidget);
        final before = tester.getTopLeft(line).dy;
        controller.setCollapsed('a', true);
        await tester.pumpAndSettle();
        if (foldCurrent) {
          final top = tester.getTopLeft(find.byType(IndexedCodeViewport)).dy;
          expect(
            (tester.getTopLeft(find.text('a.txt')).dy - top).abs(),
            lessThan(40),
          );
        } else {
          expect(line, findsOneWidget);
          expect(tester.getTopLeft(line).dy, closeTo(before, 1));
        }
        expectPlainTree(tester);
      },
    );
  }

  testWidgets('folding from a hunk-header anchor returns to its file header', (
    tester,
  ) async {
    final file = parsePatch(
      '--- a/a.txt\n+++ b/a.txt\n'
      '@@ -0,0 +1,150 @@\n'
      '${List.generate(150, (i) => '+a ${i + 1}\n').join()}'
      '@@ -0,0 +301 @@\n+a 301\n',
    ).single.copyWith(identity: 'a');
    final controller = PatchController<String>([file, added('b', count: 600)]);
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(view(controller, scroll));
    await tester.pumpAndSettle();

    // Jump near the second hunk, then align its header exactly with the
    // viewport. No reveal request is involved in establishing this anchor.
    scroll.jumpTo(3100);
    await tester.pumpAndSettle();
    final header = find.textContaining('@@ -0,0 +301 @@', findRichText: true);
    expect(header, findsOneWidget);
    final top = tester.getTopLeft(find.byType(IndexedCodeViewport)).dy;
    scroll.jumpTo(scroll.offset + tester.getTopLeft(header).dy - top);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, closeTo(top, 1));
    expect(scroll.offset, greaterThan(3000));

    controller.setCollapsed('a', true);
    await tester.pumpAndSettle();

    final fileHeader = find.text('a.txt');
    expect(fileHeader, findsOneWidget);
    expect(tester.getTopLeft(fileHeader).dy - top, inInclusiveRange(0, 40));
    expect(scroll.offset, lessThan(40));
    expect(
      find.text('b 150', findRichText: true),
      findsNothing,
      reason: 'The previous numeric offset must not expose the later file',
    );
    expectPlainTree(tester);
  });

  for (final reorder in [false, true]) {
    testWidgets(
      '${reorder ? 'reordering' : 'folding'} a preceding file preserves manual scrolling after reveal',
      (tester) async {
        final a = added('a');
        final b = added('b', count: 600);
        final controller = PatchController<String>([a, b]);
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(view(controller, scroll));
        await tester.pumpAndSettle();
        controller.revealLine('b', DiffSide.newer, 150, revision: 0);
        await tester.pumpAndSettle();
        final target = find.text('b 150', findRichText: true);
        expect(target, findsOneWidget);

        // Read a different part of the file without issuing another reveal.
        scroll.jumpTo(scroll.offset + 2100);
        await tester.pumpAndSettle();
        final reader = find.text('b 250', findRichText: true);
        expect(reader, findsOneWidget);
        expect(target, findsNothing);
        final before = tester.getTopLeft(reader).dy;
        final offset = scroll.offset;
        final request = tester
            .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
            .revealRequest;
        if (reorder) {
          controller.setFiles([b, a]);
        } else {
          controller.setCollapsed('a', true);
        }
        await tester.pumpAndSettle();

        expect(reader, findsOneWidget);
        expect(tester.getTopLeft(reader).dy, closeTo(before, 1));
        expect(scroll.offset, lessThan(offset));
        expect(
          target,
          findsNothing,
          reason: 'The completed reveal must not run again',
        );
        expect(
          tester
              .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
              .revealRequest,
          request,
        );
        expectPlainTree(tester);
      },
    );
  }

  testWidgets('swapping controllers refreshes an identical pending reveal', (
    tester,
  ) async {
    final file = added('a');
    final first = PatchController<String>([file]);
    final second = PatchController<String>([file]);
    final scroll = ScrollController();
    final highlighter = Highlighter(languages: []);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(scroll.dispose);
    first.revealLine('a', DiffSide.newer, 150, revision: 0);
    second.revealLine('a', DiffSide.newer, 150, revision: 0);
    var current = first;
    late StateSetter update;
    await tester.pumpWidget(
      neutralApp(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PatchView<String>.controlled(
              controller: current,
              scrollController: scroll,
              theme: githubDarkTheme,
              highlighter: highlighter,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = find.text('a 150', findRichText: true);
    expect(target, findsOneWidget);
    final request = tester
        .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
        .revealRequest;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(target, findsNothing);

    update(() => current = second);
    await tester.pumpAndSettle();
    expect(target, findsOneWidget);
    expect(
      tester
          .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
          .revealRequest,
      greaterThan(request),
    );
    expectPlainTree(tester);
  });

  testWidgets('queued and repeated reveals reach distant rows in both modes', (
    tester,
  ) async {
    for (final mode in DiffMode.values) {
      final controller = PatchController<String>([
        added('a', count: 10000),
      ], mode: mode);
      final scroll = ScrollController();
      controller.setHunkCollapsed('a', 0, true);
      expect(
        controller.revealLine('a', DiffSide.newer, 9000, revision: 0),
        true,
      );
      await tester.pumpWidget(view(controller, scroll));
      await tester.pumpAndSettle();
      final target = find.text('a 9000', findRichText: true);
      expect(target, findsOneWidget);
      final first = tester
          .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
          .revealRequest;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(target, findsNothing);
      controller.revealLine('a', DiffSide.newer, 9000, revision: 0);
      await tester.pumpAndSettle();
      expect(target, findsOneWidget);
      expect(
        tester
            .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
            .revealRequest,
        greaterThan(first),
      );
      expectPlainTree(tester);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      scroll.dispose();
    }
  });

  testWidgets(
    'annotation updates preserve scroll and layout without re-revealing',
    (tester) async {
      final file = added('a');
      final controller = PatchController<String>([file]);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(view(controller, scroll));
      await tester.pumpAndSettle();
      controller.revealLine('a', DiffSide.newer, 150, revision: 0);
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.offset + 100);
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      final layout = tester
          .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
          .layoutKey;
      controller.setAnnotations([
        DiffAnnotation(
          id: 'note',
          fileId: 'a',
          revision: 0,
          side: DiffSide.newer,
          line: 150,
          data: 'Payload',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 0.01));
      expect(
        tester
            .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
            .layoutKey,
        layout,
      );
    },
  );

  testWidgets(
    'headers and context gaps use controller-owned folding under WidgetsApp',
    (tester) async {
      final file = diffTexts(
        'before\nold\nafter',
        'before\nnew\nafter',
        path: 'a.txt',
        contextLines: 0,
      ).copyWith(identity: 'a');
      final controller = PatchController<String>([file]);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(view(controller, scroll));
      await tester.pumpAndSettle();
      await tester.tap(find.text('a.txt'));
      await tester.pumpAndSettle();
      expect(controller.isCollapsed('a'), true);
      expect(find.text('new', findRichText: true), findsNothing);
      await tester.tap(find.text('a.txt'));
      await tester.pumpAndSettle();
      expect(controller.isCollapsed('a'), false);
      final gap = find.textContaining('unchanged', findRichText: true).first;
      await tester.tap(gap);
      await tester.pumpAndSettle();
      expect(find.text('before', findRichText: true), findsOneWidget);
      expectPlainTree(tester);
    },
  );

  testWidgets('removal and revision replacement clear pending reveal rows', (
    tester,
  ) async {
    final file = added('a');
    final controller = PatchController<String>([file]);
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    controller.revealLine('a', DiffSide.newer, 200, revision: 0);
    await tester.pumpWidget(view(controller, scroll));
    await tester.pumpAndSettle();
    controller.setFiles([file.copyWith(revision: 1)]);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
          .revealRow,
      isNull,
    );
    controller.revealLine('a', DiffSide.newer, 250, revision: 1);
    controller.setFiles([]);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IndexedCodeViewport>(find.byType(IndexedCodeViewport))
          .revealRow,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final parentScroll in [true, false]) {
    testWidgets(
      'shrink-wrapped reveal scrolls ${parentScroll ? 'the parent' : 'its own viewport'}',
      (tester) async {
        final controller = PatchController<String>([added('a')]);
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        final patch = PatchView<String>.controlled(
          controller: controller,
          theme: githubDarkTheme,
          highlighter: Highlighter(languages: []),
          shrinkWrap: true,
          scrollController: parentScroll ? null : scroll,
        );
        controller.revealLine('a', DiffSide.newer, 200, revision: 0);
        await tester.pumpWidget(
          neutralApp(
            parentScroll
                ? SingleChildScrollView(controller: scroll, child: patch)
                : patch,
          ),
        );
        await tester.pumpAndSettle();
        final line = find.text('a 200', findRichText: true);
        expect(scroll.offset, greaterThan(1000));
        expect(tester.getTopLeft(line).dy, closeTo(0, 1));
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        controller.revealLine('a', DiffSide.newer, 200, revision: 0);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(line).dy, closeTo(0, 1));
        expectPlainTree(tester);
      },
    );
  }

  testWidgets(
    'swapping controllers detaches listeners and uses the new source',
    (tester) async {
      final a = _TrackedController([added('a', count: 3)]);
      final b = _TrackedController([added('b', count: 3)]);
      final scroll = ScrollController();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(scroll.dispose);
      var current = a;
      late StateSetter update;
      await tester.pumpWidget(
        neutralApp(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return PatchView<String>.controlled(
                controller: current,
                scrollController: scroll,
                theme: githubDarkTheme,
                highlighter: Highlighter(languages: []),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => current = b);
      await tester.pumpAndSettle();
      expect(a.observed, false);
      expect(b.observed, true);
      a.setFiles([]);
      await tester.pumpAndSettle();
      expect(find.text('b 1', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(b.observed, false);
    },
  );

  // Ported from code_review_flutter/test/review_patch_view_test.dart:975.
  testWidgets('controlled updates release replaced file revisions', (
    tester,
  ) async {
    final controller = PatchController<String>([]);
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    replace(controller, 1);
    await tester.pumpWidget(view(controller, scroll));
    await tester.pumpAndSettle();
    final replaced = <WeakReference<FileDiff>>[];
    for (final revision in [2, 3, 4, 5]) {
      replaced.add(replace(controller, revision));
      await tester.pumpAndSettle();
    }
    expect(find.text('revision 5 1', findRichText: true), findsOneWidget);
    await tester.runAsync(collectGarbage);
    expect(replaced.take(2).map((file) => file.target), [isNull, isNull]);
  });

  testWidgets(
    'controlled replacement cancels work through the existing scheduler',
    (tester) async {
      final pending = <Completer<HighlightWindowResult>>[];
      final cancellations = <HighlightCancellation>[];
      final inputs = <HighlightWindowRequest>[];
      Future<HighlightWindowResult> executor(
        HighlightWindowRequest input, {
        required Highlighter highlighter,
        required SyntaxTheme theme,
        required HighlightCancellation cancellation,
      }) {
        inputs.add(input);
        cancellations.add(cancellation);
        final job = Completer<HighlightWindowResult>();
        pending.add(job);
        return job.future;
      }

      final controller = PatchController<String>([added('a')]);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(view(controller, scroll, executor: executor));
      expect(inputs, hasLength(1));
      controller.setAnnotations([
        DiffAnnotation(
          id: 'note',
          fileId: 'a',
          revision: 0,
          side: DiffSide.newer,
          line: 1,
          data: 'Payload',
        ),
      ]);
      await tester.pump();
      expect(cancellations.single.isCancelled, false);
      controller.setFiles([added('replacement', revision: 1)]);
      await tester.pump();
      expect(cancellations.single.isCancelled, true);
      expect(
        inputs,
        hasLength(1),
        reason: 'Cancelled work still serializes the worker',
      );
      pending[0].complete(
        HighlightWindowResult(
          request: inputs[0],
          theme: githubDarkTheme,
          grammarRevision: 0,
          ranges: const [],
        ),
      );
      await tester.pump();
      expect(inputs, hasLength(2));
      expect(inputs[1].revision, 1);
      await tester.pumpWidget(const SizedBox());
      expect(cancellations[1].isCancelled, true);
      pending[1].complete(
        HighlightWindowResult(
          request: inputs[1],
          theme: githubDarkTheme,
          grammarRevision: 0,
          ranges: const [],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
