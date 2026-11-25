import 'identity.dart';
import 'model.dart';

final class TaskListPage {
  TaskListPage({required List<TaskList> lists, this.nextCursor})
    : lists = List.unmodifiable(lists) {
    _validateCursor(nextCursor);
    if (lists.isNotEmpty &&
        lists.any((list) => list.id.account != lists.first.id.account)) {
      throw ArgumentError('A list page cannot mix accounts.');
    }
  }
  final List<TaskList> lists;
  final String? nextCursor;
}

/// Cursors are opaque and provider scoped. Adapters validate account, origin and
/// collection binding before following them. Persist a page and its checkpoint
/// in one transaction; a partial page never establishes that absent rows died.
final class TaskSyncPage {
  TaskSyncPage({
    required this.list,
    required List<RemoteTask> upserts,
    required List<TaskId> tombstones,
    this.nextCursor,
    this.checkpoint,
    this.resetRequired = false,
  }) : upserts = List.unmodifiable(upserts),
       tombstones = List.unmodifiable(tombstones) {
    _validateContinuation(nextCursor, checkpoint);
    if (upserts.any((task) => task.id.list != list) ||
        tombstones.any((id) => id.list != list)) {
      throw ArgumentError('A task sync page must belong to one exact list.');
    }
  }
  final TaskListId list;
  final List<RemoteTask> upserts;
  final List<TaskId> tombstones;
  final String? nextCursor;
  final String? checkpoint;
  final bool resetRequired;
  bool get complete => nextCursor == null;
}

final class TaskListSyncPage {
  TaskListSyncPage({
    required this.account,
    required List<TaskList> upserts,
    required List<TaskListId> tombstones,
    this.nextCursor,
    this.checkpoint,
    this.resetRequired = false,
  }) : upserts = List.unmodifiable(upserts),
       tombstones = List.unmodifiable(tombstones) {
    _validateContinuation(nextCursor, checkpoint);
    if (upserts.any((list) => list.id.account != account) ||
        tombstones.any((id) => id.account != account)) {
      throw ArgumentError('A list sync page must belong to one exact account.');
    }
  }
  final TaskAccountId account;
  final List<TaskList> upserts;
  final List<TaskListId> tombstones;
  final String? nextCursor;
  final String? checkpoint;
  final bool resetRequired;
  bool get complete => nextCursor == null;
}

void _validateCursor(String? value) {
  if (value != null && (value.isEmpty || value.length > 131072)) {
    throw ArgumentError('Task cursors must be bounded and nonempty.');
  }
}

void _validateContinuation(String? nextCursor, String? checkpoint) {
  _validateCursor(nextCursor);
  _validateCursor(checkpoint);
  if (nextCursor != null && checkpoint != null) {
    throw ArgumentError('A page cannot be both continuing and checkpointed.');
  }
}
