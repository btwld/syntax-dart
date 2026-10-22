import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:syntax/syntax.dart';
import 'inline_comment_region.dart';
import 'comment_shortcuts.dart';
import 'comment_highlight.dart';

/// Localizable text for discussion counts, filters and navigation.
class CommentNavigationLabels {
  /// Uses English defaults; applications can replace any label.
  const CommentNavigationLabels({
    this.unresolved = 'unresolved',
    this.previous = 'Previous discussion',
    this.next = 'Next discussion',
    this.filter = 'Filter discussions',
    this.all = 'All threads',
    this.openOnly = 'Unresolved only',
    this.resolvedOnly = 'Resolved only',
    this.failure = 'Could not reveal this discussion. Try again.',
  });

  /// Count suffix and accessible command labels.
  final String unresolved, previous, next, filter;

  /// Filter choices and safe navigation failure feedback.
  final String all, openOnly, resolvedOnly, failure;
}

/// Counts and guarded commands for application-supplied review controls.
class CommentNavigationDetails {
  /// Restricts counts and navigation to fileId, or spans all bound files.
  const CommentNavigationDetails(this.controller, {this.fileId});

  /// Application-owned subscriptions, filter and navigation state.
  final CommentNavigationController controller;

  /// Optional scope for this set of controls.
  final String? fileId;

  /// Discussion counts independent of the visibility filter.
  int get unresolved => controller.count(fileId: fileId, resolved: false);

  /// Number of completed discussions, including hidden ones.
  int get resolved => controller.count(fileId: fileId, resolved: true);

  /// All nonempty discussions in this scope.
  int get total => unresolved + resolved;

  /// Discussions participating in navigation.
  List<CommentThreadLocation> get visible => controller.visible(fileId: fileId);

  /// One-based current position, or zero when no matching thread is selected.
  int get position =>
      visible.indexWhere((entry) => entry.key == controller.current?.key) + 1;

  /// Previous/next commands are absent when the filter matches no discussions.
  VoidCallback? get previous => visible.isEmpty
      ? null
      : () {
          controller.previous(fileId: fileId);
        };

  /// Moves forward through visible discussions, wrapping at the end.
  VoidCallback? get next => visible.isEmpty
      ? null
      : () {
          controller.next(fileId: fileId);
        };

  /// Changes visibility without deleting any comments or drafts.
  void setFilter(CommentThreadFilter value) => controller.filter = value;
}

/// A reusable unresolved-thread count for default or custom file headers.
class SyntaxCommentCount extends StatelessWidget {
  /// Counts threads (not messages), including when resolved ones are filtered.
  const SyntaxCommentCount({
    super.key,
    required this.controller,
    this.fileId,
    this.labels = const CommentNavigationLabels(),
    this.builder,
  });

  /// Application-owned discussion index.
  final CommentNavigationController controller;

  /// File whose count to display; null counts the whole review.
  final String? fileId;

  /// Localizable labels.
  final CommentNavigationLabels labels;

  /// Replaces the whole badge, including its semantics and styling.
  final Widget Function(BuildContext, CommentNavigationDetails)? builder;
  @override
  Widget build(BuildContext context) => CommentNavigationListener(
    controller: controller,
    builder: (context) {
      final details = CommentNavigationDetails(controller, fileId: fileId);
      if (builder != null) return builder!(context, details);
      final color = Theme.of(context).colorScheme.primary;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          spacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 14, color: color),
            Text(
              '${details.unresolved} ${labels.unresolved}',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      );
    },
  );
}

/// Placeable navigation and filtering controls for file or diff discussions.
class SyntaxCommentNavigation extends StatelessWidget {
  /// Apps may replace the full controls, only the count, or only the actions.
  const SyntaxCommentNavigation({
    super.key,
    required this.controller,
    this.fileId,
    this.labels = const CommentNavigationLabels(),
    this.builder,
    this.countBuilder,
    this.actionsBuilder,
    this.errorBuilder,
    this.padding = const EdgeInsets.all(8),
    this.decoration,
  });

  /// Application-owned discussion index; never disposed by this widget.
  final CommentNavigationController controller;

  /// Optional file scope for counts and previous/next; filtering is shared.
  final String? fileId;

  /// Default accessible labels and filter text.
  final CommentNavigationLabels labels;

  /// Replaces or wraps the complete controls with all commands available.
  final Widget Function(BuildContext, CommentNavigationDetails, Widget)?
  builder;

  /// Replaces the unresolved badge.
  final Widget Function(BuildContext, CommentNavigationDetails)? countBuilder;

  /// Replaces navigation, position and filter controls.
  final Widget Function(BuildContext, CommentNavigationDetails)? actionsBuilder;

  /// Replaces safe default failure feedback.
  final Widget Function(BuildContext, CommentNavigationDetails, Object)?
  errorBuilder;

  /// Container styling for embedding the controls in application toolbars.
  final EdgeInsetsGeometry padding;

  /// Optional toolbar decoration.
  final Decoration? decoration;
  @override
  Widget build(BuildContext context) => CommentNavigationListener(
    controller: controller,
    builder: (context) {
      final details = CommentNavigationDetails(controller, fileId: fileId);
      final child = Container(
        padding: padding,
        decoration: decoration,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            countBuilder?.call(context, details) ??
                SyntaxCommentCount(
                  controller: controller,
                  fileId: fileId,
                  labels: labels,
                ),
            actionsBuilder?.call(context, details) ??
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: SyntaxCommentShortcuts.tooltip(
                        context,
                        CommentShortcutCommand.previous,
                        labels.previous,
                      ),
                      onPressed: details.previous,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                    Text(
                      '${details.position} / ${details.visible.length}',
                      semanticsLabel:
                          '${details.position} / ${details.visible.length}',
                    ),
                    IconButton(
                      tooltip: SyntaxCommentShortcuts.tooltip(
                        context,
                        CommentShortcutCommand.next,
                        labels.next,
                      ),
                      onPressed: details.next,
                      icon: const Icon(Icons.arrow_downward, size: 18),
                    ),
                    Semantics(
                      container: true,
                      button: true,
                      child: PopupMenuButton<CommentThreadFilter>(
                        tooltip: labels.filter,
                        initialValue: controller.filter,
                        onSelected: details.setFilter,
                        itemBuilder: (_) => [
                          for (final filter in CommentThreadFilter.values)
                            CheckedPopupMenuItem(
                              value: filter,
                              checked: filter == controller.filter,
                              child: Text(switch (filter) {
                                CommentThreadFilter.all => labels.all,
                                CommentThreadFilter.unresolved =>
                                  labels.openOnly,
                                CommentThreadFilter.resolved =>
                                  labels.resolvedOnly,
                              }),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.filter_alt_outlined, size: 16),
                              const SizedBox(width: 4),
                              Text(switch (controller.filter) {
                                CommentThreadFilter.all => labels.all,
                                CommentThreadFilter.unresolved =>
                                  labels.openOnly,
                                CommentThreadFilter.resolved =>
                                  labels.resolvedOnly,
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            if (controller.isNavigating)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (controller.error case final error?)
              Semantics(
                liveRegion: true,
                child:
                    errorBuilder?.call(context, details, error) ??
                    Text(
                      labels.failure,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
              ),
          ],
        ),
      );
      return InlineCommentRegion(
        child: builder?.call(context, details, child) ?? child,
      );
    },
  );
}

// Internal adapters for renderer-neutral subscriptions and exact annotation reveals.
// ignore_for_file: public_member_api_docs
class CommentNavigationListener extends StatefulWidget {
  const CommentNavigationListener({
    super.key,
    required this.controller,
    required this.builder,
  });
  final CommentNavigationController controller;
  final WidgetBuilder builder;
  @override
  State<CommentNavigationListener> createState() =>
      _CommentNavigationListenerState();
}

class _CommentNavigationListenerState extends State<CommentNavigationListener> {
  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  @override
  void didUpdateWidget(CommentNavigationListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(changed);
      widget.controller.addListener(changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class CommentNavigationViewport extends StatefulWidget {
  const CommentNavigationViewport({super.key, required this.child});
  final Widget child;
  @override
  State<CommentNavigationViewport> createState() =>
      _CommentNavigationViewportState();
}

class _CommentNavigationViewportState extends State<CommentNavigationViewport> {
  final _metrics = ValueNotifier<int>(0);
  @override
  Widget build(BuildContext context) {
    // One outer listener covers nested file-preview viewports as well as the
    // collection itself, including changes to the outer visible area.
    if (context
            .dependOnInheritedWidgetOfExactType<_DiscussionViewportScope>() !=
        null) {
      return widget.child;
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          _metrics.value++;
        }
        return false;
      },
      child: _DiscussionViewportScope(notifier: _metrics, child: widget.child),
    );
  }

  @override
  void dispose() {
    _metrics.dispose();
    super.dispose();
  }
}

class _DiscussionViewportScope extends InheritedNotifier<ChangeNotifier> {
  const _DiscussionViewportScope({
    required super.notifier,
    required super.child,
  });
}

// Weakly held per viewport, so shared navigation also reveals independent views.
final _revealed = Expando<Expando<_DiscussionReveal>>();

class _DiscussionReveal {
  _DiscussionReveal(this.request);
  final int request;
  bool following = true;
  bool settled = false;
  int corrections = 0;
}

class CommentNavigationAnchor extends StatefulWidget {
  const CommentNavigationAnchor({
    super.key,
    required this.controller,
    required this.fileId,
    required this.annotationId,
    required this.child,
  });
  final CommentNavigationController? controller;
  final String fileId, annotationId;
  final Widget child;
  @override
  State<CommentNavigationAnchor> createState() =>
      _CommentNavigationAnchorState();
}

class _CommentNavigationAnchorState extends State<CommentNavigationAnchor> {
  final _target = GlobalKey();
  final _positions = <ScrollPosition>[];
  _DiscussionReveal? _reveal;
  bool _queued = false, _moving = false;
  (String, String) get _key => (widget.fileId, widget.annotationId);

  void _scrolled() {
    if (!_moving &&
        _positions.any((p) => p.userScrollDirection != ScrollDirection.idle)) {
      _reveal?.following = false;
    }
  }

  void _detach() {
    for (final position in _positions) {
      position.removeListener(_scrolled);
    }
    _positions.clear();
  }

  void _queueReveal() {
    final navigation = widget.controller;
    if (navigation == null ||
        navigation.isDisposed ||
        navigation.current?.key != _key ||
        navigation.revealTarget?.key != _key) {
      _reveal = null;
      _detach();
      return;
    }
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Indexed rows publish their measurements after this frame. Revealing
      // before those measurements would count the same height change twice.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (mounted) _ensureVisible();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  void _ensureVisible() {
    final navigation = widget.controller;
    final targetContext = _target.currentContext;
    if (navigation == null ||
        navigation.isDisposed ||
        navigation.isNavigating ||
        navigation.error != null ||
        navigation.current?.key != _key ||
        navigation.revealTarget?.key != _key ||
        targetContext == null) {
      _reveal = null;
      _detach();
      return;
    }
    final target = targetContext.findRenderObject();
    if (target == null || !target.attached) return;
    var scrollable = Scrollable.maybeOf(targetContext);
    if (scrollable == null) return;
    final seen = _revealed[navigation] ??= Expando<_DiscussionReveal>();
    final previous = seen[scrollable.position];
    final initial = previous?.request != navigation.revealRequest;
    final reveal = initial
        ? _DiscussionReveal(navigation.revealRequest)
        : previous!;
    seen[scrollable.position] = _reveal = reveal;
    final config = SyntaxCommentHighlightTheme.maybeOf(context);
    final adjustments = <(ScrollPosition, double)>[];
    _detach();
    RenderObject object = target;
    while (scrollable != null) {
      final position = scrollable.position;
      _positions.add(position);
      position.addListener(_scrolled);
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (position.axis == Axis.vertical &&
          position.hasContentDimensions &&
          viewport != null) {
        final rect = identical(object, target)
            ? target.paintBounds
            : MatrixUtils.transformRect(
                target.getTransformTo(object),
                target.paintBounds,
              ).intersect(object.paintBounds);
        // An outer viewport can see no part of the target until the inner
        // preview has scrolled. Its next layout will provide a usable rectangle.
        if (!rect.isEmpty) {
          final start = viewport
              .getOffsetToReveal(object, 0, rect: rect)
              .offset;
          final end = viewport.getOffsetToReveal(object, 1, rect: rect).offset;
          final extent = position.viewportDimension;
          final padding = math.min(config?.scrollPadding ?? 12, extent * .2);
          final low = end + padding, high = start - padding;
          final pixels = position.pixels;
          // A tall thread starts at its heading on a jump. While reading it,
          // resizing must not continually pull the user away from a reply field.
          final destination = low <= high
              ? pixels.clamp(low, high)
              : initial || start >= pixels + extent || end + extent <= pixels
              ? high
              : pixels;
          adjustments.add((
            position,
            destination.clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          ));
        }
      }
      object = scrollable.context.findRenderObject()!;
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    if (!initial &&
        (!reveal.following ||
            (!(config?.keepVisible ?? true) && reveal.settled))) {
      return;
    }
    final moves = adjustments
        .where((entry) => (entry.$1.pixels - entry.$2).abs() > .5)
        .toList();
    // Even with maintenance disabled, finish the initial jump after nested
    // source reveals settle. Bound these initial corrections for custom views.
    reveal.settled = moves.isEmpty || ++reveal.corrections >= 8;
    // Source reveals and indexed row measurements can settle in later frames.
    // Only move when the target is clipped; ordinary scrolling is authoritative
    // once a user scroll has suspended following.
    _moving = true;
    try {
      for (final (position, destination) in moves) {
        position.jumpTo(destination);
      }
    } finally {
      _moving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigation = widget.controller;
    if (navigation == null) return widget.child;
    final config = SyntaxCommentHighlightTheme.maybeOf(context);
    context.dependOnInheritedWidgetOfExactType<_DiscussionViewportScope>();
    return CommentNavigationListener(
      controller: navigation,
      builder: (context) {
        final selected = navigation.current?.key == _key;
        _queueReveal();
        final style = config?.style ?? const CommentThreadHighlightStyle();
        final color =
            style.borderColor ?? Theme.of(context).colorScheme.primary;
        final details = CommentThreadHighlightDetails(
          fileId: widget.fileId,
          annotationId: widget.annotationId,
          isActive: selected,
        );
        // Always retain the same child position so selecting a thread neither
        // recreates inputs nor changes the measured height of a source row.
        final content =
            (config?.enabled == false
                ? null
                : config?.builder?.call(context, details, widget.child)) ??
            Stack(
              fit: StackFit.passthrough,
              children: [
                widget.child,
                if (selected && config?.enabled != false)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: style.inset,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                style.backgroundColor ??
                                color.withValues(alpha: .06),
                            border: Border.all(
                              color: color,
                              width: style.borderWidth,
                            ),
                            borderRadius: style.borderRadius,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
        return Focus(
          canRequestFocus: false,
          onFocusChange: (focused) {
            if (focused && !navigation.isDisposed) {
              navigation.select(widget.fileId, widget.annotationId);
            }
          },
          child: Listener(
            onPointerDown: (_) {
              if (!navigation.isDisposed) {
                navigation.select(widget.fileId, widget.annotationId);
              }
            },
            child: Semantics(
              selected: selected,
              child: _DiscussionLayoutObserver(
                key: _target,
                onLayout: _queueReveal,
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

class _DiscussionLayoutObserver extends SingleChildRenderObjectWidget {
  const _DiscussionLayoutObserver({
    super.key,
    required this.onLayout,
    required super.child,
  });
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _DiscussionLayoutBox(onLayout);
  @override
  void updateRenderObject(
    BuildContext context,
    _DiscussionLayoutBox renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _DiscussionLayoutBox extends RenderProxyBox {
  _DiscussionLayoutBox(this.onLayout);
  VoidCallback onLayout;
  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}

Widget commentFileHeader(
  BuildContext context,
  Widget header,
  CommentNavigationController? controller,
  String fileId,
  Widget Function(BuildContext, CommentNavigationDetails)? builder,
) {
  if (controller == null || controller.count(fileId: fileId) == 0) {
    return header;
  }
  final count = SyntaxCommentCount(
    controller: controller,
    fileId: fileId,
    builder: builder,
  );
  return LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 480
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              Align(alignment: Alignment.centerLeft, child: count),
            ],
          )
        : Row(
            children: [
              Expanded(child: header),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .4,
                ),
                child: count,
              ),
            ],
          ),
  );
}
