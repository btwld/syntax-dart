import 'package:flutter/material.dart';

/// Appearance of the active discussion, independent of the thread's contents.
@immutable
class CommentThreadHighlightStyle {
  /// A foreground outline and translucent tint remain visible over custom cards.
  const CommentThreadHighlightStyle({
    this.borderColor,
    this.backgroundColor,
    this.borderWidth = 2,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.inset = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  }) : assert(borderWidth >= 0);

  /// Outline color; defaults to the source view's primary color.
  final Color? borderColor;

  /// Foreground tint; defaults to the primary color at six percent opacity.
  /// Use a translucent color to preserve the readability of the thread.
  final Color? backgroundColor;

  /// Outline thickness. Zero removes the outline.
  final double borderWidth;

  /// Shape of the outline and tint.
  final BorderRadiusGeometry borderRadius;

  /// Paint-only inset; never changes row measurements or draft layout.
  final EdgeInsetsGeometry inset;
}

/// Stable annotation identity and selection state for custom highlights.
@immutable
class CommentThreadHighlightDetails {
  /// Annotation IDs are scoped to their containing file.
  const CommentThreadHighlightDetails({
    required this.fileId,
    required this.annotationId,
    required this.isActive,
  });

  /// Source file and annotation identities.
  final String fileId, annotationId;

  /// Whether this is the navigation controller's selected discussion.
  final bool isActive;
}

/// Configures active discussion highlights in descendant file and diff views.
///
/// Wrap a review area once to style every annotation, including custom threads
/// and collapsed summaries. No controller or thread session is owned here.
class SyntaxCommentHighlightTheme extends InheritedWidget {
  /// Apps can customize the default painting or replace it with [builder].
  const SyntaxCommentHighlightTheme({
    super.key,
    required super.child,
    this.style = const CommentThreadHighlightStyle(),
    this.builder,
    this.enabled = true,
    this.keepVisible = true,
    this.scrollPadding = 12,
  }) : assert(scrollPadding >= 0);

  /// Outline, tint and shape for the default paint-only highlight.
  final CommentThreadHighlightStyle style;

  /// Replaces the highlight for both active and inactive annotations. The child
  /// is the original annotation. Preserve it to retain inputs and actions.
  /// Selected semantics and navigation remain outside this builder.
  final Widget Function(BuildContext, CommentThreadHighlightDetails, Widget)?
  builder;

  /// Disables visual highlighting, preserving selection and navigation.
  final bool enabled;

  /// Keeps explicitly navigated threads visible after resizing or row changes.
  /// Manual scrolling suspends this until the next navigation command. Pointer
  /// selection never starts automatic scrolling. Initial jumps always reveal.
  final bool keepVisible;

  /// Preferred space above/below a revealed thread, limited by viewport edges.
  final double scrollPadding;

  /// Nearest configuration, or null to use defaults.
  static SyntaxCommentHighlightTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyntaxCommentHighlightTheme>();

  @override
  bool updateShouldNotify(SyntaxCommentHighlightTheme oldWidget) =>
      style != oldWidget.style ||
      builder != oldWidget.builder ||
      enabled != oldWidget.enabled ||
      keepVisible != oldWidget.keepVisible ||
      scrollPadding != oldWidget.scrollPadding;
}
