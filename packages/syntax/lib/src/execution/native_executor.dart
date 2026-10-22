import 'dart:async';
import 'dart:isolate';
import '../edit/editor.dart';
import 'executor.dart';

/// Executes each request in a cancellable native Dart isolate.
/// Use [HighlightPool] to bound concurrency and share identical requests.
HighlightExecutor createNativeHighlightExecutor() => _NativeExecutor();

final class _NativeJob {
  final result = Completer<HighlightResult>();
  final port = ReceivePort();
  Isolate? isolate;
  void fail(Object error, [StackTrace? stack]) {
    if (!result.isCompleted) result.completeError(error, stack);
    close();
  }

  void close() {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}

final class _NativeExecutor implements HighlightExecutor {
  bool _disposed = false;
  final Set<_NativeJob> _jobs = {};
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) async {
    if (_disposed) throw StateError('Executor is disposed');
    cancellation?.throwIfCancelled();
    final job = _NativeJob();
    _jobs.add(job);
    final unsubscribe = cancellation?.onCancel(
      () => job.fail(const OperationCancelled()),
    );
    job.port.listen((Object? message) {
      if (message is Map) {
        try {
          final result = HighlightResult.fromJson(
            Map<String, Object?>.from(message),
          );
          if (!job.result.isCompleted) job.result.complete(result);
          job.close();
        } on Object catch (error, stack) {
          job.fail(error, stack);
        }
      } else if (message is List) {
        job.fail(RemoteError('${message.first}', '${message.last}'));
      } else if (!job.result.isCompleted) {
        job.fail(
          StateError('Highlight isolate exited before delivering a result'),
        );
      }
    });
    // Await spawn independently so disposal and cancellation can close the
    // result before the new isolate has reached its entry point.
    unawaited(
      Isolate.spawn<(SendPort, Map<String, Object?>)>(
        _nativeMain,
        (job.port.sendPort, request.toJson()),
        onError: job.port.sendPort,
        onExit: job.port.sendPort,
      ).then((isolate) {
        job.isolate = isolate;
        if (job.result.isCompleted) job.close();
      }, onError: (Object error, StackTrace stack) => job.fail(error, stack)),
    );
    try {
      return await job.result.future;
    } finally {
      unsubscribe?.call();
      job.close();
      _jobs.remove(job);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _jobs.toList()) {
      job.fail(const OperationCancelled());
    }
    _jobs.clear();
  }
}

void _nativeMain((SendPort, Map<String, Object?>) input) {
  Isolate.exit(
    input.$1,
    computeHighlight(HighlightRequest.fromJson(input.$2)).toJson(),
  );
}
