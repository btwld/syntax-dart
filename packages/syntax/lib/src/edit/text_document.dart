/// A small synchronous subscription surface shared by all renderers.
class SyntaxObservable {
  final Set<void Function()> _listeners = {};
  bool _disposed = false;

  /// Whether this owner has released its resources and subscriptions.
  bool get isDisposed => _disposed;

  /// Throws StateError after disposal.
  void checkAlive() {
    if (_disposed) throw StateError('Object has been disposed');
  }

  /// Subscribes a synchronous callback; duplicate callbacks are registered once.
  void addListener(void Function() listener) {
    checkAlive();
    _listeners.add(listener);
  }

  /// Removes a previously registered callback.
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Notifies a stable snapshot of subscribers, respecting removed listeners.
  void notifyListeners() {
    checkAlive();
    for (final listener in List.of(_listeners)) {
      if (_listeners.contains(listener)) listener();
    }
  }

  /// Cancels pending work and releases retained resources; the object must not be reused.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

/// A zero-based line and UTF-16 column, excluding the line terminator.
final class DocumentPosition implements Comparable<DocumentPosition> {
  /// Creates a zero-based line and UTF-16 column.
  const DocumentPosition(this.line, this.character);

  /// Zero-based logical source line.
  final int line;

  /// Zero-based UTF-16 column excluding the line terminator.
  final int character;
  @override
  int compareTo(DocumentPosition other) => line == other.line
      ? character.compareTo(other.character)
      : line.compareTo(other.line);
  @override
  bool operator ==(Object other) =>
      other is DocumentPosition &&
      line == other.line &&
      character == other.character;
  @override
  int get hashCode => Object.hash(line, character);
}

/// A half-open range in document positions.
final class DocumentRange {
  /// Creates a half-open range in document coordinates.
  const DocumentRange(this.start, this.end);

  /// Inclusive beginning of the range.
  final DocumentPosition start;

  /// Exclusive end of the range.
  final DocumentPosition end;
}

/// All edits in one batch address the document before that batch.
final class DocumentEdit {
  /// Replaces the given half-open range with exact source text.
  const DocumentEdit(this.range, this.text);

  /// Range addressed against the document before the transaction.
  final DocumentRange range;

  /// Exact source text, including original line endings where applicable.
  final String text;
}

/// A half-open replacement in UTF-16 offsets.
final class OffsetEdit {
  /// Replaces the half-open UTF-16 interval without normalizing its text.
  const OffsetEdit(this.start, this.end, this.text);

  /// Inclusive beginning of the range.
  final int start;

  /// Exclusive end of the range.
  final int end;

  /// Exact source text, including original line endings where applicable.
  final String text;
}

/// Directed selection in UTF-16 document offsets.
final class DocumentSelection {
  /// Creates a directed selection from its fixed and moving endpoints.
  const DocumentSelection(this.anchor, this.active);

  /// Creates a caret at a UTF-16 document offset.
  const DocumentSelection.collapsed(int offset)
    : anchor = offset,
      active = offset;

  /// Fixed endpoint of the directed selection, in UTF-16 code units.
  final int anchor;

  /// Moving endpoint of the directed selection, in UTF-16 code units.
  final int active;

  /// Inclusive beginning of the range.
  int get start => anchor < active ? anchor : active;

  /// Exclusive end of the range.
  int get end => anchor > active ? anchor : active;

  /// Whether both selection endpoints address the same offset.
  bool get isCollapsed => anchor == active;
  @override
  bool operator ==(Object other) =>
      other is DocumentSelection &&
      anchor == other.anchor &&
      active == other.active;
  @override
  int get hashCode => Object.hash(anchor, active);
}

/// An immutable edit transaction. Maps retained positions through replacements.
final class DocumentChange {
  /// Records the revisions and ordered edits of one atomic transaction.
  DocumentChange(
    this.previousRevision,
    this.revision,
    Iterable<OffsetEdit> edits,
  ) : edits = List.unmodifiable(edits);

  /// Revision against which all edit coordinates were specified.
  final int previousRevision;

  /// Monotonically increasing content revision for rejecting obsolete work.
  final int revision;

  /// Non-overlapping replacements addressing the previous revision.
  final List<OffsetEdit> edits;

  /// Maps a UTF-16 offset through the transaction with insertion affinity.
  int mapOffset(int offset, {bool afterInsertion = true}) {
    var delta = 0;
    for (final edit in edits) {
      if (offset < edit.start) break;
      if (offset <= edit.end) {
        return edit.start + delta + (afterInsertion ? edit.text.length : 0);
      }
      delta += edit.text.length - (edit.end - edit.start);
    }
    return offset + delta;
  }

  /// Maps both directed endpoints through the transaction.
  DocumentSelection mapSelection(DocumentSelection selection) =>
      DocumentSelection(
        mapOffset(selection.anchor),
        mapOffset(selection.active),
      );
}

final class _Piece {
  const _Piece(this.buffer, this.start, this.end);
  final String buffer;
  final int start;
  final int end;
  int get length => end - start;
}

final class _DocumentSnapshot {
  _DocumentSnapshot(this.pieces, this.length, this.lineIds);
  final List<_Piece> pieces;
  final int length;
  final Map<int, Object> lineIds;
}

/// Indexed text backed by immutable pieces. Edits reuse untouched buffers;
/// strings and line indexes are materialized only when requested.
final class TextDocument extends SyntaxObservable {
  /// Creates a piece-backed document with bounded undo history.
  TextDocument(
    String text, {
    this.id = '',
    this.historyLimit = 1000,
    int revision = 0,
  }) : _pieces = [if (text.isNotEmpty) _Piece(text, 0, text.length)],
       _length = text.length,
       _text = text,
       _revision = revision {
    RangeError.checkNotNegative(revision, 'revision');
    RangeError.checkNotNegative(historyLimit, 'historyLimit');
  }

  /// Stable application-supplied identity; it must not depend on list position.
  final String id;

  /// Maximum retained undo transactions; zero disables history recording.
  final int historyLimit;
  List<_Piece> _pieces;
  int _length;
  String? _text;
  List<int>? _starts;
  Map<int, Object> _lineIds = {};
  final Map<Object, int> _identityLines = Map.identity();
  int _revision;
  final List<_DocumentSnapshot> _undo = [];
  final List<_DocumentSnapshot> _redo = [];

  /// Most recent transaction, or null before the first change.
  DocumentChange? lastChange;

  /// Monotonically increasing content revision for rejecting obsolete work.
  int get revision {
    checkAlive();
    return _revision;
  }

  /// Source length in UTF-16 code units.
  int get length {
    checkAlive();
    return _length;
  }

  /// Whether an earlier atomic editing transaction can be restored.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether an undone transaction can be reapplied.
  bool get canRedo => _redo.isNotEmpty;

  /// Logical line count, including an empty final line after a terminator.
  int get lineCount => _lineStarts.length;

  /// Exact source text, including original line endings where applicable.
  String get text {
    checkAlive();
    return _text ??= _pieces
        .map((p) => p.buffer.substring(p.start, p.end))
        .join();
  }

  List<int> get _lineStarts {
    checkAlive();
    return _starts ??= _indexLines(text);
  }

  static List<int> _indexLines(String source) {
    final starts = <int>[0];
    for (var i = 0; i < source.length; i++) {
      final c = source.codeUnitAt(i);
      if (c == 13) {
        if (i + 1 < source.length && source.codeUnitAt(i + 1) == 10) i++;
        starts.add(i + 1);
      } else if (c == 10) {
        starts.add(i + 1);
      }
    }
    return starts;
  }

  /// Converts a UTF-16 offset to a position, clamping terminators to line end.
  DocumentPosition positionAt(int offset) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    final starts = _lineStarts;
    var low = 0;
    var high = starts.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return DocumentPosition(
      low,
      (offset - starts[low]).clamp(0, lineText(low).length),
    );
  }

  /// Converts a validated document position to a UTF-16 offset.
  int offsetAt(DocumentPosition position) {
    RangeError.checkValidIndex(position.line, _lineStarts, 'line');
    RangeError.checkValueInInterval(
      position.character,
      0,
      lineText(position.line).length,
      'character',
    );
    return _lineStarts[position.line] + position.character;
  }

  /// UTF-16 offset of a zero-based logical line.
  int lineStart(int line) =>
      _lineStarts[RangeError.checkValidIndex(line, _lineStarts)];

  /// Stable identity for a requested line, retained when its text survives edits.
  Object lineIdentity(int line) {
    RangeError.checkValidIndex(line, _lineStarts, 'line');
    return _lineIds.putIfAbsent(line, () {
      final identity = Object();
      _identityLines[identity] = line;
      return identity;
    });
  }

  /// Finds a retained line identity after edits, or null if its text changed.
  int? lineForIdentity(Object identity) => _identityLines[identity];

  /// Source for a zero-based line, optionally including its original terminator.
  String lineText(int line, {bool includeTerminator = false}) {
    final start = lineStart(line);
    var end = line + 1 < _lineStarts.length ? _lineStarts[line + 1] : length;
    if (!includeTerminator) {
      if (end > start && text.codeUnitAt(end - 1) == 10) end--;
      if (end > start && text.codeUnitAt(end - 1) == 13) end--;
    }
    return text.substring(start, end);
  }

  /// First line ending found in the source, or LF for a single logical line.
  String get eol => RegExp(r'\r\n|\r|\n').firstMatch(text)?[0] ?? '\n';

  /// Returns exact source for the range, or the entire document when omitted.
  String getText([DocumentRange? range]) => range == null
      ? text
      : text.substring(offsetAt(range.start), offsetAt(range.end));

  /// Returns half-open match ranges in source order; invalid regexes throw.
  List<DocumentRange> search(
    String query, {
    bool caseSensitive = false,
    bool regularExpression = false,
    bool wholeWord = false,
  }) {
    if (query.isEmpty) return const [];
    final pattern = regularExpression ? query : RegExp.escape(query);
    final expression = RegExp(
      wholeWord ? '\\b(?:$pattern)\\b' : pattern,
      caseSensitive: caseSensitive,
      multiLine: true,
      unicode: true,
    );
    return List.unmodifiable([
      for (final match in expression.allMatches(text))
        DocumentRange(positionAt(match.start), positionAt(match.end)),
    ]);
  }

  /// Validates and applies an atomic batch against pre-edit coordinates.
  DocumentChange applyEdits(
    Iterable<DocumentEdit> edits, {
    bool recordHistory = true,
  }) => applyOffsetEdits([
    for (final e in edits)
      OffsetEdit(offsetAt(e.range.start), offsetAt(e.range.end), e.text),
  ], recordHistory: recordHistory);

  /// Validation finishes before any state changes, including history.
  DocumentChange applyOffsetEdits(
    Iterable<OffsetEdit> edits, {
    bool recordHistory = true,
  }) {
    checkAlive();
    final sorted = edits.toList()..sort((a, b) => a.start.compareTo(b.start));
    OffsetEdit? previous;
    for (final edit in sorted) {
      RangeError.checkValidRange(edit.start, edit.end, length);
      if (previous != null &&
          (edit.start < previous.end || edit.start == previous.start)) {
        throw ArgumentError('Edit ranges overlap');
      }
      previous = edit;
    }
    final effective = sorted
        .where((e) => text.substring(e.start, e.end) != e.text)
        .toList();
    if (effective.isEmpty) return DocumentChange(revision, revision, const []);
    if (recordHistory && historyLimit > 0) {
      _undo.add(_snapshot());
      if (_undo.length > historyLimit) _undo.removeAt(0);
    }
    _redo.clear();
    final oldRevision = revision;
    final retainedLines = [
      for (final entry in _lineIds.entries)
        (
          lineStart(entry.key),
          lineText(entry.key, includeTerminator: true),
          entry.value,
        ),
    ];
    final oldStarts = _starts;
    List<int>? updatedStarts;
    if (oldStarts != null) {
      // Rescan only complete lines touching a transaction, with one neighbor
      // on each side so CR/LF joins and splits are handled at edit boundaries.
      final firstLine = (positionAt(effective.first.start).line - 1).clamp(
        0,
        lineCount - 1,
      );
      final afterLine = (positionAt(effective.last.end).line + 2).clamp(
        0,
        lineCount,
      );
      final from = oldStarts[firstLine];
      final to = afterLine == lineCount ? length : oldStarts[afterLine];
      final region = StringBuffer();
      var cursor = from, delta = 0;
      for (final edit in effective) {
        region
          ..write(text.substring(cursor, edit.start))
          ..write(edit.text);
        cursor = edit.end;
        delta += edit.text.length - (edit.end - edit.start);
      }
      region.write(text.substring(cursor, to));
      final local = _indexLines(region.toString());
      updatedStarts = [
        ...oldStarts.take(firstLine),
        for (final offset in local)
          if (afterLine == oldStarts.length || offset < to - from + delta)
            from + offset,
        for (final offset in oldStarts.skip(afterLine)) offset + delta,
      ];
    }
    for (final edit in effective.reversed) {
      _replace(edit);
    }
    _invalidate();
    _starts = updatedStarts;
    final change = lastChange = DocumentChange(
      oldRevision,
      revision,
      effective,
    );
    _lineIds = {};
    _identityLines.clear();
    for (final (offset, original, identity) in retainedLines) {
      final mapped = change.mapOffset(offset);
      final line = positionAt(mapped).line;
      if (lineText(line, includeTerminator: true) == original) {
        _lineIds[line] = identity;
        _identityLines[identity] = line;
      }
    }
    notifyListeners();
    return change;
  }

  void _replace(OffsetEdit edit) {
    final next = <_Piece>[];
    var offset = 0;
    var inserted = false;
    for (final piece in _pieces) {
      final end = offset + piece.length;
      if (offset < edit.start) {
        final take = (edit.start - offset).clamp(0, piece.length);
        if (take > 0) {
          next.add(_Piece(piece.buffer, piece.start, piece.start + take));
        }
      }
      if (!inserted && end >= edit.start) {
        if (edit.text.isNotEmpty) {
          next.add(_Piece(edit.text, 0, edit.text.length));
        }
        inserted = true;
      }
      if (end > edit.end) {
        final skip = (edit.end - offset).clamp(0, piece.length);
        next.add(_Piece(piece.buffer, piece.start + skip, piece.end));
      }
      offset = end;
    }
    if (!inserted && edit.text.isNotEmpty) {
      next.add(_Piece(edit.text, 0, edit.text.length));
    }
    _pieces = next;
    _length += edit.text.length - (edit.end - edit.start);
  }

  _DocumentSnapshot _snapshot() =>
      _DocumentSnapshot(List.of(_pieces), _length, Map.of(_lineIds));
  void _invalidate() {
    _text = null;
    _starts = null;
    _revision++;
  }

  /// Restores the previous editing transaction and advances the revision.
  bool undo() => _restore(_undo, _redo);

  /// Reapplies an undone transaction and advances the revision.
  bool redo() => _restore(_redo, _undo);
  bool _restore(List<_DocumentSnapshot> from, List<_DocumentSnapshot> to) {
    checkAlive();
    if (from.isEmpty) return false;
    final oldLength = length;
    final oldRevision = revision;
    to.add(_snapshot());
    final snapshot = from.removeLast();
    _pieces = snapshot.pieces;
    _length = snapshot.length;
    _lineIds = Map.of(snapshot.lineIds);
    _identityLines
      ..clear()
      ..addEntries(
        _lineIds.entries.map((entry) => MapEntry(entry.value, entry.key)),
      );
    _invalidate();
    lastChange = DocumentChange(oldRevision, revision, [
      OffsetEdit(0, oldLength, text),
    ]);
    notifyListeners();
    return true;
  }

  /// Discards undo and redo snapshots without changing content or revision.
  void clearHistory() {
    checkAlive();
    _undo.clear();
    _redo.clear();
  }

  /// Installs an external source atomically and clears local undo history.
  /// The resulting revision is at least [revision] and newer than this document.
  void reset(String value, {int revision = 0}) {
    checkAlive();
    RangeError.checkNotNegative(revision, 'revision');
    final previous = _revision, oldLength = _length;
    _pieces = [if (value.isNotEmpty) _Piece(value, 0, value.length)];
    _length = value.length;
    _text = value;
    _starts = null;
    _lineIds.clear();
    _identityLines.clear();
    _undo.clear();
    _redo.clear();
    _revision = revision > previous ? revision : previous + 1;
    lastChange = DocumentChange(previous, _revision, [
      OffsetEdit(0, oldLength, value),
    ]);
    notifyListeners();
  }

  @override
  void dispose() {
    _undo.clear();
    _redo.clear();
    _pieces = [];
    _lineIds.clear();
    _identityLines.clear();
    super.dispose();
  }
}

/// Immutable source identity used by asynchronous jobs and file collections.
final class SourceFile {
  /// Creates an immutable source snapshot with application-owned identity.
  const SourceFile({
    required this.id,
    required this.path,
    required this.text,
    this.language,
    this.revision = 0,
  });

  /// Stable application-supplied identity; it must not depend on list position.
  final String id;

  /// Display path and optional language-detection hint; no filesystem access occurs.
  final String path;

  /// Exact source text, including original line endings where applicable.
  final String text;

  /// Explicit language identifier, or null to detect from the display path.
  final String? language;

  /// Monotonically increasing content revision for rejecting obsolete work.
  final int revision;

  /// Creates a new snapshot with the same identity and an incremented revision.
  SourceFile withText(String value) => SourceFile(
    id: id,
    path: path,
    text: value,
    language: language,
    revision: revision + 1,
  );
}

/// Bounded, explicitly owned sessions; an active entry is never evicted.
final class SessionStore<T> {
  /// Creates a bounded cache with explicit active claims and eviction cleanup.
  SessionStore({this.capacity = 100, this.onEvict}) {
    RangeError.checkNotNegative(capacity, 'capacity');
  }

  /// Maximum retained inactive entries; active entries are never evicted.
  final int capacity;

  /// Cleanup invoked when an inactive entry is removed or the store is cleared.
  final void Function(T)? onEvict;
  final _entries = <String, T>{};
  final _active = <String, int>{};

  /// Reads a retained session without claiming it or changing its recency.
  T? peek(String id) => _entries[id];

  /// Claims an existing session or creates one. Every claim needs a release.
  T acquire(String id, T Function() create) {
    _active[id] = (_active[id] ?? 0) + 1;
    try {
      final value = _entries.remove(id) ?? create();
      _entries[id] = value;
      return value;
    } on Object {
      _releaseClaim(id);
      rethrow;
    }
  }

  /// Releases a claim and evicts the oldest excess inactive entries.
  void release(String id) {
    _releaseClaim(id);
    _trim();
  }

  void _releaseClaim(String id) {
    final count = _active[id] ?? 0;
    if (count <= 1) {
      _active.remove(id);
    } else {
      _active[id] = count - 1;
    }
  }

  void _trim() {
    final inactive = _entries.keys
        .where((k) => !_active.containsKey(k))
        .toList();
    for (final key in inactive.take(
      (inactive.length - capacity).clamp(0, inactive.length),
    )) {
      final value = _entries.remove(key);
      if (value != null) onEvict?.call(value);
    }
  }

  /// Removes an inactive entry, returning false when it is still claimed.
  bool remove(String id) {
    if (_active.containsKey(id)) return false;
    final value = _entries.remove(id);
    if (value != null) onEvict?.call(value);
    return value != null;
  }

  /// Removes inactive entries, or all entries when the owner is disposing.
  void clear({bool includeActive = false}) {
    if (includeActive) _active.clear();
    for (final key in _entries.keys.toList()) {
      remove(key);
    }
  }
}
