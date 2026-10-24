// Parses Oniguruma (Ruby syntax) source into the AST in onig_ast.dart.
part of 'onig_translator.dart';

final class _Flags {
  const _Flags({this.i = false, this.x = false, this.m = false});
  final bool i;
  final bool x;
  final bool m;

  _Flags apply(String on, String off) => _Flags(
    i: off.contains('i') ? false : (on.contains('i') || i),
    x: off.contains('x') ? false : (on.contains('x') || x),
    m: off.contains('m') ? false : (on.contains('m') || m),
  );
}

/// Result of a group that only switches flags, e.g. `(?i)`.
final class _IsolatedFlags extends _Node {
  _IsolatedFlags(this.flags);
  final _Flags flags;
}

final class _Parser {
  /// With [prescan], the parser only records capture group names and
  /// skips checks that need the whole pattern. See [_groupNames].
  _Parser(this.src, {this.prescan = false});

  final String src;
  final bool prescan;
  int _i = 0;
  int _groupCount = 0;
  final Map<int, _Group> _groups = {};
  final Map<String, List<int>> _names = {};
  final List<String?> _namesInOrder = [];
  int _gCount = 0;
  bool _hasA = false;
  bool _hasKeep = false;
  bool _hasBackrefs = false;
  bool _usesWords = false;

  Never _fail(String reason) => throw UnsupportedPatternException(src, reason);

  _Ast parse() {
    final root = _parseAlternation(const _Flags(), topLevel: true);
    if (_i < src.length) _fail('unbalanced parenthesis');
    return _Ast(
      root: root,
      groupCount: _groupCount,
      groups: _groups,
      globalCi: _allCaseInsensitive(root),
      hasA: _hasA,
      hasG: _gCount > 0,
      // `\K` needs a search, so a leading `\G` can't use matchAsPrefix.
      leadingG: _gCount > 0 && !_hasKeep && _isLeadingG(root, _gCount),
      hasKeep: _hasKeep,
      hasBackrefs: _hasBackrefs,
      usesWords: _usesWords,
    );
  }

  /// Whether every case-sensitive atom is under `(?i)`. Then the pattern
  /// can use the RegExp flag, which applies Unicode case folding, instead
  /// of expanding letters one by one.
  static bool _allCaseInsensitive(_Node root) {
    var any = false;
    bool visit(_Node n) => switch (n) {
      _Char(:final ci) ||
      _Class(:final ci) ||
      _Backref(:final ci) => (any = true) && ci,
      _Alt(:final branches) => branches.every(visit),
      _Seq(:final items) => items.every(visit),
      _Group(:final body) => visit(body),
      _Quant(:final atom) => visit(atom),
      _ => true,
    };
    return visit(root) && any;
  }

  /// Names of all capture groups in order, `null` for unnamed ones, from a
  /// first parsing pass. Lets the parser tell a `\12` backreference from an
  /// octal escape, and resolve references to groups defined later.
  late final List<String?> _groupNames = prescan
      ? const []
      : ((_Parser(src, prescan: true)..parse())._namesInOrder);

  /// During the prescan every multi-digit escape counts as a backreference.
  /// That only affects how many digits are read, never group numbering.
  int get _totalGroups => prescan ? 1 << 30 : _groupNames.length;

  bool _isLeadingG(_Node root, int gCount) {
    bool startsWithG(_Node n) => switch (n) {
      _Seq(:final items) =>
        items.isNotEmpty &&
            (items.first is _Marker &&
                    (items.first as _Marker).marker == gMarker ||
                items.length == 1 && startsWithG(items.first)),
      _Group(kind: _GroupKind.nonCapture, :final body) => startsWithG(body),
      _Alt(:final branches) => branches.every(startsWithG),
      _Marker(:final marker) => marker == gMarker,
      _ => false,
    };
    int branchCount(_Node n) => switch (n) {
      _Alt(:final branches) => branches.length,
      _Seq(:final items) when items.length == 1 => branchCount(items.first),
      _Group(kind: _GroupKind.nonCapture, :final body) => branchCount(body),
      _ => 1,
    };
    return startsWithG(root) && branchCount(root) == gCount;
  }

  bool get _atEnd => _i >= src.length;
  String get _peek => src[_i];
  bool _lookingAt(String s) => src.startsWith(s, _i);

  _Node _parseAlternation(_Flags flags, {bool topLevel = false}) {
    final branches = <_Node>[_parseSequence(flags)];
    while (!_atEnd && _peek == '|') {
      _i++;
      branches.add(_parseSequence(flags));
    }
    if (!topLevel && _atEnd) _fail('missing )');
    return branches.length == 1 ? branches.single : _Alt(branches);
  }

  void _skipExtended(_Flags flags) {
    if (!flags.x) return;
    while (!_atEnd) {
      final c = _peek;
      if (c == ' ' ||
          c == '\t' ||
          c == '\n' ||
          c == '\r' ||
          c == '\f' ||
          c == '\v') {
        _i++;
      } else if (c == '#') {
        while (!_atEnd && _peek != '\n') {
          _i++;
        }
      } else {
        break;
      }
    }
  }

  _Node _parseSequence(_Flags flags) {
    final items = <_Node>[];
    while (true) {
      _skipExtended(flags);
      if (_atEnd || _peek == '|' || _peek == ')') break;
      final atom = _parseAtom(flags);
      if (atom == null) continue;
      if (atom is _IsolatedFlags) {
        // Oniguruma: an isolated option group spans the rest of the
        // enclosing group, including later alternatives.
        final rest = _parseAlternationUntilClose(atom.flags);
        items.add(_Group(_GroupKind.nonCapture, rest));
        break;
      }
      items.add(_parseQuantifiers(atom, flags));
    }
    return _Seq(items);
  }

  _Node _parseAlternationUntilClose(_Flags flags) {
    final branches = <_Node>[_parseSequence(flags)];
    while (!_atEnd && _peek == '|') {
      _i++;
      branches.add(_parseSequence(flags));
    }
    return branches.length == 1 ? branches.single : _Alt(branches);
  }

  _Node _parseQuantifiers(_Node atom, _Flags flags) {
    var node = atom;
    while (true) {
      _skipExtended(flags);
      if (_atEnd) break;
      final c = _peek;
      int min;
      int? max;
      var braces = false;
      if (c == '*') {
        min = 0;
        max = null;
        _i++;
      } else if (c == '+') {
        min = 1;
        max = null;
        _i++;
      } else if (c == '?') {
        min = 0;
        max = 1;
        _i++;
      } else if (c == '{') {
        final interval = _tryInterval();
        if (interval == null) break;
        bool reversed;
        (min, max, reversed) = interval;
        braces = true;
        if (reversed) {
          // Oniguruma (Ruby syntax) reads `{n,m}` with n > m as a
          // possessive `{m,n}`.
          node = _Quant(node, min, max, possessive: true);
          continue;
        }
      } else {
        break;
      }
      var lazy = false;
      var possessive = false;
      if (!_atEnd && _peek == '?') {
        lazy = true;
        _i++;
      } else if (!braces && !_atEnd && _peek == '+') {
        // In Ruby syntax only `*+`, `++` and `?+` are possessive. `{n,m}+`
        // is a second quantifier, handled by the next loop iteration.
        possessive = true;
        _i++;
      }
      node = _Quant(node, min, max, lazy: lazy, possessive: possessive);
    }
    return node;
  }

  (int, int?, bool)? _tryInterval() {
    final m = RegExp(r'\{(\d*)(,?)(\d*)\}').matchAsPrefix(src, _i);
    if (m == null) return null;
    final a = m.group(1)!;
    final comma = m.group(2)!.isNotEmpty;
    final b = m.group(3)!;
    if (a.isEmpty && (!comma || b.isEmpty)) return null;
    _i = m.end;
    final min = a.isEmpty ? 0 : int.parse(a);
    final max = comma ? (b.isEmpty ? null : int.parse(b)) : min;
    if (max != null && max < min) return (max, min, true);
    return (min, max, false);
  }

  _Node? _parseAtom(_Flags flags) {
    final c = _peek;
    switch (c) {
      case '(':
        return _parseGroup(flags);
      case '[':
        _i++;
        return _Class(_parseClass(flags), flags.i);
      case '.':
        _i++;
        return _Dot(flags.m);
      case '^':
        _i++;
        // Oniguruma's `^` does not match after a newline that ends the
        // input. ECMAScript's multiline `^` does, which would make `^$`
        // match after the "\n" vscode-textmate appends to every line.
        return _Raw(r'(?:(?<![\s\S])|(?<=\n)(?=[\s\S]))', assertion: true);
      case r'$':
        _i++;
        return _Raw(r'$', assertion: true);
      case r'\':
        return _parseEscape(flags);
      case '*':
      case '+':
      case '?':
        _fail('quantifier without target');
      default:
        return _Char(_readCodePoint(), flags.i);
    }
  }

  int _readCodePoint() {
    final unit = src.codeUnitAt(_i++);
    if (unit >= 0xD800 && unit <= 0xDBFF && !_atEnd) {
      final next = src.codeUnitAt(_i);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        _i++;
        return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
      }
    }
    return unit;
  }

  _Node? _parseGroup(_Flags flags) {
    _i++; // (
    if (!_lookingAt('?')) {
      _namesInOrder.add(null);
      final index = ++_groupCount;
      final body = _parseAlternation(flags);
      _expect(')');
      return _groups[index] = _Group(_GroupKind.capture, body, index: index);
    }
    _i++; // ?
    if (_atEnd) _fail('bad group');
    final c = _peek;
    _GroupKind? kind;
    if (c == '#') {
      while (!_atEnd && _peek != ')') {
        _i++;
      }
      _expect(')');
      return null;
    } else if (c == ':') {
      kind = _GroupKind.nonCapture;
      _i++;
    } else if (c == '=') {
      kind = _GroupKind.lookahead;
      _i++;
    } else if (c == '!') {
      kind = _GroupKind.negativeLookahead;
      _i++;
    } else if (c == '>') {
      kind = _GroupKind.atomic;
      _i++;
    } else if (_lookingAt('<=')) {
      kind = _GroupKind.lookbehind;
      _i += 2;
    } else if (_lookingAt('<!')) {
      kind = _GroupKind.negativeLookbehind;
      _i += 2;
    } else if (c == '<' || c == "'" || _lookingAt('P<')) {
      if (c == 'P') _i++;
      final close = _peek == '<' ? '>' : "'";
      _i++;
      final end = src.indexOf(close, _i);
      if (end < 0) _fail('unterminated group name');
      final name = src.substring(_i, end);
      _i = end + 1;
      _namesInOrder.add(name);
      final index = ++_groupCount;
      (_names[name] ??= []).add(index);
      final body = _parseAlternation(flags);
      _expect(')');
      return _groups[index] = _Group(_GroupKind.capture, body, index: index);
    } else if (c == '~') {
      _i++;
      if (_atEnd) _fail('absent operator');
      // The absent repeater consumes characters only while its body does not
      // match. Stopper/expression forms use a distinct range-state operator.
      if (_peek == '|') _fail('absent range operator');
      final body = _parseAlternation(flags);
      _expect(')');
      if (!_isValidAbsentRepeater(body, flags)) {
        _fail('absent operator');
      }
      return _Quant(
        _Group(
          _GroupKind.nonCapture,
          _Seq([_Group(_GroupKind.negativeLookahead, body), _Dot(true)]),
        ),
        0,
        null,
      );
    } else if (c == '(') {
      _fail('conditional');
    } else {
      final m = RegExp(r'([imx]*)(?:-([imx]*))?([:)])').matchAsPrefix(src, _i);
      if (m == null) _fail('unknown group (?$c');
      _i = m.end;
      final newFlags = flags.apply(m.group(1)!, m.group(2) ?? '');
      if (m.group(3) == ')') return _IsolatedFlags(newFlags);
      final body = _parseAlternation(newFlags);
      _expect(')');
      return _Group(_GroupKind.nonCapture, body);
    }
    final body = _parseAlternation(flags);
    _expect(')');
    return _Group(kind, body);
  }

  void _expect(String s) {
    if (!_lookingAt(s)) _fail('expected $s');
    _i += s.length;
  }

  /// `(?:(?!body)[\s\S])*` matches Oniguruma's `(?~body)` only when [body]
  /// is a single character or a non-self-overlapping literal delimiter
  /// immediately followed by that delimiter.
  bool _isValidAbsentRepeater(_Node body, _Flags flags) {
    if (_peekQuantifier(flags)) return false;
    if (_isSingleChar(body)) return true;
    final chars = _literalChars(body);
    if (chars == null || chars.length < 2) return false;
    for (var offset = 1; offset < chars.length; offset++) {
      var overlaps = true;
      for (var j = 0; offset + j < chars.length; j++) {
        if (!_sameChar(chars[offset + j], chars[j])) {
          overlaps = false;
          break;
        }
      }
      if (overlaps) return false;
    }
    final saved = _i;
    try {
      for (final expected in chars) {
        _skipExtended(flags);
        if (_atEnd || _peek == '|' || _peek == ')') return false;
        final actual = _readLiteralChar(flags);
        if (actual == null ||
            actual.cp != expected.cp ||
            actual.ci != expected.ci ||
            _peekQuantifier(flags)) {
          return false;
        }
      }
      return true;
    } on UnsupportedPatternException {
      return false;
    } finally {
      _i = saved;
    }
  }

  bool _peekQuantifier(_Flags flags) {
    final saved = _i;
    try {
      _skipExtended(flags);
      if (_atEnd) return false;
      final c = _peek;
      if (c == '*' || c == '+' || c == '?') return true;
      return c == '{' && _tryInterval() != null;
    } finally {
      _i = saved;
    }
  }

  _Char? _readLiteralChar(_Flags flags) {
    final c = _peek;
    if (c == r'\') {
      _i++;
      if (_atEnd) return null;
      final esc = _peek;
      if (const {
        'A',
        'G',
        'z',
        'Z',
        'b',
        'B',
        'd',
        'D',
        'w',
        'W',
        's',
        'S',
        'h',
        'H',
        'R',
        'N',
        'O',
        'X',
        'K',
        'p',
        'P',
        'k',
        'g',
        'y',
        'Y',
      }.contains(esc)) {
        return null;
      }
      if (_isDigit(esc)) {
        final node = _parseNumericEscape(flags);
        return node is _Char ? node : null;
      }
      return _Char(_readEscapedChar(inClass: false), flags.i);
    }
    if (c == '(' ||
        c == '[' ||
        c == '.' ||
        c == '^' ||
        c == r'$' ||
        c == '*' ||
        c == '+' ||
        c == '?') {
      return null;
    }
    return _Char(_readCodePoint(), flags.i);
  }

  static bool _isSingleChar(_Node node) => switch (node) {
    _Char() || _Class() || _Dot() => true,
    _Word(:final assertion) => !assertion,
    _Raw(:final es, :final assertion) => !assertion && !es.startsWith('(?:'),
    _Seq(:final items) => items.length == 1 && _isSingleChar(items.single),
    _Group(kind: _GroupKind.nonCapture, :final body) => _isSingleChar(body),
    _Alt(:final branches) => branches.every(_isSingleChar),
    _ => false,
  };

  static List<_Char>? _literalChars(_Node node) => switch (node) {
    _Char() => [node],
    _Seq(:final items) => () {
      final chars = <_Char>[];
      for (final item in items) {
        final sub = _literalChars(item);
        if (sub == null) return null;
        chars.addAll(sub);
      }
      return chars.isEmpty ? null : chars;
    }(),
    _Group(kind: _GroupKind.nonCapture, :final body) => _literalChars(body),
    _ => null,
  };

  static bool _sameChar(_Char a, _Char b) => a.ci || b.ci
      ? String.fromCharCode(a.cp).toLowerCase() ==
            String.fromCharCode(b.cp).toLowerCase()
      : a.cp == b.cp;

  _Node _parseEscape(_Flags flags) {
    _i++; // backslash
    if (_atEnd) _fail('trailing backslash');
    final c = _peek;
    _i++;
    switch (c) {
      case 'A':
        _hasA = true;
        return _Marker(aMarker);
      case 'G':
        _gCount++;
        return _Marker(gMarker);
      case 'z':
        // Same rewrite as vscode-textmate: lines carry a trailing "\n".
        return _Raw(r'$(?!\n)(?<!\n)', assertion: true);
      case 'Z':
        return _Raw(r'(?=\n?(?![\s\S]))', assertion: true);
      case 'b':
      case 'B':
      case 'd':
      case 'D':
      case 'w':
      case 'W':
        _usesWords = true;
        return _Word(c);
      case 's':
      case 'S':
        return _Raw('\\$c');
      case 'h':
        return _Raw('[0-9a-fA-F]');
      case 'H':
        return _Raw('[^0-9a-fA-F]');
      case 'R':
        return _Raw(r'(?:\r\n|[\n\v\f\r\u{85}\u{2028}\u{2029}])');
      case 'N':
        return _Raw(r'[^\n]');
      case 'O':
        return _Raw(r'[\s\S]');
      case 'X':
        return _Raw(r'(?:\P{M}\p{M}*)');
      case 'K':
        _hasKeep = true;
        return _Keep();
      case 'p':
      case 'P':
        final (content, negated) = _readProperty(c == 'P');
        return _Raw(_propertyOutsideClass(content, negated));
      case 'k':
        _hasBackrefs = true;
        return _Backref(_readGroupReference(), flags.i);
      case 'g':
        return _Subroutine(_readGroupReference());
      case 'y':
      case 'Y':
        _fail('text segment boundary');
      default:
        if (_isDigit(c)) {
          _i--;
          return _parseNumericEscape(flags);
        }
        _i--;
        return _Char(_readEscapedChar(inClass: false), flags.i);
    }
  }

  _Node _parseNumericEscape(_Flags flags) {
    final m = RegExp(r'\d+').matchAsPrefix(src, _i)!;
    final digits = m.group(0)!;
    final n = int.parse(digits);
    if (digits[0] != '0' && (n <= 9 || n <= _totalGroups)) {
      _i = m.end;
      if (n > _totalGroups) _fail('backreference to missing group $n');
      _hasBackrefs = true;
      return _Backref(n, flags.i);
    }
    return _Char(_readOctal(), flags.i);
  }

  int _readOctal() {
    final m = RegExp(r'[0-7]{1,3}').matchAsPrefix(src, _i);
    if (m == null) {
      // \8 or \9 that is not a backreference: a literal digit.
      return src.codeUnitAt(_i++);
    }
    _i = m.end;
    return int.parse(m.group(0)!, radix: 8);
  }

  int _readGroupReference() {
    if (_atEnd) _fail('bad group reference');
    final open = _peek;
    final close = open == '<' ? '>' : (open == "'" ? "'" : null);
    if (close == null) _fail('bad group reference');
    final end = src.indexOf(close, _i + 1);
    if (end < 0) _fail('unterminated group reference');
    final ref = src.substring(_i + 1, end);
    _i = end + 1;
    final number = int.tryParse(ref);
    if (number != null) {
      // Relative references count from the current group.
      if (ref.startsWith('-')) return _groupCount + 1 + number;
      if (ref.startsWith('+')) return _groupCount + number;
      return number;
    }
    final indices = _names[ref];
    if (indices != null) return indices.last;
    if (prescan) return 0;
    // The name may be defined later in the pattern.
    final later = _groupNames.lastIndexOf(ref);
    if (later < 0) _fail('unknown group name $ref');
    return later + 1;
  }

  /// Reads `\p{…}`, after the `p` or `P` has been consumed.
  (String, bool) _readProperty(bool negated) {
    if (_atEnd || _peek != '{') _fail('bad property');
    final end = src.indexOf('}', _i);
    if (end < 0) _fail('unterminated property');
    var name = src.substring(_i + 1, end);
    _i = end + 1;
    if (name.startsWith('^')) {
      negated = !negated;
      name = name.substring(1);
    }
    return (_propertyContent(name), negated);
  }

  String _propertyContent(String name) {
    final content = unicodePropertyClassContent(name);
    if (content == null) _fail('unknown property $name');
    return content;
  }

  int _readEscapedChar({required bool inClass}) {
    final c = _peek;
    _i++;
    switch (c) {
      case 't':
        return 0x09;
      case 'n':
        return 0x0A;
      case 'r':
        return 0x0D;
      case 'f':
        return 0x0C;
      case 'v':
        return 0x0B;
      case 'a':
        return 0x07;
      case 'e':
        return 0x1B;
      case 'b' when inClass:
        return 0x08;
      case 'x':
        if (!_atEnd && _peek == '{') {
          final end = src.indexOf('}', _i);
          if (end < 0) _fail('bad \\x{}');
          final value = int.tryParse(
            src.substring(_i + 1, end).trim(),
            radix: 16,
          );
          if (value == null || value < 0 || value > 0x10FFFF) {
            _fail('bad \\x{}');
          }
          _i = end + 1;
          return value;
        }
        final m = RegExp(r'[0-9a-fA-F]{1,2}').matchAsPrefix(src, _i);
        if (m == null) return 0x78; // literal x
        _i = m.end;
        return int.parse(m.group(0)!, radix: 16);
      case 'u':
        final m = RegExp(r'[0-9a-fA-F]{4}').matchAsPrefix(src, _i);
        if (m == null) return 0x75; // literal u
        _i = m.end;
        return int.parse(m.group(0)!, radix: 16);
      case 'c':
        if (_atEnd) _fail('bad \\c');
        return src.codeUnitAt(_i++) & 0x1F;
      case '0':
        _i--;
        return _readOctal();
      default:
        if (inClass && _isDigit(c)) {
          _i--;
          return _readOctal();
        }
        _i--;
        return _readCodePoint();
    }
  }

  _ClassSet _parseClass(_Flags flags) {
    var negated = false;
    if (!_atEnd && _peek == '^') {
      negated = true;
      _i++;
    }
    final operands = <List<_ClassItem>>[[]];
    var first = true;
    while (true) {
      if (_atEnd) _fail('unterminated character class');
      final c = _peek;
      final items = operands.last;
      if (c == ']' && !first) {
        _i++;
        break;
      }
      first = false;
      if (c == '[') {
        final posix = _tryPosixBracket();
        if (posix != null) {
          items.add(posix);
          continue;
        }
        _i++;
        items.add(_CNested(_parseClass(flags)));
        continue;
      }
      if (_lookingAt('&&')) {
        _i += 2;
        operands.add([]);
        continue;
      }
      final start = _parseClassAtom();
      if (start is _CChar &&
          _lookingAt('-') &&
          _i + 1 < src.length &&
          src[_i + 1] != ']') {
        final save = _i;
        _i++; // -
        if (_lookingAt('[') || _lookingAt('&&')) {
          _i = save;
          items.add(start);
          continue;
        }
        final end = _parseClassAtom();
        if (end is _CChar) {
          if (end.cp < start.cp) _fail('bad class range');
          items.add(_CRange(start.cp, end.cp));
        } else {
          items
            ..add(start)
            ..add(_CChar(0x2D))
            ..add(end);
        }
        continue;
      }
      items.add(start);
    }
    return _ClassSet(negated, operands);
  }

  _ClassItem? _tryPosixBracket() {
    final m = RegExp(r'\[:(\^?)([a-zA-Z]+):\]').matchAsPrefix(src, _i);
    if (m == null) return null;
    final content = posixClassContent(m.group(2)!);
    if (content == null) return null;
    _i = m.end;
    final item = _CRaw(content);
    return m.group(1)!.isEmpty
        ? item
        : _CNested(
            _ClassSet(true, [
              [item],
            ]),
          );
  }

  _ClassItem _parseClassAtom() {
    if (_peek != r'\') return _CChar(_readCodePoint());
    _i++;
    if (_atEnd) _fail('trailing backslash');
    final c = _peek;
    switch (c) {
      case 'd':
      case 'D':
      case 'w':
      case 'W':
        _i++;
        _usesWords = true;
        return _CWord(c);
      case 's':
      case 'S':
        _i++;
        return _CRaw('\\$c');
      case 'h':
        _i++;
        return _CRaw('0-9a-fA-F');
      case 'H':
        _i++;
        return _CNested(
          _ClassSet(true, [
            [_CRaw('0-9a-fA-F')],
          ]),
        );
      case 'p':
      case 'P':
        _i++;
        final (content, negated) = _readProperty(c == 'P');
        return negated
            ? _CNested(
                _ClassSet(true, [
                  [_CRaw(content)],
                ]),
              )
            : _CRaw(content);
      default:
        return _CChar(_readEscapedChar(inClass: true));
    }
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}
