import 'package:noir/noir.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_noir/syntax_noir.dart';

// Run in a terminal: dart run example/main.dart
void main() => runTuiApp(const PatchDemo());

final highlighter = syntax.Highlighter(languages: [dartLanguage]);

const before = '''
class Counter {
  int count = 0;

  void increment() => count++;

  void reset() {
    count = 0;
  }
}
''';

const after = '''
class Counter {
  Counter({this.step = 1});

  final int step;
  int total = 0;

  void increment() => total += step;

  void reset() {
    total = 0;
  }
}
''';

/// The changes to a small class, unified. Arrow keys move, Enter expands
/// hidden lines or collapses the file.
class PatchDemo extends StatefulWidget {
  const PatchDemo({super.key});

  @override
  State<PatchDemo> createState() => _PatchDemoState();
}

class _PatchDemoState extends State<PatchDemo> {
  final Set<int> _collapsed = {};
  final Set<syntax.DiffGapId> _expanded = {};

  @override
  Widget build(BuildContext context) => PatchView.fromTexts(
    oldText: before,
    newText: after,
    path: 'lib/counter.dart',
    highlighter: highlighter,
    theme: githubDarkTheme,
    collapsed: _collapsed,
    expanded: _expanded,
    onToggleFile: (file) => setState(() {
      if (!_collapsed.remove(file)) _collapsed.add(file);
    }),
    onExpandGap: (id) => setState(() => _expanded.add(id)),
    autofocus: true,
  );
}
