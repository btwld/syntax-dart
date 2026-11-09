import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Preserves a measured source row in an eagerly laid-out patch column.
/// Internal to shrink-wrapped patches; bounded patches use the indexed viewport.
final class ShrinkWrapScrollAnchor {
  /// Key of the column whose direct render children correspond to row IDs.
  final key = GlobalKey();
  List<Object> _identities = const [];

  /// Captures the old visible row before installing the next row identities.
  /// Returns a post-layout correction, resolving removed rows through [resolve].
  /// Set [preserve] to false when an explicit reveal will own navigation.
  VoidCallback? update(
    List<Object> identities, {
    required Object? Function(Object) resolve,
    required bool preserve,
  }) {
    final anchor = preserve ? _capture() : null;
    _identities = identities;
    if (anchor == null) return null;
    return () {
      final identity = resolve(anchor.identity);
      final context = key.currentContext;
      if (identity == null || context == null) return;
      final bounds = _bounds(context);
      if (bounds == null) return;
      for (final (id, box) in _rows()) {
        if (id != identity) continue;
        // A removed source row may resolve to a folded file/hunk header.
        // Show that header rather than preserving an offset inside a tall row.
        final within = id == anchor.identity ? anchor.offset : 0.0;
        var remaining = box.localToGlobal(Offset.zero).dy - bounds.top - within;
        for (final scrollable in _scrollables(context)) {
          final position = scrollable.position;
          if (!position.hasContentDimensions || !position.hasPixels) continue;
          final direction = position.axisDirection == AxisDirection.up ? -1 : 1;
          final before = position.pixels;
          final after = (before + remaining * direction).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
          if ((after - before).abs() < .1) continue;
          position.jumpTo(after);
          // Paint transforms update at the next layout. Account for the consumed
          // delta here so enclosing scroll views only receive the remainder.
          remaining -= (after - before) * direction;
          if (remaining.abs() < .1) break;
        }
        return;
      }
    };
  }

  /// Drops identities when the owning view stops using the eager column.
  void clear() => _identities = const [];

  ({Object identity, double offset})? _capture() {
    final context = key.currentContext;
    if (context == null) return null;
    final bounds = _bounds(context);
    if (bounds == null || bounds.top >= bounds.bottom) return null;
    for (final (identity, box) in _rows()) {
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height <= bounds.top + .1 || top >= bounds.bottom) {
        continue;
      }
      return (identity: identity, offset: top - bounds.top);
    }
    return null;
  }

  Iterable<(Object, RenderBox)> _rows() sync* {
    final column = key.currentContext?.findRenderObject();
    if (column is! RenderFlex || !column.hasSize) return;
    var child = column.firstChild;
    for (final identity in _identities) {
      if (child == null) return;
      if (child.hasSize) yield (identity, child);
      child = column.childAfter(child);
    }
  }

  Iterable<ScrollableState> _scrollables(BuildContext context) sync* {
    var scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    while (scrollable != null) {
      yield scrollable;
      scrollable = Scrollable.maybeOf(scrollable.context, axis: Axis.vertical);
    }
  }

  ({double top, double bottom})? _bounds(BuildContext context) {
    double? top, bottom;
    for (final scrollable in _scrollables(context)) {
      final box = scrollable.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final start = box.localToGlobal(Offset.zero).dy;
      top = top == null ? start : math.max(top, start);
      final end = start + box.size.height;
      bottom = bottom == null ? end : math.min(bottom, end);
    }
    return top == null || bottom == null ? null : (top: top, bottom: bottom);
  }
}
