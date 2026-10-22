import 'dart:js_interop';

@JS('self.onmessage')
external set _onMessage(JSFunction listener);

void main() {
  void fail(JSObject _) {
    throw StateError('Worker failure fixture');
  }

  _onMessage = fail.toJS;
}
