import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

final highlighter = Highlighter(languages: [dartLanguage]);

const patch = '''
diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,3 @@ class A {
 class A {
-  int count = 0;
+  int total = 0;
 }
diff --git a/old.txt b/new.txt
similarity index 100%
rename from old.txt
rename to new.txt
''';

Future<void> pump(WidgetTester tester, Widget view) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: HighlighterScope(highlighter: highlighter, child: view),
    ),
  ),
);

/// Hosts a [PatchView] with caller-owned [collapsed] and [expanded] sets.
Widget host(
  Widget Function(
    Set<int> collapsed,
    Set<DiffGapId> expanded,
    ValueChanged<int> toggleFile,
    ValueChanged<DiffGapId> expandGap,
  )
  builder,
) {
  final collapsed = <int>{};
  final expanded = <DiffGapId>{};
  return StatefulBuilder(
    builder: (context, setState) => builder(
      collapsed,
      expanded,
      (file) => setState(() {
        if (!collapsed.remove(file)) collapsed.add(file);
      }),
      (id) => setState(() => expanded.add(id)),
    ),
  );
}

/// Whether [span] has a run of exactly [text].
bool hasRun(InlineSpan span, String text) =>
    span is TextSpan &&
    (span.text == text || (span.children ?? []).any((c) => hasRun(c, text)));

/// The plain text of every Text.rich in the view, in order.
List<String> texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.textSpan?.toPlainText() ?? t.data ?? '',
];

/// The line numbers on the same row as [code], left to right.
List<String> numbersBeside(WidgetTester tester, String code) {
  final y = tester.getTopLeft(find.text(code)).dy;
  final numbers = <(double, String)>[];
  for (final element in find.byType(Text).evaluate()) {
    final text = (element.widget as Text).data;
    if (text == null || int.tryParse(text) == null) continue;
    final at = (element.renderObject! as RenderBox).localToGlobal(Offset.zero);
    if (at.dy == y) numbers.add((at.dx, text));
  }
  numbers.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, n) in numbers) n];
}

/// The color of the first span whose text is [word].
Color? colorOf(WidgetTester tester, String word) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.textSpan)
    .whereType<TextSpan>()
    .expand((s) => s.children ?? const <InlineSpan>[])
    .whereType<TextSpan>()
    .firstWhere((s) => s.text == word)
    .style
    ?.color;

String lines(int from, int to) =>
    [for (var i = from; i <= to; i++) 'final v$i = $i;'].join('\n');

void main() {
  testWidgets('unified view shows headers, counts and both line kinds', (
    tester,
  ) async {
    await pump(
      tester,
      const PatchView.fromPatch(patch, theme: githubDarkTheme),
    );
    final all = texts(tester);
    expect(all, contains('lib/a.dart'));
    expect(all, contains('+1'));
    expect(all, contains('−1'));
    expect(all, contains('Renamed'));
    expect(all, contains('File renamed without changes'));
    expect(all, contains('  int count = 0;'));
    expect(all, contains('  int total = 0;'));
    expect(all.any((t) => t.startsWith('@@ -1,3 +1,3 @@')), isTrue);
  });

  testWidgets('changed words get a stronger background', (tester) async {
    await pump(
      tester,
      const PatchView.fromPatch(patch, theme: githubDarkTheme),
    );
    final colors = DiffColors.of(githubDarkTheme);
    final total = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.textSpan)
        .whereType<TextSpan>()
        .expand((s) => s.children ?? const <InlineSpan>[])
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == 'total');
    expect(total.style!.backgroundColor, Color(colors.insertedText));
  });

  testWidgets('split view puts old and new lines side by side', (tester) async {
    await pump(
      tester,
      const PatchView.fromPatch(
        patch,
        theme: githubDarkTheme,
        mode: DiffMode.split,
      ),
    );
    final count = tester.getTopLeft(find.text('  int count = 0;'));
    final total = tester.getTopLeft(find.text('  int total = 0;'));
    expect(count.dy, total.dy);
    expect(count.dx, lessThan(total.dx));
  });

  testWidgets('tapping a file header collapses and expands it', (tester) async {
    await pump(
      tester,
      host(
        (collapsed, expanded, toggleFile, expandGap) => PatchView.fromPatch(
          patch,
          theme: githubDarkTheme,
          collapsed: collapsed,
          expanded: expanded,
          onToggleFile: toggleFile,
          onExpandGap: expandGap,
        ),
      ),
    );
    expect(find.text('  int total = 0;'), findsOneWidget);
    await tester.tap(find.text('lib/a.dart'));
    await tester.pump();
    expect(find.text('  int total = 0;'), findsNothing);
    await tester.tap(find.text('lib/a.dart'));
    await tester.pump();
    expect(find.text('  int total = 0;'), findsOneWidget);
  });

  testWidgets('fromTexts can expand the unchanged lines', (tester) async {
    final before = [for (var i = 1; i <= 20; i++) 'final v$i = $i;'].join('\n');
    final after = before.replaceFirst('v10 = 10', 'v10 = 100');
    await pump(
      tester,
      host(
        (collapsed, expanded, toggleFile, expandGap) => PatchView.fromTexts(
          oldText: before,
          newText: after,
          path: 'values.dart',
          theme: githubLightTheme,
          collapsed: collapsed,
          expanded: expanded,
          onToggleFile: toggleFile,
          onExpandGap: expandGap,
        ),
      ),
    );
    expect(find.text('Show 6 unchanged lines'), findsOneWidget);
    expect(find.text('Show 7 unchanged lines'), findsOneWidget);
    expect(find.text('final v1 = 1;'), findsNothing);
    await tester.tap(find.text('Show 6 unchanged lines'));
    await tester.pump();
    expect(find.text('final v1 = 1;'), findsOneWidget);
    expect(find.text('Show 6 unchanged lines'), findsNothing);
  });

  testWidgets('expanded lines keep both line numbers and fit the gutter', (
    tester,
  ) async {
    // Removing four lines leaves old numbers wider than any new one.
    await pump(
      tester,
      host(
        (collapsed, expanded, toggleFile, expandGap) => PatchView.fromTexts(
          oldText: lines(1, 12),
          newText: lines(5, 12),
          path: 'values.dart',
          theme: githubDarkTheme,
          collapsed: collapsed,
          expanded: expanded,
          onToggleFile: toggleFile,
          onExpandGap: expandGap,
        ),
      ),
    );
    await tester.tap(find.text('Show 5 unchanged lines'));
    await tester.pump();
    expect(numbersBeside(tester, 'final v12 = 12;'), ['12', '8']);
    expect(
      tester.getSize(find.text('12')).height,
      tester.getSize(find.text('final v12 = 12;')).height,
    );
  });

  testWidgets('gutter width fits the widest digit', (tester) async {
    await pump(
      tester,
      PatchView.fromTexts(
        oldText: lines(1, 1000),
        newText: lines(1, 1000).replaceFirst('v999 = 999', 'v999 = 0'),
        path: 'values.dart',
        theme: githubDarkTheme,
      ),
    );
    final number = tester.renderObject<RenderParagraph>(
      find.text('1000').first,
    );
    expect(
      number.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(number.size.width),
    );
    expect(tester.getSize(find.text('1000').first).width, 4 * 14 + 8);
  });

  testWidgets('expanding every gap shows both files in order', (tester) async {
    // Tall enough that every row is built at once.
    tester.view.physicalSize = const Size(1200, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final random = Random(3);
    String text() => [
      for (var i = 0; i < 30; i++) ['a', 'b', 'c', '}'][random.nextInt(4)],
    ].join('\n');
    for (var run = 0; run < 4; run++) {
      final before = text();
      final edited = before.split('\n')
        ..removeRange(4, 6)
        ..insert(12, 'new')
        ..[20] = 'changed';
      final after = edited.join('\n') + (run.isEven ? '\n' : '');
      await pump(
        tester,
        host(
          (collapsed, expanded, toggleFile, expandGap) => PatchView.fromTexts(
            oldText: before,
            newText: after,
            path: 'f.txt',
            contextLines: run % 4,
            theme: githubDarkTheme,
            collapsed: collapsed,
            expanded: expanded,
            onToggleFile: toggleFile,
            onExpandGap: expandGap,
          ),
        ),
      );
      while (find.textContaining('unchanged line').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('unchanged line').first);
        await tester.pump();
      }

      // Each code line follows its old number, new number and marker.
      final paragraphs = [
        for (final e in find.byType(RichText).evaluate())
          e.renderObject! as RenderParagraph,
      ];
      final rows = [
        for (var i = 3; i < paragraphs.length; i++)
          if (paragraphs[i].registrar != null)
            [
              for (final p in paragraphs.sublist(i - 3, i + 1))
                p.text.toPlainText(),
            ],
      ];
      final oldSide = [
        for (final [n, _, marker, code] in rows)
          if (marker != '+') '$n $code',
      ];
      final newSide = [
        for (final [_, n, marker, code] in rows)
          if (marker != '−') '$n $code',
      ];
      List<String> numbered(String s) => [
        for (final (i, line) in s.split('\n').indexed)
          if (i < s.split('\n').length - 1 || line.isNotEmpty) '${i + 1} $line',
      ];
      expect(oldSide, numbered(before), reason: 'run $run');
      expect(newSide, numbered(after), reason: 'run $run');
      expect(find.textContaining('@@'), findsNothing, reason: 'run $run');
    }
  });

  testWidgets('without context, the line before a deletion is kept', (
    tester,
  ) async {
    await pump(
      tester,
      host(
        (collapsed, expanded, toggleFile, expandGap) => PatchView.fromTexts(
          oldText: lines(1, 6),
          newText: lines(1, 6).replaceFirst('final v5 = 5;\n', ''),
          contextLines: 0,
          theme: githubDarkTheme,
          collapsed: collapsed,
          expanded: expanded,
          onToggleFile: toggleFile,
          onExpandGap: expandGap,
        ),
      ),
    );
    expect(find.text('Show 4 unchanged lines'), findsOneWidget);
    expect(find.text('Show 1 unchanged line'), findsOneWidget);
    await tester.tap(find.text('Show 4 unchanged lines'));
    await tester.pump();
    expect(numbersBeside(tester, 'final v4 = 4;'), ['4', '4']);
  });

  testWidgets('only code is selectable', (tester) async {
    await pump(
      tester,
      const PatchView.fromPatch(patch, theme: githubDarkTheme),
    );
    // A paragraph without a registrar can't be part of a selection, so
    // headers, line numbers and markers stay out of copied text.
    final selectable = [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.registrar != null)
          p.text.toPlainText(),
    ];
    expect(selectable, [
      'class A {',
      '  int count = 0;',
      '  int total = 0;',
      '}',
    ]);
  });

  testWidgets('split view leaves a blank side for unpaired lines', (
    tester,
  ) async {
    await pump(
      tester,
      PatchView.fromTexts(
        oldText: 'keep\nold one\nold two\n',
        newText: 'keep\nnew one\n',
        theme: githubDarkTheme,
        mode: DiffMode.split,
      ),
    );
    final oldOne = tester.getTopLeft(find.text('old one'));
    final newOne = tester.getTopLeft(find.text('new one'));
    final oldTwo = tester.getTopLeft(find.text('old two'));
    expect(oldOne.dy, newOne.dy);
    expect(oldTwo.dy, greaterThan(oldOne.dy));
    expect(numbersBeside(tester, 'old two'), ['3']);
  });

  testWidgets('a theme change re-highlights', (tester) async {
    await pump(
      tester,
      const PatchView.fromPatch(patch, theme: githubDarkTheme),
    );
    final dark = colorOf(tester, 'class');
    await pump(
      tester,
      const PatchView.fromPatch(patch, theme: githubLightTheme),
    );
    expect(colorOf(tester, 'class'), isNot(dark));
  });

  testWidgets('a language added later is used on the next build', (
    tester,
  ) async {
    final late = Highlighter();
    // A new widget each time, so the second pump rebuilds the view, as a
    // parent rebuilding would. Highlighter doesn't notify on its own.
    Widget view() => HighlighterScope(
      highlighter: late,
      // ignore: prefer_const_constructors
      child: PatchView.fromPatch(patch, theme: githubDarkTheme),
    );
    // Highlighted, `class` is a span of its own in a keyword color.
    Iterable<TextSpan> classSpans() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.textSpan)
        .whereType<TextSpan>()
        .expand((s) => s.children ?? const <InlineSpan>[])
        .whereType<TextSpan>()
        .where((s) => s.text == 'class');
    await pump(tester, view());
    expect(classSpans(), isEmpty);
    late.addLanguage(dartLanguage);
    await pump(tester, view());
    expect(
      classSpans().single.style!.color,
      isNot(githubDarkTheme.foregroundColor),
    );
  });

  testWidgets('language overrides the path', (tester) async {
    await pump(
      tester,
      PatchView.fromTexts(
        oldText: 'var a;\n',
        newText: 'final a = 1;\n',
        language: 'dart',
        theme: githubDarkTheme,
      ),
    );
    expect(colorOf(tester, 'final'), isNot(githubDarkTheme.foregroundColor));
  });

  testWidgets('notices for empty, binary and mode-only changes', (
    tester,
  ) async {
    await pump(tester, const PatchView.fromPatch('', theme: githubDarkTheme));
    expect(find.text('No changes'), findsOneWidget);
    await pump(
      tester,
      const PatchView.fromPatch('''
diff --git a/logo.png b/logo.png
index 1111111..2222222 100644
Binary files a/logo.png and b/logo.png differ
diff --git a/run.sh b/run.sh
old mode 100644
new mode 100755
''', theme: githubDarkTheme),
    );
    expect(find.text('Binary file not shown'), findsOneWidget);
    expect(find.text('No content changes'), findsOneWidget);
    await pump(
      tester,
      PatchView.fromTexts(oldText: 'a', newText: 'a', theme: githubDarkTheme),
    );
    expect(find.text('No changes'), findsOneWidget);
  });

  testWidgets('a missing final newline is marked', (tester) async {
    await pump(
      tester,
      PatchView.fromTexts(oldText: 'a\n', newText: 'b', theme: githubDarkTheme),
    );
    expect(find.byTooltip('No newline at end of file'), findsOneWidget);
  });

  testWidgets('headers fit narrow widths', (tester) async {
    for (final width in [120.0, 240.0, 320.0]) {
      await pump(
        tester,
        Center(
          child: SizedBox(
            width: width,
            child: const PatchView.fromPatch(patch, theme: githubDarkTheme),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('collapsed and expanded follow the caller-provided sets', (
    tester,
  ) async {
    final files = parsePatch(patch);
    await pump(
      tester,
      PatchView(files: files, theme: githubDarkTheme, collapsed: const {0}),
    );
    expect(find.text('  int total = 0;'), findsNothing);
    await pump(
      tester,
      PatchView(files: files, theme: githubLightTheme, collapsed: const {}),
    );
    expect(find.text('  int total = 0;'), findsOneWidget);
  });

  testWidgets('Enter on a focused file header collapses it', (tester) async {
    await pump(
      tester,
      host(
        (collapsed, expanded, toggleFile, expandGap) => PatchView.fromPatch(
          patch,
          theme: githubDarkTheme,
          collapsed: collapsed,
          expanded: expanded,
          onToggleFile: toggleFile,
          onExpandGap: expandGap,
        ),
      ),
    );
    Focus.of(tester.element(find.text('lib/a.dart'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('  int total = 0;'), findsNothing);
  });

  testWidgets('headers and changed lines are announced', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const PatchView.fromPatch(patch, theme: githubDarkTheme),
    );
    expect(
      find.bySemanticsLabel('Modified, lib/a.dart, 1 addition, 1 deletion'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Renamed, old.txt to new.txt, 0 additions, '
        '0 deletions',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('^Added line 2')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('code reads left to right in a right-to-left app', (
    tester,
  ) async {
    await pump(
      tester,
      const Directionality(
        textDirection: TextDirection.rtl,
        child: PatchView.fromPatch(
          patch,
          theme: githubDarkTheme,
          mode: DiffMode.split,
        ),
      ),
    );
    // The old side stays on the left.
    expect(
      tester.getTopLeft(find.text('  int count = 0;')).dx,
      lessThan(tester.getTopLeft(find.text('  int total = 0;')).dx),
    );
  });

  testWidgets('labels can be replaced, for example to translate them', (
    tester,
  ) async {
    await pump(
      tester,
      PatchView.fromTexts(
        oldText: lines(1, 12),
        newText: lines(1, 12).replaceFirst('v8 = 8', 'v8 = 80'),
        theme: githubDarkTheme,
        labels: const _Spanish(),
      ),
    );
    expect(find.text('Mostrar 4 líneas sin cambios'), findsOneWidget);
    expect(find.text('Mostrar 1 línea sin cambios'), findsOneWidget);
  });

  testWidgets('a long file colors its rows between frames', (tester) async {
    final before = [for (var i = 0; i < 4000; i++) 'final v$i = $i;'];
    final after = [...before]..[3000] = 'final v3000 = 300000;';
    await pump(
      tester,
      PatchView.fromTexts(
        oldText: before.join('\n'),
        newText: after.join('\n'),
        path: 'a.dart',
        theme: githubDarkTheme,
      ),
    );
    InlineSpan added() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.textSpan)
        .whereType<TextSpan>()
        .firstWhere((s) => s.toPlainText().contains('= 300000'));
    // Line 3001 isn't tokenized yet, but its changed word is marked.
    expect(hasRun(added(), 'final'), isFalse);
    expect(hasRun(added(), '300000'), isTrue);

    for (var i = 0; i < 1000 && !hasRun(added(), 'final'); i++) {
      await tester.pump();
    }
    expect(hasRun(added(), 'final'), isTrue);
  });

  testWidgets(
    'IndexedCodeViewport preserves visible anchor when a row shrinks',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var height = 800.0;
      var revision = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              height: 300,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return IndexedCodeViewport(
                    controller: scroll,
                    count: 100,
                    layoutKey: revision,
                    identity: (index) => index,
                    indexOf: (identity) => identity as int,
                    builder: (context, index) => SizedBox(
                      key: ValueKey('row-$index'),
                      height: index == 2 ? height : 24,
                      child: Text(index == 2 ? 'Tall row' : 'Line $index'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(548);
      await tester.pumpAndSettle();
      update(() {
        height = 200;
        revision++;
      });
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(48, .1));
      expect(find.text('Tall row').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('PatchView supports horizontal scroll when wrap is false', (
    tester,
  ) async {
    final longOld = 'final oldLine = "${'a' * 120}";\n';
    final longNew = 'final newLine = "${'b' * 120}";\n';
    await pump(
      tester,
      PatchView.fromTexts(
        oldText: longOld,
        newText: longNew,
        path: 'a.dart',
        theme: githubDarkTheme,
        wrap: false,
        showLineNumbers: false,
        indicators: DiffIndicators.bars,
        hunkSeparatorStyle: HunkSeparatorStyle.minimal,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HorizontalCode), findsWidgets);
    expect(find.text('┃'), findsNWidgets(2));
  });

  testWidgets('shrinkWrap with stickyHeaders works in unbounded height', (
    tester,
  ) async {
    await pump(
      tester,
      SingleChildScrollView(
        child: PatchView.fromPatch(
          patch,
          theme: githubDarkTheme,
          shrinkWrap: true,
          stickyHeaders: true,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('lib/a.dart'), findsNWidgets(2));
  });

  testWidgets('expanding a gap at the top of the screen preserves scroll', (
    tester,
  ) async {
    final before = lines(1, 60);
    final after = before
        .replaceFirst('v5 = 5', 'v5 = 50')
        .replaceFirst('v45 = 45', 'v45 = 450');
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pump(
      tester,
      SizedBox(
        height: 300,
        child: host(
          (collapsed, expanded, toggleFile, expandGap) => PatchView.fromTexts(
            oldText: before,
            newText: after,
            path: 'values.dart',
            theme: githubDarkTheme,
            scrollController: scroll,
            collapsed: collapsed,
            expanded: expanded,
            onToggleFile: toggleFile,
            onExpandGap: expandGap,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gapFinder = find.textContaining('unchanged lines').first;
    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    final gapTop = tester.getTopLeft(gapFinder).dy;
    final viewTop = tester.getTopLeft(find.byType(PatchView)).dy;
    scroll.jumpTo(scroll.offset + (gapTop - viewTop));
    await tester.pumpAndSettle();
    final beforeOffset = scroll.offset;
    expect(beforeOffset, greaterThan(100));

    await tester.tap(gapFinder);
    await tester.pumpAndSettle();
    // Must stay anchored at the expanded gap, not jump back to 0.
    expect(scroll.offset, greaterThanOrEqualTo(beforeOffset - 30));
    expect(find.text('final v9 = 9;'), findsOneWidget);
  });

  testWidgets(
    'HorizontalCode re-registers when group changes in didUpdateWidget',
    (tester) async {
      final groupA = HorizontalCodeGroup()..offset = 40;
      final groupB = HorizontalCodeGroup()..offset = 120;
      Widget build(HorizontalCodeGroup group) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            height: 30,
            child: HorizontalCode(
              group: group,
              child: const SizedBox(width: 500, height: 20),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build(groupA));
      await tester.pump();
      ScrollableState horizontalScroll() =>
          tester.state<ScrollableState>(find.byType(Scrollable));
      expect(horizontalScroll().position.pixels, 40);

      await tester.pumpWidget(build(groupB));
      await tester.pump();
      expect(horizontalScroll().position.pixels, 120);

      // Moving the old group no longer affects the widget.
      groupA.move(10);
      await tester.pump();
      expect(horizontalScroll().position.pixels, 120);

      groupB.move(200);
      await tester.pump();
      expect(horizontalScroll().position.pixels, 200);
    },
  );
}

final class _Spanish extends DiffLabels {
  const _Spanish();

  @override
  String showUnchangedLines(int count) => count == 1
      ? 'Mostrar 1 línea sin cambios'
      : 'Mostrar $count líneas sin cambios';
}
