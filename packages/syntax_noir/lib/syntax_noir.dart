/// Terminal widgets for [syntax](https://pub.dev/packages/syntax_darts) on
/// [noir](https://pub.dev/packages/noir): syntax highlighting with TextMate
/// grammars and VS Code themes.
///
/// - [SyntaxCodeHighlighter] highlights noir's `CodeView`.
/// - [PatchView] shows a diff or patch, unified or split.
/// - [PatchPainter] paints diff rows, for building your own view.
/// - [noirColor] and [noirTextStyle] convert syntax's colors and styles.
///
/// noir and syntax both export `DiffLine`, `DiffHunk` and `DiffLineKind`,
/// so import syntax with a prefix:
///
/// ```dart
/// import 'package:noir/noir.dart';
/// import 'package:syntax_darts/syntax.dart' as syntax;
/// import 'package:syntax_noir/syntax_noir.dart';
/// ```
library;

export 'src/code_highlighter.dart';
export 'src/colors.dart';
export 'src/patch_painter.dart';
export 'src/patch_view.dart';
