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
