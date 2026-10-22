import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syntax/syntax.dart';
import 'comment_gutter_preview.dart';
import 'comment_thread_controller.dart';
import 'comment_thread.dart';

/// Icons, colors and sizing for existing-discussion gutter indicators.
@immutable
class CommentGutterStyle {
  /// Uses code-theme colors and compact icons without increasing row height.
  const CommentGutterStyle({
    this.icon = Icons.chat_bubble_outline,
    this.resolvedIcon = Icons.check_circle_outline,
    this.color,
    this.resolvedColor,
    this.activeColor,
    this.backgroundColor = Colors.transparent,
    this.activeBackgroundColor,
    this.width = 26,
    this.iconSize = 16,
    this.showCount = true,
  }) : assert(width > 0),
       assert(iconSize > 0);

  /// Icon for open discussions and for a group containing only resolved ones.
  final IconData icon, resolvedIcon;

  /// Defaults use primary, on-surface-variant and primary, respectively.
  final Color? color, resolvedColor, activeColor;

  /// Button fills; the active default is a translucent primary tint.
  final Color backgroundColor;
  final Color? activeBackgroundColor;

  /// Reserved width in each source gutter; stable across visible rows.
  final double width;

  /// Preferred icon size, scaled down for small source rows.
  final double iconSize;

  /// Displays a small count when multiple threads share this attachment point.
  final bool showCount;
}

/// An attachment point and commands for application-owned gutter controls.
class CommentGutterDetails {
  /// Snapshots are scoped to a source revision. Commands reject stale controls.
  CommentGutterDetails({
    required this.controller,
    required this.fileId,
    required this.sourceRevision,
    required Iterable<(int, DiffSide?)> sourceLines,
    required Iterable<CommentThreadLocation> threads,
  }) : sourceLines = List.unmodifiable(sourceLines),
       threads = List.unmodifiable(threads);

  /// Application-owned navigation index.
  final CommentNavigationController controller;

  /// Source identity addressed by this indicator.
  final String fileId;
  final int sourceRevision;

  /// Zero-based source addresses. Unified context can represent both sides.
  final List<(int, DiffSide?)> sourceLines;

  /// Visible discussions in navigation order, excluding filtered threads.
  final List<CommentThreadLocation> threads;

  /// Number of discussions, independent of the number of replies.
  int get count => threads.length;

  /// Number of open discussions at this attachment point.
  int get unresolved => threads.where((entry) => !entry.thread.resolved).length;

  /// Whether this group contains the selected discussion.
  bool get isActive =>
      threads.any((entry) => entry.key == controller.current?.key);

  /// Next discussion at this point, cycling when several share the same line.
  CommentThreadLocation? get next {
    if (threads.isEmpty) return null;
    final current = threads.indexWhere(
      (entry) => entry.key == controller.current?.key,
    );
    return threads[(current + 1) % threads.length];
  }

  /// Expands, reveals and focuses a discussion without changing resolution or
  /// source selection. Omit [thread] to cycle through this indicator's threads.
  /// Custom thread UIs can expand their own session before invoking this command.
  Future<bool> open([CommentThreadLocation? thread]) async {
    final target = thread ?? next;
    if (controller.isDisposed ||
        target == null ||
        !threads.any((entry) => entry.key == target.key)) {
      return false;
    }
    CommentThreadLocation? current;
    for (final (line, side) in sourceLines) {
      for (final entry in controller.threadsAtLine(
        fileId,
        line,
        side: side,
        sourceRevision: sourceRevision,
      )) {
        if (entry.key == target.key) current = entry;
      }
    }
    if (current == null) return false;
    return controller.reveal(current, expandAndFocus: true);
  }
}

/// Customizes existing-comment indicators in descendant file and diff gutters.
class SyntaxCommentGutterTheme extends InheritedWidget {
  /// Buttons are enabled automatically when a view has commentNavigation.
  const SyntaxCommentGutterTheme({
    super.key,
    required super.child,
    this.enabled = true,
    this.style = const CommentGutterStyle(),
    this.labelBuilder,
    this.builder,
    this.onActivate,
    this.previewEnabled = true,
    this.previewStyle = const CommentGutterPreviewStyle(),
    this.previewDelay = const Duration(milliseconds: 350),
    this.previewHideDelay = const Duration(milliseconds: 200),
    this.previewBuilder,
    this.previewActionsBuilder,
    this.previewThreadController,
    this.previewComposerBuilder,
    this.previewThreadLabels = const CommentThreadLabels(),
  });

  /// Hides the marker column without changing discussions or navigation.
  final bool enabled;

  /// Default icon, color, width and count styling.
  final CommentGutterStyle style;

  /// Replaces the default localized tooltip and accessible button label.
  final String Function(CommentGutterDetails)? labelBuilder;

  /// Wraps or replaces the whole indicator. Return null to hide this marker.
  /// The child is the default button; replacement widgets own their semantics
  /// and can use details.open to retain navigation behavior.
  final Widget? Function(BuildContext, CommentGutterDetails, Widget)? builder;

  /// Replaces the default open action (for example, to choose between threads).
  /// Call details.open when ready. The default cycles through colocated threads.
  final FutureOr<void> Function(CommentGutterDetails)? onActivate;

  /// Shows an interactive preview on hover, or F2 while the marker has focus.
  /// Disabling previews preserves the marker's normal tooltip and click action.
  final bool previewEnabled;

  /// Bounds and surface colors for the preview, including custom content.
  final CommentGutterPreviewStyle previewStyle;

  /// Delays showing on hover and hiding after leaving the marker and preview.
  /// The hide delay lets the pointer cross the gap between the two surfaces.
  final Duration previewDelay, previewHideDelay;

  /// Wraps or replaces the preview body. Return null to suppress this preview.
  /// The default child shows message excerpts, reply counts and thread actions.
  /// The surrounding bounded surface, hover handling and dismissal are retained.
  final Widget? Function(BuildContext, CommentGutterPreviewDetails, Widget)?
  previewBuilder;

  /// Replaces each thread's actions in the default preview. Return null to hide
  /// them. Use details.open(thread) or details.close() in application actions.
  final Widget? Function(
    BuildContext,
    CommentGutterPreviewDetails,
    CommentThreadLocation,
    Widget,
  )?
  previewActionsBuilder;

  /// Resolves application-owned sessions for direct preview replies and
  /// resolve/reopen actions. Return the same retained session used inline,
  /// matching the location's thread identity and revision, or null for read-only
  /// previews. Sessions are never disposed by the gutter.
  final CommentThreadController? Function(CommentThreadLocation)?
  previewThreadController;

  /// Wraps or replaces the reply input and submit/cancel controls. Details carry
  /// the shared draft, preview-local focus and guarded commands. Custom inputs
  /// own their shortcuts. Returning null hides the composer for that thread.
  final Widget? Function(
    BuildContext,
    CommentGutterPreviewThreadDetails,
    Widget,
  )?
  previewComposerBuilder;

  /// Localized reply, submit, cancel, resolve/reopen and error labels.
  final CommentThreadLabels previewThreadLabels;

  /// Configuration for descendant source views, or null for defaults.
  static SyntaxCommentGutterTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyntaxCommentGutterTheme>();
  @override
  bool updateShouldNotify(SyntaxCommentGutterTheme old) =>
      enabled != old.enabled ||
      style != old.style ||
      builder != old.builder ||
      labelBuilder != old.labelBuilder ||
      onActivate != old.onActivate ||
      previewEnabled != old.previewEnabled ||
      previewStyle != old.previewStyle ||
      previewDelay != old.previewDelay ||
      previewHideDelay != old.previewHideDelay ||
      previewBuilder != old.previewBuilder ||
      previewActionsBuilder != old.previewActionsBuilder ||
      previewThreadController != old.previewThreadController ||
      previewComposerBuilder != old.previewComposerBuilder ||
      previewThreadLabels != old.previewThreadLabels;
}

// Internal paint-positioned adapter keeps pointer input outside line dragging.
// ignore_for_file: public_member_api_docs
double commentGutterWidth(
  BuildContext context,
  CommentNavigationController? navigation,
) {
  final theme = SyntaxCommentGutterTheme.maybeOf(context);
  return navigation == null || theme?.enabled == false
      ? 0
      : (theme?.style.width ?? 26);
}

class CommentGutterOverlay extends StatelessWidget {
  const CommentGutterOverlay({
    super.key,
    required this.navigation,
    required this.fileId,
    required this.sourceRevision,
    required this.lines,
    required this.leadingWidth,
    required this.child,
    this.split = false,
  });
  final CommentNavigationController? navigation;
  final String fileId;
  final int sourceRevision;
  final List<(int, DiffSide?)> lines;
  final double leadingWidth;
  final bool split;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nav = navigation, config = SyntaxCommentGutterTheme.maybeOf(context);
    final style = config?.style ?? const CommentGutterStyle();
    Widget? indicator(List<(int, DiffSide?)> sources) {
      if (nav == null || config?.enabled == false) return null;
      final entries = <(String, String), CommentThreadLocation>{};
      for (final (line, side) in sources) {
        for (final entry in nav.threadsAtLine(
          fileId,
          line,
          side: side,
          sourceRevision: sourceRevision,
        )) {
          entries[entry.key] = entry;
        }
      }
      if (entries.isEmpty) return null;
      final details = CommentGutterDetails(
        controller: nav,
        fileId: fileId,
        sourceRevision: sourceRevision,
        sourceLines: sources,
        threads: entries.values.toList()
          ..sort((a, b) => a.annotationId.compareTo(b.annotationId)),
      );
      final colors = Theme.of(context).colorScheme;
      final color = details.isActive
          ? style.activeColor ?? colors.primary
          : details.unresolved == 0
          ? style.resolvedColor ?? colors.onSurfaceVariant
          : style.color ?? colors.primary;
      final label =
          config?.labelBuilder?.call(details) ??
          (details.count == 1
              ? 'Open discussion'
              : 'Open next discussion (${details.count} threads)');
      final iconButton = IconButton(
        isSelected: details.isActive,
        onPressed: () {
          final action = config?.onActivate;
          if (action != null) {
            action(details);
          } else {
            details.open();
          }
        },
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size(style.width, style.iconSize + 4),
          maximumSize: Size(style.width, style.iconSize + 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: color,
          backgroundColor: details.isActive
              ? style.activeBackgroundColor ??
                    colors.primary.withValues(alpha: .15)
              : style.backgroundColor,
        ),
        icon: ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                details.unresolved == 0 ? style.resolvedIcon : style.icon,
                size: style.iconSize,
              ),
              if (style.showCount && details.count > 1)
                Positioned(
                  right: -5,
                  top: -4,
                  child: Text(
                    '${details.count}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      // Keep one named button even when its ordinary tooltip is suppressed by
      // the interactive preview. TooltipVisibility differs across Flutter SDKs.
      final button = Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(label: label, child: iconButton),
        ),
      );
      final marker = config?.builder != null
          ? config!.builder!(context, details, button)
          : button;
      return marker == null
          ? null
          : CommentGutterPreviewAnchor(
              key: _CommentGutterKeys.maybeOf(context)?.keyFor(details),
              details: details,
              config: config,
              child: marker,
            );
    }

    Widget positioned(Widget marker, bool right) => Positioned.fill(
      child: Align(
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: split ? .5 : 1,
          heightFactor: 1,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: leadingWidth),
              child: SelectionContainer.disabled(
                child: SizedBox(
                  width: style.width,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: marker,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final left = indicator(
      split ? lines.where((entry) => entry.$2 == DiffSide.old).toList() : lines,
    );
    final right = split
        ? indicator(lines.where((entry) => entry.$2 == DiffSide.newer).toList())
        : null;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (left != null) positioned(left, false),
        if (right != null) positioned(right, true),
      ],
    );
  }
}

// Preserve an open overlay when the indexed viewport replaces its local sliver
// window during annotation measurements. Keys are scoped to a view and pruned
// after unmount, so scrolling still releases offscreen rows and their previews.
class CommentGutterScope extends StatefulWidget {
  const CommentGutterScope({super.key, required this.child});
  final Widget child;
  @override
  State<CommentGutterScope> createState() => _CommentGutterScopeState();
}

class _CommentGutterScopeState extends State<CommentGutterScope> {
  final _keys = <(String, int, String), GlobalKey>{};
  bool _scheduled = false;
  void _prune() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _keys.removeWhere((_, key) => key.currentContext == null);
    });
  }

  GlobalKey keyFor(CommentGutterDetails details) {
    _prune();
    return _keys.putIfAbsent((
      details.fileId,
      details.sourceRevision,
      details.sourceLines
          .map((entry) => '${entry.$1}:${entry.$2?.index}')
          .join(','),
    ), GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    _prune();
    return _CommentGutterKeys(owner: this, child: widget.child);
  }
}

class _CommentGutterKeys extends InheritedWidget {
  const _CommentGutterKeys({required this.owner, required super.child});
  final _CommentGutterScopeState owner;
  static _CommentGutterScopeState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CommentGutterKeys>()?.owner;
  @override
  bool updateShouldNotify(_CommentGutterKeys old) => old.owner != owner;
}
