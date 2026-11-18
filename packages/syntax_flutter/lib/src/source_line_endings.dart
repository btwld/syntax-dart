/// Lazily resolves terminators for context synthesized from a full source.
///
/// Keeps a cursor rather than a document-sized terminator index. Existing
/// diff lines should use their recorded terminator instead of this fallback.
class SourceLineEndings {
  /// Reads [source] using its existing [lines], which exclude terminators.
  SourceLineEndings(this.source, this.lines);

  /// Original source including terminators.
  final String source;

  /// Immutable source lines without terminators.
  final List<String> lines;

  int _nextLine = 1;
  int _offset = 0;
  int? _lastLine;
  String _lastEnding = '\n';

  /// Resolves the one-based [line], advancing only as far as requested.
  String endingAt(int line) {
    RangeError.checkValueInInterval(line, 1, lines.length, 'line');
    if (_lastLine == line) return _lastEnding;
    if (line < _nextLine) {
      _nextLine = 1;
      _offset = 0;
    }
    while (_nextLine <= line) {
      _offset += lines[_nextLine - 1].length;
      if (_offset >= source.length) {
        _lastEnding = '\n';
      } else if (source.codeUnitAt(_offset) == 13) {
        _lastEnding =
            _offset + 1 < source.length && source.codeUnitAt(_offset + 1) == 10
            ? '\r\n'
            : '\r';
        _offset += _lastEnding.length;
      } else {
        _lastEnding = '\n';
        _offset++;
      }
      _nextLine++;
    }
    _lastLine = line;
    return _lastEnding;
  }
}
