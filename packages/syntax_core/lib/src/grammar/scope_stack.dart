/// An immutable stack of scope names, innermost last, for example
/// `source.dart > string.interpolated.single.dart`.
///
/// Stacks share their parents, so pushing is cheap. Tokens keep a reference
/// to the stack instead of copying it.
final class ScopeStack {
  ScopeStack._(this.parent, this.scope)
    : depth = parent == null ? 1 : parent.depth + 1;

  /// A stack holding the single root [scope].
  ScopeStack.root(String scope) : this._(null, scope);

  /// The stack without its innermost scope, or `null` at the root.
  final ScopeStack? parent;

  /// The innermost scope name.
  final String scope;

  /// How many scopes the stack holds.
  final int depth;

  /// Pushes [scopePath]. Space-separated paths push one scope per segment,
  /// as in vscode-textmate. A `null` or empty path returns this stack.
  ScopeStack push(String? scopePath) {
    if (scopePath == null || scopePath.isEmpty) return this;
    if (!scopePath.contains(' ')) return ScopeStack._(this, scopePath);
    var result = this;
    for (final segment in scopePath.split(' ')) {
      if (segment.isNotEmpty) result = ScopeStack._(result, segment);
    }
    return result;
  }

  /// Scope names from outermost to innermost.
  late final List<String> scopes = _toList();

  List<String> _toList() {
    final result = List<String>.filled(depth, '');
    ScopeStack? node = this;
    for (var i = depth - 1; i >= 0; i--) {
      result[i] = node!.scope;
      node = node.parent;
    }
    return List.unmodifiable(result);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScopeStack || other.depth != depth) return false;
    ScopeStack? a = this;
    ScopeStack? b = other;
    while (a != null && b != null) {
      if (identical(a, b)) return true;
      if (a.scope != b.scope) return false;
      a = a.parent;
      b = b.parent;
    }
    return a == null && b == null;
  }

  @override
  int get hashCode => Object.hash(scope, depth, parent?.scope);

  @override
  String toString() => scopes.join(' ');
}
