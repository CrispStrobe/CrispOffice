import 'model.dart';
import 'patch.dart';
import 'result.dart';

/// An immutable view of a previously bound remote task and its local working
/// copy. Null [local] means an intentional local deletion. New unbound drafts
/// need a create operation and receive their remote identity only on success.
final class TaskSyncSnapshot {
  TaskSyncSnapshot({
    required this.base,
    required this.local,
    required this.localRevision,
  }) {
    if (localRevision < 0 || localRevision > 0x1fffffffffffff) {
      throw ArgumentError(
        'Local revisions must be exact nonnegative integers.',
      );
    }
  }
  final RemoteTask base;
  final TaskFields? local;
  final int localRevision;
}

enum TaskReconciliationKind {
  unchanged,
  acceptRemote,
  pushLocal,
  merged,
  conflict,
  deleteRemote,
  deleted,
}

/// A plan, not a write acknowledgement. Hosts must compare [localRevision]
/// again in their committing transaction. [remote] carries the fresh provider
/// revision/payload to use for conditional writes and later base advancement.
/// Conflicts expose no merged value or executable patch.
final class TaskReconciliation {
  TaskReconciliation._({
    required this.kind,
    required this.remote,
    required this.merged,
    required this.localRevision,
    this.pendingChanges = const TaskPatch(),
    Set<TaskField> conflicts = const {},
    this.deletionConflict = false,
  }) : conflicts = Set.unmodifiable(conflicts);

  final TaskReconciliationKind kind;
  final RemoteTask? remote;
  final TaskFields? merged;
  final TaskPatch pendingChanges;
  final Set<TaskField> conflicts;
  final bool deletionConflict;
  final int localRevision;

  bool get hasConflict => kind == TaskReconciliationKind.conflict;
  bool get needsRemoteWrite =>
      kind == TaskReconciliationKind.deleteRemote || !pendingChanges.isEmpty;
}

/// Field-wise three-way reconciliation. Null [remote] means an authoritative
/// tombstone or explicitly confirmed absence, never a failed/incomplete fetch.
/// The function is pure: it performs no IO, persistence, retries or deletion.
TaskResult<TaskReconciliation> reconcileTask({
  required TaskSyncSnapshot snapshot,
  required RemoteTask? remote,
  required int expectedLocalRevision,
}) {
  if (snapshot.localRevision != expectedLocalRevision) {
    return const TaskFailure(TaskProblem(TaskProblemCode.staleOperation));
  }
  if (remote != null && remote.id != snapshot.base.id) {
    return const TaskFailure(TaskProblem(TaskProblemCode.invalidInput));
  }
  final local = snapshot.local;
  final base = snapshot.base.fields;
  TaskResult<TaskReconciliation> result(
    TaskReconciliationKind kind, {
    TaskFields? merged,
    TaskPatch pending = const TaskPatch(),
    Set<TaskField> conflicts = const {},
    bool deletionConflict = false,
  }) => TaskSuccess(
    TaskReconciliation._(
      kind: kind,
      remote: remote,
      merged: merged,
      localRevision: snapshot.localRevision,
      pendingChanges: pending,
      conflicts: conflicts,
      deletionConflict: deletionConflict,
    ),
  );

  if (remote == null) {
    return local == null || local == base
        ? result(TaskReconciliationKind.deleted)
        : result(TaskReconciliationKind.conflict, deletionConflict: true);
  }
  if (local == null) {
    return remote.fields == base && _sameDeletionBase(snapshot.base, remote)
        ? result(TaskReconciliationKind.deleteRemote)
        : result(TaskReconciliationKind.conflict, deletionConflict: true);
  }

  final conflicts = <TaskField>{};
  T? merge<T extends Object>(TaskField field, T? before, T? ours, T? theirs) {
    if (ours == before) return theirs;
    if (theirs == before || ours == theirs) return ours;
    conflicts.add(field);
    return ours;
  }

  final merged = TaskFields(
    title: merge(
      TaskField.title,
      base.title,
      local.title,
      remote.fields.title,
    )!,
    notes: merge(TaskField.notes, base.notes, local.notes, remote.fields.notes),
    status: merge(
      TaskField.status,
      base.status,
      local.status,
      remote.fields.status,
    )!,
    priority: merge(
      TaskField.priority,
      base.priority,
      local.priority,
      remote.fields.priority,
    )!,
    start: merge(TaskField.start, base.start, local.start, remote.fields.start),
    due: merge(TaskField.due, base.due, local.due, remote.fields.due),
    reminder: merge(
      TaskField.reminder,
      base.reminder,
      local.reminder,
      remote.fields.reminder,
    ),
    completedAt: merge(
      TaskField.completedAt,
      base.completedAt,
      local.completedAt,
      remote.fields.completedAt,
    ),
  );
  if (conflicts.isNotEmpty) {
    return result(TaskReconciliationKind.conflict, conflicts: conflicts);
  }
  final pending = TaskPatch.between(remote.fields, merged);
  final coupledConflicts = _coupledConflicts(merged, pending);
  if (coupledConflicts.isNotEmpty) {
    return result(TaskReconciliationKind.conflict, conflicts: coupledConflicts);
  }
  final kind = pending.isEmpty
      ? (local == base && remote.fields == base
            ? TaskReconciliationKind.unchanged
            : TaskReconciliationKind.acceptRemote)
      : (remote.fields == base
            ? TaskReconciliationKind.pushLocal
            : TaskReconciliationKind.merged);
  return result(kind, merged: merged, pending: pending);
}

/// Independent edits can be individually valid but produce an invalid combined
/// value. Check coupled fields when the proposed patch would change one of
/// them. Unrelated edits do not reinterpret an already observed remote value.
Set<TaskField> _coupledConflicts(TaskFields fields, TaskPatch pending) {
  final conflicts = <TaskField>{};
  if ((pending.status.isChanged || pending.completedAt.isChanged) &&
      fields.completedAt != null &&
      fields.status != TaskStatus.completed) {
    conflicts.addAll({TaskField.status, TaskField.completedAt});
  }
  if (pending.start.isChanged || pending.due.isChanged) {
    final ordering = _compareDates(fields.start, fields.due);
    if (ordering != null && ordering > 0) {
      conflicts.addAll({TaskField.start, TaskField.due});
    }
  }
  return conflicts;
}

/// Compare civil dates or wall times with exactly the same zone identifier.
/// Different value kinds/zones are incomparable without provider/host rules.
int? _compareDates(TaskDateValue? start, TaskDateValue? due) {
  if (start is TaskDate && due is TaskDate) {
    final first = start.year * 10000 + start.month * 100 + start.day;
    final second = due.year * 10000 + due.month * 100 + due.day;
    return first.compareTo(second);
  }
  if (start is TaskDateTime &&
      due is TaskDateTime &&
      start.timeZone == due.timeZone) {
    String comparable(String value) {
      final parts = value.split('.');
      return '${parts.first}.${(parts.length == 1 ? '' : parts[1]).padRight(9, '0')}';
    }

    return comparable(
      start.localDateTime,
    ).compareTo(comparable(due.localDateTime));
  }
  return null;
}

/// A checklist/attachment/unknown-property update must not disappear merely
/// because the common projection stayed equal. A changed revision is treated
/// conservatively even if a partial payload appears identical. When no payload
/// was retained, an unchanged non-null revision is the minimum evidence.
bool _sameDeletionBase(RemoteTask before, RemoteTask after) {
  if (before.revision != after.revision) return false;
  final oldData = before.providerData;
  final newData = after.providerData;
  if (oldData != null && newData != null) {
    return oldData.format == newData.format && oldData.raw == newData.raw;
  }
  return oldData == null && newData == null && before.revision != null;
}
