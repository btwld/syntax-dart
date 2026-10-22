import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax_flutter/syntax_flutter.dart';
import 'comment_threads.dart';

const interactionBefore = '''String formatName(String name) {
  final cleaned = name.trim();
  return cleaned;
}

// Retry configuration is shared by every request.
// Keep the delay bounded for interactive clients.
int retryDelay(int attempt) {
  final delay = attempt * 100;
  return delay;
}

// Only retry failures that can recover.
// Authentication failures need a new session.
bool shouldRetry(int status) {
  return status == 500;
}
''';
const interactionAfter = '''String formatName(String name) {
  final cleaned = name.trim();
  return cleaned.isEmpty ? 'Guest' : cleaned;
}

// Retry configuration is shared by every request.
// Keep the delay bounded for interactive clients.
int retryDelay(int attempt) {
  final delay = attempt * 200;
  return delay.clamp(200, 2000);
}

// Only retry failures that can recover.
// Authentication failures need a new session.
bool shouldRetry(int status) {
  return status == 429 || status >= 500;
}
''';

PatchController interactionReview() {
  final diff = diffTexts(
    interactionBefore,
    interactionAfter,
    path: 'lib/request_policy.dart',
    id: 'policy',
    contextLines: 1,
  );
  const names = [
    'formatName(String name)',
    'retryDelay(int attempt)',
    'shouldRetry(int status)',
  ];
  return PatchController(
    [
      diff.copyWith(
        hunks: [
          for (final (i, h) in diff.hunks.indexed)
            DiffHunk(
              oldStart: h.oldStart,
              oldCount: h.oldCount,
              newStart: h.newStart,
              newCount: h.newCount,
              lines: h.lines,
              section: names[i],
            ),
        ],
      ),
    ],
    expansionLineCount: 2,
    foldableHunks: true,
  );
}

/// Focused examples of public review APIs, sharing the main gallery's palette.
class InteractionExamples extends StatefulWidget {
  const InteractionExamples({
    super.key,
    required this.kind,
    required this.theme,
    required this.textStyle,
    this.fontStyles = const {},
  });
  final int kind;
  final SyntaxTheme theme;
  final TextStyle textStyle;
  final Map<String, TextStyle> fontStyles;
  @override
  State<InteractionExamples> createState() => _InteractionExamplesHostState();
}

class _InteractionExamplesHostState extends State<InteractionExamples> {
  int reset = 0;
  @override
  Widget build(BuildContext context) => _InteractionExample(
    key: ValueKey((widget.kind, reset)),
    kind: widget.kind,
    theme: widget.theme,
    textStyle: widget.textStyle,
    fontStyles: widget.fontStyles,
    onReset: () => setState(() => reset++),
  );
}

class _InteractionExample extends StatefulWidget {
  const _InteractionExample({
    super.key,
    required this.kind,
    required this.theme,
    required this.textStyle,
    required this.fontStyles,
    required this.onReset,
  });
  final int kind;
  final SyntaxTheme theme;
  final TextStyle textStyle;
  final Map<String, TextStyle> fontStyles;
  final VoidCallback onReset;
  @override
  State<_InteractionExample> createState() => _InteractionExamplesState();
}

class _InteractionExamplesState extends State<_InteractionExample> {
  final highlighter = Highlighter(languages: [dartLanguage]);
  late final review = interactionReview()..addListener(changed);
  late final file = EditorController(
    file: const SourceFile(
      id: 'source',
      path: 'lib/request_policy.dart',
      text: interactionAfter,
    ),
  )..addListener(changed);
  final fileCommentInput = TextEditingController();
  final diffCommentInput = TextEditingController();
  final fileCommentFocus = FocusNode();
  final diffCommentFocus = FocusNode();
  TextEditingController get commentInput =>
      fileMode ? fileCommentInput : diffCommentInput;
  FocusNode get commentFocus => fileMode ? fileCommentFocus : diffCommentFocus;
  FileSelectionDetails? fileComment;
  DiffSelectionDetails? diffComment;
  bool customComposer = false, customThreads = false;
  final threads = ExampleCommentThreads();
  late final diffComments = CommentNavigationController.patch(review);
  late final fileComments = CommentNavigationController.file(
    file,
    annotationLine: (a) => file.document.positionAt(a.end).line,
  );
  CommentNavigationController get comments =>
      fileMode ? fileComments : diffComments;
  final oldInput = TextEditingController(text: interactionBefore);
  final newInput = TextEditingController(text: interactionAfter);
  bool fileMode = false,
      wrap = true,
      numbers = true,
      backgrounds = true,
      customHeader = true,
      customSelectionAction = false;
  DiffIndicators indicators = DiffIndicators.classic;
  HunkSeparatorStyle separators = HunkSeparatorStyle.lineInfo;
  InlineDiffMode comparison = InlineDiffMode.mergedWords;
  double? fontSize;
  String fontName = 'Default';
  String? status;
  String get help => switch (widget.kind) {
    0 =>
      'Drag line numbers, then click the comment icon or press Ctrl/Cmd+Shift+M. Shift-click extends a range.',
    1 => 'Click a section name to fold it. Reset restores accepted changes.',
    2 => 'Appearance settings affect this sample only.',
    3 => 'Select a line or activate a token to inspect its details.',
    4 => 'Click the custom header to collapse or expand the file.',
    _ => 'Edit either source, then compare to refresh the diff.',
  };
  String? inspected;
  void changed() {
    if (mounted) setState(() {});
  }

  void selectPreset({bool cross = false}) {
    if (fileMode && widget.kind == 0) {
      file.selectLines(1, 3);
    } else {
      review.select(
        DiffSelection(
          'policy',
          cross ? DiffSide.old : DiffSide.newer,
          2,
          4,
          activeSide: DiffSide.newer,
        ),
      );
      review.revealLine('policy', 2);
    }
  }

  String get selectionText => fileMode && widget.kind == 0
      ? file.document.text.substring(
          file.selections.first.start,
          file.selections.first.end,
        )
      : review.selectedText();
  String get selectionLabel {
    if (fileMode && widget.kind == 0) {
      final s = file.selections.first;
      return s.isCollapsed
          ? 'No selection'
          : 'Lines ${file.document.positionAt(s.anchor).line + 1} → ${file.document.positionAt(s.active).line + 1}';
    }
    final s = review.selection;
    return s == null
        ? 'No selection'
        : '${s.side == DiffSide.old ? 'Old' : 'New'} ${s.anchor} → ${s.activeSide == DiffSide.old ? 'old' : 'new'} ${s.active}';
  }

  Future<void> copy() async {
    await Clipboard.setData(ClipboardData(text: selectionText));
    if (mounted) {
      setState(() => status = 'Copied source without gutters or review notes.');
    }
  }

  void annotate({FileSelectionDetails? source, DiffSelectionDetails? diff}) {
    var reveal = source == null && diff == null;
    if (source == null && diff == null) {
      if (fileMode) {
        final selection = file.selections.first;
        source = FileSelectionDetails(
          file: file.file,
          selection: selection,
          anchorLine: file.document.positionAt(selection.anchor).line,
          activeLine: file.document.positionAt(selection.active).line,
        );
      } else {
        final selection = review.selection;
        if (selection == null) return;
        diff = DiffSelectionDetails(
          file: review.file(selection.fileId),
          selection: selection,
        );
      }
    }
    if (source != null && fileComment?.matches(file.file) == true) {
      source = fileComment;
      reveal = true;
    } else if (diff != null &&
        diffComment != null &&
        review.files.any(diffComment!.matches)) {
      diff = diffComment;
      reveal = true;
    } else {
      commentInput.clear();
      setState(() {
        if (source != null) fileComment = source;
        if (diff != null) diffComment = diff;
      });
    }
    commentFocus.requestFocus();
    if (!reveal) {
      // Preserve visible code. A reverse selection can end offscreen, in which
      // case the input is not mounted and needs an explicit reveal next frame.
      final focus = commentFocus;
      final pendingSource = source, pendingDiff = diff;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || focus.context != null) return;
        if ((pendingSource != null && identical(fileComment, pendingSource)) ||
            (pendingDiff != null && identical(diffComment, pendingDiff))) {
          annotate(source: pendingSource, diff: pendingDiff);
        }
      });
      return;
    }
    if (source != null) {
      file.reveal(
        DocumentRange(
          DocumentPosition(source.endLine, 0),
          DocumentPosition(source.endLine, 0),
        ),
      );
    } else {
      final endpoint = diff!.endIn(review.mode);
      review.revealLine(diff.file.id, endpoint.line, side: endpoint.side);
    }
  }

  void cancelComment() {
    commentInput.clear();
    setState(() {
      if (fileMode) {
        fileComment = null;
      } else {
        diffComment = null;
      }
    });
  }

  void submitComment(String text) {
    final source = fileMode ? fileComment : null;
    final diff = fileMode ? null : diffComment;
    if (source == null && diff == null) return;
    final thread = threads.create(text);
    if (source != null) {
      if (!source.matches(file.file)) return;
      file.setAnnotations([
        ...file.annotations,
        LineAnnotation(
          id: thread.id,
          start: source.selection.start,
          end: source.selection.end,
          data: thread,
        ),
      ]);
      cancelComment();
      return;
    }
    if (!review.files.any(diff!.matches)) return;
    final s = diff.selection;
    final endpoint = diff.endIn(review.mode);
    review.setAnnotations([
      ...review.annotations,
      ReviewAnnotation(
        id: thread.id,
        fileId: s.fileId,
        side: endpoint.side,
        line: endpoint.line,
        data: thread,
      ),
    ]);
    cancelComment();
  }

  Widget composer() => SyntaxCommentComposer(
    controller: commentInput,
    focusNode: commentFocus,
    onSubmit: submitComment,
    onCancel: cancelComment,
    submitLabel: 'Add note',
    inputBuilder: customComposer
        ? (context, details) => TextField(
            controller: details.controller,
            focusNode: details.focusNode,
            autofocus: true,
            enabled: !details.isSubmitting,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Your feedback',
              prefixIcon: Icon(Icons.forum_outlined),
              filled: true,
              border: OutlineInputBorder(),
            ),
          )
        : null,
    actionsBuilder: customComposer
        ? (context, details) => Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: details.isSubmitting
                    ? null
                    : details.controller.clear,
                child: const Text('Clear draft'),
              ),
              TextButton(
                onPressed: details.cancel,
                child: const Text('Discard'),
              ),
              FilledButton.icon(
                onPressed: details.submit,
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('Post note'),
              ),
            ],
          )
        : null,
  );

  Widget customAction(VoidCallback comment) => Tooltip(
    message: 'Discuss this selection',
    child: TextButton.icon(
      onPressed: comment,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xff7258d6),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 20),
        fixedSize: const Size(76, 20),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.forum_outlined, size: 13),
      label: const Text('Discuss', style: TextStyle(fontSize: 11)),
    ),
  );

  Widget fileThread(LineAnnotation<Object?> annotation) => threads.view(
    annotation.data! as ReviewThread,
    custom: customThreads,
    onChanged: (thread) => file.setAnnotations([
      for (final current in file.annotations)
        if (current.id != annotation.id)
          current
        else if (thread.comments.isNotEmpty)
          LineAnnotation(
            id: current.id,
            start: current.start,
            end: current.end,
            data: thread,
          ),
    ]),
  );

  Widget diffThread(ReviewAnnotation<Object?> annotation) => threads.view(
    annotation.data! as ReviewThread,
    custom: customThreads,
    onChanged: (thread) => review.setAnnotations([
      for (final current in review.annotations)
        if (current.id != annotation.id)
          current
        else if (thread.comments.isNotEmpty)
          ReviewAnnotation(
            id: current.id,
            fileId: current.fileId,
            side: current.side,
            line: current.line,
            data: thread,
          ),
    ]),
  );

  Widget button(String label, VoidCallback? action) =>
      TextButton(onPressed: action, child: Text(label));
  Widget menu<T>(
    String label,
    T value,
    List<T> values,
    void Function(T) set,
    String Function(T) name,
  ) => DropdownButton<T>(
    value: value,
    underline: const SizedBox(),
    isDense: true,
    hint: Text(label),
    items: [
      for (final item in values)
        DropdownMenuItem(
          value: item,
          child: Text(
            '$label: ${name(item)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ],
    onChanged: (item) {
      if (item != null) setState(() => set(item));
    },
  );
  Widget get controls => Padding(
    padding: const EdgeInsets.all(12),
    child: Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.kind == 0) ...[
          button(
            fileMode ? 'Show diff' : 'Show file',
            () => setState(() => fileMode = !fileMode),
          ),
          button('Select lines 2–4', selectPreset),
          if (!fileMode)
            button('Select across sides', () => selectPreset(cross: true)),
          button('Clear selection', () {
            review.select(null);
            file.setSelections([]);
          }),
          button('Copy selection', selectionText.isEmpty ? null : copy),
          button(
            'Add comment',
            (fileMode
                    ? file.selections.first.isCollapsed
                    : review.selection == null)
                ? null
                : annotate,
          ),
          button(
            customSelectionAction
                ? 'Default comment icon'
                : 'Custom comment action',
            () =>
                setState(() => customSelectionAction = !customSelectionAction),
          ),
          button(
            customComposer ? 'Default composer' : 'Custom composer',
            () => setState(() => customComposer = !customComposer),
          ),
          button(
            customThreads ? 'Default threads' : 'Custom threads',
            () => setState(() => customThreads = !customThreads),
          ),
          Text(selectionLabel, style: const TextStyle(fontSize: 12)),
        ],
        if (widget.kind == 1) ...[
          button('Fold all sections', () => review.setHunksCollapsed(true)),
          button('Expand all sections', () => review.setHunksCollapsed(false)),
          button('Jump to retryDelay', () => review.revealLine('policy', 9)),
          button('Expand context', review.expandAll),
          button('Collapse context', review.collapseContext),
        ],
        if (widget.kind == 1 || widget.kind == 2)
          menu(
            'Separators',
            separators,
            HunkSeparatorStyle.values,
            (v) => separators = v,
            (v) => switch (v) {
              HunkSeparatorStyle.lineInfo => 'Line info',
              HunkSeparatorStyle.compact => 'Compact',
              HunkSeparatorStyle.metadata => 'Patch metadata',
              HunkSeparatorStyle.minimal => 'Minimal',
            },
          ),
        if (widget.kind == 2) ...[
          menu(
            'Markers',
            indicators,
            DiffIndicators.values,
            (v) => indicators = v,
            (v) => v.name,
          ),
          menu(
            'Inline',
            comparison,
            InlineDiffMode.values,
            (v) => comparison = v,
            (v) => v.name,
          ),
          button(
            numbers ? 'Hide numbers' : 'Show numbers',
            () => setState(() => numbers = !numbers),
          ),
          button(
            backgrounds ? 'Hide backgrounds' : 'Show backgrounds',
            () => setState(() => backgrounds = !backgrounds),
          ),
          menu(
            'Size',
            fontSize ?? widget.textStyle.fontSize ?? 13,
            ({11.0, 13.0, 16.0, 19.0, widget.textStyle.fontSize ?? 13}.toList()
              ..sort()),
            (v) => fontSize = v,
            (v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v',
          ),
          menu(
            'Font',
            fontName,
            ['Default', ...widget.fontStyles.keys],
            (v) => fontName = v,
            (v) => v,
          ),
        ],
        if (widget.kind == 3)
          button('Inspect selected line', () {
            final s = review.selection;
            if (s == null) {
              selectPreset();
            }
            final selected = review.selection!;
            final source = review.file(selected.fileId);
            final text = (selected.activeSide == DiffSide.old
                ? source.oldLines
                : source.newLines)![selected.active - 1];
            setState(() => inspected = 'Line ${selected.active}: $text');
          }),
        if (widget.kind == 4)
          button(
            customHeader ? 'Default header' : 'Custom header',
            () => setState(() => customHeader = !customHeader),
          ),
        if (widget.kind != 0 || !fileMode)
          button(
            review.mode == DiffMode.unified ? 'Split view' : 'Unified view',
            () => review.mode = review.mode == DiffMode.unified
                ? DiffMode.split
                : DiffMode.unified,
          ),
        button(
          wrap ? 'Wrap on' : 'Wrap off',
          () => setState(() => wrap = !wrap),
        ),
        button('Reset example', widget.onReset),
      ],
    ),
  );

  String tokenHelp(FileDiff source, DiffLine line, DiffSegment segment) =>
      '${segment.text.trim().isEmpty ? 'Whitespace' : segment.text}\n${segment.changed ? 'Changed token' : 'Syntax token'} · line ${line.newNumber ?? line.oldNumber}\nColor #${segment.style.foreground.toRadixString(16).substring(2)}';

  @override
  Widget build(BuildContext context) {
    final style = (widget.fontStyles[fontName] ?? widget.textStyle).copyWith(
      fontSize: fontSize,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.kind == 5)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final (label, input) in [
                      ('Original source', oldInput),
                      ('Updated source', newInput),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: TextField(
                            controller: input,
                            minLines: 3,
                            maxLines: 3,
                            style: style,
                            decoration: InputDecoration(
                              labelText: label,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                button('Compare sources', () {
                  review.setFiles([
                    diffTexts(
                      oldInput.text,
                      newInput.text,
                      path: 'comparison.dart',
                      id: 'policy',
                    ),
                  ]);
                  setState(
                    () => status = 'Comparison updated from your input.',
                  );
                }),
              ],
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: Column(
              children: [
                controls,
                if (widget.kind == 0)
                  SyntaxCommentNavigation(
                    controller: comments,
                    countBuilder: customThreads
                        ? (_, details) =>
                              Text('Needs attention: ${details.unresolved}')
                        : null,
                    actionsBuilder: customThreads
                        ? (_, details) => Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              button('Previous thread', details.previous),
                              Text(
                                '${details.position} / ${details.visible.length}',
                              ),
                              button('Next thread', details.next),
                              FilterChip(
                                label: const Text('Hide resolved'),
                                selected:
                                    details.controller.filter ==
                                    CommentThreadFilter.unresolved,
                                onSelected: (hide) => details.setFilter(
                                  hide
                                      ? CommentThreadFilter.unresolved
                                      : CommentThreadFilter.all,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (widget.kind == 3)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              inspected ??
                  'Hover a token for details. Click it, or Tab to it and press Enter, to pin the details below.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        Expanded(
          child: fileMode && widget.kind == 0
              ? SyntaxFileView(
                  controller: file,
                  highlighter: highlighter,
                  theme: widget.theme,
                  textStyle: style,
                  wrap: wrap,
                  onComment: (selection) => annotate(source: selection),
                  commentSelection: fileComment,
                  annotationLineBuilder: (annotation) =>
                      file.document.positionAt(annotation.end).line,
                  commentBuilder: (context, selection) => composer(),
                  commentNavigation: fileComments,
                  commentCountBuilder: customThreads
                      ? (_, details) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('${details.unresolved} to review'),
                        )
                      : null,
                  annotationBuilder: (context, annotation) =>
                      fileThread(annotation),
                  selectionActionStyle: SelectionActionStyle(
                    gutterWidth: customSelectionAction ? 80 : 24,
                  ),
                  selectionActionBuilder: customSelectionAction
                      ? (context, selection) =>
                            customAction(() => annotate(source: selection))
                      : null,
                )
              : PatchView.controlled(
                  controller: review,
                  onComment: (selection) => annotate(diff: selection),
                  commentSelection: diffComment,
                  commentBuilder: (context, selection) => composer(),
                  commentNavigation: diffComments,
                  commentCountBuilder: customThreads
                      ? (_, details) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('${details.unresolved} to review'),
                        )
                      : null,
                  annotationBuilder: (context, annotation) =>
                      diffThread(annotation),
                  selectionActionStyle: SelectionActionStyle(
                    gutterWidth: customSelectionAction ? 80 : 24,
                  ),
                  selectionActionBuilder: customSelectionAction
                      ? (context, selection) =>
                            customAction(() => annotate(diff: selection))
                      : null,
                  highlighter: highlighter,
                  theme: widget.theme,
                  textStyle: style,
                  wrap: wrap,
                  inlineDiffMode: comparison,
                  showBackgrounds: backgrounds,
                  indicators: indicators,
                  showLineNumbers: numbers,
                  hunkSeparatorStyle: separators,
                  showReviewActions: widget.kind == 1,
                  tokenTooltip: widget.kind == 3 ? tokenHelp : null,
                  onTokenTap: widget.kind == 3
                      ? (f, l, t) =>
                            setState(() => inspected = tokenHelp(f, l, t))
                      : null,
                  headerBuilder: widget.kind == 4 && customHeader
                      ? (context, source, collapsed, toggle) => Material(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: ListTile(
                            textColor: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            iconColor: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            leading: const Icon(Icons.description_outlined),
                            title: Text(source.path),
                            subtitle: Text(
                              '${source.additions} additions · ${source.deletions} deletions',
                            ),
                            trailing: IconButton(
                              tooltip: collapsed
                                  ? 'Expand custom file'
                                  : 'Collapse custom file',
                              onPressed: toggle,
                              icon: Icon(
                                collapsed
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                              ),
                            ),
                            onTap: toggle,
                          ),
                        )
                      : null,
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(status ?? help, style: const TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    review.removeListener(changed);
    file.removeListener(changed);
    diffComments.dispose();
    fileComments.dispose();
    review.dispose();
    file.dispose();
    threads.dispose();
    fileCommentInput.dispose();
    diffCommentInput.dispose();
    fileCommentFocus.dispose();
    diffCommentFocus.dispose();
    oldInput.dispose();
    newInput.dispose();
    super.dispose();
  }
}
