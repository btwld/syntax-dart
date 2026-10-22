import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax/syntax.dart';
import 'editor.dart';
import 'styles.dart';
import 'indexed_viewport.dart';
import 'horizontal_scroll.dart';

/// A virtualized highlighted file with source-only line selection and copy.
class SyntaxFileView extends StatefulWidget {
  /// Displays a persistent session, including annotations and external carets.
  const SyntaxFileView({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.wrap = true,
    this.showHeader = true,
    this.showLineNumbers = true,
    this.textStyle,
    this.headerBuilder,
    this.annotationBuilder,
    this.gutterActionBuilder,
    this.onLineTap,
    this.onTokenTap,
    this.scrollController,
    this.executor,
  });

  /// The document and logical selection state.
  final EditorController controller;

  /// Registered grammars.
  final Highlighter highlighter;

  /// Current palette.
  final SyntaxTheme theme;

  /// Wraps long logical lines instead of enabling horizontal scrolling.
  final bool wrap;

  /// Shows a fixed file header above the scrollable body.
  final bool showHeader;

  /// Shows source line numbers in a nonselectable gutter.
  final bool showLineNumbers;

  /// Optional monospace typography.
  final TextStyle? textStyle;

  /// Custom fixed file header.
  final Widget Function(BuildContext, SourceFile)? headerBuilder;

  /// Custom content below an annotated line.
  final Widget Function(BuildContext, LineAnnotation<Object?>)?
  annotationBuilder;

  /// Custom per-line gutter actions.
  final Widget Function(BuildContext, int)? gutterActionBuilder;

  /// Called with a zero-based line number.
  final ValueChanged<int>? onLineTap;

  /// Called with the line and highlighted token that was clicked.
  final void Function(int, ThemedToken)? onTokenTap;

  /// Optional externally owned vertical scroll controller.
  final ScrollController? scrollController;

  /// Optional shared background executor. Omission uses incremental local work.
  final HighlightExecutor? executor;
  @override
  State<SyntaxFileView> createState() => _SyntaxFileViewState();
}

class _SyntaxFileViewState extends State<SyntaxFileView> {
  late ScrollController _scroll;
  LiveHighlighter? _highlight;
  Object? _grammarKey;
  void _syncGrammar() {
    final name =
        editor.file.language ??
        widget.highlighter.languageForPath(editor.file.path)?.name;
    final key = (
      widget.highlighter,
      widget.highlighter.revision,
      editor.document,
      name,
      widget.executor,
    );
    if (_grammarKey == key) return;
    _grammarKey = key;
    _highlight?.dispose();
    _highlight =
        widget.executor != null ||
            name == null ||
            widget.highlighter.language(name) == null
        ? null
        : (LiveHighlighter(editor.document, widget.highlighter.grammar(name))
            ..pause());
  }

  PresentationController? _presentation;
  int? _visibleStart, _visibleEnd;
  bool _windowQueued = false;
  void _presentationChanged() {
    if (mounted) setState(() {});
  }

  void _requestLine(int line) {
    if (_presentation == null) return;
    _visibleStart = _visibleStart == null || line < _visibleStart!
        ? line
        : _visibleStart;
    _visibleEnd = _visibleEnd == null || line + 1 > _visibleEnd!
        ? line + 1
        : _visibleEnd;
    if (_windowQueued) return;
    _windowQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowQueued = false;
      if (!mounted || _visibleStart == null) return;
      _presentation?.setViewport(_visibleStart!, _visibleEnd!);
      _visibleStart = _visibleEnd = null;
    });
  }

  final _horizontal = HorizontalCodeGroup();
  EditorController get editor => widget.controller;
  double get _height =>
      (widget.textStyle?.fontSize ?? 14) * (widget.textStyle?.height ?? 1.5);
  void _attach() {
    _horizontal
      ..offset = editor.horizontalOffset
      ..onChanged = (offset) => editor.horizontalOffset = offset;
    if (widget.executor case final executor?) {
      _presentation = PresentationController(
        editor: editor,
        highlighter: widget.highlighter,
        theme: widget.theme,
        executor: executor,
      )..addListener(_presentationChanged);
    }
    _grammarKey = null;
    _syncGrammar();
    editor.addListener(_changed);
    _scroll =
        widget.scrollController ??
        ScrollController(initialScrollOffset: editor.verticalOffset);
    _scroll.addListener(_scrolled);
  }

  void _scrolled() {
    editor.verticalOffset = _scroll.offset;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  void _detach(EditorController controller, ScrollController? external) {
    _horizontal.onChanged = null;
    controller.removeListener(_changed);
    _highlight?.dispose();
    _highlight = null;
    _presentation?.dispose();
    _presentation = null;
    _scroll.removeListener(_scrolled);
    if (external == null) _scroll.dispose();
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(SyntaxFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != editor ||
        oldWidget.highlighter != widget.highlighter ||
        oldWidget.scrollController != widget.scrollController ||
        oldWidget.executor != widget.executor) {
      _detach(oldWidget.controller, oldWidget.scrollController);
      _attach();
    } else {
      _presentation?.theme = widget.theme;
    }
  }

  void _selectLine(int line) {
    final doc = editor.document;
    final start = doc.lineStart(line), end = start + doc.lineText(line).length;
    final existing = editor.selections.first;
    final extend = HardwareKeyboard.instance.isShiftPressed;
    editor.setSelections([
      DocumentSelection(extend ? existing.anchor : start, end),
    ]);
    widget.onLineTap?.call(line);
  }

  void _copy() {
    final text = editor.selections
        .map((s) => editor.document.text.substring(s.start, s.end))
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) {
    _syncGrammar();
    final doc = editor.document;
    final styles = TokenTextStyles(
      widget.theme,
      base: widget.textStyle ?? defaultCodeTextStyle,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
      },
      child: Focus(
        child: ColoredBox(
          color: widget.theme.backgroundColor,
          child: Column(
            children: [
              if (widget.showHeader)
                widget.headerBuilder?.call(context, editor.file) ??
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(editor.file.path, style: styles.base),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy selection',
                          onPressed: _copy,
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
              Expanded(
                child: IndexedCodeViewport(
                  controller: _scroll,
                  count: doc.lineCount,
                  layoutKey: (
                    doc.id,
                    doc.revision,
                    widget.wrap,
                    widget.textStyle,
                    editor.annotations,
                  ),
                  identity: doc.lineIdentity,
                  indexOf: doc.lineForIdentity,
                  estimatedHeight: _height,
                  revealRow: editor.revealTarget?.start.line,
                  revealRequest: editor.revealRequest,
                  builder: (context, line) {
                    _requestLine(line);
                    _highlight?.flush(endLine: line + 1);
                    final tokens =
                        _presentation?.line(line) ??
                        _highlight?.themedLine(line, widget.theme);
                    final text = doc.lineText(line);
                    final start = doc.lineStart(line),
                        end = start + text.length;
                    final selected = editor.selections.any(
                      (s) => s.start <= end && s.end > start,
                    );
                    Widget code = Text.rich(
                      TextSpan(
                        style: styles.base,
                        children: tokens == null
                            ? [TextSpan(text: text)]
                            : [
                                for (final token in tokens)
                                  if (widget.onTokenTap == null)
                                    TextSpan(
                                      text: token.text,
                                      style: styles[token.style],
                                    )
                                  else
                                    WidgetSpan(
                                      child: GestureDetector(
                                        onTap: () =>
                                            widget.onTokenTap!(line, token),
                                        child: Text(
                                          token.text,
                                          style: styles[token.style],
                                        ),
                                      ),
                                    ),
                              ],
                      ),
                      softWrap: widget.wrap,
                    );
                    if (!widget.wrap) {
                      code = HorizontalCode(group: _horizontal, child: code);
                    }
                    code = SelectionArea(child: code);
                    return KeyedSubtree(
                      key: ValueKey(doc.lineIdentity(line)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: 'Line ${line + 1}',
                            selected: selected,
                            child: ColoredBox(
                              color: selected
                                  ? widget.theme.selectionColor
                                  : widget.theme.backgroundColor,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.showLineNumbers)
                                    SelectionContainer.disabled(
                                      child: GestureDetector(
                                        onTap: () => _selectLine(line),
                                        child: SizedBox(
                                          width:
                                              doc.lineCount.toString().length *
                                                  (styles.base.fontSize ?? 14) +
                                              20,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 12,
                                            ),
                                            child: Text(
                                              '${line + 1}',
                                              textAlign: TextAlign.right,
                                              style: styles.base.copyWith(
                                                color: widget
                                                    .theme
                                                    .lineNumberColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (widget.gutterActionBuilder != null)
                                    SelectionContainer.disabled(
                                      child: widget.gutterActionBuilder!(
                                        context,
                                        line,
                                      ),
                                    ),
                                  Expanded(child: code),
                                ],
                              ),
                            ),
                          ),
                          for (final d in editor.diagnostics)
                            if (d.start < end + 1 && d.end >= start)
                              SelectionContainer.disabled(
                                child: Text(
                                  d.message,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                          for (final a in editor.annotations)
                            if (a.start >= start &&
                                (a.start < end + 1 ||
                                    line == doc.lineCount - 1))
                              SelectionContainer.disabled(
                                child:
                                    widget.annotationBuilder?.call(
                                      context,
                                      a,
                                    ) ??
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text('${a.data}'),
                                    ),
                              ),
                          for (final caret in editor.carets)
                            if (caret.selection.active >= start &&
                                caret.selection.active <= end)
                              SelectionContainer.disabled(
                                child: Text(
                                  caret.label.isEmpty ? caret.id : caret.label,
                                  style: TextStyle(color: Color(caret.color)),
                                ),
                              ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _detach(editor, widget.scrollController);
    super.dispose();
  }
}

/// Flat multi-file workspace with bounded retained sessions and native editors.
class SyntaxFileList extends StatefulWidget {
  /// Uses [controller] to retain drafts and collapse state across view changes.
  const SyntaxFileList({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.editable = false,
    this.onComplete,
    this.fileHeight = 360,
  });

  /// Files and session storage.
  final FileListController controller;

  /// Registered grammars.
  final Highlighter highlighter;

  /// Current palette.
  final SyntaxTheme theme;

  /// Enables native editing for expanded files.
  final bool editable;

  /// Application decision for each completed draft.
  final Future<bool> Function(SourceFile)? onComplete;

  /// Height of each independent file viewport.
  final double fileHeight;
  @override
  State<SyntaxFileList> createState() => _SyntaxFileListState();
}

class _SyntaxFileListState extends State<SyntaxFileList> {
  final _scroll = ScrollController();
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SyntaxFileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  Widget build(BuildContext context) => IndexedCodeViewport(
    controller: _scroll,
    count: widget.controller.files.length,
    layoutKey: (
      widget.controller.files,
      widget.fileHeight,
      widget.controller.files
          .map((file) => widget.controller.isCollapsed(file.id))
          .join(','),
    ),
    estimatedHeight: widget.fileHeight + 56,
    identity: (index) => widget.controller.files[index].id,
    indexOf: (key) {
      final index = widget.controller.files.indexWhere(
        (file) => file.id == key,
      );
      return index < 0 ? null : index;
    },
    revealRow: widget.controller.revealTarget == null
        ? null
        : widget.controller.files.indexWhere(
            (file) => file.id == widget.controller.revealTarget!.$1,
          ),
    revealRequest: widget.controller.revealRequest,
    builder: (context, index) {
      final file = widget.controller.files[index];
      return Column(
        key: ValueKey(file.id),
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(file.path),
            trailing: Icon(
              widget.controller.isCollapsed(file.id)
                  ? Icons.expand_more
                  : Icons.expand_less,
            ),
            onTap: () => widget.controller.toggle(file.id),
          ),
          if (widget.controller.hasSourceConflict(file.id))
            TextButton(
              onPressed: () => widget.controller.reload(file.id),
              child: const Text('Source changed — reload latest source'),
            ),
          if (!widget.controller.isCollapsed(file.id))
            SizedBox(
              height: widget.fileHeight,
              child: _SessionFile(
                key: ValueKey('${file.id}:session'),
                file: file,
                owner: widget,
              ),
            ),
        ],
      );
    },
  );
  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }
}

class _SessionFile extends StatefulWidget {
  const _SessionFile({super.key, required this.file, required this.owner});
  final SourceFile file;
  final SyntaxFileList owner;
  @override
  State<_SessionFile> createState() => _SessionFileState();
}

class _SessionFileState extends State<_SessionFile> {
  late EditorController _editor;
  int _revealRequest = -1;
  @override
  void initState() {
    super.initState();
    _editor = widget.owner.controller.acquire(widget.file.id);
  }

  @override
  void didUpdateWidget(_SessionFile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner.controller != widget.owner.controller ||
        oldWidget.file.id != widget.file.id) {
      oldWidget.owner.controller.release(oldWidget.file.id);
      _editor = widget.owner.controller.acquire(widget.file.id);
      _revealRequest = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.owner;
    if (owner.controller.revealTarget case (
      final id,
      final range,
    ) when id == widget.file.id) {
      if (_revealRequest != owner.controller.revealRequest) {
        _revealRequest = owner.controller.revealRequest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _editor.reveal(range);
        });
      }
    }
    return owner.editable
        ? SyntaxEditor(
            controller: _editor,
            highlighter: owner.highlighter,
            theme: owner.theme,
            onComplete: owner.onComplete == null
                ? null
                : (_) => owner.controller.complete(
                    widget.file.id,
                    _editor,
                    owner.onComplete!,
                  ),
          )
        : SyntaxFileView(
            controller: _editor,
            highlighter: owner.highlighter,
            theme: owner.theme,
            showHeader: false,
          );
  }

  @override
  void dispose() {
    widget.owner.controller.release(widget.file.id);
    super.dispose();
  }
}

/// Streaming file surface; delivery and cancellation belong to [controller].
class StreamingCodeView extends StatelessWidget {
  /// Displays accumulated and provisional source through the normal file view.
  const StreamingCodeView({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
  });

  /// Producer and live document.
  final StreamDocumentController controller;

  /// Registered grammars.
  final Highlighter highlighter;

  /// Current palette.
  final SyntaxTheme theme;
  @override
  Widget build(BuildContext context) => SyntaxFileView(
    controller: controller.editor,
    highlighter: highlighter,
    theme: theme,
  );
}

/// Resolves ordinary and base-section conflicts with explicit side actions.
class MergeConflictView extends StatefulWidget {
  /// Keeps the resolved file in [controller].
  const MergeConflictView({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
  });

  /// Parsed conflicts and resolution commands.
  final MergeController controller;

  /// Registered grammars.
  final Highlighter highlighter;

  /// Current palette.
  final SyntaxTheme theme;
  @override
  State<MergeConflictView> createState() => _MergeConflictViewState();
}

class _MergeConflictViewState extends State<MergeConflictView> {
  late EditorController _editor;
  void _changed() {
    _editor.document.applyOffsetEdits([
      OffsetEdit(0, _editor.document.length, widget.controller.file.text),
    ]);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _editor = EditorController(file: widget.controller.file);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(MergeConflictView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _editor.dispose();
      _editor = EditorController(file: widget.controller.file);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: SyntaxFileView(
          controller: _editor,
          highlighter: widget.highlighter,
          theme: widget.theme,
        ),
      ),
      if (widget.controller.conflicts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('All conflicts resolved'),
        )
      else
        SizedBox(
          height: 160,
          child: ListView.builder(
            itemCount: widget.controller.conflicts.length,
            itemBuilder: (context, index) {
              final conflict = widget.controller.conflicts[index];
              return ListTile(
                title: Text(
                  'Conflict ${index + 1}: ${conflict.currentLabel} / ${conflict.incomingLabel}',
                ),
                onTap: () => _editor.reveal(
                  DocumentRange(
                    _editor.document.positionAt(conflict.start),
                    _editor.document.positionAt(conflict.end),
                  ),
                ),
                subtitle: Wrap(
                  children: [
                    for (final (label, resolution) in [
                      ('Keep current', ChangeResolution.old),
                      ('Keep incoming', ChangeResolution.newer),
                      ('Keep both', ChangeResolution.both),
                    ])
                      TextButton(
                        onPressed: () =>
                            widget.controller.resolve(index, resolution),
                        child: Text(label),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
    ],
  );
  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _editor.dispose();
    super.dispose();
  }
}
