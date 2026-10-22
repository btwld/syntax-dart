import 'dart:async';

import 'package:syntax/syntax.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:test/test.dart';

void main() {
  test('unified export rejects unrepresentable lone-CR logical lines', () {
    expect(
      () => renderPatch(diffTexts('a\rb\r', 'a\rB\r')),
      throwsUnsupportedError,
    );
  });
  test(
    'a loading observer shares the request without starting a second load',
    () async {
      final partial = parsePatch(
        renderPatch(diffTexts('a\n', 'b\n', path: 'f')),
      ).single;
      final gate = Completer<({String oldText, String newText})>();
      var calls = 0;
      final review = PatchController(
        [partial],
        contentsLoader: (_, _) {
          calls++;
          return gate.future;
        },
      );
      Future<bool>? observed;
      var requested = false;
      review.addListener(() {
        if (!requested) {
          requested = true;
          observed = review.loadContents(partial.id);
        }
      });
      final first = review.loadContents(partial.id);
      expect(observed, same(first));
      gate.complete((oldText: 'a\n', newText: 'b\n'));
      expect(await observed!, isTrue);
      expect(calls, 1);
      review.dispose();
    },
  );
  test('changed sources clear obsolete object IDs after verified hydration', () {
    final partial = parsePatch(
      'diff --git a/f b/f\nindex abc123..def456 100644\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n+new\n',
    ).single;
    final loaded = hydrateDiff(partial, oldText: 'old\n', newText: 'new\n');
    expect(loaded.oldObjectId, 'abc123');
    expect(loaded.newObjectId, 'def456');
    final resolved = resolveDiffChange(loaded, 0, ChangeResolution.old);
    expect(resolved.oldObjectId, 'abc123');
    expect(resolved.newObjectId, isNull);
    expect(renderPatch(resolved), isNot(contains('def456')));
  });

  test(
    'provisional decoding errors complete and detach a bound producer',
    () async {
      final source = StreamController<Object>(sync: true);
      final stream = StreamDocumentController(
        const SourceFile(id: 's', path: '', text: ''),
      );
      final completion = expectLater(
        stream.bind(source.stream),
        throwsFormatException,
      );
      source.add([0xf0]);
      expect(
        () => stream.replaceProvisional('replacement'),
        throwsFormatException,
      );
      await completion;
      expect(stream.error, isA<FormatException>());
      expect(stream.isComplete, isFalse);
      expect(stream.isCancelled, isTrue);
      expect(source.hasListener, isFalse);
      stream.dispose();
      await source.close();
    },
  );

  test('patch transport and source line endings round trip independently', () {
    final file = diffTexts('one\r\ntwo\r\n', 'one\ntwo\r\n', path: 'f');
    final patch = renderPatch(file);
    expect(patch, contains('-one\r\n+one\n two\r\n'));
    for (final transport in ['\n', '\r\n']) {
      final encoded = patch.replaceAll('\n', transport);
      final parsed = parsePatch(encoded).single;
      expect(parsed.patchLineEnding, transport);
      expect(parsed.hunks.single.lines.map((line) => line.sourceLineEnding), [
        '\r\n',
        '\n',
        '\r\n',
      ]);
      expect(renderPatch(parsed), encoded);
      expect(
        () => hydrateDiff(parsed, oldText: 'one\ntwo\n', newText: 'one\ntwo\n'),
        throwsStateError,
      );
      expect(
        hydrateDiff(
          parsed,
          oldText: file.oldText!,
          newText: file.newText!,
        ).newText,
        file.newText,
      );
    }
  });

  test(
    'streamed commits retain unique file identities at every chunk boundary',
    () {
      final first = 'a' * 40, second = 'b' * 40;
      final source =
          'commit $first\nFirst\n${renderPatch(diffTexts('a\n', 'b\n', path: 'same'))}'
          '${renderPatch(diffTexts('x\n', 'y\n', path: 'other'))}'
          'commit $second\nSecond\n${renderPatch(diffTexts('b\n', 'c\n', path: 'same'))}';
      final expected = parsePatchDocuments(
        source,
      ).expand((document) => document.files).toList();
      for (var split = 0; split <= source.length; split++) {
        final parser = PatchStreamParser();
        final files = [
          ...parser.add(source.substring(0, split)),
          ...parser.add(source.substring(split)),
          ...parser.finish(),
        ];
        expect(
          files.map((file) => file.id),
          expected.map((file) => file.id),
          reason: 'split $split',
        );
        expect(files.map(renderPatch), expected.map(renderPatch));
      }
      final parser = PatchStreamParser();
      final files = [
        for (var i = 0; i < source.length; i++) ...parser.add(source[i]),
        ...parser.finish(),
      ];
      expect(files.map((file) => file.id), expected.map((file) => file.id));
    },
  );

  test(
    'completing or discarding a shared draft keeps other views usable',
    () async {
      final review = PatchController([
        diffTexts('old\n', 'new\n', id: 'f'),
      ], sessionLimit: 0);
      final editor = review.beginEdit('f');
      expect(review.beginEdit('f'), same(editor));
      editor.insertText('one ');
      expect(await review.completeEdit('f'), isTrue);
      review.releaseEdit('f');
      expect(editor.isDisposed, isFalse);
      editor.insertText('two ');
      expect(await review.completeEdit('f'), isTrue);
      expect(review.file('f').newText, 'one two new\n');
      editor.insertText('discarded ');
      review.discardEdit('f');
      expect(editor.isDisposed, isFalse);
      expect(editor.document.text, 'one two new\n');
      expect(editor.canUndo, isFalse);
      review.releaseEdit('f');
      expect(editor.isDisposed, isTrue);
      review.dispose();
    },
  );

  test(
    'shared partial loading lets a concurrent reveal wait for its source',
    () async {
      final full = diffTexts(
        'a\nb\nc\n',
        'a\nB\nc\n',
        id: 'f',
        contextLines: 0,
      );
      final partial = parsePatch(
        renderPatch(full),
      ).single.copyWith(identity: 'f');
      final gate = Completer<({String oldText, String newText})>();
      var loads = 0;
      final review = PatchController(
        [partial],
        contentsLoader: (_, _) {
          loads++;
          return gate.future;
        },
      );
      final loading = review.loadContents('f');
      final reveal = review.revealLine('f', 3);
      gate.complete((oldText: 'a\nb\nc\n', newText: 'a\nB\nc\n'));
      expect(await loading, isTrue);
      expect(await reveal, isNotNull);
      expect(loads, 1);
      review.dispose();
    },
  );

  test('a slow reveal cannot overwrite a newer navigation request', () async {
    final full = diffTexts('a\nb\nc\n', 'a\nB\nc\n', id: 'a', contextLines: 0);
    final partial = parsePatch(
      renderPatch(full),
    ).single.copyWith(identity: 'a');
    final gate = Completer<({String oldText, String newText})>();
    final review = PatchController([
      partial,
      diffTexts('old\n', 'new\n', id: 'b'),
    ], contentsLoader: (_, _) => gate.future);
    final first = review.revealLine('a', 3);
    final second = await review.revealLine('b', 1);
    gate.complete((oldText: 'a\nb\nc\n', newText: 'a\nB\nc\n'));
    expect(await first, isNull);
    // Hydration can change row indexes, but must retain the newer file target.
    expect(review.scrollRequest, 1);
    expect(second, isNotNull);
    expect(review.layout[review.scrollTargetRow!].file, 1);
    review.dispose();
  });

  test('review source copy preserves internal CRLF and CR terminators', () {
    final review = PatchController([
      diffTexts('', 'one\r\ntwo\rthree\n', id: 'f'),
    ]);
    review.select(const DiffSelection('f', DiffSide.newer, 1, 3));
    expect(review.selectedText(), 'one\r\ntwo\rthree');
    review.dispose();
    final partial = PatchController(
      parsePatch(renderPatch(diffTexts('', 'one\r\ntwo\r\n', id: 'f'))),
    );
    partial.select(
      DiffSelection(partial.files.single.id, DiffSide.newer, 1, 2),
    );
    expect(partial.selectedText(), 'one\r\ntwo');
    partial.dispose();
  });

  test(
    'failed UTF-8 completion is not marked successful and chunks cannot reorder',
    () {
      final stream = StreamDocumentController(
        const SourceFile(id: 'f', path: '', text: ''),
      );
      stream.add([0xf0, 0x9f]);
      expect(stream.finish, throwsFormatException);
      expect(stream.isComplete, isFalse);
      expect(stream.isCancelled, isTrue);
      stream.dispose();
      final mixed = StreamDocumentController(
        const SourceFile(id: 'f', path: '', text: ''),
      );
      mixed.add([0xf0, 0x9f]);
      expect(() => mixed.add('out of order'), throwsFormatException);
      expect(mixed.editor.document.text, '');
      mixed.dispose();
    },
  );
  test(
    'adjacent selections remain distinct and surrounding keeps the primary direction',
    () {
      final editor = EditorController(
        file: const SourceFile(id: 'f', path: '', text: 'abcdef'),
      );
      editor.setSelections(const [
        DocumentSelection(6, 3),
        DocumentSelection(0, 3),
      ]);
      editor.insertText('(');
      expect(editor.document.text, '(abc)(def)');
      expect(editor.selections, const [
        DocumentSelection(9, 6),
        DocumentSelection(1, 4),
      ]);
      editor.undo();
      expect(editor.selections, const [
        DocumentSelection(6, 3),
        DocumentSelection(0, 3),
      ]);
      editor.insertText('x');
      expect(editor.document.text, 'xx');
      expect(editor.selections, const [
        DocumentSelection.collapsed(2),
        DocumentSelection.collapsed(1),
      ]);
      editor.dispose();
    },
  );

  test(
    'native insertion locates repeated characters from the primary selection',
    () {
      final editor = EditorController(
        file: const SourceFile(id: 'f', path: '', text: 'aaa aaa'),
      );
      editor.setSelections(const [
        DocumentSelection.collapsed(1),
        DocumentSelection.collapsed(5),
      ]);
      editor.updateFromInput('aaaa aaa', const DocumentSelection.collapsed(2));
      expect(editor.document.text, 'aaaa aaaa');
      expect(editor.selections, const [
        DocumentSelection.collapsed(2),
        DocumentSelection.collapsed(7),
      ]);
      editor.undo();
      expect(editor.document.text, 'aaa aaa');
      editor.dispose();
    },
  );

  test(
    'hydration preserves review marks while changed content clears them',
    () async {
      final original = diffTexts('old\n', 'new\n', id: 'f');
      final file = parsePatch(
        renderPatch(original),
      ).single.copyWith(identity: 'f');
      final review = PatchController([
        file,
      ], contentsLoader: (_, _) async => (oldText: 'old\n', newText: 'new\n'));
      review.setAnnotations([
        const ReviewAnnotation(
          id: 'a',
          fileId: 'f',
          side: DiffSide.newer,
          line: 1,
          data: 'note',
        ),
      ]);
      review.select(const DiffSelection('f', DiffSide.newer, 1, 1));
      expect(await review.loadContents('f'), isTrue);
      expect(review.annotations, hasLength(1));
      expect(review.selection, isNotNull);
      review.updateFile(diffTexts('another\n', 'replacement\n', id: 'f'));
      expect(review.annotations, isEmpty);
      expect(review.selection, isNull);
      review.dispose();
    },
  );

  test(
    'obsolete loaders finish immediately even if the provider ignores cancellation',
    () async {
      final file = parsePatch(
        '--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n+new\n',
      ).single;
      final gate = Completer<({String oldText, String newText})>();
      final review = PatchController([
        file,
      ], contentsLoader: (_, _) => gate.future);
      final loading = review.loadContents(file.id);
      review.setFiles([]);
      expect(await loading.timeout(const Duration(seconds: 1)), isFalse);
      gate.complete((oldText: 'old\n', newText: 'new\n'));
      review.dispose();
    },
  );
  test(
    'clean file sessions refresh and dirty sessions reject obsolete completion',
    () async {
      const initial = SourceFile(id: 'f', path: 'old.dart', text: 'initial');
      final files = FileListController([initial]);
      final editor = files.acquire('f');
      final refreshed = SourceFile(
        id: 'f',
        path: 'new.dart',
        text: 'external',
        revision: 10,
      );
      files.setFiles([refreshed]);
      expect(editor.file.path, 'new.dart');
      expect(editor.document.text, 'external');
      expect(editor.document.revision, greaterThanOrEqualTo(10));
      expect(editor.canUndo, isFalse);
      editor.insertText('draft ');
      files.setFiles([refreshed.withText('newer external')]);
      expect(editor.document.text, 'draft external');
      var offered = false;
      await expectLater(
        files.complete('f', editor, (_) async {
          offered = true;
          return true;
        }),
        throwsStateError,
      );
      expect(offered, isFalse);
      files.dispose();
    },
  );

  test(
    'shared file and review sessions survive one view releasing its claim',
    () {
      final files = FileListController([
        const SourceFile(id: 'f', path: '', text: 'source'),
      ], sessionLimit: 0);
      final a = files.acquire('f');
      expect(files.acquire('f'), same(a));
      files.release('f');
      expect(a.isDisposed, isFalse);
      files.release('f');
      expect(a.isDisposed, isTrue);
      files.dispose();
      final review = PatchController([
        diffTexts('old', 'new', id: 'f'),
      ], sessionLimit: 0);
      final draft = review.beginEdit('f');
      expect(review.beginEdit('f'), same(draft));
      review.releaseEdit('f');
      expect(draft.isDisposed, isFalse);
      review.releaseEdit('f');
      expect(draft.isDisposed, isTrue);
      review.dispose();
    },
  );

  test('removing a revealed file clears its pending navigation', () {
    final files = FileListController([
      const SourceFile(id: 'f', path: '', text: ''),
    ]);
    files.reveal(
      'f',
      const DocumentRange(DocumentPosition(0, 0), DocumentPosition(0, 0)),
    );
    files.setFiles([]);
    expect(files.revealTarget, isNull);
    files.dispose();
  });

  test('hydration rejects missing newline markers and malformed counts', () {
    final file = parsePatch(
      '--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n+new\n',
    ).single;
    expect(
      () => hydrateDiff(file, oldText: 'old', newText: 'new'),
      throwsStateError,
    );
    final malformed = parsePatch(
      '--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n-old\n+new\n',
    ).single;
    expect(
      () => hydrateDiff(malformed, oldText: 'old\n', newText: 'new\n'),
      throwsStateError,
    );
  });

  test(
    'cancelled consumers release running and queued highlight work',
    () async {
      final backend = _ControlledExecutor();
      final pool = HighlightPool(
        executor: backend,
        concurrency: 1,
        queueSize: 1,
      );
      HighlightRequest request(String id) => HighlightRequest(
        file: SourceFile(id: id, path: '', text: id),
        languages: [],
        theme: githubDarkTheme,
      );
      final firstCancel = CancellationToken(),
          queuedCancel = CancellationToken();
      final first = pool.highlight(request('first'), cancellation: firstCancel);
      final firstCheck = expectLater(first, throwsA(isA<OperationCancelled>()));
      final queued = pool.highlight(
        request('queued'),
        cancellation: queuedCancel,
      );
      final queuedCheck = expectLater(
        queued,
        throwsA(isA<OperationCancelled>()),
      );
      queuedCancel.cancel();
      await queuedCheck;
      expect(pool.stats.queued, 0);
      firstCancel.cancel();
      await firstCheck;
      await Future<void>.delayed(Duration.zero);
      expect(backend.tokens.first.isCancelled, isTrue);
      expect(pool.stats.active, 0);
      final fresh = pool.highlight(request('fresh'));
      backend.jobs.last.complete(computeHighlight(request('fresh')));
      expect((await fresh).fileId, 'fresh');
      expect(backend.ids, ['first', 'fresh']);
      pool.dispose();
    },
  );
}

class _ControlledExecutor implements HighlightExecutor {
  final ids = <String>[];
  final tokens = <CancellationToken>[];
  final jobs = <Completer<HighlightResult>>[];
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) {
    ids.add(request.file.id);
    tokens.add(cancellation!);
    final job = Completer<HighlightResult>();
    jobs.add(job);
    return job.future;
  }

  @override
  void dispose() {}
}
