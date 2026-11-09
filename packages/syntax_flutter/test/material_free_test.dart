import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show Icon, InkWell, Material, MaterialLocalizations, Theme, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_core/themes/github_light.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'highlighted_code_test.dart' show recordClipboard;

// Ported from code_review_flutter/test/neutral_review_test.dart's neutral host
// and keyboard/disabled semantics cases. No Material localization exception.
Widget neutralApp(Widget child) => WidgetsApp(
  color: const Color(0xff202124),
  onGenerateRoute: (_) => PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => DefaultTextStyle(
      style: const TextStyle(fontSize: 14, color: Color(0xffeeeeee)),
      child: child,
    ),
  ),
);

void expectPlainTree(WidgetTester tester) {
  for (final type in [Material, InkWell, Tooltip, Icon, Theme]) {
    expect(find.byType(type), findsNothing, reason: 'Found $type');
  }
  for (final element in find.byType(SelectableRegion).evaluate()) {
    expect(
      Localizations.of<MaterialLocalizations>(element, MaterialLocalizations),
      isNull,
    );
  }
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    expect(text.text.style?.fontFamily, isNot('MaterialIcons'));
  }
  expect(tester.takeException(), isNull);
}

Future<void> focusAction(WidgetTester tester, Finder child) async {
  final control = find
      .ancestor(of: child, matching: find.byType(FocusableActionDetector))
      .first;
  Focus.of(
    tester.element(
      find
          .descendant(of: control, matching: find.byType(GestureDetector))
          .first,
    ),
  ).requestFocus();
  await tester.pump();
}

void main() {
  test('library imports stay outside Material and Cupertino', () {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      expect(
        file.readAsStringSync(),
        isNot(
          matches(
            r'''(?:import|export)\s+['"]package:flutter/(?:material|cupertino|src/material|src/cupertino)''',
          ),
        ),
        reason: file.path,
      );
    }
  });

  for (final mode in DiffMode.values) {
    testWidgets(
      'plain routed host supports $mode disclosure, selection and marker',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final copied = recordClipboard(tester);
        final collapsed = <int>{};
        await tester.pumpWidget(
          neutralApp(
            StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  Expanded(
                    child: PatchView.fromTexts(
                      oldText: '',
                      newText: 'new',
                      path: 'a.txt',
                      highlighter: Highlighter(),
                      theme: githubDarkTheme,
                      mode: mode,
                      collapsed: collapsed,
                      onToggleFile: (file) => setState(() {
                        if (!collapsed.remove(file)) collapsed.add(file);
                      }),
                    ),
                  ),
                  Expanded(
                    child: HighlightedCode(
                      'alpha\nbeta',
                      language: 'text',
                      highlighter: Highlighter(),
                      theme: githubLightTheme,
                      lineNumbers: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SelectableRegion), findsNWidgets(2));
        expect(
          find.bySemanticsLabel('No newline at end of file'),
          findsOneWidget,
        );
        expectPlainTree(tester);

        await focusAction(tester, find.text('a.txt'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(collapsed, {0});
        expect(find.text('new'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(collapsed, isEmpty);
        expect(find.text('new'), findsOneWidget);

        // Open each actual selection overlay and use its copy callback. The
        // patch marker, headers and line numbers must not enter the clipboard.
        for (final (viewType, expected) in [
          (PatchView, 'new'),
          (HighlightedCode, 'alpha\nbeta'),
        ]) {
          final region = find.descendant(
            of: find.byType(viewType),
            matching: find.byType(SelectableRegion),
          );
          final state = tester.state<SelectableRegionState>(region);
          state.selectAll(SelectionChangedCause.toolbar);
          await tester.pumpAndSettle();
          expect(find.text('Copy'), findsOneWidget);
          expectPlainTree(tester);
          await tester.tap(find.text('Copy'));
          await tester.pumpAndSettle();
          expect(copied(), expected);
        }
        semantics.dispose();
      },
    );
  }

  testWidgets('plain secondary menu selects all and preserves keyboard copy', (
    tester,
  ) async {
    final copied = recordClipboard(tester);
    await tester.pumpWidget(
      neutralApp(
        HighlightedCode(
          'alpha\nbeta',
          language: 'text',
          highlighter: Highlighter(),
          theme: githubDarkTheme,
          lineNumbers: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final region = find.byType(SelectableRegion);
    await tester.tapAt(
      tester.getTopLeft(region) + const Offset(60, 8),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsOneWidget);
    expectPlainTree(tester);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied(), 'alpha\nbeta');
    expectPlainTree(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'gap controls support keyboard activation and disabled semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final expanded = <DiffGapId>{};
      final before = [for (var i = 1; i <= 20; i++) 'line $i'].join('\n');
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        neutralApp(
          StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return PatchView.fromTexts(
                oldText: before,
                newText: before.replaceFirst('line 10', 'changed'),
                path: 'a.txt',
                highlighter: Highlighter(),
                theme: githubDarkTheme,
                expanded: expanded,
                onExpandGap: enabled
                    ? (id) => setState(() => expanded.add(id))
                    : null,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gap = find.text('Show 6 unchanged lines');
      await focusAction(tester, gap);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(expanded.length, 1);
      expect(find.text('line 1'), findsOneWidget);
      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      final disabled = find.bySemanticsLabel('Show 7 unchanged lines');
      final flags = tester
          .getSemantics(disabled)
          .getSemanticsData()
          .flagsCollection;
      expect(flags.isButton, isTrue);
      expect(flags.isEnabled, Tristate.isFalse);
      await tester.tap(find.text('Show 7 unchanged lines'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(expanded.length, 1);
      expectPlainTree(tester);
      semantics.dispose();
    },
  );

  testWidgets(
    'injected controls, actions, menu and marker work without Material',
    (tester) async {
      var toggles = 0;
      var menus = 0;
      final chrome = SyntaxSelectionChrome(
        selectionControls: SyntaxSelectionChrome.plain.selectionControls,
        contextMenuBuilder: (_, state) {
          menus++;
          return const Align(
            alignment: Alignment.topLeft,
            child: Text('Custom menu'),
          );
        },
        actionBuilder: (_, action, child) => GestureDetector(
          onTap: action.onInvoke,
          child: Semantics(
            label: 'Custom ${action.kind.name}',
            enabled: action.enabled,
            button: true,
            child: child,
          ),
        ),
        noNewlineMarkerBuilder: (_, message) => const Text('Missing newline'),
      );
      await tester.pumpWidget(
        neutralApp(
          Column(
            children: [
              Expanded(
                child: PatchView.fromTexts(
                  oldText: 'old\n',
                  newText: 'new',
                  path: 'a.txt',
                  highlighter: Highlighter(),
                  theme: githubDarkTheme,
                  selectionChrome: chrome,
                  onToggleFile: (_) => toggles++,
                ),
              ),
              Expanded(
                child: HighlightedCode(
                  'code',
                  language: 'text',
                  highlighter: Highlighter(),
                  theme: githubLightTheme,
                  selectionChrome: chrome,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Missing newline'), findsOneWidget);
      await tester.tap(find.text('a.txt'));
      expect(toggles, 1);
      for (final region in tester.widgetList<SelectableRegion>(
        find.byType(SelectableRegion),
      )) {
        expect(region.selectionControls, same(chrome.selectionControls));
      }
      // A secondary pointer opens the real menu, with no Material delegate.
      await tester.tapAt(
        tester.getCenter(find.text('new')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom menu'), findsOneWidget);
      expect(menus, greaterThan(0));
      expectPlainTree(tester);
    },
  );
}
