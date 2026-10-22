import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';
import 'comment_thread_test.dart' show save, initialThread;

Finder get preview => find
    .ancestor(
      of: find.text('Discussion preview'),
      matching: find.byType(Material),
    )
    .first;
Finder inside(Finder finder) => find.descendant(of: preview, matching: finder);
Finder action(String label) => inside(
  find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is TextButton),
  ),
);

class ReviewFixture {
  ReviewFixture({
    DiffMode? mode,
    bool resolved = true,
    ReviewThreadUpdater? update,
  }) {
    session = CommentThreadController(
      thread: initialThread().copyWith(resolved: resolved),
      onUpdate: update ?? save,
    );
    if (mode != null) {
      patch = PatchController([
        diffTexts('old\nend', 'new\nend', id: 'f', path: 'f'),
      ], mode: mode);
    }
    publish();
    nav = patch == null
        ? CommentNavigationController.file(editor)
        : CommentNavigationController.patch(patch!);
    session.addListener(publish);
  }
  final editor = EditorController(
    file: const SourceFile(id: 'f', path: 'f', text: 'one\ntwo\nthree'),
  );
  PatchController? patch;
  late CommentThreadController session;
  late CommentNavigationController nav;
  ReviewThread? published;
  void publish() {
    if (identical(published, session.thread)) return;
    published = session.thread;
    if (patch == null) {
      editor.setAnnotations([
        LineAnnotation(id: 'a', start: 0, end: 0, data: session.thread),
      ]);
    } else {
      patch!.setAnnotations([
        ReviewAnnotation(
          id: 'a',
          fileId: 'f',
          side: DiffSide.newer,
          line: 1,
          data: session.thread,
        ),
      ]);
    }
  }

  Widget view() => patch == null
      ? SyntaxFileView(
          controller: editor,
          highlighter: Highlighter(),
          theme: githubDarkTheme,
          commentNavigation: nav,
          annotationBuilder: (_, _) => SyntaxCommentThread(controller: session),
        )
      : PatchView.controlled(
          controller: patch!,
          highlighter: Highlighter(),
          theme: githubDarkTheme,
          commentNavigation: nav,
          annotationBuilder: (_, _) => SyntaxCommentThread(controller: session),
        );
  Future<void> launch(
    WidgetTester tester, {
    Widget Function(Widget)? wrap,
  }) async {
    final view = this.view();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body:
              wrap?.call(view) ??
              SyntaxCommentGutterTheme(
                previewThreadController: (_) => session,
                child: view,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    nav.dispose();
    session.dispose();
    editor.dispose();
    patch?.dispose();
  }
}

Future<TestGesture> showPreview(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  return mouse;
}

Future<void> reply(WidgetTester tester, String text) async {
  await tester.tap(action('Reply'));
  await tester.pumpAndSettle();
  expect(preview, findsOneWidget);
  final input = inside(find.byType(TextField));
  expect(input, findsOneWidget);
  await tester.enterText(input, text);
  await tester.pump();
}

Future<void> tapPreview(WidgetTester tester, Finder finder) async {
  await tester.pump();
  final scroll = Scrollable.maybeOf(tester.element(finder));
  if (scroll != null) {
    await scroll.position.ensureVisible(
      tester.renderObject(finder),
      alignment: 1,
    );
    await tester.pump();
  }
  await tester.tap(finder);
}

void main() {
  for (final mode in [null, ...DiffMode.values]) {
    testWidgets(
      '$mode replies and toggles resolution in place without opening inline editor',
      (tester) async {
        final f = ReviewFixture(mode: mode);
        f.editor.selectLines(2, 2);
        final selected = f.editor.selections.single;
        await f.launch(tester);
        final mouse = await showPreview(tester);
        await reply(tester, 'Saved directly in preview');
        expect(f.session.isCollapsed, isTrue);
        expect(f.session.isReplying, isFalse);
        expect(f.session.replyFocus.hasFocus, isFalse);
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'Preview reply');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(
          f.session.thread.comments.last.body,
          'Saved directly in preview',
        );
        expect(f.session.thread.comments.length, 2);
        expect(f.session.replyInput.text, isEmpty);
        expect(preview, findsOneWidget);
        expect(inside(find.byType(TextField)), findsNothing);
        expect(f.session.isCollapsed, isTrue);
        expect(f.session.thread.resolved, isTrue);
        await tester.tap(action('Reopen'));
        await tester.pumpAndSettle();
        expect(preview, findsOneWidget);
        expect(f.session.thread.resolved, isFalse);
        await tester.tap(action('Resolve'));
        await tester.pumpAndSettle();
        expect(preview, findsOneWidget);
        expect(f.session.thread.resolved, isTrue);
        expect(f.nav.count(resolved: true), 1);
        expect(f.nav.current, isNull);
        expect(f.editor.selections.single, same(selected));
        expect(f.patch?.selection, isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }

  testWidgets(
    'failed saves retain draft, pending commands disable, and retry succeeds',
    (tester) async {
      var request = Completer<ReviewThread>();
      ReviewThreadChange? change;
      var calls = 0;
      final f = ReviewFixture(
        update: (value) {
          calls++;
          change = value;
          return request.future;
        },
      );
      await f.launch(tester);
      final mouse = await showPreview(tester);
      await reply(tester, 'Keep this draft');
      await tapPreview(
        tester,
        inside(find.widgetWithText(FilledButton, 'Post reply')),
      );
      await tester.pump();
      expect(f.session.isSubmitting, isTrue);
      expect(tester.widget<TextButton>(action('Reopen')).onPressed, isNull);
      request.completeError(StateError('Private server information'));
      await tester.pumpAndSettle();
      expect(f.session.replyInput.text, 'Keep this draft');
      expect(
        inside(find.text('Could not update this discussion. Try again.')),
        findsOneWidget,
      );
      expect(find.textContaining('Private server information'), findsNothing);
      request = Completer<ReviewThread>();
      await tapPreview(
        tester,
        inside(find.widgetWithText(FilledButton, 'Post reply')),
      );
      await tester.pump();
      request.complete(save(change!));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(f.session.thread.comments.length, 2);
      expect(preview, findsOneWidget);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'dismissal retains shared drafts without attaching the inline focus node twice',
    (tester) async {
      final f = ReviewFixture(resolved: false);
      f.session.startReply();
      f.session.replyInput.text = 'Retained inline draft';
      await f.launch(tester);
      final mouse = await showPreview(tester);
      expect(f.session.replyFocus.hasFocus, isTrue);
      expect(inside(find.byType(TextField)), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.enterText(
        inside(find.byType(TextField)),
        'Edited from preview',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Discussion preview'), findsNothing);
      expect(f.session.replyInput.text, 'Edited from preview');
      expect(f.session.isReplying, isTrue);
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(inside(find.byType(TextField))).controller,
        same(f.session.replyInput),
      );
      expect(
        tester.widget<TextField>(inside(find.byType(TextField))).focusNode,
        isNot(same(f.session.replyFocus)),
      );
      await tester.enterText(
        inside(find.byType(TextField)),
        'Posted from preview',
      );
      await tapPreview(
        tester,
        inside(find.widgetWithText(FilledButton, 'Post reply')),
      );
      await tester.pumpAndSettle();
      expect(f.session.thread.comments.length, 2);
      expect(f.session.isReplying, isFalse);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'custom controls enforce current permissions, snapshots and source revision',
    (tester) async {
      final f = ReviewFixture();
      CommentGutterPreviewThreadDetails? commands;
      await f.launch(
        tester,
        wrap: (view) => SyntaxCommentGutterTheme(
          previewThreadController: (_) => f.session,
          previewActionsBuilder: (_, details, location, child) {
            commands = details.thread(location);
            return Wrap(
              children: [
                TextButton(
                  onPressed: commands?.reply,
                  child: const Text('Compose'),
                ),
                TextButton(
                  onPressed: commands?.toggleResolved,
                  child: const Text('Toggle'),
                ),
              ],
            );
          },
          previewComposerBuilder: (_, editor, child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: editor.controller.replyInput,
                focusNode: editor.focusNode,
                decoration: const InputDecoration(labelText: 'Custom input'),
              ),
              TextButton(
                onPressed: editor.submitReply,
                child: const Text('Send custom reply'),
              ),
            ],
          ),
          child: view,
        ),
      );
      final mouse = await showPreview(tester);
      final stale = commands!;
      f.session.permissions = const CommentThreadPermissions(
        reply: false,
        resolve: false,
      );
      await tester.pumpAndSettle();
      stale.reply!();
      expect(await stale.toggleResolved!(), isFalse);
      expect(inside(find.byType(TextField)), findsNothing);
      f.session.permissions = const CommentThreadPermissions();
      await tester.pumpAndSettle();
      await tester.tap(action('Compose'));
      await tester.pumpAndSettle();
      await tester.enterText(
        inside(find.byType(TextField)),
        'Custom saved reply',
      );
      await tester.pump();
      await tester.tap(action('Send custom reply'));
      await tester.pumpAndSettle();
      expect(f.session.thread.comments.last.body, 'Custom saved reply');
      expect(await stale.toggleResolved!(), isFalse);
      final staleSource = commands!;
      f.editor.applyEdits([const OffsetEdit(0, 0, 'changed')]);
      await tester.pumpAndSettle();
      expect(await staleSource.toggleResolved!(), isFalse);
      expect(f.session.thread.resolved, isTrue);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'in-flight saves survive dismissal but cannot overwrite changed source',
    (tester) async {
      var pending = Completer<ReviewThread>();
      ReviewThreadChange? request;
      final f = ReviewFixture(
        update: (change) {
          request = change;
          return pending.future;
        },
      );
      await f.launch(tester);
      final mouse = await showPreview(tester);
      await reply(tester, 'Saved after dismissal');
      await tapPreview(
        tester,
        inside(find.widgetWithText(FilledButton, 'Post reply')),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pump();
      pending.complete(save(request!));
      await tester.pumpAndSettle();
      expect(f.session.thread.comments.length, 2);
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byTooltip('Open discussion')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await reply(tester, 'Draft for obsolete source');
      pending = Completer<ReviewThread>();
      await tapPreview(
        tester,
        inside(find.widgetWithText(FilledButton, 'Post reply')),
      );
      await tester.pump();
      f.editor.applyEdits([const OffsetEdit(0, 0, 'changed')]);
      await tester.pump();
      pending.complete(save(request!));
      await tester.pumpAndSettle();
      expect(f.session.thread.comments.length, 2);
      expect(f.session.replyInput.text, 'Draft for obsolete source');
      expect(f.session.isSubmitting, isFalse);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}
