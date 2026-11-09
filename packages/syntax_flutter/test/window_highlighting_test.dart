import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

final class _Worker {
  final inputs = <HighlightWindowRequest>[];
  final jobs = <Completer<HighlightWindowResult>>[];
  final configurations = <(Highlighter, SyntaxTheme)>[];
  final cancellations = <HighlightCancellation>[];

  Future<HighlightWindowResult> call(
    HighlightWindowRequest input, {
    required Highlighter highlighter,
    required SyntaxTheme theme,
    required HighlightCancellation cancellation,
  }) {
    inputs.add(input);
    configurations.add((highlighter, theme));
    cancellations.add(cancellation);
    final job = Completer<HighlightWindowResult>();
    jobs.add(job);
    return job.future;
  }

  Future<void> complete(int i) async {
    final config = configurations[i];
    // Simulate a worker that ignores cancellation; the view must still reject it.
    jobs[i].complete(
      await highlightWindow(
        inputs[i],
        highlighter: config.$1,
        theme: config.$2,
        cancellation: HighlightCancellation(),
      ),
    );
  }
}

void main() {
  late Highlighter highlighter;
  setUp(() => highlighter = Highlighter(languages: [dartLanguage]));
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets(
    'code requests built windows, prioritizes a distant jump and ignores disposal',
    (tester) async {
      final worker = _Worker();
      final source = List.generate(
        10000,
        (i) => 'final value$i = $i;',
      ).join('\n');
      await tester.pumpWidget(
        app(
          HighlightedCode(
            source,
            language: 'dart',
            theme: githubDarkTheme,
            highlighter: highlighter,
            executor: worker.call,
          ),
        ),
      );
      expect(worker.inputs, hasLength(1));
      expect(worker.inputs.first.startLine, lessThan(100));
      expect(worker.inputs.first.endLine, lessThanOrEqualTo(128));
      final vertical = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere(
            (s) => axisDirectionToAxis(s.widget.axisDirection) == Axis.vertical,
          );
      vertical.position.jumpTo(vertical.position.maxScrollExtent * 0.9);
      await tester.pump();
      expect(worker.inputs, hasLength(1));
      await tester.runAsync(() => worker.complete(0));
      await tester.pump();
      expect(worker.inputs, hasLength(2));
      expect(worker.inputs[1].startLine, greaterThan(8000));
      expect(
        worker.inputs[1].endLine - worker.inputs[1].startLine,
        lessThanOrEqualTo(64),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(worker.cancellations[1].isCancelled, isTrue);
      await tester.runAsync(() => worker.complete(1));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(worker.inputs, hasLength(2));
    },
  );

  testWidgets(
    'source replacement cancels inflight colors even with the same widget identity',
    (tester) async {
      final worker = _Worker();
      Widget code(String source) => app(
        HighlightedCode(
          source,
          language: 'dart',
          theme: githubDarkTheme,
          highlighter: highlighter,
          executor: worker.call,
        ),
      );
      await tester.pumpWidget(code('/* old'));
      await tester.pumpWidget(code('final replacement = 1;'));
      expect(worker.cancellations.single.isCancelled, isTrue);
      await tester.runAsync(() => worker.complete(0));
      await tester.pump();
      expect(worker.inputs, hasLength(2));
      expect(worker.inputs[1].code, 'final replacement = 1;');
      await tester.runAsync(() => worker.complete(1));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('replacement', findRichText: true),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'full diffs request visible source lines before offscreen output',
    (tester) async {
      final worker = _Worker();
      final before = List.generate(4000, (i) => 'final value$i = $i;');
      final after = [...before]..[3000] = 'final value3000 = 300000;';
      await tester.pumpWidget(
        app(
          PatchView.fromTexts(
            oldText: before.join('\n'),
            newText: after.join('\n'),
            path: 'a.dart',
            theme: githubDarkTheme,
            highlighter: highlighter,
            executor: worker.call,
          ),
        ),
      );
      expect(worker.inputs, hasLength(1));
      expect(worker.inputs.single.startLine, greaterThan(2900));
      expect(worker.inputs.single.endLine, lessThan(3100));
      expect(
        find.textContaining('value3000', findRichText: true),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => worker.complete(0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(worker.inputs, hasLength(1));
    },
  );

  testWidgets(
    'parsed hunk sides reset state and match core syntax and word changes',
    (tester) async {
      final worker = _Worker();
      final file = parsePatch(
        '--- a/a.dart\n+++ b/a.dart\n'
        '@@ -1,2 +1,2 @@\n-/* old\n-*/\n+/* new\n+*/\n'
        '@@ -100 +100 @@\n-final value = 1;\n+final value = 2;\n',
      ).single;
      await tester.pumpWidget(
        app(
          PatchView(
            files: [file],
            theme: githubDarkTheme,
            highlighter: highlighter,
            executor: worker.call,
          ),
        ),
      );
      for (var i = 0; i < worker.jobs.length; i++) {
        await tester.runAsync(() => worker.complete(i));
        await tester.pump();
        await tester.pump();
      }
      expect(worker.inputs, hasLength(4));
      expect(
        worker.inputs.every((r) => r.startLine == 0 && r.endLine <= 2),
        isTrue,
      );
      final expected = DiffHighlightCache(
        highlighter: highlighter,
        theme: githubDarkTheme,
      );
      for (final line in file.hunks.expand((h) => h.lines)) {
        final text = tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => t.textSpan?.toPlainText() == line.text)
            .first
            .textSpan!;
        final spans = <TextSpan>[];
        text.visitChildren((span) {
          if (span is TextSpan && span.text != null) spans.add(span);
          return true;
        });
        expect(
          spans.map((s) => s.text),
          expected.segmentsFor(file, line).map((s) => s.text),
        );
        expect(
          spans.map((s) => s.style?.color?.toARGB32()),
          expected.segmentsFor(file, line).map((s) => s.style.foreground),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'oversize old and new inputs keep visible output without repeated jobs',
    (tester) async {
      var calls = 0;
      Future<HighlightWindowResult> worker(
        HighlightWindowRequest request, {
        required Highlighter highlighter,
        required SyntaxTheme theme,
        required HighlightCancellation cancellation,
      }) async {
        calls++;
        final lines = request.code.split('\n');
        var offset = 0;
        final ranges = <StyledRange>[];
        for (var i = 0; i < request.endLine; i++) {
          if (i >= request.startLine) {
            ranges.add(
              StyledRange(
                offset,
                offset + lines[i].length,
                const TokenStyle(foreground: 0xFF00FF00),
              ),
            );
          }
          offset += lines[i].length + 1;
        }
        return HighlightWindowResult(
          request: request,
          grammarRevision: highlighter.revision,
          theme: theme,
          ranges: ranges,
        );
      }

      final file = parsePatch(
        '--- a/a.dart\n+++ b/a.dart\n'
        '@@ -1,300 +1,300 @@\n'
        '${List.filled(300, '-${'a' * 4000}').join('\n')}\n'
        '${List.filled(300, '+${'b' * 4000}').join('\n')}\n',
      ).single;
      await tester.pumpWidget(
        app(
          PatchView(
            files: [file],
            theme: githubDarkTheme,
            highlighter: highlighter,
            executor: worker,
            inlineDiffMode: InlineDiffMode.none,
            wrap: false,
            mode: DiffMode.split,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final done = calls;
      expect(done, greaterThanOrEqualTo(2));
      expect(done, lessThanOrEqualTo(4));
      await tester.pump();
      await tester.pump();
      expect(calls, done);
      final colored = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (t) =>
                t.textSpan is TextSpan &&
                (t.textSpan! as TextSpan).children?.any(
                      (s) =>
                          s is TextSpan &&
                          s.style?.color?.toARGB32() == 0xFF00FF00,
                    ) ==
                    true,
          );
      expect(colored.length, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
