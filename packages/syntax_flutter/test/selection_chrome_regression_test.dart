import 'package:flutter/material.dart' show TextMagnifier;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree, focusAction, neutralApp;

const _cursor = Color(0xffff00aa);
const _theme = SyntaxTheme(
  name: 'selection-regression',
  json: {
    'colors': {
      'editor.background': '#101010',
      'editor.foreground': '#ffffff',
      'editorCursor.foreground': '#ff00aa',
      'editor.selectionBackground': '#334455',
    },
  },
);

Widget _surface(bool patch, {SyntaxSelectionChrome? chrome}) => patch
    ? PatchView.fromTexts(
        oldText: '',
        newText: 'alpha beta\ngamma delta',
        path: 'a.txt',
        theme: _theme,
        highlighter: Highlighter(),
        selectionChrome: chrome,
        onToggleFile: (_) {},
      )
    : HighlightedCode(
        'alpha beta\ngamma delta',
        language: 'text',
        theme: _theme,
        highlighter: Highlighter(),
        selectionChrome: chrome,
      );

// Identify the two painted handles, rather than the larger gesture targets
// Flutter places around them in the overlay.
Finder _handles() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.constraints?.maxWidth == 12 &&
      widget.constraints?.maxHeight == 22,
);

Future<void> _showHandles(WidgetTester tester) async {
  tester
      .state<SelectableRegionState>(find.byType(SelectableRegion))
      .selectAll(SelectionChangedCause.toolbar);
  await tester.pumpAndSettle();
  expect(_handles(), findsNWidgets(2));
}

Future<TestGesture> _dragHandle(WidgetTester tester) async {
  await _showHandles(tester);
  final gesture = await tester.startGesture(tester.getCenter(_handles().last));
  await gesture.moveBy(const Offset(-30, 0));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('patch controls and handles retain theme cursor color', (
    tester,
  ) async {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    await tester.pumpWidget(neutralApp(_surface(true)));
    await tester.pumpAndSettle();
    await _showHandles(tester);
    for (final handle in tester.widgetList<Container>(_handles())) {
      expect((handle.decoration! as BoxDecoration).color, _cursor);
    }
    final inherited = DefaultSelectionStyle.of(
      tester.element(find.byType(SelectableRegion)),
    );
    expect(inherited.cursorColor, _cursor);
    expect(inherited.selectionColor, _theme.selectionColor);

    await focusAction(tester, find.text('a.txt'));
    await tester.pumpAndSettle();
    final borders = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>()
        .where((border) => border.top.width == 2);
    expect(borders.map((border) => border.top.color), contains(_cursor));
    expectPlainTree(tester);
  });

  for (final patch in [false, true]) {
    testWidgets(
      '${patch ? 'patch' : 'code'} touch handle drag shows a magnifier',
      (tester) async {
        await tester.pumpWidget(neutralApp(_surface(patch)));
        await tester.pumpAndSettle();
        final gesture = await _dragHandle(tester);
        expect(find.byType(RawMagnifier), findsOneWidget);
        final lens = tester.getRect(find.byType(RawMagnifier));
        expect(lens.left, greaterThanOrEqualTo(0));
        expect(lens.top, greaterThanOrEqualTo(0));
        expect(lens.right, lessThanOrEqualTo(800));
        expect(lens.bottom, lessThanOrEqualTo(600));
        final loupe = tester.widget<RawMagnifier>(find.byType(RawMagnifier));
        expect(loupe.magnificationScale, greaterThan(1));
        final focalPoint = lens.center + loupe.focalPointOffset;
        await gesture.moveBy(const Offset(-28, 0));
        await tester.pump();
        final moved = tester.widget<RawMagnifier>(find.byType(RawMagnifier));
        expect(
          tester.getRect(find.byType(RawMagnifier)).center +
              moved.focalPointOffset,
          isNot(focalPoint),
        );
        expectPlainTree(tester);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byType(RawMagnifier), findsNothing);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets('plain magnifier follows the caret in an offset root overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xff101010),
        builder: (_, child) =>
            Padding(padding: const EdgeInsets.all(64), child: child),
        onGenerateRoute: (_) =>
            PageRouteBuilder<void>(pageBuilder: (_, _, _) => _surface(false)),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await _dragHandle(tester);
    final lens = tester.getRect(find.byType(RawMagnifier));
    final overlay = tester.getRect(find.byType(Overlay));
    expect(lens.left, greaterThanOrEqualTo(overlay.left));
    expect(lens.top, greaterThanOrEqualTo(overlay.top));
    expect(lens.right, lessThanOrEqualTo(overlay.right));
    expect(lens.bottom, lessThanOrEqualTo(overlay.bottom));
    final state = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    final caretCenter =
        tester.getTopLeft(find.byType(SelectableRegion)) +
        state.selectionEndpoints.last.point -
        Offset(0, state.endGlyphHeight / 2);
    final loupe = tester.widget<RawMagnifier>(find.byType(RawMagnifier));
    expect(lens.center + loupe.focalPointOffset, caretCenter);
    // Removing a selecting view must also remove its active overlay.
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(RawMagnifier), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host can restore adaptive magnification', (tester) async {
    final configuration = TextMagnifier.adaptiveMagnifierConfiguration;
    final chrome = SyntaxSelectionChrome(
      selectionControls: SyntaxSelectionChrome.plain.selectionControls,
      magnifierConfiguration: configuration,
    );
    await tester.pumpWidget(neutralApp(_surface(false, chrome: chrome)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableRegion>(find.byType(SelectableRegion))
          .magnifierConfiguration,
      same(configuration),
    );
    final gesture = await _dragHandle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TextMagnifier), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextMagnifier), findsNothing);
    expectPlainTree(tester);
  });

  testWidgets('host can disable the plain magnifier', (tester) async {
    final chrome = SyntaxSelectionChrome(
      selectionControls: SyntaxSelectionChrome.plain.selectionControls,
      magnifierConfiguration: TextMagnifierConfiguration.disabled,
    );
    await tester.pumpWidget(neutralApp(_surface(true, chrome: chrome)));
    await tester.pumpAndSettle();
    final gesture = await _dragHandle(tester);
    expect(find.byType(RawMagnifier), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expectPlainTree(tester);
  });
}
