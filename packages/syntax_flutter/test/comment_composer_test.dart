import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'interaction_test.dart' show app, row;

FileSelectionDetails selectedFile(
  EditorController editor,
  int anchor,
  int active,
) {
  editor.selectLines(anchor, active);
  return FileSelectionDetails(
    file: editor.file,
    selection: editor.selections.single,
    anchorLine: anchor,
    activeLine: active,
  );
}

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
}) async {
  await tester.pump();
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  for (final reverse in [false, true]) {
    testWidgets(
      'file composer stays below the complete ${reverse ? 'reverse' : 'forward'} range',
      (tester) async {
        final editor = EditorController(
          file: const SourceFile(
            id: 'a',
            path: 'a.txt',
            text: 'one😀\r\ntwo\r\nthree\r\nfour',
          ),
        );
        final draft = TextEditingController();
        final details = selectedFile(editor, reverse ? 2 : 0, reverse ? 0 : 2);
        final highlighter = Highlighter();
        String? saved;
        var cancelled = false;
        Widget view() => app(
          SyntaxFileView(
            controller: editor,
            highlighter: highlighter,
            theme: githubDarkTheme,
            wrap: false,
            commentSelection: details,
            commentBuilder: (_, selection) => SyntaxCommentComposer(
              controller: draft,
              onSubmit: (text) => saved = text,
              onCancel: () => cancelled = true,
            ),
          ),
        );
        await tester.pumpWidget(view());
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        final composer = tester.getRect(find.byType(SyntaxCommentComposer));
        expect(composer.top, tester.getRect(row('three')).bottom);
        expect(tester.getRect(row('four')).top, composer.bottom);
        await tester.enterText(find.byType(TextField), '  Range note 😀  ');
        await chord(tester, LogicalKeyboardKey.enter, meta: reverse);
        expect(saved, 'Range note 😀');
        expect(editor.document.text, details.file.text);
        editor.selectLines(
          3,
          3,
        ); // The draft must not follow subsequent source selections.
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(SyntaxCommentComposer)).top,
          tester.getRect(row('three')).bottom,
        );
        expect(draft.text, '  Range note 😀  ');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(cancelled, isTrue);
        editor.applyEdits([const OffsetEdit(0, 0, 'changed\n')]);
        await tester.pumpAndSettle();
        expect(find.byType(SyntaxCommentComposer), findsNothing);
        expect(draft.text, '  Range note 😀  ');
        await tester.pumpWidget(const SizedBox());
        draft.dispose();
        editor.dispose();
      },
    );
  }

  testWidgets(
    'comment input uses native select and copy rather than source shortcuts',
    (tester) async {
      final editor = EditorController(
        file: const SourceFile(id: 'a', path: 'a.txt', text: 'source'),
      );
      final draft = TextEditingController(text: 'comment draft');
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      for (final meta in [false, true]) {
        debugDefaultTargetPlatformOverride = meta
            ? TargetPlatform.macOS
            : TargetPlatform.linux;
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpWidget(
          app(
            SyntaxFileView(
              controller: editor,
              highlighter: Highlighter(),
              theme: githubDarkTheme,
              commentSelection: selectedFile(editor, 0, 0),
              commentBuilder: (_, _) => SyntaxCommentComposer(
                controller: draft,
                onSubmit: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await chord(tester, LogicalKeyboardKey.keyA, meta: meta);
        await chord(tester, LogicalKeyboardKey.keyC, meta: meta);
        expect(copied, 'comment draft');
        expect(editor.document.text, 'source');
        // A non-native modifier must not fall through to source-copy either.
        copied = null;
        await chord(tester, LogicalKeyboardKey.keyC, meta: !meta);
        expect(copied, isNot('source'));
      }
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      draft.dispose();
      editor.dispose();
    },
  );

  for (final reverse in [false, true]) {
    testWidgets(
      'cross-side ${reverse ? 'reverse' : 'forward'} comments follow unified and split display order',
      (tester) async {
        final source = diffTexts(
          'base\nold one\nold two\ntail',
          'base\nnew\ntail',
          id: 'a',
          path: 'a.txt',
        );
        final review = PatchController([source]);
        final selection = reverse
            ? const DiffSelection(
                'a',
                DiffSide.newer,
                2,
                3,
                activeSide: DiffSide.old,
              )
            : const DiffSelection(
                'a',
                DiffSide.old,
                3,
                2,
                activeSide: DiffSide.newer,
              );
        review.select(selection);
        final snapshot = DiffSelectionDetails(
          file: source,
          selection: selection,
        );
        final draft = TextEditingController();
        expect(snapshot.endIn(DiffMode.unified), (
          side: DiffSide.newer,
          line: 2,
        ));
        expect(snapshot.endIn(DiffMode.split), (side: DiffSide.old, line: 3));
        await tester.pumpWidget(
          app(
            PatchView.controlled(
              controller: review,
              highlighter: Highlighter(),
              theme: githubDarkTheme,
              commentSelection: snapshot,
              commentBuilder: (_, _) => SyntaxCommentComposer(
                controller: draft,
                autofocus: false,
                onSubmit: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(SyntaxCommentComposer)).dy,
          tester.getRect(row('new')).bottom,
        );
        await tester.enterText(find.byType(TextField), 'Preserve draft');
        review.mode = DiffMode.split;
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(SyntaxCommentComposer)).dy,
          tester.getRect(row('old two')).bottom,
        );
        expect(draft.text, 'Preserve draft');
        review.toggleFile('a');
        await tester.pumpAndSettle();
        expect(find.byType(SyntaxCommentComposer), findsNothing);
        review.toggleFile('a');
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextField, 'Preserve draft'),
          findsOneWidget,
        );
        review.setFiles([
          diffTexts('different', 'content', id: 'a', path: 'a.txt'),
        ]);
        await tester.pumpAndSettle();
        expect(
          find.byType(SyntaxCommentComposer),
          findsNothing,
        ); // Even at the same revision.
        expect(draft.text, 'Preserve draft');
        await tester.pumpWidget(const SizedBox());
        draft.dispose();
        review.dispose();
      },
    );
  }

  testWidgets(
    'virtualized file comments retain drafts and measure input height changes',
    (tester) async {
      final editor = EditorController(
        file: SourceFile(
          id: 'a',
          path: 'a.txt',
          text: List.generate(1000, (i) => 'row $i').join('\n'),
        ),
      );
      final draft = TextEditingController();
      final scroll = ScrollController();
      final selection = selectedFile(editor, 0, 2);
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            scrollController: scroll,
            wrap: false,
            commentSelection: selection,
            commentBuilder: (_, _) => SyntaxCommentComposer(
              controller: draft,
              autofocus: false,
              onSubmit: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialHeight = tester
          .getSize(find.byType(SyntaxCommentComposer))
          .height;
      await tester.enterText(
        find.byType(TextField),
        'one\ntwo\nthree\nfour\nfive\nsix',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SyntaxCommentComposer)).height,
        greaterThan(initialHeight),
      );
      expect(
        tester.getRect(row('row 3')).top,
        tester.getRect(find.byType(SyntaxCommentComposer)).bottom,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      scroll.jumpTo(12000);
      await tester.pumpAndSettle();
      expect(find.byType(SyntaxCommentComposer), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'one\ntwo\nthree\nfour\nfive\nsix'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
      editor.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'custom inputs and actions receive the retained draft and enabled commands',
    (tester) async {
      final draft = TextEditingController();
      var busy = false, cancellations = 0;
      String? saved;
      late StateSetter rebuild;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, set) {
              rebuild = set;
              return SyntaxCommentComposer(
                controller: draft,
                isSubmitting: busy,
                errorText: 'Try again',
                onSubmit: (text) => saved = text,
                onCancel: () => cancellations++,
                header: const Text('Custom heading'),
                decoration: const BoxDecoration(color: Colors.white),
                inputBuilder: (_, details) => TextField(
                  controller: details.controller,
                  autofocus: true,
                  enabled: !details.isSubmitting,
                  decoration: const InputDecoration(labelText: 'Custom input'),
                ),
                actionsBuilder: (_, details) => Row(
                  children: [
                    TextButton(
                      onPressed: details.cancel,
                      child: const Text('Discard'),
                    ),
                    FilledButton(
                      onPressed: details.submit,
                      child: const Text('Publish note'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.bySemanticsLabel('Try again'), findsOneWidget);
      expect(find.text('Custom heading'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'custom draft');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      rebuild(() => busy = true);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await chord(tester, LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(saved, isNull);
      expect(cancellations, 0);
      rebuild(() => busy = false);
      await tester.pump();
      await tester.tap(find.text('Publish note'));
      expect(saved, 'custom draft');
      expect(
        draft.text,
        'custom draft',
      ); // Only the application decides when to clear.
      await tester.tap(find.text('Discard'));
      expect(cancellations, 1);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      draft.dispose();
    },
  );

  testWidgets(
    'collection previews forward inline builders and custom annotation anchors',
    (tester) async {
      final files = FileListController([
        const SourceFile(id: 'a', path: 'a.txt', text: 'one\ntwo\nthree\nfour'),
      ]);
      final editor = files.acquire('a');
      final selection = selectedFile(editor, 2, 0);
      editor.setAnnotations([
        LineAnnotation(
          id: 'note',
          start: selection.selection.start,
          end: selection.selection.end,
          data: 'Range note',
        ),
      ]);
      final draft = TextEditingController(text: 'Unsent');
      await tester.pumpWidget(
        app(
          SyntaxFileList(
            controller: files,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            fileHeight: 480,
            commentSelection: selection,
            commentBuilder: (_, _) => SyntaxCommentComposer(
              controller: draft,
              autofocus: false,
              onSubmit: (_) {},
              onCancel: () {},
            ),
            annotationLineBuilder: (note) =>
                editor.document.positionAt(note.end).line,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(SyntaxCommentComposer)).top,
        tester.getRect(row('three')).bottom,
      );
      expect(
        tester.getTopLeft(find.text('Range note')).dy,
        greaterThan(tester.getRect(row('three')).bottom),
      );
      files.toggle('a');
      await tester.pumpAndSettle();
      files.toggle('a');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Unsent'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      files.release('a');
      files.dispose();
      draft.dispose();
    },
  );
}
