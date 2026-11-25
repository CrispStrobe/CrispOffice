import 'package:quds_tasks_core/quds_tasks_core.dart';

void main() {
  final account = TaskAccountId('fixture', provider: 'portable');
  final list = TaskListId('fixture', account: account);
  final task = RemoteTask(
    id: TaskId('fixture', list: list),
    fields: TaskFields(title: 'Portable', due: TaskDate(2026, 11, 25)),
  );
  final result = reconcileTask(
    snapshot: TaskSyncSnapshot(
      base: task,
      local: task.fields,
      localRevision: 0,
    ),
    remote: task,
    expectedLocalRevision: 0,
  );
  if (result is! TaskSuccess<TaskReconciliation> ||
      result.value.kind != TaskReconciliationKind.unchanged ||
      result.value.needsRemoteWrite) {
    throw StateError('Portable task reconciliation failed.');
  }
}
