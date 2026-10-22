import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
  testWidgets(
    'stream keeps existing text colored while highlighting catches up',
    (tester) async {
      final stream = StreamDocumentController(
        const SourceFile(
          id: 'stream',
          path: 'stream.dart',
          text: 'final stable = 1;\n',
        ),
      );
      final executor = _DelayedExecutor();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyntaxFileView(
              controller: stream.editor,
              highlighter: Highlighter(languages: [dartLanguage]),
              theme: githubDarkTheme,
              executor: executor,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(executor.requests, isNotEmpty);
      executor.completeLatest();
      await tester.pumpAndSettle();
      final line = find.text('final stable = 1;', findRichText: true);
      final element = tester.element(line);
      final original = tester.widget<RichText>(line).text;
      final colored = <InlineSpan>[];
      original.visitChildren((span) {
        if (span.style?.color != null) colored.add(span);
        return true;
      });
      expect(colored.length, greaterThan(1));
      for (final chunk in ['final next', ' = 2;', '\n// done']) {
        stream.add(chunk);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget<RichText>(line).text, original);
        expect(tester.element(line), same(element));
      }
      executor.completeLatest();
      await tester.pumpAndSettle();
      expect(tester.widget<RichText>(line).text, original);
      expect(find.text('final next = 2;', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      stream.dispose();
    },
  );
  testWidgets(
    '100000 lines jump directly and retain mounted rows while scrolling',
    (tester) async {
      final editor = EditorController(
        file: SourceFile(
          id: 'large',
          path: 'events.txt',
          text: List.generate(100000, (i) => 'record $i').join('\n'),
        ),
      );
      final scroll = ScrollController();
      final executor = _RecordingExecutor();
      var visible = (0, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyntaxFileView(
              controller: editor,
              highlighter: Highlighter(),
              theme: githubDarkTheme,
              wrap: false,
              scrollController: scroll,
              executor: executor,
              onVisibleLinesChanged: (start, end) => visible = (start, end),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(visible.$1, 0);
      editor.reveal(
        const DocumentRange(
          DocumentPosition(90000, 0),
          DocumentPosition(90000, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(visible.$1, 90000);
      expect(find.text('record 90000', findRichText: true), findsOneWidget);
      expect(find.byType(RichText).evaluate().length, lessThan(160));
      expect(
        executor.requests.every((r) => r.endLine! - r.startLine < 100),
        isTrue,
      );
      final requests = executor.requests.length;
      final retained = tester.element(
        find.text('record 90005', findRichText: true),
      );
      scroll.jumpTo(scroll.offset + 21);
      await tester.pumpAndSettle();
      expect(visible.$1, 90001);
      expect(executor.requests.length, requests);
      expect(
        tester.element(find.text('record 90005', findRichText: true)),
        same(retained),
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(visible.$2, 100000);
      expect(find.text('record 99999', findRichText: true), findsOneWidget);
      expect(find.byType(RichText).evaluate().length, lessThan(160));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
      scroll.dispose();
      executor.dispose();
    },
  );
}

class _RecordingExecutor implements HighlightExecutor {
  final requests = <HighlightRequest>[];
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) async {
    requests.add(request);
    return computeHighlight(request);
  }

  @override
  void dispose() {}
}

class _DelayedExecutor implements HighlightExecutor {
  final requests = <(HighlightRequest, Completer<HighlightResult>)>[];

  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) {
    final completer = Completer<HighlightResult>();
    requests.add((request, completer));
    return completer.future;
  }

  void completeLatest() {
    for (final (request, completer) in requests) {
      if (!completer.isCompleted) completer.complete(computeHighlight(request));
    }
  }

  @override
  void dispose() {}
}
