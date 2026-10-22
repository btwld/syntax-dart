import 'dart:async';
import 'dart:convert';
import 'document.dart';
import 'edit/text_document.dart';
import 'grammar/grammar.dart';
import 'grammar/scope_stack.dart';
import 'highlighter.dart';
import 'theme/theme.dart';

/// Semantic scope categories useful for editor interactions.
enum TokenKind {
  /// Ordinary source tokens.
  other,

  /// Comment text or delimiters.
  comment,

  /// Quoted or interpolated string content.
  string,

  /// Regular-expression literal content.
  regularExpression,
}

/// Classifies comment, string and regex scopes without depending on a palette.
TokenKind classifyToken(ScopeStack scopes) {
  for (final scope in scopes.scopes.reversed) {
    if (scope.startsWith('comment')) return TokenKind.comment;
    if (scope.startsWith('string.regexp') || scope.startsWith('string.regex')) {
      return TokenKind.regularExpression;
    }
    if (scope.startsWith('string')) return TokenKind.string;
  }
  return TokenKind.other;
}

/// Retains exact line text, raw tokens and grammar states for incremental reuse.
final class HighlightedLine {
  /// Retains exact line text, raw tokens and grammar states for incremental reuse.
  HighlightedLine(this.text, this.tokens, this.startState, this.endState);

  /// Exact source text, including original line endings where applicable.
  final String text;

  /// Token boundaries and scopes for this source line.
  final List<Token> tokens;

  /// Grammar state before this line, or null at the document start.
  final StateStack? startState;

  /// Grammar state carried forward to the next line.
  final StateStack endState;
  SyntaxTheme? _theme;
  List<ThemedToken>? _themed;

  /// Resolves retained raw token scopes using the supplied palette.
  List<ThemedToken> themed(SyntaxTheme theme) {
    if (_theme != theme) {
      _theme = theme;
      _themed = themeTokens(text, tokens, theme);
    }
    return _themed!;
  }
}

/// Incremental tokenization with viewport priority and cooperative background
/// slices. A changed grammar requires a new session; changing a theme does not.
final class LiveHighlighter extends SyntaxObservable {
  /// Attaches incremental, cooperatively scheduled highlighting to an indexed document.
  LiveHighlighter(
    this.document,
    this.grammar, {
    this.sliceLines = 200,
    this.priorityEndLine = 100,
  }) {
    if (sliceLines < 1) throw ArgumentError.value(sliceLines, 'sliceLines');
    document.addListener(_update);
    _update();
  }

  /// Subscribed source; disposing this highlighter leaves the document alive.
  final TextDocument document;

  /// Compiled grammar owned by the current isolate.
  final Grammar grammar;

  /// Maximum lines processed between cooperative scheduling yields.
  final int sliceLines;

  /// Exclusive viewport limit prioritized before remaining background work.
  int priorityEndLine;
  List<HighlightedLine?> _lines = [];
  List<HighlightedLine?> _candidates = [];
  int _next = 0;
  Timer? _timer;
  bool _paused = false;

  /// Monotonically increasing content revision for rejecting obsolete work.
  int get revision => document.revision;

  /// Whether any document lines still need tokenization.
  bool get pending => _next < document.lineCount;

  /// Logical line count, including an empty final line after a terminator.
  int get lineCount => document.lineCount;

  /// Inclusive zero-based start of the latest retokenized range.
  int lastStartLine = 0;

  /// Exclusive zero-based end of the latest retokenized range.
  int lastEndLine = 0;

  void _update() {
    _timer?.cancel();
    _timer = null;
    final old = _lines;
    final count = document.lineCount;
    var prefix = 0;
    while (prefix < count &&
        prefix < old.length &&
        old[prefix]?.text == document.lineText(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < count - prefix &&
        suffix < old.length - prefix &&
        old[old.length - 1 - suffix]?.text ==
            document.lineText(count - 1 - suffix)) {
      suffix++;
    }
    _lines = List.filled(count, null);
    _candidates = List.filled(count, null);
    for (var i = 0; i < prefix; i++) {
      _lines[i] = old[i];
    }
    for (var i = 0; i < suffix; i++) {
      _candidates[count - 1 - i] = old[old.length - 1 - i];
    }
    _next = prefix;
    if (!_paused) {
      flush(endLine: priorityEndLine);
      _schedule();
    }
  }

  /// Cached line data, or null while this line awaits tokenization.
  HighlightedLine? line(int index) {
    checkAlive();
    RangeError.checkValidIndex(index, _lines);
    return _lines[index];
  }

  /// Returns cached line colors, or plain text if tokenization is pending.
  List<ThemedToken> themedLine(int index, SyntaxTheme theme) {
    final ready = line(index);
    if (ready != null) return ready.themed(theme);
    return [
      ThemedToken(
        document.lineText(index),
        0,
        TokenStyle(foreground: theme.foreground),
        ScopeStack.root('text.plain'),
      ),
    ];
  }

  /// Prioritizes a visible range while preserving all preceding grammar state.
  void prioritize(int startLine, int endLine) {
    RangeError.checkValidRange(startLine, endLine, lineCount);
    priorityEndLine = endLine;
    flush(endLine: endLine);
    _schedule();
  }

  /// Synchronously finishes through the exclusive limit, or the whole document.
  void flush({int? endLine}) {
    checkAlive();
    final end = (endLine ?? lineCount).clamp(0, lineCount);
    final start = _next;
    var state = _next == 0 ? null : _lines[_next - 1]?.endState;
    while (_next < end) {
      final text = document.lineText(_next);
      final old = _candidates[_next];
      if (old != null && old.startState == state && old.text == text) {
        _lines[_next] = old;
      } else {
        final result = grammar.tokenizeLine(text, state);
        _lines[_next] = HighlightedLine(
          text,
          result.tokens,
          state,
          result.endState,
        );
      }
      state = _lines[_next]!.endState;
      _next++;
    }
    lastStartLine = start;
    lastEndLine = _next;
    if (_next > start) notifyListeners();
  }

  void _schedule() {
    if (_paused || !pending || isDisposed || _timer != null) return;
    _timer = Timer(Duration.zero, () {
      _timer = null;
      flush(endLine: _next + sliceLines);
      _schedule();
    });
  }

  /// Stops scheduled work while retaining state for synchronous viewport requests.
  void pause() {
    checkAlive();
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Resumes cooperative background highlighting from the first invalid line.
  void resume() {
    checkAlive();
    _paused = false;
    _schedule();
  }

  /// Builds absolute UTF-16 styled ranges for the requested line window.
  List<StyledRange> ranges(
    SyntaxTheme theme, {
    int startLine = 0,
    int? endLine,
  }) {
    final end = endLine ?? lineCount;
    RangeError.checkValidRange(startLine, end, lineCount);
    return [
      for (var i = startLine; i < end; i++)
        for (final token in themedLine(i, theme))
          if (token.text.isNotEmpty)
            StyledRange(
              document.lineStart(i) + token.offset,
              document.lineStart(i) + token.offset + token.text.length,
              token.style,
            ),
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    document.removeListener(_update);
    _lines = [];
    _candidates = [];
    super.dispose();
  }
}

/// An emitted source line with its absolute location and exact terminator.
final class StreamHighlightLine {
  /// An emitted source line with its absolute location and exact terminator.
  const StreamHighlightLine({
    required this.index,
    required this.offset,
    required this.text,
    required this.terminator,
    required this.tokens,
  });

  /// Zero-based logical line index and absolute UTF-16 source offset.
  final int index, offset;

  /// Source line body and its original LF, CRLF, CR or empty terminator.
  final String text, terminator;

  /// Token boundaries and scopes for this source line.
  final List<ThemedToken> tokens;
}

/// Accepts strings and UTF-8 chunks. Completed lines are stable; [preview]
/// retokenizes only the unfinished line without advancing grammar state.
final class StreamingHighlighter {
  /// Creates an incremental decoder and tokenizer for streamed source.
  StreamingHighlighter({required this.grammar, required this.theme});

  /// Compiled grammar owned by the current isolate.
  final Grammar grammar;

  /// Palette used to resolve token scopes into presentation styles.
  SyntaxTheme theme;
  String _pending = '';
  StateStack? _state;
  int _index = 0, _offset = 0;
  bool _closed = false;
  ByteConversionSink? _decoder;

  void _check() {
    if (_closed) throw StateError('Stream is closed');
  }

  /// Accepts text or UTF-8 bytes and emits complete lines, retaining the partial tail.
  List<StreamHighlightLine> push(Object chunk) {
    _check();
    if (chunk is String) {
      if (chunk.isNotEmpty) {
        _decoder?.close();
        _decoder = null;
        _pending += chunk;
      }
    } else if (chunk is List<int>) {
      _decoder ??= const Utf8Decoder(allowMalformed: true)
          .startChunkedConversion(
            StringConversionSink.fromStringSink(
              _StreamSink((value) => _pending += value),
            ),
          );
      _decoder!.add(chunk);
    } else {
      throw ArgumentError('Expected text or UTF-8 bytes');
    }
    return _drain(false);
  }

  StreamHighlightLine _line(
    String text,
    String terminator, {
    bool commit = true,
  }) {
    final result = grammar.tokenizeLine(text, _state);
    final line = StreamHighlightLine(
      index: _index,
      offset: _offset,
      text: text,
      terminator: terminator,
      tokens: List.unmodifiable(themeTokens(text, result.tokens, theme)),
    );
    if (commit) {
      _state = result.endState;
      _index++;
      _offset += text.length + terminator.length;
    }
    return line;
  }

  /// Provisional highlighting of the unfinished final line without advancing state.
  StreamHighlightLine get preview {
    _check();
    return _line(_pending, '', commit: false);
  }

  List<StreamHighlightLine> _drain(bool finalChunk) {
    final result = <StreamHighlightLine>[];
    var consumed = 0;
    final matches = RegExp(r'\r\n|\r|\n').allMatches(_pending);
    for (final match in matches) {
      if (!finalChunk && match[0] == '\r' && match.end == _pending.length) {
        break;
      }
      result.add(_line(_pending.substring(consumed, match.start), match[0]!));
      consumed = match.end;
    }
    _pending = _pending.substring(consumed);
    if (finalChunk) {
      result.add(_line(_pending, ''));
      _pending = '';
    }
    return result;
  }

  /// Completes delivery and returns the final buffered output.
  List<StreamHighlightLine> finish() {
    _check();
    _decoder?.close();
    _decoder = null;
    final result = _drain(true);
    _closed = true;
    return result;
  }

  /// Consumes a producer stream, emitting lines through normal completion.
  Stream<StreamHighlightLine> bind(Stream<Object> input) async* {
    try {
      await for (final chunk in input) {
        yield* Stream.fromIterable(push(chunk));
      }
      yield* Stream.fromIterable(finish());
    } finally {
      dispose();
    }
  }

  /// Cancels pending work and releases retained resources; the object must not be reused.
  void dispose() {
    _closed = true;
    _decoder = null;
    _pending = '';
    _state = null;
  }
}

final class _StreamSink implements StringSink {
  _StreamSink(this.add);
  final void Function(String) add;
  @override
  void write(Object? object) => add('$object');
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      add(objects.join(separator));
  @override
  void writeCharCode(int charCode) => add(String.fromCharCode(charCode));
  @override
  void writeln([Object? object = '']) => add('$object\n');
}

/// Lazy grammar loading with dependency closure and shared pending requests.
final class LanguageRegistry {
  /// Registers lazy language loaders against a shared highlighter.
  LanguageRegistry(this.highlighter);

  /// Highlighter receiving loaded languages and their dependency closure.
  final Highlighter highlighter;
  final Map<String, Future<Language> Function()> _loaders = {};
  final Map<String, List<String>> _dependencies = {};
  final Map<String, Future<Language>> _pending = {};
  final Map<String, String> _aliases = {};

  /// Registers a lazy language and the grammars it includes or injects.
  void register(
    String name,
    Future<Language> Function() loader, {
    List<String> dependencies = const [],
    List<String> aliases = const [],
  }) {
    if (_loaders.containsKey(name)) {
      throw ArgumentError('Language already registered: $name');
    }
    _loaders[name] = loader;
    _dependencies[name] = List.unmodifiable(dependencies);
    for (final alias in aliases) {
      _aliases.putIfAbsent(alias, () => name);
    }
  }

  /// Installs the complete dependency closure before reporting readiness.
  /// Simultaneous callers share raw loads, including mutually embedded grammars.
  Future<Language> resolve(String name) async {
    final canonical = _loaders.containsKey(name)
        ? name
        : _aliases[name] ?? name;
    final visited = <String>{};
    Future<Language> visit(String id) async {
      if (!visited.add(id)) return highlighter.language(id)!;
      final language = await _load(id);
      for (final dependency in _dependencies[id] ?? const <String>[]) {
        await visit(dependency);
      }
      return language;
    }

    return visit(canonical);
  }

  Future<Language> _load(String name) async {
    if (_pending[name] case final pending?) return pending;
    final loaded = highlighter.language(name);
    if (loaded != null) return loaded;
    final loader = _loaders[name];
    if (loader == null) throw ArgumentError('Unknown language: $name');
    final pending = _pending[name] = loader().then((language) {
      highlighter.addLanguage(language);
      return language;
    });
    try {
      return await pending;
    } finally {
      _pending.remove(name);
    }
  }
}
