import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:syntax/syntax.dart';
import 'comment_gutter.dart';
import 'comment_thread_controller.dart';
import 'comment_composer.dart';
import 'comment_thread.dart';

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
    this.threadDetails,
  });

  /// Source identity, addresses and visible discussion snapshots.
  final CommentGutterDetails gutter;

  /// Dismisses this preview without selecting or changing a discussion.
  final VoidCallback close;

  /// Resolves guarded editing commands for an application-owned session.
  /// Null when no session resolver is supplied. Custom whole-preview builders
  /// can use [thread] to build their own actions and reply input.
  final CommentGutterPreviewThreadDetails? Function(CommentThreadLocation)?
  threadDetails;

  /// Current preview-local editor state, or null for an unavailable session.
  CommentGutterPreviewThreadDetails? thread(CommentThreadLocation location) =>
      threadDetails?.call(location);

  /// Closes the preview, then expands, reveals and focuses the chosen thread.
  /// This is independent of the gutter's onActivate action. Omit [thread] to
  /// use the gutter's next discussion. Stale destinations return false.
  Future<bool> open([CommentThreadLocation? thread]) {
    close();
    return gutter.open(thread);
  }
}

/// Shared draft and guarded commands for one discussion inside a preview.
///
/// Commands are null when busy or unauthorized and recheck source/thread
/// revisions when invoked. Retaining an old details object cannot mutate a
/// replacement thread or source. Persistence belongs to [controller].
class CommentGutterPreviewThreadDetails {
  /// Describes a preview editor without taking ownership of its session.
  const CommentGutterPreviewThreadDetails({
    required this.controller,
    required this.location,
    required this.focusNode,
    required this.isReplying,
    required this.reply,
    required this.cancelReply,
    required this.submitReply,
    required this.toggleResolved,
  });

  /// Retained application-owned session, including its shared replyInput.
  final CommentThreadController controller;

  /// Source and thread snapshot used by these commands.
  final CommentThreadLocation location;

  /// Focus owned by this preview, distinct from the inline thread's focus node.
  /// Custom inputs should use it; do not dispose it or retain it after dismissal.
  final FocusNode focusNode;

  /// Whether this preview is displaying a reply form.
  final bool isReplying;

  /// Opens the preview reply form without expanding or focusing the inline UI.
  final VoidCallback? reply;

  /// Discards the shared draft and closes this preview's form; null while saving.
  /// Merely dismissing the preview always retains the draft.
  final VoidCallback? cancelReply;

  /// Saves the shared draft, or null when empty, stale, busy or unauthorized.
  final Future<bool> Function()? submitReply;

  /// Resolves/reopens in place, or null when stale, busy or unauthorized.
  final Future<bool> Function()? toggleResolved;

  /// Current application request state and failure, for custom controls.
  bool get isSubmitting => controller.isSubmitting;
  Object? get error => controller.error;
}

class _PreviewSession {
  _PreviewSession(this.controller)
    : replying = controller.replyInput.text.isNotEmpty;
  final CommentThreadController controller;
  final focus = FocusNode(debugLabel: 'Preview reply');
  bool replying;
  bool listening = false;
  void dispose() => focus.dispose();
}

bool _matchesPreviewSource(
  CommentGutterDetails gutter,
  CommentThreadLocation target,
  CommentThreadController session, {
  bool includeFiltered = false,
}) {
  if (gutter.controller.isDisposed ||
      session.isDisposed ||
      session.thread.id != target.thread.id ||
      session.thread.revision != target.thread.revision) {
    return false;
  }
  return gutter.controller.threads.any(
    (entry) =>
        entry.key == target.key &&
        entry.thread.id == target.thread.id &&
        entry.thread.revision == target.thread.revision &&
        entry.sourceRevision == gutter.sourceRevision &&
        gutter.sourceLines.contains((entry.line, entry.side)) &&
        (includeFiltered || gutter.controller.isVisible(entry.thread)),
  );
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
  final _sessions = <(String, String), _PreviewSession>{};
  int _epoch = 0;
  int _mutations = 0;
  Timer? _showTimer, _hideTimer;
  OverlayState? _owner;
  CommentNavigationController? _listening;
  FocusNode? _returnFocus;
  bool _markerHovered = false, _previewHovered = false;
  Size? _size;
  Rect? _anchorRect;
  bool _positionScheduled = false;

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
      _anchorRect = _readAnchorRect();
      _owner = Overlay.of(context);
      _owners[_owner!]?._hide();
      _owners[_owner!] = this;
      // Both vertical and horizontal ancestor scrolling dismiss the preview.
      context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          final position = (element.state as ScrollableState).position;
          if (!_scrolls.contains(position)) {
            _scrolls.add(position);
            position.addListener(_sourceScrolled);
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

  Rect? _readAnchorRect() {
    final box = _anchor.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final overlay = Overlay.of(context).context.findRenderObject()!;
    return Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
  }

  void _positionAfterLayout() {
    if (_positionScheduled || !_portal.isShowing) return;
    _positionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionScheduled = false;
      if (!mounted || !_portal.isShowing) return;
      final rect = _readAnchorRect();
      if (rect != null && rect != _anchorRect) {
        setState(() => _anchorRect = rect);
      }
    });
  }

  void _changed() {
    if (_current().threads.isEmpty) {
      _hide();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _sourceScrolled() {
    // Collapsing an inline thread can reduce the viewport's scroll extent.
    // Keep this preview through layout corrections from its own save, while
    // still dismissing immediately for active user scrolling.
    if (_mutations > 0 &&
        _scrolls.every((position) => !position.isScrollingNotifier.value)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _portal.isShowing) setState(() {});
      });
      return;
    }
    _hide();
  }

  Future<bool> _mutate(Future<bool> Function() operation) async {
    _mutations++;
    try {
      return await operation();
    } finally {
      // Indexed rows measure their changed height after the first frame and
      // correct the source scroll offset in the following layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _mutations--);
        WidgetsBinding.instance.scheduleFrame();
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _listen(_PreviewSession binding) {
    if (binding.listening) return;
    binding.replying = binding.controller.replyInput.text.isNotEmpty;
    binding.listening = true;
    binding.controller.addListener(_changed);
    binding.controller.replyInput.addListener(_changed);
  }

  void _unlisten(_PreviewSession binding) {
    if (!binding.listening) return;
    binding.listening = false;
    binding.controller.removeListener(_changed);
    binding.controller.replyInput.removeListener(_changed);
  }

  void _syncSessions(CommentGutterDetails gutter) {
    final next = <(String, String), CommentThreadController>{};
    for (final entry in gutter.threads) {
      final session = widget.config?.previewThreadController?.call(entry);
      if (session != null && _matchesPreviewSource(gutter, entry, session)) {
        next[entry.key] = session;
      }
    }
    for (final key in _sessions.keys.toList()) {
      if (next[key] != _sessions[key]!.controller) {
        final old = _sessions.remove(key)!;
        _unlisten(old);
        old.dispose();
      }
    }
    for (final entry in next.entries) {
      final binding = _sessions.putIfAbsent(
        entry.key,
        () => _PreviewSession(entry.value),
      );
      _listen(binding);
    }
  }

  CommentGutterPreviewThreadDetails? _threadDetails(
    CommentGutterDetails gutter,
    CommentThreadLocation location,
    int epoch,
  ) {
    final binding = _sessions[location.key];
    if (binding == null) return null;
    final session = binding.controller;
    bool current() =>
        mounted &&
        _portal.isShowing &&
        epoch == _epoch &&
        _sessions[location.key] == binding &&
        _matchesPreviewSource(gutter, location, session);
    // Completion may outlive this overlay. A closed preview does not cancel an
    // authorized save, but a changed source or external thread update does.
    bool sourceCurrent() =>
        _matchesPreviewSource(gutter, location, session, includeFiltered: true);
    if (!current()) return null;
    return CommentGutterPreviewThreadDetails(
      controller: session,
      location: location,
      focusNode: binding.focus,
      isReplying: binding.replying,
      reply: session.isSubmitting || !session.mayReply
          ? null
          : () {
              if (!current() || session.isSubmitting || !session.mayReply) {
                return;
              }
              setState(() => binding.replying = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (current() && binding.replying) binding.focus.requestFocus();
              });
            },
      cancelReply: session.isSubmitting
          ? null
          : () {
              if (!current() || session.isSubmitting) return;
              session.cancelReply();
              setState(() => binding.replying = false);
              _focus.requestFocus();
            },
      submitReply:
          !binding.replying ||
              session.isSubmitting ||
              !session.mayReply ||
              session.replyInput.text.trim().isEmpty
          ? null
          : () async {
              if (!current() || session.isSubmitting || !session.mayReply) {
                return false;
              }
              final saved = await _mutate(
                () => session.submitReplyDraft(isCurrent: sourceCurrent),
              );
              if (saved &&
                  mounted &&
                  _sessions[location.key] == binding &&
                  session.replyInput.text.isEmpty) {
                setState(() => binding.replying = false);
                if (_portal.isShowing &&
                    epoch == _epoch &&
                    binding.focus.hasFocus) {
                  _focus.requestFocus();
                }
              }
              return saved;
            },
      toggleResolved: session.isSubmitting || !session.mayResolve
          ? null
          : () {
              if (!current() || session.isSubmitting || !session.mayResolve) {
                return Future.value(false);
              }
              return _mutate(
                () => session.toggleResolved(isCurrent: sourceCurrent),
              );
            },
    );
  }

  void _detach() {
    for (final position in _scrolls) {
      position.removeListener(_sourceScrolled);
    }
    _scrolls.clear();
    _listening?.removeListener(_changed);
    _listening = null;
    for (final binding in _sessions.values) {
      _unlisten(binding);
    }
    if (_owner != null && _owners[_owner!] == this) _owners[_owner!] = null;
    _owner = null;
  }

  void _hide({bool restoreFocus = false}) {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _previewHovered = false;
    _epoch++;
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
    _positionAfterLayout();
    final rect = _anchorRect;
    if (rect == null) return const SizedBox.shrink();
    final gutter = _current();
    _syncSessions(gutter);
    final epoch = _epoch;
    final details = CommentGutterPreviewDetails(
      gutter: gutter,
      close: _hide,
      threadDetails: (location) => _threadDetails(gutter, location, epoch),
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
    for (final binding in _sessions.values) {
      binding.dispose();
    }
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
                final editor = details.thread(entry);
                final labels =
                    config?.previewThreadLabels ?? const CommentThreadLabels();
                final defaultActions = Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    if (editor?.controller.mayReply == true &&
                        !editor!.isReplying)
                      TextButton.icon(
                        onPressed: editor.reply,
                        icon: const Icon(Icons.reply, size: 16),
                        label: Text(labels.reply),
                      ),
                    if (editor?.controller.mayResolve == true)
                      TextButton.icon(
                        onPressed: editor!.toggleResolved,
                        icon: Icon(
                          thread.resolved ? Icons.refresh : Icons.check,
                          size: 16,
                        ),
                        label: Text(
                          thread.resolved ? labels.reopen : labels.resolve,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => details.open(entry),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open thread'),
                    ),
                  ],
                );
                final actions = config?.previewActionsBuilder == null
                    ? defaultActions
                    : config!.previewActionsBuilder!(
                        context,
                        details,
                        entry,
                        defaultActions,
                      );
                Widget? composer;
                if (editor != null && editor.isReplying) {
                  final form = CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): () =>
                          editor.submitReply?.call(),
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): () =>
                          editor.submitReply?.call(),
                    },
                    child: SyntaxCommentComposer(
                      autofocus: false,
                      controller: editor.controller.replyInput,
                      focusNode: editor.focusNode,
                      onSubmit: (_) => editor.submitReply?.call(),
                      onCancel: () => editor.cancelReply?.call(),
                      canSubmit: editor.submitReply != null,
                      isSubmitting: editor.isSubmitting,
                      shortcutsEnabled: false,
                      title: labels.reply,
                      submitLabel: labels.postReply,
                      cancelLabel: labels.cancel,
                      inputDecoration: InputDecoration(
                        labelText: labels.inputLabel,
                        border: const OutlineInputBorder(),
                      ),
                      errorText: editor.error == null ? null : labels.failure,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                    ),
                  );
                  composer = config?.previewComposerBuilder == null
                      ? form
                      : config!.previewComposerBuilder!(context, editor, form);
                }
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
                    if (editor?.error != null && !editor!.isReplying)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          labels.failure,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (composer != null)
                      _PreviewComposer(
                        key: ValueKey(entry.key),
                        focus: editor!.focusNode,
                        child: composer,
                      ),
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

// Reveal the form's actions inside the preview's own scrollable. Walking all
// ancestor scrollables would also scroll the source and dismiss the overlay.
class _PreviewComposer extends StatefulWidget {
  const _PreviewComposer({super.key, required this.focus, required this.child});
  final FocusNode focus;
  final Widget child;
  @override
  State<_PreviewComposer> createState() => _PreviewComposerState();
}

class _PreviewComposerState extends State<_PreviewComposer> {
  bool _revealed = false;
  void _focused() {
    if (_revealed || !widget.focus.hasFocus) return;
    _revealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focus.hasFocus) return;
      final target = context.findRenderObject();
      if (target != null) {
        Scrollable.maybeOf(
          context,
        )?.position.ensureVisible(target, alignment: 1);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_focused);
    _focused();
  }

  @override
  void didUpdateWidget(_PreviewComposer old) {
    super.didUpdateWidget(old);
    if (old.focus == widget.focus) return;
    old.focus.removeListener(_focused);
    widget.focus.addListener(_focused);
    _revealed = false;
    _focused();
  }

  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    widget.focus.removeListener(_focused);
    super.dispose();
  }
}
