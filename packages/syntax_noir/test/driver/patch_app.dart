import 'package:noir/noir.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_noir/syntax_noir.dart';

/// The app the driver tests launch: twenty lines with `v10` changed, side
/// by side with `split`, or no files at all with `empty`.
void main(List<String> args) {
  final highlighter = syntax.Highlighter(languages: [dartLanguage]);
  final before = [for (var i = 1; i <= 20; i++) 'final v$i = $i;'].join('\n');
  runTuiApp(
    args.contains('empty')
        ? PatchView(
            files: const [],
            highlighter: highlighter,
            theme: githubDarkTheme,
            autofocus: true,
          )
        : PatchView.fromTexts(
            oldText: before,
            newText: before.replaceFirst('v10 = 10', 'v10 = 100'),
            path: 'values.dart',
            highlighter: highlighter,
            theme: githubDarkTheme,
            mode: args.contains('split')
                ? syntax.DiffMode.split
                : syntax.DiffMode.unified,
            autofocus: true,
          ),
  );
}
