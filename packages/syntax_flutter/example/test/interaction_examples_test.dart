import 'package:flutter/material.dart';
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
        await tap(find.text('Reply'));
        await tester.enterText(find.byType(TextField), 'Reply draft');
        await tester.pumpAndSettle();
        await tap(find.text('Custom threads'));
        expect(find.widgetWithText(TextField, 'Reply draft'), findsOneWidget);
        expect(find.text('Team discussion'), findsOneWidget);
        await tap(find.text('Send reply'));
        expect(session.thread.comments.length, 2);
        await tap(find.text('Mark resolved'));
        expect(session.thread.resolved, isTrue);
        expect(find.text('Root comment'), findsNothing);
        expect(find.text('Team review · 2 messages'), findsOneWidget);
        await tap(find.text('Show discussion'));
        expect(find.text('Root comment'), findsOneWidget);
        expect(session.thread.resolved, isTrue);
        await tap(find.text('Hide discussion'));
        expect(find.text('Root comment'), findsNothing);
        await tap(find.text('Reopen thread'));
        expect(session.thread.resolved, isFalse);
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
          expect((
            patch!.annotations.single.side,
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
