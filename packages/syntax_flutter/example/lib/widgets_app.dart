import 'package:flutter/widgets.dart';
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

/// Runs the plain widgets demo with no Material localization or icon font.
void main() => runApp(const WidgetsDemo());

/// A routed widgets-only host for both syntax surfaces.
class WidgetsDemo extends StatelessWidget {
  /// Creates the plain widgets demo.
  const WidgetsDemo({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: githubDarkTheme.backgroundColor,
    onGenerateRoute: (_) =>
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const _DemoSurfaces()),
  );
}

class _DemoSurfaces extends StatefulWidget {
  const _DemoSurfaces();

  @override
  State<_DemoSurfaces> createState() => _DemoSurfacesState();
}

class _DemoSurfacesState extends State<_DemoSurfaces> {
  final _highlighter = Highlighter(languages: [dartLanguage]);
  final _collapsed = <int>{};
  final _expanded = <DiffGapId>{};
  final _chrome = SyntaxSelectionChrome(
    selectionControls: SyntaxSelectionChrome.plain.selectionControls,
    // A host can supply its own tooltip here; the accessible description is
    // retained by PatchView and is never included when copying code.
    noNewlineMarkerBuilder: (_, message) => Text('[$message]'),
  );

  @override
  Widget build(BuildContext context) => HighlighterScope(
    highlighter: _highlighter,
    child: DefaultTextStyle(
      style: TextStyle(color: githubDarkTheme.foregroundColor, fontSize: 14),
      child: ColoredBox(
        color: githubDarkTheme.backgroundColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Code: select text, then copy with the context menu.',
                ),
                Expanded(
                  child: HighlightedCode(
                    'void main() {\n  print("Hello");\n}',
                    language: 'dart',
                    theme: githubDarkTheme,
                    lineNumbers: true,
                    selectionChrome: _chrome,
                  ),
                ),
                const Text(
                  'Patch: Tab to its header; Enter or Space folds it.',
                ),
                Expanded(
                  child: PatchView.fromTexts(
                    oldText: 'void main() => print("Hello");\n',
                    newText: 'void main() => print("Hello, widgets!");',
                    path: 'lib/main.dart',
                    leading: const Text(
                      'Compare the greeting implementations.',
                    ),
                    stickyHeaders: true,
                    canvasColor: const Color(0xff101010),
                    sectionDecoration: BoxDecoration(
                      border: Border.all(color: const Color(0xff444444)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    fileFooterBuilder: (_, file, collapsed) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        collapsed ? 'File folded' : 'End of ${file.path}',
                      ),
                    ),
                    gutterBuilder: (_, line) =>
                        line.line == 1 ? const Text('•') : null,
                    selectionActionBuilder: (_, details) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Selected ${details.selection.anchor} → '
                        '${details.selection.active} on ${details.selection.activeSide.name}',
                      ),
                    ),
                    theme: githubDarkTheme,
                    selectionChrome: _chrome,
                    collapsed: _collapsed,
                    expanded: _expanded,
                    onToggleFile: (file) => setState(() {
                      if (!_collapsed.remove(file)) _collapsed.add(file);
                    }),
                    onExpandGap: (gap) => setState(() => _expanded.add(gap)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
