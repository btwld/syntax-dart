import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

/// Interactive examples of persistent file, review, merge and stream sessions.
class WorkflowsDemo extends StatefulWidget {
  const WorkflowsDemo({super.key});
  @override
  State<WorkflowsDemo> createState() => _WorkflowsDemoState();
}

class _WorkflowsDemoState extends State<WorkflowsDemo> {
  final _highlighter = Highlighter(languages: [dartLanguage]);
  late final _pool = HighlightPool(
    executor: kIsWeb
        ? createBrowserHighlightExecutor(
            workerUri: const bool.fromEnvironment('SYNTAX_WORKER')
                ? Uri.base.resolve('highlight_worker.js')
                : null,
          )
        : createNativeHighlightExecutor(),
    cacheSize: 4,
  );
  late final _editor = EditorController(
    file: const SourceFile(
      id: 'editor',
      path: 'editable.dart',
      text: 'void main() {\n  // TODO: greet\n  print("Hello");\n}\n',
    ),
    proposalProvider: (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      request.cancellation.throwIfCancelled();
      final index = request.file.text.indexOf('TODO');
      return index < 0 ? [] : [OffsetEdit(index, index + 4, 'DONE')];
    },
  );
  late final _files = FileListController([
    for (var i = 0; i < 12; i++)
      SourceFile(
        id: 'file-$i',
        path: 'example_$i.dart',
        text: 'final value$i = $i;\n',
      ),
  ], sessionLimit: 4);
  late final _large = EditorController(
    file: SourceFile(
      id: 'large',
      path: 'large.dart',
      text: [for (var i = 0; i < 100000; i++) 'final value$i = $i;'].join('\n'),
    ),
  );
  static const _before = 'void main() {\n  print("Hello");\n}\n';
  static const _after = 'void main() {\n  print("Hello, world!");\n}\n';
  late final _patch = PatchController(
    [
      parsePatch(
        renderPatch(diffTexts(_before, _after, path: 'partial.dart')),
      ).single.copyWith(identity: 'partial'),
      for (var i = 1; i < 1000; i++)
        diffTexts(
          'final value = $i;\n',
          'final value = ${i + 1};\n',
          path: 'change_$i.dart',
          id: 'change-$i',
        ),
    ],
    contentsLoader: (_, cancellation) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      cancellation.throwIfCancelled();
      return (oldText: _before, newText: _after);
    },
  );
  final _merge = MergeController(
    const SourceFile(
      id: 'merge',
      path: 'merge.dart',
      text:
          'void main() {\n<<<<<<< current\n  print("Current");\n||||||| base\n  print("Base");\n=======\n  print("Incoming");\n>>>>>>> incoming\n}\n',
    ),
  );
  final _stream = StreamDocumentController(
    const SourceFile(id: 'stream', path: 'live.dart', text: ''),
  );
  Timer? _timer;
  int _streamLine = 0, _tab = 0;
  bool _wrap = true, _dark = true, _backgrounds = true, _indicators = true;
  InlineDiffMode _comparison = InlineDiffMode.mergedWords;
  SyntaxPaletteVariant _variant = SyntaxPaletteVariant.standard;
  SyntaxTheme get _theme => createSyntaxTheme(dark: _dark, variant: _variant);
  @override
  void initState() {
    super.initState();
    _editor.setDiagnostics([
      const Diagnostic(
        start: 18,
        end: 22,
        message: 'Replace the TODO marker to clear this diagnostic',
        severity: DiagnosticSeverity.information,
      ),
    ]);
    _editor.setAnnotations([
      const LineAnnotation(
        id: 'note',
        start: 16,
        end: 30,
        data: 'This annotation follows edits.',
      ),
    ]);
    _editor.setCarets([
      const RemoteCaret(
        id: 'reviewer',
        label: 'Reviewer',
        selection: DocumentSelection.collapsed(16),
        color: 0xff4c9eff,
      ),
    ]);
    _patch.setAnnotations([
      const ReviewAnnotation(
        id: 'review',
        fileId: 'partial',
        side: DiffSide.newer,
        line: 2,
        data: 'Review the greeting, then load full contents to accept or edit.',
      ),
    ]);
  }

  void _startStream() {
    if (_timer != null || _stream.isComplete || _stream.isCancelled) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_streamLine >= 100) {
        timer.cancel();
        _stream.finish();
        setState(() {});
        return;
      }
      _stream.add('final streamed$_streamLine = ${_streamLine++};\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files and review workflows'),
        actions: [
          IconButton(
            tooltip: 'Switch light and dark',
            onPressed: () => setState(() => _dark = !_dark),
            icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (index, name) in [
                'Editor',
                'Files',
                'Patch',
                'Conflicts',
                'Streaming',
                '100,000 lines',
              ].indexed)
                ChoiceChip(
                  label: Text(name),
                  selected: _tab == index,
                  onSelected: (_) => setState(() => _tab = index),
                ),
              FilterChip(
                label: const Text('Wrap'),
                selected: _wrap,
                onSelected: (value) => setState(() => _wrap = value),
              ),
              DropdownButton<SyntaxPaletteVariant>(
                value: _variant,
                items: [
                  for (final value in SyntaxPaletteVariant.values)
                    DropdownMenuItem(value: value, child: Text(value.name)),
                ],
                onChanged: (value) => setState(() => _variant = value!),
              ),
            ],
          ),
          if (_tab == 2)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => _patch.setMode(
                      _patch.mode == DiffMode.unified
                          ? DiffMode.split
                          : DiffMode.unified,
                    ),
                  ),
                  child: Text(_patch.mode.name),
                ),
                DropdownButton<InlineDiffMode>(
                  value: _comparison,
                  items: [
                    for (final value in InlineDiffMode.values)
                      DropdownMenuItem(value: value, child: Text(value.name)),
                  ],
                  onChanged: (value) => setState(() => _comparison = value!),
                ),
                FilterChip(
                  label: const Text('Backgrounds'),
                  selected: _backgrounds,
                  onSelected: (value) => setState(() => _backgrounds = value),
                ),
                FilterChip(
                  label: const Text('Indicators'),
                  selected: _indicators,
                  onSelected: (value) => setState(() => _indicators = value),
                ),
                TextButton(
                  onPressed: () => _patch.revealLine('change-900', 1),
                  child: const Text('Go to file 900'),
                ),
              ],
            ),
          if (_tab == 4)
            Row(
              children: [
                TextButton(
                  onPressed: _startStream,
                  child: const Text('Start stream'),
                ),
                TextButton(
                  onPressed: () {
                    _timer?.cancel();
                    _stream.cancel();
                  },
                  child: const Text('Cancel stream'),
                ),
              ],
            ),
          if (_tab == 5)
            Row(
              children: [
                TextButton(
                  onPressed: () => _large.reveal(
                    const DocumentRange(
                      DocumentPosition(90000, 0),
                      DocumentPosition(90000, 10),
                    ),
                  ),
                  child: const Text('Go to line 90,001'),
                ),
                TextButton(
                  onPressed: () => _large.reveal(
                    const DocumentRange(
                      DocumentPosition(0, 0),
                      DocumentPosition(0, 0),
                    ),
                  ),
                  child: const Text('Back to top'),
                ),
              ],
            ),
          Expanded(
            child: switch (_tab) {
              0 => SyntaxEditor(
                controller: _editor,
                highlighter: _highlighter,
                theme: theme,
                wrap: _wrap,
                executor: _pool,
                onComplete: (_) async => true,
              ),
              1 => SyntaxFileList(
                controller: _files,
                highlighter: _highlighter,
                theme: theme,
                editable: true,
                onComplete: (_) async => true,
              ),
              2 => PatchView.controlled(
                controller: _patch,
                highlighter: _highlighter,
                theme: theme,
                wrap: _wrap,
                showReviewActions: true,
                stickyHeaders: true,
                inlineDiffMode: _comparison,
                showBackgrounds: _backgrounds,
                showChangeIndicators: _indicators,
                onEditComplete: (_) async => true,
              ),
              3 => MergeConflictView(
                controller: _merge,
                highlighter: _highlighter,
                theme: theme,
                wrap: _wrap,
              ),
              4 => StreamingCodeView(
                controller: _stream,
                highlighter: _highlighter,
                theme: theme,
              ),
              _ => SyntaxFileView(
                controller: _large,
                highlighter: _highlighter,
                theme: theme,
                wrap: _wrap,
                executor: _pool,
              ),
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _editor.dispose();
    _files.dispose();
    _large.dispose();
    _patch.dispose();
    _merge.dispose();
    _stream.dispose();
    _pool.dispose();
    super.dispose();
  }
}
