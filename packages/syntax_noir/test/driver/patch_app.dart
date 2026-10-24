import 'package:noir/noir.dart';
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/syntax.dart' as syntax;
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_noir/syntax_noir.dart';

/// The app the driver tests launch: twenty lines with `v10` changed, side
/// by side with `split`, or no files at all with `empty`.
void main(List<String> args) => runTuiApp(_App(args));

class _App extends StatefulWidget {
  const _App(this.args);

  final List<String> args;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  final _highlighter = syntax.Highlighter(languages: [dartLanguage]);
  final _before = [for (var i = 1; i <= 20; i++) 'final v$i = $i;'].join('\n');
  final Set<int> _collapsed = {};
  final Set<syntax.DiffGapId> _expanded = {};

  void _toggleFile(int file) => setState(() {
    if (!_collapsed.remove(file)) _collapsed.add(file);
  });

  void _expandGap(syntax.DiffGapId id) => setState(() => _expanded.add(id));

  @override
  Widget build(BuildContext context) {
    if (widget.args.contains('empty')) {
      return PatchView(
        files: const [],
        highlighter: _highlighter,
        theme: githubDarkTheme,
        collapsed: _collapsed,
        expanded: _expanded,
        onToggleFile: _toggleFile,
        onExpandGap: _expandGap,
        autofocus: true,
      );
    }
    if (widget.args.contains('sticky')) {
      return PatchView(
        files: [
          syntax.diffTexts('a\n', 'b\n', path: 'first.dart'),
          syntax.diffTexts('c\n', 'd\n', path: 'second.dart'),
        ],
        highlighter: _highlighter,
        theme: githubDarkTheme,
        stickyHeaders: true,
        collapsed: _collapsed,
        expanded: _expanded,
        onToggleFile: _toggleFile,
        onExpandGap: _expandGap,
        autofocus: true,
      );
    }
    return PatchView.fromTexts(
      oldText: _before,
      newText: _before.replaceFirst('v10 = 10', 'v10 = 100'),
      path: 'values.dart',
      highlighter: _highlighter,
      theme: githubDarkTheme,
      mode: widget.args.contains('split')
          ? syntax.DiffMode.split
          : syntax.DiffMode.unified,
      collapsed: _collapsed,
      expanded: _expanded,
      onToggleFile: _toggleFile,
      onExpandGap: _expandGap,
      autofocus: true,
    );
  }
}
