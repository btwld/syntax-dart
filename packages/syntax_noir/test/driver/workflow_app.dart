import 'package:noir/noir.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_noir/syntax_noir.dart';

void main(List<String> args) => runTuiApp(
  Theme(
    data: ThemeData.dark,
    child: WorkflowApp(mode: args.firstOrNull ?? 'editor'),
  ),
);

class WorkflowApp extends StatefulWidget {
  const WorkflowApp({required this.mode, super.key});
  final String mode;
  @override
  State<WorkflowApp> createState() => _WorkflowAppState();
}

class _WorkflowAppState extends State<WorkflowApp> {
  final highlighter = syntax.Highlighter(languages: [dartLanguage]);
  late final editor = syntax.EditorController(
    file: const syntax.SourceFile(
      id: 'a',
      path: 'main.dart',
      text: 'final answer = 1;\nsecond line',
    ),
    proposalDelay: const Duration(milliseconds: 5),
    proposalProvider: widget.mode == 'proposal'
        ? (_) async => [const syntax.OffsetEdit(0, 1, 'suggested')]
        : null,
  );
  late final patch = syntax.PatchController([
    syntax.diffTexts(
      'one\nold\nthree\n',
      'one\nnew\nthree\n',
      path: 'a.dart',
      id: 'a',
    ),
  ], foldableHunks: widget.mode == 'fold');
  final merge = syntax.MergeController(
    const syntax.SourceFile(
      id: 'm',
      path: 'merge.dart',
      text: 'before\n<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\nafter',
    ),
  );
  String message = '';
  bool visible = true;
  bool secondFiles = false;
  final firstFiles = syntax.FileListController([
    syntax.SourceFile(
      id: 'shared',
      path: 'first.dart',
      text: List.generate(100, (i) => 'first row $i').join('\n'),
    ),
  ], sessionLimit: 0);
  final nextFiles = syntax.FileListController([
    const syntax.SourceFile(
      id: 'shared',
      path: 'second.dart',
      text: 'replacement source',
    ),
  ], sessionLimit: 0);
  @override
  void initState() {
    super.initState();
    editor.setDiagnostics([
      const syntax.Diagnostic(start: 6, end: 12, message: 'Review the answer'),
    ]);
    editor.setAnnotations([
      syntax.LineAnnotation(
        id: 'note',
        start: 0,
        end: 0,
        data: widget.mode == 'annotations'
            ? 'Review annotation\n${'界' * 25}\nAnnotation final row'
            : 'Review annotation',
      ),
    ]);
    patch.setAnnotations([
      syntax.ReviewAnnotation(
        id: 'multi',
        fileId: 'a',
        side: syntax.DiffSide.newer,
        line: 1,
        data: widget.mode == 'long-review'
            ? List.generate(30, (i) => 'Review note row $i').join('\n')
            : 'Review first row\nReview second row\nReview final row',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.mode == 'files') ...[
        Button(
          label: 'Swap collection',
          onPressed: () => setState(() => secondFiles = !secondFiles),
        ),
        Button(
          label: 'Reveal distant row',
          onPressed: () => firstFiles.reveal(
            'shared',
            const syntax.DocumentRange(
              syntax.DocumentPosition(80, 0),
              syntax.DocumentPosition(80, 0),
            ),
          ),
        ),
        Button(
          label: 'Reveal first row',
          onPressed: () => firstFiles.reveal(
            'shared',
            const syntax.DocumentRange(
              syntax.DocumentPosition(0, 0),
              syntax.DocumentPosition(0, 0),
            ),
          ),
        ),
      ],
      if (widget.mode == 'fold')
        Button(
          label: 'Reveal selected line',
          onPressed: () => patch.revealLine('a', 2),
        ),
      if (widget.mode == 'restore')
        Button(
          label: visible ? 'Hide editor' : 'Show editor',
          onPressed: () => setState(() => visible = !visible),
        ),
      Expanded(
        child: !visible
            ? const Text('Draft retained')
            : switch (widget.mode) {
                'files' => SyntaxFileList(
                  controller: secondFiles ? nextFiles : firstFiles,
                  highlighter: highlighter,
                  theme: githubDarkTheme,
                ),
                'patch' || 'long-review' || 'fold' => PatchView.controlled(
                  controller: patch,
                  highlighter: highlighter,
                  theme: githubDarkTheme,
                  autofocus: true,
                  showReviewActions: true,
                  onCopy: (text) => setState(
                    () => message = 'Copied: ${text.replaceAll('\n', '|')}',
                  ),
                ),
                'conflict' => MergeConflictView(
                  controller: merge,
                  highlighter: highlighter,
                  theme: githubDarkTheme,
                  autofocus: true,
                ),
                _ => SyntaxEditor(
                  controller: editor,
                  highlighter: highlighter,
                  theme: githubDarkTheme,
                  autofocus: true,
                  wrap: widget.mode == 'wrap',
                  annotationRowCount: widget.mode == 'custom-annotations'
                      ? (_, width) => width < 40 ? 4 : 2
                      : null,
                  annotationRowBuilder: widget.mode == 'custom-annotations'
                      ? (_, annotation, row, width) =>
                            Text('Custom annotation row $row')
                      : null,
                  onCopy: (text) => setState(() => message = 'Copied: $text'),
                  onComplete: (file) async {
                    setState(
                      () => message =
                          'Completed: ${file.text.replaceAll('\n', '|')}',
                    );
                    return true;
                  },
                ),
              },
      ),
      Text(message, maxLines: 1),
    ],
  );
  @override
  void dispose() {
    firstFiles.dispose();
    nextFiles.dispose();
    editor.dispose();
    patch.dispose();
    merge.dispose();
    super.dispose();
  }
}
