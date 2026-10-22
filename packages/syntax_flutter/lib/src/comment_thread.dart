import 'package:flutter/material.dart';
import 'package:syntax/syntax.dart';
import 'comment_composer.dart';
import 'comment_thread_controller.dart';
import 'inline_comment_region.dart';

/// Localizable labels used by the default inline discussion UI.
@immutable
class CommentThreadLabels {
  /// Overrides labels without replacing the default presentation.
  const CommentThreadLabels({
    this.title = 'Discussion',
    this.reply = 'Reply',
    this.postReply = 'Post reply',
    this.edit = 'Edit',
    this.editTitle = 'Edit comment',
    this.save = 'Save changes',
    this.delete = 'Delete',
    this.deleteQuestion = 'Delete this comment?',
    this.cancel = 'Cancel',
    this.resolve = 'Resolve',
    this.reopen = 'Reopen',
    this.resolved = 'Resolved',
    this.open = 'Open',
    this.expand = 'Expand discussion',
    this.collapse = 'Collapse discussion',
    this.edited = 'Edited',
    this.inputLabel = 'Comment',
    this.failure = 'Could not update this discussion. Try again.',
    this.staleEdit =
        'This comment changed. Copy your draft, then cancel and edit the latest version.',
  });

  /// Thread heading and reply labels.
  final String title, reply, postReply;

  /// Message edit and save labels.
  final String edit, editTitle, save;

  /// Inline deletion and cancellation labels.
  final String delete, deleteQuestion, cancel;

  /// Resolution commands and status labels.
  final String resolve, reopen, resolved, open;

  /// Commands to inspect or hide a resolved thread without changing its status.
  final String expand, collapse;

  /// Edited marker and default input label.
  final String edited, inputLabel;

  /// Default persistence failure and concurrent-edit feedback.
  final String failure, staleEdit;
}

/// Current thread state and guarded commands for custom thread builders.
class CommentThreadDetails {
  /// Wraps an application-owned session without taking ownership of it.
  const CommentThreadDetails(this.controller);

  /// Retained state and asynchronous commands, including custom workflows.
  final CommentThreadController controller;

  /// Current authoritative thread snapshot.
  ReviewThread get thread => controller.thread;

  /// Whether an application request is pending.
  bool get isSubmitting => controller.isSubmitting;

  /// Whether only the resolved summary is visible.
  bool get isCollapsed => controller.isCollapsed;

  /// Shows a collapsed discussion, including in read-only sessions.
  VoidCallback? get expand => isCollapsed ? controller.expand : null;

  /// Hides an expanded resolved discussion without changing its status.
  VoidCallback? get collapse =>
      thread.resolved && !isCollapsed ? controller.collapse : null;

  /// Opens a reply editor, or null when busy or not permitted.
  VoidCallback? get reply =>
      !isSubmitting && controller.mayReply ? controller.startReply : null;

  /// Resolves/reopens, or null when busy or not permitted.
  VoidCallback? get toggleResolved => !isSubmitting && controller.mayResolve
      ? () {
          controller.toggleResolved();
        }
      : null;
}

/// A message and guarded actions passed to custom message/action builders.
class CommentMessageDetails {
  /// Describes one posted message by stable identity.
  const CommentMessageDetails(this.thread, this.comment);

  /// Containing thread and retained state.
  final CommentThreadDetails thread;

  /// Current message, including author and optional timestamps.
  final ReviewComment comment;

  /// Opens the inline edit form, or null while busy or unauthorized.
  VoidCallback? get edit =>
      !thread.isSubmitting &&
          thread.controller.mayEdit(comment) &&
          (thread.controller.editingId == null ||
              thread.controller.editingId == comment.id)
      ? () => thread.controller.startEdit(comment.id)
      : null;

  /// Opens inline delete confirmation, or null while busy or unauthorized.
  VoidCallback? get delete =>
      !thread.isSubmitting && thread.controller.mayDelete(comment)
      ? () => thread.controller.requestDelete(comment.id)
      : null;
}

/// Retained input and commands for a custom reply or message editor.
class CommentThreadComposerDetails {
  /// Describes an editor without owning its controller or focus.
  const CommentThreadComposerDetails({
    required this.thread,
    required this.comment,
    required this.controller,
    required this.focusNode,
    required this.submit,
    required this.cancel,
    required this.errorText,
  });

  /// Containing thread and request state.
  final CommentThreadDetails thread;

  /// Message being edited; null for a reply.
  final ReviewComment? comment;

  /// Draft and focus retained outside the virtualized row.
  final TextEditingController controller;

  /// Retained focus, also usable by custom rich inputs.
  final FocusNode focusNode;

  /// Null for busy, empty, stale or unauthorized submissions.
  final VoidCallback? submit;

  /// Discards the draft; null while a request is pending.
  final VoidCallback? cancel;

  /// Feedback for a draft that can no longer overwrite its source message.
  final String? errorText;
}

/// An inline, application-owned review discussion with replaceable UI.
///
/// Place this widget in a file/diff `annotationBuilder`. Retain [controller]
/// outside the builder so replies and edits survive virtualization. All changes
/// go through the controller's application callback; no backend is assumed.
class SyntaxCommentThread extends StatelessWidget {
  /// Provides replies, message editing/deletion and resolve/reopen controls.
  const SyntaxCommentThread({
    super.key,
    required this.controller,
    this.labels = const CommentThreadLabels(),
    this.builder,
    this.headerBuilder,
    this.actionsBuilder,
    this.collapsedBuilder,
    this.collapsedActionsBuilder,
    this.commentBuilder,
    this.commentActionsBuilder,
    this.composerBuilder,
    this.errorBuilder,
    this.decoration,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.textStyle,
  });

  /// Application-owned thread session; never disposed by this widget.
  final CommentThreadController controller;

  /// Localizable text for the default presentation.
  final CommentThreadLabels labels;

  /// Replaces or wraps the entire thread, with the default tree as its child.
  final Widget Function(BuildContext, CommentThreadDetails, Widget)? builder;

  /// Replaces the thread heading and resolution status.
  final Widget Function(BuildContext, CommentThreadDetails)? headerBuilder;

  /// Replaces thread-wide reply and resolve/reopen actions.
  final Widget Function(BuildContext, CommentThreadDetails)? actionsBuilder;

  /// Replaces or wraps the compact resolved summary and its inline actions.
  /// The surrounding card, error feedback and whole-thread [builder] still
  /// apply. Details expose expansion state and guarded expand/reopen commands.
  final Widget Function(BuildContext, CommentThreadDetails, Widget)?
  collapsedBuilder;

  /// Replaces the compact summary's expand and reopen actions.
  final Widget Function(BuildContext, CommentThreadDetails)?
  collapsedActionsBuilder;

  /// Replaces or wraps a full posted message, including its inline controls.
  final Widget Function(BuildContext, CommentMessageDetails, Widget)?
  commentBuilder;

  /// Replaces a posted message's edit/delete action bar.
  final Widget Function(BuildContext, CommentMessageDetails)?
  commentActionsBuilder;

  /// Replaces reply and edit forms, including their input and action areas.
  final Widget Function(BuildContext, CommentThreadComposerDetails)?
  composerBuilder;

  /// Renders application failures without exposing exception details by default.
  final Widget Function(BuildContext, CommentThreadDetails, Object)?
  errorBuilder;

  /// Card background, border and shape; defaults to the surrounding code theme.
  final Decoration? decoration;

  /// Spacing inside and outside the card.
  final EdgeInsetsGeometry padding, margin;

  /// Optional body typography. Rich rendering belongs in [commentBuilder].
  final TextStyle? textStyle;

  Widget _disclosure(CommentThreadDetails details) => Semantics(
    expanded: !details.isCollapsed,
    child: TextButton.icon(
      onPressed: details.isCollapsed ? details.expand : details.collapse,
      icon: Icon(
        details.isCollapsed ? Icons.expand_more : Icons.expand_less,
        size: 16,
      ),
      label: Text(details.isCollapsed ? labels.expand : labels.collapse),
    ),
  );

  Widget _collapsed(BuildContext context, CommentThreadDetails details) {
    final colors = Theme.of(context).colorScheme;
    final summary = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, size: 18, color: colors.primary),
        Semantics(
          liveRegion: true,
          child: Text(
            labels.resolved,
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (details.isSubmitting)
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        collapsedActionsBuilder?.call(context, details) ??
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _disclosure(details),
                if (controller.mayResolve)
                  TextButton(
                    onPressed: details.toggleResolved,
                    child: Text(labels.reopen),
                  ),
              ],
            ),
      ],
    );
    return collapsedBuilder?.call(context, details, summary) ?? summary;
  }

  Widget _composer(
    BuildContext context,
    CommentThreadDetails details, {
    bool edit = false,
  }) {
    final input = edit ? controller.editInput : controller.replyInput;
    final focus = edit ? controller.editFocus : controller.replyFocus;
    final comment = edit
        ? controller.thread.comment(controller.editingId!)
        : null;
    final allowed = edit
        ? comment != null &&
              controller.mayEdit(comment) &&
              !controller.editIsStale
        : controller.mayReply;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: input,
      builder: (context, value, _) {
        final commands = CommentThreadComposerDetails(
          thread: details,
          comment: edit ? comment ?? controller.editingComment : null,
          controller: input,
          focusNode: focus,
          submit:
              !controller.isSubmitting &&
                  allowed &&
                  value.text.trim().isNotEmpty
              ? () {
                  edit ? controller.submitEdit() : controller.submitReply();
                }
              : null,
          cancel: controller.isSubmitting
              ? null
              : edit
              ? controller.cancelEdit
              : controller.cancelReply,
          errorText: edit && controller.editIsStale ? labels.staleEdit : null,
        );
        return composerBuilder?.call(context, commands) ??
            SyntaxCommentComposer(
              controller: input,
              focusNode: focus,
              isSubmitting: controller.isSubmitting,
              canSubmit: allowed,
              errorText: commands.errorText,
              title: edit ? labels.editTitle : labels.reply,
              submitLabel: edit ? labels.save : labels.postReply,
              cancelLabel: labels.cancel,
              inputDecoration: InputDecoration(
                labelText: labels.inputLabel,
                border: const OutlineInputBorder(),
              ),
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              decoration: const BoxDecoration(),
              onSubmit: (_) => commands.submit?.call(),
              onCancel: () => commands.cancel?.call(),
            );
      },
    );
  }

  Widget _message(
    BuildContext context,
    CommentThreadDetails details,
    ReviewComment comment,
  ) {
    final colors = Theme.of(context).colorScheme;
    final actions = CommentMessageDetails(details, comment);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            Text(comment.author, style: Theme.of(context).textTheme.labelLarge),
            if (comment.editedAt != null)
              Text(
                labels.edited,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            commentActionsBuilder?.call(context, actions) ??
                Wrap(
                  spacing: 4,
                  children: [
                    if (controller.mayEdit(comment))
                      TextButton(
                        onPressed: actions.edit,
                        child: Text(labels.edit),
                      ),
                    if (controller.mayDelete(comment))
                      TextButton(
                        onPressed: actions.delete,
                        child: Text(labels.delete),
                      ),
                  ],
                ),
          ],
        ),
        const SizedBox(height: 6),
        if (controller.editingId == comment.id)
          _composer(context, details, edit: true)
        else
          Text(
            comment.body,
            style: textStyle ?? Theme.of(context).textTheme.bodyMedium,
          ),
        if (controller.deletingId == comment.id)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(labels.deleteQuestion),
                TextButton(
                  onPressed: details.isSubmitting
                      ? null
                      : controller.cancelDelete,
                  child: Text(labels.cancel),
                ),
                FilledButton(
                  onPressed: details.isSubmitting
                      ? null
                      : () {
                          controller.confirmDelete();
                        },
                  child: Text(labels.delete),
                ),
              ],
            ),
          ),
      ],
    );
    return KeyedSubtree(
      key: ValueKey(comment.id),
      child: commentBuilder?.call(context, actions, body) ?? body,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final details = CommentThreadDetails(controller);
      final thread = details.thread;
      final content = thread.comments.isEmpty
          ? const SizedBox.shrink()
          : Container(
              margin: margin,
              padding: padding,
              decoration:
                  decoration ??
                  BoxDecoration(
                    color: colors.surface,
                    border: Border.all(
                      color: thread.resolved
                          ? colors.primary.withValues(alpha: .5)
                          : colors.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (details.isCollapsed)
                    _collapsed(context, details)
                  else ...[
                    headerBuilder?.call(context, details) ??
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              thread.resolved
                                  ? Icons.check_circle_outline
                                  : Icons.forum_outlined,
                              size: 16,
                              color: colors.primary,
                            ),
                            Text(
                              labels.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                thread.resolved ? labels.resolved : labels.open,
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (details.isSubmitting)
                              const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < thread.comments.length; i++) ...[
                      if (i > 0) const Divider(height: 24),
                      _message(context, details, thread.comments[i]),
                    ],
                    const SizedBox(height: 8),
                    actionsBuilder?.call(context, details) ??
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (thread.resolved) _disclosure(details),
                            if (controller.mayReply && !controller.isReplying)
                              TextButton.icon(
                                onPressed: details.reply,
                                icon: const Icon(Icons.reply, size: 16),
                                label: Text(labels.reply),
                              ),
                            if (controller.mayResolve)
                              TextButton(
                                onPressed: details.toggleResolved,
                                child: Text(
                                  thread.resolved
                                      ? labels.reopen
                                      : labels.resolve,
                                ),
                              ),
                          ],
                        ),
                    if (controller.editingId != null &&
                        thread.comment(controller.editingId!) == null)
                      _composer(context, details, edit: true),
                    if (controller.isReplying) ...[
                      const Divider(height: 24),
                      _composer(context, details),
                    ],
                  ],
                  if (controller.error case final error?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        container: true,
                        liveRegion: true,
                        child:
                            errorBuilder?.call(context, details, error) ??
                            Text(
                              labels.failure,
                              style: TextStyle(color: colors.error),
                            ),
                      ),
                    ),
                ],
              ),
            );
      return InlineCommentRegion(
        child: builder?.call(context, details, content) ?? content,
      );
    },
  );
}
