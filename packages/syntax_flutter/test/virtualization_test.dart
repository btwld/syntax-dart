import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
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
