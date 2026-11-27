import 'dart:math' as math;

import 'package:syntax_core/syntax.dart';

import 'highlight_scheduler.dart';

/// A view's line index over one immutable source snapshot.
class WindowSource {
  /// Indexes LF-delimited line starts without copying line bodies.
  WindowSource(String code)
    : _code = code,
      _lines = null,
      codeUnits = code.length {
    offsets.add(0);
    for (var i = code.indexOf('\n'); i >= 0; i = code.indexOf('\n', i + 1)) {
      offsets.add(i + 1);
    }
  }

  /// Indexes existing diff lines without eagerly joining offscreen source.
  WindowSource.lines(List<String> lines) : _lines = lines {
    var offset = 0;
    for (final line in lines) {
      offsets.add(offset);
      offset += line.length + 1;
    }
    if (offsets.isEmpty) offsets.add(0);
    codeUnits = offset == 0 ? 0 : offset - 1;
  }

  String? _code;
  final List<String>? _lines;

  /// Exact source used by window requests, joined only when work is needed.
  String get code => _code ??= _lines!.join('\n');

  /// Input size, available without materializing a joined source.
  late final int codeUnits;

  /// UTF-16 start offset of each logical line.
  final offsets = <int>[];

  /// Fixed small windows keep results bounded while sharing nearby work.
  List<StyledRange>? ranges(
    int line,
    String id,
    int revision,
    String language,
    HighlightWindowScheduler scheduler, {
    int windowSize = 64,
  }) {
    final start = line ~/ windowSize * windowSize;
    return scheduler.rangesFor(
      HighlightWindowRequest(
        fileId: id,
        revision: revision,
        code: code,
        language: language,
        startLine: start,
        endLine: math.min(start + windowSize, offsets.length),
      ),
    );
  }
}

/// Splits a line into syntax and changed-word segments, preserving plain gaps.
List<DiffSegment> windowSegments(
  String text,
  int offset,
  List<StyledRange>? ranges,
  TokenStyle plain, [
  List<CharRange> changes = const [],
]) {
  if (text.isEmpty) return const [];
  final colors = <StyledRange>[];
  var position = offset;
  for (final range in ranges ?? const <StyledRange>[]) {
    if (range.end <= offset) continue;
    if (range.start >= offset + text.length) break;
    final start = math.max(offset, range.start);
    final end = math.min(offset + text.length, range.end);
    if (start > position) colors.add(StyledRange(position, start, plain));
    colors.add(StyledRange(start, end, range.style));
    position = end;
  }
  if (position < offset + text.length) {
    colors.add(StyledRange(position, offset + text.length, plain));
  }
  final segments = <DiffSegment>[];
  for (final range in colors) {
    var start = range.start - offset;
    final end = range.end - offset;
    for (final change in changes) {
      if (change.end <= start) continue;
      if (change.start >= end) break;
      if (change.start > start) {
        segments.add(
          DiffSegment(text.substring(start, change.start), range.style),
        );
        start = change.start;
      }
      final stop = math.min(change.end, end);
      segments.add(
        DiffSegment(text.substring(start, stop), range.style, changed: true),
      );
      start = stop;
    }
    if (start < end) {
      segments.add(DiffSegment(text.substring(start, end), range.style));
    }
  }
  return segments;
}
