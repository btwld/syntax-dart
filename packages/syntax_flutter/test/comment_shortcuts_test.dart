import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

class ReviewFixture {
  final editor = EditorController(
    file: const SourceFile(id: 'file', path: 'file.txt', text: 'one\ntwo'),
  );
  final focus = FocusNode();
  final outside = FocusNode();
  final sessions = <CommentThreadController>[];
  late final navigation = CommentNavigationController.file(editor);
  int saves = 0;
  Completer<ReviewThread>? pending;

  ReviewFixture() {
    for (final id in ['a', 'b']) {
      sessions.add(
        CommentThreadController(
          thread: ReviewThread(
            id: id,
            comments: [
              ReviewComment(id: id, author: 'Reviewer', body: 'Message $id'),
            ],
          ),
          onUpdate: (change) {
            saves++;
            return pending?.future ??
                change.thread.copyWith(
                  resolved: change.resolved,
                  comments: change.kind == ReviewThreadChangeKind.reply
                      ? [
                          ...change.thread.comments,
                          ReviewComment(
                            id: 'reply-$saves',
                            author: 'You',
                            body: change.text!,
                          ),
                        ]
                      : null,
                );
          },
        )..addListener(sync),
      );
    }
    sync();
  }

  void sync() => editor.setAnnotations([
    for (var i = 0; i < sessions.length; i++)
      LineAnnotation(
        id: sessions[i].thread.id,
        start: i * 4,
        end: i * 4 + 1,
        data: sessions[i].thread,
      ),
  ]);

  CommentThreadController session(CommentThreadLocation location) =>
      sessions.firstWhere((session) => session.thread.id == location.thread.id);

  Widget build({
    List<CommentShortcutBinding> bindings = defaultCommentShortcuts,
    bool enabled = true,
    bool allowInTextFields = false,
    String? fileId,
  }) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          TextField(
            focusNode: outside,
            decoration: const InputDecoration(labelText: 'Outside'),
          ),
          Expanded(
            child: SyntaxCommentShortcuts(
              controller: navigation,
              threadController: session,
              focusNode: focus,
              autofocus: true,
              bindings: bindings,
              enabled: enabled,
              fileId: fileId,
              allowInTextFields: allowInTextFields,
              child: Column(
                children: [
                  SyntaxCommentNavigation(controller: navigation),
                  Expanded(
                    child: SyntaxFileView(
                      controller: editor,
                      highlighter: Highlighter(),
                      theme: githubDarkTheme,
                      commentNavigation: navigation,
                      annotationBuilder: (_, a) => SyntaxCommentThread(
                        controller: sessions.firstWhere(
                          (s) => s.thread.id == a.id,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    navigation.dispose();
    editor.dispose();
    for (final session in sessions) {
      session.dispose();
    }
    focus.dispose();
    outside.dispose();
  }
}

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool alt = true,
  bool settle = true,
}) async {
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('nested scopes dispatch only to the nearest review', (
    tester,
  ) async {
    var outerVisits = 0, innerVisits = 0;
    CommentNavigationController navigation(bool outer) =>
        CommentNavigationController(
          onReveal: (_) {
            outer ? outerVisits++ : innerVisits++;
            return true;
          },
          threads: [
            CommentThreadLocation(
              fileId: 'file',
              annotationId: 'a',
              line: 0,
              thread: ReviewThread(
                id: 'a',
                comments: [
                  const ReviewComment(id: 'a', author: 'You', body: 'Note'),
                ],
              ),
            ),
          ],
        );
    final outer = navigation(true), inner = navigation(false);
    await tester.pumpWidget(
      MaterialApp(
        home: SyntaxCommentShortcuts(
          controller: outer,
          child: SyntaxCommentShortcuts(
            controller: inner,
            autofocus: true,
            child: const Text('Nested review'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(innerVisits, 1);
    expect(outerVisits, 0);
    await tester.pumpWidget(const SizedBox());
    outer.dispose();
    inner.dispose();
  });

  testWidgets(
    'apps can opt into input shortcuts and restrict commands to a file',
    (tester) async {
      final fixture = ReviewFixture();
      await tester.pumpWidget(fixture.build(fileId: 'other'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current, isNull);
      fixture.navigation.select('file', 'a');
      await key(tester, LogicalKeyboardKey.keyR);
      expect(fixture.sessions.first.isReplying, isFalse);
      await tester.pumpWidget(fixture.build(allowInTextFields: true));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyR);
      expect(fixture.sessions.first.replyFocus.hasFocus, isTrue);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current?.annotationId, 'b');
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'obsolete session snapshots cannot be changed through a shortcut',
    (tester) async {
      final fixture = ReviewFixture();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      fixture.editor.setAnnotations([
        LineAnnotation(
          id: 'a',
          start: 0,
          end: 1,
          data: fixture.sessions.first.thread.copyWith(revision: 9),
        ),
      ]);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.enter);
      await key(tester, LogicalKeyboardKey.keyR);
      expect(fixture.saves, 0);
      expect(fixture.sessions.first.isReplying, isFalse);
      await fixture.dispose(tester);
    },
  );
  testWidgets(
    'default hotkeys navigate, reply, resolve and reopen selected threads',
    (tester) async {
      final fixture = ReviewFixture();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current?.annotationId, 'a');
      expect(find.byTooltip('Next discussion (Alt/Option+↓)'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current?.annotationId, 'b');
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(fixture.navigation.current?.annotationId, 'a');
      await key(tester, LogicalKeyboardKey.keyR);
      expect(fixture.sessions.first.isReplying, isTrue);
      expect(fixture.sessions.first.replyFocus.hasFocus, isTrue);
      await tester.enterText(
        find.widgetWithText(TextField, 'Comment'),
        'Draft stays here',
      );
      await key(tester, LogicalKeyboardKey.enter);
      expect(fixture.saves, 0);
      expect(fixture.sessions.first.replyInput.text, 'Draft stays here');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current?.annotationId, 'a');
      fixture.focus.requestFocus();
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
      expect(fixture.sessions.first.thread.resolved, isTrue);
      expect(fixture.sessions.first.isCollapsed, isTrue);
      expect(fixture.sessions.first.replyInput.text, 'Draft stays here');
      await key(tester, LogicalKeyboardKey.enter);
      expect(fixture.sessions.first.thread.resolved, isFalse);
      expect(fixture.sessions.first.isCollapsed, isFalse);
      expect(fixture.saves, 2);
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'pointer and focus select the intended thread without a reveal request',
    (tester) async {
      final fixture = ReviewFixture();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message b'));
      await tester.pumpAndSettle();
      expect(fixture.navigation.current?.annotationId, 'b');
      expect(fixture.navigation.revealTarget, isNull);
      expect(fixture.editor.revealRequest, 0);
      await key(tester, LogicalKeyboardKey.keyR);
      expect(fixture.sessions.last.isReplying, isTrue);
      expect(fixture.sessions.first.isReplying, isFalse);
      // Focusing a command in another thread changes the target too.
      Focus.of(tester.element(find.text('Resolve').first)).requestFocus();
      await tester.pumpAndSettle();
      expect(fixture.navigation.current?.annotationId, 'a');
      await key(tester, LogicalKeyboardKey.enter);
      expect(fixture.sessions.first.thread.resolved, isTrue);
      expect(fixture.sessions.last.thread.resolved, isFalse);
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'custom bindings replace defaults, preserve typing, and can be disabled',
    (tester) async {
      final fixture = ReviewFixture();
      const bindings = [
        CommentShortcutBinding(
          activator: SingleActivator(LogicalKeyboardKey.keyJ),
          command: CommentShortcutCommand.next,
          label: 'J',
        ),
        CommentShortcutBinding(
          activator: SingleActivator(LogicalKeyboardKey.keyR),
          command: CommentShortcutCommand.reply,
          label: 'R',
        ),
      ];
      await tester.pumpWidget(fixture.build(bindings: bindings));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current, isNull);
      await key(tester, LogicalKeyboardKey.keyJ, alt: false);
      expect(fixture.navigation.current?.annotationId, 'a');
      expect(find.byTooltip('Next discussion (J)'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyR, alt: false);
      await key(tester, LogicalKeyboardKey.keyJ, alt: false);
      expect(fixture.navigation.current?.annotationId, 'a');
      fixture.focus.requestFocus();
      await tester.pumpWidget(fixture.build(bindings: const []));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Next discussion'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyJ, alt: false);
      expect(fixture.navigation.current?.annotationId, 'a');
      await tester.pumpWidget(
        fixture.build(bindings: bindings, enabled: false),
      );
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyJ, alt: false);
      expect(fixture.navigation.current?.annotationId, 'a');
      await fixture.dispose(tester);
    },
  );

  testWidgets(
    'outside focus and modal dialogs cannot trigger review commands',
    (tester) async {
      final fixture = ReviewFixture();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      fixture.outside.requestFocus();
      await tester.pump();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current, isNull);
      fixture.focus.requestFocus();
      await tester.pump();
      final context = tester.element(find.byType(SyntaxCommentShortcuts));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Dialog')),
        ),
      );
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current, isNull);
      await key(tester, LogicalKeyboardKey.escape, alt: false);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current?.annotationId, 'a');
      await fixture.dispose(tester);
      await key(tester, LogicalKeyboardKey.enter);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permissions, pending saves, repeated keys and filters guard actions',
    (tester) async {
      final fixture = ReviewFixture();
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyR);
      expect(fixture.sessions.every((session) => !session.isReplying), isTrue);
      await key(tester, LogicalKeyboardKey.arrowDown);
      fixture.sessions.first.permissions = const CommentThreadPermissions(
        reply: false,
        resolve: false,
      );
      await key(tester, LogicalKeyboardKey.keyR);
      await key(tester, LogicalKeyboardKey.enter);
      expect(fixture.saves, 0);
      fixture.sessions.first.permissions = const CommentThreadPermissions();
      fixture.pending = Completer<ReviewThread>();
      await key(tester, LogicalKeyboardKey.enter, settle: false);
      await key(tester, LogicalKeyboardKey.enter, settle: false);
      expect(fixture.saves, 1);
      fixture.pending!.complete(
        fixture.sessions.first.thread.copyWith(resolved: true),
      );
      await tester.pumpAndSettle();
      fixture.pending = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(fixture.saves, 2);
      expect(fixture.sessions.first.thread.resolved, isFalse);
      fixture.navigation.filter = CommentThreadFilter.resolved;
      await key(tester, LogicalKeyboardKey.enter);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(fixture.navigation.current, isNull);
      expect(fixture.saves, 2);
      await fixture.dispose(tester);
    },
  );
}
