import 'dart:async';
import 'package:syntax/syntax.dart';
import 'package:test/test.dart';

ReviewThread thread(String id, {bool resolved = false}) => ReviewThread(
  id: id,
  resolved: resolved,
  comments: [ReviewComment(id: id, author: 'Reviewer', body: id)],
);

void main() {
  test(
    'anchor index groups threads by file and side with visibility and revision guards',
    () {
      final patch = PatchController([
        diffTexts('one\ntwo', 'one\nnew', id: 'f', path: 'f'),
      ]);
      patch.setAnnotations([
        for (final (id, side, resolved) in [
          ('a', DiffSide.old, false),
          ('b', DiffSide.newer, true),
          ('c', DiffSide.newer, false),
        ])
          ReviewAnnotation(
            id: id,
            fileId: 'f',
            side: side,
            line: 2,
            data: thread(id, resolved: resolved),
          ),
      ]);
      final nav = CommentNavigationController.patch(patch);
      expect(
        nav
            .threadsAtLine('f', 1, side: DiffSide.old)
            .map((t) => t.annotationId),
        ['a'],
      );
      expect(
        nav
            .threadsAtLine('f', 1, side: DiffSide.newer)
            .map((t) => t.annotationId),
        ['b', 'c'],
      );
      expect(nav.threadsAtLine('f', 1), isEmpty);
      expect(
        nav.threadsAtLine('f', 1, side: DiffSide.old, sourceRevision: 42),
        isEmpty,
      );
      nav.filter = CommentThreadFilter.unresolved;
      expect(
        nav
            .threadsAtLine('f', 1, side: DiffSide.newer)
            .map((t) => t.annotationId),
        ['c'],
      );
      expect(
        () => nav.threadsAtLine('f', 1, side: DiffSide.newer).clear(),
        throwsUnsupportedError,
      );
      patch.setAnnotations([]);
      expect(nav.threadsAtLine('f', 1, side: DiffSide.old), isEmpty);
      nav.dispose();
      patch.dispose();
      expect(nav.threadsAtLine('f', 1), isEmpty);
    },
  );

  test(
    'opening and ordinary navigation have distinct focus requests and cancel stale opens',
    () async {
      final gate = Completer<bool>();
      final nav = CommentNavigationController(
        onReveal: (_) => gate.future,
        threads: [
          for (final id in ['a', 'b'])
            CommentThreadLocation(
              fileId: 'f',
              annotationId: id,
              thread: thread(id, resolved: true),
              line: 0,
            ),
        ],
      );
      final first = nav.reveal(nav.threads.first, expandAndFocus: true);
      expect(nav.openTarget!.annotationId, 'a');
      final second = nav.next();
      expect(nav.openTarget, isNull);
      gate.complete(true);
      expect(await first, isFalse);
      expect(await second, isTrue);
      await nav.reveal(nav.threads.first, expandAndFocus: true);
      expect(nav.openTarget!.annotationId, 'a');
      nav.filter = CommentThreadFilter.unresolved;
      expect(nav.openTarget, isNull);
      nav.dispose();
    },
  );
}
