import 'dart:async';
import 'dart:convert';
import 'editor.dart';
import 'text_document.dart';

/// A live document that accepts text or UTF-8 chunks and provisional tails.
final class StreamDocumentController extends SyntaxObservable {
  /// Starts an empty or partially populated streamed file.
  StreamDocumentController(SourceFile file)
    : editor = EditorController(file: file);

  /// The session used by file, editor and terminal surfaces.
  final EditorController editor;
  ByteConversionSink? _decoder;
  StreamSubscription<Object>? _subscription;
  bool _complete = false, _cancelled = false;

  /// Whether the producer finished normally.
  bool get isComplete => _complete;

  /// Whether further delivery has been cancelled.
  bool get isCancelled => _cancelled;

  /// Last decoding or stream failure.
  Object? error;
  void _check() {
    checkAlive();
    if (_complete || _cancelled) throw StateError('Stream is closed');
  }

  void _append(String text) {
    if (text.isEmpty) return;
    final end = editor.document.length;
    editor.applyEdits([OffsetEdit(end, end, text)]);
    notifyListeners();
  }

  void _fail(Object failure, StackTrace stack) {
    error = failure;
    _cancelled = true;
    _decoder = null;
    unawaited(_subscription?.cancel());
    if (_completion?.isCompleted == false) {
      _completion!.completeError(failure, stack);
    }
    if (!isDisposed) notifyListeners();
  }

  /// Appends decoded text or bytes. Byte chunks may split a UTF-8 character.
  void add(Object chunk) {
    _check();
    try {
      if (chunk is String) {
        if (chunk.isEmpty) return;
        _closeDecoder();
        _append(chunk);
      } else if (chunk is List<int>) {
        _decoder ??= const Utf8Decoder().startChunkedConversion(
          _StreamTextSink(_append),
        );
        _decoder!.add(chunk);
      } else {
        throw ArgumentError('Expected a string or UTF-8 bytes');
      }
    } on Object catch (failure, stack) {
      _fail(failure, stack);
      rethrow;
    }
  }

  void _closeDecoder() {
    final decoder = _decoder;
    _decoder = null;
    decoder?.close();
  }

  /// Replaces only the last unfinished logical line.
  void replaceProvisional(String text) {
    _check();
    try {
      _closeDecoder();
    } on Object catch (failure, stack) {
      _fail(failure, stack);
      rethrow;
    }
    final doc = editor.document;
    editor.applyEdits([
      OffsetEdit(doc.lineStart(doc.lineCount - 1), doc.length, text),
    ]);
    notifyListeners();
  }

  /// Decodes any remaining bytes, then closes the producer side.
  void finish() {
    _check();
    try {
      _closeDecoder();
      _complete = true;
      unawaited(_subscription?.cancel());
      if (_completion?.isCompleted == false) _completion!.complete();
    } on Object catch (failure, stack) {
      _fail(failure, stack);
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Subscribes to one producer. Completion and cancellation stay observable.
  Future<void> bind(Stream<Object> stream) async {
    _check();
    if (_subscription != null) {
      throw StateError('A producer is already attached');
    }
    final done = Completer<void>();
    _completion = done;
    _subscription = stream.listen(
      (chunk) {
        try {
          add(chunk);
        } on Object catch (failure, stack) {
          _fail(failure, stack);
        }
      },
      onError: (Object failure, StackTrace stack) {
        _fail(failure, stack);
      },
      onDone: () {
        try {
          if (!_cancelled) finish();
          if (!done.isCompleted) done.complete();
        } on Object catch (failure, stack) {
          if (!done.isCompleted) done.completeError(failure, stack);
        }
      },
      cancelOnError: true,
    );
    return done.future;
  }

  Completer<void>? _completion;

  /// Stops delivery while keeping the accumulated document available.
  void cancel() {
    if (_cancelled || _complete) return;
    _cancelled = true;
    _decoder = null;
    unawaited(_subscription?.cancel());
    if (_completion?.isCompleted == false) _completion!.complete();
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    editor.dispose();
    super.dispose();
  }
}

final class _StreamTextSink implements Sink<String> {
  _StreamTextSink(this.onText);
  final void Function(String) onText;
  @override
  void add(String data) => onText(data);
  @override
  void close() {}
}
