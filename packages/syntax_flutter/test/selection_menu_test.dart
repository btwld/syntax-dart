import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'highlighted_code_test.dart' show codeOf, copy, recordClipboard;
import 'material_free_test.dart' show expectPlainTree;

const _source = 'alpha\nbeta';

Widget _code() => HighlightedCode(
  _source,
  language: 'text',
  highlighter: Highlighter(),
  theme: githubDarkTheme,
);

void _narrowViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _expectMenuFits(WidgetTester tester, List<String> labels) {
  final toolbar = tester.getRect(find.byType(SyntaxChrome));
  expect(toolbar.left, greaterThanOrEqualTo(0));
  expect(toolbar.right, lessThanOrEqualTo(320));
  expect(toolbar.width, lessThanOrEqualTo(320));
  expect(toolbar.bottom, lessThanOrEqualTo(640));
  for (final label in labels) {
    final text = find.text(label);
    expect(text.hitTestable(), findsOneWidget);
    final bounds = tester.getRect(text);
    expect(bounds.left, greaterThanOrEqualTo(toolbar.left));
    expect(bounds.right, lessThanOrEqualTo(toolbar.right));
    expect(bounds.top, greaterThanOrEqualTo(toolbar.top));
    expect(bounds.bottom, lessThanOrEqualTo(toolbar.bottom));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _selectWord(WidgetTester tester) async {
  await tester.longPressAt(tester.getTopLeft(codeOf(0)) + const Offset(28, 20));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plain menu overrides the Material overlay fallback text style', (
    tester,
  ) async {
    _narrowViewport(tester);
    await tester.pumpWidget(MaterialApp(home: _code()));
    await tester.pumpAndSettle();
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.toolbar);
    await tester.pumpAndSettle();

    for (final label in ['Copy', 'Select all']) {
      final paragraph = tester.widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      final style = paragraph.text.style!;
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.height, 1.25);
      expect(style.decoration, TextDecoration.none);
      expect(style.color, githubDarkTheme.foregroundColor);
    }
    _expectMenuFits(tester, ['Copy', 'Select all']);
  });

  testWidgets('scaled localized actions wrap and both remain tappable', (
    tester,
  ) async {
    _narrowViewport(tester);
    final copied = recordClipboard(tester);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xff202124),
        localizationsDelegates: const [_LongLabelsDelegate()],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        onGenerateRoute: (_) =>
            PageRouteBuilder<void>(pageBuilder: (_, _, _) => _code()),
      ),
    );
    await tester.pumpAndSettle();
    await _selectWord(tester);
    const labels = _LongLabels();
    _expectMenuFits(tester, [
      labels.copyButtonLabel,
      labels.selectAllButtonLabel,
    ]);
    expectPlainTree(tester);
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.text(labels.copyButtonLabel)),
      ).scale(14),
      28,
    );
    await tester.tap(find.text(labels.copyButtonLabel));
    await tester.pumpAndSettle();
    expect(copied(), 'alpha');

    await _selectWord(tester);
    _expectMenuFits(tester, [
      labels.copyButtonLabel,
      labels.selectAllButtonLabel,
    ]);
    await tester.tap(find.text(labels.selectAllButtonLabel));
    await tester.pumpAndSettle();
    await copy(tester);
    expect(copied(), _source);
    expectPlainTree(tester);
  });
}

class _LongLabels extends DefaultWidgetsLocalizations {
  const _LongLabels();

  @override
  String get copyButtonLabel => 'Copy selected source text';

  @override
  String get selectAllButtonLabel => 'Select all source lines';
}

class _LongLabelsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _LongLabelsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) async => const _LongLabels();

  @override
  bool shouldReload(_LongLabelsDelegate old) => false;
}
