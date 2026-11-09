import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'selection_chrome.dart';

/// Builds an injected action or its widgets-only default.
Widget buildSyntaxAction(
  BuildContext context,
  SyntaxSelectionChrome chrome,
  SyntaxChromeAction action,
  Widget child,
) =>
    chrome.actionBuilder?.call(context, action, child) ??
    SyntaxActionButton(action: action, child: child);

/// Widgets-only activation used by the default syntax controls.
class SyntaxActionButton extends StatefulWidget {
  /// Makes [child] focusable and activatable according to [action].
  const SyntaxActionButton({
    super.key,
    required this.action,
    required this.child,
  });

  /// Accessible description and callback.
  final SyntaxChromeAction action;

  /// Visual content, excluded from the button's semantics.
  final Widget child;

  @override
  State<SyntaxActionButton> createState() => _SyntaxActionButtonState();
}

class _SyntaxActionButtonState extends State<SyntaxActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return Semantics(
      button: true,
      enabled: action.enabled,
      expanded: action.expanded,
      label: action.label,
      onTap: action.onInvoke,
      child: FocusableActionDetector(
        enabled: action.enabled,
        mouseCursor: action.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              action.onInvoke?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: action.onInvoke,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: _focused
                  ? Border.all(
                      color:
                          DefaultSelectionStyle.of(context).cursorColor ??
                          DefaultTextStyle.of(context).style.color ??
                          const Color(0xff808080),
                      width: 2,
                    )
                  : null,
            ),
            child: ExcludeSemantics(child: widget.child),
          ),
        ),
      ),
    );
  }
}
