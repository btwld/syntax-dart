import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax/syntax.dart';
import 'comment_thread_controller.dart';

/// Review commands available to application-configured shortcuts.
enum CommentShortcutCommand {
  /// Reveal the previous visible discussion, wrapping at the beginning.
  previous,

  /// Reveal the next visible discussion, wrapping at the end.
  next,

  /// Open and focus the selected discussion's retained reply draft.
  reply,

  /// Resolve or reopen the selected discussion through its save callback.
  toggleResolved,
}

/// One keyboard binding and its application-supplied, localizable display text.
@immutable
class CommentShortcutBinding {
  /// Labels should describe the actual activator, including its modifiers.
  const CommentShortcutBinding({
    required this.activator,
    required this.command,
    required this.label,
  });

  /// Key combination recognized by Flutter.
  final ShortcutActivator activator;

  /// Review command to invoke once on key down; held-key repeats are ignored.
  final CommentShortcutCommand command;

  /// Human-readable shortcut displayed in tooltips or application help.
  final String label;
}

/// Default bindings, active only inside an enabled review shortcut scope.
const defaultCommentShortcuts = <CommentShortcutBinding>[
  CommentShortcutBinding(
    activator: SingleActivator(LogicalKeyboardKey.arrowUp, alt: true),
    command: CommentShortcutCommand.previous,
    label: 'Alt/Option+↑',
  ),
  CommentShortcutBinding(
    activator: SingleActivator(LogicalKeyboardKey.arrowDown, alt: true),
    command: CommentShortcutCommand.next,
    label: 'Alt/Option+↓',
  ),
  CommentShortcutBinding(
    activator: SingleActivator(LogicalKeyboardKey.keyR, alt: true),
    command: CommentShortcutCommand.reply,
    label: 'Alt/Option+R',
  ),
  CommentShortcutBinding(
    activator: SingleActivator(LogicalKeyboardKey.enter, alt: true),
    command: CommentShortcutCommand.toggleResolved,
    label: 'Alt/Option+Enter',
  ),
];

/// Scoped review hotkeys for file/diff views, inline threads and their toolbars.
///
/// Wrap the toolbar and source view together. Pass the same [controller] to the
/// view's commentNavigation. Clicking or focusing an annotation selects its
/// thread; navigation keys also select their destination. [threadController]
/// resolves application-owned sessions, including for unmounted annotations.
/// No session or navigation controller is disposed by this widget.
class SyntaxCommentShortcuts extends StatefulWidget {
  /// Empty [bindings] disables all commands. The first matching binding wins.
  const SyntaxCommentShortcuts({
    super.key,
    required this.controller,
    required this.child,
    this.threadController,
    this.fileId,
    this.bindings = defaultCommentShortcuts,
    this.enabled = true,
    this.allowInTextFields = false,
    this.autofocus = false,
    this.focusNode,
  });

  /// Discussion index used for navigation and the selected thread.
  final CommentNavigationController controller;

  /// Returns the current retained session for an anchor, or null if unavailable.
  /// Sessions should reflect the latest annotation snapshot. Permissions and
  /// pending saves are checked before reply or resolution commands run.
  final CommentThreadController? Function(CommentThreadLocation)?
  threadController;

  /// Optional file scope for navigation and thread actions.
  final String? fileId;

  /// Replaces defaults entirely; duplicate activators use their first entry.
  final List<CommentShortcutBinding> bindings;

  /// Temporarily disables the scope without discarding selection or drafts.
  final bool enabled;

  /// Opts into review commands while native text inputs have focus.
  /// Defaults to false to preserve typing, IME and editor navigation.
  final bool allowInTextFields;

  /// Requests initial focus on the review area when no child already has it.
  final bool autofocus;

  /// Optional application-owned focus for bringing the review area into focus.
  final FocusNode? focusNode;

  /// Toolbar and source/annotation content participating in this scope.
  final Widget child;

  /// Active bindings available to custom toolbar/thread builders and help UI.
  static List<CommentShortcutBinding> bindingsOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ShortcutScope>();
    return scope?.owner.widget.enabled == true
        ? List.unmodifiable(scope!.owner.widget.bindings)
        : const [];
  }

  /// Appends configured key labels to a localized tooltip or action label.
  static String tooltip(
    BuildContext context,
    CommentShortcutCommand command,
    String label,
  ) {
    final keys = bindingsOf(context)
        .where((binding) => binding.command == command)
        .map((binding) => binding.label)
        .join(' / ');
    return keys.isEmpty ? label : '$label ($keys)';
  }

  @override
  State<SyntaxCommentShortcuts> createState() => _SyntaxCommentShortcutsState();
}

class _SyntaxCommentShortcutsState extends State<SyntaxCommentShortcuts> {
  final _ownedFocus = FocusNode(debugLabel: 'Review discussion shortcuts');
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  @override
  void initState() {
    super.initState();
    // Handle only explicitly bound review commands before the inline input
    // boundary stops viewer shortcuts. Ordinary keys retain normal dispatch.
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  KeyEventResult _key(KeyEvent event) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (!mounted ||
        !widget.enabled ||
        widget.controller.isDisposed ||
        !_focus.hasFocus ||
        focused == null ||
        ModalRoute.of(context)?.isCurrent == false ||
        focused.getInheritedWidgetOfExactType<_ShortcutScope>()?.owner !=
            this) {
      return KeyEventResult.ignored;
    }
    if (!widget.allowInTextFields &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    for (final binding in widget.bindings) {
      if (!binding.activator.accepts(event, HardwareKeyboard.instance)) {
        continue;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      return _invoke(binding.command)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  bool _invoke(CommentShortcutCommand command) {
    final navigation = widget.controller;
    if (command == CommentShortcutCommand.next ||
        command == CommentShortcutCommand.previous) {
      if (navigation.visible(fileId: widget.fileId).isEmpty) return false;
      _focus.requestFocus();
      if (command == CommentShortcutCommand.next) {
        navigation.next(fileId: widget.fileId);
      } else {
        navigation.previous(fileId: widget.fileId);
      }
      return true;
    }
    final current = navigation.current;
    if (navigation.isNavigating ||
        current == null ||
        (widget.fileId != null && current.fileId != widget.fileId)) {
      return false;
    }
    final session = widget.threadController?.call(current);
    if (session == null ||
        session.isDisposed ||
        session.isSubmitting ||
        session.thread.id != current.thread.id ||
        session.thread.revision != current.thread.revision) {
      return false;
    }
    switch (command) {
      case CommentShortcutCommand.reply:
        if (!session.mayReply) return false;
        session.startReply();
      case CommentShortcutCommand.toggleResolved:
        if (!session.mayResolve) return false;
        _focus.requestFocus();
        session.toggleResolved();
      case CommentShortcutCommand.previous:
      case CommentShortcutCommand.next:
        return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => _ShortcutScope(
    owner: this,
    // Rebuild descendant hints when callers replace bindings or enabled state.
    bindings: widget.bindings,
    enabled: widget.enabled,
    child: Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      skipTraversal: true,
      child: Listener(
        onPointerDown: (_) {
          if (!_focus.hasFocus) _focus.requestFocus();
        },
        child: widget.child,
      ),
    ),
  );

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    _ownedFocus.dispose();
    super.dispose();
  }
}

class _ShortcutScope extends InheritedWidget {
  const _ShortcutScope({
    required this.owner,
    required this.bindings,
    required this.enabled,
    required super.child,
  });
  final _SyntaxCommentShortcutsState owner;
  final List<CommentShortcutBinding> bindings;
  final bool enabled;
  @override
  bool updateShouldNotify(_ShortcutScope oldWidget) =>
      owner != oldWidget.owner ||
      bindings != oldWidget.bindings ||
      enabled != oldWidget.enabled;
}
