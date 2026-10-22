import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax/syntax.dart';
import 'editor.dart';
import 'styles.dart';
import 'chrome.dart';
import 'indexed_viewport.dart';
import 'horizontal_scroll.dart';
import 'line_selection.dart';
import 'selection_actions.dart';
import 'selection_action_overlay.dart';
import 'inline_comment_region.dart';
import 'comment_navigation.dart';

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
    this.commentNavigation,
    this.commentCountBuilder,
    this.annotationLineBuilder,
    this.gutterActionBuilder,
    this.onComment,
    this.commentSelection,
    this.commentBuilder,
    this.selectionActionBuilder,
    this.selectionActionStyle = const SelectionActionStyle(),
    this.onLineTap,
    this.onTokenTap,
    this.scrollController,
    this.executor,
    this.onVisibleLinesChanged,
    this.lineBackgroundBuilder,
    this.lineHeaderBuilder,
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

  /// Shared discussion counts, visibility and source navigation.
  final CommentNavigationController? commentNavigation;

  /// Replaces the unresolved count appended to the file header.
  final Widget Function(BuildContext, CommentNavigationDetails)?
  commentCountBuilder;

  /// Custom content below an annotated line.
  final Widget Function(BuildContext, LineAnnotation<Object?>)?
  annotationBuilder;

  /// Optional zero-based display line for a range annotation. By default it
  /// appears below the range start; applications can anchor notes at its end.
  final int Function(LineAnnotation<Object?>)? annotationLineBuilder;

  /// Custom per-line gutter actions.
  final Widget Function(BuildContext, int)? gutterActionBuilder;

  /// Opens an application-owned comment for the primary logical selection.
  /// Enables a button at its active line and configurable keyboard shortcuts.
  final ValueChanged<FileSelectionDetails>? onComment;

  /// Snapshot for an app-owned inline comment, independent of live selection.
  /// A stale source revision hides the composer; the application owns its draft.
  final FileSelectionDetails? commentSelection;

  /// Builds an inline editor below the last selected line in [commentSelection].
  /// Supports variable heights. Retain input controllers outside this builder
  /// so drafts survive scrolling, collapsing, and other row unmounts.
  final Widget Function(BuildContext, FileSelectionDetails)? commentBuilder;

  /// Replaces the selected line's action; returning null hides it.
  /// The widget is constrained to the source row and must supply its own
  /// callbacks and accessible labels. Native text selections are independent.
  final Widget? Function(BuildContext, FileSelectionDetails)?
  selectionActionBuilder;

  /// Icon, tooltip, placement, style and shortcuts for selection actions.
  final SelectionActionStyle selectionActionStyle;

  /// Called with a zero-based line number.
  final ValueChanged<int>? onLineTap;

  /// Called with the line and highlighted token that was clicked.
  final void Function(int, ThemedToken)? onTokenTap;

  /// Optional externally owned vertical scroll controller.
  final ScrollController? scrollController;

  /// Optional shared background executor. Omission uses bounded cooperative work.
  final HighlightExecutor? executor;

  /// Reports visible zero-based source lines as a half-open range after layout.
  final void Function(int startLine, int endLine)? onVisibleLinesChanged;

  /// Optional background for a zero-based source line, beneath selection.
  final Color? Function(int line)? lineBackgroundBuilder;

  /// Optional nonselectable content above a zero-based source line.
  final Widget? Function(BuildContext context, int line)? lineHeaderBuilder;
  @override
  State<SyntaxFileView> createState() => _SyntaxFileViewState();
}

class _SyntaxFileViewState extends State<SyntaxFileView> {
  late ScrollController _scroll;
  final _focus = FocusNode();
  DocumentSelection? _gutterSelection;
  int? _gutterRevision;
  HighlightExecutor? _ownedExecutor;
  PresentationController? _presentation;
  void _presentationChanged() {
    if (mounted) setState(() {});
  }

  void _viewportChanged(int start, int end) {
    _presentation?.setViewport(start, end);
    widget.onVisibleLinesChanged?.call(start, end);
  }

  final _horizontal = HorizontalCodeGroup();
  EditorController get editor => widget.controller;
  double get _height =>
      MediaQuery.textScalerOf(context).scale(widget.textStyle?.fontSize ?? 14) *
      (widget.textStyle?.height ?? 1.5);
  void _attach() {
    _horizontal
      ..offset = editor.horizontalOffset
      ..onChanged = (offset) => editor.horizontalOffset = offset;
    final executor =
        widget.executor ?? (_ownedExecutor = CooperativeHighlightExecutor());
    _presentation = PresentationController(
      editor: editor,
      highlighter: widget.highlighter,
      theme: widget.theme,
      executor: executor,
    )..addListener(_presentationChanged);
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
    _gutterSelection = null;
    _gutterRevision = null;
    _horizontal.onChanged = null;
    controller.removeListener(_changed);
    _presentation?.dispose();
    _presentation = null;
    _ownedExecutor?.dispose();
    _ownedExecutor = null;
    _scroll.removeListener(_scrolled);
    if (external == null) _scroll.dispose();
  }

  @override
  void initState() {
    super.initState();
    _attach();
    widget.commentNavigation?.addListener(_changed);
  }

  @override
  void didUpdateWidget(SyntaxFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentNavigation != widget.commentNavigation) {
      oldWidget.commentNavigation?.removeListener(_changed);
      widget.commentNavigation?.addListener(_changed);
    }
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

  void _selectLine(int line, {bool? extend}) {
    _focus.requestFocus();
    final doc = editor.document;
    final existing = editor.selections.first;
    final anchor = (extend ?? HardwareKeyboard.instance.isShiftPressed)
        ? doc.positionAt(existing.anchor).line
        : line;
    editor.selectLines(anchor, line);
    _gutterSelection = editor.selections.first;
    _gutterRevision = doc.revision;
    widget.onLineTap?.call(line);
  }

  FileSelectionDetails? _selectionDetails() {
    final selection = editor.selections.first;
    // An explicitly selected empty line is meaningful, unlike an idle caret.
    if (selection.isCollapsed &&
        (!identical(selection, _gutterSelection) ||
            editor.document.revision != _gutterRevision)) {
      return null;
    }
    return FileSelectionDetails(
      file: editor.file,
      selection: selection,
      anchorLine: editor.document.positionAt(selection.anchor).line,
      activeLine: editor.document.positionAt(selection.active).line,
    );
  }

  void _comment() {
    final details = _selectionDetails();
    if (details != null) widget.onComment?.call(details);
  }

  void _copy() {
    final text = editor.selections
        .map((s) => editor.document.text.substring(s.start, s.end))
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final doc = editor.document;
    final comment =
        widget.commentBuilder != null &&
            widget.commentSelection?.matches(editor.file) == true
        ? widget.commentSelection
        : null;
    final selection =
        widget.onComment != null || widget.selectionActionBuilder != null
        ? _selectionDetails()
        : null;
    final actionWidth =
        widget.onComment != null || widget.selectionActionBuilder != null
        ? widget.selectionActionStyle.gutterWidth
        : 0.0;
    final gutterWidth =
        actionWidth +
        (widget.showLineNumbers
            ? doc.lineCount.toString().length *
                      (widget.textStyle?.fontSize ?? 14) +
                  20
            : 0);
    final styles = TokenTextStyles(
      widget.theme,
      base: widget.textStyle ?? defaultCodeTextStyle,
    );
    return SyntaxChrome(
      theme: widget.theme,
      child: CallbackShortcuts(
        bindings: {
          if (widget.onComment != null)
            for (final shortcut in widget.selectionActionStyle.shortcuts)
              shortcut: _comment,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
        },
        child: Focus(
          focusNode: _focus,
          child: Material(
            color: widget.theme.backgroundColor,
            child: Column(
              children: [
                if (widget.showHeader)
                  commentFileHeader(
                    context,
                    widget.headerBuilder?.call(context, editor.file) ??
                        Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  editor.file.path,
                                  style: styles.base,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy selection',
                              onPressed: _copy,
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                    widget.commentNavigation,
                    editor.file.id,
                    widget.commentCountBuilder,
                  ),
                Expanded(
                  child: LineSelectionRegion(
                    controller: _scroll,
                    child: IndexedCodeViewport(
                      controller: _scroll,
                      count: doc.lineCount,
                      layoutKey: (
                        doc.id,
                        doc.revision,
                        widget.wrap,
                        widget.textStyle,
                        MediaQuery.textScalerOf(context),
                        widget.executor,
                        widget.highlighter.revision,
                        editor.annotations,
                        widget.commentNavigation?.filter,
                        widget.annotationLineBuilder,
                        editor.diagnostics,
                        editor.carets,
                        widget.lineHeaderBuilder,
                        gutterWidth,
                        comment,
                      ),
                      identity: doc.lineIdentity,
                      indexOf: doc.lineForIdentity,
                      estimatedHeight: _height.ceilToDouble(),
                      fixedHeight:
                          !widget.wrap &&
                          comment == null &&
                          editor.annotations.isEmpty &&
                          editor.diagnostics.isEmpty &&
                          editor.carets.isEmpty &&
                          widget.onTokenTap == null &&
                          widget.lineHeaderBuilder == null,
                      onVisibleRange: _viewportChanged,
                      revealRow: editor.revealTarget?.start.line,
                      revealRequest: editor.revealRequest,
                      builder: (context, line) {
                        final tokens = _presentation?.line(line);
                        final text = doc.lineText(line);
                        final start = doc.lineStart(line),
                            end = start + text.length;
                        final selected =
                            editor.selections.any(
                              (s) => s.start <= end && s.end > start,
                            ) ||
                            (selection?.activeLine == line);
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
                                          alignment:
                                              PlaceholderAlignment.baseline,
                                          baseline: TextBaseline.alphabetic,
                                          child: GestureDetector(
                                            onTap: () =>
                                                widget.onTokenTap!(line, token),
                                            child: Text(
                                              token.text,
                                              style: styles.base.merge(
                                                styles[token.style],
                                              ),
                                            ),
                                          ),
                                        ),
                                  ],
                          ),
                          softWrap: widget.wrap,
                        );
                        if (!widget.wrap) {
                          code = HorizontalCode(
                            group: _horizontal,
                            child: code,
                          );
                        }
                        code = SelectionArea(child: code);
                        final background =
                            widget.lineBackgroundBuilder?.call(line) ??
                            widget.theme.backgroundColor;
                        final header = widget.lineHeaderBuilder?.call(
                          context,
                          line,
                        );
                        return KeyedSubtree(
                          key: ValueKey(doc.lineIdentity(line)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (header != null)
                                SelectionContainer.disabled(child: header),
                              SelectionActionOverlay(
                                alignment:
                                    widget.selectionActionStyle.alignment,
                                action: selection?.activeLine != line
                                    ? null
                                    : widget.selectionActionBuilder != null
                                    ? widget.selectionActionBuilder!(
                                        context,
                                        selection!,
                                      )
                                    : defaultSelectionAction(
                                        widget.selectionActionStyle,
                                        () => widget.onComment!(selection!),
                                      ),
                                child: LineSelectionTarget(
                                  isGutter: (x, _) => x < gutterWidth,
                                  onSelect: (_, _, extend) =>
                                      _selectLine(line, extend: extend),
                                  child: Semantics(
                                    label: 'Line ${line + 1}',
                                    selected: selected,
                                    child: ColoredBox(
                                      color: selected
                                          ? Color.alphaBlend(
                                              widget.theme.selectionColor,
                                              background,
                                            )
                                          : background,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (gutterWidth > 0)
                                            SelectionContainer.disabled(
                                              child: Semantics(
                                                button: true,
                                                label:
                                                    'Select line ${line + 1}',
                                                onTap: () => _selectLine(line),
                                                excludeSemantics: true,
                                                child: MouseRegion(
                                                  cursor:
                                                      SystemMouseCursors.click,
                                                  child: SizedBox(
                                                    width: gutterWidth,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            right: 12,
                                                          ),
                                                      child: Text(
                                                        widget.showLineNumbers
                                                            ? '${line + 1}'
                                                            : '',
                                                        textAlign:
                                                            TextAlign.right,
                                                        style: styles.base
                                                            .copyWith(
                                                              color: widget
                                                                  .theme
                                                                  .lineNumberColor,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (widget.gutterActionBuilder !=
                                              null)
                                            SelectionContainer.disabled(
                                              child:
                                                  widget.gutterActionBuilder!(
                                                    context,
                                                    line,
                                                  ),
                                            ),
                                          Expanded(child: code),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              for (final d in editor.diagnostics)
                                if (d.start < end + 1 && d.end >= start)
                                  SelectionContainer.disabled(
                                    child: Text(
                                      d.message,
                                      style: TextStyle(
                                        color: widget.theme.diagnosticColor(
                                          d.severity,
                                        ),
                                      ),
                                    ),
                                  ),
                              if (comment != null && comment.endLine == line)
                                InlineCommentRegion(
                                  key: ValueKey(comment),
                                  child: widget.commentBuilder!(
                                    context,
                                    comment,
                                  ),
                                ),
                              for (final a in editor.annotations)
                                if ((widget.commentNavigation?.isVisible(
                                          a.data,
                                        ) ??
                                        true) &&
                                    (widget.annotationLineBuilder != null
                                        ? widget.annotationLineBuilder!(a) ==
                                              line
                                        : a.start >= start &&
                                              (a.start < end + 1 ||
                                                  line == doc.lineCount - 1)))
                                  SelectionContainer.disabled(
                                    child: CommentNavigationAnchor(
                                      controller: widget.commentNavigation,
                                      fileId: editor.file.id,
                                      annotationId: a.id,
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
                                  ),
                              for (final caret in editor.carets)
                                if (caret.selection.active >= start &&
                                    caret.selection.active <= end)
                                  SelectionContainer.disabled(
                                    child: Text(
                                      caret.label.isEmpty
                                          ? caret.id
                                          : caret.label,
                                      style: TextStyle(
                                        color: Color(caret.color),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.commentNavigation?.removeListener(_changed);
    _detach(editor, widget.scrollController);
    _focus.dispose();
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
    this.wrap = true,
    this.textStyle,
    this.onComment,
    this.commentSelection,
    this.commentBuilder,
    this.selectionActionBuilder,
    this.selectionActionStyle = const SelectionActionStyle(),
    this.annotationBuilder,
    this.commentNavigation,
    this.commentCountBuilder,
    this.annotationLineBuilder,
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

  /// Wraps source lines in each expanded file.
  final bool wrap;

  /// Code typography shared by file previews and editors.
  final TextStyle? textStyle;

  /// Application-owned comment action for selections in file previews.
  final ValueChanged<FileSelectionDetails>? onComment;

  /// Inline comment snapshot, routed to the matching file preview.
  final FileSelectionDetails? commentSelection;

  /// Builds the application's inline editor below its selected range.
  final Widget Function(BuildContext, FileSelectionDetails)? commentBuilder;

  /// Replaces a preview's selection action, or returns null to hide it.
  final Widget? Function(BuildContext, FileSelectionDetails)?
  selectionActionBuilder;

  /// Presentation and shortcuts shared by preview selection actions.
  final SelectionActionStyle selectionActionStyle;

  /// Shared discussion counts and filtering for retained file sessions.
  final CommentNavigationController? commentNavigation;

  /// Replaces each file header's unresolved discussion count.
  final Widget Function(BuildContext, CommentNavigationDetails)?
  commentCountBuilder;

  /// Application-owned annotation content below preview source lines.
  final Widget Function(BuildContext, LineAnnotation<Object?>)?
  annotationBuilder;

  /// Optional zero-based anchor for range annotations in file previews.
  final int Function(LineAnnotation<Object?>)? annotationLineBuilder;
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
    widget.commentNavigation?.addListener(_changed);
  }

  @override
  void didUpdateWidget(SyntaxFileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentNavigation != widget.commentNavigation) {
      oldWidget.commentNavigation?.removeListener(_changed);
      widget.commentNavigation?.addListener(_changed);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  Widget build(BuildContext context) => SyntaxChrome(
    theme: widget.theme,
    child: IndexedCodeViewport(
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
            commentFileHeader(
              context,
              ListTile(
                title: Text(file.path),
                trailing: Icon(
                  widget.controller.isCollapsed(file.id)
                      ? Icons.expand_more
                      : Icons.expand_less,
                ),
                onTap: () => widget.controller.toggle(file.id),
              ),
              widget.commentNavigation,
              file.id,
              widget.commentCountBuilder,
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
    ),
  );
  @override
  void dispose() {
    widget.commentNavigation?.removeListener(_changed);
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
            textStyle: owner.textStyle,
            wrap: owner.wrap,
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
            textStyle: owner.textStyle,
            wrap: owner.wrap,
            showHeader: false,
            onComment: owner.onComment,
            commentSelection: owner.commentSelection,
            commentBuilder: owner.commentBuilder,
            selectionActionBuilder: owner.selectionActionBuilder,
            selectionActionStyle: owner.selectionActionStyle,
            annotationBuilder: owner.annotationBuilder,
            commentNavigation: owner.commentNavigation,
            annotationLineBuilder: owner.annotationLineBuilder,
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
    this.wrap = true,
    this.textStyle,
  });

  /// Producer and live document.
  final StreamDocumentController controller;

  /// Registered grammars.
  final Highlighter highlighter;

  /// Current palette.
  final SyntaxTheme theme;

  /// Wraps incoming source lines instead of scrolling horizontally.
  final bool wrap;

  /// Code typography, preserved across streaming updates.
  final TextStyle? textStyle;
  @override
  Widget build(BuildContext context) => SyntaxFileView(
    controller: controller.editor,
    highlighter: highlighter,
    theme: theme,
    wrap: wrap,
    textStyle: textStyle,
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
    this.wrap = true,
    this.textStyle,
    this.showLineNumbers = true,
  });

  /// Parsed conflicts and resolution commands.
  final MergeController controller;

  /// Registered grammars.
  final Highlighter highlighter;

  /// Current palette, including optional standard `merge.*` editor colors.
  final SyntaxTheme theme;

  /// Wraps long source lines.
  final bool wrap;

  /// Optional code typography, shared with the surrounding file views.
  final TextStyle? textStyle;

  /// Shows original source line numbers, including marker lines.
  final bool showLineNumbers;

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

  Widget _sectionHeader(
    int index,
    MergeConflictSection section,
    MergeSectionColors colors,
  ) {
    final conflict = widget.controller.conflicts[index];
    final (title, label) = switch (section.kind) {
      MergeSectionKind.current => ('Current change', conflict.currentLabel),
      MergeSectionKind.base => ('Common ancestor', ''),
      MergeSectionKind.incoming => ('Incoming change', conflict.incomingLabel),
    };
    return Container(
      key: ValueKey(('merge-section', section.start)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Color(colors.header),
        border: Border(left: BorderSide(color: Color(colors.border), width: 3)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          Semantics(
            header: true,
            child: Text(
              label.isEmpty ? title : '$title · $label',
              style: TextStyle(
                color: widget.theme.foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (section.kind != MergeSectionKind.base)
            Wrap(
              spacing: 4,
              children: [
                for (final (label, resolution) in [
                  if (section.kind == MergeSectionKind.current) ...[
                    ('Keep current', ChangeResolution.old),
                    ('Keep both', ChangeResolution.both),
                  ] else
                    ('Keep incoming', ChangeResolution.newer),
                ])
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: widget.theme.foregroundColor,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () =>
                        widget.controller.resolve(index, resolution),
                    child: Text(label),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final merge = widget.controller;
    final colors = MergeColors.of(widget.theme);
    final headers = <int, (int, MergeConflictSection)>{
      for (var index = 0; index < merge.conflicts.length; index++)
        for (final section in merge.conflicts[index].sections)
          section.start: (index, section),
    };
    return ColoredBox(
      color: widget.theme.backgroundColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    merge.file.path,
                    style: TextStyle(color: widget.theme.foregroundColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  merge.conflicts.isEmpty
                      ? 'All conflicts resolved'
                      : '${merge.conflicts.length} conflict${merge.conflicts.length == 1 ? '' : 's'} remaining',
                  style: TextStyle(
                    color: widget.theme.foregroundColor,
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy selection',
                  color: widget.theme.foregroundColor,
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: _editor.selections
                          .map(
                            (s) =>
                                _editor.document.text.substring(s.start, s.end),
                          )
                          .join('\n'),
                    ),
                  ),
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: SyntaxFileView(
              controller: _editor,
              highlighter: widget.highlighter,
              theme: widget.theme,
              wrap: widget.wrap,
              textStyle: widget.textStyle,
              showLineNumbers: widget.showLineNumbers,
              showHeader: false,
              lineBackgroundBuilder: (line) {
                final section = merge.sectionAt(
                  _editor.document.lineStart(line),
                );
                return section == null
                    ? null
                    : Color(colors.forSection(section.kind).background);
              },
              lineHeaderBuilder: (context, line) {
                final header = headers[_editor.document.lineStart(line)];
                return header == null
                    ? null
                    : _sectionHeader(
                        header.$1,
                        header.$2,
                        colors.forSection(header.$2.kind),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _editor.dispose();
    super.dispose();
  }
}
