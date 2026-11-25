import 'dart:convert';

import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_graph/quds_tasks_graph.dart';

import 'store.dart';
import 'worker.dart';

const _conflict = TaskProblem(
  TaskProblemCode.conflict,
  mutationMayHaveOccurred: false,
);
const _permission = TaskProblem(
  TaskProblemCode.permissionDenied,
  mutationMayHaveOccurred: false,
);
const _unresolved = TaskProblem(
  TaskProblemCode.conflict,
  mutationMayHaveOccurred: true,
);

Future<TaskResult<bool>> syncCalDavTasks(
  TaskSyncWorker worker,
  TaskAccountLease lease,
  CalDavTaskProvider provider,
  CalDavTaskList list,
) => worker.synchronize(
  lease,
  list.id,
  pull: (position) => provider.pull(
    list,
    cursor: position.cursor,
    knownRevisions: position.knownRevisions,
  ),
  write: (intent) async {
    switch (intent.kind) {
      case TaskWriteKind.create:
        final time = intent.attemptedAt;
        return provider.create(
          list,
          operationId: intent.operationId,
          fields: intent.fields!,
          timestamp: DateTime.utc(
            time.year,
            time.month,
            time.day,
            time.hour,
            time.minute,
            time.second,
          ),
        );
      case TaskWriteKind.update:
        final base = intent.base!;
        if (base.revision == null) return const TaskFailure(_conflict);
        return provider.update(
          list,
          base.id,
          expectedRevision: base.revision!,
          patch: intent.patch,
        );
      case TaskWriteKind.delete:
        final base = intent.base!;
        if (base.revision == null) return const TaskFailure(_conflict);
        return _deleted(
          await provider.delete(
            list,
            base.id,
            expectedRevision: base.revision!,
          ),
        );
    }
  },
  recover: (intent) async {
    if (intent.kind == TaskWriteKind.create) {
      return switch (await provider.recoverCreate(
        list,
        operationId: intent.operationId,
      )) {
        TaskSuccess(value: final task?) => TaskSuccess(task),
        TaskSuccess() => const TaskFailure(_unresolved),
        TaskFailure(:final problem) => TaskFailure(problem),
      };
    }
    return _recoverExisting(
      intent,
      await provider.read(list, intent.base!.id),
      confirmDeletion: true,
    );
  },
);

/// Graph performs an exact read before each update/delete. The service's
/// conditional write semantics are still unqualified, so there is a read/write
/// race. The host must explicitly enable that behavior for the account.
Future<TaskResult<bool>> syncGraphTasks(
  TaskSyncWorker worker,
  TaskAccountLease lease,
  GraphTaskProvider provider,
  TaskList list, {
  required bool enableWrites,
}) => worker.synchronize(
  lease,
  list.id,
  pull: (position) =>
      provider.pullTaskChanges(list.id, cursor: position.cursor),
  write: (intent) async {
    if (list.readOnly || !enableWrites) return const TaskFailure(_permission);
    if (intent.kind == TaskWriteKind.create) {
      return provider.createTask(
        list.id,
        intent.fields!,
        operationId: intent.operationId,
        localTaskId: intent.localId,
      );
    }
    final base = intent.base!;
    final observed = await provider.getTask(base.id);
    if (observed case TaskFailure(:final problem)) {
      return TaskFailure(
        TaskProblem(
          problem.code,
          retryAfter: problem.retryAfter,
          mutationMayHaveOccurred: false,
        ),
      );
    }
    final current = (observed as TaskSuccess<RemoteTask?>).value;
    if (current == null ||
        current.revision != base.revision ||
        current.fields != base.fields ||
        !_sameData(current.providerData, base.providerData)) {
      return const TaskFailure(_conflict);
    }
    if (intent.kind == TaskWriteKind.update) {
      return provider.updateTask(base.id, intent.patch);
    }
    return _deleted(await provider.deleteTask(base.id));
  },
  recover: (intent) async {
    if (intent.kind != TaskWriteKind.create) {
      final id = intent.base!.id;
      if (intent.kind == TaskWriteKind.delete) {
        // synchronize() already completed a pull; only an authoritative
        // tombstone or complete baseline can remove the cached task.
        final cached = worker.store.cachedTask(id);
        if (cached case TaskFailure(:final problem)) {
          return TaskFailure(problem);
        }
        if ((cached as TaskSuccess<RemoteTask?>).value == null) {
          return const TaskSuccess(null);
        }
        return const TaskFailure(_unresolved);
      }
      final observation = await provider.getTask(id);
      return switch (observation) {
        TaskFailure(:final problem) => TaskFailure(problem),
        TaskSuccess(value: final task?)
            when provider.matchesUpdate(task, intent.patch) =>
          TaskSuccess(task),
        _ => const TaskFailure(_unresolved),
      };
    }
    String? cursor;
    RemoteTask? match;
    for (var i = 0; i < 32; i++) {
      final scanned = await provider.findCreateOperation(
        list.id,
        operationId: intent.operationId,
        localTaskId: intent.localId,
        cursor: cursor,
      );
      if (scanned case TaskFailure(:final problem)) return TaskFailure(problem);
      final page = (scanned as TaskSuccess<GraphTaskCreateRecoveryPage>).value;
      for (final task in page.matches) {
        if (match != null && match.id != task.id) {
          return const TaskFailure(_unresolved);
        }
        match = task;
      }
      if (page.nextCursor == null) {
        return match == null
            ? const TaskFailure(_unresolved)
            : TaskSuccess(match);
      }
      if (cursor == page.nextCursor) break;
      cursor = page.nextCursor;
    }
    return const TaskFailure(_unresolved);
  },
);

bool _sameData(TaskProviderData? a, TaskProviderData? b) {
  if (a?.format != b?.format) return false;
  if (a?.raw == b?.raw) return true;
  if (a == null || b == null) return false;
  final first = jsonDecode(a.raw) as Map<String, Object?>;
  final second = jsonDecode(b.raw) as Map<String, Object?>;
  // GET and delta may attach different metadata and order object keys
  // differently while describing the same provider object.
  first.remove('@odata.context');
  second.remove('@odata.context');
  return _sameJson(first, second);
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    return a.length == b.length &&
        a.entries.every(
          (entry) =>
              b.containsKey(entry.key) && _sameJson(entry.value, b[entry.key]),
        );
  }
  if (a is List<Object?> && b is List<Object?>) {
    return a.length == b.length &&
        a.asMap().entries.every(
          (entry) => _sameJson(entry.value, b[entry.key]),
        );
  }
  return a == b;
}

TaskResult<RemoteTask?> _deleted(TaskResult<TaskUnit> outcome) =>
    switch (outcome) {
      TaskSuccess() => const TaskSuccess(null),
      TaskFailure(:final problem) => TaskFailure(problem),
    };

TaskResult<RemoteTask?> _recoverExisting(
  TaskWriteIntent intent,
  TaskResult<RemoteTask?> observed, {
  required bool confirmDeletion,
}) => switch (observed) {
  TaskFailure(:final problem) => TaskFailure(problem),
  TaskSuccess(value: null)
      when confirmDeletion && intent.kind == TaskWriteKind.delete =>
    const TaskSuccess(null),
  TaskSuccess(value: final task?)
      when intent.kind == TaskWriteKind.update &&
          task.fields == intent.fields =>
    TaskSuccess(task),
  _ => const TaskFailure(_unresolved),
};
