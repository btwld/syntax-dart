// Decoders such as JavaScript dartify produce maps with dynamic key types.
// A fresh cast wrapper on every lookup breaks the rule compiler's identity
// table, so a recursive include would never find its in-progress rule.
final _views = Expando<Map<String, Object?>>('grammar map views');

/// Returns a stable typed view so recursive rule identity survives decoding.
Map<String, Object?> asGrammarMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return _views[value] ??= value.cast<String, Object?>();
  }
  return const {};
}
