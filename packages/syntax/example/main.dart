import 'package:syntax/langs/dart.dart';
import 'package:syntax/syntax.dart';
import 'package:syntax/themes/github_dark.dart';

const code = '''
void main() {
  // Greets the world.
  print('Hello, world!');
}
''';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);

  // Colored output for a terminal.
  print(highlighter.toAnsi(code, language: 'dart', theme: githubDarkTheme));

  // Or styled ranges over the text, to paint with any renderer.
  final ranges = highlighter.highlightRanges(
    code,
    language: 'dart',
    theme: githubDarkTheme,
  );
  for (final range in ranges) {
    final text = code.substring(range.start, range.end);
    print('${colorToHex(range.style.foreground)}  $text');
  }

  // Or a diff, laid out as the rows a diff view shows.
  final diff = diffTexts(
    code,
    code.replaceFirst('Greets the world', 'Says hello'),
  );
  for (final row in layoutDiff([diff])) {
    print(row);
  }
}
