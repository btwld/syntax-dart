import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app;

void main() {
  for (final leading in [false, true]) {
    testWidgets(
      'one controlled sticky header and fold control leading=$leading',
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
        await tester.pumpWidget(
          app(
            PatchView<void>.controlled(
              controller: controller,
              scrollController: scroll,
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              stickyHeaders: true,
              leading: leading
                  ? const SizedBox(height: 90, child: Text('Introduction'))
                  : null,
              headerBuilder: (_, _, _, toggle) => SizedBox(
                key: const ValueKey('file-header'),
                height: 80,
                child: GestureDetector(
                  onTap: toggle,
                  child: const Text('Fold file'),
                ),
              ),
              fileLabelBuilder: (_, _) => const SizedBox(
                key: ValueKey('file-label'),
                height: 24,
                child: Text('Label'),
              ),
            ),
            height: 320,
          ),
        );
        await tester.pumpAndSettle();
        void expectOneInList() {
          expect(find.byKey(const ValueKey('file-header')), findsOneWidget);
          expect(find.byKey(const ValueKey('file-label')), findsOneWidget);
          expect(find.text('Fold file'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('file-header')).hitTestable(),
            findsOneWidget,
          );
        }

        expectOneInList();
        final headerTop = tester
            .getTopLeft(find.byKey(const ValueKey('file-header')))
            .dy;
        // Keep part of the source header visible: no pinned copy yet.
        scroll.jumpTo(headerTop + 20);
        await tester.pumpAndSettle();
        expectOneInList();
        // Once the complete source header and label leave the viewport,
        // exactly one pinned header and folding control can be painted.
        scroll.jumpTo(headerTop + 180);
        await tester.pumpAndSettle();
        final pinned = find.byKey(const ValueKey('file-header')).hitTestable();
        expect(pinned, findsOneWidget);
        expect(
          find.byKey(const ValueKey('file-label')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Fold file').hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(pinned).dy, closeTo(0, .1));
        // The pinned folding control remains functional and is replaced by
        // the in-list header when folding brings the file back into view.
        await tester.tap(find.text('Fold file').hitTestable());
        await tester.pumpAndSettle();
        expect(controller.isCollapsed(file.id), isTrue);
        expectOneInList();
        controller.setCollapsed(file.id, false);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expectOneInList();
        controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
        await tester.pumpAndSettle();
        final visibleHeader = tester.getRect(
          find.byKey(const ValueKey('file-header')).hitTestable(),
        );
        final visibleLabel = tester.getRect(
          find.byKey(const ValueKey('file-label')).hitTestable(),
        );
        final target = tester.getRect(
          find.text('line 200', findRichText: true),
        );
        expect(target.top, greaterThanOrEqualTo(visibleHeader.bottom));
        expect(target.top, greaterThanOrEqualTo(visibleLabel.bottom));
        expect(target.bottom, lessThanOrEqualTo(320));
        expect(find.text('Fold file').hitTestable(), findsOneWidget);
        expectPlainTree(tester);
      },
    );
  }

  testWidgets('reveals use each pinned header height', (tester) async {
    FileDiff source(String path) => diffTexts(
      '',
      List.generate(300, (i) => '$path line ${i + 1}').join('\n'),
      path: path,
    );
    final a = source('a');
    final b = source('b');
    final controller = PatchController<void>([a, b]);
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    controller.revealLine(b.id, DiffSide.newer, 200, revision: 0);
    await tester.pumpWidget(
      app(
        PatchView<void>.controlled(
          controller: controller,
          scrollController: scroll,
          theme: githubDarkTheme,
          highlighter: Highlighter(),
          stickyHeaders: true,
          headerBuilder: (_, file, _, toggle) => SizedBox(
            key: ValueKey('header-${file.path}'),
            height: file.path == 'a' ? 80 : 120,
            child: GestureDetector(
              onTap: toggle,
              child: Text('Fold ${file.path}'),
            ),
          ),
          fileLabelBuilder: (_, file) => SizedBox(
            key: ValueKey('label-${file.path}'),
            height: 24,
            child: Text('Label ${file.path}'),
          ),
        ),
        height: 320,
      ),
    );
    await tester.pumpAndSettle();
    for (final file in [b, a, b]) {
      controller.revealLine(file.id, DiffSide.newer, 200, revision: 0);
      await tester.pumpAndSettle();
      final pinned = tester.getRect(
        find.byKey(ValueKey('header-${file.path}')).hitTestable(),
      );
      final label = tester.getRect(
        find.byKey(ValueKey('label-${file.path}')).hitTestable(),
      );
      final target = tester.getRect(
        find.text('${file.path} line 200', findRichText: true),
      );
      debugPrint(
        'sticky file=${file.path}: pinned=$pinned label=$label target=$target',
      );
      expect(pinned.top, closeTo(0, .1));
      expect(target.top, greaterThanOrEqualTo(pinned.bottom));
      expect(target.top, greaterThanOrEqualTo(label.bottom));
      expect(target.bottom, lessThanOrEqualTo(320));
      expect(find.text('Fold ${file.path}').hitTestable(), findsOneWidget);
    }
    expectPlainTree(tester);
  });
}
