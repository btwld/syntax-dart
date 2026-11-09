import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/src/diff_text_selection.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'highlighted_code_test.dart' show recordClipboard;
import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app, selection;

Future<void> shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
}) async {
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  for (final meta in [false, true]) {
    for (final selectedDiff in [false, true]) {
      testWidgets(
        'nested editor owns ${meta ? 'Command' : 'Control'}+C with diff selection=$selectedDiff',
        (tester) async {
          final copied = recordClipboard(tester);
          final file = diffTexts('', 'diff source\n', path: 'draft.txt');
          final controller = PatchController<void>([file]);
          final draft = TextEditingController(text: 'draft comment');
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(draft.dispose);
          addTearDown(focus.dispose);
          await tester.pumpWidget(
            app(
              PatchView<void>.controlled(
                controller: controller,
                theme: githubDarkTheme,
                highlighter: Highlighter(),
                shrinkWrap: true,
                rowBelowBuilder: (_, _) => EditableText(
                  controller: draft,
                  focusNode: focus,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xffffffff),
                  ),
                  cursorColor: const Color(0xffffffff),
                  backgroundCursorColor: const Color(0xff000000),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (selectedDiff) {
            controller.select(
              DiffSelection(
                fileId: file.id,
                revision: 0,
                side: DiffSide.newer,
                anchor: 1,
                active: 1,
              ),
            );
            await tester.pumpAndSettle();
          }
          focus.requestFocus();
          await tester.pumpAndSettle();
          draft.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
          await tester.pumpAndSettle();
          expect(focus.hasPrimaryFocus, isTrue);
          expect(
            draft.selection,
            const TextSelection(baseOffset: 0, extentOffset: 5),
          );
          await shortcut(tester, LogicalKeyboardKey.keyC, meta: meta);
          expect(copied(), 'draft');
          expect(
            draft.selection,
            const TextSelection(baseOffset: 0, extentOffset: 5),
          );
          expectPlainTree(tester);
        },
        variant: TargetPlatformVariant.only(
          meta ? TargetPlatform.macOS : TargetPlatform.linux,
        ),
      );
    }
  }

  for (final fixed in [false, true]) {
    testWidgets(
      'visible callbacks share padded layout coordinates fixed=$fixed',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        (int, int)? visible;
        int? first;
        late IndexedViewportLayout geometry;
        await tester.pumpWidget(
          app(
            IndexedCodeViewport(
              controller: scroll,
              count: 300,
              layoutKey: 'padded',
              fixedHeight: fixed,
              estimatedHeight: 24,
              padding: const EdgeInsets.only(top: 48),
              identity: (i) => i,
              indexOf: (id) => id as int,
              builder: (_, i) => SizedBox(height: 24, child: Text('row-$i')),
              onVisibleRange: (start, end) => visible = (start, end),
              onFirstRow: (row) => first = row,
              onLayout: (layout) => geometry = layout,
            ),
            height: 130,
          ),
        );
        await tester.pumpAndSettle();
        expect(visible, (0, 4));
        for (final (offset, expected) in [(24.0, (0, 5)), (72.0, (1, 7))]) {
          scroll.jumpTo(offset);
          await tester.pumpAndSettle();
          expect(visible, expected);
          expect(first, expected.$1);
          expect(visible!.$1, geometry.rowAt(scroll.offset));
          expect(visible!.$2, geometry.rowAt(scroll.offset + 130) + 1);
        }
        expect(tester.getTopLeft(find.text('row-1')).dy, closeTo(0, .1));
        expectPlainTree(tester);
      },
    );

    testWidgets(
      'padded anchor retains within-row offset after resize fixed=$fixed',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        var height = 24.0;
        late StateSetter update;
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return IndexedCodeViewport(
                  controller: scroll,
                  count: 300,
                  layoutKey: height,
                  fixedHeight: fixed,
                  estimatedHeight: height,
                  padding: const EdgeInsets.only(top: 48),
                  identity: (i) => i,
                  indexOf: (id) => id as int,
                  builder: (_, i) =>
                      SizedBox(height: height, child: Text('row-$i')),
                  onVisibleRange: (_, _) {},
                  onLayout: (_) {},
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        scroll.jumpTo(48 + 50 * 24 + 8);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('row-50')).dy, closeTo(-8, .1));
        update(() => height = 48);
        await tester.pumpAndSettle();
        expect(scroll.offset, 48 + 50 * 48 + 8);
        expect(tester.getTopLeft(find.text('row-50')).dy, closeTo(-8, .1));
        expectPlainTree(tester);
      },
    );
  }

  for (final priorSide in <DiffSide?>[null, DiffSide.old, DiffSide.newer]) {
    testWidgets(
      'split select-all highlights exactly the copied side prior=$priorSide',
      (tester) async {
        final copied = recordClipboard(tester);
        final older = List.generate(80, (i) => 'old ${i + 1}');
        final newer = List.generate(80, (i) => 'new ${i + 1}');
        final file = diffTexts(
          older.join('\n'),
          newer.join('\n'),
          path: 'split.txt',
        );
        await tester.pumpWidget(
          app(
            PatchView<void>(
              files: [file],
              mode: DiffMode.split,
              theme: githubDarkTheme,
              shrinkWrap: true,
              highlighter: Highlighter(),
              padding: EdgeInsets.zero,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final region = tester.widget<SelectableRegion>(
          find.byType(SelectableRegion),
        );
        if (priorSide != null) {
          await tester.tap(
            find.text(
              priorSide == DiffSide.old ? 'old 1' : 'new 1',
              findRichText: true,
            ),
          );
        } else {
          region.focusNode!.requestFocus(); // No pointer event chooses a side.
        }
        await tester.pumpAndSettle();
        expect(selection(tester).activeSide.value, priorSide);
        await shortcut(tester, LogicalKeyboardKey.keyA);
        final side = priorSide ?? DiffSide.newer;
        expect(selection(tester).activeSide.value, side);
        var checked = 0;
        for (final element in find.byType(DiffSelectableCell).evaluate()) {
          final cell = element.widget as DiffSelectableCell;
          final container = tester.widget<SelectionContainer>(
            find
                .descendant(
                  of: find.byWidget(cell),
                  matching: find.byType(SelectionContainer),
                )
                .first,
          );
          final text =
              container.delegate!.getSelectedContent()?.plainText ?? '';
          expect(
            text.isNotEmpty,
            cell.cell.side == side,
            reason: '${cell.cell}',
          );
          checked++;
        }
        expect(checked, greaterThan(2));
        await shortcut(tester, LogicalKeyboardKey.keyA); // Repeated select-all.
        expect(selection(tester).activeSide.value, side);
        await shortcut(tester, LogicalKeyboardKey.keyC);
        expect(copied(), (side == DiffSide.old ? older : newer).join('\n'));
        expectPlainTree(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }
}
