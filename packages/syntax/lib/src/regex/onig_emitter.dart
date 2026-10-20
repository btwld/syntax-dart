// Emits ECMAScript source for the AST in onig_ast.dart.
part of 'onig_translator.dart';

final class _Emitted {
  _Emitted(this.source, this.textGroups, this.offsetTerms, this.groupCount);
  final String source;
  final Map<int, int> textGroups;
  final Map<int, List<int>> offsetTerms;

  /// Capture groups in [source], hidden ones included.
  final int groupCount;
}

final class _Emitter {
  _Emitter(
    this.ast, {
    required this.indexed,
    this.unicodeWords = false,
    this.groupOffset = 0,
    this.expandCase = false,
  });

  final _Ast ast;
  final bool indexed;

  /// Added to every backreference, for embedding the pattern after
  /// [groupOffset] other groups.
  final int groupOffset;

  /// Expand case-insensitive letters even when the whole pattern is
  /// case-insensitive, because the RegExp flag cannot be used.
  final bool expandCase;

  bool get _globalCi => ast.globalCi && !expandCase;

  /// Emit `\w`, `\b` and `\d` with Oniguruma's Unicode meaning.
  final bool unicodeWords;

  /// Oniguruma's Unicode word characters.
  static const _wordChars = r'\p{L}\p{M}\p{N}\p{Pc}';

  String _wordSource(String kind) {
    if (!unicodeWords) return '\\$kind';
    const w = _wordChars;
    return switch (kind) {
      'w' => '[$w]',
      'W' => '[^$w]',
      'd' => r'\p{Nd}',
      'D' => r'\P{Nd}',
      'b' => '(?:(?<=[$w])(?![$w])|(?<![$w])(?=[$w]))',
      _ => '(?:(?<=[$w])(?=[$w])|(?<![$w])(?![$w]))',
    };
  }

  final StringBuffer _out = StringBuffer();
  int _groups = 0;
  final Map<int, int> _textGroups = {};
  final Map<int, List<int>> _offsetTerms = {};
  int _lookbehindDepth = 0;
  int _expansionDepth = 0;

  // Indexed mode records where each capture group starts, relative to the
  // match start, as a sum of emitted group lengths (see
  // [TranslatedPattern.offsetTerms]). [_base] is that sum for the node
  // being emitted, or null where no capture can take part in a match, as
  // in a negative lookaround. [_backward] is set inside lookbehinds, which
  // match right to left.
  List<int>? _base = const [];
  bool _backward = false;
  final Map<_Node, bool> _captures = Map.identity();

  bool get _tracking => indexed && _expansionDepth == 0 && _base != null;

  Never _fail(String reason) => throw UnsupportedPatternException('', reason);

  _Emitted run() {
    _emitRoot(ast.root);
    final source = _out.toString().replaceAllMapped(
      RegExp('$_backrefOpen(\\d+)$_backrefClose'),
      (m) {
        final emitted = _textGroups[int.parse(m.group(1)!)];
        if (emitted == null) _fail('backreference to missing group');
        return '(?:\\${emitted + groupOffset})';
      },
    );
    return _Emitted(source, _textGroups, _offsetTerms, _groups);
  }

  void _emitRoot(_Node root) {
    // \K is only expressible at the top level of a pattern without
    // alternation: `x\Ky` becomes `(?<=Kx)y`, where the K marker keeps the
    // start of `x` at or after the search start.
    final seq = _flattenSingle(root);
    if (seq is _Seq) {
      final keep = seq.items.lastIndexWhere((n) => n is _Keep);
      if (keep >= 0) {
        if (seq.items.indexWhere((n) => n is _Keep) != keep) {
          _fail('multiple \\K');
        }
        final prefix = _Seq([_Marker(keepMarker), ...seq.items.take(keep)]);
        _emit(
          _Seq([
            _Group(_GroupKind.lookbehind, prefix),
            ...seq.items.skip(keep + 1),
          ]),
        );
        return;
      }
    }
    _emit(root);
  }

  _Node _flattenSingle(_Node n) => switch (n) {
    _Seq(:final items)
        when items.length == 1 &&
            items.single is _Group &&
            (items.single as _Group).kind == _GroupKind.nonCapture =>
      _flattenSingle((items.single as _Group).body),
    _ => n,
  };

  void _emit(_Node node) {
    switch (node) {
      case _Alt(:final branches):
        for (var i = 0; i < branches.length; i++) {
          if (i > 0) _out.write('|');
          _emit(branches[i]);
        }
      case _Seq(:final items):
        if (_tracking) {
          _emitTrackedSeq(items);
        } else {
          for (final item in items) {
            _emit(item);
          }
        }
      case _Char(:final cp, :final ci):
        _out.write(_charSource(cp, ci && !_globalCi));
      case _Dot(:final dotAll):
        _out.write(dotAll ? r'[\s\S]' : r'[^\n]');
      case _Raw(:final es):
        _out.write(es);
      case _Word(:final kind):
        _out.write(_wordSource(kind));
      case _Marker(:final marker):
        _out.write(marker);
      case _Class(:final set, :final ci):
        _out.write(_classSource(set, ci && !_globalCi));
      case _Group():
        _emitGroup(node);
      case _Quant():
        _emitQuant(node);
      case _Backref(:final index):
        _out.write('$_backrefOpen$index$_backrefClose');
      case _Subroutine(:final index):
        _emitSubroutine(index);
      case _Keep():
        _fail('\\K inside a group or alternation');
      case _IsolatedFlags():
        break;
    }
  }

  void _emitGroup(_Group group) {
    switch (group.kind) {
      case _GroupKind.capture:
        if (_expansionDepth > 0) {
          _out.write('(?:');
          _emit(group.body);
          _out.write(')');
          return;
        }
        final index = group.index!;
        if (_tracking) _offsetTerms[index] = _base!;
        _textGroups[index] = ++_groups;
        _out.write('(');
        _emit(group.body);
        _out.write(')');
      case _GroupKind.nonCapture:
        _out.write('(?:');
        _emit(group.body);
        _out.write(')');
      case _GroupKind.lookahead:
        _out.write('(?=');
        _withDirection(backward: false, () => _emit(group.body));
        _out.write(')');
      case _GroupKind.negativeLookahead:
        _out.write('(?!');
        _withoutCaptures(() => _emit(group.body));
        _out.write(')');
      case _GroupKind.lookbehind:
        _out.write('(?<=');
        _lookbehindDepth++;
        if (_tracking && _hasCapture(group.body)) {
          // The body ends where the lookbehind is, so it starts the body's
          // length before it.
          final base = _base!;
          _out.write('(');
          final body = ++_groups;
          _base = [...base, -body];
          _withDirection(backward: true, () => _emit(group.body));
          _base = base;
          _out.write(')');
        } else {
          _withDirection(backward: true, () => _emit(group.body));
        }
        _lookbehindDepth--;
        _out.write(')');
      case _GroupKind.negativeLookbehind:
        _out.write('(?<!');
        _lookbehindDepth++;
        _withoutCaptures(() => _emit(group.body));
        _lookbehindDepth--;
        _out.write(')');
      case _GroupKind.atomic:
        _emitAtomic(() => _emit(group.body));
    }
  }

  /// `(?>x)` becomes `(?=(x))\n`. A lookahead never backtracks into its
  /// match, and the backreference consumes exactly that text. Lookbehinds
  /// run right to left, so atomicity is dropped there.
  void _emitAtomic(void Function() body) {
    if (_lookbehindDepth > 0) {
      _out.write('(?:');
      body();
      _out.write(')');
      return;
    }
    final hidden = ++_groups;
    _out.write('(?=(');
    body();
    _out.write('))(?:\\${hidden + groupOffset})');
  }

  void _emitQuant(_Quant q) {
    if (q.possessive) {
      _emitAtomic(() => _emitQuant(_Quant(q.atom, q.min, q.max)));
      return;
    }
    final max = q.max;
    if (_tracking &&
        !_backward &&
        (max == null || max > 1) &&
        _hasCapture(q.atom)) {
      _emitTrackedQuant(q);
      return;
    }
    // Otherwise any iteration whose captures survive starts where the
    // quantifier does: there is at most one, or iterations run right to
    // left in a lookbehind and the last one is leftmost.
    if (_needsWrapping(q.atom)) {
      _out.write('(?:');
      _emit(q.atom);
      _out.write(')');
    } else {
      _emit(q.atom);
    }
    _writeQuantifier(q);
  }

  void _writeQuantifier(_Quant q) {
    _out.write(switch ((q.min, q.max)) {
      (0, null) => '*',
      (1, null) => '+',
      (0, 1) => '?',
      (final min, null) => '{$min,}',
      (final min, final max?) when min == max => '{$min}',
      (final min, final max?) => '{$min,$max}',
    });
    if (q.lazy) _out.write('?');
  }

  /// A forward quantifier that may repeat a body with captures. ECMAScript
  /// clears those captures at each iteration, so they come from the last
  /// one, which starts at the quantifier's start plus the length of all
  /// iterations minus the length of the last.
  void _emitTrackedQuant(_Quant q) {
    final base = _base!;
    _out.write('(');
    final all = ++_groups;
    final atom = q.atom;
    if (atom is _Group && atom.kind == _GroupKind.capture) {
      // The group's own text is the last iteration.
      _base = [...base, all, -(_groups + 1)];
      _emit(atom);
    } else {
      _out.write('(');
      final last = ++_groups;
      _base = [...base, all, -last];
      _emit(atom);
      _out.write(')');
    }
    _base = base;
    _writeQuantifier(q);
    _out.write(')');
  }

  /// Emits [items] so each item with captures knows where it starts: the
  /// sequence start plus the length of every item before it. Items without
  /// captures between them are measured by one hidden group.
  void _emitTrackedSeq(List<_Node> items) {
    final base = _base!;
    final last = items.lastIndexWhere(_hasCapture);
    var offset = base;
    var runStart = 0;
    for (var i = 0; i <= last; i++) {
      final item = items[i];
      if (!_hasCapture(item)) continue;
      final run = items.sublist(runStart, i);
      if (run.every(_isZeroWidth)) {
        run.forEach(_emit);
      } else {
        _out.write('(');
        final measured = ++_groups;
        run.forEach(_emit);
        _out.write(')');
        offset = [...offset, measured];
      }
      _base = offset;
      if (i < last && !_isZeroWidth(item)) {
        offset = [...offset, _emitMeasured(item)];
      } else {
        _emit(item);
      }
      _base = base;
      runStart = i + 1;
    }
    for (var i = last + 1; i < items.length; i++) {
      _emit(items[i]);
    }
  }

  /// Emits [node] and returns a group whose text is exactly what it
  /// matched.
  int _emitMeasured(_Node node) {
    if (node is _Group && node.kind == _GroupKind.capture ||
        node is _Group &&
            node.kind == _GroupKind.atomic &&
            _lookbehindDepth == 0) {
      // Both open with the group that holds their text.
      final group = _groups + 1;
      _emit(node);
      return group;
    }
    _out.write('(');
    final group = ++_groups;
    _emit(node);
    _out.write(')');
    return group;
  }

  void _withDirection(void Function() emit, {required bool backward}) {
    final outer = _backward;
    _backward = backward;
    emit();
    _backward = outer;
  }

  /// Captures in a negative lookaround never take part in a match.
  void _withoutCaptures(void Function() emit) {
    final base = _base;
    _base = null;
    emit();
    _base = base;
  }

  /// Whether [node] has a capture group that can take part in a match.
  bool _hasCapture(_Node node) => _captures[node] ??= switch (node) {
    _Group(kind: _GroupKind.capture) => true,
    _Group(kind: _GroupKind.negativeLookahead) => false,
    _Group(kind: _GroupKind.negativeLookbehind) => false,
    _Group(:final body) => _hasCapture(body),
    _Seq(:final items) => items.any(_hasCapture),
    _Alt(:final branches) => branches.any(_hasCapture),
    _Quant(:final atom, :final max) => max != 0 && _hasCapture(atom),
    _ => false,
  };

  /// Whether [node] always matches the empty string. False when unsure.
  static bool _isZeroWidth(_Node node) => switch (node) {
    _Marker() || _IsolatedFlags() => true,
    _Raw(:final assertion) => assertion,
    _Word(:final assertion) => assertion,
    _Group(
      kind: _GroupKind.lookahead ||
          _GroupKind.negativeLookahead ||
          _GroupKind.lookbehind ||
          _GroupKind.negativeLookbehind,
    ) =>
      true,
    _Group(:final body) => _isZeroWidth(body),
    _Seq(:final items) => items.every(_isZeroWidth),
    _Alt(:final branches) => branches.every(_isZeroWidth),
    _Quant(:final atom, :final max) => max == 0 || _isZeroWidth(atom),
    _ => false,
  };

  bool _needsWrapping(_Node atom) => switch (atom) {
    _Char() || _Dot() => false,
    _Word() => atom.assertion || unicodeWords,
    _Raw(:final es, :final assertion) => assertion || !_isSingleRaw(es),
    _Group(:final kind) =>
      kind != _GroupKind.capture && kind != _GroupKind.nonCapture,
    _ => true,
  };

  static bool _isSingleRaw(String es) =>
      RegExp(r'^(\\[dDwWsS]|\\[pP]\{[^}]+\}|\[[^\[\]]*\])$').hasMatch(es);

  void _emitSubroutine(int index) {
    if (_expansionDepth >= _subroutineDepthLimit) {
      _out.write('(?!)');
      return;
    }
    final target = index == 0 ? ast.root : ast.groups[index]?.body;
    if (target == null) _fail('subroutine to missing group $index');
    _expansionDepth++;
    _out.write('(?:');
    _emit(target);
    _out.write(')');
    _expansionDepth--;
    // Each level copies the group again, so a body with several calls
    // grows exponentially with depth.
    if (_out.length > _maxExpandedLength) {
      _fail('subroutine expansion too large');
    }
  }

  static const _maxExpandedLength = 100000;

  static const _syntaxChars = r'^$\.*+?()[]{}|/';

  static String _charSource(int cp, bool ci) {
    if (ci) {
      final other = _otherCase(cp);
      if (other != null) {
        return '[${_classChar(cp)}${_classChar(other)}]';
      }
    }
    if (cp < 0x80 && _syntaxChars.contains(String.fromCharCode(cp))) {
      return '\\${String.fromCharCode(cp)}';
    }
    return _printable(cp) ? String.fromCharCode(cp) : _escapeCodePoint(cp);
  }

  static String _classChar(int cp) {
    if (cp < 0x80 && r'\]-^['.contains(String.fromCharCode(cp))) {
      return '\\${String.fromCharCode(cp)}';
    }
    return _printable(cp) ? String.fromCharCode(cp) : _escapeCodePoint(cp);
  }

  static bool _printable(int cp) =>
      cp >= 0x20 &&
      cp != 0x7F &&
      !(cp >= 0x80 && cp <= 0x9F) &&
      !(cp >= 0xD800 && cp <= 0xDFFF) &&
      cp != 0x2028 &&
      cp != 0x2029 &&
      !(cp >= 0xE000 && cp <= 0xF8FF);

  static String _escapeCodePoint(int cp) => '\\u{${cp.toRadixString(16)}}';

  static int? _otherCase(int cp) {
    if (cp > 0xFFFF || cp >= 0xD800 && cp <= 0xDFFF) return null;
    final s = String.fromCharCode(cp);
    final upper = s.toUpperCase();
    final lower = s.toLowerCase();
    if (upper != s && upper.length == 1) return upper.codeUnitAt(0);
    if (lower != s && lower.length == 1) return lower.codeUnitAt(0);
    return null;
  }

  /// ECMAScript for one class set. A flat set becomes `[...]`. Nested
  /// negations and intersections become lookaround compositions that
  /// consume exactly one character.
  String _classSource(_ClassSet set, bool ci) {
    final flat = _flatContent(set, ci);
    if (flat != null) return '[${set.negated ? '^' : ''}$flat]';
    final operands = [for (final op in set.operands) _operandSource(op, ci)];
    final positive = operands.length == 1
        ? operands.single
        : '${operands.take(operands.length - 1).map((o) => '(?=$o)').join()}'
              '${operands.last}';
    return set.negated
        ? r'(?:(?!'
              '$positive'
              r')[\s\S])'
        : '(?:$positive)';
  }

  /// Bracket content when [set] needs no lookarounds, otherwise `null`.
  String? _flatContent(_ClassSet set, bool ci) {
    if (set.operands.length != 1) return null;
    final out = StringBuffer();
    for (final item in set.operands.single) {
      final s = _flatItem(item, ci);
      if (s == null) return null;
      out.write(s);
    }
    return out.toString();
  }

  String? _flatItem(_ClassItem item, bool ci) => switch (item) {
    _CChar(:final cp) =>
      _classChar(cp) +
          (ci && _otherCase(cp) != null ? _classChar(_otherCase(cp)!) : ''),
    _CRange(:final from, :final to) => _rangeSource(from, to, ci),
    _CRaw(:final es) => es,
    _CWord(:final kind) => switch ((kind, unicodeWords)) {
      (_, false) => '\\$kind',
      ('w', true) => _wordChars,
      ('d', true) => r'\p{Nd}',
      ('D', true) => r'\P{Nd}',
      _ => null, // \W: a negated set, handled by _complexItem
    },
    _CNested(:final set) when !set.negated => _flatContent(set, ci),
    _CNested() => null,
  };

  String _rangeSource(int from, int to, bool ci) {
    final base = '${_classChar(from)}-${_classChar(to)}';
    if (!ci) return base;
    if (to - from <= 0x3000 && to > 0x7F) return base + _foldedRange(from, to);
    final extra = StringBuffer();
    // Add the other-case counterpart for the ASCII letter part of a range.
    void addCounterpart(int lo, int hi, int delta) {
      final a = from < lo ? lo : from;
      final b = to > hi ? hi : to;
      if (a <= b) {
        extra.write('${_classChar(a + delta)}-${_classChar(b + delta)}');
      }
    }

    addCounterpart(0x61, 0x7A, -0x20); // a-z -> A-Z
    addCounterpart(0x41, 0x5A, 0x20); // A-Z -> a-z
    return '$base$extra';
  }

  /// Other-case counterparts of a non-ASCII range, as class content.
  static String _foldedRange(int from, int to) {
    final extra = <int>[];
    for (var cp = from; cp <= to; cp++) {
      final other = _otherCase(cp);
      if (other != null && (other < from || other > to)) extra.add(other);
    }
    extra.sort();
    final out = StringBuffer();
    for (var i = 0; i < extra.length; i++) {
      var j = i;
      while (j + 1 < extra.length && extra[j + 1] <= extra[j] + 1) {
        j++;
      }
      out.write(_classChar(extra[i]));
      if (extra[j] != extra[i]) out.write('-${_classChar(extra[j])}');
      i = j;
    }
    return out.toString();
  }

  String _operandSource(List<_ClassItem> items, bool ci) {
    final flat = StringBuffer();
    final complex = <String>[];
    for (final item in items) {
      final s = _flatItem(item, ci);
      if (s != null) {
        flat.write(s);
      } else {
        complex.add(
          item is _CNested ? _classSource(item.set, ci) : '[^$_wordChars]',
        ); // \W in Unicode mode
      }
    }
    final parts = [if (flat.isNotEmpty) '[$flat]', ...complex];
    if (parts.isEmpty) return '(?!)';
    return parts.length == 1 ? parts.single : '(?:${parts.join('|')})';
  }
}
