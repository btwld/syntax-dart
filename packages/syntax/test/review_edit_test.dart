import 'dart:async';
import 'dart:math';
import 'package:syntax/syntax.dart';
import 'package:test/test.dart';

void main() {
  test('piece edits reconstruct random text and undo every transaction', () {
    final random = Random(71);
    final document = TextDocument('hello\r\nworld😀\n');
    var expected = document.text;
    final history = <String>[];
    for (var i = 0; i < 300; i++) {
      final start = random.nextInt(expected.length + 1);
      final end = start + random.nextInt(expected.length - start + 1);
      final replacement = ['abc', '', '\r\n', '😀', 'x\ry'][random.nextInt(5)];
      final next = expected.replaceRange(start, end, replacement);
      if (next != expected) history.add(expected);
      document.applyOffsetEdits([OffsetEdit(start, end, replacement)]);
      expected = next;
      expect(document.text, expected);
    }
    for (final previous in history.reversed) {
      expect(document.undo(), isTrue);
      expect(document.text, previous);
    }
    expect(document.canUndo, isFalse);
  });

  test('batch edits are atomic and use pre-edit UTF-16 positions', () {
    final doc = TextDocument('😀abc\r\nnext\rlast\n');
    expect(doc.lineCount, 4);
    expect(doc.offsetAt(const DocumentPosition(1, 2)), 9);
    expect(doc.positionAt(9), const DocumentPosition(1, 2));
    doc.applyOffsetEdits([
      const OffsetEdit(2, 3, 'XY'),
      const OffsetEdit(7, 11, 'N'),
    ]);
    expect(doc.text, '😀XYbc\r\nN\rlast\n');
    final text = doc.text, revision = doc.revision;
    expect(
      () => doc.applyOffsetEdits([
        const OffsetEdit(0, 3, ''),
        const OffsetEdit(2, 4, ''),
      ]),
      throwsArgumentError,
    );
    expect(doc.text, text);
    expect(doc.revision, revision);
    doc.undo();
    expect(doc.text, '😀abc\r\nnext\rlast\n');
    doc.redo();
    expect(doc.text, text);
  });

  test(
    'editor commands preserve selections and annotations through history',
    () {
      final editor = EditorController(
        file: const SourceFile(id: 'a', path: 'a.dart', text: 'one\ntwo\n'),
      );
      editor.setSelections([const DocumentSelection(0, 3)]);
      editor.setAnnotations([
        const LineAnnotation(id: 'note', start: 4, end: 7, data: 'review'),
      ]);
      editor.insertText('(', autoSurround: true);
      expect(editor.document.text, '(one)\ntwo\n');
      expect(editor.selections.single, const DocumentSelection(1, 4));
      expect(editor.annotations.single.start, 6);
      editor.undo();
      expect(editor.document.text, 'one\ntwo\n');
      expect(editor.selections.single, const DocumentSelection(0, 3));
      expect(editor.annotations.single.start, 4);
      editor.redo();
      expect(editor.document.text, '(one)\ntwo\n');
      editor.execute(EditorCommand.toggleComment);
      expect(editor.document.text, '// (one)\ntwo\n');
      editor.execute(EditorCommand.toggleComment);
      expect(editor.document.text, '(one)\ntwo\n');
      expect(editor.matchingBracket(0), 4);
      editor.dispose();
    },
  );

  test('stale proposals never replace newer content', () async {
    final pending = Completer<List<OffsetEdit>>();
    final editor = EditorController(
      file: const SourceFile(id: 'a', path: 'a', text: 'old'),
      proposalProvider: (_) => pending.future,
      proposalDelay: const Duration(days: 1),
    );
    final request = editor.requestProposal();
    editor.applyEdits([const OffsetEdit(0, 3, 'new')]);
    pending.complete([const OffsetEdit(0, 3, 'stale')]);
    await request;
    expect(editor.proposedEdits, isEmpty);
    expect(editor.document.text, 'new');
    editor.dispose();
  });

  test(
    'review decisions preserve unrelated hunks and missing final newline',
    () {
      final before = 'a\nb\nc\nd\ne';
      final after = 'A\nb\nc\nd\nE';
      final diff = diffTexts(before, after, path: 'a', contextLines: 0);
      final accepted = resolveDiffChange(diff, 0, ChangeResolution.newer);
      expect(accepted.oldText, 'A\nb\nc\nd\ne');
      expect(accepted.newText, after);
      final rejected = resolveDiffChange(diff, 1, ChangeResolution.old);
      expect(rejected.newText, 'A\nb\nc\nd\ne');
      expect(rejected.oldText, before);
    },
  );

  test('conflicts resolve sequentially with diff3 bases and CRLF', () {
    const source =
        'before\r\n<<<<<<< local\r\na\r\n||||||| base\r\nb\r\n=======\r\nc\r\n>>>>>>> remote\r\n<<<<<<< local\r\nx\r\n=======\r\ny\r\n>>>>>>> remote';
    final controller = MergeController(
      const SourceFile(id: 'a', path: 'a', text: source),
    );
    expect(controller.conflicts.length, 2);
    expect(controller.conflicts.first.base, 'b\r\n');
    controller.resolve(0, ChangeResolution.both);
    expect(controller.conflicts.length, 1);
    controller.resolve(0, ChangeResolution.newer);
    expect(controller.file.text, 'before\r\na\r\nc\r\ny');
  });

  test('patch metadata, diagnostics, extraction and context roundtrip', () {
    const patch =
        'commit abcdef123\nsubject\n\ndiff --git a/a b/a\nold mode 100644\nnew mode 100755\nindex abc123..def456\n--- a/a\n+++ b/a\n@@ -1,3 +1,3 @@\n before\n-old\n+new\n after\n';
    final parsed = parsePatchDocuments(patch).single;
    expect(parsed.introduction, startsWith('commit abcdef123'));
    expect(parsed.files.single.oldMode, '100644');
    expect(parsed.files.single.newMode, '100755');
    expect(parsed.files.single.oldObjectId, 'abc123');
    final trimmed = parsePatch(trimPatchContext(patch, 0)).single.hunks.single;
    expect(trimmed.oldStart, 2);
    expect(trimmed.oldCount, 1);
    expect(parsePatch(extractFilePatch(patch, 'a')).length, 1);
    expect(
      () =>
          parsePatchDocuments(patch.replaceFirst('-1,3', '-1,9'), strict: true),
      throwsFormatException,
    );
  });

  test(
    'partial hydration validates content and discards stale responses',
    () async {
      final full = diffTexts('a\nb\n', 'a\nc\n', path: 'a');
      final partial = parsePatch(renderPatch(full)).single;
      expect(
        () => hydrateDiff(partial, oldText: 'x\nb\n', newText: 'a\nc\n'),
        throwsStateError,
      );
      final pending = Completer<({String oldText, String newText})>();
      final controller = PatchController([
        partial,
      ], contentsLoader: (_, _) => pending.future);
      final load = controller.loadContents(partial.id);
      controller.updateFile(partial.copyWith(revision: 2));
      pending.complete((oldText: 'a\nb\n', newText: 'a\nc\n'));
      expect(await load, isFalse);
      expect(controller.files.single.isPartial, isTrue);
      controller.dispose();
    },
  );

  test('large expanded context is indexed without allocating every row', () {
    final lines = List.generate(100000, (i) => 'line $i');
    final before = lines.join('\n');
    lines[50000] = 'changed';
    final full = diffTexts(before, lines.join('\n'), path: 'large');
    final layout = DiffLayout([full], mode: DiffMode.split, expandAll: true);
    expect(layout.length, 100001);
    expect(layout.blockCount, lessThan(12));
    expect(layout.rowForLine(0, 70000), 70000);
    expect((layout[70000] as DiffPairRow).right!.text, 'line 69999');
  });

  test('session store does not evict active sessions', () {
    final evicted = <String>[];
    final store = SessionStore<String>(capacity: 1, onEvict: evicted.add);
    store.acquire('a', () => 'a');
    store.acquire('b', () => 'b');
    store.acquire('c', () => 'c');
    store.release('b');
    store.release('c');
    expect(evicted, ['b']);
    expect(store.remove('a'), isFalse);
    expect(store.acquire('a', () => 'new'), 'a');
    store.release('a');
    expect(store.remove('a'), isFalse);
    store.release('a');
    expect(store.remove('a'), isTrue);
  });
}
