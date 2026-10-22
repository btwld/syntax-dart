import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

const exampleCommentShortcuts = [
  CommentShortcutBinding(
    activator: SingleActivator(LogicalKeyboardKey.keyK),
    command: CommentShortcutCommand.previous,
    label: 'K',
  ),
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
  CommentShortcutBinding(
    activator: SingleActivator(LogicalKeyboardKey.keyX),
    command: CommentShortcutCommand.toggleResolved,
    label: 'X',
  ),
];

class ExampleCommentShortcutHelp extends StatelessWidget {
  const ExampleCommentShortcutHelp({super.key});
  @override
  Widget build(BuildContext context) {
    final bindings = SyntaxCommentShortcuts.bindingsOf(context);
    return TextButton.icon(
      icon: const Icon(Icons.keyboard_outlined, size: 16),
      label: const Text('Discussion shortcuts'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discussion shortcuts'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final binding in bindings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${binding.label} — ${switch (binding.command) {
                        CommentShortcutCommand.previous => 'Previous thread',
                        CommentShortcutCommand.next => 'Next thread',
                        CommentShortcutCommand.reply => 'Reply to selected thread',
                        CommentShortcutCommand.toggleResolved => 'Resolve / reopen selected thread',
                      }}',
                    ),
                  ),
                const Text(
                  'Click a discussion or use next/previous to select it. '
                  'Shortcuts apply inside this review area and pause while typing. '
                  'Ctrl/Cmd+Enter submits a reply; Escape cancels its draft.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Application-owned in-memory persistence and session lifetime for the gallery.
class ExampleCommentThreads {
  final _sessions = <String, CommentThreadController>{};
  final _callbacks = <String, ValueChanged<ReviewThread>>{};
  final _retired = <CommentThreadController>{};
  int _nextId = 0;

  ReviewThread create(
    String text, {
    String? id,
    String author = 'You',
    String authorId = 'viewer',
  }) => ReviewThread(
    id: id ?? 'discussion-${++_nextId}',
    comments: [
      ReviewComment(
        id: 'message-${++_nextId}',
        author: author,
        authorId: authorId,
        body: text,
        createdAt: DateTime.now(),
      ),
    ],
  );

  ReviewThread _save(ReviewThreadChange change) {
    final thread = change.thread;
    return switch (change.kind) {
      ReviewThreadChangeKind.reply => thread.copyWith(
        comments: [
          ...thread.comments,
          ReviewComment(
            id: 'message-${++_nextId}',
            author: 'You',
            authorId: 'viewer',
            body: change.text!,
            createdAt: DateTime.now(),
          ),
        ],
      ),
      ReviewThreadChangeKind.edit => thread.copyWith(
        comments: [
          for (final message in thread.comments)
            if (message.id == change.commentId)
              message.edit(change.text!, editedAt: DateTime.now())
            else
              message,
        ],
      ),
      ReviewThreadChangeKind.delete => thread.copyWith(
        comments: thread.comments.where(
          (message) => message.id != change.commentId,
        ),
      ),
      ReviewThreadChangeKind.resolve => thread.copyWith(
        resolved: change.resolved,
      ),
    };
  }

  CommentThreadController session(
    ReviewThread thread, {
    required ValueChanged<ReviewThread> onChanged,
  }) {
    _callbacks[thread.id] = onChanged;
    final controller = _sessions.putIfAbsent(thread.id, () {
      var published = thread;
      final controller = CommentThreadController(
        thread: thread,
        onUpdate: _save,
        permissions: CommentThreadPermissions(
          edit: (message) => message.authorId == 'viewer',
          delete: (message) => message.authorId == 'viewer',
        ),
      );
      controller.addListener(() {
        final current = controller.thread;
        if (identical(current, published)) return;
        published = current;
        _callbacks[thread.id]?.call(current);
        if (current.comments.isEmpty) {
          _sessions.remove(thread.id);
          _callbacks.remove(thread.id);
          _retire(controller);
        }
      });
      return controller;
    });
    return controller;
  }

  Widget view(
    ReviewThread thread, {
    required ValueChanged<ReviewThread> onChanged,
    bool custom = false,
  }) {
    final controller = session(thread, onChanged: onChanged);
    return SyntaxCommentThread(
      key: ValueKey(thread.id),
      controller: controller,
      builder: custom
          ? (context, details, child) => DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    width: 3,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              child: child,
            )
          : null,
      headerBuilder: custom
          ? (context, details) => Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.forum_outlined, size: 18),
                const Text(
                  'Team discussion',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${details.thread.comments.length} '
                  '${details.thread.comments.length == 1 ? 'message' : 'messages'}',
                ),
                if (details.thread.resolved)
                  const Chip(label: Text('Completed')),
              ],
            )
          : null,
      collapsedBuilder: custom
          ? (context, details, child) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Team review · ${details.thread.comments.length} '
                  '${details.thread.comments.length == 1 ? 'message' : 'messages'}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                child,
              ],
            )
          : null,
      collapsedActionsBuilder: custom
          ? (context, details) => Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Semantics(
                  expanded: false,
                  child: TextButton.icon(
                    onPressed: details.expand,
                    icon: const Icon(Icons.unfold_more, size: 16),
                    label: const Text('Show discussion'),
                  ),
                ),
                TextButton(
                  onPressed: details.toggleResolved,
                  child: const Text('Reopen thread'),
                ),
              ],
            )
          : null,
      actionsBuilder: custom
          ? (context, details) => Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (details.thread.resolved)
                  Semantics(
                    expanded: true,
                    child: TextButton(
                      onPressed: details.collapse,
                      child: const Text('Hide discussion'),
                    ),
                  ),
                if (!controller.isReplying)
                  TextButton(
                    onPressed: details.reply,
                    child: const Text('Reply to thread'),
                  ),
                TextButton(
                  onPressed: details.toggleResolved,
                  child: Text(
                    details.thread.resolved ? 'Reopen thread' : 'Mark resolved',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: details.thread.comments
                          .map(
                            (comment) => '${comment.author}: ${comment.body}',
                          )
                          .join('\n\n'),
                    ),
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy discussion'),
                ),
              ],
            )
          : null,
      commentActionsBuilder: custom
          ? (context, details) => Wrap(
              children: [
                if (controller.mayEdit(details.comment))
                  IconButton(
                    tooltip: 'Edit message',
                    onPressed: details.edit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                  ),
                if (controller.mayDelete(details.comment))
                  IconButton(
                    tooltip: 'Remove message',
                    onPressed: details.delete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                  ),
              ],
            )
          : null,
      composerBuilder: custom
          ? (context, details) => SyntaxCommentComposer(
              controller: details.controller,
              focusNode: details.focusNode,
              isSubmitting: details.thread.isSubmitting,
              canSubmit: details.submit != null,
              errorText: details.errorText,
              title: details.comment == null
                  ? 'Join the discussion'
                  : 'Update your message',
              inputDecoration: const InputDecoration(
                labelText: 'Your response',
                filled: true,
                border: OutlineInputBorder(),
              ),
              margin: EdgeInsets.zero,
              onSubmit: (_) => details.submit?.call(),
              onCancel: () => details.cancel?.call(),
              actionsBuilder: (context, _) => Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: details.cancel,
                    child: const Text('Cancel draft'),
                  ),
                  FilledButton.icon(
                    onPressed: details.submit,
                    icon: const Icon(Icons.send_outlined, size: 16),
                    label: Text(
                      details.comment == null ? 'Send reply' : 'Save message',
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  void _retire(CommentThreadController controller) {
    _retired.add(controller);
    // Let fields unmount before disposing their retained input controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retired.remove(controller)) controller.dispose();
    });
  }

  void clear() {
    for (final controller in _sessions.values) {
      _retire(controller);
    }
    _sessions.clear();
    _callbacks.clear();
  }

  void dispose() {
    for (final controller in {..._sessions.values, ..._retired}) {
      controller.dispose();
    }
    _sessions.clear();
    _retired.clear();
    _callbacks.clear();
  }
}
