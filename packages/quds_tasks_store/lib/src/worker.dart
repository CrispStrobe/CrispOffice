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

/// A recovery implementation must return a failure when it cannot positively
/// establish the outcome. Only an acknowledged delete returns a successful null.
typedef ApplyTaskWrite =
    Future<TaskResult<RemoteTask?>> Function(TaskWriteIntent intent);

/// Pulls before pushing so pending edits reconcile with current remote state.
final class TaskSyncWorker {
  const TaskSyncWorker(this.store);

  final TaskPullStore store;

  Future<TaskResult<bool>> synchronize(
    TaskAccountLease lease,
    TaskListId list, {
    required FetchTaskPage pull,
    required ApplyTaskWrite write,
    required ApplyTaskWrite recover,
    int maxWrites = 20,
  }) async {
    if (maxWrites < 1) {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidInput));
    }
    final retry = store.retryDelay(lease, list);
    if (retry case TaskFailure(:final problem)) return TaskFailure(problem);
    if ((retry as TaskSuccess<Duration?>).value case final delay?) {
      return TaskFailure(
        TaskProblem(TaskProblemCode.throttled, retryAfter: delay),
      );
    }
    final received = await TaskPullWorker(store).refresh(lease, list, pull);
    if (received case TaskFailure(:final problem)) {
      return _defer(lease, list, problem);
    }
    if (!(received as TaskSuccess<bool>).value) return received;
    final deferred = <String>{};
    TaskProblem? unresolved;
    for (var i = 0; i < maxWrites; i++) {
      final position = store.nextWrite(lease, list, excluding: deferred);
      if (position case TaskFailure(:final problem)) {
        return TaskFailure(problem);
      }
      final intent = (position as TaskSuccess<TaskWriteIntent?>).value;
      if (intent == null) {
        return unresolved == null
            ? const TaskSuccess(true)
            : TaskFailure(unresolved);
      }
      final receipt = await (intent.recovery ? recover : write)(intent);
      if (store.finishWrite(lease, intent, receipt) case TaskFailure(
        :final problem,
      )) {
        return TaskFailure(problem);
      }
      if (receipt case TaskFailure(:final problem)) {
        if (problem.code == TaskProblemCode.conflict) {
          deferred.add(intent.localId);
          unresolved ??= problem;
        } else {
          return _defer(lease, list, problem);
        }
      }
    }
    return unresolved == null
        ? const TaskSuccess(false)
        : TaskFailure(unresolved);
  }

  TaskResult<bool> _defer(
    TaskAccountLease lease,
    TaskListId list,
    TaskProblem problem,
  ) => switch (store.deferSync(lease, list, problem)) {
    TaskSuccess() => TaskFailure(problem),
    TaskFailure(problem: final storageProblem) => TaskFailure(storageProblem),
  };
}
