import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Input state and commands supplied to custom comment input/action builders.
@immutable
class CommentComposerDetails {
  /// Describes the current draft without taking ownership of it.
  const CommentComposerDetails({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.submit,
    required this.cancel,
  });

  /// Application-owned draft, retained when the composer leaves the viewport.
  final TextEditingController controller;

  /// Optional application-owned focus node for a custom input.
  final FocusNode? focusNode;

  /// Whether an application submission is pending.
  final bool isSubmitting;

  /// Submit command, or null for an empty draft or a pending submission.
  final VoidCallback? submit;

  /// Cancel command, or null during a pending submission.
  final VoidCallback? cancel;
}

/// An inline comment form with replaceable input, actions and presentation.
///
/// The application owns [controller], submission, errors and cancellation.
/// Retain the controller outside virtualized rows and dispose it with the
/// application session. This widget never saves or clears a draft implicitly.
class SyntaxCommentComposer extends StatelessWidget {
  /// Builds a form that supports Ctrl/Cmd+Enter to submit and Escape to cancel.
  const SyntaxCommentComposer({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
    this.focusNode,
    this.autofocus = true,
    this.isSubmitting = false,
    this.canSubmit = true,
    this.errorText,
    this.title = 'Comment on selection',
    this.submitLabel = 'Add comment',
    this.cancelLabel = 'Cancel',
    this.inputDecoration = const InputDecoration(
      labelText: 'Review note',
      hintText: 'Leave a comment on these lines…',
      border: OutlineInputBorder(),
    ),
    this.textStyle,
    this.inputBuilder,
    this.actionsBuilder,
    this.header,
    this.decoration,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.shortcutsEnabled = true,
  });

  /// Draft controller, owned and disposed by the application.
  final TextEditingController controller;

  /// Called with trimmed, nonempty text. The application saves and closes.
  final ValueChanged<String> onSubmit;

  /// Application command to close the form or discard its draft.
  final VoidCallback onCancel;

  /// Optional application-owned input focus.
  final FocusNode? focusNode;

  /// Focuses the default input when it is mounted.
  final bool autofocus;

  /// Disables the default input and commands while an application saves.
  final bool isSubmitting;

  /// Application validation or permissions can disable saving without losing
  /// the draft or disabling cancellation.
  final bool canSubmit;

  /// Application-supplied validation or submission error, announced accessibly.
  final String? errorText;

  /// Localizable default heading.
  final String title;

  /// Localizable default submit button text.
  final String submitLabel;

  /// Localizable default cancel button text.
  final String cancelLabel;

  /// Decoration of the default multiline input.
  final InputDecoration inputDecoration;

  /// Typography of the default input.
  final TextStyle? textStyle;

  /// Replaces the input, for example with an application's rich text editor.
  final Widget Function(BuildContext, CommentComposerDetails)? inputBuilder;

  /// Replaces the action area, including submit/cancel and extra app commands.
  final Widget Function(BuildContext, CommentComposerDetails)? actionsBuilder;

  /// Replaces the heading. Use an empty widget to omit it.
  final Widget? header;

  /// Replaces the default themed card background and border.
  final Decoration? decoration;

  /// Space inside the form.
  final EdgeInsetsGeometry padding;

  /// Space between the form and adjacent source rows.
  final EdgeInsetsGeometry margin;

  /// Enables Ctrl/Cmd+Enter and Escape. Custom editors can supply their own.
  final bool shortcutsEnabled;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      final colors = Theme.of(context).colorScheme;
      final details = CommentComposerDetails(
        controller: controller,
        focusNode: focusNode,
        isSubmitting: isSubmitting,
        submit: isSubmitting || !canSubmit || value.text.trim().isEmpty
            ? null
            : () {
                final text = controller.text.trim();
                if (text.isNotEmpty) onSubmit(text);
              },
        cancel: isSubmitting ? null : onCancel,
      );
      return CallbackShortcuts(
        bindings: {
          if (shortcutsEnabled) ...{
            const SingleActivator(
              LogicalKeyboardKey.enter,
              control: true,
            ): () =>
                details.submit?.call(),
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                details.submit?.call(),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                details.cancel?.call(),
          },
        },
        child: Container(
          margin: margin,
          padding: padding,
          decoration:
              decoration ??
              BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              header ??
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              inputBuilder?.call(context, details) ??
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: autofocus,
                    enabled: !isSubmitting,
                    minLines: 3,
                    maxLines: 8,
                    style: textStyle,
                    decoration: inputDecoration,
                  ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text(
                      errorText!,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              actionsBuilder?.call(context, details) ??
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: details.cancel,
                        child: Text(cancelLabel),
                      ),
                      FilledButton(
                        onPressed: details.submit,
                        child: isSubmitting
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(submitLabel),
                      ),
                    ],
                  ),
            ],
          ),
        ),
      );
    },
  );
}
