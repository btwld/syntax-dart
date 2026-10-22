import '../theme/theme.dart';
import 'executor.dart';

/// Internal transport cache: source and grammars cross a worker boundary only
/// once per retained snapshot. Both peers keep the same four-entry LRU order.
class HighlightSender {
  final _sources = <Object, int>{};
  int _next = 0;

  /// Encodes a new source once, followed by small viewport messages.
  Map<String, Object?> encode(HighlightRequest request) {
    final key = request.sourceIdentity;
    final previous = _sources.remove(key);
    final id = previous ?? _next++;
    _sources[key] = id;
    while (_sources.length > 4) {
      _sources.remove(_sources.keys.first);
    }
    return {
      'sourceId': id,
      if (previous == null) 'source': request.toJson(),
      'startLine': request.startLine,
      'endLine': request.endLine,
      'theme': request.theme.json,
      'themeName': request.theme.name,
    };
  }
}

/// Counterpart to [HighlightSender] inside a persistent worker.
class HighlightReceiver {
  final _sources = <int, HighlightRequest>{};

  /// Resolves viewport messages against the bounded source cache.
  HighlightRequest decode(Map<String, Object?> data) {
    final id = data['sourceId'] as int;
    final retained = _sources.remove(id);
    final source = data['source'] == null
        ? retained!
        : HighlightRequest.fromJson(
            Map<String, Object?>.from(data['source'] as Map),
          );
    _sources[id] = source;
    while (_sources.length > 4) {
      _sources.remove(_sources.keys.first);
    }
    return HighlightRequest(
      file: source.file,
      languages: source.languages,
      maxLineLength: source.maxLineLength,
      startLine: data['startLine'] as int,
      endLine: data['endLine'] as int?,
      theme: SyntaxTheme.fromJson(
        Map<String, Object?>.from(data['theme'] as Map),
        name: data['themeName'] as String,
      ),
    );
  }
}
