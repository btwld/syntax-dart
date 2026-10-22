import 'package:flutter/material.dart';
import 'package:syntax/syntax.dart';
import 'inline_comment_region.dart';

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
                      tooltip: labels.previous,
                      onPressed: details.previous,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                    Text(
                      '${details.position} / ${details.visible.length}',
                      semanticsLabel:
                          '${details.position} / ${details.visible.length}',
                    ),
                    IconButton(
                      tooltip: labels.next,
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

final _revealed = Expando<int>();

class CommentNavigationAnchor extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final navigation = controller;
    if (navigation == null) return child;
    return CommentNavigationListener(
      controller: navigation,
      builder: (context) {
        final selected = navigation.current?.key == (fileId, annotationId);
        final request = navigation.revealRequest;
        if (selected &&
            !navigation.isNavigating &&
            navigation.error == null &&
            _revealed[navigation] != request) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted ||
                navigation.isDisposed ||
                navigation.isNavigating ||
                navigation.revealRequest != request ||
                navigation.current?.key != (fileId, annotationId) ||
                _revealed[navigation] == request) {
              return;
            }
            _revealed[navigation] = request;
            Scrollable.ensureVisible(
              context,
              alignment: .1,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          });
        }
        return Semantics(
          selected: selected,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: selected
                  ? Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            child: child,
          ),
        );
      },
    );
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
