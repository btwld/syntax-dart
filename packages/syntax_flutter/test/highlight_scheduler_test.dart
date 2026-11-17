import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_core/themes/github_light.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

final class _DelayedExecutor {
  final requests = <HighlightWindowRequest>[];
  final jobs = <Completer<HighlightWindowResult>>[];
  final configurations = <(Highlighter, SyntaxTheme, int)>[];
  final cancellations = <HighlightCancellation>[];

  Future<HighlightWindowResult> call(
    HighlightWindowRequest input, {
    required Highlighter highlighter,
    required SyntaxTheme theme,
    required HighlightCancellation cancellation,
  }) {
    requests.add(input);
    configurations.add((highlighter, theme, highlighter.revision));
    cancellations.add(cancellation);
    final job = Completer<HighlightWindowResult>();
    jobs.add(job);
    return job.future;
  }

  void complete(int index, {HighlightWindowRequest? override}) {
    final config = configurations[index];
    jobs[index].complete(
      HighlightWindowResult(
        request: override ?? requests[index],
        grammarRevision: config.$3,
        theme: config.$2,
        ranges: [
          StyledRange(0, 1, TokenStyle(foreground: config.$2.foreground)),
        ],
      ),
    );
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late Highlighter highlighter;
  late _DelayedExecutor executor;
  setUp(() {
    highlighter = Highlighter(languages: [dartLanguage]);
    executor = _DelayedExecutor();
  });
  HighlightWindowRequest request(
    String id, {
    int revision = 0,
    String code = 'true',
    int start = 0,
    int end = 1,
  }) => HighlightWindowRequest(
    fileId: id,
    revision: revision,
    code: code,
    language: 'dart',
    startLine: start,
    endLine: end,
  );
  HighlightWindowScheduler cache({
    int entries = 8,
    int units = 1024 * 1024,
    void Function()? changed,
    void Function(Object, StackTrace)? error,
  }) {
    final result = HighlightWindowScheduler(
      highlighter: highlighter,
      theme: githubDarkTheme,
      executor: executor.call,
      maxEntries: entries,
      maxCodeUnits: units,
      onChanged: changed ?? () {},
      onError: error,
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    'ready windows survive revisits; stale revision and exact content do not',
    () async {
      final scheduler = cache();
      final a = request('a');
      expect(scheduler.rangesFor(a), isNull);
      await _tick();
      executor.complete(0);
      await _tick();
      final ready = scheduler.rangesFor(a);
      expect(ready, isNotNull);
      scheduler.rangesFor(request('b'));
      expect(scheduler.rangesFor(a), same(ready));
      expect(scheduler.rangesFor(request('a', revision: 1)), isNull);
      expect(
        scheduler.rangesFor(request('a', revision: 1, code: '/* x')),
        isNull,
      );
      expect(scheduler.pendingCount, 2);
      expect(scheduler.entryCount, 2);
    },
  );

  test(
    'pending work and retained input stay bounded, including stale active work',
    () async {
      final scheduler = cache(entries: 3, units: 120000);
      final files = [
        for (var i = 0; i < 15; i++) request('$i', code: '$i${'x' * 29998}'),
      ];
      scheduler.rangesFor(files.first);
      await _tick();
      for (final input in files.skip(1)) {
        scheduler.rangesFor(input);
        expect(scheduler.entryCount, lessThanOrEqualTo(3));
        expect(scheduler.retainedCodeUnits, lessThanOrEqualTo(120000));
        expect(scheduler.pendingCount, lessThanOrEqualTo(3));
      }
      expect(executor.requests, hasLength(1));
      scheduler.configure(
        highlighter: highlighter,
        theme: githubLightTheme,
        executor: executor.call,
      );
      expect(executor.cancellations.single.isCancelled, isTrue);
      for (final input in files) {
        scheduler.rangesFor(input);
        expect(scheduler.entryCount, lessThanOrEqualTo(3));
        expect(scheduler.retainedCodeUnits, lessThanOrEqualTo(120000));
      }
      await _tick();
      expect(executor.requests, hasLength(1));
      for (var i = 0; i < executor.jobs.length; i++) {
        executor.complete(i);
        await _tick();
      }
      expect(scheduler.pendingCount, 0);
      expect(scheduler.entryCount, lessThanOrEqualTo(3));
    },
  );

  test(
    'one oversize active input prevents accumulating oversize pending sources',
    () async {
      final scheduler = cache(units: 10);
      scheduler.rangesFor(request('a', code: 'a' * 100));
      await _tick();
      scheduler.rangesFor(request('b', code: 'b' * 100));
      expect(scheduler.entryCount, 1);
      expect(scheduler.pendingCount, 1);
      expect(scheduler.retainedCodeUnits, 100);
      executor.complete(0);
      await _tick();
      scheduler.rangesFor(request('b', code: 'b' * 100));
      await _tick();
      expect(executor.requests, hasLength(2));
      expect(scheduler.entryCount, 1);
    },
  );

  test(
    'latest viewport takes priority over queued offscreen windows',
    () async {
      final scheduler = cache();
      scheduler.rangesFor(request('a'));
      await _tick();
      scheduler.rangesFor(request('b'));
      scheduler.rangesFor(request('visible'));
      executor.complete(0);
      await _tick();
      expect(executor.requests[1].fileId, 'visible');
    },
  );

  test(
    'content, grammar, theme and executor changes reject active results',
    () async {
      final scheduler = cache();
      final old = request('a');
      scheduler.rangesFor(old);
      await _tick();
      final changed = request('a', code: 'false');
      scheduler.rangesFor(changed);
      expect(executor.cancellations.single.isCancelled, isTrue);
      executor.complete(0);
      await _tick();
      expect(executor.requests, hasLength(2));
      expect(scheduler.rangesFor(changed), isNull);
      highlighter.addLanguage(dartLanguage);
      scheduler.rangesFor(changed);
      executor.complete(1);
      await _tick();
      expect(executor.requests, hasLength(3));
      scheduler.configure(
        highlighter: highlighter,
        theme: githubLightTheme,
        executor: executor.call,
      );
      scheduler.rangesFor(changed);
      executor.complete(2);
      await _tick();
      expect(executor.requests, hasLength(4));
      executor.complete(3);
      await _tick();
      expect(scheduler.rangesFor(changed), isNotNull);
      final replacement = _DelayedExecutor();
      scheduler.configure(
        highlighter: highlighter,
        theme: githubLightTheme,
        executor: replacement.call,
      );
      expect(scheduler.rangesFor(changed), isNull);
      await _tick();
      expect(replacement.requests, hasLength(1));
      replacement.complete(0);
      await _tick();
    },
  );

  test(
    'LRU windows evict and executor failures stay plain without error leaks',
    () async {
      var errors = 0;
      final scheduler = cache(entries: 2, error: (_, _) => errors++);
      final a = request('a'), b = request('b'), c = request('c');
      scheduler.rangesFor(a);
      await _tick();
      executor.complete(0);
      await _tick();
      final ready = scheduler.rangesFor(a);
      scheduler.rangesFor(b);
      await _tick();
      executor.complete(1);
      await _tick();
      scheduler.rangesFor(a); // touch a; b should be evicted
      scheduler.rangesFor(c);
      await _tick();
      executor.jobs[2].completeError(StateError('invalid grammar'));
      await _tick();
      expect(errors, 1);
      expect(scheduler.rangesFor(a), same(ready));
      expect(scheduler.rangesFor(c), isNull);
      await _tick();
      expect(executor.requests, hasLength(3));
      expect(scheduler.rangesFor(b), isNull);
      expect(scheduler.entryCount, 2);
    },
  );

  test(
    'clearing rejects inflight cache population; mismatched identity stays plain',
    () async {
      final scheduler = cache();
      final input = request('a');
      scheduler.rangesFor(input);
      await _tick();
      scheduler.clear();
      executor.complete(0);
      await _tick();
      expect(scheduler.entryCount, 0);
      scheduler.rangesFor(input);
      await _tick();
      executor.complete(1, override: request('other'));
      await _tick();
      expect(scheduler.rangesFor(input), isNull);
    },
  );

  test(
    'disposal discards late work without repaint or new execution',
    () async {
      var paints = 0;
      final scheduler = cache(changed: () => paints++);
      scheduler.rangesFor(request('a'));
      await _tick();
      scheduler.rangesFor(request('b'));
      scheduler.dispose();
      executor.complete(0);
      await _tick();
      expect(paints, 0);
      expect(executor.requests, hasLength(1));
      expect(scheduler.entryCount, 0);
      expect(scheduler.retainedCodeUnits, 0);
      expect(scheduler.rangesFor(request('a')), isNull);
    },
  );
  test('windows of one oversize source share its input charge', () async {
    final scheduler = cache(units: 10);
    final code = 'a\n' * 50;
    scheduler.rangesFor(request('a', code: code));
    await _tick();
    executor.complete(0);
    await _tick();
    scheduler.rangesFor(request('a', code: code, start: 1, end: 2));
    await _tick();
    expect(executor.requests, hasLength(2));
    expect(scheduler.entryCount, 2);
    expect(scheduler.retainedCodeUnits, code.length);
    executor.complete(1);
    await _tick();
    expect(scheduler.pendingCount, 0);
  });
}
