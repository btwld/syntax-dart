import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:syntax/syntax.dart';

import 'chrome.dart';
import 'patch_view.dart';
import 'styles.dart';

/// Native text-input binding for a renderer-neutral editing session.
///
/// IME composition stays in Flutter while edits, history and selections live
/// in [editor]. Only viewport lines build colored spans. Offscreen text is
/// represented by at most two plain spans.
class DocumentTextEditingController extends TextEditingController {
  /// Attaches to a session; disposing this binding leaves the session alive.
  DocumentTextEditingController({
    required this.editor,
    required this.highlighter,
    required SyntaxTheme theme,
    this.language,
    HighlightExecutor? executor,
  }) : _theme = theme,
       super(text: editor.document.text) {
    if (executor != null) {
      _presentation = PresentationController(
        editor: editor,
        highlighter: highlighter,
        theme: theme,
        executor: executor,
        language: language,
      )..addListener(_notifyPresentation);
      _presentation!.setViewport(0, math.min(100, editor.document.lineCount));
    } else {
      _syncGrammar();
    }
    editor.addListener(_fromEditor);
    addListener(_fromInput);
    _fromEditor();
  }

  /// Logical state shared with other views.
  final EditorController editor;

  /// Registered grammars used by this binding.
  final Highlighter highlighter;

  /// Current colors; changing this does not invalidate grammar state.
  SyntaxTheme get theme => _theme;
  SyntaxTheme _theme;
  set theme(SyntaxTheme value) {
    if (identical(_theme, value)) return;
    _theme = value;
    _presentation?.theme = value;
    _notifyPresentation();
  }

  /// Explicit language override.
  final String? language;
  LiveHighlighter? _highlight;
  PresentationController? _presentation;
  Object? _grammarKey;
  void _syncGrammar() {
    if (_presentation != null) return;
    final name =
        language ??
        editor.file.language ??
        highlighter.languageForPath(editor.file.path)?.name;
    final key = (highlighter.revision, name);
    if (_grammarKey == key) return;
    _grammarKey = key;
    _highlight?.dispose();
    _highlight = name == null || highlighter.language(name) == null
        ? null
        : (LiveHighlighter(editor.document, highlighter.grammar(name))
            ..pause());
  }

  bool _updating = false;
  int _firstLine = 0, _lastLine = 100;

  /// Limits colored spans to visible lines plus the caller's overscan.
  void setViewport(int firstLine, int lastLine) {
    firstLine = firstLine.clamp(0, editor.document.lineCount - 1);
    lastLine = lastLine.clamp(firstLine + 1, editor.document.lineCount);
    _presentation?.setViewport(firstLine, lastLine);
    if (_firstLine == firstLine && _lastLine == lastLine) return;
    _firstLine = firstLine;
    _lastLine = lastLine;
    _notifyPresentation();
  }

  void _notifyPresentation() {
    final previous = _updating;
    _updating = true;
    try {
      notifyListeners();
    } finally {
      _updating = previous;
    }
  }

  void _fromEditor() {
    if (_updating) return;
    _updating = true;
    try {
      final selection = editor.selections.first;
      final source = editor.document.text;
      value = TextEditingValue(
        text: source,
        selection: TextSelection(
          baseOffset: selection.anchor,
          extentOffset: selection.active,
        ),
        composing: source == text ? value.composing : TextRange.empty,
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
        if (forward) {
          final rest = source.substring(offset);
          return offset + (rest.isEmpty ? 0 : rest.characters.first.length);
        }
        final before = source.substring(0, offset);
        return offset - (before.isEmpty ? 0 : before.characters.last.length);
      }

      editor.updateFromInput(
        text,
        selection.isValid
            ? DocumentSelection(selection.baseOffset, selection.extentOffset)
            : null,
        composing: !value.composing.isCollapsed,
        deletionBoundary: boundary,
      );
      final next = editor.selections.first;
      if (text != editor.document.text ||
          (selection.isValid &&
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
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    _syncGrammar();
    final document = editor.document;
    final first = _firstLine.clamp(0, document.lineCount - 1);
    final last = _lastLine.clamp(first + 1, document.lineCount);
    _highlight?.flush(endLine: last);
    final styles = TokenTextStyles(theme, base: style ?? defaultCodeTextStyle);
    final children = <InlineSpan>[];
    final from = document.lineStart(first);
    final to = last == document.lineCount
        ? document.length
        : document.lineStart(last);
    if (from > 0) children.add(TextSpan(text: text.substring(0, from)));
    final ranges =
        _highlight?.ranges(theme, startLine: first, endLine: last) ??
        <StyledRange>[
          if (_presentation != null)
            for (var line = first; line < last; line++)
              ..._presentationRanges(line),
        ];
    final boundaries = <int>{from, to};
    for (final r in ranges) {
      boundaries
        ..add(r.start)
        ..add(r.end);
    }
    final caret = editor.selections.first.active;
    final bracket =
        editor.matchingBracket(caret) ?? editor.matchingBracket(caret - 1);
    final decorations = <(int, int, TextStyle)>[
      if (bracket != null)
        (
          bracket,
          bracket + 1,
          TextStyle(
            backgroundColor: theme.selectionColor,
            decoration: TextDecoration.underline,
          ),
        ),
      if (withComposing && value.isComposingRangeValid)
        (
          value.composing.start,
          value.composing.end,
          const TextStyle(decoration: TextDecoration.underline),
        ),
      for (final diagnostic in editor.diagnostics)
        (
          diagnostic.start,
          diagnostic.end,
          TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: theme.diagnosticColor(diagnostic.severity),
          ),
        ),
      for (final s in editor.selections.skip(1))
        (
          s.start,
          s.isCollapsed ? (s.start + 1).clamp(0, text.length) : s.end,
          TextStyle(backgroundColor: theme.selectionColor),
        ),
      for (final caret in editor.carets)
        (
          caret.selection.start,
          caret.selection.isCollapsed
              ? (caret.selection.start + 1).clamp(0, text.length)
              : caret.selection.end,
          TextStyle(backgroundColor: Color(caret.color).withValues(alpha: .4)),
        ),
    ];
    for (final (start, end, _) in decorations) {
      if (end > from && start < to) {
        boundaries
          ..add(start.clamp(from, to))
          ..add(end.clamp(from, to));
      }
    }
    final points = boundaries.toList()..sort();
    var index = 0;
    for (var p = 0; p < points.length - 1; p++) {
      final start = points[p], end = points[p + 1];
      while (index < ranges.length && ranges[index].end <= start) {
        index++;
      }
      var tokenStyle = index < ranges.length && ranges[index].start <= start
          ? styles[ranges[index].style]
          : styles.base;
      for (final (a, b, decoration) in decorations) {
        if (a < end && b > start) tokenStyle = tokenStyle.merge(decoration);
      }
      children.add(
        TextSpan(text: text.substring(start, end), style: tokenStyle),
      );
    }
    if (to < text.length) children.add(TextSpan(text: text.substring(to)));
    return TextSpan(style: styles.base, children: children);
  }

  @override
  void dispose() {
    editor.removeListener(_fromEditor);
    removeListener(_fromInput);
    _highlight?.dispose();
    _presentation?.dispose();
    super.dispose();
  }

  Iterable<StyledRange> _presentationRanges(int line) sync* {
    var offset = editor.document.lineStart(line);
    for (final token in _presentation!.line(line) ?? const <ThemedToken>[]) {
      yield StyledRange(offset, offset + token.text.length, token.style);
      offset += token.text.length;
    }
  }
}

/// Native multiline editor with shared history, commands, diagnostics and proposals.
class SyntaxEditor extends StatefulWidget {
  /// Uses [controller] for persistent state and [onComplete] to accept a draft.
  const SyntaxEditor({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.language,
    this.onComplete,
    this.onDismiss,
    this.shortcuts = const {},
    this.showToolbar = true,
    this.autofocus = false,
    this.textStyle,
    this.annotationBuilder,
    this.selectionActionsBuilder,
    this.wrap = true,
    this.executor,
  });

  /// Optional actions for the current selection, displayed above the editor.
  final Widget Function(BuildContext, EditorController)?
  selectionActionsBuilder;

  /// Logical editing session, retained by the application or a file controller.
  final EditorController controller;

  /// Registered grammars.
  final Highlighter highlighter;

  /// Current palette.
  final SyntaxTheme theme;

  /// Wraps source lines; disabling this enables retained horizontal scrolling.
  final bool wrap;

  /// Shared background executor, owned and disposed by the caller.
  final HighlightExecutor? executor;

  /// Optional language override.
  final String? language;

  /// Application callback for accepting or rejecting the edited result.
  final Future<bool> Function(SourceFile result)? onComplete;

  /// Called when the user dismisses the editing surface.
  final VoidCallback? onDismiss;

  /// Custom key bindings, overriding the defaults with the same activator.
  final Map<ShortcutActivator, EditorCommand> shortcuts;

  /// Shows search, history and completion controls.
  final bool showToolbar;

  /// Requests initial text-input focus.
  final bool autofocus;

  /// Monospace typography used in the text field.
  final TextStyle? textStyle;

  /// Optional annotation presentation beneath the field.
  final Widget Function(BuildContext, LineAnnotation<Object?>)?
  annotationBuilder;
  @override
  State<SyntaxEditor> createState() => _SyntaxEditorState();
}

class _SyntaxEditorState extends State<SyntaxEditor> {
  late DocumentTextEditingController _input;
  late ScrollController _scroll;
  late ScrollController _horizontal;
  final _fieldKey = GlobalKey();
  Object? _widthKey;
  double _sourceWidth = 0;
  bool _viewportQueued = false;
  final _focus = FocusNode(), _searchFocus = FocusNode();
  final _search = TextEditingController(),
      _replacement = TextEditingController();
  bool _finding = false, _saving = false;
  String? _message;
  DocumentRange? _revealed;
  int _revealRequest = -1;
  EditorController get editor => widget.controller;
  double get _lineHeight =>
      (widget.textStyle?.fontSize ?? 14) * (widget.textStyle?.height ?? 1.5);
  void _attach() {
    _input = DocumentTextEditingController(
      editor: editor,
      highlighter: widget.highlighter,
      theme: widget.theme,
      language: widget.language,
      executor: widget.executor,
    );
    _scroll = ScrollController(initialScrollOffset: editor.verticalOffset)
      ..addListener(_scrolled);
    _horizontal = ScrollController(initialScrollOffset: editor.horizontalOffset)
      ..addListener(() => editor.horizontalOffset = _horizontal.offset);
    editor.addListener(_changed);
    _scrolled();
    _revealRequest = -1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changed();
    });
  }

  void _detach() {
    editor.removeListener(_changed);
    _input.dispose();
    _scroll.dispose();
    _horizontal.dispose();
  }

  void _scrolled() {
    if (_scroll.hasClients) editor.verticalOffset = _scroll.offset;
    if (_viewportQueued) return;
    _viewportQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportQueued = false;
      if (!mounted) return;
      final render = _editableRender();
      if (render == null || !render.hasSize) return;
      final first = editor.document
          .positionAt(
            render
                .getPositionForPoint(render.localToGlobal(Offset.zero))
                .offset
                .clamp(0, editor.document.length),
          )
          .line;
      final last = editor.document
          .positionAt(
            render
                .getPositionForPoint(
                  render.localToGlobal(
                    Offset(render.size.width, render.size.height),
                  ),
                )
                .offset
                .clamp(0, editor.document.length),
          )
          .line;
      _input.setViewport(
        math.max(0, first - 20),
        math.min(editor.document.lineCount, last + 21),
      );
    });
  }

  RenderEditable? _editableRender() {
    RenderEditable? result;
    void visit(RenderObject node) {
      if (node is RenderEditable) {
        result = node;
      } else if (result == null) {
        node.visitChildren(visit);
      }
    }

    final root = _fieldKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return result;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_revealRequest != editor.revealRequest && editor.revealTarget != null) {
      _revealRequest = editor.revealRequest;
      _revealed = editor.revealTarget;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            (_scroll.offset +
                    (_editableRender()
                            ?.getLocalRectForCaret(
                              TextPosition(
                                offset: editor.document.offsetAt(
                                  _revealed!.start,
                                ),
                              ),
                            )
                            .top ??
                        _revealed!.start.line * _lineHeight))
                .clamp(0, _scroll.position.maxScrollExtent),
          );
        }
      });
    }
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
        oldWidget.language != widget.language ||
        oldWidget.executor != widget.executor) {
      oldWidget.controller.removeListener(_changed);
      _input.dispose();
      _scroll.dispose();
      _horizontal.dispose();
      _attach();
    } else {
      _input.theme = widget.theme;
    }
  }

  void _command(EditorCommand command) {
    editor.execute(command);
    _focus.requestFocus();
  }

  void _toggleFind() {
    setState(() => _finding = !_finding);
    (_finding ? _searchFocus : _focus).requestFocus();
  }

  bool _find({bool previous = false}) {
    final matches = editor
        .find(_search.text)
        .map(
          (r) => DocumentSelection(
            editor.document.offsetAt(r.start),
            editor.document.offsetAt(r.end),
          ),
        )
        .toList();
    if (matches.isEmpty) {
      setState(() => _message = 'No matches');
      return false;
    }
    final current = editor.selections.first;
    final found = previous
        ? matches.where((m) => m.start < current.start).lastOrNull ??
              matches.last
        : matches
                  .where(
                    (m) => m.start >= current.end && m.start != current.start,
                  )
                  .firstOrNull ??
              matches.first;
    editor.setSelections([DocumentSelection(found.start, found.end)]);
    editor.reveal(
      DocumentRange(
        editor.document.positionAt(found.start),
        editor.document.positionAt(found.end),
      ),
    );
    setState(() => _message = '${matches.length} matches');
    return true;
  }

  void _replaceMatch() {
    final selection = editor.selections.first;
    if (_search.text.isEmpty) return;
    if (editor.document.text.substring(selection.start, selection.end) !=
        _search.text) {
      if (!_find()) return;
    }
    editor.setSelections([editor.selections.first]);
    editor.insertText(_replacement.text, autoSurround: false);
    _find();
  }

  Future<void> _complete() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final result = editor.file;
      final accepted = await widget.onComplete!(result);
      if (mounted) {
        setState(
          () => _message = accepted ? 'Changes accepted' : 'Changes declined',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      for (final control in [true, false]) ...{
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: control,
          meta: !control,
        ): () =>
            _command(EditorCommand.undo),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: control,
          meta: !control,
          shift: true,
        ): () =>
            _command(EditorCommand.redo),
        SingleActivator(
          LogicalKeyboardKey.slash,
          control: control,
          meta: !control,
        ): () =>
            _command(EditorCommand.toggleComment),
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: control,
          meta: !control,
        ): () =>
            _toggleFind(),
      },
      const SingleActivator(LogicalKeyboardKey.tab): () =>
          _command(EditorCommand.indent),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
          _command(EditorCommand.outdent),
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
          _command(EditorCommand.moveLineUp),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
          _command(EditorCommand.moveLineDown),
      const SingleActivator(
        LogicalKeyboardKey.arrowUp,
        alt: true,
        shift: true,
      ): () =>
          _command(EditorCommand.copyLineUp),
      const SingleActivator(
        LogicalKeyboardKey.arrowDown,
        alt: true,
        shift: true,
      ): () =>
          _command(EditorCommand.copyLineDown),
      for (final entry in widget.shortcuts.entries)
        entry.key: () => _command(entry.value),
    };
    return SyntaxChrome(
      theme: widget.theme,
      child: CallbackShortcuts(
        bindings: {
          for (final control in [true, false])
            SingleActivator(
              LogicalKeyboardKey.keyF,
              control: control,
              meta: !control,
            ): _toggleFind,
        },
        child: Material(
          color: widget.theme.backgroundColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.selectionActionsBuilder != null)
                widget.selectionActionsBuilder!(context, widget.controller),
              if (widget.showToolbar)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Undo',
                      onPressed: editor.canUndo
                          ? () => _command(EditorCommand.undo)
                          : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      onPressed: editor.canRedo
                          ? () => _command(EditorCommand.redo)
                          : null,
                      icon: const Icon(Icons.redo),
                    ),
                    IconButton(
                      tooltip: 'Find and replace',
                      onPressed: _toggleFind,
                      icon: const Icon(Icons.search),
                    ),
                    if (widget.onComplete != null)
                      TextButton(
                        onPressed: _saving ? null : _complete,
                        child: const Text('Done'),
                      ),
                    if (widget.onDismiss != null)
                      TextButton(
                        onPressed: widget.onDismiss,
                        child: const Text('Cancel'),
                      ),
                    if (_message != null)
                      Text(
                        _message!,
                        style: TextStyle(color: widget.theme.foregroundColor),
                      ),
                  ],
                ),
              if (_finding)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _search,
                        focusNode: _searchFocus,
                        decoration: const InputDecoration(labelText: 'Find'),
                        onSubmitted: (_) => _find(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous match',
                      onPressed: () => _find(previous: true),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Next match',
                      onPressed: _find,
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _replacement,
                        decoration: const InputDecoration(labelText: 'Replace'),
                      ),
                    ),
                    TextButton(
                      onPressed: _replaceMatch,
                      child: const Text('Replace'),
                    ),
                    TextButton(
                      onPressed: () =>
                          editor.replaceAll(_search.text, _replacement.text),
                      child: const Text('Replace all'),
                    ),
                  ],
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _scrolled();
                    final field = CallbackShortcuts(
                      bindings: bindings,
                      child: TextField(
                        key: _fieldKey,
                        controller: _input,
                        focusNode: _focus,
                        autofocus: widget.autofocus,
                        scrollController: _scroll,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        style: widget.textStyle ?? defaultCodeTextStyle,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                    );
                    if (widget.wrap) return field;
                    final style = widget.textStyle ?? defaultCodeTextStyle;
                    final widthKey = (
                      editor.document.id,
                      editor.document.revision,
                      style,
                      MediaQuery.textScalerOf(context),
                    );
                    if (_widthKey != widthKey) {
                      _widthKey = widthKey;
                      final painter = TextPainter(
                        text: TextSpan(
                          text: editor.document.text,
                          style: style,
                        ),
                        textDirection: TextDirection.ltr,
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      _sourceWidth = painter.width + 32;
                      painter.dispose();
                    }
                    return SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(constraints.maxWidth, _sourceWidth),
                        height: constraints.maxHeight,
                        child: field,
                      ),
                    );
                  },
                ),
              ),
              if (editor.diagnostics.isNotEmpty)
                SizedBox(
                  height: 72,
                  child: ListView(
                    children: [
                      for (final d in editor.diagnostics)
                        ListTile(
                          dense: true,
                          title: Text(d.message),
                          leading: Icon(
                            d.severity == DiagnosticSeverity.error
                                ? Icons.error_outline
                                : Icons.info_outline,
                            color: widget.theme.diagnosticColor(d.severity),
                          ),
                          onTap: () {
                            editor.setSelections([
                              DocumentSelection(d.start, d.end),
                            ]);
                            editor.reveal(
                              DocumentRange(
                                editor.document.positionAt(d.start),
                                editor.document.positionAt(d.end),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              if (editor.annotations.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final a in editor.annotations)
                        widget.annotationBuilder?.call(context, a) ??
                            Text(
                              '${editor.document.positionAt(a.start).line + 1}: ${a.data}',
                            ),
                    ],
                  ),
                ),
              if (editor.proposedEdits.isNotEmpty) ...[
                SizedBox(
                  height: 140,
                  child: PatchView.fromTexts(
                    oldText: editor.document.text,
                    newText: _proposalText(),
                    theme: widget.theme,
                    highlighter: widget.highlighter,
                    language:
                        widget.language ??
                        editor.file.language ??
                        widget.highlighter
                            .languageForPath(editor.file.path)
                            ?.name,
                    textStyle: widget.textStyle,
                    wrap: widget.wrap,
                    contextLines: 0,
                    padding: EdgeInsets.zero,
                  ),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: editor.acceptProposal,
                      child: const Text('Accept suggestion'),
                    ),
                    TextButton(
                      onPressed: editor.dismissProposal,
                      child: const Text('Dismiss suggestion'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _proposalText() {
    final preview = TextDocument(editor.document.text)
      ..applyOffsetEdits(editor.proposedEdits);
    final result = preview.text;
    preview.dispose();
    return result;
  }

  @override
  void dispose() {
    _detach();
    _focus.dispose();
    _searchFocus.dispose();
    _search.dispose();
    _replacement.dispose();
    super.dispose();
  }
}
