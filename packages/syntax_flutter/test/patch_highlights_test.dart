import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/src/patch_highlights.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

class _CountingLines extends ListBase<DiffLine> {
  _CountingLines(this.values);

  final List<DiffLine> values;
  int reads = 0;

  @override
  int get length => values.length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  DiffLine operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, DiffLine value) =>
      throw UnsupportedError('read only');
}

void main() {
  late Highlighter highlighter;
  setUp(() => highlighter = Highlighter(languages: [dartLanguage]));

  PatchWindowHighlights cache() {
    final scheduler = HighlightWindowScheduler(
      highlighter: highlighter,
      theme: githubDarkTheme,
      onChanged: () {},
    );
    addTearDown(scheduler.dispose);
    return PatchWindowHighlights(scheduler);
  }

  testWidgets('20 stationary built windows finish once and stay ready', (
    tester,
  ) async {
    final calls = <String, int>{};
    Future<HighlightWindowResult> worker(
      HighlightWindowRequest request, {
      required Highlighter highlighter,
      required SyntaxTheme theme,
      required HighlightCancellation cancellation,
    }) async {
      calls.update(request.fileId, (count) => count + 1, ifAbsent: () => 1);
      return HighlightWindowResult(
        request: request,
        grammarRevision: highlighter.revision,
        theme: theme,
        ranges: [
          StyledRange(
            0,
            request.code.length,
            const TokenStyle(foreground: 0xFF00FF00),
          ),
        ],
      );
    }

    final file = parsePatch(
      '--- a/a.dart\n+++ b/a.dart\n'
      '${List.generate(20, (i) => '@@ -0,0 +${i * 10 + 1} @@\n+final value$i = $i;\n').join()}',
    ).single;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SingleChildScrollView(
                child: PatchView(
                  files: [file],
                  theme: githubDarkTheme,
                  highlighter: highlighter,
                  executor: worker,
                  shrinkWrap: true,
                  selectable: false,
                  inlineDiffMode: InlineDiffMode.none,
                ),
              );
            },
          ),
        ),
      ),
    );
    // A fixed frame count makes a repeating job loop fail deterministically,
    // rather than waiting for pumpAndSettle to time out.
    for (var frame = 0; frame < 100; frame++) {
      await tester.pump();
    }
    expect(calls, hasLength(20));
    expect(calls.values, everyElement(1));
    for (var frame = 0; frame < 30; frame++) {
      rebuild(() {});
      await tester.pump();
    }
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump();
    }
    expect(calls.values, everyElement(1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final colored = tester
        .widgetList<Text>(find.byType(Text))
        .where(
          (text) =>
              text.textSpan is TextSpan &&
              (text.textSpan! as TextSpan).children?.any(
                    (span) =>
                        span is TextSpan &&
                        span.style?.color?.toARGB32() == 0xFF00FF00,
                  ) ==
                  true,
        );
    expect(colored, hasLength(20));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('equal pairs in distinct files both retain changed-word emphasis', () {
    final highlights = cache();
    FileDiff file(String id) =>
        diffTexts('final x = 1;', 'final x = 2;', path: '$id.dart');
    final a = file('a'), b = file('b');
    final first = a.hunks.single.lines.last;
    final second = b.hunks.single.lines.last;
    expect(first, second);
    expect(identical(first, second), isFalse);
    for (final file in [a, b]) {
      for (final line in file.hunks.single.lines) {
        final segments = highlights.segments(
          file,
          line,
          highlighter,
          githubDarkTheme,
          null,
          InlineDiffMode.mergedWords,
        );
        expect(
          segments
              .where((segment) => segment.changed)
              .map((s) => s.text)
              .join(),
          line.kind == DiffLineKind.removed ? '1' : '2',
        );
      }
    }
  });

  test(
    'cached parsed-side lookup does no work proportional to hunk lines per row',
    () {
      final highlights = cache();
      final lines = _CountingLines(
        List.generate(
          100000,
          (i) => DiffLine(DiffLineKind.added, 'line $i', newNumber: 500 + i),
        ),
      );
      final file = FileDiff(
        oldPath: 'a.txt',
        newPath: 'a.txt',
        kind: FileDiffKind.modified,
        hunks: [
          DiffHunk(
            oldStart: 0,
            oldCount: 0,
            newStart: 500,
            newCount: lines.length,
            lines: lines,
          ),
        ],
      );
      highlights.segments(
        file,
        lines.values[99970],
        highlighter,
        githubDarkTheme,
        null,
        InlineDiffMode.none,
      );
      lines.reads = 0;
      for (var repaint = 0; repaint < 2; repaint++) {
        for (final line in lines.values.skip(99970)) {
          highlights.segments(
            file,
            line,
            highlighter,
            githubDarkTheme,
            null,
            InlineDiffMode.none,
          );
        }
      }
      expect(
        lines.reads,
        0,
        reason:
            'Reuse the side index and derive each line index from its source number',
      );
    },
  );
}
