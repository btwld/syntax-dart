part of 'patch_view.dart';

DiffLine? _textAt(DiffRow row, DiffSide? side) => switch (row) {
  DiffLineRow(:final line) =>
    side == DiffSide.old && line.oldNumber == null ||
            side == DiffSide.newer && line.newNumber == null
        ? null
        : line,
  DiffPairRow(:final left, :final right) => side == DiffSide.old ? left : right,
  _ => null,
};

bool _rowAddresses(DiffRow row, DiffSide side, int number) {
  final line = _textAt(row, side);
  return (side == DiffSide.old ? line?.oldNumber : line?.newNumber) == number;
}

extension _PatchSelection<T> on _PatchViewState<T> {
  void _setSelection(DiffSelection? selection) {
    if (_selection == selection || !mounted) return;
    _copiedSelection = null;
    _copiedText = null;
    final controller = widget.controller;
    if (controller != null) {
      controller.select(selection);
    } else {
      _rebuild(() => _localSelection = selection);
      _reportSelection();
    }
  }

  void _startDrag(DiffLineContext coordinate, PointerDownEvent event) {
    if (!widget.selectable || event.buttons != 1) return;
    final previous = _selection;
    _dragAnchor =
        HardwareKeyboard.instance.isShiftPressed &&
            previous != null &&
            previous.fileId == coordinate.file.id &&
            previous.revision == coordinate.file.revision
        ? DiffLineContext(
            file: coordinate.file,
            side: previous.side,
            line: previous.anchor,
          )
        : coordinate;
    _pointer = event.position;
    _nativeSelection.beginGutter();
    _extendTo(coordinate);
    _lineFocus.requestFocus();
  }

  void _extendTo(DiffLineContext coordinate) {
    final anchor = _dragAnchor;
    if (anchor == null ||
        coordinate.file.id != anchor.file.id ||
        coordinate.file.revision != anchor.file.revision ||
        !_files.any((file) => identical(file, coordinate.file))) {
      return;
    }
    _setSelection(
      DiffSelection(
        fileId: anchor.file.id,
        revision: anchor.file.revision,
        side: anchor.side,
        anchor: anchor.line,
        active: coordinate.line,
        activeSide: coordinate.side,
      ),
    );
  }

  void _moveDrag(PointerMoveEvent event) {
    if (_dragAnchor == null) return;
    _pointer = event.position;
    _extendDrag();
    if (!_autoScroll.isActive) {
      _lastTick = Duration.zero;
      _autoScroll.start();
    }
  }

  void _stopDrag() {
    _dragAnchor = null;
    _pointer = null;
    if (_autoScroll.isActive) _autoScroll.stop();
  }

  void _extendDrag() {
    if (_pointer == null || _dragAnchor == null) return;
    DiffLineContext? nearest;
    var distance = double.infinity;
    for (final entry in _gutterCells.entries) {
      if (!entry.value.mounted) continue;
      final (fileIndex, side, number) = entry.key;
      if (_files[fileIndex].id != _dragAnchor!.file.id) continue;
      final box = entry.value.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final y = _pointer!.dy;
      final x = _pointer!.dx;
      final dy = y < rect.top
          ? rect.top - y
          : y > rect.bottom
          ? y - rect.bottom
          : 0.0;
      final dx = x < rect.left
          ? rect.left - x
          : x > rect.right
          ? x - rect.right
          : 0.0;
      final delta = dy * 10000 + dx;
      if (delta < distance) {
        nearest = DiffLineContext(
          file: _files[fileIndex],
          side: side,
          line: number,
        );
        distance = delta;
      }
    }
    if (nearest != null) _extendTo(nearest);
  }

  void _scrollTick(Duration elapsed) {
    final seconds = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (_pointer == null) return;
    final row = _gutterCells.values
        .where((context) => context.mounted)
        .firstOrNull;
    if (row == null) return;
    var scrollable = Scrollable.maybeOf(row, axis: Axis.vertical);
    while (scrollable != null) {
      final position = scrollable.position;
      final box = scrollable.context.findRenderObject();
      if (box is RenderBox && box.hasSize && position.hasContentDimensions) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        final y = _pointer!.dy;
        final edge = y < rect.top + 24
            ? y - rect.top - 24
            : y > rect.bottom - 24
            ? y - rect.bottom + 24
            : 0.0;
        final direction = position.axisDirection == AxisDirection.up ? -1 : 1;
        final target =
            (position.pixels + direction * edge.clamp(-100, 100) * 15 * seconds)
                .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (target != position.pixels) {
          position.jumpTo(target);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _extendDrag();
          });
          return;
        }
      }
      scrollable = Scrollable.maybeOf(scrollable.context, axis: Axis.vertical);
    }
  }

  // Native selections and gutter copies share the same per-file range index.
  String _lineEnding(FileDiff file, DiffLine line, DiffSide? side) {
    side ??= line.newNumber == null ? DiffSide.old : DiffSide.newer;
    if ((side == DiffSide.old ? file.oldText : file.newText) == null) {
      return line.sourceLineEnding;
    }
    return (_lineEndings[file] ??= PatchLineEndings(file)).endingAt(line, side);
  }

  ({DiffLayout layout, int start, int end})? _boundsFor(
    FileDiff file,
    DiffSelection selection,
  ) {
    final key = (file, selection);
    if (_crossKey == key) return _crossBounds;
    _crossKey = key;
    final layout = DiffLayout([file], expandAll: true);
    final anchor = layout.rowForLine(
      0,
      selection.anchor,
      oldSide: selection.side == DiffSide.old,
    );
    final active = layout.rowForLine(
      0,
      selection.active,
      oldSide: selection.activeSide == DiffSide.old,
    );
    return _crossBounds = anchor == null || active == null
        ? null
        : (
            layout: layout,
            start: math.min(anchor, active),
            end: math.max(anchor, active),
          );
  }

  List<DiffLine> _selectedLines(DiffSelection selection) {
    final file = _files
        .where(
          (file) =>
              file.id == selection.fileId &&
              file.revision == selection.revision,
        )
        .firstOrNull;
    if (file == null) return [];
    if (!selection.crossesSides) {
      final full = selection.side == DiffSide.old
          ? file.oldLines
          : file.newLines;
      if (full != null) {
        return [
          for (var n = selection.start; n <= selection.end; n++)
            DiffLine(
              DiffLineKind.context,
              full[n - 1],
              oldNumber: selection.side == DiffSide.old ? n : null,
              newNumber: selection.side == DiffSide.newer ? n : null,
              sourceLineEnding: '\n',
            ),
        ];
      }
      return [
        for (final hunk in file.hunks)
          for (final line in hunk.lines)
            if ((selection.side == DiffSide.old
                    ? line.oldNumber
                    : line.newNumber)
                case final n? when n >= selection.start && n <= selection.end)
              line,
      ];
    }
    final bounds = _boundsFor(file, selection);
    if (bounds == null) return [];
    return [
      for (var i = bounds.start; i <= bounds.end; i++)
        if (bounds.layout[i] case DiffLineRow(:final line)) line,
    ];
  }

  String _selectedText(DiffSelection selection) {
    if (_copiedSelection == selection && _copiedText != null) {
      return _copiedText!;
    }
    final file = _files
        .where(
          (file) =>
              file.id == selection.fileId &&
              file.revision == selection.revision,
        )
        .firstOrNull;
    if (file == null) return '';
    final lines = _selectedLines(selection);
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      buffer.write(lines[i].text);
      if (i < lines.length - 1) {
        buffer.write(
          _lineEnding(
            file,
            lines[i],
            selection.crossesSides ? null : selection.side,
          ),
        );
      }
    }
    _copiedSelection = selection;
    return _copiedText = buffer.toString();
  }

  bool _lineSelected(FileDiff file, DiffLine line, DiffSide? side) {
    final selection = _selection;
    if (selection == null ||
        selection.fileId != file.id ||
        selection.revision != file.revision) {
      return false;
    }
    if (!selection.crossesSides) {
      if (side != null && side != selection.side) return false;
      final number = selection.side == DiffSide.old
          ? line.oldNumber
          : line.newNumber;
      return number != null &&
          number >= selection.start &&
          number <= selection.end;
    }
    if (side == DiffSide.old && line.oldNumber == null ||
        side == DiffSide.newer && line.newNumber == null) {
      return false;
    }
    final bounds = _boundsFor(file, selection);
    if (bounds == null) return false;
    // The same indexed coordinate lookup used for endpoints takes no source
    // row allocation, even when the range spans the entire document.
    final number = side == DiffSide.old || line.newNumber == null
        ? line.oldNumber
        : line.newNumber;
    if (number == null) return false;
    final index = bounds.layout.rowForLine(
      0,
      number,
      oldSide: side == DiffSide.old || line.newNumber == null,
    );
    return index != null && index >= bounds.start && index <= bounds.end;
  }

  void _copy() {
    final native = _nativeSelection.getSelectedContent()?.plainText;
    final text =
        native ?? (_selection == null ? null : _selectedText(_selection!));
    if (text != null) Clipboard.setData(ClipboardData(text: text));
  }
}

// The outer SelectableRegion is overridable too. A nested editor/region adds
// its own calling action to that chain; forward it, while keeping the outer
// patch's native and gutter selections on the same source-copy path.
class _PatchCopyAction extends Action<CopySelectionTextIntent> {
  _PatchCopyAction(this.copy);
  final VoidCallback copy;

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    final caller = callingAction;
    if (caller != null && caller.callingAction != null) {
      return caller.invoke(intent);
    }
    copy();
    return null;
  }
}
