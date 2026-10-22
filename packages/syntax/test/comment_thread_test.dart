import 'package:syntax/syntax.dart';
import 'package:test/test.dart';

void main() {
  const message = ReviewComment(
    id: 'm',
    author: 'Author',
    authorId: 'user',
    body: 'Original',
  );

  test('thread snapshots copy messages and validate identities/revisions', () {
    final source = [message];
    final thread = ReviewThread(id: 't', comments: source);
    source.clear();
    expect(thread.comments, [message]);
    expect(() => thread.comments.clear(), throwsUnsupportedError);
    expect(
      () => ReviewThread(id: 't', comments: [message, message]),
      throwsArgumentError,
    );
    expect(
      () => ReviewThread(id: 't', comments: [], revision: -1),
      throwsRangeError,
    );
    expect(thread.comment('missing'), isNull);
  });

  test('edits and resolution preserve message and thread identity', () {
    final timestamp = DateTime.utc(2026, 1, 1);
    final thread = ReviewThread(id: 't', comments: [message]);
    final edited = message.edit('Updated', editedAt: timestamp);
    final updated = thread.copyWith(comments: [edited], resolved: true);
    expect(updated.id, thread.id);
    expect(updated.revision, 1);
    expect(updated.resolved, isTrue);
    expect(updated.comment('m')!.authorId, 'user');
    expect(updated.comment('m')!.editedAt, timestamp);
    expect(thread.comment('m')!.body, 'Original');
    expect(updated.copyWith(comments: []).comments, isEmpty);
  });

  test(
    'operation requests carry the exact application snapshot and target',
    () {
      final thread = ReviewThread(id: 't', comments: [message], revision: 8);
      final reply = ReviewThreadChange.reply(thread, 'Reply');
      final edit = ReviewThreadChange.edit(thread, 'm', 'Edited');
      final delete = ReviewThreadChange.delete(thread, 'm');
      final resolve = ReviewThreadChange.resolve(thread, true);
      expect(identical(reply.thread, thread), isTrue);
      expect(reply.kind, ReviewThreadChangeKind.reply);
      expect(edit.commentId, 'm');
      expect(edit.text, 'Edited');
      expect(delete.kind, ReviewThreadChangeKind.delete);
      expect(delete.text, isNull);
      expect(resolve.resolved, isTrue);
    },
  );
}
