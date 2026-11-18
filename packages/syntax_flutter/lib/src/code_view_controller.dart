import 'package:flutter/foundation.dart';

/// Source and directed line selection for a read-only code view.
///
/// Lines are zero-based and inclusive. Empty source has one empty line;
/// a trailing newline introduces an empty final line. Dispose the controller
/// when its owner no longer needs it. A controller can outlive its view.
class CodeViewController extends ChangeNotifier {
  /// Starts with [code] at [revision] for the stable [sourceId].
  CodeViewController({
    required this.sourceId,
    required String code,
    int revision = 0,
  }) : _code = code,
       _revision = revision,
       _lines = code.split('\n');

  /// Stable identity of the source displayed by this controller.
  final String sourceId;

  String _code;
  int _revision;
  List<String> _lines;
  ({int anchor, int active})? _selection;
  int? _revealTarget;
  int _revealRequest = 0;
  int _selectionRequest = 0;

  /// Exact source bytes represented as a Dart string, including line breaks.
  String get code => _code;

  /// Caller-supplied revision of [code].
  int get revision => _revision;

  /// Number of source lines, including an empty final line after a newline.
  int get lineCount => _lines.length;

  /// Directed, inclusive line selection, or `null` before a selection.
  ({int anchor, int active})? get selection => _selection;

  /// Selected source with its original intervening line breaks.
  ///
  /// Excludes the separator after the last selected line. Returns `null`
  /// when no lines are selected and an empty string for an empty line.
  String? get selectedText {
    final selection = _selection;
    if (selection == null) return null;
    final start = selection.anchor < selection.active
        ? selection.anchor
        : selection.active;
    final end = selection.anchor > selection.active
        ? selection.anchor
        : selection.active;
    final last = _lines[end];
    return [
      ..._lines.getRange(start, end),
      last.endsWith('\r') && end < lineCount - 1
          ? last.substring(0, last.length - 1)
          : last,
    ].join('\n');
  }

  /// Replaces the source and clears line selection and pending reveal.
  ///
  /// Updating only the revision also clears selection. An identical source
  /// and revision is a no-op. Revisions are caller-owned and need not increase.
  void setCode(String code, {required int revision}) {
    if (code == _code && revision == _revision) return;
    _code = code;
    _revision = revision;
    _lines = code.split('\n');
    _selection = null;
    _revealTarget = null;
    notifyListeners();
  }

  /// Selects complete lines from [anchor] to [active], preserving direction.
  ///
  /// Throws [RangeError] if either line is outside the source.
  void selectLines(int anchor, int active) {
    _checkLine(anchor);
    _checkLine(active);
    _selection = (anchor: anchor, active: active);
    _selectionRequest++;
    notifyListeners();
  }

  /// Requests that [line] be brought into view without changing selection.
  ///
  /// Before mounting, the latest request waits for a view. Repeating a
  /// request reveals the line again. Throws [RangeError] for an invalid line.
  void revealLine(int line) {
    _checkLine(line);
    _revealTarget = line;
    _revealRequest++;
    notifyListeners();
  }

  /// Latest requested zero-based line, retained for a subsequently mounted view.
  @internal
  int? get revealTarget => _revealTarget;

  /// Serial identifying repeated reveal commands to the same line.
  @internal
  int get revealRequest => _revealRequest;

  /// Serial identifying repeated line-selection commands for mounted views.
  @internal
  int get selectionRequest => _selectionRequest;

  void _checkLine(int line) => RangeError.checkValidIndex(line, _lines, 'line');
}
