import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:syntax/syntax.dart';

/// Application authorization for the default discussion actions.
/// These controls supplement, and do not replace, server-side authorization.
class CommentThreadPermissions {
  /// Allows all actions by default. Null predicates hide edit/delete actions.
  const CommentThreadPermissions({
    this.reply = true,
    this.resolve = true,
    this.edit = _allow,
    this.delete = _allow,
  });

  static bool _allow(ReviewComment comment) => true;

  /// Whether to offer reply and resolve/reopen commands.
  final bool reply, resolve;

  /// Per-message edit/delete permissions, for example matching an author ID.
  final bool Function(ReviewComment)? edit, delete;
}

/// Application persistence callback returning an authoritative newer revision.
/// Throw to keep the draft open and expose the failure for inline presentation.
typedef ReviewThreadUpdater =
    FutureOr<ReviewThread> Function(ReviewThreadChange change);

/// Retained discussion and draft state shared by mounted inline thread views.
///
/// Own this controller outside virtualized rows and dispose it with the review
/// session. [onUpdate] authorizes and persists changes. Without it, the thread
/// is read-only. [setThread] accepts external updates and invalidates pending
/// results; the application must also check revisions when saving remotely.
class CommentThreadController extends ChangeNotifier {
  /// Creates a session for one stable thread identity.
  CommentThreadController({
    required ReviewThread thread,
    this.onUpdate,
    CommentThreadPermissions permissions = const CommentThreadPermissions(),
  }) : _thread = thread,
       _permissions = permissions;

  ReviewThread _thread;
  CommentThreadPermissions _permissions;
  bool _disposed = false, _busy = false, _replying = false;
  int _generation = 0;
  Object? _error;
  ReviewComment? _editing, _deleting;

  /// Current authoritative thread snapshot.
  ReviewThread get thread => _thread;

  /// Persists changes and returns the same thread ID with a higher revision.
  final ReviewThreadUpdater? onUpdate;

  /// Application-owned permissions, which can change during a session.
  CommentThreadPermissions get permissions => _permissions;
  set permissions(CommentThreadPermissions value) {
    _checkAlive();
    _permissions = value;
    notifyListeners();
  }

  /// Draft controllers retained through folding, scrolling and remounts.
  final replyInput = TextEditingController(),
      editInput = TextEditingController();

  /// Retained focus for the default or application-supplied inputs.
  final replyFocus = FocusNode(), editFocus = FocusNode();

  /// Whether a save, delete or resolution request is pending.
  bool get isSubmitting => _busy;

  /// Last failure. The view supplies a safe default message or a custom builder.
  Object? get error => _error;

  /// Whether the reply input is open.
  bool get isReplying => _replying;

  /// Identity of the message being edited or awaiting inline delete confirmation.
  String? get editingId => _editing?.id;

  /// Snapshot on which the retained edit draft is based, even after deletion.
  ReviewComment? get editingComment => _editing;

  /// Identity of the message awaiting inline delete confirmation.
  String? get deletingId => _deleting?.id;

  /// Whether the application offers reply and resolve/reopen actions.
  bool get mayReply =>
      onUpdate != null && permissions.reply && thread.comments.isNotEmpty;

  /// Whether the application offers resolve/reopen actions.
  bool get mayResolve =>
      onUpdate != null && permissions.resolve && thread.comments.isNotEmpty;

  /// Whether the application offers an edit action for this message.
  bool mayEdit(ReviewComment comment) =>
      onUpdate != null &&
      thread.comment(comment.id) != null &&
      (permissions.edit?.call(comment) ?? false);

  /// Whether the application offers a delete action for this message.
  bool mayDelete(ReviewComment comment) =>
      onUpdate != null &&
      thread.comment(comment.id) != null &&
      (permissions.delete?.call(comment) ?? false);

  bool _sameMessage(ReviewComment? snapshot) {
    if (snapshot == null) return false;
    final current = thread.comment(snapshot.id);
    return current != null &&
        current.body == snapshot.body &&
        current.authorId == snapshot.authorId &&
        current.editedAt == snapshot.editedAt;
  }

  /// A remote edit cannot be overwritten by a draft based on older content.
  bool get editIsStale => _editing != null && !_sameMessage(_editing);

  /// Opens the reply input, preserving a retained draft.
  void startReply() {
    _checkAlive();
    if (_busy || !mayReply) return;
    _replying = true;
    _error = null;
    replyFocus.requestFocus();
    notifyListeners();
  }

  /// Discards a reply draft. Pending submissions cannot be cancelled locally.
  void cancelReply() {
    _checkAlive();
    if (_busy) return;
    _replying = false;
    replyInput.clear();
    _error = null;
    notifyListeners();
  }

  /// Opens an inline editor. Finish the current edit before editing another.
  void startEdit(String id) {
    _checkAlive();
    final comment = thread.comment(id);
    if (_busy ||
        comment == null ||
        !mayEdit(comment) ||
        (_editing != null && _editing!.id != id)) {
      return;
    }
    if (_editing == null) {
      _editing = comment;
      editInput.text = comment.body;
    }
    _error = null;
    editFocus.requestFocus();
    notifyListeners();
  }

  /// Discards the current edit without changing the posted message.
  void cancelEdit() {
    _checkAlive();
    if (_busy) return;
    _editing = null;
    editInput.clear();
    _error = null;
    notifyListeners();
  }

  /// Opens an inline delete confirmation for one message.
  void requestDelete(String id) {
    _checkAlive();
    final comment = thread.comment(id);
    if (_busy || comment == null || !mayDelete(comment)) return;
    _deleting = comment;
    _error = null;
    notifyListeners();
  }

  /// Cancels a pending inline delete confirmation.
  void cancelDelete() {
    _checkAlive();
    if (_busy) return;
    _deleting = null;
    _error = null;
    notifyListeners();
  }

  /// Saves a nonempty reply through the application callback.
  Future<bool> submitReply() async {
    _checkAlive();
    final draft = replyInput.text;
    final text = draft.trim();
    if (_busy || !_replying || !mayReply || text.isEmpty) return false;
    return _submit(ReviewThreadChange.reply(thread, text), () {
      if (replyInput.text == draft) {
        _replying = false;
        replyInput.clear();
      }
    });
  }

  /// Saves an edit only if its original message is still current and permitted.
  Future<bool> submitEdit() async {
    _checkAlive();
    final comment = _editing, draft = editInput.text;
    final text = draft.trim();
    if (_busy ||
        comment == null ||
        text.isEmpty ||
        editIsStale ||
        !mayEdit(thread.comment(comment.id) ?? comment)) {
      return false;
    }
    return _submit(ReviewThreadChange.edit(thread, comment.id, text), () {
      if (editInput.text == draft) {
        _editing = null;
        editInput.clear();
      } else {
        _editing = thread.comment(comment.id);
      }
    });
  }

  /// Deletes the confirmed message only if it has not changed in the meantime.
  /// Deleting the final message returns an empty thread for the app to remove.
  Future<bool> confirmDelete() async {
    _checkAlive();
    final comment = _deleting;
    if (_busy ||
        comment == null ||
        !_sameMessage(comment) ||
        !mayDelete(thread.comment(comment.id) ?? comment)) {
      return false;
    }
    return _submit(ReviewThreadChange.delete(thread, comment.id), () {
      _deleting = null;
      if (_editing?.id == comment.id) {
        _editing = null;
        editInput.clear();
      }
    });
  }

  /// Resolves or reopens without hiding or discarding the messages or drafts.
  Future<bool> toggleResolved() async {
    _checkAlive();
    if (_busy || !mayResolve) return false;
    return _submit(ReviewThreadChange.resolve(thread, !thread.resolved), () {});
  }

  /// Applies a newer external snapshot and invalidates in-flight responses.
  /// Draft text is retained; stale edits stay visible but cannot overwrite it.
  void setThread(ReviewThread value) {
    _checkAlive();
    if (identical(value, thread)) return;
    if (value.id != thread.id || value.revision <= thread.revision) {
      throw ArgumentError('Expected the same thread with a higher revision');
    }
    _generation++;
    _thread = value;
    _busy = false;
    _error = null;
    if (_deleting != null && !_sameMessage(_deleting)) _deleting = null;
    notifyListeners();
  }

  Future<bool> _submit(ReviewThreadChange change, VoidCallback complete) async {
    final generation = ++_generation;
    _busy = true;
    _error = null;
    notifyListeners();
    if (_disposed || generation != _generation) return false;
    try {
      final result = await onUpdate!(change);
      if (_disposed || generation != _generation) return false;
      if (result.id != thread.id || result.revision <= thread.revision) {
        throw StateError('Expected the same thread with a higher revision');
      }
      _thread = result;
      complete();
      _busy = false;
      notifyListeners();
      return true;
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _error = error;
        _busy = false;
        notifyListeners();
      }
      return false;
    }
  }

  void _checkAlive() {
    if (_disposed) throw StateError('The comment thread has been disposed');
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    replyInput.dispose();
    editInput.dispose();
    replyFocus.dispose();
    editFocus.dispose();
    super.dispose();
  }
}
