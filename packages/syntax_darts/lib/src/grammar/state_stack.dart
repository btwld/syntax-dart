part of 'grammar.dart';

/// Tokenizer state at a line boundary: the stack of open grammar rules.
///
/// It is opaque. Pass the state returned for one line into the next line of
/// the same [Grammar]. Two equal states produce identical tokens for
/// identical text, so an editor can stop re-tokenizing once the state after
/// an edit converges.
final class StateStack {
  StateStack._(
    this._grammar,
    this._parent,
    this._ruleId,
    this._enterPos,
    this._anchorPos,
    this._beginRuleCapturedEOL,
    this._endRule,
    this._nameScopes,
    this._contentNameScopes,
  ) : _depth = _parent == null ? 1 : _parent._depth + 1;

  final Grammar _grammar;
  final StateStack? _parent;
  final int _ruleId;

  /// Position in the current line where this rule was pushed, or -1 when it
  /// was pushed on an earlier line.
  final int _enterPos;

  /// Position where `\G` may match after this rule is popped, or -1 when the
  /// rule was pushed on an earlier line.
  final int _anchorPos;

  /// Whether the begin match ended at the end of the line. If so, `\G` may
  /// match at the start of the next line.
  final bool _beginRuleCapturedEOL;

  /// The `end` or `while` pattern with backreferences resolved, if any.
  final String? _endRule;

  /// Scopes including this rule's `name`.
  final ScopeStack _nameScopes;

  /// Scopes including this rule's `contentName`. Text between the begin and
  /// end matches gets these scopes.
  final ScopeStack _contentNameScopes;

  final int _depth;

  /// The scopes open at this point, for example `source.dart
  /// comment.block.dart` at the end of a line inside a block comment.
  ScopeStack get scopes => _contentNameScopes;

  StateStack _push(
    int ruleId,
    int enterPos,
    int anchorPos,
    bool beginRuleCapturedEOL,
    ScopeStack nameScopes,
    ScopeStack contentNameScopes,
  ) => StateStack._(
    _grammar,
    this,
    ruleId,
    enterPos,
    anchorPos,
    beginRuleCapturedEOL,
    null,
    nameScopes,
    contentNameScopes,
  );

  StateStack? _pop() => _parent;

  /// Pops unless this is the root.
  StateStack _safePop() => _parent ?? this;

  StateStack _withContentNameScopes(ScopeStack scopes) =>
      identical(scopes, _contentNameScopes)
      ? this
      : StateStack._(
          _grammar,
          _parent,
          _ruleId,
          _enterPos,
          _anchorPos,
          _beginRuleCapturedEOL,
          _endRule,
          _nameScopes,
          scopes,
        );

  StateStack _withEndRule(String endRule) => _endRule == endRule
      ? this
      : StateStack._(
          _grammar,
          _parent,
          _ruleId,
          _enterPos,
          _anchorPos,
          _beginRuleCapturedEOL,
          endRule,
          _nameScopes,
          _contentNameScopes,
        );

  /// Whether a frame entered at the same position already holds this rule.
  /// This catches grammars that push the same rule forever.
  bool _hasSameRuleAs(StateStack other) {
    StateStack? node = this;
    while (node != null && node._enterPos == other._enterPos) {
      if (node._ruleId == other._ruleId) return true;
      node = node._parent;
    }
    return false;
  }

  /// This state with all line positions cleared, ready for the next line.
  StateStack _reset() => _isReset
      ? this
      : StateStack._(
          _grammar,
          _parent?._reset(),
          _ruleId,
          -1,
          -1,
          _beginRuleCapturedEOL,
          _endRule,
          _nameScopes,
          _contentNameScopes,
        );

  bool get _isReset =>
      _enterPos == -1 && _anchorPos == -1 && (_parent?._isReset ?? true);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StateStack ||
        other._depth != _depth ||
        !identical(other._grammar, _grammar)) {
      return false;
    }
    StateStack? a = this;
    StateStack? b = other;
    while (a != null && b != null) {
      if (identical(a, b)) return true;
      if (a._ruleId != b._ruleId ||
          a._endRule != b._endRule ||
          a._beginRuleCapturedEOL != b._beginRuleCapturedEOL ||
          a._contentNameScopes != b._contentNameScopes) {
        return false;
      }
      a = a._parent;
      b = b._parent;
    }
    return a == null && b == null;
  }

  @override
  int get hashCode =>
      Object.hash(_ruleId, _depth, _endRule, _contentNameScopes);

  @override
  String toString() => 'StateStack($_contentNameScopes)';
}
