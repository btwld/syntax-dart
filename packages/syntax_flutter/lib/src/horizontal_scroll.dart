import 'package:flutter/widgets.dart';

// Mounted rows share one horizontal offset while each retains its own native
// scroll position. The group outlives the viewport's recycled row widgets.
/// Retains one horizontal position across a bounded set of mounted rows.
class HorizontalCodeGroup {
  final Set<_HorizontalCodeState> _members = {};

  /// Shared horizontal pixel offset.
  double offset = 0;

  /// Records user scrolling in the owning view's retained state.
  ValueChanged<double>? onChanged;
  bool _updating = false;

  /// Synchronizes mounted positions after native scrolling.
  void move(double value) {
    if (_updating || value == offset) return;
    offset = value;
    onChanged?.call(value);
    _updating = true;
    try {
      for (final member in _members.toList()) {
        member.synchronize();
      }
    } finally {
      _updating = false;
    }
  }
}

/// Supplies a shared horizontal position to descendant code rows.
class HorizontalCodeScope extends InheritedWidget {
  /// Attaches an externally retained scroll group.
  const HorizontalCodeScope({
    required this.group,
    required super.child,
    super.key,
  });

  /// Group shared by both split panes and neighboring rows.
  final HorizontalCodeGroup group;
  @override
  bool updateShouldNotify(HorizontalCodeScope oldWidget) =>
      oldWidget.group != group;
}

/// Native horizontal scrolling synchronized through the nearest scope.
class HorizontalCode extends StatefulWidget {
  /// Wraps one source row.
  const HorizontalCode({required this.child, this.group, super.key});

  /// Explicit group, or the nearest inherited group when omitted.
  final HorizontalCodeGroup? group;

  /// Source presentation without a gutter.
  final Widget child;
  @override
  State<HorizontalCode> createState() => _HorizontalCodeState();
}

class _HorizontalCodeState extends State<HorizontalCode> {
  final _controller = ScrollController();
  HorizontalCodeGroup? _group;
  bool _syncing = false;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() {
    if (!_syncing) _group?.move(_controller.offset);
  }

  void synchronize() {
    if (!_controller.hasClients || _group == null) return;
    final offset = _group!.offset.clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if (_controller.offset == offset) return;
    _syncing = true;
    try {
      _controller.jumpTo(offset);
    } finally {
      _syncing = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.dependOnInheritedWidgetOfExactType<HorizontalCodeScope>();
    _syncGroup();
  }

  @override
  void didUpdateWidget(HorizontalCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) _syncGroup();
  }

  void _syncGroup() {
    final group =
        widget.group ??
        context.getInheritedWidgetOfExactType<HorizontalCodeScope>()?.group;
    if (_group != group) {
      _group?._members.remove(this);
      _group = group;
      _group?._members.add(this);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) synchronize();
    });
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) synchronize();
          });
          return false;
        },
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      );
  @override
  void dispose() {
    _group?._members.remove(this);
    _controller.dispose();
    super.dispose();
  }
}
