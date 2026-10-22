/// An immutable message in an application-owned review discussion.
final class ReviewComment {
  /// Creates a message with a stable identity independent of its list position.
  const ReviewComment({
    required this.id,
    required this.author,
    required this.body,
    this.authorId,
    this.createdAt,
    this.editedAt,
  });

  /// Stable message identity, unique within its thread.
  final String id;

  /// Display name and optional account identity for application permissions.
  final String author;

  /// Optional account identity for application permission checks.
  final String? authorId;

  /// Plain source text; renderers may supply their own rich text presentation.
  final String body;

  /// Optional application timestamps; formatting belongs to the renderer.
  final DateTime? createdAt, editedAt;

  /// Returns edited content while preserving identity, author and creation time.
  ReviewComment edit(String body, {DateTime? editedAt}) => ReviewComment(
    id: id,
    author: author,
    authorId: authorId,
    body: body,
    createdAt: createdAt,
    editedAt: editedAt ?? this.editedAt,
  );
}

/// A revisioned, immutable discussion, attached through an annotation payload.
///
/// An empty message list represents a deleted discussion. Source ranges remain
/// on the containing file/diff annotation and are independent of message edits.
final class ReviewThread {
  /// Copies messages and rejects ambiguous duplicate message identities.
  ReviewThread({
    required this.id,
    required Iterable<ReviewComment> comments,
    this.revision = 0,
    this.resolved = false,
  }) : comments = List.unmodifiable(comments) {
    RangeError.checkNotNegative(revision, 'revision');
    if (this.comments.map((comment) => comment.id).toSet().length !=
        this.comments.length) {
      throw ArgumentError('Message identities must be unique within a thread');
    }
  }

  /// Stable discussion identity, independent of source line or display position.
  final String id;

  /// Monotonically increasing application revision for concurrent updates.
  final int revision;

  /// Whether the discussion has been resolved. Messages remain available.
  final bool resolved;

  /// Messages in chronological display order.
  final List<ReviewComment> comments;

  /// Finds a message by stable identity, including after reordering or deletion.
  ReviewComment? comment(String id) {
    for (final comment in comments) {
      if (comment.id == id) return comment;
    }
    return null;
  }

  /// Creates the next revision, optionally changing messages or resolution.
  /// Pass an explicit higher [revision] when using a server's revision counter.
  ReviewThread copyWith({
    Iterable<ReviewComment>? comments,
    bool? resolved,
    int? revision,
  }) => ReviewThread(
    id: id,
    comments: comments ?? this.comments,
    resolved: resolved ?? this.resolved,
    revision: revision ?? this.revision + 1,
  );
}

/// The application operation requested by a discussion UI.
enum ReviewThreadChangeKind {
  /// Append a new message.
  reply,

  /// Replace a message's body.
  edit,

  /// Remove one message, preserving its replies as independent messages.
  delete,

  /// Resolve or reopen the discussion.
  resolve,
}

/// A proposed change against a specific immutable thread revision.
///
/// Applications authorize and persist the operation, then return the updated
/// thread. Validate [thread.revision] at the persistence boundary as well.
final class ReviewThreadChange {
  /// Requests a new reply with a nonempty body supplied by the renderer.
  const ReviewThreadChange.reply(this.thread, String this.text)
    : kind = ReviewThreadChangeKind.reply,
      commentId = null,
      resolved = null;

  /// Requests editing one existing message.
  const ReviewThreadChange.edit(this.thread, String id, String this.text)
    : kind = ReviewThreadChangeKind.edit,
      commentId = id,
      resolved = null;

  /// Requests deleting one existing message.
  const ReviewThreadChange.delete(this.thread, String id)
    : kind = ReviewThreadChangeKind.delete,
      commentId = id,
      text = null,
      resolved = null;

  /// Requests a resolution state, including reopening a resolved discussion.
  const ReviewThreadChange.resolve(this.thread, bool this.resolved)
    : kind = ReviewThreadChangeKind.resolve,
      text = null,
      commentId = null;

  /// Source snapshot used to reject stale requests.
  final ReviewThread thread;

  /// Operation to authorize and persist.
  final ReviewThreadChangeKind kind;

  /// Target message for edits/deletions; null for thread-wide operations.
  final String? commentId;

  /// Trimmed body for a reply or edit; null for other operations.
  final String? text;

  /// Requested resolution state; only set for a resolve operation.
  final bool? resolved;
}
