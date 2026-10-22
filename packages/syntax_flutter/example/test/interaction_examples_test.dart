import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';
import 'package:syntax_example/interaction_examples.dart';

Future<void> launch(
  WidgetTester tester,
  int kind, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InteractionExamples(
          kind: kind,
          theme: githubDarkTheme,
          textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final fileMode in [false, true]) {
    testWidgets(
      '${fileMode ? 'file' : 'diff'} previews demonstrate custom content and actions',
      (tester) async {
        await launch(tester, 0, size: const Size(1200, 1100));
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        if (fileMode) await tap(find.text('Show file'));
        await tap(find.text('Load sample threads'));
        await tap(find.byTooltip('Next discussion (Alt/Option+↓)'));
        await tap(find.byTooltip('Next discussion (Alt/Option+↓)'));
        final session = tester
            .widgetList<SyntaxCommentThread>(find.byType(SyntaxCommentThread))
            .firstWhere((w) => w.controller.thread.resolved)
            .controller;
        await tap(find.text('Custom preview'));
        final marker = find.byTooltip('Open discussion').last;
        await tester.ensureVisible(marker);
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(marker));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.text('REVIEW NOTEBOOK'), findsOneWidget);
        expect(
          find.text('Rate limits are covered. This discussion is resolved.'),
          findsOneWidget,
        );
        expect(session.isCollapsed, isTrue);
        final surface = find
            .ancestor(
              of: find.text('Discussion preview'),
              matching: find.byType(Material),
            )
            .first;
        Future<void> previewTap(String label) async {
          final control = find.descendant(
            of: surface,
            matching: find.text(label),
          );
          final scroll = Scrollable.maybeOf(tester.element(control));
          await scroll?.position.ensureVisible(
            tester.renderObject(control),
            alignment: 1,
          );
          await tester.pump();
          await tester.tap(control);
          await tester.pumpAndSettle();
        }

        await previewTap('Quick reply');
        final input = find.descendant(
          of: surface,
          matching: find.byType(TextField),
        );
        expect(input, findsOneWidget);
        expect(session.isCollapsed, isTrue);
        await tester.enterText(input, 'Reply saved from the notebook preview');
        await tester.pump();
        await previewTap('Send reply');
        expect(
          session.thread.comments.last.body,
          'Reply saved from the notebook preview',
        );
        expect(session.isReplying, isFalse);
        await previewTap('Reopen note');
        expect(session.thread.resolved, isFalse);
        await previewTap('Mark done');
        expect(session.thread.resolved, isTrue);
        await mouse.moveTo(tester.getCenter(find.text('Continue review')));
        await tester.pump(const Duration(milliseconds: 400));
        await previewTap('Continue review');
        expect(find.text('REVIEW NOTEBOOK'), findsNothing);
        expect(
          find.text('Discussion opened from the preview.'),
          findsOneWidget,
        );
        expect(session.isCollapsed, isFalse);
        expect(session.thread.resolved, isTrue);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${fileMode ? 'file' : 'diff'} gutter markers open resolved samples and demonstrate custom actions',
      (tester) async {
        await launch(tester, 0, size: const Size(1200, 1100));
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        if (fileMode) await tap(find.text('Show file'));
        await tap(find.text('Load sample threads'));
        await tap(find.byTooltip('Next discussion (Alt/Option+↓)'));
        await tap(find.byTooltip('Next discussion (Alt/Option+↓)'));
        final session = tester
            .widgetList<SyntaxCommentThread>(find.byType(SyntaxCommentThread))
            .firstWhere((w) => w.controller.thread.resolved)
            .controller;
        expect(session.isCollapsed, isTrue);
        await tap(find.text('Custom gutter'));
        await tap(find.byTooltip('Open review notes (1)').last);
        expect(session.isCollapsed, isFalse);
        expect(session.thread.resolved, isTrue);
        expect(find.text('Discussion opened from the gutter.'), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Review discussion',
        );
        expect(
          find
              .text('Rate limits are covered. This discussion is resolved.')
              .hitTestable(),
          findsOneWidget,
        );
        await tap(find.text('Default gutter'));
        expect(find.byTooltip('Open review notes (1)'), findsNothing);
        expect(find.byTooltip('Open discussion'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${fileMode ? 'file' : 'diff'} sample threads demonstrate active custom highlights',
      (tester) async {
        await launch(tester, 0, size: const Size(1200, 1100));
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        if (fileMode) await tap(find.text('Show file'));
        await tap(find.text('Load sample threads'));
        expect(find.text('1 / 3'), findsOneWidget);
        expect(find.text('2 unresolved'), findsAtLeastNWidgets(1));
        await tap(find.text('Custom highlight'));
        await tap(find.text('Custom source highlight'));
        final source = find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0x2446b8d9),
        );
        final navigation = fileMode
            ? tester
                  .widget<SyntaxFileView>(find.byType(SyntaxFileView))
                  .commentNavigation!
            : tester
                  .widget<PatchView>(find.byType(PatchView))
                  .commentNavigation!;
        expect(source, findsNWidgets(3));
        expect(
          navigation.isSourceLineActive(
            fileMode ? 'source' : 'policy',
            1,
            side: fileMode ? null : DiffSide.newer,
          ),
          isTrue,
        );
        final active = find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border ==
                  Border.all(color: const Color(0xffdf9438), width: 3),
        );
        expect(active, findsOneWidget);
        await tap(find.byTooltip('Next discussion (Alt/Option+↓)'));
        expect(source, findsNWidgets(3));
        expect(
          navigation.isSourceLineActive(
            fileMode ? 'source' : 'policy',
            1,
            side: fileMode ? null : DiffSide.newer,
          ),
          isFalse,
        );
        expect(
          navigation.isSourceLineActive(
            fileMode ? 'source' : 'policy',
            7,
            side: fileMode ? null : DiffSide.newer,
          ),
          isTrue,
        );
        expect(find.text('2 / 3'), findsOneWidget);
        expect(
          find
              .text('Could we document the maximum retry delay here?')
              .hitTestable(),
          findsOneWidget,
        );
        expect(active, findsOneWidget);
        await tap(find.byTooltip('Next discussion (Alt/Option+↓)'));
        expect(find.text('3 / 3'), findsOneWidget);
        expect(find.text('Resolved').hitTestable(), findsOneWidget);
        expect(active, findsOneWidget);
        expect(source, findsNWidgets(3));
        await tap(find.text('Load sample threads'));
        expect(find.text('1 / 3'), findsOneWidget);
        await tap(find.text('Default highlight'));
        expect(active, findsNothing);
        expect(source, findsNWidgets(3));
        await tap(find.text('Default source highlight'));
        expect(source, findsNothing);
        expect(find.text('2 unresolved'), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${fileMode ? 'file' : 'diff'} custom shortcut guide and thread commands work',
      (tester) async {
        await launch(tester, 0, size: const Size(1200, 1100));
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        if (fileMode) await tap(find.text('Show file'));
        await tap(find.text('Select lines 2–4'));
        await tap(find.byTooltip('Comment on selected lines'));
        await tester.enterText(find.byType(TextField), 'Shortcut review');
        await tester.pump();
        await tap(find.text('Add note'));
        await tap(find.text('Custom shortcuts'));
        await tap(find.text('Discussion shortcuts'));
        expect(find.text('J — Next thread'), findsOneWidget);
        expect(
          find.text('X — Resolve / reopen selected thread'),
          findsOneWidget,
        );
        await tap(find.text('Close'));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.pumpAndSettle();
        expect(find.text('1 / 1'), findsOneWidget);
        final session = tester
            .widget<SyntaxCommentThread>(find.byType(SyntaxCommentThread))
            .controller;
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
        await tester.pumpAndSettle();
        expect(session.replyFocus.hasFocus, isTrue);
        await tester.enterText(find.byType(TextField), 'Retained reply');
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
        await tester.pumpAndSettle();
        expect(session.thread.resolved, isFalse);
        Focus.of(
          tester.element(find.byType(SyntaxCommentNavigation)),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
        await tester.pumpAndSettle();
        expect(session.thread.resolved, isTrue);
        expect(find.text('Resolved'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
        await tester.pumpAndSettle();
        expect(session.thread.resolved, isFalse);
        expect(session.replyInput.text, 'Retained reply');
        await tap(find.text('Default shortcuts'));
        expect(
          find.byTooltip('Next discussion (Alt/Option+↓)'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${fileMode ? 'file' : 'diff'} threads support custom reply edit delete and resolution actions',
      (tester) async {
        await launch(tester, 0, size: const Size(1200, 1100));
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        if (fileMode) await tap(find.text('Show file'));
        await tap(find.text('Select lines 2–4'));
        await tap(find.byTooltip('Comment on selected lines'));
        await tester.enterText(find.byType(TextField), 'Root comment');
        await tester.pump();
        await tap(find.text('Add note'));
        expect(find.text('1 unresolved'), findsNWidgets(2));
        await tap(find.widgetWithIcon(IconButton, Icons.arrow_downward));
        expect(find.text('1 / 1'), findsOneWidget);
        final session = tester
            .widget<SyntaxCommentThread>(find.byType(SyntaxCommentThread))
            .controller;
        final originalId = session.thread.id;
        final rootId = session.thread.comments.single.id;
        final patch = fileMode
            ? null
            : tester.widget<PatchView>(find.byType(PatchView)).controller!;
        final editor = fileMode
            ? tester
                  .widget<SyntaxFileView>(find.byType(SyntaxFileView))
                  .controller
            : null;
        final anchor = editor != null
            ? (editor.annotations.single.start, editor.annotations.single.end)
            : (patch!.annotations.single.side, patch.annotations.single.line);
        final linkedRange = patch?.annotations.single.sourceSelection;
        if (patch != null) {
          expect(linkedRange, isNotNull);
          expect((linkedRange!.anchor, linkedRange.active), (2, 4));
        }
        await tap(find.text('Reply'));
        await tester.enterText(find.byType(TextField), 'Reply draft');
        await tester.pumpAndSettle();
        await tap(find.text('Custom threads'));
        expect(find.text('Needs attention: 1'), findsOneWidget);
        expect(find.text('1 to review'), findsOneWidget);
        await tap(find.text('Next thread'));
        expect(find.text('1 / 1'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Reply draft'), findsOneWidget);
        expect(find.text('Team discussion'), findsOneWidget);
        await tap(find.text('Send reply'));
        expect(session.thread.comments.length, 2);
        await tap(find.text('Mark resolved'));
        expect(session.thread.resolved, isTrue);
        expect(find.text('Needs attention: 0'), findsOneWidget);
        expect(find.text('0 to review'), findsOneWidget);
        expect(find.text('Root comment'), findsNothing);
        expect(find.text('Team review · 2 messages'), findsOneWidget);
        await tap(find.text('Hide resolved'));
        expect(find.byType(SyntaxCommentThread), findsNothing);
        expect(find.text('0 / 0'), findsOneWidget);
        await tap(find.text('Hide resolved'));
        expect(find.text('Team review · 2 messages'), findsOneWidget);
        await tap(find.text('Show discussion'));
        expect(find.text('Root comment'), findsOneWidget);
        expect(session.thread.resolved, isTrue);
        await tap(find.text('Hide discussion'));
        expect(find.text('Root comment'), findsNothing);
        await tap(find.text('Reopen thread'));
        expect(session.thread.resolved, isFalse);
        expect(find.text('Needs attention: 1'), findsOneWidget);
        expect(find.text('1 to review'), findsOneWidget);
        expect(find.text('Root comment'), findsOneWidget);
        await tap(
          find.descendant(
            of: find.byKey(ValueKey(rootId)),
            matching: find.byTooltip('Edit message'),
          ),
        );
        await tester.enterText(find.byType(TextField), 'Updated root');
        await tester.pump();
        await tap(find.text('Save message'));
        expect(session.thread.comments.first.body, 'Updated root');
        expect(find.text('Edited'), findsOneWidget);
        final replyId = session.thread.comments.last.id;
        await tap(
          find.descendant(
            of: find.byKey(ValueKey(replyId)),
            matching: find.byTooltip('Remove message'),
          ),
        );
        expect(find.byType(AlertDialog), findsNothing);
        await tap(find.widgetWithText(FilledButton, 'Delete'));
        expect(session.thread.comments.single.id, rootId);
        if (editor != null) {
          expect((
            editor.annotations.single.start,
            editor.annotations.single.end,
          ), anchor);
          expect(
            (editor.annotations.single.data! as ReviewThread)
                .comments
                .single
                .body,
            'Updated root',
          );
        } else {
          expect(patch!.annotations.single.sourceSelection, same(linkedRange));
          expect((
            patch.annotations.single.side,
            patch.annotations.single.line,
          ), anchor);
          expect(
            (patch.annotations.single.data! as ReviewThread)
                .comments
                .single
                .body,
            'Updated root',
          );
        }
        await tap(find.byTooltip('Remove message'));
        await tap(find.widgetWithText(FilledButton, 'Delete'));
        expect(find.byType(SyntaxCommentThread), findsNothing);
        expect(editor?.annotations ?? patch!.annotations, isEmpty);
        await tap(find.text('Add comment'));
        await tester.enterText(find.byType(TextField), 'New discussion');
        await tester.pump();
        await tap(find.text('Add note'));
        final next = tester
            .widget<SyntaxCommentThread>(find.byType(SyntaxCommentThread))
            .controller;
        expect(next.thread.id, isNot(originalId));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('selection presets, source copy and annotations are live', (
    tester,
  ) async {
    await launch(tester, 0);
    final review = tester.widget<PatchView>(find.byType(PatchView)).controller!;
    await tester.tap(find.text('Select across sides'));
    await tester.pumpAndSettle();
    expect(review.selection!.crossesSides, isTrue);
    expect(review.selectedText(), contains('cleaned.isEmpty'));
    await tester.tap(find.byTooltip('Comment on selected lines'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SyntaxCommentComposer), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Handle missing names');
    await tester.pump();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(
      (review.annotations.single.data! as ReviewThread).comments.single.body,
      'Handle missing names',
    );
    await tester.tap(find.text('Clear selection'));
    await tester.pumpAndSettle();
    expect(review.selection, isNull);
    await tester.tap(find.text('Show file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select lines 2–4'));
    await tester.pumpAndSettle();
    final file = tester
        .widget<SyntaxFileView>(find.byType(SyntaxFileView))
        .controller;
    expect(file.document.positionAt(file.selections.single.start).line, 1);
    expect(file.document.positionAt(file.selections.single.end).line, 3);
    final beforeComment = tester.getTopLeft(
      find.textContaining('String formatName', findRichText: true).last,
    );
    await tester.tap(find.byTooltip('Comment on selected lines'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(
        find.textContaining('String formatName', findRichText: true).last,
      ),
      beforeComment,
    );
    await tester.enterText(find.byType(TextField), 'File range note');
    await tester.pump();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(file.annotations.single.start, file.selections.single.start);
    expect(file.annotations.single.end, file.selections.single.end);
    expect(find.text('File range note'), findsOneWidget);
    await tester.ensureVisible(find.text('Custom comment action'));
    await tester.tap(find.text('Custom comment action'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Comment on selected lines'), findsNothing);
    await tester.tap(find.byTooltip('Discuss this selection'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Custom action note');
    await tester.pump();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(file.annotations.length, 2);
    expect(find.text('Custom action note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reverse ranges reveal an inline input outside the mounted viewport',
    (tester) async {
      await launch(tester, 0);
      await tester.tap(find.text('Show file'));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<SyntaxFileView>(find.byType(SyntaxFileView))
          .controller;
      final end = editor.document.text.length;
      editor.applyEdits([
        OffsetEdit(
          end,
          end,
          List.generate(1200, (i) => '// extra $i').join('\n'),
        ),
      ]);
      editor.selectLines(1000, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Comment on selected lines'));
      await tester.pumpAndSettle();
      expect(editor.revealTarget?.start.line, 1000);
      expect(find.byType(SyntaxCommentComposer), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Long range note');
      await tester.pump();
      await tester.ensureVisible(find.text('Add note'));
      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();
      expect(
        (editor.annotations.single.data! as ReviewThread).comments.single.body,
        'Long range note',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'inline inputs and actions are customizable and keep separate view drafts',
    (tester) async {
      await launch(tester, 0, size: const Size(520, 900));
      Future<void> tapVisible(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      final review = tester
          .widget<PatchView>(find.byType(PatchView))
          .controller!;
      await tapVisible('Select across sides');
      await tester.tap(find.byTooltip('Comment on selected lines'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Diff draft');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Custom composer'));
      await tapVisible('Custom composer');
      expect(find.text('Your feedback'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Diff draft'), findsOneWidget);
      await tapVisible('Show file');
      await tapVisible('Select lines 2–4');
      await tester.tap(find.byTooltip('Comment on selected lines'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), 'File draft');
      await tester.pumpAndSettle();
      await tapVisible('Show diff');
      expect(find.widgetWithText(TextField, 'Diff draft'), findsOneWidget);
      await tester.ensureVisible(find.text('Clear draft'));
      await tester.tap(find.text('Clear draft'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Post note'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Final review');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Post note'));
      await tapVisible('Post note');
      expect(
        (review.annotations.single.data! as ReviewThread).comments.single.body,
        'Final review',
      );
      expect(find.byType(SyntaxCommentComposer), findsNothing);
      await tapVisible('Show file');
      expect(find.widgetWithText(TextField, 'File draft'), findsOneWidget);
      await tester.ensureVisible(find.text('Discard'));
      await tapVisible('Discard');
      expect(find.byType(SyntaxCommentComposer), findsNothing);
      expect(
        tester
            .widget<SyntaxFileView>(find.byType(SyntaxFileView))
            .controller
            .annotations,
        isEmpty,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'custom diff actions retain range and discard notes for replaced source',
    (tester) async {
      await launch(tester, 0, size: const Size(520, 900));
      final review = tester
          .widget<PatchView>(find.byType(PatchView))
          .controller!;
      await tester.tap(find.text('Select across sides'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Custom comment action'));
      await tester.tap(find.text('Custom comment action'));
      await tester.pumpAndSettle();
      final selection = review.selection;
      await tester.tap(find.byTooltip('Discuss this selection'));
      await tester.pumpAndSettle();
      expect(identical(review.selection, selection), isTrue);
      await tester.enterText(find.byType(TextField), 'Stale note');
      review.setFiles([
        diffTexts('before', 'after', id: 'policy', path: 'changed.dart'),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(SyntaxCommentComposer), findsNothing);
      expect(review.annotations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('named sections fold independently and reveal their function', (
    tester,
  ) async {
    await launch(tester, 1);
    final review = tester.widget<PatchView>(find.byType(PatchView)).controller!;
    expect(review.files.single.hunks.length, 3);
    await tester.tap(find.text('Fold all sections'));
    await tester.pumpAndSettle();
    expect(review.layout.whereType<DiffLineRow>(), isEmpty);
    await tester.tap(find.text('Jump to retryDelay'));
    await tester.pumpAndSettle();
    expect(review.isHunkCollapsed('policy', 0), isTrue);
    expect(review.isHunkCollapsed('policy', 1), isFalse);
    expect(review.isHunkCollapsed('policy', 2), isTrue);
    expect(
      find.textContaining('delay.clamp', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Expand all sections'));
    await tester.pumpAndSettle();
    expect(review.isHunkCollapsed('policy', 0), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('appearance and custom header controls work at compact width', (
    tester,
  ) async {
    await launch(tester, 2, size: const Size(520, 900));
    await tester.tap(find.text('Hide numbers'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatchView>(find.byType(PatchView)).showLineNumbers,
      isFalse,
    );
    await tester.tap(find.text('Hide backgrounds'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatchView>(find.byType(PatchView)).showBackgrounds,
      isFalse,
    );
    await tester.tap(find.text('Markers: classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markers: bars').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatchView>(find.byType(PatchView)).indicators,
      DiffIndicators.bars,
    );
    expect(tester.takeException(), isNull);
    await launch(tester, 4);
    await tester.tap(find.byTooltip('Collapse custom file'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PatchView>(find.byType(PatchView))
          .controller!
          .isCollapsed('policy'),
      isTrue,
    );
    await tester.tap(find.byTooltip('Expand custom file'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'token inspection and arbitrary source comparison produce output',
    (tester) async {
      await launch(tester, 3);
      final tokenText = tester.widget<Text>(
        find
            .descendant(
              of: find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Tooltip &&
                        widget.message!.contains('Changed token'),
                  )
                  .first,
              matching: find.byType(Text),
            )
            .first,
      );
      expect(tokenText.style!.fontFamily, 'monospace');
      expect(tokenText.style!.fontSize, 13);
      await tester.tap(find.text('Inspect selected line'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Line 4:'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip && widget.message!.contains('Changed token'),
        ),
        findsWidgets,
      );
      await launch(tester, 5);
      await tester.enterText(
        find.widgetWithText(TextField, 'Original source'),
        'final value = 1;',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Updated source'),
        'final value = 2;',
      );
      await tester.tap(find.text('Compare sources'));
      await tester.pumpAndSettle();
      final review = tester
          .widget<PatchView>(find.byType(PatchView))
          .controller!;
      expect(review.files.single.newText, 'final value = 2;');
      expect(review.files.single.oldText, 'final value = 1;');
      expect(tester.takeException(), isNull);
      await launch(tester, 3);
      await tester.tap(find.text('Inspect selected line'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Line 4:'), findsOneWidget);
      expect(
        tester
            .widget<PatchView>(find.byType(PatchView))
            .controller!
            .files
            .single
            .path,
        'lib/request_policy.dart',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('appearance preserves supplied fonts and resets locally', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractionExamples(
            kind: 2,
            theme: githubDarkTheme,
            textStyle: const TextStyle(
              fontFamily: 'Gallery Mono',
              fontSize: 13.5,
            ),
            fontStyles: const {
              'Alternate': TextStyle(
                fontFamily: 'Alternate Mono',
                fontSize: 13.5,
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    PatchView view() => tester.widget<PatchView>(find.byType(PatchView));
    expect(view().textStyle!.fontFamily, 'Gallery Mono');
    expect(view().textStyle!.fontSize, 13.5);
    await tester.tap(find.text('Font: Default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Font: Alternate').last);
    await tester.pumpAndSettle();
    expect(view().textStyle!.fontFamily, 'Alternate Mono');
    await tester.tap(find.text('Hide backgrounds'));
    await tester.ensureVisible(find.text('Reset example'));
    await tester.tap(find.text('Reset example'));
    await tester.pumpAndSettle();
    expect(view().showBackgrounds, isTrue);
    expect(view().textStyle!.fontFamily, 'Gallery Mono');
  });
}
