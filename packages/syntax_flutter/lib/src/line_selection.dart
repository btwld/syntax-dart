// Internal renderer coordination, not exported as public API.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Internal pointer coordinator. Only a gutter starts a logical line drag;
/// code keeps Flutter's native text selection. Targets are mounted rows only.
class LineSelectionRegion extends StatefulWidget {
  const LineSelectionRegion({
    super.key,
    required this.controller,
    required this.child,
  });
  final ScrollController controller;
  final Widget child;
  @override
  State<LineSelectionRegion> createState() => _LineSelectionRegionState();
}

class _LineSelectionRegionState extends State<LineSelectionRegion> {
  final targets = <_LineSelectionTargetState>{};
  Offset? pointer;
  int? pointerId;
  Timer? timer;

  void start(PointerDownEvent event, _LineSelectionTargetState target) {
    if (event.buttons != 1 || pointerId != null) return;
    pointerId = event.pointer;
    pointer = event.position;
    target.select(event.position, HardwareKeyboard.instance.isShiftPressed);
    timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final position = pointer;
      final box = context.findRenderObject();
      if (position == null ||
          box is! RenderBox ||
          !widget.controller.hasClients) {
        return;
      }
      final y = box.globalToLocal(position).dy;
      final delta = y < 28
          ? -18.0
          : y > box.size.height - 28
          ? 18.0
          : 0.0;
      if (delta == 0) return;
      final scroll = widget.controller;
      scroll.jumpTo(
        (scroll.offset + delta).clamp(0, scroll.position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pointer != null) selectAt(pointer!);
      });
    });
  }

  void selectAt(Offset position) {
    final viewport = context.findRenderObject();
    if (viewport is RenderBox && viewport.hasSize) {
      final local = viewport.globalToLocal(position);
      position = viewport.localToGlobal(
        Offset(local.dx, local.dy.clamp(0, viewport.size.height - 1)),
      );
    }
    for (final target in targets.toList()) {
      final box = target.context.findRenderObject();
      if (!target.mounted || box is! RenderBox || !box.hasSize) continue;
      final local = box.globalToLocal(position);
      if (local.dy >= 0 && local.dy < box.size.height) {
        target.select(position, true);
        return;
      }
    }
  }

  void stop() {
    timer?.cancel();
    timer = null;
    pointerId = null;
    pointer = null;
  }

  @override
  Widget build(BuildContext context) => _SelectionScope(
    owner: this,
    child: Listener(
      onPointerMove: (event) {
        if (event.pointer != pointerId) return;
        pointer = event.position;
        selectAt(event.position);
      },
      onPointerUp: (event) {
        if (event.pointer == pointerId) stop();
      },
      onPointerCancel: (event) {
        if (event.pointer == pointerId) stop();
      },
      child: widget.child,
    ),
  );
  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

class _SelectionScope extends InheritedWidget {
  const _SelectionScope({required this.owner, required super.child});
  final _LineSelectionRegionState owner;
  @override
  bool updateShouldNotify(_SelectionScope oldWidget) =>
      oldWidget.owner != owner;
}

class LineSelectionTarget extends StatefulWidget {
  const LineSelectionTarget({
    super.key,
    required this.child,
    required this.isGutter,
    required this.onSelect,
  });
  final Widget child;
  final bool Function(double x, double width) isGutter;
  final void Function(double x, double width, bool extend) onSelect;
  @override
  State<LineSelectionTarget> createState() => _LineSelectionTargetState();
}

class _LineSelectionTargetState extends State<LineSelectionTarget> {
  _LineSelectionRegionState? owner;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    owner?.targets.remove(this);
    owner = context
        .dependOnInheritedWidgetOfExactType<_SelectionScope>()
        ?.owner;
    owner?.targets.add(this);
  }

  void select(Offset position, bool extend) {
    final box = context.findRenderObject() as RenderBox;
    widget.onSelect(box.globalToLocal(position).dx, box.size.width, extend);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      final box = context.findRenderObject() as RenderBox;
      if (widget.isGutter(event.localPosition.dx, box.size.width)) {
        owner?.start(event, this);
      }
    },
    child: widget.child,
  );
  @override
  void dispose() {
    owner?.targets.remove(this);
    super.dispose();
  }
}
