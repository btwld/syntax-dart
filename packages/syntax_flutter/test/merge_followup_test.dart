import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app, copy, select, selection;

void main() {
  for (final (shrinkWrap, parentScroll) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    testWidgets(
      'controlled sticky reveal clears header shrink=$shrinkWrap parent=$parentScroll',
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
        final patch = PatchView<void>.controlled(
          controller: controller,
          theme: githubDarkTheme,
          highlighter: Highlighter(),
          scrollController: parentScroll ? null : scroll,
          shrinkWrap: shrinkWrap,
          stickyHeaders: true,
          leading: const SizedBox(height: 90, child: Text('Introduction')),
          headerBuilder: (_, _, _, _) => const SizedBox(
            key: ValueKey('header'),
            height: 80,
            child: Text('Pinned header'),
          ),
          fileLabelBuilder: (_, _) => const SizedBox(
            key: ValueKey('label'),
            height: 24,
            child: Text('File label'),
          ),
          sectionDecoration: BoxDecoration(border: Border.all(width: 2)),
        );
        await tester.pumpWidget(
          app(
            parentScroll
                ? SingleChildScrollView(controller: scroll, child: patch)
                : patch,
            height: 320,
          ),
        );
        await tester.pumpAndSettle();
        void expectRevealed() {
          final row = tester.getRect(find.text('line 200', findRichText: true));
          final header = tester.getRect(
            find.byKey(const ValueKey('header')).first,
          );
          final label = tester.getRect(
            find.byKey(const ValueKey('label')).first,
          );
          debugPrint(
            'sticky shrink=$shrinkWrap parent=$parentScroll: row=$row header=$header label=$label',
          );
          expect(row.top, greaterThanOrEqualTo(header.bottom));
          expect(row.top, greaterThanOrEqualTo(label.bottom));
          expect(row.top, greaterThanOrEqualTo(0));
          expect(row.bottom, lessThanOrEqualTo(320));
        }

        expectRevealed();
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
        await tester.pumpAndSettle();
        expectRevealed();
        expectPlainTree(tester);
      },
    );
  }

  for (final mode in DiffMode.values) {
    testWidgets('equal source lists retain native selection $mode', (
      tester,
    ) async {
      var file = diffTexts('', 'alpha\nbeta\ngamma', path: 'a.txt');
      final highlighter = Highlighter();
      late StateSetter update;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return PatchView<void>(
                files: [file],
                theme: githubDarkTheme,
                highlighter: highlighter,
                mode: mode,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await select(tester, 'alpha', 1, 'gamma', 2);
      expect(
        selection(tester).getSelectedContent()!.plainText,
        'lpha\nbeta\nga',
      );
      update(() {});
      await tester.pumpAndSettle();
      expect(
        selection(tester).getSelectedContent()?.plainText,
        'lpha\nbeta\nga',
      );
      await copy(tester, 'lpha\nbeta\nga');
      update(
        () => file = diffTexts(
          '',
          'replacement\nsource',
          path: 'a.txt',
          revision: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(selection(tester).getSelectedContent(), isNull);
      expect(selection(tester).retainedRows.value, isEmpty);
      expectPlainTree(tester);
    });
  }

  for (final shrinkWrap in [false, true]) {
    testWidgets('2000 short hunks reuse row indexes shrink=$shrinkWrap', (
      tester,
    ) async {
      final file = FileDiff(
        oldPath: 'a.txt',
        newPath: 'a.txt',
        kind: FileDiffKind.modified,
        hunks: [
          for (var i = 1; i <= 2000; i++)
            DiffHunk(
              oldStart: i,
              oldCount: 0,
              newStart: i,
              newCount: 1,
              lines: [DiffLine(DiffLineKind.added, 'line $i', newNumber: i)],
            ),
        ],
      );
      final controller = PatchController<void>([file]);
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      final layout = controller.layout;
      final pending = Completer<HighlightWindowResult>();
      var sourceBuilds = 0;
      final builtLines = <int>{};
      await tester.pumpWidget(
        app(
          PatchView<void>.controlled(
            controller: controller,
            scrollController: scroll,
            shrinkWrap: shrinkWrap,
            selectable: false,
            theme: githubDarkTheme,
            highlighter: Highlighter(),
            executor:
                (
                  request, {
                  required highlighter,
                  required theme,
                  required cancellation,
                }) => pending.future,
            rowBelowBuilder: (_, row) {
              sourceBuilds++;
              builtLines.add((row.row as DiffLineRow).line.newNumber!);
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugPrint(
        '2000 hunks shrink=$shrinkWrap: source builds=$sourceBuilds coordinate lookups=${layout.debugRowForLineCalls}',
      );
      expect(sourceBuilds, greaterThan(0));
      // The indexed viewport may restore each mounted row's stable key;
      // source cells themselves must not add coordinate lookups on each build.
      final builtCells = builtLines.length;
      expect(
        layout.debugRowForLineCalls,
        shrinkWrap ? 0 : lessThanOrEqualTo(builtCells),
      );
      if (shrinkWrap) {
        expect(sourceBuilds, greaterThanOrEqualTo(2000));
      } else {
        expect(sourceBuilds, lessThan(100));
        final before = layout.debugRowForLineCalls;
        scroll.jumpTo(scroll.position.maxScrollExtent - 150);
        await tester.pumpAndSettle();
        expect(builtLines.any((line) => line >= 1900), isTrue);
        debugPrint(
          'late scroll: source builds=$sourceBuilds coordinate lookups=${layout.debugRowForLineCalls - before}',
        );
        expect(
          layout.debugRowForLineCalls - before,
          lessThanOrEqualTo(sourceBuilds),
        );
      }
      expectPlainTree(tester);
    });
  }
}
