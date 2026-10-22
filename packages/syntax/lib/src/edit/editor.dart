import 'dart:async';
import 'text_document.dart';

/// Application diagnostic importance.
enum DiagnosticSeverity {
  /// Optional improvement or suggestion.
  hint,

  /// Informational source note.
  information,

  /// Potential problem requiring attention.
  warning,

  /// Source error requiring correction.
  error,
}

/// Metadata remains caller-owned; the controller only transforms its range.
final class LineAnnotation<T> {
  /// Creates a stable annotation over half-open UTF-16 source offsets.
  const LineAnnotation({
    required this.id,
    required this.start,
    required this.end,
    required this.data,
  });

  /// Stable application-supplied identity; it must not depend on list position.
  final String id;

  /// Inclusive beginning of the range.
  final int start;

  /// Exclusive end of the range.
  final int end;

  /// Application-owned annotation payload, passed unchanged to renderers.
  final T data;

  /// Maps the annotation range through an atomic document transaction.
  LineAnnotation<T> transform(DocumentChange change) => LineAnnotation(
    id: id,
    start: change.mapOffset(start, afterInsertion: false),
    end: change.mapOffset(end),
    data: data,
  );
}

/// An application diagnostic over half-open UTF-16 source offsets.
final class Diagnostic {
  /// An application diagnostic over half-open UTF-16 source offsets.
  const Diagnostic({
    required this.start,
    required this.end,
    required this.message,
    this.severity = DiagnosticSeverity.error,
  });

  /// Inclusive beginning of the range.
  final int start;

  /// Exclusive end of the range.
  final int end;

  /// Human-readable description suitable for presentation to the user.
  final String message;

  /// Importance used by renderers to choose diagnostic emphasis.
  final DiagnosticSeverity severity;
}

/// An externally supplied participant selection, independent of local input.
final class RemoteCaret {
  /// An externally supplied participant selection, independent of local input.
  const RemoteCaret({
    required this.id,
    required this.selection,
    required this.color,
    this.label = '',
  });

  /// Stable application-supplied identity; it must not depend on list position.
  final String id;

  /// Directed selection retained independently of mounted views.
  final DocumentSelection selection;

  /// ARGB color used to distinguish this participant.
  final int color;

  /// Optional display label for the participant.
  final String label;
}

/// Portable editing actions implemented by the shared session.
enum EditorCommand {
  /// Restores the previous editing transaction and advances the revision.
  undo,

  /// Reapplies an undone transaction and advances the revision.
  redo,

  /// Select the complete source.
  selectAll,

  /// Increase indentation of selected lines.
  indent,

  /// Remove one indentation level.
  outdent,

  /// Add or remove the configured line comment prefix.
  toggleComment,

  /// Surround or unwrap selections with block comment delimiters.
  toggleBlockComment,

  /// Move selected lines above their preceding line.
  moveLineUp,

  /// Move selected lines below their following line.
  moveLineDown,

  /// Duplicate selected lines above themselves.
  copyLineUp,

  /// Duplicate selected lines below themselves.
  copyLineDown,

  /// Insert a blank line after the active line.
  insertBlankLine,

  /// Remove selected source lines.
  deleteLine,

  /// Collapse multiple selections to one caret.
  simplifySelection,

  /// Applies the current proposed edits as one undoable transaction.
  acceptProposal,

  /// Cancels pending proposals and removes their preview.
  dismissProposal,
}

/// Signals that a caller or owner cancelled an asynchronous operation.
final class OperationCancelled implements Exception {
  /// Signals that a caller or owner cancelled an asynchronous operation.
  const OperationCancelled();
  @override
  String toString() => 'Operation cancelled';
}

/// Cancellation is cooperative, and cancelled results must not be installed.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  /// Whether cancellation has been requested; cancellation cannot be reversed.
  bool get isCancelled => _cancelled;

  /// Subscribes to cancellation and returns an unsubscribe callback.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Requests cancellation once and synchronously notifies subscribers.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Cancels this caller's wait without abandoning a shared future's errors.
  Future<T> bind<T>(Future<T> work) {
    if (_cancelled) {
      work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return Future.error(const OperationCancelled());
    }
    final result = Completer<T>();
    final unsubscribe = onCancel(() {
      if (!result.isCompleted) result.completeError(const OperationCancelled());
    });
    work
        .then(
          (value) {
            if (!result.isCompleted) result.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!result.isCompleted) result.completeError(error, stack);
          },
        )
        .whenComplete(unsubscribe);
    return result.future;
  }

  /// Throws OperationCancelled after cancellation has been requested.
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelled();
  }
}

/// Immutable source and selection snapshot supplied to a proposal provider.
final class ProposedEditRequest {
  /// Immutable source and selection snapshot supplied to a proposal provider.
  ProposedEditRequest({
    required this.file,
    required Iterable<DocumentSelection> selections,
    required this.cancellation,
  }) : selections = List.unmodifiable(selections);

  /// Current source snapshot, including stable identity and document revision.
  final SourceFile file;

  /// Directed UTF-16 selections; the first selection receives native input focus.
  final List<DocumentSelection> selections;

  /// Cancellation signal for this request and its dependent work.
  final CancellationToken cancellation;
}

/// Application callback returning atomic edits against the request revision.
typedef ProposedEditProvider =
    Future<List<OffsetEdit>> Function(ProposedEditRequest request);

/// Captures logical selections and renderer scroll offsets for restoration.
final class EditorViewState {
  /// Captures logical selections and renderer scroll offsets for restoration.
  EditorViewState({
    required Iterable<DocumentSelection> selections,
    this.horizontalOffset = 0,
    this.verticalOffset = 0,
  }) : selections = List.unmodifiable(selections);

  /// Directed UTF-16 selections; the first selection receives native input focus.
  final List<DocumentSelection> selections;

  /// Retained horizontal scroll position in the renderer's own units.
  final double horizontalOffset;

  /// Retained vertical scroll position in the renderer's own units.
  final double verticalOffset;
}

final class _EditorHistory {
  _EditorHistory(this.selections, this.annotations);
  final List<DocumentSelection> selections;
  final List<LineAnnotation<Object?>> annotations;
}

/// Shared editing behavior for file and diff surfaces. UI adapters translate
/// native input into transactions and keep their composing range locally.
final class EditorController extends SyntaxObservable {
  /// Creates a shared editor session; disposing it also disposes its document.
  EditorController({
    required SourceFile file,
    TextDocument? document,
    this.proposalDelay = const Duration(milliseconds: 300),
    this.proposalProvider,
    this.tabSize = 2,
    this.lineComment = '//',
    this.blockComment = const ('/*', '*/'),
  }) : _file = file,
       document =
           document ??
           TextDocument(file.text, id: file.id, revision: file.revision),
       _ownsDocument = document == null {
    if (tabSize < 1) throw ArgumentError.value(tabSize, 'tabSize');
    this.document.addListener(_documentChanged);
  }

  /// Editable indexed source and revision history owned by this session.
  final TextDocument document;
  final bool _ownsDocument;
  SourceFile _file;

  /// Number of spaces inserted by indentation commands.
  final int tabSize;

  /// Prefix inserted or removed by the line-comment command.
  final String lineComment;

  /// Opening and closing delimiters used by the block-comment command.
  final (String, String) blockComment;

  /// Debounce interval between input changes and a proposal request.
  final Duration proposalDelay;

  /// Optional application-supplied proposed-edit provider.
  ProposedEditProvider? proposalProvider;
  final List<_EditorHistory> _undo = [];
  final List<_EditorHistory> _redo = [];
  bool _restoring = false;
  List<DocumentSelection> _selections = const [DocumentSelection.collapsed(0)];
  List<LineAnnotation<Object?>> _annotations = const [];
  List<Diagnostic> _diagnostics = const [];
  List<RemoteCaret> _carets = const [];
  List<OffsetEdit> _proposal = const [];
  Timer? _timer;
  CancellationToken? _pending;
  int? _proposalRevision;

  /// Most recent proposal failure, cleared before a new request.
  Object? proposalError;

  /// Retained horizontal scroll position in the renderer's own units.
  double horizontalOffset = 0;

  /// Retained vertical scroll position in the renderer's own units.
  double verticalOffset = 0;

  /// Range most recently requested for scrolling; renderers own its geometry.
  DocumentRange? revealTarget;

  /// Sequence number of the latest explicit reveal command.
  int revealRequest = 0;

  /// Brings a range into view without changing the current selection.
  void reveal(DocumentRange range) {
    document.offsetAt(range.start);
    document.offsetAt(range.end);
    revealTarget = range;
    revealRequest++;
    notifyListeners();
  }

  /// Creates an immutable source snapshot with application-owned identity.
  SourceFile get file => SourceFile(
    id: _file.id,
    path: _file.path,
    text: document.text,
    language: _file.language,
    revision: document.revision,
  );

  /// Explicitly discards a draft and installs a newer source for the same file.
  /// Selections are clamped; history, proposals and revision-specific marks reset.
  void replaceSource(SourceFile source) {
    checkAlive();
    if (source.id != _file.id) {
      throw ArgumentError('Cannot replace the file identity');
    }
    _file = source;
    _selections = List.unmodifiable([
      for (final selection in _selections)
        DocumentSelection(
          selection.anchor.clamp(0, source.text.length),
          selection.active.clamp(0, source.text.length),
        ),
    ]);
    _annotations = const [];
    _diagnostics = const [];
    _carets = const [];
    _undo.clear();
    _redo.clear();
    revealTarget = null;
    dismissProposal(notify: false);
    _restoring = true;
    try {
      document.reset(source.text, revision: source.revision);
    } finally {
      _restoring = false;
    }
    notifyListeners();
    _scheduleProposal();
  }

  /// Directed UTF-16 selections; the first selection receives native input focus.
  List<DocumentSelection> get selections => _selections;

  /// Application annotations positioned against the current document.
  List<LineAnnotation<Object?>> get annotations => _annotations;

  /// Diagnostics for the current source revision.
  List<Diagnostic> get diagnostics => _diagnostics;

  /// Externally supplied participant selections.
  List<RemoteCaret> get carets => _carets;

  /// Validated proposed edits against the current document revision.
  List<OffsetEdit> get proposedEdits => _proposal;

  /// Whether a proposal request is awaiting completion.
  bool get isProposing => _pending != null;

  /// Whether an earlier atomic editing transaction can be restored.
  bool get canUndo => document.canUndo;

  /// Whether an undone transaction can be reapplied.
  bool get canRedo => document.canRedo;

  /// Validates and installs directed UTF-16 selections, then notifies subscribers.
  void setSelections(Iterable<DocumentSelection> selections) {
    checkAlive();
    final next = selections.toList();
    if (next.isEmpty) next.add(const DocumentSelection.collapsed(0));
    for (final s in next) {
      RangeError.checkValidRange(s.start, s.end, document.length);
    }
    _selections = List.unmodifiable(next);
    dismissProposal(notify: false);
    notifyListeners();
    _scheduleProposal();
  }

  /// Selects complete zero-based lines, including both endpoints in either
  /// direction. The final line's terminator is excluded from source copying.
  void selectLines(int anchor, int active) {
    final a = document.lineStart(anchor);
    final b = document.lineStart(active);
    setSelections([
      active < anchor
          ? DocumentSelection(a + document.lineText(anchor).length, b)
          : DocumentSelection(a, b + document.lineText(active).length),
    ]);
  }

  /// Replaces annotations and notifies mounted renderers.
  void setAnnotations(Iterable<LineAnnotation<Object?>> annotations) {
    final next = annotations.toList();
    for (final item in next) {
      RangeError.checkValidRange(item.start, item.end, document.length);
    }
    _annotations = List.unmodifiable(next);
    notifyListeners();
  }

  /// Replaces application diagnostics for the current source revision.
  void setDiagnostics(Iterable<Diagnostic> diagnostics) {
    final next = diagnostics.toList();
    for (final item in next) {
      RangeError.checkValidRange(item.start, item.end, document.length);
    }
    _diagnostics = List.unmodifiable(next);
    notifyListeners();
  }

  /// Replaces externally supplied participant selections.
  void setCarets(Iterable<RemoteCaret> carets) {
    final next = carets.toList();
    for (final item in next) {
      RangeError.checkValidRange(
        item.selection.start,
        item.selection.end,
        document.length,
      );
    }
    _carets = List.unmodifiable(next);
    notifyListeners();
  }

  /// Captures logical selections and renderer scroll offsets for restoration.
  EditorViewState get viewState => EditorViewState(
    selections: selections,
    horizontalOffset: horizontalOffset,
    verticalOffset: verticalOffset,
  );

  /// Restores valid selections and scroll offsets from a saved view state.
  void restoreView(EditorViewState state) {
    horizontalOffset = state.horizontalOffset;
    verticalOffset = state.verticalOffset;
    setSelections(state.selections);
  }

  void _documentChanged() {
    if (_restoring) return;
    final change = document.lastChange;
    if (change == null) return;
    if (!_restoring) {
      _undo.add(_EditorHistory(_selections, _annotations));
      if (_undo.length > document.historyLimit) _undo.removeAt(0);
      _redo.clear();
      _selections = List.unmodifiable(_selections.map(change.mapSelection));
      _annotations = List.unmodifiable(
        _annotations.map((a) => a.transform(change)),
      );
    }
    _diagnostics = const [];
    _carets = List.unmodifiable([
      for (final caret in _carets)
        RemoteCaret(
          id: caret.id,
          label: caret.label,
          color: caret.color,
          selection: change.mapSelection(caret.selection),
        ),
    ]);
    dismissProposal(notify: false);
    notifyListeners();
    _scheduleProposal();
  }

  /// Validates and applies an atomic batch against pre-edit coordinates.
  DocumentChange applyEdits(Iterable<OffsetEdit> edits) {
    checkAlive();
    return document.applyOffsetEdits(edits);
  }

  /// Inserts at every selection, coalescing duplicate and overlapping ranges.
  void insertText(String text, {bool autoSurround = true}) {
    final selections = _normalizedSelections();
    final close = autoSurround
        ? const {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"}[text]
        : null;
    final edits = [
      for (final s in selections)
        OffsetEdit(
          s.start,
          s.end,
          close == null
              ? text
              : '$text${document.text.substring(s.start, s.end)}$close',
        ),
    ];
    final starts = <int, int>{};
    var delta = 0;
    for (final edit
        in edits.toList()..sort((a, b) => a.start.compareTo(b.start))) {
      starts[edit.start] = edit.start + delta;
      delta += edit.text.length - (edit.end - edit.start);
    }
    applyEdits(edits);
    _selections = List.unmodifiable([
      for (final s in selections)
        if (close == null)
          DocumentSelection.collapsed(starts[s.start]! + text.length)
        else if (s.anchor > s.active)
          DocumentSelection(
            starts[s.start]! + text.length + s.end - s.start,
            starts[s.start]! + text.length,
          )
        else
          DocumentSelection(
            starts[s.start]! + text.length,
            starts[s.start]! + text.length + s.end - s.start,
          ),
    ]);
    notifyListeners();
  }

  List<DocumentSelection> _normalizedSelections() {
    final sorted = _selections.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final result = <DocumentSelection>[];
    for (final s in sorted) {
      if (result.isNotEmpty &&
          (s.start < result.last.end || s.start == result.last.start)) {
        final previous = result.removeLast();
        result.add(
          DocumentSelection(
            previous.start,
            s.end > previous.end ? s.end : previous.end,
          ),
        );
      } else {
        result.add(s);
      }
    }
    int priority(DocumentSelection range) => _selections.indexWhere(
      (selection) =>
          selection.start >= range.start && selection.end <= range.end,
    );
    result.sort((a, b) => priority(a).compareTo(priority(b)));
    return result;
  }

  /// Deletes each selection, extending carets by a renderer-defined grapheme.
  /// [boundary] receives a UTF-16 offset and direction against the current text.
  void deleteText({
    bool forward = false,
    required int Function(int, bool) boundary,
  }) {
    final ranges = [
      for (final s in _selections)
        if (!s.isCollapsed)
          s
        else
          DocumentSelection(s.active, boundary(s.active, forward)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final edits = <OffsetEdit>[];
    for (final range in ranges) {
      RangeError.checkValidRange(range.start, range.end, document.length);
      if (range.isCollapsed) continue;
      if (edits.isNotEmpty && range.start <= edits.last.end) {
        final last = edits.removeLast();
        edits.add(
          OffsetEdit(
            last.start,
            range.end > last.end ? range.end : last.end,
            '',
          ),
        );
      } else {
        edits.add(OffsetEdit(range.start, range.end, ''));
      }
    }
    applyEdits(edits);
  }

  /// Applies native input while preserving logical multiple selections.
  /// Composition changes only the primary selection. Renderers optionally
  /// provide grapheme boundaries for replicated Backspace/Delete operations.
  void updateFromInput(
    String value,
    DocumentSelection? selection, {
    bool composing = false,
    int Function(int, bool)? deletionBoundary,
  }) {
    checkAlive();
    if (selection != null) {
      RangeError.checkValidRange(selection.start, selection.end, value.length);
    }
    final old = document.text, primary = _selections.first;
    if (old != value) {
      final count = value.length - old.length + primary.end - primary.start;
      if (!composing &&
          count >= 0 &&
          primary.start + count <= value.length &&
          value.substring(0, primary.start) ==
              old.substring(0, primary.start) &&
          value.substring(primary.start + count) ==
              old.substring(primary.end)) {
        insertText(value.substring(primary.start, primary.start + count));
        return;
      }
      if (!composing &&
          primary.isCollapsed &&
          selection?.isCollapsed == true &&
          deletionBoundary != null &&
          value.length < old.length) {
        final forward = selection!.active == primary.active;
        final edge = deletionBoundary(primary.active, forward);
        final start = forward ? primary.active : edge;
        final end = forward ? edge : primary.active;
        if (start >= 0 &&
            end >= start &&
            end <= old.length &&
            old.replaceRange(start, end, '') == value) {
          deleteText(forward: forward, boundary: deletionBoundary);
          return;
        }
      }
      var start = 0, end = old.length, nextEnd = value.length;
      while (start < end &&
          start < nextEnd &&
          old.codeUnitAt(start) == value.codeUnitAt(start)) {
        start++;
      }
      while (end > start &&
          nextEnd > start &&
          old.codeUnitAt(end - 1) == value.codeUnitAt(nextEnd - 1)) {
        end--;
        nextEnd--;
      }
      applyEdits([OffsetEdit(start, end, value.substring(start, nextEnd))]);
    }
    if (selection != null && selection != _selections.first) {
      setSelections([selection, ..._selections.skip(1)]);
    }
  }

  /// Restores the previous editing transaction and advances the revision.
  void undo() {
    if (!canUndo) return;
    final state = _undo.isEmpty ? null : _undo.removeLast();
    _redo.add(_EditorHistory(_selections, _annotations));
    _restoring = true;
    try {
      document.undo();
    } finally {
      _restoring = false;
    }
    _selections = state?.selections ?? const [DocumentSelection.collapsed(0)];
    _annotations = state?.annotations ?? const [];
    _diagnostics = const [];
    _carets = List.unmodifiable([
      for (final caret in _carets)
        RemoteCaret(
          id: caret.id,
          label: caret.label,
          color: caret.color,
          selection: DocumentSelection(
            caret.selection.anchor.clamp(0, document.length),
            caret.selection.active.clamp(0, document.length),
          ),
        ),
    ]);
    dismissProposal(notify: false);
    notifyListeners();
    _scheduleProposal();
  }

  /// Reapplies an undone transaction and advances the revision.
  void redo() {
    if (!canRedo) return;
    final state = _redo.isEmpty ? null : _redo.removeLast();
    _undo.add(_EditorHistory(_selections, _annotations));
    _restoring = true;
    try {
      document.redo();
    } finally {
      _restoring = false;
    }
    _selections = state?.selections ?? const [DocumentSelection.collapsed(0)];
    _annotations = state?.annotations ?? const [];
    _diagnostics = const [];
    _carets = List.unmodifiable([
      for (final caret in _carets)
        RemoteCaret(
          id: caret.id,
          label: caret.label,
          color: caret.color,
          selection: DocumentSelection(
            caret.selection.anchor.clamp(0, document.length),
            caret.selection.active.clamp(0, document.length),
          ),
        ),
    ]);
    dismissProposal(notify: false);
    notifyListeners();
    _scheduleProposal();
  }

  /// Finds source ranges using literal or regular-expression search.
  List<DocumentRange> find(
    String query, {
    bool caseSensitive = false,
    bool regularExpression = false,
    bool wholeWord = false,
  }) => document.search(
    query,
    caseSensitive: caseSensitive,
    regularExpression: regularExpression,
    wholeWord: wholeWord,
  );

  /// Replaces all matches as one undoable transaction.
  void replaceAll(
    String query,
    String replacement, {
    bool caseSensitive = false,
    bool regularExpression = false,
    bool wholeWord = false,
  }) {
    final found = find(
      query,
      caseSensitive: caseSensitive,
      regularExpression: regularExpression,
      wholeWord: wholeWord,
    );
    document.applyEdits([
      for (final range in found) DocumentEdit(range, replacement),
    ]);
  }

  /// Runs a renderer-neutral editing command against the current selections.
  void execute(EditorCommand command) {
    checkAlive();
    switch (command) {
      case EditorCommand.undo:
        undo();
      case EditorCommand.redo:
        redo();
      case EditorCommand.selectAll:
        setSelections([DocumentSelection(0, document.length)]);
      case EditorCommand.simplifySelection:
        setSelections([DocumentSelection.collapsed(selections.last.active)]);
      case EditorCommand.indent:
        _indent(false);
      case EditorCommand.outdent:
        _indent(true);
      case EditorCommand.toggleComment:
        _comment();
      case EditorCommand.toggleBlockComment:
        _blockComment();
      case EditorCommand.moveLineUp:
        _moveLines(-1, false);
      case EditorCommand.moveLineDown:
        _moveLines(1, false);
      case EditorCommand.copyLineUp:
        _moveLines(-1, true);
      case EditorCommand.copyLineDown:
        _moveLines(1, true);
      case EditorCommand.insertBlankLine:
        final line = document.positionAt(selections.last.active).line;
        final end = document.lineStart(line) + document.lineText(line).length;
        applyEdits([OffsetEdit(end, end, document.eol)]);
        setSelections([DocumentSelection.collapsed(end + document.eol.length)]);
      case EditorCommand.deleteLine:
        final lines = _selectedLines().toList()..sort();
        applyEdits([
          for (final line in lines)
            OffsetEdit(
              document.lineStart(line),
              line + 1 < document.lineCount
                  ? document.lineStart(line + 1)
                  : document.length,
              '',
            ),
        ]);
      case EditorCommand.acceptProposal:
        acceptProposal();
      case EditorCommand.dismissProposal:
        dismissProposal();
    }
  }

  Set<int> _selectedLines() => {
    for (final selection in selections)
      for (
        var line = document.positionAt(selection.start).line;
        line <=
            document
                .positionAt(
                  selection.end > selection.start
                      ? selection.end - 1
                      : selection.end,
                )
                .line;
        line++
      )
        line,
  };

  void _indent(bool remove) {
    applyEdits([
      for (final line in _selectedLines())
        if (!remove)
          OffsetEdit(
            document.lineStart(line),
            document.lineStart(line),
            ' ' * tabSize,
          )
        else
          OffsetEdit(
            document.lineStart(line),
            document.lineStart(line) +
                (RegExp(
                      '^ {1,$tabSize}|^\\t',
                    ).firstMatch(document.lineText(line))?[0]?.length ??
                    0),
            '',
          ),
    ]);
  }

  void _comment() {
    if (lineComment.isEmpty) return;
    final lines = _selectedLines();
    final remove = lines.every(
      (l) => document.lineText(l).trimLeft().startsWith(lineComment),
    );
    applyEdits([
      for (final line in lines)
        (() {
          final text = document.lineText(line);
          final indent = text.length - text.trimLeft().length;
          final start = document.lineStart(line) + indent;
          final extra =
              remove &&
                  text.substring(indent + lineComment.length).startsWith(' ')
              ? 1
              : 0;
          return OffsetEdit(
            start,
            start + (remove ? lineComment.length + extra : 0),
            remove ? '' : '$lineComment ',
          );
        })(),
    ]);
  }

  void _blockComment() {
    final (open, close) = blockComment;
    applyEdits([
      for (final s in _normalizedSelections())
        (() {
          final selected = document.text.substring(s.start, s.end);
          final remove =
              selected.startsWith(open) &&
              selected.endsWith(close) &&
              selected.length >= open.length + close.length;
          return OffsetEdit(
            s.start,
            s.end,
            remove
                ? selected.substring(
                    open.length,
                    selected.length - close.length,
                  )
                : '$open$selected$close',
          );
        })(),
    ]);
  }

  void _moveLines(int direction, bool copy) {
    final lines = _selectedLines().toList()..sort();
    final groups = <(int, int)>[];
    for (final line in lines) {
      if (groups.isNotEmpty && line == groups.last.$2 + 1) {
        final previous = groups.removeLast();
        groups.add((previous.$1, line));
      } else {
        groups.add((line, line));
      }
    }
    final contents = [
      for (var i = 0; i < document.lineCount; i++) document.lineText(i),
    ];
    final endings = [
      for (var i = 0; i < document.lineCount; i++)
        document
            .lineText(i, includeTerminator: true)
            .substring(contents[i].length),
    ];
    final edits = <OffsetEdit>[];
    final targets = <(int, int)>[];
    var insertedLines = 0;
    for (final (first, last) in groups) {
      final selected = contents.sublist(first, last + 1);
      final regionStart = copy
          ? (direction < 0 ? first : last + 1)
          : (direction < 0 ? first - 1 : first);
      if (!copy &&
          (regionStart < 0 ||
              last + (direction > 0 ? 1 : 0) >= contents.length)) {
        continue;
      }
      if (copy) {
        final insertion = regionStart < document.lineCount
            ? document.lineStart(regionStart)
            : document.length;
        final duplicate = StringBuffer();
        if (regionStart == document.lineCount && endings.last.isEmpty) {
          duplicate.write(document.eol);
        }
        for (var i = first; i <= last; i++) {
          duplicate.write(contents[i]);
          final isEnd = i == last && regionStart == document.lineCount;
          duplicate.write(
            isEnd
                ? endings.last
                : endings[i].isEmpty
                ? document.eol
                : endings[i],
          );
        }
        edits.add(OffsetEdit(insertion, insertion, duplicate.toString()));
      } else {
        final regionEnd = last + (direction > 0 ? 1 : 0);
        final moved = direction < 0
            ? [...selected, contents[first - 1]]
            : [contents[last + 1], ...selected];
        final replacement = StringBuffer();
        for (var i = 0; i < moved.length; i++) {
          replacement
            ..write(moved[i])
            ..write(endings[regionStart + i]);
        }
        edits.add(
          OffsetEdit(
            document.lineStart(regionStart),
            regionEnd + 1 < document.lineCount
                ? document.lineStart(regionEnd + 1)
                : document.length,
            replacement.toString(),
          ),
        );
      }
      final target =
          (copy ? (direction < 0 ? first : last + 1) : first + direction) +
          insertedLines;
      targets.add((target, selected.length));
      if (copy) insertedLines += selected.length;
    }
    if (edits.isEmpty) return;
    applyEdits(edits);
    setSelections([
      for (final (first, count) in targets)
        DocumentSelection(
          document.lineStart(first),
          document.lineStart(first + count - 1) +
              document.lineText(first + count - 1).length,
        ),
    ]);
  }

  /// Finds the matching bracket while allowing a tokenizer to exclude strings
  /// and comments. Returns null for unmatched or ignored brackets.
  int? matchingBracket(int offset, {bool Function(int)? isIgnored}) {
    final source = document.text;
    if (offset < 0 ||
        offset >= source.length ||
        (isIgnored?.call(offset) ?? false)) {
      return null;
    }
    const opens = '([{';
    const closes = ')]}';
    final c = source[offset];
    final forward = opens.contains(c);
    final index = forward ? opens.indexOf(c) : closes.indexOf(c);
    if (index < 0) return null;
    final match = forward ? closes[index] : opens[index];
    var depth = 0;
    for (var i = offset; i >= 0 && i < source.length; i += forward ? 1 : -1) {
      if (isIgnored?.call(i) ?? false) continue;
      if (source[i] == c) depth++;
      if (source[i] == match && --depth == 0) return i;
    }
    return null;
  }

  void _scheduleProposal() {
    if (proposalProvider == null || isDisposed) return;
    _timer = Timer(proposalDelay, requestProposal);
  }

  /// Requests proposed edits, discarding cancelled or obsolete responses.
  Future<void> requestProposal() async {
    checkAlive();
    dismissProposal(notify: false);
    final provider = proposalProvider;
    if (provider == null) return;
    final token = _pending = CancellationToken();
    final revision = document.revision;
    final request = ProposedEditRequest(
      file: file,
      selections: selections,
      cancellation: token,
    );
    proposalError = null;
    notifyListeners();
    try {
      final edits = await provider(request);
      if (token.isCancelled || isDisposed || document.revision != revision) {
        return;
      }
      // Validate without touching the real document or its undo stack.
      final validation = TextDocument(document.text);
      try {
        validation.applyOffsetEdits(edits);
      } finally {
        validation.dispose();
      }
      _proposal = List.unmodifiable(edits);
      _proposalRevision = revision;
    } on Object catch (error) {
      if (!token.isCancelled && !isDisposed) proposalError = error;
    } finally {
      if (identical(_pending, token)) {
        _pending = null;
        if (!isDisposed) notifyListeners();
      }
    }
  }

  /// Applies the current proposed edits as one undoable transaction.
  void acceptProposal() {
    if (_proposalRevision != document.revision || _proposal.isEmpty) return;
    final edits = _proposal;
    dismissProposal(notify: false);
    applyEdits(edits);
  }

  /// Cancels pending proposals and removes their preview.
  void dismissProposal({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    _pending?.cancel();
    _pending = null;
    _proposal = const [];
    _proposalRevision = null;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    dismissProposal(notify: false);
    document.removeListener(_documentChanged);
    if (_ownsDocument) document.dispose();
    super.dispose();
  }
}
