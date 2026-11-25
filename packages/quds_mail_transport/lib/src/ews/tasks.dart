import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

/// Read-only access to task folders in an Exchange mailbox.
abstract interface class EwsTaskReader {
  Future<TaskResult<List<TaskList>>> taskLists(MailOperationLease lease);

  Future<TaskResult<TaskList>> defaultTaskList(MailOperationLease lease);

  Future<TaskResult<TaskSyncPage>> pullTasks(
    TaskListId list, {
    String? cursor,
    required MailOperationLease lease,
  });
}

abstract interface class EwsTaskProvider implements EwsTaskReader {
  Future<TaskResult<RemoteTask?>> readTask(TaskId id, MailOperationLease lease);

  Future<TaskResult<RemoteTask>> createTask(
    TaskListId list,
    TaskFields fields, {
    required String operationId,
    required MailOperationLease lease,
  });

  Future<TaskResult<RemoteTask>> updateTask(
    TaskId id,
    TaskPatch patch, {
    required String revision,
    required MailOperationLease lease,
  });

  Future<TaskResult<TaskUnit>> deleteTask(
    TaskId id, {
    required String revision,
    required MailOperationLease lease,
  });
}

/// Reads the operation identifier from Exchange's dedicated named property.
bool matchesEwsTaskCreate(RemoteTask task, String operationId) =>
    task.providerData?.format == 'ews-task-operation' &&
    task.providerData?.raw == operationId;

/// Checks the editable fields after Exchange has normalized the wire values.
bool matchesEwsTaskUpdate(RemoteTask task, TaskPatch patch) {
  bool matches<T extends Object>(TaskFieldPatch<T> field, T? value) =>
      !field.isChanged || field.value == value;
  bool dateMatches(TaskFieldPatch<TaskDateValue> change, TaskDateValue? value) {
    if (matches(change, value)) return true;
    if (change.value case TaskDate(:final year, :final month, :final day)) {
      final date = value is TaskDateTime && value.timeZone == 'UTC'
          ? DateTime.tryParse('${value.localDateTime}Z')
          : null;
      return date != null &&
          date.year == year &&
          date.month == month &&
          date.day == day;
    }
    return false;
  }

  final fields = task.fields;
  return matches(patch.title, fields.title) &&
      matches(
        patch.notes,
        fields.notes?.value.isEmpty == true ? null : fields.notes,
      ) &&
      matches(patch.status, fields.status) &&
      matches(patch.priority, fields.priority) &&
      dateMatches(patch.start, fields.start) &&
      dateMatches(patch.due, fields.due) &&
      matches(patch.reminder, fields.reminder) &&
      matches(patch.completedAt, fields.completedAt);
}
