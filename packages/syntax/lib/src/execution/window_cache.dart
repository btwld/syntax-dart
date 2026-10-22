part of 'executor.dart';

/// Bounded work retained by a cooperative highlighting executor.
final class HighlightWorkStats {
  /// Counts across the executor's retained document sessions.
  const HighlightWorkStats({
    required this.documents,
    required this.cachedLines,
    required this.checkpoints,
    required this.tokenizedLines,
  });

  /// Retained document indexes and compiled grammars (at most four).
  final int documents;

  /// Cached raw token lines (at most 512 per document).
  final int cachedLines;

  /// Sparse grammar states (at most 2048 per document).
  final int checkpoints;

  /// Lines tokenized since these document sessions were opened.
  final int tokenizedLines;
}

final class _HighlightSourceKey {
  _HighlightSourceKey(HighlightRequest request)
    : file = request.file,
      maxLineLength = request.maxLineLength,
      grammars = jsonEncode([
        for (final language in request.languages)
          [
            language.name,
            language.aliases,
            language.injectTo,
            language.grammar,
          ],
      ]);

  final SourceFile file;
  final int maxLineLength;
  final String grammars;

  @override
  int get hashCode => Object.hash(
    file.id,
    file.revision,
    file.path,
    file.language,
    file.text.length,
    maxLineLength,
    grammars,
  );

  @override
  bool operator ==(Object other) =>
      other is _HighlightSourceKey &&
      file.id == other.file.id &&
      file.revision == other.file.revision &&
      file.path == other.file.path &&
      file.language == other.file.language &&
      maxLineLength == other.maxLineLength &&
      grammars == other.grammars &&
      file.text == other.file.text;
}

final class _HighlightWindow {
  _HighlightWindow(HighlightRequest request)
    : document = TextDocument(request.file.text) {
    final highlighter = Highlighter(
      languages: request.languages,
      maxLineLength: request.maxLineLength,
    );
    final language =
        request.file.language ??
        highlighter.languageForPath(request.file.path)?.name;
    grammar = language == null || highlighter.language(language) == null
        ? null
        : highlighter.grammar(language);
  }

  final TextDocument document;
  late final Grammar? grammar;
  final checkpoints = SplayTreeMap<int, StateStack?>()..[0] = null;
  final tokens = <int, LineTokens>{};
  int tokenizedLines = 0;

  void _checkpoint(int line, StateStack? state) {
    checkpoints[line] = state;
    // Keep the root so every source position remains reachable.
    while (checkpoints.length > 2048) {
      checkpoints.remove(checkpoints.firstKeyAfter(0));
    }
  }

  Future<HighlightResult> highlight(
    HighlightRequest request, {
    required int sliceLines,
    required void Function() checkCancelled,
  }) async {
    final end = request.endLine ?? document.lineCount;
    RangeError.checkValidRange(request.startLine, end, document.lineCount);
    var next = grammar == null
        ? request.startLine
        : checkpoints.lastKeyBefore(request.startLine + 1) ?? 0;
    var state = checkpoints[next];
    final lines = <List<ThemedToken>>[];
    var work = 0;
    while (next < end) {
      checkCancelled();
      if (next == request.startLine) _checkpoint(next, state);
      final text = document.lineText(next);
      if (grammar == null) {
        lines.add([
          ThemedToken(
            text,
            0,
            TokenStyle(foreground: request.theme.foreground),
            ScopeStack.root('text.plain'),
          ),
        ]);
      } else {
        final cached = tokens.remove(next);
        if (cached != null) tokens[next] = cached;
        final result = cached ?? grammar!.tokenizeLine(text, state);
        if (cached == null) tokenizedLines++;
        state = result.endState;
        if (next >= request.startLine) {
          tokens[next] = result;
          while (tokens.length > 512) {
            tokens.remove(tokens.keys.first);
          }
          lines.add([
            for (final token in result.tokens)
              ThemedToken(
                text.substring(token.start, token.end),
                token.start,
                request.theme.styleFor(token.scopes),
                token.scopes,
              ),
          ]);
        }
      }
      next++;
      if (next % 128 == 0) _checkpoint(next, state);
      if (++work % sliceLines == 0) {
        // Preserve progress even if a new viewport cancels this request.
        _checkpoint(next, state);
        await Future<void>.delayed(Duration.zero);
      }
    }
    checkCancelled();
    _checkpoint(next, state);
    return HighlightResult(
      fileId: request.file.id,
      revision: request.file.revision,
      startLine: request.startLine,
      lines: lines,
    );
  }
}
