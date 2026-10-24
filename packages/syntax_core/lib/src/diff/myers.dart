// Internal: not exported from package:syntax.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

enum EditKind { equal, insert, delete }

/// One step of an edit script. [oldIndex] is set for [EditKind.equal] and
/// [EditKind.delete], and [newIndex] for [EditKind.equal] and
/// [EditKind.insert].
typedef Edit = ({EditKind kind, int oldIndex, int newIndex});

/// The shortest edit script turning [a] into [b], using Myers' O(ND)
/// algorithm.
///
/// Elements are compared with `==`, so map rich values to ints first for
/// speed. When the two sides differ in more than [maxEdits] places, the
/// differing middle is reported as one delete-then-insert block instead of
/// a minimal script. That bounds time to O((N + M) · maxEdits) and memory
/// to O(maxEdits²), about 4 MB at the default.
List<Edit> myersDiff(List<int> a, List<int> b, {int maxEdits = 1000}) {
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }

  final edits = <Edit>[
    for (var i = 0; i < prefix; i++)
      (kind: EditKind.equal, oldIndex: i, newIndex: i),
  ];
  final middle = _middle(
    a.sublist(prefix, a.length - suffix),
    b.sublist(prefix, b.length - suffix),
    maxEdits,
  );
  for (final e in middle) {
    edits.add((
      kind: e.kind,
      oldIndex: e.oldIndex < 0 ? -1 : e.oldIndex + prefix,
      newIndex: e.newIndex < 0 ? -1 : e.newIndex + prefix,
    ));
  }
  for (var i = 0; i < suffix; i++) {
    edits.add((
      kind: EditKind.equal,
      oldIndex: a.length - suffix + i,
      newIndex: b.length - suffix + i,
    ));
  }
  return edits;
}

List<Edit> _middle(List<int> a, List<int> b, int maxEdits) {
  final n = a.length;
  final m = b.length;
  // The length difference alone is a lower bound on the edits needed.
  if (n == 0 || m == 0 || (n - m).abs() > maxEdits) {
    return _replaceAll(n, m);
  }
  final max = n + m;
  final offset = max + 1;
  final v = Int32List(2 * max + 3);
  // Each step keeps the furthest x per diagonal from the step before, for
  // the diagonals that step could reach: O(D²) memory in total.
  final trace = <Int32List>[];
  for (var d = 0; d <= max; d++) {
    if (d > maxEdits) return _replaceAll(n, m);
    final snapshot = Int32List(2 * d + 1);
    for (var k = -d; k <= d; k++) {
      snapshot[k + d] = v[k + offset];
    }
    trace.add(snapshot);
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])
          ? v[k + 1 + offset]
          : v[k - 1 + offset] + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) return _backtrack(trace, n, m);
    }
  }
  return _replaceAll(n, m);
}

List<Edit> _backtrack(List<Int32List> trace, int n, int m) {
  final reversed = <Edit>[];
  var x = n;
  var y = m;
  for (var d = trace.length - 1; d >= 0; d--) {
    if (d == 0) {
      while (x > 0 && y > 0) {
        reversed.add((kind: EditKind.equal, oldIndex: --x, newIndex: --y));
      }
      break;
    }
    final snapshot = trace[d];
    int at(int k) => snapshot[k + d];
    final k = x - y;
    final prevK = k == -d || (k != d && at(k - 1) < at(k + 1)) ? k + 1 : k - 1;
    final prevX = at(prevK);
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      reversed.add((kind: EditKind.equal, oldIndex: --x, newIndex: --y));
    }
    if (x == prevX) {
      reversed.add((kind: EditKind.insert, oldIndex: -1, newIndex: prevY));
    } else {
      reversed.add((kind: EditKind.delete, oldIndex: prevX, newIndex: -1));
    }
    x = prevX;
    y = prevY;
  }
  return reversed.reversed.toList();
}

List<Edit> _replaceAll(int n, int m) => [
  for (var i = 0; i < n; i++)
    (kind: EditKind.delete, oldIndex: i, newIndex: -1),
  for (var j = 0; j < m; j++)
    (kind: EditKind.insert, oldIndex: -1, newIndex: j),
];
