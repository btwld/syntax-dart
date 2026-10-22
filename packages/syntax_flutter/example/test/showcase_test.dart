import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'package:syntax_example/showcase.dart';

Future<void> launch(
  WidgetTester tester, {
  Size size = const Size(1360, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: ShowcaseHome(dark: true, onBrightness: () {}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('merge example colors its sections and resolves inline', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('example-3')));
    await tester.pumpAndSettle();
    expect(find.text('Current change · current'), findsOneWidget);
    expect(find.text('Common ancestor'), findsOneWidget);
    expect(find.text('Incoming change · incoming'), findsOneWidget);
    final view = tester.widget<MergeConflictView>(
      find.byType(MergeConflictView),
    );
    expect(view.textStyle, isNotNull);
    expect(view.wrap, isTrue);
    await tester.tap(find.text('Wrap on'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MergeConflictView>(find.byType(MergeConflictView)).wrap,
      isFalse,
    );
    await tester.tap(find.text('Keep incoming'));
    await tester.pumpAndSettle();
    expect(view.controller.file.text, contains('seconds: 5'));
    expect(view.controller.file.text, isNot(contains('seconds: 10')));
    expect(find.text('All conflicts resolved'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Current change · current'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review has working file folds, context expansion and split view',
    (tester) async {
      await launch(tester);
      var review = tester.widget<PatchView>(find.byType(PatchView)).controller!;
      expect(review.files, hasLength(3));
      expect(review.isCollapsed('options'), isTrue);
      await tester.tap(find.text('lib/client/retry_policy.dart'));
      await tester.pumpAndSettle();
      expect(review.isCollapsed('retry'), isTrue);
      await tester.tap(find.text('lib/client/retry_policy.dart'));
      await tester.pumpAndSettle();
      expect(review.isCollapsed('retry'), isFalse);
      final count = review.layout.length;
      await tester.tap(find.text('Collapse files'));
      await tester.pumpAndSettle();
      expect(review.files.every((f) => review.isCollapsed(f.id)), isTrue);
      expect(find.text('Expand files'), findsOneWidget);
      await tester.tap(find.text('Expand files'));
      await tester.pumpAndSettle();
      expect(review.files.any((f) => review.isCollapsed(f.id)), isFalse);
      await tester.tap(find.byKey(const ValueKey('mode-split')));
      await tester.pumpAndSettle();
      expect(review.mode, DiffMode.split);
      expect(find.text('BEFORE'), findsOneWidget);
      await tester.tap(find.text('Expand context'));
      await tester.pumpAndSettle();
      expect(review.layout.length, greaterThan(count));
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      review = tester.widget<PatchView>(find.byType(PatchView)).controller!;
      expect(review.mode, DiffMode.unified);
      expect(review.isCollapsed('options'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review decisions and local comments are resettable', (
    tester,
  ) async {
    await launch(tester);
    final review = tester.widget<PatchView>(find.byType(PatchView)).controller!;
    review.select(const DiffSelection('retry', DiffSide.newer, 7, 7));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comment'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Please add a timeout test.',
    );
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();
    expect(review.annotations, hasLength(2));
    expect(find.text('Please add a timeout test.'), findsOneWidget);
    await tester.tap(find.text('Resolve').first);
    await tester.pumpAndSettle();
    expect(find.text('Reopen'), findsOneWidget);
    final before = review.file('retry').additions;
    await tester.tap(find.text('Accept').first);
    await tester.pumpAndSettle();
    expect(review.file('retry').additions, lessThan(before));
    expect(find.textContaining('Change accepted in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file previews fold and editor drafts survive navigation', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('example-1')));
    await tester.pumpAndSettle();
    expect(find.byType(SyntaxFileView), findsWidgets);
    await tester.tap(find.text('Collapse files'));
    await tester.pumpAndSettle();
    expect(find.byType(SyntaxFileView), findsNothing);
    await tester.tap(find.text('Expand files'));
    await tester.pumpAndSettle();
    expect(find.byType(SyntaxFileView), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('example-2')));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<SyntaxEditor>(find.byType(SyntaxEditor))
        .controller;
    editor.insertText('// retained draft\n');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('example-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('example-2')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SyntaxEditor>(find.byType(SyntaxEditor)).controller,
      same(editor),
    );
    expect(editor.document.text, startsWith('// retained draft'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream pauses and resets without stale delivery', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('example-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start stream'));
    await tester.pump(const Duration(milliseconds: 500));
    final stream = tester
        .widget<SyntaxFileView>(find.byType(SyntaxFileView))
        .controller;
    expect(stream.document.text, isNotEmpty);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    final paused = stream.document.text;
    await tester.pump(const Duration(seconds: 1));
    expect(stream.document.text, paused);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Ready when you are.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file drafts survive closing the editor and folding', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('example-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit lib/client/retry_policy.dart'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'final draft = 42;');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collapse files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand files'));
    await tester.pumpAndSettle();
    final preview = tester.widget<SyntaxFileView>(
      find.byType(SyntaxFileView).first,
    );
    expect(preview.controller.document.text, 'final draft = 42;');
    await tester.tap(find.byTooltip('Edit lib/client/retry_policy.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.text('Edits applied to lib/client/retry_policy.dart.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(preview.controller.document.text, isNot('final draft = 42;'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'suggestion preview, acceptance, diagnostics and reset stay in sync',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const ValueKey('example-2')));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<SyntaxEditor>(find.byType(SyntaxEditor))
          .controller;
      expect(editor.diagnostics, hasLength(1));
      await tester.tap(find.text('Preview suggestion'));
      await tester.pumpAndSettle();
      expect(find.text('Accept suggestion'), findsOneWidget);
      await tester.tap(find.text('Accept suggestion'));
      await tester.pumpAndSettle();
      expect(editor.document.text, contains('maxAttempts = 5'));
      expect(editor.diagnostics, isEmpty);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(editor.document.text, contains('maxAttempts = 3'));
      expect(editor.diagnostics, hasLength(1));
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(editor.diagnostics, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact layout exposes examples without overflow', (
    tester,
  ) async {
    await launch(tester, size: const Size(420, 850));
    expect(find.text('Every change, in context.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Collapse files'));
    await tester.pumpAndSettle();
    expect(find.text('Expand files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large file exposes a virtual window and direct jumps', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('example-5')));
    await tester.pumpAndSettle();
    expect(find.text('Wrap off'), findsOneWidget);
    final file = tester.widget<SyntaxFileView>(find.byType(SyntaxFileView));
    expect(file.controller.document.lineCount, 100000);
    await tester.tap(find.text('Line 90,001'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Visible lines 90001–'), findsOneWidget);
    expect(find.byType(RichText).evaluate().length, lessThan(220));
    await tester.tap(find.text('Back to top'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Visible lines 1–'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
