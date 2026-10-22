import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;

import 'colors.dart';
import 'annotations.dart';
import 'editor.dart';
import 'patch_painter.dart';

/// A syntax-highlighted view of code changes for the terminal.
///
/// Show a `git diff` with [PatchView.fromPatch], compare two versions of a
/// file with [PatchView.fromTexts], or pass `FileDiff`s directly. Rows are
/// laid out by syntax's `layoutDiff`, so they match `syntax_flutter`'s
/// `PatchView`: file headers with change counts, `@@` lines, old and new
/// line numbers, highlighted changed words, and collapsed unchanged lines.
///
/// Each row is one terminal line; long lines end in `…`, not wrapped. Arrow
/// keys move the selection, and Enter on a file header collapses or
/// expands the file, or on collapsed lines shows them.
class PatchView extends StatefulWidget {
  /// Shows [files] as they are. The view resets what is collapsed or
  /// expanded when it gets a different list, compared by identity.
  const PatchView({
    required List<syntax.FileDiff> files,
    required this.highlighter,
    required this.theme,
    this.language,
    this.mode = syntax.DiffMode.unified,
    this.labels = const syntax.DiffLabels(),
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.controller,
    this.inlineDiffMode = syntax.InlineDiffMode.mergedWords,
    this.showReviewActions = false,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.wrap = false,
    this.onCopy = copyTerminalSource,
    this.onEditComplete,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.annotationRowBuilder,
    this.annotationRowCount,
    this.onLine,
    this.onToken,
    super.key,
  }) : _files = files,
       _patch = null,
       _texts = null;

  /// Shows a unified diff, such as the output of `git diff`.
  const PatchView.fromPatch(
    String patch, {
    required this.highlighter,
    required this.theme,
    this.language,
    this.mode = syntax.DiffMode.unified,
    this.labels = const syntax.DiffLabels(),
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.controller,
    this.inlineDiffMode = syntax.InlineDiffMode.mergedWords,
    this.showReviewActions = false,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.wrap = false,
    this.onCopy = copyTerminalSource,
    this.onEditComplete,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.annotationRowBuilder,
    this.annotationRowCount,
    this.onLine,
    this.onToken,
    super.key,
  }) : _files = null,
       _patch = patch,
       _texts = null;

  /// Shows the changes from [oldText] to [newText], with [contextLines]
  /// unchanged lines around each change. [path] names the file and, unless
  /// [language] is set, picks the language.
  const PatchView.fromTexts({
    required String oldText,
    required String newText,
    required this.highlighter,
    required this.theme,
    String path = '',
    int contextLines = 3,
    this.language,
    this.mode = syntax.DiffMode.unified,
    this.labels = const syntax.DiffLabels(),
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.controller,
    this.inlineDiffMode = syntax.InlineDiffMode.mergedWords,
    this.showReviewActions = false,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.wrap = false,
    this.onCopy = copyTerminalSource,
    this.onEditComplete,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.annotationRowBuilder,
    this.annotationRowCount,
    this.onLine,
    this.onToken,
    super.key,
  }) : _files = null,
       _patch = null,
       _texts = (oldText, newText, path, contextLines);

  /// Uses persistent review state with loading, expansion and editing commands.
  const PatchView.controlled({
    super.key,
    required syntax.PatchController this.controller,
    required this.highlighter,
    required this.theme,
    this.language,
    this.mode = syntax.DiffMode.unified,
    this.labels = const syntax.DiffLabels(),
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.inlineDiffMode = syntax.InlineDiffMode.mergedWords,
    this.showReviewActions = false,
    this.showBackgrounds = true,
    this.showChangeIndicators = true,
    this.indicators = syntax.DiffIndicators.classic,
    this.showLineNumbers = true,
    this.hunkSeparatorStyle = syntax.HunkSeparatorStyle.lineInfo,
    this.stickyHeaders = false,
    this.wrap = false,
    this.onCopy = copyTerminalSource,
    this.onEditComplete,
    this.headerBuilder,
    this.hunkBuilder,
    this.annotationBuilder,
    this.annotationRowBuilder,
    this.annotationRowCount,
    this.onLine,
    this.onToken,
  }) : _files = null,
       _patch = null,
       _texts = null;

  /// Logical review state, including stable identity and selection.
  final syntax.PatchController? controller;

  /// Inline comparison algorithm.
  final syntax.InlineDiffMode inlineDiffMode;

  /// Shows keyboard-accessible review controls for the current row.
  final bool showReviewActions;

  /// Paints changed-line backgrounds.
  final bool showBackgrounds;

  /// Displays addition and deletion markers.
  final bool showChangeIndicators;

  /// Marker style independent of line backgrounds.
  final syntax.DiffIndicators indicators;

  /// Shows source numbers in the terminal gutters.
  final bool showLineNumbers;

  /// Presentation of context gaps and section metadata.
  final syntax.HunkSeparatorStyle hunkSeparatorStyle;

  /// Displays the selected file's header above the viewport.
  final bool stickyHeaders;

  /// Wraps source by terminal cells instead of clipping long lines.
  final bool wrap;

  /// Source-only clipboard callback.
  final void Function(String) onCopy;

  /// Application decision before an edited diff replaces its original.
  final Future<bool> Function(syntax.FileDiff)? onEditComplete;

  /// Custom fixed-height file header.
  final Widget Function(BuildContext, syntax.FileDiff, bool)? headerBuilder;

  /// Custom fixed-height hunk separator.
  final Widget Function(BuildContext, syntax.FileDiff, syntax.DiffHunk)?
  hunkBuilder;

  /// Custom annotation row beneath the selected source line.
  final Widget Function(BuildContext, syntax.ReviewAnnotation<Object?>)?
  annotationBuilder;

  /// Builds each visible row of a variable-height review annotation.
  final AnnotationRowBuilder<syntax.ReviewAnnotation<Object?>>?
  annotationRowBuilder;

  /// Measures custom rows; default annotations wrap by terminal cell width.
  final AnnotationRowCount<syntax.ReviewAnnotation<Object?>>?
  annotationRowCount;

  /// Reports source-line activation.
  final void Function(syntax.FileDiff, syntax.DiffSide, int)? onLine;

  /// Reports Alt+Enter token activation for the selected line.
  final void Function(syntax.FileDiff, syntax.DiffLine, syntax.DiffSegment)?
  onToken;

  final List<syntax.FileDiff>? _files;
  final String? _patch;
  final (String, String, String, int)? _texts;

  /// Provides the grammars.
  final syntax.Highlighter highlighter;

  /// Colors for code, line backgrounds and changed words.
  final syntax.SyntaxTheme theme;

  /// The language of every file. Defaults to guessing from each path.
  final String? language;

  /// Whether changes are shown in one column or side by side.
  final syntax.DiffMode mode;

  /// The words the view shows. Extend `DiffLabels` to translate them.
  final syntax.DiffLabels labels;

  /// Rows of terminal height. Defaults to the height available.
  final int? height;

  /// Controls keyboard focus. One is created if null.
  final FocusNode? focusNode;

  /// Whether the view takes focus when it first appears.
  final bool autofocus;

  @override
  State<PatchView> createState() => _PatchViewState();
}

class _PatchViewState extends State<PatchView> {
  String? _editing;
  syntax.EditorController? _editSession;
  syntax.PatchController? _editOwner;
  int _scrollRequest = -1;

  void _closeEdit() {
    if (_editing != null) _editOwner?.releaseEdit(_editing!);
    _editing = null;
    _editSession = null;
    _editOwner = null;
  }

  void _openEdit(String id) {
    _closeEdit();
    final controller = widget.controller!;
    _editSession = controller.beginEdit(id);
    _editOwner = controller;
    setState(() => _editing = id);
  }

  syntax.DiffSide _side = syntax.DiffSide.newer;
  int _horizontal = 0;
  syntax.RowHeightIndex? _heights;
  Object? _heightKey;
  Object? _sourceKey;
  List<syntax.FileDiff> _files = const [];
  final Set<int> _collapsed = {};
  final Set<syntax.DiffGapId> _expanded = {};
  int _selected = 0, _selectedSubrow = 0;

  /// Bumped when the files, collapsed files or expanded gaps change.
  int _layoutVersion = 0;
  Object? _rowsKey;
  List<syntax.DiffRow> _rows = const [];

  Object? _highlightsKey;
  syntax.DiffHighlightCache? _highlights;
  Object? _painterKey;
  PatchPainter? _painter;

  void _changed() {
    if (!mounted) return;
    setState(() {
      _files = widget.controller!.files;
      if (_editing != null &&
          (_editSession?.isDisposed == true ||
              !_files.any((file) => file.id == _editing))) {
        _closeEdit();
      }
      _layoutVersion++;
    });
    final target = widget.controller?.scrollTargetRow;
    if (target != null && widget.controller!.scrollRequest != _scrollRequest) {
      _scrollRequest = widget.controller!.scrollRequest;
      _selected = target;
      _selectedSubrow = 0;
    }
  }

  void _syncSource() {
    if (widget.controller case final controller?) {
      _files = controller.files;
      _layoutVersion++;
      return;
    }
    final key = (widget._files, widget._patch, widget._texts);
    if (key == _sourceKey) return;
    _sourceKey = key;
    _files = switch (key) {
      (final files?, _, _) => files,
      (_, final patch?, _) =>
        syntax
            .parsePatchDocuments(patch)
            .expand((document) => document.files)
            .toList(),
      (_, _, (final before, final after, final path, final context)?) => [
        syntax.diffTexts(before, after, path: path, contextLines: context),
      ],
      _ => const [],
    };
    _collapsed.clear();
    _expanded.clear();
    _selected = 0;
    _layoutVersion++;
  }

  List<syntax.DiffRow> _layout() {
    if (widget.controller case final controller?) return controller.layout;
    final key = (_layoutVersion, widget.mode);
    if (key == _rowsKey) return _rows;
    _rowsKey = key;
    return _rows = syntax.layoutDiff(
      _files,
      mode: widget.mode,
      collapsed: _collapsed,
      expanded: _expanded,
    );
  }

  PatchPainter _painterFor() {
    // Keyed on the files, not the layout, so collapsing a file or showing
    // lines keeps what was already highlighted. Labels only renew the
    // painter, not the highlighting.
    final highlightsKey = (
      _files,
      widget.highlighter,
      widget.language,
      widget.inlineDiffMode,
    );
    if (highlightsKey != _highlightsKey || _highlights == null) {
      _highlightsKey = highlightsKey;
      _highlights = syntax.DiffHighlightCache(
        highlighter: widget.highlighter,
        theme: widget.theme,
        language: widget.language,
        inlineDiffMode: widget.inlineDiffMode,
      );
    }
    _highlights!.theme = widget.theme;
    final painterKey = (
      _highlights,
      widget.theme,
      widget.labels,
      widget.showBackgrounds,
      widget.showChangeIndicators,
      widget.indicators,
      widget.showLineNumbers,
      widget.hunkSeparatorStyle,
    );
    if (painterKey != _painterKey || _painter == null) {
      _painterKey = painterKey;
      _painter = PatchPainter(
        files: _files,
        highlights: _highlights!,
        labels: widget.labels,
        showBackgrounds: widget.showBackgrounds,
        showChangeIndicators: widget.showChangeIndicators,
        indicators: widget.indicators,
        showLineNumbers: widget.showLineNumbers,
        hunkSeparatorStyle: widget.hunkSeparatorStyle,
      );
    }
    return _painter!;
  }

  void _activate(syntax.DiffRow row) {
    if (widget.controller case final controller?) {
      switch (row) {
        case syntax.DiffFileHeaderRow(:final file):
          controller.toggleFile(_files[file].id);
        case syntax.DiffGapRow(:final id):
          controller.expand(id);
        case syntax.DiffHunkHeaderRow(:final hunk)
            when controller.foldableHunks:
          controller.toggleHunk(
            _files[row.file].id,
            _files[row.file].hunks.indexOf(hunk),
          );
        default:
          _selectLine(row);
      }
      return;
    }
    switch (row) {
      case syntax.DiffFileHeaderRow(:final file):
        setState(() {
          if (!_collapsed.remove(file)) _collapsed.add(file);
          _layoutVersion++;
        });
      case syntax.DiffGapRow(:final id):
        setState(() {
          _expanded.add(id);
          _layoutVersion++;
        });
      default:
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_changed);
    _syncSource();
  }

  @override
  void didUpdateWidget(PatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _closeEdit();
      _scrollRequest = -1;
      oldWidget.controller?.removeListener(_changed);
      widget.controller?.addListener(_changed);
    }
    _syncSource();
  }

  syntax.DiffLine? _line(syntax.DiffRow row) => switch (row) {
    syntax.DiffLineRow(:final line) => line,
    syntax.DiffPairRow(:final left, :final right) =>
      _side == syntax.DiffSide.old ? left ?? right : right ?? left,
    _ => null,
  };
  void _selectLine(syntax.DiffRow row, {bool extend = false}) {
    final line = _line(row);
    if (line == null) return;
    final side = line.kind == syntax.DiffLineKind.removed
        ? syntax.DiffSide.old
        : line.kind == syntax.DiffLineKind.added
        ? syntax.DiffSide.newer
        : _side;
    final number = (side == syntax.DiffSide.old
        ? line.oldNumber
        : line.newNumber)!;
    final file = _files[row.file];
    final old = widget.controller?.selection;
    widget.controller?.select(
      syntax.DiffSelection(
        file.id,
        extend && old?.fileId == file.id ? old!.side : side,
        extend && old?.fileId == file.id ? old!.anchor : number,
        number,
        activeSide: side,
      ),
    );
    widget.onLine?.call(file, side, number);
  }

  int _codeWidth(syntax.DiffRow row, int width) {
    final digits = widget.showLineNumbers
        ? '${_files[row.file].maxLineNumber}'.length
        : -1;
    return math.max(
      1,
      row is syntax.DiffPairRow
          ? (width - 2) ~/ 2 - digits - 3
          : width - digits * 2 - 5,
    );
  }

  int _visualRows(syntax.DiffRow row, int width) {
    if (!widget.wrap) return 1;
    final lines = switch (row) {
      syntax.DiffLineRow(:final line) => [line],
      syntax.DiffPairRow(:final left, :final right) => [?left, ?right],
      _ => <syntax.DiffLine>[],
    };
    var count = 1;
    for (final line in lines) {
      count = math.max(
        count,
        (terminalStringWidth(line.text.replaceAll('\t', '    ')) /
                _codeWidth(row, width))
            .ceil(),
      );
    }
    return count;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_editing case final id?) {
        final controller = _editOwner!;
        return SyntaxEditor(
          controller: _editSession!,
          highlighter: widget.highlighter,
          theme: widget.theme,
          height: widget.height,
          autofocus: true,
          onDismiss: () {
            setState(_closeEdit);
          },
          onComplete: (_) async {
            final accepted = await controller.completeEdit(
              id,
              accept: widget.onEditComplete,
            );
            if (mounted &&
                identical(_editOwner, controller) &&
                _editing == id) {
              setState(_closeEdit);
            }
            return accepted;
          },
        );
      }
      final rows = _layout();
      final painter = _painterFor();
      final width = constraints.maxWidth ?? 80;
      final key = (rows, width, widget.wrap);
      if (_heightKey != key) {
        _heightKey = key;
        _heights = syntax.RowHeightIndex(rows.length, estimatedHeight: 1);
        if (widget.wrap) {
          for (var i = 0; i < rows.length; i++) {
            _heights!.measure(i, _visualRows(rows[i], width).toDouble());
          }
        }
      }
      final heights = _heights!;
      _selected = _selected.clamp(0, math.max(0, rows.length - 1));
      final selected = rows.isEmpty ? null : rows[_selected];
      final file = selected == null ? null : _files[selected.file];
      final annotations = selected == null
          ? const <syntax.ReviewAnnotation<Object?>>[]
          : (widget.controller?.annotations ??
                    const <syntax.ReviewAnnotation<Object?>>[])
                .where((a) {
                  final line = _line(selected);
                  return a.fileId == file!.id &&
                      (a.side == syntax.DiffSide.old
                              ? line?.oldNumber
                              : line?.newNumber) ==
                          a.line;
                })
                .toList();
      final annotationOffsets = <int>[0];
      for (final annotation in annotations) {
        annotationOffsets.add(
          annotationOffsets.last +
              annotationHeight(
                annotation,
                annotation.data,
                width,
                widget.annotationRowCount,
                widget.annotationBuilder != null,
              ),
        );
      }
      final totalHeight = widget.height ?? constraints.maxHeight ?? 20;
      final annotationViewport = math.min(
        annotationOffsets.last,
        math.max(1, totalHeight ~/ 2),
      );
      final controls =
          widget.showReviewActions && widget.controller != null && file != null;
      final height = math.max(
        1,
        totalHeight -
            (controls ? 2 : 0) -
            annotationViewport -
            (widget.stickyHeaders && file != null ? 1 : 0),
      );
      Widget view = ListView(
        itemCount: math.max(heights.offsetFor(rows.length).toInt(), 1),
        height: height,
        selectedIndex: rows.isEmpty
            ? null
            : heights.offsetFor(_selected).toInt() +
                  _selectedSubrow.clamp(
                    0,
                    _visualRows(rows[_selected], width) - 1,
                  ),
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        backgroundColor: noirColor(widget.theme.background),
        selectedBackgroundColor: noirColor(widget.theme.background),
        onChanged: (visual) {
          setState(() {
            _selected = heights.rowAt(visual.toDouble());
            _selectedSubrow = visual - heights.offsetFor(_selected).toInt();
          });
        },
        onSelect: (visual) {
          if (rows.isNotEmpty) {
            _activate(rows[heights.rowAt(visual.toDouble())]);
          }
        },
        itemBuilder: (context, visual, active) {
          if (rows.isEmpty) {
            return RichText(
              text: painter.empty(width: width),
              softWrap: false,
              maxLines: 1,
            );
          }
          final index = heights.rowAt(visual.toDouble());
          final row = rows[index];
          if (row is syntax.DiffFileHeaderRow && widget.headerBuilder != null) {
            return widget.headerBuilder!(
              context,
              _files[row.file],
              row.collapsed,
            );
          }
          if (row is syntax.DiffHunkHeaderRow && widget.hunkBuilder != null) {
            return widget.hunkBuilder!(context, _files[row.file], row.hunk);
          }
          final offset = widget.wrap
              ? (visual - heights.offsetFor(index).toInt()) *
                    _codeWidth(row, width)
              : _horizontal;
          return RichText(
            text: painter.paint(
              row,
              width: width,
              selected:
                  active ||
                  [
                    if (row case syntax.DiffLineRow(:final line)) line,
                    if (row case syntax.DiffPairRow(
                      :final left,
                      :final right,
                    )) ...[
                      ?left,
                      ?right,
                    ],
                  ].any(
                    (line) =>
                        (line.oldNumber != null &&
                            widget.controller?.isLineSelected(
                                  _files[row.file].id,
                                  syntax.DiffSide.old,
                                  line.oldNumber!,
                                ) ==
                                true) ||
                        (line.newNumber != null &&
                            widget.controller?.isLineSelected(
                                  _files[row.file].id,
                                  syntax.DiffSide.newer,
                                  line.newNumber!,
                                ) ==
                                true),
                  ),
              codeOffset: offset,
              ellipsis: !widget.wrap,
            ),
            softWrap: false,
            maxLines: 1,
          );
        },
      );
      view = Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          if (!event.isPress || selected == null) return KeyEventResult.ignored;
          if (event.isControlPressed &&
              event.logicalKey == LogicalKeyboardKey.keyC) {
            final controller = widget.controller;
            if (controller != null) {
              if (controller.selection == null) _selectLine(selected);
              widget.onCopy(controller.selectedText());
            }
            return KeyEventResult.handled;
          }
          if (event.isShiftPressed &&
              (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown)) {
            final next =
                (_selected +
                        (event.logicalKey == LogicalKeyboardKey.arrowUp
                            ? -1
                            : 1))
                    .clamp(0, rows.length - 1);
            if (widget.controller?.selection == null) _selectLine(selected);
            setState(() => _selected = next);
            _selectLine(rows[next], extend: true);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            setState(() {
              if (event.isAltPressed) {
                _horizontal = math.max(
                  0,
                  _horizontal +
                      (event.logicalKey == LogicalKeyboardKey.arrowRight
                          ? 8
                          : -8),
                );
              } else {
                _side = event.logicalKey == LogicalKeyboardKey.arrowLeft
                    ? syntax.DiffSide.old
                    : syntax.DiffSide.newer;
              }
            });
            return KeyEventResult.handled;
          }
          if (event.isAltPressed &&
              event.logicalKey == LogicalKeyboardKey.enter) {
            final line = _line(selected);
            if (line != null) {
              final segments = _highlights!.segmentsFor(file!, line);
              if (segments.isNotEmpty) {
                widget.onToken?.call(file, line, segments.first);
              }
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: view,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.stickyHeaders && file != null)
            widget.headerBuilder?.call(
                  context,
                  file,
                  widget.controller?.isCollapsed(file.id) ?? false,
                ) ??
                Text(file.path),
          view,
          if (annotations.isNotEmpty)
            ListView(
              key: ValueKey((
                'annotations',
                file?.id,
                _line(selected!)?.oldNumber,
                _line(selected)?.newNumber,
              )),
              height: annotationViewport,
              itemCount: annotationOffsets.last,
              itemBuilder: (context, row, active) {
                final index =
                    annotationOffsets.indexWhere((offset) => offset > row) - 1;
                final annotation = annotations[index];
                return annotationRow(
                  context,
                  annotation,
                  annotation.data,
                  row - annotationOffsets[index],
                  width,
                  widget.annotationRowBuilder,
                  widget.annotationBuilder,
                );
              },
            ),
          if (controls) ...[
            Text(
              widget.controller!.loadErrors[file.id]?.toString() ??
                  'Shift+↑↓ Select • Ctrl+C Copy • ←→ Side • Alt+←→ Scroll',
              maxLines: 1,
            ),
            Row(
              children: [
                if (file.isPartial && widget.controller!.contentsLoader != null)
                  Button(
                    label: widget.controller!.isLoading(file.id)
                        ? 'Loading…'
                        : 'Load contents',
                    onPressed: () => widget.controller!.loadContents(file.id),
                  ),
                if (!file.isPartial)
                  Button(
                    label: 'Expand all',
                    onPressed: () => widget.controller!.expandAll(file.id),
                  ),
                if (selected is syntax.DiffGapRow) ...[
                  Button(
                    label: 'Above',
                    onPressed: () => widget.controller!.expand(
                      selected.id,
                      direction: syntax.ExpansionDirection.before,
                    ),
                  ),
                  Button(
                    label: 'Below',
                    onPressed: () => widget.controller!.expand(
                      selected.id,
                      direction: syntax.ExpansionDirection.after,
                    ),
                  ),
                ],
                if (!file.isPartial && selected is syntax.DiffHunkHeaderRow)
                  for (final (label, resolution) in [
                    ('Accept', syntax.ChangeResolution.newer),
                    ('Reject', syntax.ChangeResolution.old),
                    ('Combine', syntax.ChangeResolution.both),
                  ])
                    Button(
                      label: label,
                      onPressed: () => widget.controller!.resolve(
                        file.id,
                        file.hunks.indexOf(selected.hunk),
                        resolution,
                      ),
                    ),
                if (!file.isPartial &&
                    selected != null &&
                    _line(selected) != null)
                  for (final (label, choice) in [
                    ('Accept change', syntax.ChangeResolution.newer),
                    ('Reject change', syntax.ChangeResolution.old),
                    ('Combine change', syntax.ChangeResolution.both),
                  ])
                    if (widget.controller!.changeAt(
                          file.id,
                          (_side == syntax.DiffSide.old
                                  ? _line(selected)!.oldNumber
                                  : _line(selected)!.newNumber) ??
                              0,
                          side: _side,
                        )
                        case final change?)
                      Button(
                        label: label,
                        onPressed: () => widget.controller!.resolve(
                          file.id,
                          change.hunk,
                          choice,
                          changeIndex: change.change,
                        ),
                      ),
                if (!file.isPartial && widget.onEditComplete != null)
                  Button(label: 'Edit', onPressed: () => _openEdit(file.id)),
              ],
            ),
          ],
        ],
      );
    },
  );
  @override
  void dispose() {
    _closeEdit();
    widget.controller?.removeListener(_changed);
    super.dispose();
  }
}
