import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'store.dart';

/// Fetches a page at the supplied persisted position. During a baseline it
/// must enumerate all current tasks across its pages and mark the last page
/// complete, even when the provider cannot supply a durable checkpoint.
typedef FetchTaskPage =
    Future<TaskResult<TaskSyncPage>> Function(TaskPullPosition position);

/// Drives inbound sync. A foreground trigger or the host scheduler can resume
/// a round at any time. Concurrent requests may complete, but only the request
/// holding the current database position can commit.
final class TaskPullWorker {
  const TaskPullWorker(this.store);

  final TaskPullStore store;

  /// Returns true after a complete round or false when more pages are pending.
  /// The caller can persist its own retry schedule based on a provider problem.
  Future<TaskResult<bool>> refresh(
    TaskAccountLease lease,
    TaskListId list,
    FetchTaskPage fetch, {
    int maxPages = 20,
  }) async {
    if (maxPages < 1) {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidInput));
    }
    for (var i = 0; i < maxPages; i++) {
      final TaskPullPosition position;
      switch (store.position(lease, list)) {
        case TaskSuccess(:final value):
          position = value;
        case TaskFailure(:final problem):
          return TaskFailure(problem);
      }
      final fetched = await fetch(position);
      final TaskSyncPage page;
      switch (fetched) {
        case TaskSuccess(:final value):
          page = value;
        case TaskFailure(:final problem):
          if (problem.code != TaskProblemCode.cursorExpired ||
              position.cursor == null) {
            return TaskFailure(problem);
          }
          page = TaskSyncPage(
            list: list,
            upserts: [],
            tombstones: [],
            resetRequired: true,
          );
      }
      if (store.apply(position, page) case TaskFailure(:final problem)) {
        return TaskFailure(problem);
      }
      if (page.complete && !page.resetRequired) return const TaskSuccess(true);
    }
    return const TaskSuccess(false);
  }
}
