// The parsed form of an Oniguruma pattern.
part of 'onig_translator.dart';

sealed class _Node {}

final class _Alt extends _Node {
  _Alt(this.branches);
  final List<_Node> branches;
}

final class _Seq extends _Node {
  _Seq(this.items);
  final List<_Node> items;
}

final class _Char extends _Node {
  _Char(this.cp, this.ci);
  final int cp;
  final bool ci;
}

final class _Dot extends _Node {
  _Dot(this.dotAll);
  final bool dotAll;
}

/// Pre-rendered ECMAScript. [assertion] marks zero-width atoms, which
/// cannot be quantified directly in unicode mode.
final class _Raw extends _Node {
  _Raw(this.es, {this.assertion = false});
  final String es;
  final bool assertion;
}

final class _Marker extends _Node {
  _Marker(this.marker);
  final String marker;
}

final class _Class extends _Node {
  _Class(this.set, this.ci);
  final _ClassSet set;
  final bool ci;
}

enum _GroupKind {
  capture,
  nonCapture,
  lookahead,
  negativeLookahead,
  lookbehind,
  negativeLookbehind,
  atomic,
}

final class _Group extends _Node {
  _Group(this.kind, this.body, {this.index});
  final _GroupKind kind;
  final _Node body;
  final int? index;
}

final class _Quant extends _Node {
  _Quant(
    this.atom,
    this.min,
    this.max, {
    this.lazy = false,
    this.possessive = false,
  });
  final _Node atom;
  final int min;
  final int? max;
  final bool lazy;
  final bool possessive;
}

final class _Backref extends _Node {
  _Backref(this.index, this.ci);
  final int index;
  final bool ci;
}

/// `\w`, `\W`, `\d`, `\D`, `\b` or `\B`, emitted per word mode.
final class _Word extends _Node {
  _Word(this.kind);
  final String kind;
  bool get assertion => kind == 'b' || kind == 'B';
}

final class _Subroutine extends _Node {
  _Subroutine(this.index);
  final int index;
}

final class _Keep extends _Node {}

final class _ClassSet {
  _ClassSet(this.negated, this.operands);
  final bool negated;

  /// Intersected operands (`a&&b`), each the union of its items.
  final List<List<_ClassItem>> operands;
}

sealed class _ClassItem {}

final class _CChar extends _ClassItem {
  _CChar(this.cp);
  final int cp;
}

final class _CRange extends _ClassItem {
  _CRange(this.from, this.to);
  final int from;
  final int to;
}

/// Already-valid ECMAScript class content, such as `\d` or `\p{L}\p{M}`.
final class _CRaw extends _ClassItem {
  _CRaw(this.es);
  final String es;
}

/// `\w`, `\W`, `\d` or `\D` inside a class.
final class _CWord extends _ClassItem {
  _CWord(this.kind);
  final String kind;
}

final class _CNested extends _ClassItem {
  _CNested(this.set);
  final _ClassSet set;
}

final class _Ast {
  _Ast({
    required this.root,
    required this.groupCount,
    required this.groups,
    required this.globalCi,
    required this.hasA,
    required this.hasG,
    required this.leadingG,
    required this.hasKeep,
    required this.hasBackrefs,
    required this.usesWords,
  });
  final _Node root;
  final int groupCount;
  final Map<int, _Group> groups;
  final bool globalCi;
  final bool hasA;
  final bool hasG;
  final bool leadingG;
  final bool hasKeep;
  final bool hasBackrefs;
  final bool usesWords;
}
