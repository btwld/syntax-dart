import 'dart:convert';

import 'file_diff.dart';

final RegExp _hunkHeader = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$',
);

/// Parses a unified diff, such as the output of `git diff` or `diff -u`,
/// into one [FileDiff] per file.
///
/// Git headers are understood: added, deleted, renamed and copied files,
/// quoted paths, binary files, and `\ No newline at end of file`. Text
/// before the first file, such as a commit message, is ignored. Malformed
/// input never throws; whatever could be read is returned.
///
/// Transport CRLF is distinguished from source CRLF. Display text excludes
/// carriage returns; source terminators remain available for serialization.
List<FileDiff> parsePatch(String patch) {
  final rawLines = patch.split('\n');
  final header = rawLines
      .where(
        (line) => line.startsWith('diff --git ') || line.startsWith('--- '),
      )
      .firstOrNull;
  final transport = header?.endsWith('\r') == true ? '\r\n' : '\n';
  final lines = [
    for (final line in rawLines)
      transport == '\r\n' && line.endsWith('\r')
          ? line.substring(0, line.length - 1)
          : line,
  ];
  // The final line break ends the last line; it doesn't start a blank one.
  if (patch.endsWith('\n')) lines.removeLast();
  final files = <FileDiff>[];
  _FileBuilder? file;

  void finish() {
    if (file != null) {
      files.add(file!.build().copyWith(patchLineEnding: transport));
    }
    file = null;
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('diff --git ')) {
      finish();
      file = _FileBuilder()..readGitPaths(line.substring(11));
      i++;
    } else if (line.startsWith('--- ') &&
        i + 1 < lines.length &&
        lines[i + 1].startsWith('+++ ')) {
      // Plain unified diffs start each file here.
      if (file == null || file!.hunks.isNotEmpty) {
        finish();
        file = _FileBuilder();
      }
      file!
        ..oldPath = _pathField(line.substring(4))
        ..newPath = _pathField(lines[i + 1].substring(4))
        ..sawPathLines = true;
      i += 2;
    } else if (line.startsWith('@@') && file != null) {
      i = _readHunk(lines, i, file!);
    } else if (file != null && file!.hunks.isEmpty) {
      file!.readHeaderLine(line);
      i++;
    } else {
      i++;
    }
  }
  finish();
  return files;
}

/// Reads the hunk starting at [start] and returns the index after it.
int _readHunk(List<String> lines, int start, _FileBuilder file) {
  final m = _hunkHeader.firstMatch(lines[start]);
  // A left-out count means 1. More than 9 digits is no real line number,
  // and would overflow differently on the VM and the web.
  final numbers = [
    for (var group = 1; group <= 4; group++)
      switch (m?.group(group)) {
        null => 1,
        final digits when digits.length > 9 => null,
        final digits => int.parse(digits),
      },
  ];
  if (m == null || numbers.contains(null)) return start + 1;
  final [oldStart!, oldCount!, newStart!, newCount!] = numbers;

  final diffLines = <DiffLine>[];
  var oldNumber = oldStart;
  var newNumber = newStart;
  var oldLeft = oldCount;
  var newLeft = newCount;
  var i = start + 1;
  while (i < lines.length && (oldLeft > 0 || newLeft > 0)) {
    final line = lines[i];
    final marker = line.isEmpty ? ' ' : line[0];
    final rawText = line.isEmpty ? '' : line.substring(1);
    final sourceLineEnding = rawText.endsWith('\r') ? '\r\n' : '\n';
    final text = rawText.endsWith('\r')
        ? rawText.substring(0, rawText.length - 1)
        : rawText;
    if (marker == ' ' && oldLeft > 0 && newLeft > 0) {
      diffLines.add(
        DiffLine(
          DiffLineKind.context,
          text,
          oldNumber: oldNumber++,
          newNumber: newNumber++,
          sourceLineEnding: sourceLineEnding,
        ),
      );
      oldLeft--;
      newLeft--;
    } else if (marker == '-' && oldLeft > 0) {
      diffLines.add(
        DiffLine(
          DiffLineKind.removed,
          text,
          oldNumber: oldNumber++,
          sourceLineEnding: sourceLineEnding,
        ),
      );
      oldLeft--;
    } else if (marker == '+' && newLeft > 0) {
      diffLines.add(
        DiffLine(
          DiffLineKind.added,
          text,
          newNumber: newNumber++,
          sourceLineEnding: sourceLineEnding,
        ),
      );
      newLeft--;
    } else if (line == r'\ No newline at end of file' && diffLines.isNotEmpty) {
      diffLines.add(_withoutNewline(diffLines.removeLast()));
    } else {
      break; // A malformed hunk: keep what was read.
    }
    i++;
  }
  // A "no newline" marker can follow the hunk's last line.
  while (i < lines.length &&
      lines[i] == r'\ No newline at end of file' &&
      diffLines.isNotEmpty) {
    diffLines.add(_withoutNewline(diffLines.removeLast()));
    i++;
  }

  file.hunks.add(
    DiffHunk(
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      section: m.group(5)!.trim(),
      lines: List.unmodifiable(diffLines),
    ),
  );
  return i;
}

DiffLine _withoutNewline(DiffLine line) => DiffLine(
  line.kind,
  line.text,
  oldNumber: line.oldNumber,
  newNumber: line.newNumber,
  noNewlineAtEnd: true,
  sourceLineEnding: line.sourceLineEnding,
);

/// A path from a `---` or `+++` line. Returns `null` for `/dev/null`.
String? _pathField(String field) {
  var path = field;
  final tab = path.indexOf('\t'); // diff -u appends a timestamp
  if (tab >= 0) path = path.substring(0, tab);
  path = _unquote(path.trim());
  if (path == '/dev/null') return null;
  return _stripGitPrefix(path);
}

String _stripGitPrefix(String path) =>
    path.startsWith('a/') || path.startsWith('b/') ? path.substring(2) : path;

/// The two paths of a `diff --git` line, without their `a/` and `b/`
/// prefixes.
(String, String)? _gitHeaderPaths(String rest) {
  if (rest.startsWith('"')) {
    final end = _closingQuote(rest);
    if (end < 0 || end + 2 >= rest.length) return null;
    return (
      _stripGitPrefix(_unquote(rest.substring(0, end + 1))),
      _stripGitPrefix(_unquote(rest.substring(end + 2))),
    );
  }
  // Both sides are usually the same path, which may itself contain " b/",
  // so try splitting in the middle first, as git does.
  if (rest.length.isOdd && rest[rest.length ~/ 2] == ' ') {
    final a = _stripGitPrefix(rest.substring(0, rest.length ~/ 2));
    final b = _stripGitPrefix(rest.substring(rest.length ~/ 2 + 1));
    if (a == b) return (a, b);
  }
  final quoted = rest.indexOf(' "');
  final split = quoted >= 0 && rest.endsWith('"')
      ? quoted
      : rest.lastIndexOf(' b/');
  if (split < 0) return null;
  return (
    _stripGitPrefix(rest.substring(0, split)),
    _stripGitPrefix(_unquote(rest.substring(split + 1))),
  );
}

/// The index of the quote closing the quoted string at the start of [s].
int _closingQuote(String s) {
  for (var i = 1; i < s.length; i++) {
    if (s[i] == r'\') {
      i++;
    } else if (s[i] == '"') {
      return i;
    }
  }
  return -1;
}

final RegExp _octal = RegExp('[0-3][0-7]{2}');

/// Git quotes paths with special characters, `"a/with\ttab.txt"`, and
/// writes non-ASCII paths as octal UTF-8 bytes, `"caf\303\251"`.
String _unquote(String path) {
  if (path.length < 2 || !path.startsWith('"') || !path.endsWith('"')) {
    return path;
  }
  final body = path.substring(1, path.length - 1);
  final out = StringBuffer();
  final bytes = <int>[];
  void flushBytes() {
    if (bytes.isEmpty) return;
    out.write(utf8.decode(bytes, allowMalformed: true));
    bytes.clear();
  }

  var i = 0;
  while (i < body.length) {
    if (body[i] != r'\' || i + 1 == body.length) {
      flushBytes();
      out.write(body[i++]);
      continue;
    }
    final octal = _octal.matchAsPrefix(body, i + 1);
    if (octal != null) {
      bytes.add(int.parse(octal[0]!, radix: 8));
      i += 4;
      continue;
    }
    flushBytes();
    out.write(switch (body[i + 1]) {
      'a' => '\x07',
      'b' => '\b',
      'f' => '\f',
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      'v' => '\v',
      final other => other,
    });
    i += 2;
  }
  flushBytes();
  return out.toString();
}

final class _FileBuilder {
  String? oldPath;
  String? newPath;
  bool added = false;
  bool deleted = false;
  FileDiffKind? moved;
  bool binary = false;
  bool sawPathLines = false;
  final List<DiffHunk> hunks = [];
  String? oldObjectId, newObjectId, oldMode, newMode;

  /// Reads the paths of a `diff --git` line. Rename, copy, `---` and `+++`
  /// lines that follow take precedence.
  void readGitPaths(String rest) {
    if (_gitHeaderPaths(rest) case (final a, final b)) {
      oldPath = a;
      newPath = b;
    }
  }

  void readHeaderLine(String line) {
    if (line.startsWith('index ')) {
      final match = RegExp(
        r'^index ([0-9a-f]+)\.\.([0-9a-f]+)(?: (\d+))?',
      ).firstMatch(line);
      if (match != null) {
        oldObjectId = match[1];
        newObjectId = match[2];
        oldMode ??= match[3];
        newMode ??= match[3];
      }
    } else if (line.startsWith('old mode ')) {
      oldMode = line.substring(9);
    } else if (line.startsWith('new mode ')) {
      newMode = line.substring(9);
    } else if (line.startsWith('new file mode')) {
      newMode = line.substring(14);
      added = true;
    } else if (line.startsWith('deleted file mode')) {
      deleted = true;
      oldMode = line.substring(18);
    } else if (line.startsWith('rename from ')) {
      moved = FileDiffKind.renamed;
      oldPath = _unquote(line.substring(12));
    } else if (line.startsWith('rename to ')) {
      moved = FileDiffKind.renamed;
      newPath = _unquote(line.substring(10));
    } else if (line.startsWith('copy from ')) {
      moved = FileDiffKind.copied;
      oldPath = _unquote(line.substring(10));
    } else if (line.startsWith('copy to ')) {
      moved = FileDiffKind.copied;
      newPath = _unquote(line.substring(8));
    } else if (line.startsWith('Binary files ') ||
        line.startsWith('GIT binary patch')) {
      binary = true;
    }
  }

  FileDiff build() {
    final before = added && !sawPathLines ? null : oldPath;
    final after = deleted && !sawPathLines ? null : newPath;
    final kind = switch ((before, after)) {
      (null, _) => FileDiffKind.added,
      (_, null) => FileDiffKind.deleted,
      _ when added => FileDiffKind.added,
      _ when deleted => FileDiffKind.deleted,
      _ => moved ?? FileDiffKind.modified,
    };
    return FileDiff(
      oldPath: kind == FileDiffKind.added ? null : before,
      newPath: kind == FileDiffKind.deleted ? null : after,
      kind: kind,
      hunks: List.unmodifiable(hunks),
      isBinary: binary,
      oldObjectId: oldObjectId,
      newObjectId: newObjectId,
      oldMode: oldMode,
      newMode: newMode,
    );
  }
}
