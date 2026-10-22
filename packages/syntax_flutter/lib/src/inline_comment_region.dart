// Internal focus isolation for application-owned inline editors.
// ignore_for_file: public_member_api_docs
import 'package:flutter/material.dart';

class InlineCommentRegion extends StatelessWidget {
  const InlineCommentRegion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Focus(
      canRequestFocus: false,
      // Let the input handle native shortcuts, but do not let unhandled keys
      // invoke the surrounding source viewer's review/copy commands.
      onKeyEvent: (_, _) => KeyEventResult.skipRemainingHandlers,
      child: DefaultTextEditingShortcuts(
        child: FocusTraversalGroup(child: child),
      ),
    ),
  );
}
