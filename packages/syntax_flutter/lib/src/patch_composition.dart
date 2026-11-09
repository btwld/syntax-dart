part of 'patch_view.dart';

extension _PatchComposition<T> on _PatchViewState<T> {
  Widget _composedRow(
    BuildContext context,
    int index,
    List<DiffRow> rows,
    PatchPalette palette,
    Highlighter highlighter,
    DiffLabels labels,
  ) {
    final row = rows[index];
    final file = _files[row.file];
    final first = index == 0 || rows[index - 1].file != row.file;
    final last = index == rows.length - 1 || rows[index + 1].file != row.file;
    final children = <Widget>[_buildRow(row, palette, highlighter, labels)];
    if (row is DiffLineRow || row is DiffPairRow) {
      final annotations = <DiffAnnotation<T>>[];
      for (final side in DiffSide.values) {
        final line = _textAt(row, side);
        final number = side == DiffSide.old ? line?.oldNumber : line?.newNumber;
        if (number != null) {
          annotations.addAll(_annotationsByLine[(file.id, side, number)] ?? []);
        }
      }
      final below = widget.rowBelowBuilder?.call(
        context,
        DiffRowContext<T>(file: file, row: row, annotations: annotations),
      );
      if (below != null) {
        children.add(
          SelectionContainer.disabled(
            child: KeyedSubtree(
              key: ValueKey(('below', _identity(row))),
              child: below,
            ),
          ),
        );
      }
      final selection = _selection;
      if (selection != null &&
          selection.fileId == file.id &&
          _rowAddresses(row, selection.activeSide, selection.active)) {
        final action = widget.selectionActionBuilder?.call(
          context,
          DiffSelectionDetails(
            file: file,
            selection: selection,
            selectedText: _selectedText(selection),
          ),
        );
        if (action != null) {
          children.add(SelectionContainer.disabled(child: action));
        }
      }
    }
    if (last) {
      final footer = widget.fileFooterBuilder?.call(
        context,
        file,
        widget.collapsed.contains(row.file),
      );
      if (footer != null) {
        children.add(
          SelectionContainer.disabled(
            child: KeyedSubtree(
              key: ValueKey(('footer', file.id)),
              child: footer,
            ),
          ),
        );
      }
    }
    return _section(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
      first: first,
      last: last,
    );
  }

  Widget _section(Widget child, {required bool first, required bool last}) {
    final decoration = widget.sectionDecoration;
    if (decoration == null) return child;
    final radius =
        decoration.borderRadius?.resolve(TextDirection.ltr) ??
        BorderRadius.zero;
    final clipped = BorderRadius.only(
      topLeft: first ? radius.topLeft : Radius.zero,
      topRight: first ? radius.topRight : Radius.zero,
      bottomLeft: last ? radius.bottomLeft : Radius.zero,
      bottomRight: last ? radius.bottomRight : Radius.zero,
    );
    final insets =
        decoration.border?.dimensions.resolve(TextDirection.ltr) ??
        EdgeInsets.zero;
    return ClipRRect(
      borderRadius: clipped,
      child: _SectionPaint(
        decoration: decoration,
        first: first,
        last: last,
        child: Padding(
          padding: EdgeInsets.only(
            left: insets.left,
            right: insets.right,
            top: first ? insets.top : 0,
            bottom: last ? insets.bottom : 0,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _sourceLine(
    int fileIndex,
    DiffLine line,
    DiffSide? side,
    PatchPalette palette,
    Highlighter highlighter,
    DiffLabels labels,
  ) {
    final file = _files[fileIndex];
    final index = (_layout as DiffLayout).rowForLine(
      fileIndex,
      side == DiffSide.old || line.newNumber == null
          ? line.oldNumber!
          : line.newNumber!,
      oldSide: side == DiffSide.old || line.newNumber == null,
    )!;
    final numberWidth = palette.gutterWidth(file);
    final coordinates = <(DiffSide, int?)>[
      if (side == null || side == DiffSide.old) (DiffSide.old, line.oldNumber),
      if (side == null || side == DiffSide.newer)
        (DiffSide.newer, line.newNumber),
    ];
    final markerSide =
        side ?? (line.newNumber == null ? DiffSide.old : DiffSide.newer);
    final markerNumber = markerSide == DiffSide.old
        ? line.oldNumber
        : line.newNumber;
    Widget gutterCell(DiffSide side, int? number, Widget child) {
      if (number == null) return child;
      final coordinate = DiffLineContext(file: file, side: side, line: number);
      return Builder(
        builder: (context) {
          _gutterCells.removeWhere((_, context) => !context.mounted);
          _gutterCells[(fileIndex, side, number)] = context;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _startDrag(coordinate, event),
            onPointerMove: _moveDrag,
            onPointerUp: (_) => _stopDrag(),
            onPointerCancel: (_) => _stopDrag(),
            child: child,
          );
        },
      );
    }

    final gutter = SelectionContainer.disabled(
      child: ColoredBox(
        color: palette.gutterBackground(line.kind),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.gutterBuilder != null)
              gutterCell(
                markerSide,
                markerNumber,
                SizedBox(
                  width: 24,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ClipRect(
                      child: widget.gutterBuilder!(
                        context,
                        DiffLineContext(
                          file: file,
                          side: markerSide,
                          line: markerNumber!,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (palette.lineNumbers)
              for (final (coordinateSide, number) in coordinates)
                gutterCell(
                  coordinateSide,
                  number,
                  SizedBox(
                    width: numberWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        number?.toString() ?? '',
                        style: palette.numberText,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ),
            gutterCell(
              markerSide,
              markerNumber,
              SizedBox(
                width: 20,
                child: Text(
                  palette.indicators == DiffIndicators.none
                      ? ' '
                      : line.kind == DiffLineKind.context
                      ? ' '
                      : palette.indicators == DiffIndicators.bars
                      ? '┃'
                      : line.kind == DiffLineKind.added
                      ? '+'
                      : '−',
                  textAlign: TextAlign.center,
                  style: palette.numberText.copyWith(
                    color: line.kind == DiffLineKind.added
                        ? palette.inserted
                        : palette.removed,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final selected = _lineSelected(file, line, side);
    return ColoredBox(
      color: selected
          ? widget.theme.selectionColor
          : palette.lineBackground(line.kind),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: line.kind == DiffLineKind.context
                  ? null
                  : labels.changedLine(line.kind, markerNumber),
              excludeSemantics: true,
              child: gutter,
            ),
            Expanded(
              child: widget.selectable
                  ? DiffSelectableCell(
                      selection: _nativeSelection,
                      cell: (row: index, side: side),
                      child: PatchCodeCell(
                        line: line,
                        spans: _spans(fileIndex, line, highlighter, palette),
                        palette: palette,
                        labels: labels,
                      ),
                    )
                  : PatchCodeCell(
                      line: line,
                      spans: _spans(fileIndex, line, highlighter, palette),
                      palette: palette,
                      labels: labels,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Own asynchronous decoration image listeners for as long as the row is mounted.
class _SectionPaint extends StatefulWidget {
  const _SectionPaint({
    required this.decoration,
    required this.first,
    required this.last,
    required this.child,
  });
  final BoxDecoration decoration;
  final bool first, last;
  final Widget child;

  @override
  State<_SectionPaint> createState() => _SectionPaintState();
}

class _SectionPaintState extends State<_SectionPaint> {
  final _repaint = _SectionRepaint();
  late _SectionPainter _background, _foreground;

  void _createPainters() {
    _background = _SectionPainter(
      widget.decoration,
      widget.first,
      widget.last,
      false,
      _repaint,
    );
    _foreground = _SectionPainter(
      widget.decoration,
      widget.first,
      widget.last,
      true,
      _repaint,
    );
  }

  @override
  void initState() {
    super.initState();
    _createPainters();
  }

  @override
  void didUpdateWidget(_SectionPaint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decoration != widget.decoration ||
        oldWidget.first != widget.first ||
        oldWidget.last != widget.last) {
      _background.dispose();
      _foreground.dispose();
      _createPainters();
    }
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _background,
    foregroundPainter: _foreground,
    child: widget.child,
  );

  @override
  void dispose() {
    _background.dispose();
    _foreground.dispose();
    _repaint.dispose();
    super.dispose();
  }
}

class _SectionRepaint extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// Paint a slice of a section, moving missing edges beyond the row's clip.
class _SectionPainter extends CustomPainter {
  _SectionPainter(
    this.decoration,
    this.first,
    this.last,
    this.foreground,
    _SectionRepaint repaint,
  ) : super(repaint: repaint) {
    final paintDecoration = foreground
        ? BoxDecoration(
            border: decoration.border,
            borderRadius: decoration.borderRadius,
          )
        : decoration.copyWith(
            border: Border.all(color: const Color(0x00000000), width: 0),
          );
    _painter = paintDecoration.createBoxPainter(repaint.changed);
  }
  late final BoxPainter _painter;

  void dispose() => _painter.dispose();
  final BoxDecoration decoration;
  final bool first, last, foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final radius =
        decoration.borderRadius?.resolve(TextDirection.ltr) ??
        BorderRadius.zero;
    final overlap =
        [
          radius.topLeft.x,
          radius.topRight.x,
          radius.bottomLeft.x,
          radius.bottomRight.x,
          radius.topLeft.y,
          radius.topRight.y,
          radius.bottomLeft.y,
          radius.bottomRight.y,
        ].fold<double>(32, math.max) *
        2;
    final top = first ? 0.0 : overlap;
    final bottom = last ? 0.0 : overlap;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _painter.paint(
      canvas,
      Offset(0, -top),
      ImageConfiguration(
        size: Size(size.width, size.height + top + bottom),
        textDirection: TextDirection.ltr,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SectionPainter oldDelegate) =>
      decoration != oldDelegate.decoration ||
      first != oldDelegate.first ||
      last != oldDelegate.last ||
      foreground != oldDelegate.foreground;
}
