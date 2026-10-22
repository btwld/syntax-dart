import '../edit/text_document.dart';
import '../edit/editor.dart';
import 'diff_texts.dart';
import 'file_diff.dart';
import 'parse_patch.dart';

/// Side of a source comparison.
enum DiffSide {
  /// Original source before changes.
  old,

  /// Updated source after changes.
  newer,
}

/// Source content kept when resolving a change or conflict.
enum ChangeResolution {
  /// Keep the original or current section.
  old,

  /// Keep the updated or incoming section.
  newer,

  /// Keep the original section followed by the updated section.
  both,
}

/// A diagnostic in patch input, using one-based transport line numbers.
final class PatchDiagnostic {
  /// Describes a malformed or incomplete patch at a transport line.
  const PatchDiagnostic(this.line, this.message);

  /// One-based transport line containing the parse problem.
  final int line;

  /// Human-readable description suitable for presentation to the user.
  final String message;
}

/// One commit or patch, including its introduction and recoverable errors.
final class PatchDocument {
  /// Retains a complete patch transport together with parsed files and diagnostics.
  PatchDocument({
    required this.introduction,
    required this.source,
    required Iterable<FileDiff> files,
    Iterable<PatchDiagnostic> diagnostics = const [],
  }) : files = List.unmodifiable(files),
       diagnostics = List.unmodifiable(diagnostics);

  /// Text preceding the first file header, including commit or mail metadata.
  final String introduction;

  /// Original unmodified input text.
  final String source;

  /// Files in display order; identity remains independent of this ordering.
  final List<FileDiff> files;

  /// Diagnostics for the current source revision.
  final List<PatchDiagnostic> diagnostics;
}

/// Parses mailboxes and concatenated commit patches without losing introductions.
List<PatchDocument> parsePatchDocuments(String source, {bool strict = false}) {
  final commits = RegExp(
    r'^(?:From [0-9a-f]{40,64} Mon Sep 17|commit [0-9a-f]{7,64}\s*$)',
    multiLine: true,
  ).allMatches(source).map((m) => m.start).toList();
  final boundaries = <int>{0, ...commits, source.length}.toList()..sort();
  final result = <PatchDocument>[];
  for (var i = 0; i + 1 < boundaries.length; i++) {
    final part = source.substring(boundaries[i], boundaries[i + 1]);
    if (part.trim().isEmpty) continue;
    final start =
        RegExp(
          r'^(?:diff --git |--- )',
          multiLine: true,
        ).firstMatch(part)?.start ??
        part.length;
    final commit = RegExp(
      r'^(?:From|commit) ([0-9a-f]{7,64})',
      multiLine: true,
    ).firstMatch(part)?[1];
    final files = [
      for (final file in parsePatch(part))
        commit == null ? file : file.copyWith(identity: '$commit:${file.id}'),
    ];
    final diagnostics = <PatchDiagnostic>[];
    for (final file in files) {
      for (final hunk in file.hunks) {
        final oldCount = hunk.lines.where((l) => l.oldNumber != null).length;
        final newCount = hunk.lines.where((l) => l.newNumber != null).length;
        if (oldCount != hunk.oldCount || newCount != hunk.newCount) {
          final offset = part.indexOf(hunk.header);
          diagnostics.add(
            PatchDiagnostic(
              offset < 0
                  ? 1
                  : '\n'.allMatches(part.substring(0, offset)).length + 1,
              'Hunk counts do not match its content',
            ),
          );
        }
      }
    }
    final rawLines = part.split('\n');
    for (var line = 0; line < rawLines.length; line++) {
      if (rawLines[line].startsWith('@@') &&
          !RegExp(
            r'^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@',
          ).hasMatch(rawLines[line])) {
        diagnostics.add(PatchDiagnostic(line + 1, 'Invalid hunk header'));
      }
    }
    if (files.isEmpty && start < part.length) {
      diagnostics.add(const PatchDiagnostic(1, 'No complete file header'));
    }
    if (strict && diagnostics.isNotEmpty) {
      throw FormatException(diagnostics.first.message, part);
    }
    result.add(
      PatchDocument(
        introduction: part.substring(0, start),
        source: part,
        files: files,
        diagnostics: diagnostics,
      ),
    );
  }
  return List.unmodifiable(result);
}

/// Serializes a file patch using portable unified/Git headers.
/// Lone-CR logical line terminators cannot be encoded in this line-oriented
/// format and throw rather than silently changing the source to LF.
String renderPatch(FileDiff file) {
  if (file.hunks.any(
    (hunk) => hunk.lines.any(
      (line) => !line.noNewlineAtEnd && line.sourceLineEnding == '\r',
    ),
  )) {
    throw UnsupportedError(
      'Unified patches require LF or CRLF source terminators',
    );
  }
  String path(String? value, String prefix) {
    if (value == null) return '/dev/null';
    final full = '$prefix$value';
    return full.contains(RegExp('[\t\n"\\\\]'))
        ? '"${full.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\t', '\\t').replaceAll('\n', '\\n')}"'
        : full;
  }

  final out = StringBuffer(
    'diff --git ${path(file.oldPath ?? file.newPath, 'a/')} ${path(file.newPath ?? file.oldPath, 'b/')}\n',
  );
  if (file.oldMode != file.newMode &&
      file.kind != FileDiffKind.added &&
      file.kind != FileDiffKind.deleted) {
    if (file.oldMode != null) out.writeln('old mode ${file.oldMode}');
    if (file.newMode != null) out.writeln('new mode ${file.newMode}');
  }
  if (file.kind == FileDiffKind.added) {
    out.writeln('new file mode ${file.newMode ?? '100644'}');
  }
  if (file.kind == FileDiffKind.deleted) {
    out.writeln('deleted file mode ${file.oldMode ?? '100644'}');
  }
  if (file.isRenameOrCopy) {
    final verb = file.kind == FileDiffKind.renamed ? 'rename' : 'copy';
    out.writeln('$verb from ${path(file.oldPath, '')}');
    out.writeln('$verb to ${path(file.newPath, '')}');
  }
  if (file.oldObjectId != null && file.newObjectId != null) {
    out.writeln(
      'index ${file.oldObjectId}..${file.newObjectId}${file.oldMode != null && file.oldMode == file.newMode ? ' ${file.oldMode}' : ''}',
    );
  }
  if (file.isBinary) {
    out.writeln(
      'Binary files ${path(file.oldPath, 'a/')} and ${path(file.newPath, 'b/')} differ',
    );
  } else if (file.hunks.isNotEmpty) {
    out.writeln('--- ${path(file.oldPath, 'a/')}');
    out.writeln('+++ ${path(file.newPath, 'b/')}');
    for (final hunk in file.hunks) {
      out.writeln(hunk.header);
      for (final line in hunk.lines) {
        out.writeln(
          '$line${!line.noNewlineAtEnd && line.sourceLineEnding == '\r\n' ? '\r' : ''}',
        );
        if (line.noNewlineAtEnd) out.writeln(r'\ No newline at end of file');
      }
    }
  }
  return out.toString().replaceAll('\n', file.patchLineEnding);
}

/// Extracts file patches matching either their original or current path.
String extractFilePatch(String patch, String path) => parsePatch(
  patch,
).where((f) => f.path == path || f.oldPath == path).map(renderPatch).join();

/// Keeps at most [contextLines] unchanged lines around every change.
String trimPatchContext(String patch, int contextLines) {
  RangeError.checkNotNegative(contextLines, 'contextLines');
  return parsePatch(patch).map((file) {
    final hunks = <DiffHunk>[];
    for (final hunk in file.hunks) {
      final lines = hunk.lines;
      final keep = <int>{};
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].kind == DiffLineKind.context) continue;
        for (
          var j = (i - contextLines).clamp(0, lines.length);
          j <= (i + contextLines).clamp(0, lines.length - 1);
          j++
        ) {
          keep.add(j);
        }
      }
      final indices = keep.toList()..sort();
      var start = 0;
      while (start < indices.length) {
        var end = start + 1;
        while (end < indices.length && indices[end] == indices[end - 1] + 1) {
          end++;
        }
        final selected = lines.sublist(indices[start], indices[end - 1] + 1);
        final before = lines.take(indices[start]);
        final oldCount = selected.where((l) => l.oldNumber != null).length;
        final newCount = selected.where((l) => l.newNumber != null).length;
        final oldStart =
            hunk.oldStart + before.where((l) => l.oldNumber != null).length;
        final newStart =
            hunk.newStart + before.where((l) => l.newNumber != null).length;
        hunks.add(
          DiffHunk(
            oldStart: oldCount == 0 && hunk.oldCount > 0
                ? oldStart - 1
                : oldStart,
            newStart: newCount == 0 && hunk.newCount > 0
                ? newStart - 1
                : newStart,
            oldCount: oldCount,
            newCount: newCount,
            lines: List.unmodifiable(selected),
            section: hunk.section,
          ),
        );
        start = end;
      }
    }
    return renderPatch(file.copyWith(hunks: List.unmodifiable(hunks)));
  }).join();
}

/// Emits only complete Git file sections; the last file is emitted by [finish].
final class PatchStreamParser {
  String _pending = '';
  String? _commit;
  bool _closed = false;

  List<FileDiff> _parse(String source) => [
    for (final document in parsePatchDocuments(source)) ..._files(document),
  ];

  Iterable<FileDiff> _files(PatchDocument document) {
    final commit = RegExp(
      r'^(?:From|commit) ([0-9a-f]{7,64})',
      multiLine: true,
    ).firstMatch(document.source)?[1];
    if (commit != null) _commit = commit;
    return [
      for (final file in document.files)
        commit != null || _commit == null
            ? file
            : file.copyWith(identity: '$_commit:${file.id}'),
    ];
  }

  /// Appends a transport chunk and returns newly completed file patches.
  List<FileDiff> add(String chunk) {
    if (_closed) throw StateError('Patch stream is closed');
    _pending += chunk;
    final starts = RegExp(
      r'^(?:diff --git [^\n]*\n|From [0-9a-f]{40,64} Mon Sep 17[^\n]*\n|commit [0-9a-f]{7,64}\r?\n)',
      multiLine: true,
    ).allMatches(_pending).toList();
    if (starts.length < 2) return const [];
    final boundary = starts.last.start;
    final files = _parse(_pending.substring(0, boundary));
    _pending = _pending.substring(boundary);
    return files;
  }

  /// Completes delivery and returns the final buffered output.
  List<FileDiff> finish() {
    if (_closed) throw StateError('Patch stream is closed');
    _closed = true;
    final files = _parse(_pending);
    _pending = '';
    return files;
  }

  /// Cancels pending work and releases retained resources; the object must not be reused.
  void dispose() {
    _closed = true;
    _pending = '';
  }
}

/// Verifies loaded source lines before making a partial patch expandable.
FileDiff hydrateDiff(
  FileDiff diff, {
  required String oldText,
  required String newText,
}) {
  final before = TextDocument(oldText);
  final after = TextDocument(newText);
  try {
    for (final hunk in diff.hunks) {
      if (hunk.lines.where((line) => line.oldNumber != null).length !=
              hunk.oldCount ||
          hunk.lines.where((line) => line.newNumber != null).length !=
              hunk.newCount) {
        throw StateError('Cannot hydrate a malformed hunk');
      }
      for (final line in hunk.lines) {
        for (final side in [
          (before, line.oldNumber),
          (after, line.newNumber),
        ]) {
          final (document, number) = side;
          if (number == null) continue;
          if (number < 1 ||
              number > document.lineCount ||
              document.lineText(number - 1) != line.text) {
            throw StateError(
              'Loaded content does not match the patch at line $number',
            );
          }
          final unterminated =
              document.lineStart(number - 1) + line.text.length ==
              document.length;
          if (line.noNewlineAtEnd != unterminated) {
            throw StateError('Loaded content has a different final newline');
          }
          if (!unterminated &&
              document
                      .lineText(number - 1, includeTerminator: true)
                      .substring(line.text.length) !=
                  line.sourceLineEnding) {
            throw StateError(
              'Loaded content has a different source line ending',
            );
          }
        }
      }
    }
    int boundary(TextDocument doc, int line) {
      final sourceLines = doc.length == 0
          ? 0
          : doc.lineCount - (doc.lineText(doc.lineCount - 1).isEmpty ? 1 : 0);
      if (line < 0 || line > sourceLines) {
        throw StateError('Hunk is outside loaded contents');
      }
      return line == sourceLines ? doc.length : doc.lineStart(line);
    }

    var oldEnd = 0, newEnd = 0;
    for (final hunk in diff.hunks) {
      final oldStart = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1;
      final newStart = hunk.newCount == 0 ? hunk.newStart : hunk.newStart - 1;
      if (oldStart < oldEnd ||
          newStart < newEnd ||
          oldText.substring(
                boundary(before, oldEnd),
                boundary(before, oldStart),
              ) !=
              newText.substring(
                boundary(after, newEnd),
                boundary(after, newStart),
              )) {
        throw StateError('Loaded contents contain changes outside the patch');
      }
      oldEnd = oldStart + hunk.oldCount;
      newEnd = newStart + hunk.newCount;
    }
    if (oldText.substring(boundary(before, oldEnd)) !=
        newText.substring(boundary(after, newEnd))) {
      throw StateError('Loaded contents contain changes after the last hunk');
    }
    final complete = diffTexts(oldText, newText, path: diff.path);
    return diff.copyWith(
      oldText: oldText,
      newText: newText,
      oldLines: complete.oldLines,
      newLines: complete.newLines,
      revision: diff.revision + 1,
    );
  } finally {
    before.dispose();
    after.dispose();
  }
}

/// Applies a review decision to a hunk or one contiguous change block.
/// Accept updates the old side; reject updates the new side; both combines
/// removed and added text on both sides, leaving unrelated changes intact.
FileDiff resolveDiffChange(
  FileDiff file,
  int hunkIndex,
  ChangeResolution resolution, {
  int? changeIndex,
}) {
  if (file.oldText == null || file.newText == null) {
    throw StateError('Load full file contents before resolving changes');
  }
  RangeError.checkValidIndex(hunkIndex, file.hunks, 'hunkIndex');
  final hunk = file.hunks[hunkIndex];
  final blocks = <List<DiffLine>>[];
  for (var i = 0; i < hunk.lines.length;) {
    if (hunk.lines[i].kind == DiffLineKind.context) {
      i++;
      continue;
    }
    final start = i;
    while (i < hunk.lines.length &&
        hunk.lines[i].kind != DiffLineKind.context) {
      i++;
    }
    blocks.add(hunk.lines.sublist(start, i));
  }
  if (changeIndex != null) {
    RangeError.checkValidIndex(changeIndex, blocks, 'changeIndex');
  }
  final oldDoc = TextDocument(file.oldText!);
  final newDoc = TextDocument(file.newText!);
  final oldEdits = <OffsetEdit>[];
  final newEdits = <OffsetEdit>[];
  var oldLine = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1;
  var newLine = hunk.newCount == 0 ? hunk.newStart : hunk.newStart - 1;
  var blockIndex = 0;
  for (var i = 0; i < hunk.lines.length;) {
    final line = hunk.lines[i];
    if (line.kind == DiffLineKind.context) {
      oldLine++;
      newLine++;
      i++;
      continue;
    }
    final block = blocks[blockIndex];
    final removed = block.where((l) => l.kind == DiffLineKind.removed).length;
    final added = block.where((l) => l.kind == DiffLineKind.added).length;
    int offset(TextDocument doc, int l) =>
        l >= doc.lineCount ? doc.length : doc.lineStart(l);
    final oldStart = offset(oldDoc, oldLine),
        oldEnd = offset(oldDoc, oldLine + removed);
    final newStart = offset(newDoc, newLine),
        newEnd = offset(newDoc, newLine + added);
    if (changeIndex == null || blockIndex == changeIndex) {
      final old = oldDoc.text.substring(oldStart, oldEnd);
      final newer = newDoc.text.substring(newStart, newEnd);
      final combined =
          '$old${old.isNotEmpty && newer.isNotEmpty && !old.endsWith('\n') && !old.endsWith('\r') ? oldDoc.eol : ''}$newer';
      if (resolution != ChangeResolution.old) {
        oldEdits.add(
          OffsetEdit(
            oldStart,
            oldEnd,
            resolution == ChangeResolution.both ? combined : newer,
          ),
        );
      }
      if (resolution != ChangeResolution.newer) {
        newEdits.add(
          OffsetEdit(
            newStart,
            newEnd,
            resolution == ChangeResolution.both ? combined : old,
          ),
        );
      }
    }
    oldLine += removed;
    newLine += added;
    i += block.length;
    blockIndex++;
  }
  try {
    oldDoc.applyOffsetEdits(oldEdits);
    newDoc.applyOffsetEdits(newEdits);
    final updated = diffTexts(oldDoc.text, newDoc.text, path: file.path);
    return file.copyWith(
      hunks: updated.hunks,
      oldText: updated.oldText,
      newText: updated.newText,
      oldLines: updated.oldLines,
      newLines: updated.newLines,
      revision: file.revision + 1,
    );
  } finally {
    oldDoc.dispose();
    newDoc.dispose();
  }
}

/// Source role within a merge conflict.
enum MergeSectionKind {
  /// Changes from the current branch.
  current,

  /// Optional common ancestor in a three-way conflict.
  base,

  /// Changes from the incoming branch.
  incoming,
}

/// A half-open source range including its leading conflict marker.
final class MergeConflictSection {
  /// Describes one colored section without altering its source text.
  const MergeConflictSection(this.kind, this.start, this.end);

  /// The side represented by this section.
  final MergeSectionKind kind;

  /// UTF-16 source offsets. The incoming section includes the closing marker.
  final int start, end;
}

/// One complete conflict; offsets refer to the original unresolved document.
final class MergeConflict {
  /// Describes one conflict marker range and its exact source sections.
  const MergeConflict({
    required this.start,
    required this.end,
    required this.current,
    required this.incoming,
    this.base,
    this.currentLabel = '',
    this.incomingLabel = '',
    this.sections = const [],
  });

  /// Half-open UTF-16 offsets including the conflict marker lines.
  final int start, end;

  /// Exact current and incoming conflict sections, including their line endings.
  final String current, incoming;

  /// Optional common-ancestor section from a diff3 conflict.
  final String? base;

  /// Labels following the opening and closing conflict markers.
  final String currentLabel, incomingLabel;

  /// Source ranges for current, optional base, and incoming presentation.
  final List<MergeConflictSection> sections;
}

/// Parses ordinary and diff3 markers into source ranges without changing text.
List<MergeConflict> parseMergeConflicts(String text) {
  final doc = TextDocument(text);
  final conflicts = <MergeConflict>[];
  try {
    for (var line = 0; line < doc.lineCount; line++) {
      final open = RegExp(
        r'^(<{7,})(?: (.*))?$',
      ).firstMatch(doc.lineText(line));
      if (open == null) continue;
      final size = open[1]!.length;
      int? base, divider, end;
      for (var j = line + 1; j < doc.lineCount; j++) {
        final current = doc.lineText(j);
        if (current.startsWith('<' * size)) break;
        if (divider == null && current.startsWith('|' * size)) base = j;
        if (divider == null && current == '=' * size) divider = j;
        if (divider != null &&
            RegExp('^>{$size}(?: .*)?\$').hasMatch(current)) {
          end = j;
          break;
        }
      }
      if (divider == null || end == null) continue;
      final after = end + 1 < doc.lineCount
          ? doc.lineStart(end + 1)
          : text.length;
      conflicts.add(
        MergeConflict(
          start: doc.lineStart(line),
          end: after,
          current: text.substring(
            doc.lineStart(line + 1),
            doc.lineStart(base ?? divider),
          ),
          incoming: text.substring(
            doc.lineStart(divider + 1),
            doc.lineStart(end),
          ),
          base: base == null
              ? null
              : text.substring(doc.lineStart(base + 1), doc.lineStart(divider)),
          currentLabel: open[2] ?? '',
          incomingLabel: doc.lineText(end).substring(size).trim(),
          sections: List.unmodifiable([
            MergeConflictSection(
              MergeSectionKind.current,
              doc.lineStart(line),
              doc.lineStart(base ?? divider),
            ),
            if (base != null)
              MergeConflictSection(
                MergeSectionKind.base,
                doc.lineStart(base),
                doc.lineStart(divider),
              ),
            MergeConflictSection(
              MergeSectionKind.incoming,
              doc.lineStart(divider),
              after,
            ),
          ]),
        ),
      );
      line = end;
    }
    return List.unmodifiable(conflicts);
  } finally {
    doc.dispose();
  }
}

/// Maintains the full document while conflicts are resolved in sequence.
final class MergeController extends SyntaxObservable {
  /// Maintains the full document while conflicts are resolved in sequence.
  MergeController(this.file) {
    _parse();
  }

  /// Current source snapshot, including stable identity and document revision.
  SourceFile file;

  /// Remaining conflicts in source order, reparsed after each resolution.
  List<MergeConflict> conflicts = const [];
  List<MergeConflictSection> _sections = const [];
  void _parse() {
    conflicts = parseMergeConflicts(file.text);
    _sections = [for (final conflict in conflicts) ...conflict.sections];
  }

  /// Finds the section at a source offset without scanning offscreen lines.
  MergeConflictSection? sectionAt(int offset) {
    var low = 0, high = _sections.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final section = _sections[mid];
      if (offset < section.start) {
        high = mid;
      } else if (offset >= section.end) {
        low = mid + 1;
      } else {
        return section;
      }
    }
    return null;
  }

  /// Applies a side choice and recomputes the remaining changes.
  void resolve(int index, ChangeResolution resolution) {
    RangeError.checkValidIndex(index, conflicts);
    final conflict = conflicts[index];
    var replacement = switch (resolution) {
      ChangeResolution.old => conflict.current,
      ChangeResolution.newer => conflict.incoming,
      ChangeResolution.both => '${conflict.current}${conflict.incoming}',
    };
    // A final conflict marker without a terminator preserves the file's EOF.
    if (conflict.end == file.text.length &&
        !file.text.endsWith('\n') &&
        !file.text.endsWith('\r')) {
      replacement = replacement.replaceFirst(RegExp(r'(\r\n|\r|\n)$'), '');
    }
    file = file.withText(
      file.text.replaceRange(conflict.start, conflict.end, replacement),
    );
    _parse();
    notifyListeners();
  }
}

/// Loads exact full contents for both sides; callers must honor cancellation.
typedef DiffContentsLoader =
    Future<({String oldText, String newText})> Function(
      FileDiff file,
      CancellationToken cancellation,
    );
