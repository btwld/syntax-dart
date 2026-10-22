// Internal layout shared by file and diff views.
// ignore_for_file: public_member_api_docs
import 'package:flutter/material.dart';
import 'selection_actions.dart';

Widget defaultSelectionAction(
  SelectionActionStyle style,
  VoidCallback action,
) => Builder(
  builder: (context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton.filled(
      tooltip: style.tooltip,
      onPressed: action,
      style: (style.buttonStyle ?? const ButtonStyle()).merge(
        IconButton.styleFrom(
          foregroundColor: colors.onPrimary,
          backgroundColor: colors.primary,
          padding: EdgeInsets.zero,
          minimumSize: Size.square(style.size),
          maximumSize: Size.square(style.size),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      icon: style.icon,
    );
  },
);

/// Keeps actions outside the gutter's pointer listener, so clicking an action
/// never starts a new selection. Overlays do not change indexed row heights.
class SelectionActionOverlay extends StatelessWidget {
  const SelectionActionOverlay({
    super.key,
    required this.child,
    required this.action,
    required this.alignment,
    this.split = false,
    this.right = false,
  });
  final Widget child;
  final Widget? action;
  final Alignment alignment;
  final bool split, right;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (action != null)
          Positioned.fill(
            child: Align(
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: split ? .5 : 1,
                heightFactor: 1,
                child: Align(
                  alignment: alignment,
                  child: SelectionContainer.disabled(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: alignment,
                      child: action,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
