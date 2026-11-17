import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

/// View-owned styled output, independent of the scheduler's input LRU.
/// Mounted rows pin their windows; at most eight unmounted windows are kept.
class MountedWindowHighlights extends MountedResourceCache<List<StyledRange>> {
  /// Number of distinct windows needed by mounted rows.
  int get mountedWindows => mountedEntries;

  /// Returns retained output before requesting work from [load].
  List<StyledRange>? rangesFor(
    Object key,
    List<StyledRange>? Function() load,
  ) => resourceFor(key, load);
}

/// Resources follow mounted row lifetimes, with bounded unmounted retention.
/// Mounting is the retention contract; the scheduler still bounds input work.
class MountedResourceCache<T extends Object> {
  /// [codeUnits] measures unmounted resources when a size limit is supplied.
  MountedResourceCache({this.maxCodeUnits, this.codeUnits})
    : assert(maxCodeUnits == null || codeUnits != null);

  /// Maximum UTF-16 size of the unmounted working set.
  final int? maxCodeUnits;

  /// Computes the source size retained by a resource.
  final int Function(T)? codeUnits;
  final _ready = <Object, T>{};
  final _unpinned = <Object>{};
  final _pins = <Object, int>{};
  Set<Object>? _building;

  /// Number of distinct resources needed by mounted rows.
  int get mountedEntries => _pins.length;

  /// Includes mounted resources and the bounded unmounted working set.
  Iterable<T> get values => _ready.values;

  /// Retains resources used by [builder] until its row is unmounted.
  /// [also] shares this exact build scope across related caches.
  Widget retain(
    Widget Function() builder, {
    List<MountedResourceCache<Object>> also = const [],
  }) => _RetainedResources(caches: [this, ...also], builder: builder);

  /// Returns a retained resource before requesting it from [load].
  T? resourceFor(Object key, T? Function() load) {
    _building?.add(key);
    final resource = _ready[key] ?? load();
    if (resource != null) remember(key, resource);
    return resource;
  }

  /// Retains a resource, evicting only unmounted working-set entries.
  void remember(Object key, T resource) {
    _ready[key] = resource;
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
    while (_unpinned.length > 8 ||
        (maxCodeUnits != null &&
            _unpinned.length > 1 &&
            _unpinned.fold<int>(0, (n, key) => n + codeUnits!(_ready[key]!)) >
                maxCodeUnits!)) {
      final candidates = _unpinned.where(
        (key) => !(_building?.contains(key) ?? false),
      );
      if (candidates.isEmpty) break;
      final oldest = candidates.first;
      _unpinned.remove(oldest);
      _ready.remove(oldest);
    }
  }
}

class _RetainedResources extends StatefulWidget {
  const _RetainedResources({required this.caches, required this.builder});

  final List<MountedResourceCache<Object>> caches;
  final Widget Function() builder;

  @override
  State<_RetainedResources> createState() => _RetainedResourcesState();
}

class _RetainedResourcesState extends State<_RetainedResources> {
  final _keys = <MountedResourceCache<Object>, Set<Object>>{};

  @override
  void didUpdateWidget(_RetainedResources oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final cache in _keys.keys.toList()) {
      if (!widget.caches.contains(cache)) {
        cache._updatePins(_keys.remove(cache)!, const {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = <MountedResourceCache<Object>, Set<Object>>{};
    final previous = <MountedResourceCache<Object>, Set<Object>?>{};
    for (final cache in widget.caches) {
      previous[cache] = cache._building;
      cache._building = current[cache] = <Object>{};
    }
    try {
      return widget.builder();
    } finally {
      for (final cache in widget.caches) {
        cache._building = previous[cache];
        cache._updatePins(_keys[cache] ?? const {}, current[cache]!);
        _keys[cache] = current[cache]!;
      }
    }
  }

  @override
  void dispose() {
    for (final entry in _keys.entries) {
      entry.key._updatePins(entry.value, const {});
    }
    super.dispose();
  }
}
