import 'package:flutter/material.dart';
import 'package:syntax/syntax.dart';

/// Paint-only styling for source lines linked to the active discussion.
@immutable
class CommentSourceHighlightStyle {
  /// Defaults match the active thread's accent without replacing diff colors.
  const CommentSourceHighlightStyle({
    this.backgroundColor,
    this.markerColor,
    this.markerWidth = 3,
  }) : assert(markerWidth >= 0);

  /// Translucent foreground tint. Defaults to the thread accent at 12% opacity.
  final Color? backgroundColor;

  /// Leading gutter marker color. Defaults to the thread's outline color.
  final Color? markerColor;

  /// Marker thickness; zero hides it without changing gutter or row width.
  final double markerWidth;
}

/// Source identity and range boundaries for an application-owned line overlay.
@immutable
class CommentSourceHighlightDetails {
  /// A mounted physical source line, never an empty split pane.
  const CommentSourceHighlightDetails({
    required this.location,
    required this.line,
    required this.side,
    required this.isFirst,
    required this.isLast,
  });

  /// Current discussion and its immutable source range.
  final CommentThreadLocation location;

  /// Zero-based source line; use line + 1 for display labels.
  final int line;

  /// Diff side, or null for a file view.
  final DiffSide? side;

  /// Boundaries of the linked interval on this source side.
  final bool isFirst, isLast;
}

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
    this.sourceEnabled = true,
    this.sourceStyle = const CommentSourceHighlightStyle(),
    this.sourceBuilder,
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

  /// Disables thread and source highlighting, preserving selection/navigation.
  final bool enabled;

  /// Independently hides linked source highlighting while retaining the card.
  final bool sourceEnabled;

  /// Tint and gutter marker painted over the linked source lines.
  final CommentSourceHighlightStyle sourceStyle;

  /// Replaces the overlay for each active source line; null hides that overlay.
  /// The overlay is constrained to the line or split pane, ignores pointer
  /// input, and is excluded from source copying and accessibility text. Source
  /// content, native selection and annotation widgets are never replaced.
  final Widget? Function(BuildContext, CommentSourceHighlightDetails)?
  sourceBuilder;

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
      sourceEnabled != oldWidget.sourceEnabled ||
      sourceStyle != oldWidget.sourceStyle ||
      sourceBuilder != oldWidget.sourceBuilder ||
      keepVisible != oldWidget.keepVisible ||
      scrollPadding != oldWidget.scrollPadding;
}

// Internal row adapter. Views rebuild on navigation changes, so only mounted
// rows do membership checks and no additional controller subscriptions are used.
// ignore_for_file: public_member_api_docs
class CommentSourceHighlight extends StatelessWidget {
  const CommentSourceHighlight({
    super.key,
    required this.controller,
    required this.fileId,
    required this.sourceRevision,
    required this.lines,
    required this.child,
    this.split = false,
  });
  final CommentNavigationController? controller;
  final String fileId;
  final int sourceRevision;
  final List<(int, DiffSide?)> lines;
  final bool split;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final navigation = controller;
    if (navigation == null) return child;
    final config = SyntaxCommentHighlightTheme.maybeOf(context);
    Widget? overlay(DiffSide? pane) {
      if (config?.enabled == false || config?.sourceEnabled == false) {
        return null;
      }
      bool contains(int line, DiffSide? side) => navigation.isSourceLineActive(
        fileId,
        line,
        side: side,
        sourceRevision: sourceRevision,
      );
      for (final (line, side) in lines) {
        if ((split && side != pane) || !contains(line, side)) continue;
        final details = CommentSourceHighlightDetails(
          location: navigation.current!,
          line: line,
          side: side,
          isFirst: !contains(line - 1, side),
          isLast: !contains(line + 1, side),
        );
        if (config?.sourceBuilder case final builder?) {
          return builder(context, details);
        }
        final style =
            config?.sourceStyle ?? const CommentSourceHighlightStyle();
        final color =
            style.markerColor ??
            config?.style.borderColor ??
            Theme.of(context).colorScheme.primary;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: style.backgroundColor ?? color.withValues(alpha: .12),
            border: Border(
              left: style.markerWidth == 0
                  ? BorderSide.none
                  : BorderSide(color: color, width: style.markerWidth),
            ),
          ),
        );
      }
      return null;
    }

    final single = split ? null : overlay(null);
    final left = split ? overlay(DiffSide.old) : null;
    final right = split ? overlay(DiffSide.newer) : null;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (single != null || left != null || right != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: split
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: left ?? const SizedBox()),
                          Expanded(child: right ?? const SizedBox()),
                        ],
                      )
                    : single!,
              ),
            ),
          ),
      ],
    );
  }
}
