import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;

import 'colors.dart';
import 'patch_painter.dart';

/// A syntax-highlighted view of code changes for the terminal.
///
/// Show a `git diff` with [PatchView.fromPatch], compare two versions of a
/// file with [PatchView.fromTexts], or pass `FileDiff`s directly. Rows are
/// laid out by syntax's `layoutDiff`, so they match `syntax_flutter`'s
/// `PatchView`: file headers with change counts, `@@` lines, old and new
/// line numbers, highlighted changed words, and collapsed unchanged lines.
///
/// Each row is one terminal line; long lines are cut, not wrapped. Arrow
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
    super.key,
  }) : _files = null,
       _patch = null,
       _texts = (oldText, newText, path, contextLines);

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
  Object? _sourceKey;
  List<syntax.FileDiff> _files = const [];
  final Set<int> _collapsed = {};
  final Set<syntax.DiffGapId> _expanded = {};
  int _selected = 0;

  int _layoutVersion = 0;
  Object? _rowsKey;
  List<syntax.DiffRow> _rows = const [];

  Object? _painterKey;
  PatchPainter? _painter;

  void _syncSource() {
    final key = (widget._files, widget._patch, widget._texts);
    if (key == _sourceKey) return;
    _sourceKey = key;
    _files = switch (key) {
      (final files?, _, _) => files,
      (_, final patch?, _) => syntax.parsePatch(patch),
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
    final key = (
      _layoutVersion,
      widget.highlighter,
      widget.theme,
      widget.language,
      widget.labels,
    );
    if (key == _painterKey && _painter != null) return _painter!;
    _painterKey = key;
    return _painter = PatchPainter(
      files: _files,
      highlighter: widget.highlighter,
      theme: widget.theme,
      language: widget.language,
      labels: widget.labels,
    );
  }

  void _activate(syntax.DiffRow row) {
    switch (row) {
      case syntax.DiffFileHeaderRow(:final file):
        setState(() {
          _collapsed.contains(file)
              ? _collapsed.remove(file)
              : _collapsed.add(file);
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
    _syncSource();
  }

  @override
  void didUpdateWidget(PatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSource();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rows = _layout();
      final painter = _painterFor();
      final width = constraints.maxWidth ?? 80;
      return ListView(
        itemCount: math.max(rows.length, 1),
        height: widget.height ?? constraints.maxHeight ?? 20,
        selectedIndex: rows.isEmpty
            ? null
            : math.min(_selected, rows.length - 1),
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        backgroundColor: noirColor(widget.theme.background),
        selectedBackgroundColor: noirColor(widget.theme.background),
        onChanged: (index) => _selected = index,
        onSelect: (index) => _activate(rows[index]),
        itemBuilder: (context, index, selected) => RichText(
          text: rows.isEmpty
              ? painter.empty(width: width)
              : painter.paint(rows[index], width: width, selected: selected),
          softWrap: false,
          maxLines: 1,
        ),
      );
    },
  );
}
