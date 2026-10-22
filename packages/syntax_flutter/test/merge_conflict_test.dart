import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:syntax_flutter/syntax_flutter.dart';
import 'package:syntax_flutter/src/line_selection.dart';

const source =
    'void main() {\n'
    '<<<<<<< ours\n'
    "  print('current');\n"
    '||||||| ancestor\n'
    "  print('base');\n"
    '=======\n'
    "  print('incoming');\n"
    '>>>>>>> theirs\n'
    '}\n';

Future<void> showMerge(
  WidgetTester tester,
  MergeController merge, {
  SyntaxTheme? theme,
  bool wrap = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MergeConflictView(
          controller: merge,
          highlighter: Highlighter(languages: [dartLanguage]),
          theme: theme ?? githubDarkTheme,
          textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 15),
          wrap: wrap,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color lineColor(WidgetTester tester, int line) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(LineSelectionTarget).at(line),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

void main() {
  testWidgets(
    'conflict backgrounds, inline actions and tokens survive themes',
    (tester) async {
      final merge = MergeController(
        const SourceFile(id: 'a', path: 'a.dart', text: source),
      );
      for (final theme in [githubDarkTheme, githubLightTheme]) {
        await showMerge(tester, merge, theme: theme);
        final colors = MergeColors.of(theme);
        expect(lineColor(tester, 0), Color(theme.background));
        expect(lineColor(tester, 2), Color(colors.current.background));
        expect(lineColor(tester, 4), Color(colors.base.background));
        expect(lineColor(tester, 6), Color(colors.incoming.background));
        expect(lineColor(tester, 8), Color(theme.background));
        expect(find.text('Current change · ours'), findsOneWidget);
        expect(find.text('Common ancestor'), findsOneWidget);
        expect(find.text('Incoming change · theirs'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Keep current')).dy,
          lessThan(
            tester
                .getTopLeft(
                  find.text("  print('current');", findRichText: true),
                )
                .dy,
          ),
        );
        final code = tester.widget<Text>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.textSpan?.toPlainText() == "  print('current');",
          ),
        );
        final span = code.textSpan! as TextSpan;
        expect(span.style!.fontFamily, 'monospace');
        expect(
          span.children!
              .whereType<TextSpan>()
              .map((s) => s.style!.color)
              .toSet()
              .length,
          greaterThan(1),
        );
      }
      final file = tester
          .widget<SyntaxFileView>(find.byType(SyntaxFileView))
          .controller;
      file.selectLines(1, 7);
      await tester.pumpAndSettle();
      final selection = file.selections.single;
      expect(
        file.document.text.substring(selection.start, selection.end),
        source.substring(
          source.indexOf('<<<<<<<'),
          source.indexOf('\n}', source.indexOf('>>>>>>>')),
        ),
      );
      await tester.tap(find.text('Keep incoming'));
      await tester.pumpAndSettle();
      expect(merge.file.text, "void main() {\n  print('incoming');\n}\n");
      expect(find.text('All conflicts resolved'), findsOneWidget);
      expect(find.text('Current change · ours'), findsNothing);
      // Clear the retained source selection to inspect the undecorated result.
      file.setSelections([const DocumentSelection.collapsed(0)]);
      await tester.pumpAndSettle();
      expect(lineColor(tester, 1), Color(githubLightTheme.background));
      await tester.pumpWidget(const SizedBox());
      merge.dispose();
    },
  );

  testWidgets('inline choices follow remaining conflicts at narrow widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const block = '<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n';
    final merge = MergeController(
      const SourceFile(id: 'a', path: 'a.txt', text: '$block\n$block'),
    );
    await showMerge(tester, merge);
    await tester.tap(find.text('Keep current').first);
    await tester.pumpAndSettle();
    expect(merge.conflicts, hasLength(1));
    expect(merge.file.text, 'a\n\n$block');
    expect(find.text('1 conflict remaining'), findsOneWidget);
    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();
    expect(merge.file.text, 'a\n\na\nb\n');
    expect(find.text('All conflicts resolved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    merge.dispose();
  });

  testWidgets(
    'controller replacement clears old section colors and listeners',
    (tester) async {
      final first = MergeController(
        const SourceFile(id: 'a', path: 'a.dart', text: source),
      );
      final second = MergeController(
        const SourceFile(id: 'b', path: 'b.dart', text: 'final value = 2;'),
      );
      await showMerge(tester, first, wrap: false);
      await showMerge(tester, second, wrap: false);
      first.resolve(0, ChangeResolution.old);
      await tester.pumpAndSettle();
      expect(find.text('Current change · ours'), findsNothing);
      expect(find.text('final value = 2;', findRichText: true), findsOneWidget);
      expect(lineColor(tester, 0), Color(githubDarkTheme.background));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      first.dispose();
      second.dispose();
    },
  );
}
