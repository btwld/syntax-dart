import 'package:syntax_flutter/syntax_flutter.dart';

// Small, project-owned examples with enough context to explore expansion.
const retryBefore = r'''import 'dart:async';

/// Retries a request after a temporary connection failure.
class RetryPolicy {
  const RetryPolicy();

  Future<T> run<T>(Future<T> Function() request) async {
    return request();
  }
}

class SyncClient {
  const SyncClient({required this.policy});

  final RetryPolicy policy;

  Future<String> fetch(String path) {
    return policy.run(() => send(path));
  }

  Future<String> send(String path) async {
    final response = await transport(path);
    return response.trim();
  }

  Future<String> transport(String path) async {
    return 'Response from $path';
  }
}
''';

const retryAfter = r'''import 'dart:async';

/// Retries a request after a temporary connection failure.
class RetryPolicy {
  const RetryPolicy({this.maxAttempts = 3});

  final int maxAttempts;

  Future<T> run<T>(Future<T> Function() request) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await request();
      } on TimeoutException {
        if (attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
  }
}

class SyncClient {
  const SyncClient({required this.policy});

  final RetryPolicy policy;

  Future<String> fetch(String path) {
    return policy.run(() => send(path));
  }

  Future<String> send(String path) async {
    final response = await transport(path).timeout(const Duration(seconds: 5));
    return response.trim();
  }

  Future<String> transport(String path) async {
    return 'Response from $path';
  }
}
''';

const configBefore = r'''class ClientOptions {
  const ClientOptions({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;
}
''';
const configAfter = r'''class ClientOptions {
  const ClientOptions({
    this.timeout = const Duration(seconds: 5),
    this.maxAttempts = 3,
  });

  final Duration timeout;
  final int maxAttempts;
}
''';
const testAfter = r'''import 'package:test/test.dart';
import 'package:example/retry_policy.dart';

void main() {
  test('returns a successful response', () async {
    const policy = RetryPolicy(maxAttempts: 3);
    final result = await policy.run(() async => 'connected');

    expect(result, 'connected');
  });
}
''';

const conflictSource = r'''class ClientOptions {
  const ClientOptions({
<<<<<<< current
    this.timeout = const Duration(seconds: 10),
||||||| base
    this.timeout = const Duration(seconds: 30),
=======
    this.timeout = const Duration(seconds: 5),
>>>>>>> incoming
  });

  final Duration timeout;
}
''';

List<FileDiff> showcaseDiffs() => [
  diffTexts(
    retryBefore,
    retryAfter,
    path: 'lib/client/retry_policy.dart',
    id: 'retry',
    contextLines: 2,
  ),
  diffTexts(
    configBefore,
    configAfter,
    path: 'lib/client/options.dart',
    id: 'options',
    contextLines: 2,
  ),
  diffTexts(
    '',
    testAfter,
    path: 'test/retry_policy_test.dart',
    id: 'tests',
    contextLines: 2,
  ),
];

const showcaseFiles = [
  SourceFile(
    id: 'retry',
    path: 'lib/client/retry_policy.dart',
    text: retryAfter,
  ),
  SourceFile(id: 'options', path: 'lib/client/options.dart', text: configAfter),
  SourceFile(id: 'tests', path: 'test/retry_policy_test.dart', text: testAfter),
];
