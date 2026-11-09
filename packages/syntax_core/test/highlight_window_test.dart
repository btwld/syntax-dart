import 'dart:async';

import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/syntax.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_core/themes/github_light.dart';
import 'package:test/test.dart';

void main() {
  late Highlighter highlighter;
  setUp(() => highlighter = Highlighter(languages: [dartLanguage]));

  HighlightWindowRequest request(
    String code,
    int start,
    int end, {
    String id = 'file',
    int revision = 0,
    String language = 'dart',
  }) => HighlightWindowRequest(
    fileId: id,
    revision: revision,
    code: code,
    language: language,
    startLine: start,
    endLine: end,
  );

  Future<HighlightWindowResult> run(
    HighlightWindowRequest input, {
    HighlightWindowCache? cache,
    SyntaxTheme? theme,
    HighlightCancellation? cancellation,
  }) => (cache?.highlight ?? highlightWindow)(
    input,
    highlighter: highlighter,
    theme: theme ?? githubDarkTheme,
    cancellation: cancellation ?? HighlightCancellation(),
  );

  List<StyledRange> expected(
    String code,
    int start,
    int end, [
    SyntaxTheme? theme,
  ]) {
    final offsets = [0];
    for (var i = code.indexOf('\n'); i >= 0; i = code.indexOf('\n', i + 1)) {
      offsets.add(i + 1);
    }
    return highlighter
        .highlightRanges(
          code,
          language: 'dart',
          theme: theme ?? githubDarkTheme,
        )
        .where(
          (r) =>
              r.start >= offsets[start] &&
              (end >= offsets.length || r.start < offsets[end]),
        )
        .toList();
  }

  test(
    'window retains preceding grammar state without offscreen styled output',
    () async {
      const code = '/*\r\ninside 🙂\r\n*/\r\nfinal a = 1;\n';
      final result = await run(request(code, 1, 2, id: 'f', revision: 7));
      expect(result.fileId, 'f');
      expect(result.revision, 7);
      expect(result.startLine, 1);
      expect(result.endLine, 2);
      expect(result.request.code, code);
      expect(result.grammarRevision, highlighter.revision);
      expect(result.theme, same(githubDarkTheme));
      expect(result.ranges, expected(code, 1, 2));
      expect(result.ranges.single.start, 4);
      expect(result.ranges.single.end, 13);
      expect(() => result.ranges.clear(), throwsUnsupportedError);
    },
  );

  test(
    'empty, trailing and unknown-language windows keep exact offsets',
    () async {
      expect((await run(request('', 0, 1))).ranges, isEmpty);
      expect((await run(request('a\n', 1, 2))).ranges, isEmpty);
      expect((await run(request('a', 1, 1))).ranges, isEmpty);
      final plain = await run(request('x\r\ny🙂\n', 1, 2, language: 'unknown'));
      expect(plain.ranges, [
        StyledRange(3, 6, TokenStyle(foreground: githubDarkTheme.foreground)),
      ]);
      for (final bounds in [(-1, 1), (2, 1), (0, 3), (3, 3)]) {
        await expectLater(
          run(request('a\n', bounds.$1, bounds.$2)),
          throwsRangeError,
        );
      }
    },
  );

  test(
    'nearby windows reuse checkpoints and raw tokens, including theme changes',
    () async {
      final cache = HighlightWindowCache();
      final source = [
        for (var i = 0; i < 10000; i++)
          i == 8950
              ? '/* begin'
              : i == 9050
              ? 'end */'
              : 'final value$i = $i;',
      ].join('\n');
      expect(
        (await run(request(source, 9000, 9040), cache: cache)).ranges,
        expected(source, 9000, 9040),
      );
      final before = cache.tokenizedLines;
      expect(
        (await run(request(source, 9010, 9060), cache: cache)).ranges,
        expected(source, 9010, 9060),
      );
      expect(cache.tokenizedLines - before, lessThan(150));
      final after = cache.tokenizedLines;
      expect(
        (await run(
          request(source, 9010, 9060),
          cache: cache,
          theme: githubLightTheme,
        )).ranges,
        expected(source, 9010, 9060, githubLightTheme),
      );
      expect(cache.tokenizedLines, after);
      for (var i = 9060; i < 9900; i += 60) {
        await run(request(source, i, i + 60), cache: cache);
      }
      expect(cache.cachedLines, lessThanOrEqualTo(512));
      expect(cache.checkpoints, lessThanOrEqualTo(2048));
      expect(
        (await run(request(source, 8990, 9060), cache: cache)).ranges,
        expected(source, 8990, 9060),
      );
    },
  );

  test(
    'exact content, source revision, language and grammar revision invalidate cache',
    () async {
      final cache = HighlightWindowCache();
      await run(request('/* x', 0, 1), cache: cache);
      expect(
        (await run(request('true', 0, 1), cache: cache)).ranges,
        expected('true', 0, 1),
      );
      var before = cache.tokenizedLines;
      await run(request('true', 0, 1, revision: 1), cache: cache);
      expect(cache.tokenizedLines, before + 1);
      before = cache.tokenizedLines;
      highlighter.addLanguage(dartLanguage);
      final result = await run(
        request('true', 0, 1, revision: 1),
        cache: cache,
      );
      expect(cache.tokenizedLines, before + 1);
      expect(result.grammarRevision, highlighter.revision);
      expect(
        (await run(
          request('true', 0, 1, language: 'unknown'),
          cache: cache,
        )).ranges,
        [StyledRange(0, 4, TokenStyle(foreground: githubDarkTheme.foreground))],
      );
    },
  );

  test(
    'LRU sources, raw lines and checkpoints have hard retention bounds',
    () async {
      final cache = HighlightWindowCache(
        maxEntries: 2,
        maxCodeUnits: 100,
        maxCachedLines: 2,
        maxCheckpoints: 3,
      );
      final input = request('a\nb\nc\nd\ne', 0, 5, id: 'a');
      await run(input, cache: cache);
      expect(cache.cachedLines, 2);
      expect(cache.checkpoints, lessThanOrEqualTo(3));
      await run(request('true', 0, 1, id: 'b'), cache: cache);
      await run(input, cache: cache);
      await run(request('false', 0, 1, id: 'c'), cache: cache);
      final before = cache.tokenizedLines;
      await run(request('true', 0, 1, id: 'b'), cache: cache);
      expect(cache.tokenizedLines, before + 1);
      expect(cache.entryCount, 2);
      await run(request('x' * 200, 0, 1, id: 'big'), cache: cache);
      expect(cache.entryCount, 1);
      expect(cache.retainedCodeUnits, 200);
      cache.clear();
      expect(cache.entryCount, 0);
      expect(cache.cachedLines, 0);
      expect(cache.checkpoints, 0);
    },
  );

  test(
    'cancellation before and during prefix work prevents delivery and permits reuse',
    () async {
      final cache = HighlightWindowCache(sliceLines: 1);
      final cancelled = HighlightCancellation()
        ..cancel()
        ..cancel();
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.throwIfCancelled, throwsA(isA<HighlightCancelled>()));
      await expectLater(
        run(request('true', 0, 1), cache: cache, cancellation: cancelled),
        throwsA(isA<HighlightCancelled>()),
      );
      final source = List.filled(2000, 'final a = 1;').join('\n');
      final cancellation = HighlightCancellation();
      final pending = run(
        request(source, 1900, 1910),
        cache: cache,
        cancellation: cancellation,
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<HighlightCancelled>()),
      );
      Timer.run(cancellation.cancel);
      await assertion;
      expect(cache.tokenizedLines, lessThan(1900));
      expect(
        (await run(request('true', 0, 1), cache: cache)).ranges,
        expected('true', 0, 1),
      );
    },
  );

  test(
    'large prefix work yields and cache clearing rejects inflight reinsertion',
    () async {
      final cache = HighlightWindowCache(sliceLines: 10);
      var ticks = 0;
      final ticker = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      addTearDown(ticker.cancel);
      final source = List.filled(12000, 'final a = 1;').join('\n');
      final pending = run(request(source, 11980, 12000), cache: cache);
      cache.clear();
      final result = await pending;
      expect(ticks, greaterThan(5));
      expect(result.ranges, expected(source, 11980, 12000));
      expect(cache.entryCount, 0);
    },
  );
  test(
    'cancellation releases custom frame yields and ignores late completion',
    () async {
      final frame = Completer<void>();
      final cache = HighlightWindowCache(
        sliceLines: 1,
        yieldControl: () => frame.future,
      );
      final cancellation = HighlightCancellation();
      final pending = run(
        request('a\nb', 0, 2),
        cache: cache,
        cancellation: cancellation,
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<HighlightCancelled>()),
      );
      cancellation.cancel();
      await assertion;
      frame.complete();
      await Future<void>.delayed(Duration.zero);
      expect(cache.tokenizedLines, 1);
    },
  );
}
