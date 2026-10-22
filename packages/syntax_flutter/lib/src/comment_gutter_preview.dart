import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:syntax/syntax.dart';
import 'comment_gutter.dart';

/// Bounded, theme-aware surface for discussion previews in source gutters.
@immutable
class CommentGutterPreviewStyle {
  /// Defaults adapt to the code view's Material theme and available viewport.
  const CommentGutterPreviewStyle({
    this.width = 360,
    this.maxHeight = 340,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.elevation = 8,
  }) : assert(width > 0),
       assert(maxHeight > 0),
       assert(elevation >= 0);

  /// Preferred width and maximum height, clamped to the overlay's viewport.
  final double width, maxHeight;

  /// Surface, text and outline overrides; null uses the current color scheme.
  final Color? backgroundColor, foregroundColor, borderColor;

  /// Shape and shadow of both default and application-supplied previews.
  final BorderRadius borderRadius;
  final double elevation;
}

/// Current visible discussions and commands for custom hover previews.
class CommentGutterPreviewDetails {
  /// Commands retain the gutter snapshot's source-revision guards.
  const CommentGutterPreviewDetails({
    required this.gutter,
    required this.close,
  });

  /// Source identity, addresses and visible discussion snapshots.
  final CommentGutterDetails gutter;

  /// Dismisses this preview without selecting or changing a discussion.
  final VoidCallback close;

  /// Closes the preview, then expands, reveals and focuses the chosen thread.
  /// This is independent of the gutter's onActivate action. Omit [thread] to
  /// use the gutter's next discussion. Stale destinations return false.
  Future<bool> open([CommentThreadLocation? thread]) {
    close();
    return gutter.open(thread);
  }
}

// Internal adapter; previews belong to mounted source rows, not thread sessions.
// ignore_for_file: public_member_api_docs
class CommentGutterPreviewAnchor extends StatefulWidget {
  const CommentGutterPreviewAnchor({
    super.key,
    required this.details,
    required this.config,
    required this.child,
  });
  final CommentGutterDetails details;
  final SyntaxCommentGutterTheme? config;
  final Widget child;

  @override
  State<CommentGutterPreviewAnchor> createState() =>
      _CommentGutterPreviewAnchorState();
}

class _CommentGutterPreviewAnchorState
    extends State<CommentGutterPreviewAnchor> {
  static final _owners = Expando<_CommentGutterPreviewAnchorState>();
  final _portal = OverlayPortalController();
  final _anchor = GlobalKey();
  final _focus = FocusScopeNode(debugLabel: 'Discussion preview');
  final _scrolls = <ScrollPosition>[];
  Timer? _showTimer, _hideTimer;
  OverlayState? _owner;
  CommentNavigationController? _listening;
  FocusNode? _returnFocus;
  bool _markerHovered = false, _previewHovered = false;
  Size? _size;

  bool get _enabled => widget.config?.previewEnabled ?? true;

  CommentGutterDetails _current() {
    final source = widget.details;
    final threads = <(String, String), CommentThreadLocation>{};
    for (final (line, side) in source.sourceLines) {
      for (final t in source.controller.threadsAtLine(
        source.fileId,
        line,
        side: side,
        sourceRevision: source.sourceRevision,
      )) {
        threads[t.key] = t;
      }
    }
    return CommentGutterDetails(
      controller: source.controller,
      fileId: source.fileId,
      sourceRevision: source.sourceRevision,
      sourceLines: source.sourceLines,
      threads: threads.values.toList()
        ..sort((a, b) => a.annotationId.compareTo(b.annotationId)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    if (_size != null && _size != size) _hide();
    _size = size;
  }

  @override
  void didUpdateWidget(CommentGutterPreviewAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled ||
        oldWidget.details.controller != widget.details.controller ||
        oldWidget.details.fileId != widget.details.fileId ||
        oldWidget.details.sourceRevision != widget.details.sourceRevision ||
        oldWidget.details.sourceLines.length !=
            widget.details.sourceLines.length ||
        !oldWidget.details.sourceLines.every(
          widget.details.sourceLines.contains,
        )) {
      _hide();
    }
  }

  void _show({bool keyboard = false}) {
    _showTimer?.cancel();
    if (!mounted || !_enabled || _current().threads.isEmpty) return;
    _hideTimer?.cancel();
    if (!_portal.isShowing) {
      _owner = Overlay.of(context);
      _owners[_owner!]?._hide();
      _owners[_owner!] = this;
      // Both vertical and horizontal ancestor scrolling dismiss the preview.
      context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          final position = (element.state as ScrollableState).position;
          if (!_scrolls.contains(position)) {
            _scrolls.add(position);
            position.addListener(_hide);
          }
        }
        return true;
      });
      _listening = widget.details.controller..addListener(_changed);
      _portal.show();
    }
    if (keyboard) {
      _returnFocus = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _portal.isShowing) _focus.requestFocus();
      });
    }
  }

  void _changed() {
    if (_current().threads.isEmpty) {
      _hide();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _detach() {
    for (final position in _scrolls) {
      position.removeListener(_hide);
    }
    _scrolls.clear();
    _listening?.removeListener(_changed);
    _listening = null;
    if (_owner != null && _owners[_owner!] == this) _owners[_owner!] = null;
    _owner = null;
  }

  void _hide({bool restoreFocus = false}) {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _previewHovered = false;
    _detach();
    if (!_portal.isShowing) return;
    void hide() {
      if (!mounted) return;
      if (restoreFocus && _focus.hasFocus && _returnFocus?.context != null) {
        _returnFocus!.requestFocus();
      }
      _portal.hide();
    }

    // Layout correction and theme changes can occur during a build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => hide());
    } else {
      hide();
    }
  }

  void _leave() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    if (_markerHovered || _previewHovered || _focus.hasFocus) return;
    _hideTimer = Timer(
      widget.config?.previewHideDelay ?? const Duration(milliseconds: 200),
      _hide,
    );
  }

  Widget _overlay(BuildContext context) {
    final box = _anchor.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return const SizedBox.shrink();
    }
    final overlay = Overlay.of(this.context).context.findRenderObject()!;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final details = CommentGutterPreviewDetails(
      gutter: _current(),
      close: _hide,
    );
    if (details.gutter.threads.isEmpty) return const SizedBox.shrink();
    final config = widget.config;
    final style = config?.previewStyle ?? const CommentGutterPreviewStyle();
    final defaultBody = _PreviewBody(details: details, config: config);
    final body = config?.previewBuilder == null
        ? defaultBody
        : config!.previewBuilder!(context, details, defaultBody);
    if (body == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return CustomSingleChildLayout(
      delegate: _PreviewPosition(rect, style, MediaQuery.paddingOf(context)),
      child: TapRegion(
        onTapOutside: (_) => _hide(),
        child: MouseRegion(
          onEnter: (_) {
            _previewHovered = true;
            _hideTimer?.cancel();
          },
          onExit: (_) {
            _previewHovered = false;
            _leave();
          },
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _hide(restoreFocus: true),
            },
            child: FocusScope(
              node: _focus,
              onFocusChange: (focused) {
                if (focused) {
                  _hideTimer?.cancel();
                } else {
                  _leave();
                }
              },
              child: SelectionContainer.disabled(
                child: Material(
                  color: style.backgroundColor ?? colors.surfaceContainerHigh,
                  elevation: style.elevation,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: style.borderRadius,
                    side: BorderSide(
                      color: style.borderColor ?? colors.outlineVariant,
                    ),
                  ),
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: style.foregroundColor ?? colors.onSurface,
                    ),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: _overlay,
    child: TooltipVisibility(
      visible: !_enabled,
      child: MouseRegion(
        key: _anchor,
        onEnter: (event) {
          _markerHovered = true;
          _hideTimer?.cancel();
          if (!_enabled || event.buttons != 0) return;
          _showTimer?.cancel();
          _showTimer = Timer(
            widget.config?.previewDelay ?? const Duration(milliseconds: 350),
            _show,
          );
        },
        onExit: (_) {
          _markerHovered = false;
          _leave();
        },
        child: CallbackShortcuts(
          bindings: _enabled
              ? {
                  const SingleActivator(LogicalKeyboardKey.f2): () =>
                      _show(keyboard: true),
                  const SingleActivator(LogicalKeyboardKey.escape): _hide,
                }
              : const {},
          child: Listener(onPointerDown: (_) => _hide(), child: widget.child),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _detach();
    _focus.dispose();
    super.dispose();
  }
}

class _PreviewPosition extends SingleChildLayoutDelegate {
  _PreviewPosition(this.anchor, this.style, this.padding);
  final Rect anchor;
  final CommentGutterPreviewStyle style;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0,
          math.min(style.width, constraints.maxWidth - padding.horizontal - 16),
        ),
        maxHeight: math.max(
          0,
          math.min(
            style.maxHeight,
            constraints.maxHeight - padding.vertical - 16,
          ),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = padding.left + 8, top = padding.top + 8;
    final right = math.max(
      left,
      size.width - padding.right - childSize.width - 8,
    );
    final bottom = math.max(
      top,
      size.height - padding.bottom - childSize.height - 8,
    );
    final x = anchor.right + 8 <= right
        ? anchor.right + 8
        : anchor.left - childSize.width - 8;
    return Offset(x.clamp(left, right), anchor.top.clamp(top, bottom));
  }

  @override
  bool shouldRelayout(_PreviewPosition oldDelegate) =>
      anchor != oldDelegate.anchor ||
      style != oldDelegate.style ||
      padding != oldDelegate.padding;
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.details, required this.config});
  final CommentGutterPreviewDetails details;
  final SyntaxCommentGutterTheme? config;

  @override
  Widget build(BuildContext context) {
    final threads = details.gutter.threads;
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 14,
              right: 4,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    threads.length == 1
                        ? 'Discussion preview'
                        : '${threads.length} discussions',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Close preview',
                  onPressed: details.close,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              primary: false,
              shrinkWrap: true,
              padding: const EdgeInsets.all(14),
              itemCount: threads.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (context, index) {
                final entry = threads[index], thread = entry.thread;
                final comments = thread.comments;
                final defaultActions = Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => details.open(entry),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open thread'),
                  ),
                );
                final actions = config?.previewActionsBuilder == null
                    ? defaultActions
                    : config!.previewActionsBuilder!(
                        context,
                        details,
                        entry,
                        defaultActions,
                      );
                Widget excerpt(ReviewComment comment) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment.body.length > 1024
                            ? '${comment.body.substring(0, 1024)}…'
                            : comment.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      [
                        thread.resolved ? 'Resolved' : 'Unresolved',
                        if (comments.length > 1)
                          '${comments.length - 1} ${comments.length == 2 ? 'reply' : 'replies'}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    excerpt(comments.first),
                    if (comments.length > 1) excerpt(comments.last),
                    ?actions,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
