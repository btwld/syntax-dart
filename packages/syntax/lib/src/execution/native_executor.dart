import 'dart:async';
import 'dart:isolate';
import '../edit/editor.dart';
import 'executor.dart';
import 'transport.dart';

/// Retains bounded grammar checkpoints and token windows in a native isolate.
/// Use [HighlightPool] to bound concurrency and share identical requests.
HighlightExecutor createNativeHighlightExecutor() => _NativeExecutor();

final class _NativeExecutor implements HighlightExecutor {
  final _port = ReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<HighlightResult>>{};
  final _sender = HighlightSender();
  Isolate? _isolate;
  SendPort? _worker;
  int _next = 0;
  bool _disposed = false;
  Object? _failure;

  _NativeExecutor() {
    // Observe initialization failures even if disposal wins before first use.
    unawaited(_ready.future.then<void>((_) {}, onError: (Object _) {}));
    _port.listen((Object? message) {
      if (message is SendPort) {
        _worker = message;
        if (!_ready.isCompleted) _ready.complete(message);
      } else if (message is Map) {
        final pending = _pending.remove(message['requestId']);
        if (pending == null) return;
        if (message['error'] case final String error) {
          pending.completeError(StateError(error));
        } else {
          try {
            pending.complete(
              HighlightResult.fromJson(
                Map<String, Object?>.from(message['result'] as Map),
              ),
            );
          } on Object catch (error, stack) {
            pending.completeError(error, stack);
          }
        }
      } else if (!_disposed) {
        _fail(
          message is List
              ? RemoteError('${message.first}', '${message.last}')
              : StateError('Highlight isolate exited'),
        );
      }
    });
    unawaited(
      Isolate.spawn<SendPort>(
        _nativeMain,
        _port.sendPort,
        onError: _port.sendPort,
        onExit: _port.sendPort,
      ).then((isolate) {
        _isolate = isolate;
        if (_disposed || _failure != null) {
          isolate.kill(priority: Isolate.immediate);
        }
      }, onError: (Object error) => _fail(error)),
    );
  }

  void _fail(Object error) {
    _failure = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _port.close();
  }

  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) async {
    if (_disposed) throw StateError('Executor is disposed');
    cancellation?.throwIfCancelled();
    if (_failure case final failure?) throw failure;
    final worker = await (cancellation?.bind(_ready.future) ?? _ready.future);
    if (_disposed) throw const OperationCancelled();
    cancellation?.throwIfCancelled();
    final id = _next++;
    final pending = _pending[id] = Completer<HighlightResult>();
    worker.send({'requestId': id, 'request': _sender.encode(request)});
    try {
      return await (cancellation?.bind(pending.future) ?? pending.future);
    } finally {
      _pending.remove(id);
      _worker?.send({'cancel': id});
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fail(const OperationCancelled());
  }
}

void _nativeMain(SendPort output) {
  final input = ReceivePort();
  final executor = CooperativeHighlightExecutor();
  final receiver = HighlightReceiver();
  final pending = <int, CancellationToken>{};
  Future<void> run(Map<Object?, Object?> data) async {
    final id = data['requestId'] as int;
    final cancellation = pending[id] = CancellationToken();
    try {
      final result = await executor.highlight(
        receiver.decode(Map<String, Object?>.from(data['request'] as Map)),
        cancellation: cancellation,
      );
      output.send({'requestId': id, 'result': result.toJson()});
    } on OperationCancelled {
      // A superseding viewport keeps any useful grammar checkpoints.
    } on Object catch (error, stack) {
      output.send({'requestId': id, 'error': '$error\n$stack'});
    } finally {
      pending.remove(id);
    }
  }

  output.send(input.sendPort);
  input.listen((Object? message) {
    final data = message as Map;
    if (data['cancel'] case final int id) {
      pending[id]?.cancel();
    } else {
      unawaited(run(data));
    }
  });
}
