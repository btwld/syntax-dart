import 'dart:async';
import 'dart:js_interop';
import '../edit/editor.dart';
import 'executor.dart';
import 'transport.dart';

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString url);
  external set onmessage(JSFunction listener);
  external set onerror(JSFunction listener);
  external void postMessage(JSAny? data);
  external void terminate();
}
extension type _Message(JSObject _) implements JSObject {
  external JSAny? get data;
}

extension type _WorkerError(JSObject _) implements JSObject {
  external JSString? get message;
}

/// A classic worker compiled with dart compile js; no JavaScript dependency is
/// required. Omitting the URI selects cooperative browser execution.
HighlightExecutor createBrowserHighlightExecutor({Uri? workerUri}) =>
    workerUri == null
    ? CooperativeHighlightExecutor()
    : _BrowserExecutor(workerUri);

final class _BrowserExecutor implements HighlightExecutor {
  _BrowserExecutor(Uri uri) : _worker = _Worker(uri.toString().toJS) {
    _worker.onmessage = ((JSObject event) {
      final data = Map<String, Object?>.from(
        _Message(event).data.dartify() as Map,
      );
      final pending = _pending.remove(data['requestId']);
      if (pending == null) return;
      if (data['error'] case final String error) {
        pending.completeError(StateError(error));
      } else {
        pending.complete(
          HighlightResult.fromJson(
            Map<String, Object?>.from(data['result'] as Map),
          ),
        );
      }
    }).toJS;
    _worker.onerror = ((JSObject event) {
      _failed = true;
      for (final pending in _pending.values) {
        pending.completeError(
          StateError(
            'Highlight worker failed: ${_WorkerError(event).message?.toDart ?? 'unavailable script'}',
          ),
        );
      }
      _pending.clear();
      _worker.terminate();
    }).toJS;
  }
  final _Worker _worker;
  final Map<int, Completer<HighlightResult>> _pending = {};
  int _next = 0;
  bool _disposed = false, _failed = false;
  final _fallback = CooperativeHighlightExecutor();
  final _sender = HighlightSender();
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) async {
    if (_disposed) throw StateError('Executor is disposed');
    cancellation?.throwIfCancelled();
    if (_failed) {
      return _fallback.highlight(request, cancellation: cancellation);
    }
    final id = _next++;
    final completer = _pending[id] = Completer<HighlightResult>();
    _worker.postMessage(
      {'requestId': id, 'request': _sender.encode(request)}.jsify(),
    );
    try {
      final result =
          await (cancellation?.bind(completer.future) ?? completer.future)
              .timeout(const Duration(seconds: 30));
      cancellation?.throwIfCancelled();
      return result;
    } finally {
      _pending.remove(id);
      if (!_disposed && !_failed) _worker.postMessage({'cancel': id}.jsify());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker.terminate();
    _fallback.dispose();
    for (final pending in _pending.values) {
      pending.completeError(const OperationCancelled());
    }
    _pending.clear();
  }
}
