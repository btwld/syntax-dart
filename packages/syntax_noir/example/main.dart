import 'dart:async';

import 'package:noir/noir.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax_noir/syntax_noir.dart';

// Run in a terminal: dart run example/main.dart
void main() =>
    runTuiApp(Theme(data: ThemeData.dark, child: const WorkflowsDemo()));

class WorkflowsDemo extends StatefulWidget {
  const WorkflowsDemo({super.key});
  @override
  State<WorkflowsDemo> createState() => _WorkflowsDemoState();
}

class _WorkflowsDemoState extends State<WorkflowsDemo> {
  final highlighter = syntax.Highlighter(languages: [dartLanguage]);
  final pool = syntax.HighlightPool(
    executor: syntax.createNativeHighlightExecutor(),
    cacheSize: 4,
  );
  late final editor = syntax.EditorController(
    file: const syntax.SourceFile(
      id: 'editor',
      path: 'editable.dart',
      text: 'void main() {\n  // TODO: greet\n  print("Hello");\n}\n',
    ),
    proposalProvider: (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      request.cancellation.throwIfCancelled();
      final at = request.file.text.indexOf('TODO');
      return at < 0 ? [] : [syntax.OffsetEdit(at, at + 4, 'DONE')];
    },
  );
  final files = syntax.FileListController([
    for (var i = 0; i < 12; i++)
      syntax.SourceFile(
        id: 'file-$i',
        path: 'example_$i.dart',
        text: 'final value$i = $i;\n',
      ),
  ], sessionLimit: 4);
  late final large = syntax.EditorController(
    file: syntax.SourceFile(
      id: 'large',
      path: 'large.dart',
      text: [for (var i = 0; i < 100000; i++) 'final value$i = $i;'].join('\n'),
    ),
  );
  static const before = 'void main() {\n  print("Hello");\n}\n';
  static const after = 'void main() {\n  print("Hello, world!");\n}\n';
  late final patch = syntax.PatchController(
    [
      syntax
          .parsePatch(
            syntax.renderPatch(
              syntax.diffTexts(before, after, path: 'partial.dart'),
            ),
          )
          .single
          .copyWith(identity: 'partial'),
      for (var i = 1; i < 1000; i++)
        syntax.diffTexts(
          'final value = $i;\n',
          'final value = ${i + 1};\n',
          path: 'change_$i.dart',
          id: 'change-$i',
        ),
    ],
    contentsLoader: (_, cancellation) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      cancellation.throwIfCancelled();
      return (oldText: before, newText: after);
    },
  );
  final merge = syntax.MergeController(
    const syntax.SourceFile(
      id: 'merge',
      path: 'merge.dart',
      text:
          'void main() {\n<<<<<<< current\n  print("Current");\n||||||| base\n  print("Base");\n=======\n  print("Incoming");\n>>>>>>> incoming\n}\n',
    ),
  );
  final stream = syntax.StreamDocumentController(
    const syntax.SourceFile(id: 'stream', path: 'live.dart', text: ''),
  );
  Timer? timer;
  int tab = 0, streamed = 0;
  bool wrap = true, dark = true;
  syntax.InlineDiffMode comparison = syntax.InlineDiffMode.mergedWords;
  syntax.SyntaxPaletteVariant variant = syntax.SyntaxPaletteVariant.standard;
  String message =
      'Tab moves focus. Ctrl+F searches. Ctrl+Z undoes. Ctrl+Space accepts a suggestion.';
  @override
  void initState() {
    super.initState();
    editor.setAnnotations([
      const syntax.LineAnnotation(
        id: 'note',
        start: 16,
        end: 30,
        data:
            'This annotation follows edits.\nResize the terminal to wrap long review notes.',
      ),
    ]);
    editor.setDiagnostics([
      const syntax.Diagnostic(
        start: 18,
        end: 22,
        message: 'Resolve the TODO marker',
        severity: syntax.DiagnosticSeverity.information,
      ),
    ]);
    editor.setCarets([
      const syntax.RemoteCaret(
        id: 'reviewer',
        label: 'Reviewer',
        selection: syntax.DocumentSelection.collapsed(16),
        color: 0xff4c9eff,
      ),
    ]);
    patch.setAnnotations([
      const syntax.ReviewAnnotation(
        id: 'note',
        fileId: 'partial',
        side: syntax.DiffSide.newer,
        line: 2,
        data:
            'Load full contents to edit or accept this change.\nTab into this note to scroll longer annotations.',
      ),
    ]);
  }

  Future<bool> complete(syntax.SourceFile file) async {
    setState(
      () => message = 'Accepted ${file.path}, revision ${file.revision}',
    );
    return true;
  }

  void startStream() {
    if (timer != null || stream.isComplete || stream.isCancelled) return;
    timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (streamed == 100) {
        timer.cancel();
        stream.finish();
        return;
      }
      stream.add('final streamed$streamed = ${streamed++};\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = syntax.createSyntaxTheme(dark: dark, variant: variant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final (index, name) in [
              'Editor',
              'Files',
              'Patch',
              'Conflicts',
              'Stream',
              'Large',
            ].indexed)
              Button(label: name, onPressed: () => setState(() => tab = index)),
          ],
        ),
        Row(
          children: [
            Button(
              label: wrap ? 'Wrap' : 'Scroll',
              onPressed: () => setState(() => wrap = !wrap),
            ),
            Button(
              label: dark ? 'Dark' : 'Light',
              onPressed: () => setState(() => dark = !dark),
            ),
            Button(
              label: variant.name,
              onPressed: () => setState(
                () => variant =
                    syntax.SyntaxPaletteVariant.values[(variant.index + 1) %
                        syntax.SyntaxPaletteVariant.values.length],
              ),
            ),
            if (tab == 2) ...[
              Button(
                label: patch.mode.name,
                onPressed: () => setState(
                  () => patch.setMode(
                    patch.mode == syntax.DiffMode.unified
                        ? syntax.DiffMode.split
                        : syntax.DiffMode.unified,
                  ),
                ),
              ),
              Button(
                label: comparison.name,
                onPressed: () => setState(
                  () => comparison =
                      syntax.InlineDiffMode.values[(comparison.index + 1) %
                          syntax.InlineDiffMode.values.length],
                ),
              ),
              Button(
                label: 'File 900',
                onPressed: () => patch.revealLine('change-900', 1),
              ),
            ],
            if (tab == 4) ...[
              Button(label: 'Start', onPressed: startStream),
              Button(
                label: 'Cancel',
                onPressed: () {
                  timer?.cancel();
                  stream.cancel();
                },
              ),
            ],
            if (tab == 5)
              Button(
                label: 'Line 90,001',
                onPressed: () => large.reveal(
                  const syntax.DocumentRange(
                    syntax.DocumentPosition(90000, 0),
                    syntax.DocumentPosition(90000, 10),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: switch (tab) {
            0 => SyntaxEditor(
              controller: editor,
              highlighter: highlighter,
              theme: theme,
              wrap: wrap,
              onComplete: complete,
              autofocus: true,
            ),
            1 => SyntaxFileList(
              controller: files,
              highlighter: highlighter,
              theme: theme,
              wrap: wrap,
              editable: true,
              onComplete: complete,
            ),
            2 => PatchView.controlled(
              controller: patch,
              highlighter: highlighter,
              theme: theme,
              wrap: wrap,
              stickyHeaders: true,
              showReviewActions: true,
              inlineDiffMode: comparison,
              onEditComplete: (file) async {
                setState(() => message = 'Accepted ${file.path}');
                return true;
              },
              autofocus: true,
            ),
            3 => MergeConflictView(
              controller: merge,
              highlighter: highlighter,
              theme: theme,
              autofocus: true,
            ),
            4 => StreamingCodeView(
              controller: stream,
              highlighter: highlighter,
              theme: theme,
            ),
            _ => SyntaxEditor(
              controller: large,
              highlighter: highlighter,
              theme: theme,
              executor: pool,
              wrap: wrap,
              readOnly: true,
              autofocus: true,
            ),
          },
        ),
        Text(message, maxLines: 1),
      ],
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    editor.dispose();
    files.dispose();
    large.dispose();
    patch.dispose();
    merge.dispose();
    stream.dispose();
    pool.dispose();
    super.dispose();
  }
}
