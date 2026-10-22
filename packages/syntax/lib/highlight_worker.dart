/// Browser worker entry point. Compile this library with dart compile js.
library;

import 'dart:js_interop';
import 'src/execution/executor.dart';

@JS('self.onmessage')
external set _onMessage(JSFunction listener);
@JS('self.postMessage')
external void _postMessage(JSAny? value);
extension type _Message(JSObject _) implements JSObject {
  external JSAny? get data;
}

/// Starts the worker message loop.
void main() {
  _onMessage = ((JSObject event) {
    final data = Map<String, Object?>.from(
      _Message(event).data.dartify() as Map,
    );
    try {
      final result = computeHighlight(
        HighlightRequest.fromJson(
          Map<String, Object?>.from(data['request'] as Map),
        ),
      );
      _postMessage(
        {'requestId': data['requestId'], 'result': result.toJson()}.jsify(),
      );
    } on Object catch (error, stack) {
      _postMessage(
        {'requestId': data['requestId'], 'error': '$error\n$stack'}.jsify(),
      );
    }
  }).toJS;
}
