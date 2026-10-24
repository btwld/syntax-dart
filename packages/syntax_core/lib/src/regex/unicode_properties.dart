// Oniguruma property and POSIX bracket names mapped to ECMAScript.
part of 'onig_translator.dart';

String _normalizePropertyName(String name) =>
    name.replaceAll(RegExp(r'[\s_\-]'), '').toLowerCase();

const _posix = <String, String>{
  'alnum': r'\p{L}\p{M}\p{Nd}',
  'alpha': r'\p{L}\p{M}',
  'ascii': r'\u{0}-\u{7F}',
  'blank': r'\p{Zs}\t',
  'cntrl': r'\p{Cc}',
  'digit': r'\p{Nd}',
  'graph': r'\p{L}\p{M}\p{N}\p{P}\p{S}',
  'lower': r'\p{Ll}',
  'print': r'\p{L}\p{M}\p{N}\p{P}\p{S}\p{Zs}',
  'punct': r'\p{P}$+<=>^`|~',
  'space': r'\s',
  'upper': r'\p{Lu}',
  'xdigit': r'0-9A-Fa-f',
  'word': r'\p{L}\p{M}\p{Nd}\p{Pc}',
};

/// Class content for a POSIX bracket name such as `alpha`, or `null`.
String? posixClassContent(String name) => _posix[name.toLowerCase()];

const _generalCategories = [
  'L',
  'Letter',
  'Lu',
  'Uppercase_Letter',
  'Ll',
  'Lowercase_Letter',
  'Lt',
  'Titlecase_Letter',
  'LC',
  'Cased_Letter',
  'Lm',
  'Modifier_Letter',
  'Lo',
  'Other_Letter',
  'M',
  'Mark',
  'Mn',
  'Nonspacing_Mark',
  'Mc',
  'Spacing_Mark',
  'Me',
  'Enclosing_Mark',
  'N',
  'Number',
  'Nd',
  'Decimal_Number',
  'Nl',
  'Letter_Number',
  'No',
  'Other_Number',
  'P',
  'Punctuation',
  'Pc',
  'Connector_Punctuation',
  'Pd',
  'Dash_Punctuation',
  'Ps',
  'Open_Punctuation',
  'Pe',
  'Close_Punctuation',
  'Pi',
  'Initial_Punctuation',
  'Pf',
  'Final_Punctuation',
  'Po',
  'Other_Punctuation',
  'S',
  'Symbol',
  'Sm',
  'Math_Symbol',
  'Sc',
  'Currency_Symbol',
  'Sk',
  'Modifier_Symbol',
  'So',
  'Other_Symbol',
  'Z',
  'Separator',
  'Zs',
  'Space_Separator',
  'Zl',
  'Line_Separator',
  'Zp',
  'Paragraph_Separator',
  'C',
  'Other',
  'Cc',
  'Control',
  'Cf',
  'Format',
  'Cs',
  'Surrogate',
  'Co',
  'Private_Use',
  'Cn',
  'Unassigned',
];

const _binaryProperties = [
  'ASCII',
  'ASCII_Hex_Digit',
  'Alphabetic',
  'Any',
  'Assigned',
  'Bidi_Control',
  'Cased',
  'Dash',
  'Default_Ignorable_Code_Point',
  'Diacritic',
  'Emoji',
  'Emoji_Component',
  'Emoji_Modifier',
  'Emoji_Modifier_Base',
  'Emoji_Presentation',
  'Extended_Pictographic',
  'Extender',
  'Hex_Digit',
  'ID_Continue',
  'ID_Start',
  'Ideographic',
  'Join_Control',
  'Lowercase',
  'Math',
  'Noncharacter_Code_Point',
  'Pattern_Syntax',
  'Pattern_White_Space',
  'Quotation_Mark',
  'Regional_Indicator',
  'Sentence_Terminal',
  'Terminal_Punctuation',
  'Unified_Ideograph',
  'Uppercase',
  'Variation_Selector',
  'White_Space',
  'XID_Continue',
  'XID_Start',
];

final Map<String, String> _propertyLookup = {
  for (final p in _generalCategories) _normalizePropertyName(p): '\\p{$p}',
  for (final p in _binaryProperties) _normalizePropertyName(p): '\\p{$p}',
  for (final e in _posix.entries) e.key: e.value,
};

final Map<String, String?> _scriptCache = {};

/// Class content (valid inside `[…]`) for an Oniguruma property name, or
/// `null` if ECMAScript has no equivalent. Bare script names such as `Greek`
/// become `Script=Greek`.
String? unicodePropertyClassContent(String name) {
  final normalized = _normalizePropertyName(name);
  final known = _propertyLookup[normalized];
  if (known != null) return known;
  if (RegExp('^In_', caseSensitive: false).hasMatch(name)) {
    return null; // Unicode blocks have no ECMAScript equivalent.
  }
  return _scriptCache.putIfAbsent(normalized, () {
    // ECMAScript accepts some aliases directly, such as XIDS or Alpha.
    final direct = '\\p{$name}';
    try {
      RegExp(direct, unicode: true);
      return direct;
    } on FormatException {
      // Fall through to a script name.
    }
    final canonical = name
        .split(RegExp(r'[\s_\-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join('_');
    final candidate = '\\p{Script=$canonical}';
    try {
      RegExp(candidate, unicode: true);
      return candidate;
    } on FormatException {
      return null;
    }
  });
}

String _propertyOutsideClass(String content, bool negated) {
  final single = RegExp(r'^\\p\{[^}]+\}$').hasMatch(content);
  if (single) return negated ? content.replaceFirst(r'\p', r'\P') : content;
  return negated ? '[^$content]' : '[$content]';
}
