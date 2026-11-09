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
  final _patch = PatchController<void>([
    diffTexts(
      'void main() => print("Hello");\n',
      'void main() => print("Hello, widgets!");',
      path: 'lib/main.dart',
    ),
  ]);

  @override
  void dispose() {
    _patch.dispose();
    super.dispose();
  }

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
                  child: PatchView<void>.controlled(
                    controller: _patch,
                    theme: githubDarkTheme,
                    selectionChrome: _chrome,
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
