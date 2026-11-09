import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

/// View-owned styled output, independent of the scheduler's input LRU.
/// Mounted rows pin their windows; at most eight unmounted windows are kept.
class MountedWindowHighlights {
  final _ready = <Object, List<StyledRange>>{};
  final _unpinned = <Object>{};
  final _pins = <Object, int>{};
  Set<Object>? _building;

  /// Number of distinct windows needed by mounted rows.
  int get mountedWindows => _pins.length;

  /// Retains the windows used by [builder] until its row is unmounted.
  Widget retain(Widget Function() builder) =>
      _RetainedHighlights(cache: this, builder: builder);

  /// Returns retained output before requesting work from [load].
  List<StyledRange>? rangesFor(Object key, List<StyledRange>? Function() load) {
    _building?.add(key);
    final ranges = _ready[key] ?? load();
    if (ranges != null) remember(key, ranges);
    return ranges;
  }

  /// Accepts output without retaining the request's complete source.
  void remember(Object key, List<StyledRange> ranges) {
    _ready[key] = ranges;
    if (!_pins.containsKey(key)) {
      _unpinned.remove(key);
      _unpinned.add(key);
    }
    _trim();
  }

  /// Invalidates output while preserving mounted row lifetimes.
  void clear() {
    _ready.clear();
    _unpinned.clear();
  }

  void _updatePins(Set<Object> before, Set<Object> after) {
    for (final key in before.difference(after)) {
      final remaining = _pins[key]! - 1;
      if (remaining == 0) {
        _pins.remove(key);
        if (_ready.containsKey(key)) _unpinned.add(key);
      } else {
        _pins[key] = remaining;
      }
    }
    for (final key in after.difference(before)) {
      _pins.update(key, (count) => count + 1, ifAbsent: () => 1);
      _unpinned.remove(key);
    }
    _trim();
  }

  void _trim() {
    while (_unpinned.length > 8) {
      final oldest = _unpinned.first;
      _unpinned.remove(oldest);
      _ready.remove(oldest);
    }
  }
}

class _RetainedHighlights extends StatefulWidget {
  const _RetainedHighlights({required this.cache, required this.builder});

  final MountedWindowHighlights cache;
  final Widget Function() builder;

  @override
  State<_RetainedHighlights> createState() => _RetainedHighlightsState();
}

class _RetainedHighlightsState extends State<_RetainedHighlights> {
  Set<Object> _keys = {};

  @override
  void didUpdateWidget(_RetainedHighlights oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cache, widget.cache)) {
      oldWidget.cache._updatePins(_keys, const {});
      _keys = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = widget.cache;
    final keys = <Object>{};
    final previous = cache._building;
    cache._building = keys;
    try {
      return widget.builder();
    } finally {
      cache._building = previous;
      cache._updatePins(_keys, keys);
      _keys = keys;
    }
  }

  @override
  void dispose() {
    widget.cache._updatePins(_keys, const {});
    super.dispose();
  }
}
