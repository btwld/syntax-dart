import 'dart:async';
import 'package:syntax/syntax.dart';
import 'package:test/test.dart';

ReviewThread thread(String id, {bool resolved = false}) => ReviewThread(
  id: id,
  resolved: resolved,
  comments: [
    ReviewComment(id: 'root', author: 'Reviewer', body: id),
    const ReviewComment(id: 'reply', author: 'You', body: 'Reply'),
  ],
);
CommentThreadLocation location(
  String file,
  String id, {
  bool resolved = false,
  int line = 0,
  int revision = 0,
}) => CommentThreadLocation(
  fileId: file,
  annotationId: id,
  thread: thread(id, resolved: resolved),
  line: line,
  sourceRevision: revision,
);

void main() {
  test(
    'pointer selection updates the cursor without scrolling and invalidates pending reveals',
    () async {
      final gate = Completer<bool>();
      var cancelled = 0;
      final controller = CommentNavigationController(
        onReveal: (_) => gate.future,
        onCancelReveal: () => cancelled++,
        threads: [location('a', 'one'), location('a', 'two', resolved: true)],
      );
      expect(controller.select('missing', 'one'), isFalse);
      expect(controller.select('a', 'one'), isTrue);
      expect(controller.current?.annotationId, 'one');
      expect(controller.revealTarget, isNull);
      final reveal = controller.next();
      expect(controller.revealTarget?.annotationId, 'two');
      expect(controller.select('a', 'one'), isTrue);
      expect(controller.revealTarget, isNull);
      expect(cancelled, 1);
      gate.complete(true);
      expect(await reveal, isFalse);
      controller.filter = CommentThreadFilter.unresolved;
      expect(controller.select('a', 'two'), isFalse);
      expect(controller.current?.annotationId, 'one');
      controller.dispose();
    },
  );
  test('counts discussions independently of replies and filters', () async {
    final controller = CommentNavigationController(
      onReveal: (_) => true,
      threads: [
        location('a', 'one'),
        location('a', 'two', resolved: true),
        location('b', 'one'),
        CommentThreadLocation(
          fileId: 'a',
          annotationId: 'empty',
          thread: ReviewThread(id: 'empty', comments: []),
          line: 0,
        ),
      ],
    );
    expect(controller.count(), 3);
    expect(controller.count(fileId: 'a', resolved: false), 1);
    expect(controller.count(fileId: 'b', resolved: true), 0);
    controller.filter = CommentThreadFilter.unresolved;
    expect(controller.visible().length, 2);
    expect(controller.count(), 3);
    expect(controller.isVisible('diagnostic'), isTrue);
    expect(controller.isVisible(thread('resolved', resolved: true)), isFalse);
    expect(
      () => controller.setThreads([location('a', 'x'), location('a', 'x')]),
      throwsArgumentError,
    );
    expect(controller.count(), 3);
    expect(
      () => controller.setThreads([location('a', 'x', line: -1)]),
      throwsRangeError,
    );
    expect(() => controller.threads.clear(), throwsUnsupportedError);
    controller.dispose();
  });

  test(
    'navigation wraps in both directions and respects file scope and filters',
    () async {
      final visited = <(String, String)>[];
      final controller = CommentNavigationController(
        onReveal: (entry) {
          visited.add(entry.key);
          return true;
        },
        threads: [
          location('a', 'one'),
          location('a', 'two', resolved: true),
          location('b', 'one'),
        ],
      );
      await controller.previous();
      await controller.next();
      await controller.next();
      expect(visited, [('b', 'one'), ('a', 'one'), ('a', 'two')]);
      controller.filter = CommentThreadFilter.unresolved;
      expect(controller.current, isNull);
      await controller.next(fileId: 'a');
      await controller.next(fileId: 'a');
      expect(visited.last, ('a', 'one'));
      controller.setThreads([location('b', 'one'), location('a', 'one')]);
      expect(controller.current?.key, ('a', 'one'));
      await controller.next();
      expect(controller.current?.key, ('b', 'one'));
      controller.filter = CommentThreadFilter.resolved;
      expect(await controller.next(), isFalse);
      expect(controller.current, isNull);
      controller.dispose();
    },
  );

  test(
    'obsolete reveals and disposal cannot overwrite the latest result',
    () async {
      final pending = <Completer<bool>>[];
      final controller = CommentNavigationController(
        onReveal: (_) {
          final result = Completer<bool>();
          pending.add(result);
          return result.future;
        },
        threads: [location('a', 'one'), location('a', 'two')],
      );
      final first = controller.next();
      final second = controller.next();
      pending[1].complete(true);
      expect(await second, isTrue);
      pending[0].completeError(StateError('old request'));
      expect(await first, isFalse);
      expect(controller.current?.annotationId, 'two');
      expect(controller.error, isNull);
      final moved = controller.next();
      controller.setThreads([
        location('a', 'one', revision: 1),
        location('a', 'two'),
      ]);
      pending[2].complete(true);
      expect(await moved, isFalse);
      expect(controller.current, isNull);
      final filtered = controller.next();
      controller.filter = CommentThreadFilter.resolved;
      pending[3].complete(true);
      expect(await filtered, isFalse);
      controller.filter = CommentThreadFilter.all;
      final disposed = controller.next();
      controller.dispose();
      pending[4].complete(false);
      expect(await disposed, isFalse);
      expect(() => controller.next(), throwsStateError);
    },
  );

  test(
    'patch binding sorts sides and files, unfolds targets and updates counts',
    () async {
      final source = PatchController([
        diffTexts('a\nb\nc', 'a\nchanged\nc', id: 'first', path: 'first.txt'),
        diffTexts('x', 'y', id: 'second', path: 'second.txt'),
      ], foldableHunks: true);
      source.setAnnotations([
        ReviewAnnotation(
          id: 'second',
          fileId: 'second',
          side: DiffSide.newer,
          line: 1,
          data: thread('second'),
        ),
        ReviewAnnotation(
          id: 'new',
          fileId: 'first',
          side: DiffSide.newer,
          line: 2,
          data: thread('new'),
        ),
        ReviewAnnotation(
          id: 'old',
          fileId: 'first',
          side: DiffSide.old,
          line: 2,
          data: thread('old'),
        ),
      ]);
      final controller = CommentNavigationController.patch(source);
      expect(controller.threads.map((entry) => entry.annotationId), [
        'old',
        'new',
        'second',
      ]);
      source.toggleFile('first');
      expect(await controller.next(), isTrue);
      expect(source.isCollapsed('first'), isFalse);
      expect(source.scrollTargetRow, isNotNull);
      source.setAnnotations([
        for (final a in source.annotations)
          ReviewAnnotation(
            id: a.id,
            fileId: a.fileId,
            side: a.side,
            line: a.line,
            data: (a.data! as ReviewThread).copyWith(resolved: true),
          ),
      ]);
      expect(controller.count(resolved: false), 0);
      controller.filter = CommentThreadFilter.unresolved;
      expect(await controller.next(), isFalse);
      source.setFiles([source.files.last]);
      expect(controller.count(), 1);
      controller.dispose();
      source.dispose();
    },
  );

  test(
    'file binding uses the rendered anchor and follows edits and deletions',
    () async {
      final editor = EditorController(
        file: const SourceFile(id: 'a', path: 'a.txt', text: 'one\ntwo\nthree'),
      );
      editor.setAnnotations([
        LineAnnotation(id: 'note', start: 0, end: 7, data: thread('note')),
      ]);
      final controller = CommentNavigationController.file(
        editor,
        annotationLine: (a) => editor.document.positionAt(a.end).line,
      );
      expect(controller.threads.single.line, 1);
      await controller.next();
      expect(editor.revealTarget?.start.line, 1);
      editor.applyEdits([const OffsetEdit(0, 0, 'inserted\n')]);
      expect(controller.current, isNull);
      expect(controller.threads.single.line, 2);
      expect(await controller.next(), isTrue);
      expect(editor.revealTarget?.start.line, 2);
      editor.setAnnotations([]);
      expect(controller.current, isNull);
      expect(controller.count(), 0);
      controller.dispose();
      editor.dispose();
    },
  );

  test(
    'file-list binding tracks retained sessions and reveals folded files',
    () async {
      final files = FileListController([
        const SourceFile(id: 'a', path: 'a.txt', text: 'one\ntwo'),
        const SourceFile(id: 'b', path: 'b.txt', text: 'three'),
      ]);
      final controller = CommentNavigationController.files(files);
      final editor = files.acquire('b');
      editor.setAnnotations([
        LineAnnotation(id: 'note', start: 0, end: 3, data: thread('note')),
      ]);
      expect(controller.count(fileId: 'b', resolved: false), 1);
      files.release('b');
      files.toggle('b');
      expect(await controller.next(), isTrue);
      expect(files.isCollapsed('b'), isFalse);
      expect(files.revealTarget?.$1, 'b');
      files.setFiles([files.files.first]);
      expect(controller.count(), 0);
      controller.dispose();
      files.dispose();
    },
  );

  test('unavailable content reports failure and can be retried', () async {
    var available = false;
    final controller = CommentNavigationController(
      onReveal: (_) => available,
      threads: [location('a', 'one')],
    );
    expect(await controller.next(), isFalse);
    expect(controller.error, isA<StateError>());
    available = true;
    expect(await controller.next(), isTrue);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test(
    'file-list counts drop evicted sessions and tolerate owner disposal',
    () async {
      final files = FileListController([
        const SourceFile(id: 'a', path: 'a', text: 'one'),
      ], sessionLimit: 0);
      final navigation = CommentNavigationController.files(files);
      final editor = files.acquire('a');
      editor.setAnnotations([
        LineAnnotation(id: 'note', start: 0, end: 1, data: thread('note')),
      ]);
      expect(navigation.count(), 1);
      files.release('a');
      await Future<void>.delayed(Duration.zero);
      expect(editor.isDisposed, isTrue);
      expect(navigation.count(), 0);
      files.acquire('a');
      navigation.dispose();
      files.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  for (final interruption in ['none', 'filter', 'source', 'dispose']) {
    test(
      'partial-patch navigation handles $interruption during loading',
      () async {
        const contents = (
          oldText: 'one\ntwo\nthree\n',
          newText: 'one\nchanged\nthree\n',
        );
        final partial = parsePatch(
          renderPatch(
            diffTexts(
              contents.oldText,
              contents.newText,
              path: 'file',
              contextLines: 0,
            ),
          ),
        ).single;
        final gate = Completer<({String oldText, String newText})>();
        final source = PatchController([
          partial,
        ], contentsLoader: (_, _) => gate.future);
        source.setAnnotations([
          ReviewAnnotation(
            id: 'note',
            fileId: partial.id,
            side: DiffSide.newer,
            line: 3,
            data: thread('note'),
          ),
        ]);
        final navigation = CommentNavigationController.patch(source);
        final reveal = navigation.next();
        expect(navigation.isNavigating, isTrue);
        switch (interruption) {
          case 'filter':
            navigation.filter = CommentThreadFilter.resolved;
          case 'source':
            source.updateFile(partial.copyWith(revision: 7));
          case 'dispose':
            navigation.dispose();
        }
        gate.complete(contents);
        expect(await reveal, interruption == 'none');
        expect(
          source.scrollTargetRow,
          interruption == 'none' ? isNotNull : isNull,
        );
        if (interruption == 'none') {
          expect(navigation.current?.annotationId, 'note');
          expect(navigation.current?.sourceRevision, 1);
          expect(navigation.count(resolved: false), 1);
          final request = navigation.revealRequest;
          navigation.filter = CommentThreadFilter.unresolved;
          expect(navigation.revealRequest, request);
        }
        if (!navigation.isDisposed) navigation.dispose();
        source.dispose();
      },
    );
  }
}
