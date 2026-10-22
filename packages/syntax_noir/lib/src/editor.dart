import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show InputPriority, InputSubscription;
import 'package:syntax/syntax.dart' as syntax;

import 'colors.dart';
import 'annotations.dart';

/// Writes source text through the terminal's OSC 52 clipboard facility.
/// Applications can replace this with their renderer's clipboard callback.
void copyTerminalSource(String text) {
  if (text.isNotEmpty && stdout.hasTerminal) {
    stdout.write('\x1b]52;c;${base64Encode(utf8.encode(text))}\x07');
  }
}

/// Terminal text-input binding for a shared editing session.
class DocumentTextEditingController extends TextEditingController {
  /// Disposing this adapter leaves [editor] and its history intact.
  DocumentTextEditingController(this.editor)
    : super(text: editor.document.text) {
    editor.addListener(_fromEditor);
    addListener(_fromInput);
    _fromEditor();
  }

  /// Shared document, selection and history.
  final syntax.EditorController editor;
  bool _updating = false;
  void _fromEditor() {
    if (_updating) return;
    _updating = true;
    try {
      final s = editor.selections.first;
      value = TextEditingValue(
        text: editor.document.text,
        selection: TextSelection(baseOffset: s.anchor, extentOffset: s.active),
      );
    } finally {
      _updating = false;
    }
  }

  void _fromInput() {
    if (_updating) return;
    _updating = true;
    try {
      final source = editor.document.text;
      int boundary(int offset, bool forward) {
        final map = TextIndexMap(source);
        return map.graphemeToUtf16(
          map.utf16ToGrapheme(offset) + (forward ? 1 : -1),
        );
      }

      editor.updateFromInput(
        text,
        selectionWithinText
            ? syntax.DocumentSelection(
                selection.baseOffset,
                selection.extentOffset,
              )
            : null,
        deletionBoundary: boundary,
      );
      final next = editor.selections.first;
      if (text != editor.document.text ||
          (selectionWithinText &&
              (selection.baseOffset != next.anchor ||
                  selection.extentOffset != next.active))) {
        value = TextEditingValue(
          text: editor.document.text,
          selection: TextSelection(
            baseOffset: next.anchor,
            extentOffset: next.active,
          ),
        );
      }
    } finally {
      _updating = false;
    }
  }

  @override
  void dispose() {
    editor.removeListener(_fromEditor);
    removeListener(_fromInput);
    super.dispose();
  }
}

class _EditorIntent extends Intent {
  const _EditorIntent(this.command);
  final syntax.EditorCommand command;
}

/// Highlighted terminal editor using native input intents and UTF-16 selections.
///
/// Ctrl+F opens search; Ctrl+Z/Ctrl+Y undo and redo; Ctrl+Enter completes;
/// Alt+Up/Down moves lines; Shift+arrows extends selections; Ctrl+Space accepts
/// a proposal. Commands and drafts remain in [controller] after unmounting.
class SyntaxEditor extends StatefulWidget {
  /// Creates an editable or read-only source viewport.
  const SyntaxEditor({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.height,
    this.wrap = false,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.showHeader = true,
    this.onComplete,
    this.onDismiss,
    this.onCopy = copyTerminalSource,
    this.shortcuts = const {},
    this.annotationBuilder,
    this.annotationRowBuilder,
    this.annotationRowCount,
    this.selectionActionsBuilder,
    this.onLine,
    this.onToken,
    this.headerBuilder,
    this.executor,
    this.lineBackgroundBuilder,
  });

  /// Optional keyboard-accessible actions for the current selection.
  final Widget Function(BuildContext, syntax.EditorController)?
  selectionActionsBuilder;

  /// Shared document, selections, proposals and commands.
  final syntax.EditorController controller;

  /// Registered grammars.
  final syntax.Highlighter highlighter;

  /// Current colors.
  final syntax.SyntaxTheme theme;

  /// Optional shared executor for viewport highlighting in the background.
  final syntax.HighlightExecutor? executor;

  /// Optional ARGB background beneath a zero-based source line and its gutter.
  final int? Function(int line)? lineBackgroundBuilder;

  /// Viewport height in terminal rows, including controls.
  final int? height;

  /// Wraps lines by terminal cell width.
  final bool wrap;

  /// Allows navigation and copying while rejecting edits.
  final bool readOnly;

  /// Requests initial keyboard focus.
  final bool autofocus;

  /// Optional caller-owned focus node.
  final FocusNode? focusNode;

  /// Displays the fixed file header and command hints.
  final bool showHeader;

  /// Application accepts or rejects the completed draft.
  final Future<bool> Function(syntax.SourceFile)? onComplete;

  /// Dismisses the surface, leaving session ownership with the caller.
  final VoidCallback? onDismiss;

  /// Explicit copy handler. Defaults to OSC 52 terminal copying.
  final void Function(String) onCopy;

  /// Application bindings override default editing commands.
  final Map<ShortcutActivator, syntax.EditorCommand> shortcuts;

  /// Legacy single-row annotation presentation. Default text wraps by cell width.
  final Widget Function(BuildContext, syntax.LineAnnotation<Object?>)?
  annotationBuilder;

  /// Builds each visible row of a variable-height annotation.
  final AnnotationRowBuilder<syntax.LineAnnotation<Object?>>?
  annotationRowBuilder;

  /// Measures custom annotation rows; defaults to wrapped text height.
  final AnnotationRowCount<syntax.LineAnnotation<Object?>>? annotationRowCount;

  /// Reports keyboard and pointer source-line navigation.
  final void Function(int)? onLine;

  /// Reports token activation at the current caret with Alt+Enter.
  final void Function(int, syntax.ThemedToken)? onToken;

  /// Custom fixed file header.
  final Widget Function(BuildContext, syntax.SourceFile)? headerBuilder;
  @override
  State<SyntaxEditor> createState() => _SyntaxEditorState();
}

class _SyntaxEditorState extends State<SyntaxEditor> {
  late DocumentTextEditingController _input;
  late FocusNode _focus;
  syntax.LiveHighlighter? _highlight;
  Object? _grammarKey;
  void _syncGrammar() {
    final name =
        editor.file.language ??
        widget.highlighter.languageForPath(editor.file.path)?.name;
    final key = (
      widget.highlighter,
      widget.highlighter.revision,
      doc,
      name,
      widget.executor,
    );
    if (_grammarKey == key) return;
    _grammarKey = key;
    _requestedWindow = null;
    _highlight?.dispose();
    _highlight =
        widget.executor != null ||
            name == null ||
            widget.highlighter.language(name) == null
        ? null
        : (syntax.LiveHighlighter(doc, widget.highlighter.grammar(name))
            ..pause());
  }

  syntax.PresentationController? _presentation;
  (int, int)? _requestedWindow;
  void _presentationChanged() {
    if (mounted) setState(() {});
  }

  InputSubscription? _paste;
  syntax.RowHeightIndex? _rows;
  Object? _layoutKey;
  int? _matchingBracket;
  syntax.DocumentRange? _pendingReveal;
  int _revealRequest = -1;
  syntax.DocumentSelection? _lastSelection;
  int _top = 0, _horizontal = 0, _bodyHeight = 10, _width = 80;
  bool _finding = false, _saving = false;
  final _query = TextEditingController(),
      _replacement = TextEditingController();
  String _message = '';
  syntax.EditorController get editor => widget.controller;
  syntax.TextDocument get doc => editor.document;
  void _attach() {
    _layoutKey = null;
    _rows = null;
    _revealRequest = -1;
    _pendingReveal = null;
    _lastSelection = editor.selections.first;
    if (widget.executor case final executor?) {
      _presentation = syntax.PresentationController(
        editor: editor,
        highlighter: widget.highlighter,
        theme: widget.theme,
        executor: executor,
      )..addListener(_presentationChanged);
    }
    _input = DocumentTextEditingController(editor);
    _focus = widget.focusNode ?? FocusNode();
    _top = editor.verticalOffset.toInt();
    _horizontal = editor.horizontalOffset.toInt();
    _grammarKey = null;
    _syncGrammar();
    editor.addListener(_changed);
    // Noir 0.0.4 exposes paste subscriptions only through its tree owner.
    // Keep this compatibility bridge localized until a public input scope exists.
    // ignore: invalid_use_of_internal_member
    _paste = context.owner.inputManager.onPaste((event) {
      if (!_focus.hasFocus || event.isConsumed || widget.readOnly) return;
      editor.insertText(event.text, autoSurround: false);
      event.consume();
    }, priority: InputPriority.focus);
    _changed();
  }

  void _detach(syntax.EditorController controller, FocusNode? external) {
    controller.removeListener(_changed);
    _input.dispose();
    _highlight?.dispose();
    _highlight = null;
    _presentation?.dispose();
    _presentation = null;
    _requestedWindow = null;
    _paste?.cancel();
    if (external == null) _focus.dispose();
  }

  void _changed() {
    if (_revealRequest != editor.revealRequest && editor.revealTarget != null) {
      _revealRequest = editor.revealRequest;
      _pendingReveal = editor.revealTarget;
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(SyntaxEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != editor ||
        oldWidget.highlighter != widget.highlighter ||
        oldWidget.focusNode != widget.focusNode ||
        oldWidget.executor != widget.executor) {
      _detach(oldWidget.controller, oldWidget.focusNode);
      _attach();
    } else {
      _presentation?.theme = widget.theme;
    }
  }

  List<syntax.LineAnnotation<Object?>> _annotations(int line) {
    final start = doc.lineStart(line), end = start + doc.lineText(line).length;
    return editor.annotations
        .where((a) => a.start >= start && a.start <= end)
        .toList();
  }

  void _layout(int width) {
    final key = (
      doc,
      doc.revision,
      width,
      widget.wrap,
      editor.annotations,
      widget.annotationBuilder,
      widget.annotationRowCount,
      widget.annotationRowBuilder,
    );
    if (_layoutKey == key) return;
    final anchor = _rows?.rowAt(_top.toDouble());
    final within = anchor == null ? 0 : _top - _rows!.offsetFor(anchor).toInt();
    _layoutKey = key;
    _width = math.max(1, width);
    _rows = syntax.RowHeightIndex(doc.lineCount, estimatedHeight: 1);
    if (widget.wrap || editor.annotations.isNotEmpty) {
      for (var line = 0; line < doc.lineCount; line++) {
        final count = widget.wrap
            ? math.max(
                1,
                ((terminalStringWidth(_safe(doc.lineText(line))) + 1) / _width)
                    .ceil(),
              )
            : 1;
        final notes = _annotations(line).fold<int>(
          0,
          (total, a) =>
              total +
              annotationHeight(
                a,
                a.data,
                _width + _gutter,
                widget.annotationRowCount,
                widget.annotationBuilder != null,
              ),
        );
        _rows!.measure(line, (count + notes).toDouble());
      }
    }
    if (anchor != null) {
      final line = anchor.clamp(0, doc.lineCount - 1);
      final height = _rows!.offsetFor(line + 1) - _rows!.offsetFor(line);
      _top =
          _rows!.offsetFor(line).toInt() + within.clamp(0, height.toInt() - 1);
    }
  }

  int get _gutter => doc.lineCount.toString().length + 2;
  void _ensureCaret() {
    final pos = doc.positionAt(editor.selections.first.active);
    final cell = terminalStringWidth(
      _safe(doc.lineText(pos.line).substring(0, pos.character)),
    );
    final row =
        _rows!.offsetFor(pos.line).toInt() + (widget.wrap ? cell ~/ _width : 0);
    if (row < _top) _top = row;
    if (row >= _top + _bodyHeight) _top = row - _bodyHeight + 1;
    if (!widget.wrap) {
      if (cell < _horizontal) _horizontal = cell;
      if (cell >= _horizontal + _width) _horizontal = cell - _width + 1;
    }
    _top = _top.clamp(
      0,
      math.max(0, _rows!.offsetFor(doc.lineCount).toInt() - _bodyHeight),
    );
    editor.verticalOffset = _top.toDouble();
    editor.horizontalOffset = _horizontal.toDouble();
  }

  String _safe(String text) => text
      .replaceAll('\t', ' ' * editor.tabSize)
      .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '�');
  Widget _paint(int row) {
    final line = _rows!.rowAt(row.toDouble());
    final subrow = row - _rows!.offsetFor(line).toInt();
    final codeRows = widget.wrap
        ? math.max(
            1,
            ((terminalStringWidth(_safe(doc.lineText(line))) + 1) / _width)
                .ceil(),
          )
        : 1;
    if (subrow >= codeRows) {
      var row = subrow - codeRows;
      for (final annotation in _annotations(line)) {
        final height = annotationHeight(
          annotation,
          annotation.data,
          _width + _gutter,
          widget.annotationRowCount,
          widget.annotationBuilder != null,
        );
        if (row < height) {
          return annotationRow(
            context,
            annotation,
            annotation.data,
            row,
            _width + _gutter,
            widget.annotationRowBuilder,
            widget.annotationBuilder,
          );
        }
        row -= height;
      }
      return const Text('');
    }
    _highlight?.flush(endLine: line + 1);
    final tokens =
        _presentation?.line(line) ?? _highlight?.themedLine(line, widget.theme);
    final text = doc.lineText(line);
    final lineBackground = widget.lineBackgroundBuilder?.call(line);
    final background = lineBackground == null
        ? widget.theme.background
        : syntax.alphaBlend(lineBackground, widget.theme.background);
    final base = TextStyle(
      color: noirColor(widget.theme.foreground),
      backgroundColor: noirColor(background),
    );
    final spans = <InlineSpan>[
      TextSpan(
        text: subrow == 0
            ? '${'${line + 1}'.padLeft(_gutter - 1)} '
            : ' ' * _gutter,
        style: base.copyWith(
          color: noirColor(widget.theme.lineNumberForeground),
        ),
      ),
    ];
    final map = TextIndexMap(text);
    var tokenIndex = 0, cell = 0, painted = 0;
    final from = widget.wrap ? subrow * _width : _horizontal;
    final startOffset = doc.lineStart(line);
    for (var i = 0; i <= map.graphemeCount; i++) {
      final a = map.graphemeToUtf16(i);
      final b = map.graphemeToUtf16(i + 1);
      final grapheme = i == map.graphemeCount
          ? ' '
          : _safe(text.substring(a, b));
      final cells = terminalStringWidth(grapheme);
      if (cell + cells > from && cell < from + _width) {
        while (tokens != null &&
            tokenIndex < tokens.length - 1 &&
            tokens[tokenIndex].offset + tokens[tokenIndex].text.length <= a) {
          tokenIndex++;
        }
        var style = tokens == null || tokens.isEmpty
            ? base
            : noirTextStyle(tokens[tokenIndex].style, background: background);
        if (style.backgroundColor == null) {
          style = style.copyWith(backgroundColor: noirColor(background));
        }
        final offset = startOffset + a;
        if (editor.selections.any((s) => s.start <= offset && s.end > offset)) {
          style = style.copyWith(
            backgroundColor: noirColor(widget.theme.selectionBackground),
          );
        }
        if (_focus.hasFocus &&
            editor.selections.any((s) => s.active == offset)) {
          style = style.reverse();
        }
        if (offset == _matchingBracket) style = style.underline();
        if (editor.diagnostics.any(
          (d) => d.start <= offset && d.end > offset,
        )) {
          style = style.underline();
        }
        for (final caret in editor.carets) {
          if (caret.selection.active == offset) {
            style = style.copyWith(backgroundColor: noirColor(caret.color));
          }
        }
        final visible = cell < from || cell + cells > from + _width
            ? ' ' *
                  (math.min(cell + cells, from + _width) - math.max(cell, from))
            : grapheme;
        spans.add(TextSpan(text: visible, style: style));
        painted += terminalStringWidth(visible);
      }
      cell += cells;
      if (cell >= from + _width) break;
    }
    if (lineBackground != null && painted < _width) {
      spans.add(TextSpan(text: ' ' * (_width - painted), style: base));
    }
    return PointerListener(
      onPointerDown: (event) {
        _focus.requestFocus();
        final localCell = math.max(0, event.x - _gutter) + from;
        var grapheme = 0, cells = 0;
        while (grapheme < map.graphemeCount) {
          final next = terminalStringWidth(
            _safe(
              text.substring(
                map.graphemeToUtf16(grapheme),
                map.graphemeToUtf16(grapheme + 1),
              ),
            ),
          );
          if (cells + next > localCell) break;
          cells += next;
          grapheme++;
        }
        final at = startOffset + map.graphemeToUtf16(grapheme);
        editor.setSelections([syntax.DocumentSelection.collapsed(at)]);
        widget.onLine?.call(line);
      },
      child: RichText(
        text: TextSpan(style: base, children: spans),
        softWrap: false,
        maxLines: 1,
      ),
    );
  }

  void _move(VoidCallback command, {bool extend = false}) {
    final anchor = editor.selections.first.anchor;
    command();
    if (extend) {
      editor.setSelections([
        syntax.DocumentSelection(anchor, _input.selection.extentOffset),
      ]);
    }
    widget.onLine?.call(doc.positionAt(editor.selections.first.active).line);
  }

  void _copy() => widget.onCopy(
    editor.selections.map((s) => doc.text.substring(s.start, s.end)).join('\n'),
  );
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copy();
      return KeyEventResult.handled;
    }
    if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
      setState(() => _finding = !_finding);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (editor.proposedEdits.isNotEmpty) {
        editor.dismissProposal();
      } else if (_finding) {
        setState(() => _finding = false);
      } else {
        widget.onDismiss?.call();
      }
      return KeyEventResult.handled;
    }
    if (event.isAltPressed && event.logicalKey == LogicalKeyboardKey.enter) {
      final pos = doc.positionAt(editor.selections.first.active);
      _highlight?.flush(endLine: pos.line + 1);
      final tokens =
          _highlight?.themedLine(pos.line, widget.theme) ??
          const <syntax.ThemedToken>[];
      for (final token in tokens) {
        if (token.offset <= pos.character &&
            token.offset + token.text.length > pos.character) {
          widget.onToken?.call(pos.line, token);
          break;
        }
      }
      return KeyEventResult.handled;
    }
    if (event.isShiftPressed) {
      final move = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => _input.moveCursorLeft,
        LogicalKeyboardKey.arrowRight => _input.moveCursorRight,
        LogicalKeyboardKey.arrowUp => _input.moveCursorUp,
        LogicalKeyboardKey.arrowDown => _input.moveCursorDown,
        _ => null,
      };
      if (move != null && !event.isAltPressed) {
        _move(move, extend: true);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _find() {
    final matches = editor.find(_query.text);
    if (matches.isEmpty) {
      setState(() => _message = 'No matches');
      return;
    }
    final offset = editor.selections.first.end;
    final match =
        matches.where((m) => doc.offsetAt(m.start) > offset).firstOrNull ??
        matches.first;
    editor.setSelections([
      syntax.DocumentSelection(
        doc.offsetAt(match.start),
        doc.offsetAt(match.end),
      ),
    ]);
    setState(() => _message = '${matches.length} matches');
    _focus.requestFocus();
  }

  Future<void> _complete() async {
    if (_saving || widget.onComplete == null) return;
    setState(() => _saving = true);
    try {
      final accepted = await widget.onComplete!(editor.file);
      if (mounted) {
        setState(
          () => _message = accepted ? 'Changes accepted' : 'Changes declined',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _syncGrammar();
      final height = widget.height ?? constraints.maxHeight ?? 20;
      final caret = editor.selections.first.active;
      _matchingBracket =
          editor.matchingBracket(caret) ?? editor.matchingBracket(caret - 1);
      final extras =
          (widget.selectionActionsBuilder == null ? 0 : 1) +
          (widget.showHeader ? 1 : 0) +
          (_finding ? 2 : 0) +
          1 +
          (editor.proposedEdits.isNotEmpty ? 2 : 0) +
          (editor.diagnostics.isNotEmpty ? 1 : 0);
      _bodyHeight = math.max(1, height - extras);
      _layout(math.max(1, (constraints.maxWidth ?? 80) - _gutter));
      if (_pendingReveal case final range?) {
        _pendingReveal = null;
        final line = range.start.line.clamp(0, doc.lineCount - 1);
        _top = _rows!.offsetFor(line).toInt();
        _top = _top.clamp(
          0,
          math.max(0, _rows!.offsetFor(doc.lineCount).toInt() - _bodyHeight),
        );
        editor.verticalOffset = _top.toDouble();
        _lastSelection = editor.selections.first;
      } else if (_lastSelection != editor.selections.first) {
        _ensureCaret();
        _lastSelection = editor.selections.first;
      }
      _top = _top.clamp(
        0,
        math.max(0, _rows!.offsetFor(doc.lineCount).toInt() - _bodyHeight),
      );
      editor.verticalOffset = _top.toDouble();
      if (_presentation != null) {
        final window = (
          _rows!.rowAt(_top.toDouble()),
          (_rows!.rowAt((_top + _bodyHeight).toDouble()) + 1).clamp(
            0,
            doc.lineCount,
          ),
        );
        if (window != _requestedWindow) {
          _requestedWindow = window;
          Timer.run(() {
            if (mounted) _presentation?.setViewport(window.$1, window.$2);
          });
        }
      }
      final connection = TextInputConnection(
        controller: _input,
        readOnly: widget.readOnly,
        onSubmit: _complete,
      );
      final shortcuts = <ShortcutActivator, Intent>{
        ...connection.shortcuts,
        const CharacterActivator('/', control: true): const _EditorIntent(
          syntax.EditorCommand.toggleComment,
        ),
        for (final (key, command) in [
          (LogicalKeyboardKey.keyZ, syntax.EditorCommand.undo),
          (LogicalKeyboardKey.keyY, syntax.EditorCommand.redo),
          (LogicalKeyboardKey.keyA, syntax.EditorCommand.selectAll),
          (LogicalKeyboardKey.space, syntax.EditorCommand.acceptProposal),
        ])
          SingleActivator(key, control: true): _EditorIntent(command),
        const SingleActivator(LogicalKeyboardKey.tab): const _EditorIntent(
          syntax.EditorCommand.indent,
        ),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true):
            const _EditorIntent(syntax.EditorCommand.outdent),
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
            const _EditorIntent(syntax.EditorCommand.moveLineUp),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
            const _EditorIntent(syntax.EditorCommand.moveLineDown),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          alt: true,
          shift: true,
        ): const _EditorIntent(
          syntax.EditorCommand.copyLineUp,
        ),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          alt: true,
          shift: true,
        ): const _EditorIntent(
          syntax.EditorCommand.copyLineDown,
        ),
        for (final e in widget.shortcuts.entries) e.key: _EditorIntent(e.value),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.selectionActionsBuilder != null)
            SizedBox(
              height: 1,
              child: widget.selectionActionsBuilder!(context, editor),
            ),
          if (widget.showHeader)
            widget.headerBuilder?.call(context, editor.file) ??
                Text(editor.file.path),
          if (_finding) ...[
            TextInput(controller: _query, placeholder: 'Find', onSubmit: _find),
            Row(
              children: [
                Expanded(
                  child: TextInput(
                    controller: _replacement,
                    placeholder: 'Replace',
                  ),
                ),
                Button(label: 'Next', onPressed: _find),
                if (!widget.readOnly)
                  Button(
                    label: 'Replace all',
                    onPressed: () =>
                        editor.replaceAll(_query.text, _replacement.text),
                  ),
              ],
            ),
          ],
          Shortcuts(
            shortcuts: shortcuts,
            child: Actions(
              actions: {
                ...connection.actions,
                _EditorIntent: CallbackAction<_EditorIntent>((intent, context) {
                  if (widget.readOnly &&
                      intent.command != syntax.EditorCommand.selectAll) {
                    return KeyEventResult.ignored;
                  }
                  editor.execute(intent.command);
                  return KeyEventResult.handled;
                }),
                InsertTextIntent: CallbackAction<InsertTextIntent>((
                  intent,
                  context,
                ) {
                  if (widget.readOnly) return KeyEventResult.ignored;
                  editor.insertText(intent.text);
                  return KeyEventResult.handled;
                }),
              },
              child: Focus(
                focusNode: _focus,
                autofocus: widget.autofocus,
                onKeyEvent: _key,
                onFocusChange: (_) {
                  if (mounted) setState(() {});
                },
                child: SizedBox(
                  height: _bodyHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var row = _top;
                        row <
                            math.min(
                              _top + _bodyHeight,
                              _rows!.offsetFor(doc.lineCount).toInt(),
                            );
                        row++
                      )
                        _paint(row),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (editor.diagnostics.isNotEmpty)
            Text(
              editor.diagnostics
                  .map(
                    (d) => '${doc.positionAt(d.start).line + 1}: ${d.message}',
                  )
                  .join(' | '),
              maxLines: 1,
            ),
          if (editor.proposedEdits.isNotEmpty) ...[
            Text(
              'Suggestion: ${editor.proposedEdits.map((e) => e.text).join(' | ')}',
              maxLines: 1,
            ),
            Row(
              children: [
                Button(
                  label: 'Accept suggestion',
                  onPressed: editor.acceptProposal,
                ),
                Button(
                  label: 'Dismiss suggestion',
                  onPressed: editor.dismissProposal,
                ),
              ],
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  _message.isEmpty
                      ? 'Ctrl+F Find • Ctrl+C Copy • Ctrl+Z Undo'
                      : _message,
                  maxLines: 1,
                ),
              ),
              if (widget.onComplete != null)
                Button(
                  label: _saving ? 'Saving…' : 'Done',
                  onPressed: _saving ? null : _complete,
                ),
              if (widget.onDismiss != null)
                Button(label: 'Cancel', onPressed: widget.onDismiss),
            ],
          ),
        ],
      );
    },
  );
  @override
  void dispose() {
    _detach(editor, widget.focusNode);
    _query.dispose();
    _replacement.dispose();
    super.dispose();
  }
}
