import 'file_diff.dart';
import 'parse_patch.dart';

/// A recoverable problem in a patch document.
final class PatchDiagnostic {
  /// Describes a malformed or incomplete patch at [line].
  const PatchDiagnostic(this.line, this.message);

  /// One-based transport line within [PatchDocument.source].
  final int line;

  /// Human-readable description of the problem.
  final String message;
}

/// One commit or patch, including its introduction and recoverable problems.
final class PatchDocument {
  /// Keeps the original transport and snapshots the supplied collections.
  PatchDocument({
    required this.introduction,
    required this.source,
    required Iterable<FileDiff> files,
    Iterable<PatchDiagnostic> diagnostics = const [],
  }) : files = List.unmodifiable(files),
       diagnostics = List.unmodifiable(diagnostics);

  /// Exact text preceding the first file header, including mail metadata.
  final String introduction;

  /// Original unmodified text of this document, including line endings.
  final String source;

  /// Files in input order, in an unmodifiable list.
  final List<FileDiff> files;

  /// Recoverable parse problems, in transport order, in an unmodifiable list.
  final List<PatchDiagnostic> diagnostics;
}

final _commitHeader = RegExp(
  r'^(?:From ([0-9a-f]{40,64}) Mon Sep 17 00:00:00 2001|commit ([0-9a-f]{7,64}))\r?$',
  multiLine: true,
  caseSensitive: false,
);

final _hunkHeader = RegExp(
  r'^@@ -(\d{1,9})(?:,(\d{1,9}))? \+(\d{1,9})(?:,(\d{1,9}))? @@ ?(.*)$',
);

/// Parses unified diffs, concatenated `git log -p` commits, or a `git
/// format-patch` mailbox, retaining introductions and original transport.
///
/// Composes [parsePatch]. Files in a commit have IDs prefixed with the commit
/// hash and `:`; files without commit metadata keep [parsePatch]'s IDs. A
/// nonempty preamble before the first commit is its own document. Leading
/// whitespace is kept with the first commit. Empty or whitespace-only input
/// returns an empty list.
///
/// Malformed hunk headers, incomplete file headers and hunk count mismatches
/// become [PatchDiagnostic]s. In [strict] mode the first diagnostic throws a
/// [FormatException] whose source and offset refer to that document. Otherwise
/// recoverable files are returned. The result and document lists are immutable.
List<PatchDocument> parsePatchDocuments(String source, {bool strict = false}) {
  if (source.trim().isEmpty) return const [];
  final commits = _commitHeader.allMatches(source).toList();
  final boundaries = <int>{
    0,
    for (final commit in commits)
      if (commit != commits.first ||
          source.substring(0, commit.start).trim().isNotEmpty)
        commit.start,
    source.length,
  }.toList()..sort();
  final documents = <PatchDocument>[];
  for (var i = 0; i + 1 < boundaries.length; i++) {
    final part = source.substring(boundaries[i], boundaries[i + 1]);
    final lines = part.split('\n');
    // Only normalize a temporary view of transport lines. Keep [part] intact.
    final normalized = [
      for (final line in lines)
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
    final start = normalized.indexWhere(
      (line) => line.startsWith('diff --git ') || line.startsWith('--- '),
    );
    final introduction = start < 0
        ? part
        : lines.take(start).map((line) => '$line\n').join();
    final commit = _commitHeader.firstMatch(introduction);
    final hash = commit?[1] ?? commit?[2];
    final files = [
      for (final file in parsePatch(part))
        hash == null ? file : file.copyWith(identity: '$hash:${file.id}'),
    ];
    final diagnostics = _diagnose(normalized, files);
    if (strict && diagnostics.isNotEmpty) {
      final first = diagnostics.first;
      final offset = lines
          .take(first.line - 1)
          .fold<int>(0, (offset, line) => offset + line.length + 1);
      throw FormatException(first.message, part, offset);
    }
    documents.add(
      PatchDocument(
        introduction: introduction,
        source: part,
        files: files,
        diagnostics: diagnostics,
      ),
    );
  }
  return List.unmodifiable(documents);
}

List<PatchDiagnostic> _diagnose(List<String> lines, List<FileDiff> files) {
  final diagnostics = <PatchDiagnostic>[];
  final hunks = files.expand((file) => file.hunks).iterator;
  final fileHeaders = <int>[];
  var inFile = false;
  var sawHunk = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('diff --git ')) {
      fileHeaders.add(i + 1);
      inFile = true;
      sawHunk = false;
    } else if (line.startsWith('--- ') &&
        i + 1 < lines.length &&
        lines[i + 1].startsWith('+++ ')) {
      if (!inFile || sawHunk) fileHeaders.add(i + 1);
      inFile = true;
      sawHunk = false;
      i++;
    } else if (line.startsWith('--- ')) {
      diagnostics.add(PatchDiagnostic(i + 1, 'No complete file header'));
    } else if (line.startsWith('@@')) {
      if (!inFile) {
        diagnostics.add(PatchDiagnostic(i + 1, 'Hunk has no file header'));
      } else if (!_hunkHeader.hasMatch(line)) {
        diagnostics.add(PatchDiagnostic(i + 1, 'Invalid hunk header'));
      } else if (hunks.moveNext()) {
        sawHunk = true;
        final hunk = hunks.current;
        final oldCount = hunk.lines.where((l) => l.oldNumber != null).length;
        final newCount = hunk.lines.where((l) => l.newNumber != null).length;
        if (oldCount != hunk.oldCount || newCount != hunk.newCount) {
          diagnostics.add(
            PatchDiagnostic(i + 1, 'Hunk counts do not match its content'),
          );
        }
        // Skip consumed content so removed text such as "-- a/path" is not
        // mistaken for another file header. No-newline markers consume a
        // transport line without adding a DiffLine.
        for (var consumed = 0; consumed < hunk.lines.length; consumed++) {
          i++;
          while (i + 1 < lines.length &&
              lines[i + 1] == r'\ No newline at end of file') {
            i++;
          }
        }
      }
    }
  }
  for (var i = 0; i < files.length; i++) {
    if (files[i].oldPath == null && files[i].newPath == null) {
      diagnostics.add(
        PatchDiagnostic(fileHeaders[i], 'No complete file header'),
      );
    }
  }
  diagnostics.sort((a, b) => a.line.compareTo(b.line));
  return diagnostics;
}
