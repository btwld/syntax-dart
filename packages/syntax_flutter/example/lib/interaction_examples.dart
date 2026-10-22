import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

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
  final oldInput = TextEditingController(text: interactionBefore);
  final newInput = TextEditingController(text: interactionAfter);
  bool fileMode = false,
      wrap = true,
      numbers = true,
      backgrounds = true,
      customHeader = true;
  DiffIndicators indicators = DiffIndicators.classic;
  HunkSeparatorStyle separators = HunkSeparatorStyle.lineInfo;
  InlineDiffMode comparison = InlineDiffMode.mergedWords;
  double? fontSize;
  String fontName = 'Default';
  String? status;
  String get help => switch (widget.kind) {
    0 => 'Drag line numbers or Shift-click to extend a range.',
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

  Future<void> annotate() async {
    var note = '';
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comment on selection'),
        content: TextField(
          onChanged: (value) => note = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Review note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, note),
            child: const Text('Add note'),
          ),
        ],
      ),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    final s = review.selection;
    if (s == null) return;
    review.setAnnotations([
      ...review.annotations,
      ReviewAnnotation(
        id: 'note-${review.annotations.length}',
        fileId: s.fileId,
        side: s.activeSide,
        line: s.active,
        data: text,
      ),
    ]);
  }

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
          if (!fileMode)
            button('Add comment', review.selection == null ? null : annotate),
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
          child: SingleChildScrollView(child: controls),
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
                )
              : PatchView.controlled(
                  controller: review,
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
    review.dispose();
    file.dispose();
    oldInput.dispose();
    newInput.dispose();
    super.dispose();
  }
}
