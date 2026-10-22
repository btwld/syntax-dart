@TestOn('browser')
library;

import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:test/test.dart';

void main() {
  test('compiled worker returns equivalent source presentation', () async {
    final worker = createBrowserHighlightExecutor(
      workerUri: Uri.base.resolve('fixtures/highlight_worker.js'),
    );
    addTearDown(worker.dispose);
    final request = HighlightRequest(
      file: const SourceFile(
        id: 'worker',
        path: 'test.dart',
        text: '/* 😀 */\nfinal value = 42;\n',
        revision: 3,
      ),
      languages: [dartLanguage],
      theme: githubDarkTheme,
    );
    expect(
      (await worker.highlight(request)).toJson(),
      computeHighlight(request).toJson(),
    );
    final cancellation = CancellationToken()..cancel();
    await expectLater(
      worker.highlight(request, cancellation: cancellation),
      throwsA(isA<OperationCancelled>()),
    );
  });
  test(
    'missing worker reports failure and subsequent work falls back',
    () async {
      final worker = createBrowserHighlightExecutor(
        workerUri: Uri.base.resolve('/missing_worker.js'),
      );
      addTearDown(worker.dispose);
      final request = HighlightRequest(
        file: const SourceFile(id: 'fallback', path: '', text: 'plain'),
        languages: const [],
        theme: githubDarkTheme,
      );
      await expectLater(worker.highlight(request), throwsStateError);
      expect(
        (await worker.highlight(request)).lines.single.single.text,
        'plain',
      );
    },
  );
  test(
    'a worker crash rejects pending jobs and falls back on the next request',
    () async {
      final executor = createBrowserHighlightExecutor(
        workerUri: Uri.base.resolve('fixtures/failing_worker.js'),
      );
      addTearDown(executor.dispose);
      final request = HighlightRequest(
        file: const SourceFile(id: 'crash', path: '', text: 'source'),
        languages: const [],
        theme: githubDarkTheme,
      );
      await expectLater(executor.highlight(request), throwsStateError);
      expect(
        (await executor.highlight(request)).lines.single.single.text,
        'source',
      );
    },
  );
  test('disposing a worker immediately cancels its pending delivery', () async {
    final executor = createBrowserHighlightExecutor(
      workerUri: Uri.base.resolve('fixtures/highlight_worker.js'),
    );
    final request = HighlightRequest(
      file: const SourceFile(id: 'dispose', path: '', text: 'source'),
      languages: const [],
      theme: githubDarkTheme,
    );
    final pending = executor.highlight(request);
    executor.dispose();
    await expectLater(pending, throwsA(isA<OperationCancelled>()));
  });
}
