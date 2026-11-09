// Internal renderer coordination, not exported as public API.
// ignore_for_file: public_member_api_docs

import 'dart:collection';
import 'dart:math' as math;

import 'package:syntax_core/syntax.dart' show DiffSide;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'code_rows.dart';

typedef TextCell = ({int row, DiffSide? side});

/// Native character selection over a virtual document. Only endpoints must
/// remain mounted; intermediate code comes from the immutable source rows.
final class DiffTextSelection extends RowSelectionDelegate {
  final retainedRows = ValueNotifier<Set<Object>>(const {});
  final activeSide = ValueNotifier<DiffSide?>(null);
  final _cells = <TextCell, RowSelectionDelegate>{};
  final _listeners = <TextCell, VoidCallback>{};
  final _selected = SplayTreeSet<TextCell>((a, b) {
    final row = a.row.compareTo(b.row);
    return row != 0
        ? row
        : (a.side?.index ?? -1).compareTo(b.side?.index ?? -1);
  });
  Object? _source;
  int _rowCount = 0;
  bool _split = false;
  bool _all = false;
  bool _gutter = false;
  bool _disposed = false;
  bool _queued = false;
  bool _clearing = false;
  String? Function(int, DiffSide?) _textAt = (_, _) => null;
  String Function(int, DiffSide?) _endingAt = (_, _) => '\n';
  Object Function(int) _identity = (row) => row;
  VoidCallback? onBegin;

  void configure({
    required Object source,
    required int rowCount,
    required bool split,
    required String? Function(int, DiffSide?) textAt,
    required Object Function(int) identity,
    String Function(int, DiffSide?)? endingAt,
  }) {
    if (_source != source) {
      clear();
      activeSide.value = null;
      _source = source;
    }
    _rowCount = rowCount;
    _split = split;
    _textAt = textAt;
    _endingAt = endingAt ?? ((_, _) => '\n');
    _identity = identity;
  }

  void begin(DiffSide? side) {
    if (_split && activeSide.value != side) clear();
    _gutter = false;
    activeSide.value = _split ? side : null;
    onBegin?.call();
  }

  void beginGutter() {
    clear();
    _gutter = true;
  }

  void clear() {
    // A stale scrollable delegate can replay its old range as children arrive.
    // Only a new user selection may unlock code cells after this reset.
    _gutter = true;
    _all = false;
    super.dispatchSelectionEvent(const ClearSelectionEvent());
    _selected.clear();
    _publishRetained();
  }

  bool _accepts(TextCell cell) =>
      !_gutter &&
      (!_split || activeSide.value == null || cell.side == activeSide.value);

  void register(TextCell cell, RowSelectionDelegate delegate) {
    unregister(cell);
    _cells[cell] = delegate;
    void changed() {
      if ((delegate.getSelectedContent()?.plainText.isNotEmpty ?? false) &&
          _accepts(cell)) {
        _selected.add(cell);
      } else {
        _selected.remove(cell);
      }
      _publishRetained();
    }

    _listeners[cell] = changed;
    delegate.addListener(changed);
    changed();
  }

  void unregister(TextCell cell, [RowSelectionDelegate? delegate]) {
    final current = _cells[cell];
    if (current == null ||
        (delegate != null && !identical(current, delegate))) {
      return;
    }
    current.removeListener(_listeners.remove(cell)!);
    _cells.remove(cell);
    _selected.remove(cell);
    _publishRetained();
  }

  void _restore(TextCell cell, RowSelectionDelegate delegate) {
    if (_disposed ||
        _clearing ||
        !_accepts(cell) ||
        !_cells.containsKey(cell)) {
      return;
    }
    final selected = _selected.where(_accepts).toList();
    if (_all ||
        (selected.length >= 2 &&
            cell.row > selected.first.row &&
            cell.row < selected.last.row)) {
      delegate.dispatchSelectionEvent(const SelectAllSelectionEvent());
    }
  }

  void _publishRetained() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_queued) return;
      _queued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        _publishRetained();
      });
      return;
    }
    final selected = _selected.where(_accepts).toList();
    final ids = <Object>{
      if (selected.isNotEmpty) _identity(selected.first.row),
      if (selected.isNotEmpty) _identity(selected.last.row),
    };
    if (!setEquals(retainedRows.value, ids)) {
      retainedRows.value = Set.unmodifiable(ids);
    }
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (event is SelectAllSelectionEvent) {
      _gutter = false;
      onBegin?.call();
    }
    if (_gutter && event is! ClearSelectionEvent) {
      return SelectionResult.none;
    }
    _all = event is SelectAllSelectionEvent;
    return super.dispatchSelectionEvent(event);
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    _clearing = true;
    try {
      // Clearing an old scroll container can synchronously unregister it.
      // Flush those notifications over a snapshot before the base delegate
      // resets its edge bookkeeping and visits the now-stable children.
      for (final selectable in selectables.toList()) {
        dispatchSelectionEventToChild(selectable, event);
      }
      return super.handleClearSelection(event);
    } finally {
      _clearing = false;
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    final selected = _selected.where(_accepts).toList();
    if (!_all && selected.isEmpty) return null;
    if (_rowCount == 0) return null;
    final first = _all ? 0 : selected.first.row;
    final last = _all ? _rowCount - 1 : selected.last.row;
    final startRange = _all ? null : _cells[selected.first]?.getSelection();
    final endRange = _all ? null : _cells[selected.last]?.getSelection();
    if (!_all && (startRange == null || endRange == null)) return null;
    final buffer = StringBuffer();
    String? previousEnding;
    for (var row = first; row <= last; row++) {
      final text = _textAt(
        row,
        _split ? activeSide.value ?? DiffSide.newer : null,
      );
      if (text == null) continue;
      final start = row == first && startRange != null
          ? math
                .min(startRange.startOffset, startRange.endOffset)
                .clamp(0, text.length)
          : 0;
      final end = row == last && endRange != null
          ? math
                .max(endRange.startOffset, endRange.endOffset)
                .clamp(start, text.length)
          : text.length;
      if (previousEnding != null) buffer.write(previousEnding);
      buffer.write(text.substring(start, end));
      previousEnding = _endingAt(
        row,
        _split ? activeSide.value ?? DiffSide.newer : null,
      );
    }
    final text = buffer.toString();
    return text.isEmpty ? null : SelectedContent(plainText: text);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final cell in _cells.keys.toList()) {
      unregister(cell);
    }
    retainedRows.dispose();
    activeSide.dispose();
    super.dispose();
  }
}

/// One code cell, excluding gutters, headers, and inline comments.
final class DiffSelectableCell extends StatefulWidget {
  const DiffSelectableCell({
    super.key,
    required this.selection,
    required this.cell,
    required this.child,
  });

  final DiffTextSelection selection;
  final TextCell cell;
  final Widget child;

  @override
  State<DiffSelectableCell> createState() => _DiffSelectableCellState();
}

final class _DiffSelectableCellState extends State<DiffSelectableCell> {
  late final _delegate = _CellSelection(
    () => widget.selection._accepts(widget.cell),
    (delegate) => widget.selection._restore(widget.cell, delegate),
  );
  Widget? _held;

  @override
  void initState() {
    super.initState();
    widget.selection.register(widget.cell, _delegate);
    _delegate.addListener(_changed);
  }

  void _changed() {
    if (_delegate.value.hasSelection) {
      _held ??= widget.child;
    } else if (_held != null) {
      _held = null;
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void didUpdateWidget(DiffSelectableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection ||
        oldWidget.cell != widget.cell) {
      oldWidget.selection.unregister(oldWidget.cell, _delegate);
      widget.selection.register(widget.cell, _delegate);
      _held = null;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => widget.selection.begin(widget.cell.side),
    child: SelectionContainer(
      delegate: _delegate,
      child: _held ?? widget.child,
    ),
  );

  @override
  void dispose() {
    widget.selection.unregister(widget.cell, _delegate);
    _delegate.dispose();
    super.dispose();
  }
}

/// Keep both split columns registered. Replacing the other column with a
/// disabled container would leave the next drag without an initial anchor
/// until Flutter registers that column again after a frame.
final class _CellSelection extends RowSelectionDelegate {
  _CellSelection(this.accepts, this.restore);

  final bool Function() accepts;
  final void Function(RowSelectionDelegate) restore;

  @override
  void didChangeSelectables() {
    super.didChangeSelectables();
    restore(this);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) =>
      event is ClearSelectionEvent || accepts()
      ? super.dispatchSelectionEvent(event)
      : SelectionResult.none;
}
