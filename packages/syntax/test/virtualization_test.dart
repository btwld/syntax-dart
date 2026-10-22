import 'dart:async';
import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:syntax/src/execution/transport.dart';
import 'package:test/test.dart';

void main() {
  final source = SourceFile(
    id: 'large',
    path: 'a.dart',
    text: [
      for (var i = 0; i < 10000; i++)
        i == 8950
            ? '/* begin'
            : i == 9050
            ? 'end */'
            : 'final value$i = $i;',
    ].join('\n'),
  );
  HighlightRequest request(
    int start,
    int end, {
    SyntaxTheme? theme,
    SourceFile? file,
  }) => HighlightRequest(
    file: file ?? source,
    languages: [dartLanguage],
    theme: theme ?? githubDarkTheme,
    startLine: start,
    endLine: end,
  );
  test('nearby viewports reuse checkpoints and bounded raw tokens', () async {
    final executor = CooperativeHighlightExecutor(sliceLines: 500);
    addTearDown(executor.dispose);
    final initial = request(9000, 9040);
    expect(
      (await executor.highlight(initial)).toJson(),
      computeHighlight(initial).toJson(),
    );
    final work = executor.stats.tokenizedLines;
    final adjacent = request(9010, 9060);
    expect(
      (await executor.highlight(adjacent)).toJson(),
      computeHighlight(adjacent).toJson(),
    );
    expect(executor.stats.tokenizedLines - work, lessThan(150));
    final after = executor.stats.tokenizedLines;
    final light = request(9010, 9060, theme: githubLightTheme);
    expect(
      (await executor.highlight(light)).toJson(),
      computeHighlight(light).toJson(),
    );
    expect(executor.stats.tokenizedLines, after);
    for (var line = 9060; line < 9900; line += 60) {
      await executor.highlight(request(line, line + 60));
    }
    expect(executor.stats.cachedLines, lessThanOrEqualTo(512));
    expect(executor.stats.checkpoints, lessThanOrEqualTo(2048));
    final backward = request(8990, 9060);
    expect(
      (await executor.highlight(backward)).toJson(),
      computeHighlight(backward).toJson(),
    );
  });
  test('worker transport sends source once and evicts old snapshots', () {
    final sender = HighlightSender(), receiver = HighlightReceiver();
    final first = sender.encode(request(0, 20));
    expect(first['source'], isNotNull);
    receiver.decode(first);
    final next = sender.encode(request(30, 50));
    expect(next.containsKey('source'), isFalse);
    expect(receiver.decode(next).toJson(), request(30, 50).toJson());
    for (var i = 0; i < 5; i++) {
      receiver.decode(
        sender.encode(
          request(
            0,
            1,
            file: SourceFile(id: '$i', path: '', text: 'x'),
          ),
        ),
      );
    }
    final reloaded = sender.encode(request(0, 1));
    expect(reloaded['source'], isNotNull);
    expect(receiver.decode(reloaded).file.text, source.text);
  });
  test(
    'source identity includes exact content even at the same revision',
    () async {
      final executor = CooperativeHighlightExecutor();
      addTearDown(executor.dispose);
      await executor.highlight(
        request(
          0,
          1,
          file: const SourceFile(id: 'same', path: 'a.dart', text: '/* x'),
        ),
      );
      final changed = request(
        0,
        1,
        file: const SourceFile(id: 'same', path: 'a.dart', text: 'true'),
      );
      expect(
        (await executor.highlight(changed)).toJson(),
        computeHighlight(changed).toJson(),
      );
    },
  );
  test(
    'presentation reuses overscan and keeps ready colors during scrolling',
    () async {
      final editor = EditorController(file: source);
      final executor = _Pending();
      final presentation = PresentationController(
        editor: editor,
        highlighter: Highlighter(languages: [dartLanguage]),
        theme: githubDarkTheme,
        executor: executor,
        overscan: 30,
      );
      addTearDown(() {
        presentation.dispose();
        editor.dispose();
      });
      presentation.setViewport(0, 20);
      final first = presentation.flush();
      executor.complete(0);
      await first;
      presentation.setViewport(5, 25);
      await Future<void>.delayed(Duration.zero);
      expect(executor.requests, hasLength(1));
      expect(presentation.line(5), isNotNull);
      presentation.setViewport(40, 60);
      final next = presentation.flush();
      expect(presentation.line(5), isNotNull);
      expect(presentation.isLoading, isTrue);
      executor.complete(1);
      await next;
      expect(presentation.line(59), isNotNull);
      presentation.setViewport(500, 520);
      final abandoned = presentation.flush();
      presentation.setViewport(40, 60);
      expect(presentation.isLoading, isFalse);
      executor.complete(2);
      await abandoned;
      expect(presentation.line(59), isNotNull);
      expect(presentation.line(500), isNull);
      editor.insertText('// changed\n');
      expect(presentation.snapshot, isNull);
    },
  );
  test(
    'persistent native executor cancels and accepts subsequent viewports',
    () async {
      final executor = createNativeHighlightExecutor();
      addTearDown(executor.dispose);
      final cancellation = CancellationToken();
      final pending = executor.highlight(
        request(9000, 9010),
        cancellation: cancellation,
      );
      cancellation.cancel();
      await expectLater(pending, throwsA(isA<OperationCancelled>()));
      for (final range in [(0, 20), (30, 50)]) {
        final input = request(range.$1, range.$2);
        expect(
          (await executor.highlight(input)).toJson(),
          computeHighlight(input).toJson(),
        );
      }
    },
  );
}

class _Pending implements HighlightExecutor {
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

  void complete(int index) =>
      requests[index].$2.complete(computeHighlight(requests[index].$1));
  @override
  void dispose() {}
}
