import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'interaction_test.dart' show app;

ReviewThread initialThread() => ReviewThread(
  id: 'thread',
  comments: const [
    ReviewComment(
      id: 'root',
      author: 'Morgan',
      authorId: 'm',
      body: 'Original note',
    ),
  ],
);

ReviewThread save(ReviewThreadChange change) => switch (change.kind) {
  ReviewThreadChangeKind.reply => change.thread.copyWith(
    comments: [
      ...change.thread.comments,
      ReviewComment(
        id: 'reply-${change.thread.revision}',
        author: 'You',
        authorId: 'you',
        body: change.text!,
      ),
    ],
  ),
  ReviewThreadChangeKind.edit => change.thread.copyWith(
    comments: [
      for (final message in change.thread.comments)
        if (message.id == change.commentId)
          message.edit(change.text!, editedAt: DateTime.utc(2026))
        else
          message,
    ],
  ),
  ReviewThreadChangeKind.delete => change.thread.copyWith(
    comments: change.thread.comments.where(
      (message) => message.id != change.commentId,
    ),
  ),
  ReviewThreadChangeKind.resolve => change.thread.copyWith(
    resolved: change.resolved,
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'commands preserve identity, confirmation and replies when deleting root',
    () async {
      final changes = <ReviewThreadChange>[];
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: (change) {
          changes.add(change);
          return save(change);
        },
      );
      controller.startReply();
      expect(await controller.submitReply(), isFalse);
      controller.replyInput.text = '  Reply 😀\nSecond line  ';
      expect(await controller.submitReply(), isTrue);
      expect(controller.thread.comments.last.body, 'Reply 😀\nSecond line');
      expect(controller.replyInput.text, isEmpty);
      controller.startEdit('root');
      controller.editInput.text = 'Edited';
      expect(await controller.submitEdit(), isTrue);
      expect(controller.thread.comment('root')!.body, 'Edited');
      expect(controller.thread.comment('root')!.editedAt, isNotNull);
      controller.requestDelete('root');
      expect(changes.length, 2);
      controller.cancelDelete();
      expect(await controller.confirmDelete(), isFalse);
      controller.requestDelete('root');
      expect(await controller.confirmDelete(), isTrue);
      expect(controller.thread.id, 'thread');
      expect(controller.thread.comments.single.id, 'reply-0');
      await controller.toggleResolved();
      expect(controller.thread.resolved, isTrue);
      await controller.toggleResolved();
      expect(controller.thread.resolved, isFalse);
      controller.requestDelete('reply-0');
      await controller.confirmDelete();
      expect(controller.thread.comments, isEmpty);
      expect(controller.mayReply, isFalse);
      controller.dispose();
    },
  );

  test(
    'permissions apply to commands and read-only sessions never mutate',
    () async {
      var calls = 0;
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: (change) {
          calls++;
          return save(change);
        },
        permissions: const CommentThreadPermissions(
          reply: false,
          resolve: false,
          edit: null,
          delete: null,
        ),
      );
      controller.startReply();
      controller.startEdit('root');
      controller.requestDelete('root');
      expect(controller.isReplying, isFalse);
      expect(controller.editingId, isNull);
      expect(controller.deletingId, isNull);
      expect(await controller.toggleResolved(), isFalse);
      expect(calls, 0);
      controller.permissions = CommentThreadPermissions(
        edit: (message) => message.authorId == 'm',
        delete: null,
      );
      controller.startEdit('root');
      controller.editInput.text = 'Unsaved';
      controller.permissions = const CommentThreadPermissions(edit: null);
      expect(await controller.submitEdit(), isFalse);
      expect(controller.editInput.text, 'Unsaved');
      controller.cancelEdit();
      controller.dispose();
      final readOnly = CommentThreadController(thread: initialThread());
      expect(readOnly.mayReply, isFalse);
      expect(readOnly.mayEdit(readOnly.thread.comments.single), isFalse);
      readOnly.dispose();
    },
  );

  test(
    'async errors retain drafts and duplicate requests cannot submit',
    () async {
      var pending = Completer<ReviewThread>();
      var calls = 0;
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: (change) {
          calls++;
          return pending.future;
        },
      );
      controller.startReply();
      controller.replyInput.text = 'Retry me';
      final first = controller.submitReply();
      expect(controller.isSubmitting, isTrue);
      expect(await controller.submitReply(), isFalse);
      controller.cancelReply();
      expect(controller.isReplying, isTrue);
      pending.completeError(StateError('offline'));
      expect(await first, isFalse);
      expect(controller.error, isA<StateError>());
      expect(controller.replyInput.text, 'Retry me');
      pending = Completer<ReviewThread>();
      final retry = controller.submitReply();
      pending.complete(
        save(ReviewThreadChange.reply(controller.thread, 'Retry me')),
      );
      expect(await retry, isTrue);
      expect(calls, 2);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );

  test(
    'external revisions invalidate stale saves without erasing drafts',
    () async {
      final pending = Completer<ReviewThread>();
      final before = initialThread();
      final controller = CommentThreadController(
        thread: before,
        onUpdate: (_) => pending.future,
      );
      controller.startReply();
      controller.replyInput.text = 'Keep my draft';
      final saving = controller.submitReply();
      final external = before.copyWith(resolved: true, revision: 7);
      controller.setThread(external);
      pending.complete(save(ReviewThreadChange.reply(before, 'Keep my draft')));
      expect(await saving, isFalse);
      expect(identical(controller.thread, external), isTrue);
      expect(controller.replyInput.text, 'Keep my draft');
      expect(controller.isSubmitting, isFalse);
      expect(() => controller.setThread(before), throwsArgumentError);
      expect(
        () => controller.setThread(
          ReviewThread(id: 'other', comments: [], revision: 8),
        ),
        throwsArgumentError,
      );
      controller.dispose();
    },
  );

  test(
    'remote edits protect the source message and invalidate delete confirmation',
    () async {
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: save,
      );
      controller.startEdit('root');
      controller.editInput.text = 'Local draft';
      controller.requestDelete('root');
      controller.setThread(
        controller.thread.copyWith(
          comments: [controller.thread.comments.single.edit('Remote update')],
        ),
      );
      expect(controller.editIsStale, isTrue);
      expect(controller.deletingId, isNull);
      expect(await controller.submitEdit(), isFalse);
      expect(controller.editInput.text, 'Local draft');
      expect(controller.thread.comments.single.body, 'Remote update');
      controller.cancelEdit();
      controller.startEdit('root');
      expect(controller.editInput.text, 'Remote update');
      controller.dispose();
    },
  );

  test(
    'draft changes during a save are retained for a subsequent submission',
    () async {
      var pending = Completer<ReviewThread>();
      late ReviewThreadChange request;
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: (change) {
          request = change;
          return pending.future;
        },
      );
      controller.startReply();
      controller.replyInput.text = 'First';
      final first = controller.submitReply();
      controller.replyInput.text = 'Next draft';
      pending.complete(save(request));
      await first;
      expect(controller.replyInput.text, 'Next draft');
      expect(controller.isReplying, isTrue);
      controller.startEdit('root');
      controller.editInput.text = 'First edit';
      pending = Completer<ReviewThread>();
      final edit = controller.submitEdit();
      controller.editInput.text = 'Next edit';
      pending.complete(save(request));
      await edit;
      expect(controller.editInput.text, 'Next edit');
      expect(controller.editingId, 'root');
      expect(controller.editIsStale, isFalse);
      controller.dispose();
    },
  );

  test(
    'invalid callback results and disposal cannot corrupt a session',
    () async {
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: (change) => change.thread,
      );
      expect(await controller.toggleResolved(), isFalse);
      expect(controller.error, isA<StateError>());
      expect(controller.thread.resolved, isFalse);
      controller.dispose();
      final pending = Completer<ReviewThread>();
      final disposed = CommentThreadController(
        thread: initialThread(),
        onUpdate: (_) => pending.future,
      );
      final saving = disposed.toggleResolved();
      disposed.dispose();
      pending.complete(initialThread().copyWith(resolved: true));
      expect(await saving, isFalse);
      expect(() => disposed.startReply(), throwsStateError);
    },
  );

  testWidgets(
    'default inline thread supports reply edit delete resolve and reopen',
    (tester) async {
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: save,
      );
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: SyntaxCommentThread(controller: controller),
          ),
        ),
      );
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A reply');
      await tester.pump();
      await tester.ensureVisible(find.text('Post reply'));
      await tester.tap(find.text('Post reply'));
      await tester.pumpAndSettle();
      expect(find.text('A reply'), findsOneWidget);
      final reply = find.byKey(const ValueKey('reply-0'));
      await tester.tap(find.descendant(of: reply, matching: find.text('Edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'An edited reply');
      await tester.pump();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Edited'), findsOneWidget);
      await tester.ensureVisible(find.text('Resolve'));
      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('An edited reply'), findsOneWidget);
      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();
      expect(controller.thread.resolved, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('root')));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('root')),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Delete this comment?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Original note'), findsNothing);
      expect(controller.thread.comments.single.body, 'An edited reply');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'custom builders control the full thread, messages, editors and actions',
    (tester) async {
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: save,
      );
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: SyntaxCommentThread(
              controller: controller,
              builder: (_, details, child) => Column(
                children: [Text('Custom ${details.thread.id}'), child],
              ),
              headerBuilder: (_, details) =>
                  Text('Status: ${details.thread.resolved}'),
              commentBuilder: (_, details, child) => Column(
                children: [Text('Custom message ${details.comment.id}'), child],
              ),
              commentActionsBuilder: (_, details) => TextButton(
                onPressed: details.edit,
                child: const Text('Rewrite'),
              ),
              actionsBuilder: (_, details) => Wrap(
                children: [
                  TextButton(
                    onPressed: details.reply,
                    child: const Text('Respond'),
                  ),
                  TextButton(
                    onPressed: details.toggleResolved,
                    child: const Text('Toggle status'),
                  ),
                ],
              ),
              composerBuilder: (_, details) => Column(
                children: [
                  TextField(
                    controller: details.controller,
                    focusNode: details.focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Custom response',
                    ),
                  ),
                  TextButton(
                    onPressed: details.submit,
                    child: const Text('Publish'),
                  ),
                  TextButton(
                    onPressed: details.cancel,
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Respond'));
      await tester.pumpAndSettle();
      expect(find.text('Custom thread'), findsOneWidget);
      expect(find.text('Custom message root'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Publish'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Custom reply');
      await tester.pump();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(controller.thread.comments.last.body, 'Custom reply');
      await tester.tap(find.text('Toggle status'));
      await tester.pumpAndSettle();
      expect(find.text('Status: true'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'busy errors stale edits and revoked permissions have inline feedback',
    (tester) async {
      final pending = Completer<ReviewThread>();
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: (_) => pending.future,
      );
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: SyntaxCommentThread(
              controller: controller,
              errorBuilder: (_, _, _) => const Text('Connection unavailable'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Draft');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      pending.completeError(StateError('private server details'));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(find.textContaining('private server'), findsNothing);
      controller.setThread(
        controller.thread.copyWith(
          comments: [controller.thread.comments.single.edit('Remote')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('This comment changed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save changes'),
            )
            .onPressed,
        isNull,
      );
      expect(controller.editInput.text, 'Draft');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'file annotations retain reply drafts across virtualization and source-copy shortcuts',
    (tester) async {
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: save,
      );
      final editor = EditorController(
        file: SourceFile(
          id: 'file',
          path: 'file.txt',
          text: List.generate(1500, (i) => 'row $i').join('\n'),
        ),
      );
      editor.setAnnotations([
        const LineAnnotation(id: 'thread', start: 0, end: 5, data: 'thread'),
      ]);
      editor.selectLines(0, 0);
      final scroll = ScrollController();
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
      await tester.pumpWidget(
        app(
          SyntaxFileView(
            controller: editor,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            scrollController: scroll,
            annotationBuilder: (_, _) =>
                SyntaxCommentThread(controller: controller),
          ),
        ),
      );
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Retained reply');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, 'Retained reply');
      controller.replyFocus.unfocus();
      scroll.jumpTo(20000);
      await tester.pumpAndSettle();
      expect(find.byType(SyntaxCommentThread), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Retained reply'), findsOneWidget);
      expect(editor.document.text, startsWith('row 0\nrow 1'));
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      controller.dispose();
      editor.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'diff threads retain edits when folded or switched between layouts',
    (tester) async {
      final controller = CommentThreadController(
        thread: initialThread(),
        onUpdate: save,
      );
      final review = PatchController([
        diffTexts(
          'one\ntwo\nthree',
          'one\nchanged\nthree',
          id: 'file',
          path: 'file.txt',
        ),
      ]);
      review.setAnnotations([
        const ReviewAnnotation(
          id: 'thread',
          fileId: 'file',
          side: DiffSide.newer,
          line: 2,
          data: 'thread',
        ),
      ]);
      await tester.pumpWidget(
        app(
          PatchView.controlled(
            controller: review,
            highlighter: Highlighter(),
            theme: githubDarkTheme,
            annotationBuilder: (_, _) =>
                SyntaxCommentThread(controller: controller),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Keep this edit');
      await tester.pumpAndSettle();
      review.toggleFile('file');
      await tester.pumpAndSettle();
      expect(find.byType(SyntaxCommentThread), findsNothing);
      review.toggleFile('file');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Keep this edit'), findsOneWidget);
      review.mode = DiffMode.split;
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Keep this edit'), findsOneWidget);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(controller.thread.comments.single.body, 'Keep this edit');
      expect(review.files.single.newText, 'one\nchanged\nthree');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      review.dispose();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'thread controls wrap at compact width in ${dark ? 'dark' : 'light'} palettes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = CommentThreadController(
          thread: initialThread(),
          onUpdate: save,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SyntaxCommentThread(controller: controller),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Reply'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Long reply\nsecond line\nthird line',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
