import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';

Future<TaskResult<bool>> syncStudioEwsTasks(
  TaskSyncWorker worker,
  TaskAccountLease lease,
  EwsTaskProvider provider,
  TaskList list,
  MailAccountSession session,
) => worker.synchronize(
  lease,
  list.id,
  pull: (position) => provider.pullTasks(
    list.id,
    cursor: position.cursor,
    lease: session.begin(),
  ),
  write: (intent) async {
    switch (intent.kind) {
      case TaskWriteKind.create:
        return provider.createTask(
          list.id,
          intent.fields!,
          operationId: intent.operationId,
          lease: session.begin(),
        );
      case TaskWriteKind.update:
        final base = intent.base!;
        if (base.revision == null) return const TaskFailure(_missingRevision);
        return provider.updateTask(
          base.id,
          intent.patch,
          revision: base.revision!,
          lease: session.begin(),
        );
      case TaskWriteKind.delete:
        final base = intent.base!;
        if (base.revision == null) return const TaskFailure(_missingRevision);
        return switch (await provider.deleteTask(
          base.id,
          revision: base.revision!,
          lease: session.begin(),
        )) {
          TaskSuccess() => const TaskSuccess(null),
          TaskFailure(:final problem) => TaskFailure(problem),
        };
    }
  },
  recover: (intent) async {
    if (intent.kind == TaskWriteKind.create) {
      final result = worker.store.tasks(list.id);
      return switch (result) {
        TaskFailure(:final problem) => TaskFailure(problem),
        TaskSuccess(:final value) => switch (value
            .where((task) => matchesEwsTaskCreate(task, intent.operationId))
            .singleOrNull) {
          final task?
              when matchesEwsTaskUpdate(
                task,
                TaskPatch.between(const TaskFields(title: ''), intent.fields!),
              ) =>
            TaskSuccess(task),
          _ => const TaskFailure(_unresolved),
        },
      };
    }
    final cached = worker.store.cachedTask(intent.base!.id);
    return switch (cached) {
      TaskFailure(:final problem) => TaskFailure(problem),
      TaskSuccess(value: null) when intent.kind == TaskWriteKind.delete =>
        const TaskSuccess(null),
      TaskSuccess(value: final task?)
          when intent.kind == TaskWriteKind.update &&
              matchesEwsTaskUpdate(task, intent.patch) =>
        TaskSuccess(task),
      _ => const TaskFailure(_unresolved),
    };
  },
);

const _missingRevision = TaskProblem(
  TaskProblemCode.conflict,
  mutationMayHaveOccurred: false,
);

const _unresolved = TaskProblem(
  TaskProblemCode.conflict,
  mutationMayHaveOccurred: true,
);
