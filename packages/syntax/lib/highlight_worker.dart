/// Browser worker entry point. Compile this library with dart compile js.
library;

import 'dart:js_interop';
import 'dart:async';
import 'src/execution/executor.dart';
import 'src/execution/transport.dart';
import 'src/edit/editor.dart';

@JS('self.onmessage')
external set _onMessage(JSFunction listener);
@JS('self.postMessage')
external void _postMessage(JSAny? value);
extension type _Message(JSObject _) implements JSObject {
  external JSAny? get data;
}

/// Starts the worker message loop.
void main() {
  final executor = CooperativeHighlightExecutor();
  final receiver = HighlightReceiver();
  final pending = <int, CancellationToken>{};
  Future<void> run(Map<String, Object?> data) async {
    final id = data['requestId'] as int;
    final cancellation = pending[id] = CancellationToken();
    try {
      final result = await executor.highlight(
        receiver.decode(Map<String, Object?>.from(data['request'] as Map)),
        cancellation: cancellation,
      );
      _postMessage({'requestId': id, 'result': result.toJson()}.jsify());
    } on OperationCancelled {
      // The viewport no longer needs this result.
    } on Object catch (error, stack) {
      _postMessage({'requestId': id, 'error': '$error\n$stack'}.jsify());
    } finally {
      pending.remove(id);
    }
  }

  _onMessage = ((JSObject event) {
    final data = Map<String, Object?>.from(
      _Message(event).data.dartify() as Map,
    );
    if (data['cancel'] case final int id) {
      pending[id]?.cancel();
    } else {
      unawaited(run(data));
    }
  }).toJS;
}
