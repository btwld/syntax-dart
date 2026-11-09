import 'package:flutter/widgets.dart';

/// The purpose of a syntax surface's control.
enum SyntaxChromeActionKind {
  /// Fold or unfold a file.
  toggleFile,

  /// Reveal hidden unchanged lines.
  expandGap,

  /// Copy selected code.
  copy,

  /// Select all code.
  selectAll,
}

/// Accessible description and activation for an injected control.
@immutable
class SyntaxChromeAction {
  /// Describes a control; a null [onInvoke] disables it.
  const SyntaxChromeAction({
    required this.kind,
    required this.label,
    required this.onInvoke,
    this.expanded,
  });

  /// Purpose of this control.
  final SyntaxChromeActionKind kind;

  /// Accessible, human-readable label.
  final String label;

  /// Activation callback, or null when disabled.
  final VoidCallback? onInvoke;

  /// Whether activation is available.
  bool get enabled => onInvoke != null;

  /// Expanded state for disclosure controls, otherwise null.
  final bool? expanded;
}

/// Selection and control rendering shared by code and patch views.
///
/// Omit the views' `selectionChrome` to use painted selection handles and a
/// widgets-only Copy/Select all menu. Custom controls should mix in
/// [TextSelectionHandleControls] to use [contextMenuBuilder]; Flutter ignores
/// that builder for legacy controls that implement their own toolbar.
@immutable
class SyntaxSelectionChrome {
  /// Uses caller-owned selection controls with optional custom chrome.
  const SyntaxSelectionChrome({
    required this.selectionControls,
    this.contextMenuBuilder,
    this.actionBuilder,
    this.noNewlineMarkerBuilder,
  });

  /// Selection handles (and, for legacy controls, the toolbar).
  final TextSelectionControls selectionControls;

  /// Builds a selection menu; null uses the plain Copy/Select all menu.
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;

  /// Replaces an action's entire control, including activation and semantics.
  ///
  /// [SyntaxChromeAction] supplies its callback and accessible state; `child`
  /// supplies the default visual content, including the painted glyph.
  final Widget Function(BuildContext, SyntaxChromeAction, Widget child)?
  actionBuilder;

  /// Replaces the visible missing-final-newline marker.
  ///
  /// The supplied message remains the accessible label and is excluded from
  /// copied code. The default paints a small circle with a horizontal stroke.
  final Widget Function(BuildContext, String message)? noNewlineMarkerBuilder;

  /// Plain controls for hosts with no design-system selection implementation.
  static final SyntaxSelectionChrome plain = SyntaxSelectionChrome(
    selectionControls: _PlainSelectionControls(),
  );
}

class _PlainSelectionControls extends EmptyTextSelectionControls
    with TextSelectionHandleControls {
  @override
  Size getHandleSize(double textLineHeight) => const Size(22, 22);

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      const Offset(11, 0);

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 22,
      height: 22,
      child: Center(
        child: Container(
          width: 12,
          height: 22,
          decoration: BoxDecoration(
            color:
                DefaultSelectionStyle.of(context).cursorColor ??
                const Color(0xff808080),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    ),
  );
}
