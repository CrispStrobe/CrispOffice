import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';

Future<TaskResult<bool>> syncStudioGoogleTasks(
  TaskSyncWorker worker,
  TaskAccountLease lease,
  GoogleTaskProvider provider,
  TaskList list,
  MailAccountSession session,
) => worker.synchronize(
  lease,
  list.id,
  pull: (position) =>
      provider.pull(list.id, cursor: position.cursor, lease: session.begin()),
  write: (intent) async {
    if (intent.kind == TaskWriteKind.create) {
      return provider.create(list.id, intent.fields!, session.begin());
    }
    final base = intent.base!;
    final revision = base.revision;
    if (revision == null) {
      return const TaskFailure(
        TaskProblem(TaskProblemCode.conflict, mutationMayHaveOccurred: false),
      );
    }
    if (intent.kind == TaskWriteKind.update) {
      return provider.update(
        base.id,
        intent.patch,
        revision: revision,
        lease: session.begin(),
      );
    }
    return switch (await provider.delete(
      base.id,
      revision: revision,
      lease: session.begin(),
    )) {
      TaskSuccess() => const TaskSuccess(null),
      TaskFailure(:final problem) => TaskFailure(problem),
    };
  },
  recover: (intent) async {
    if (intent.kind == TaskWriteKind.create) {
      // Google assigns IDs and has no client operation identifier.
      return const TaskFailure(_unresolved);
    }
    return switch (worker.store.cachedTask(intent.base!.id)) {
      TaskFailure(:final problem) => TaskFailure(problem),
      TaskSuccess(value: null) when intent.kind == TaskWriteKind.delete =>
        const TaskSuccess(null),
      TaskSuccess(value: final task?)
          when intent.kind == TaskWriteKind.update &&
              googleTaskMatchesUpdate(task, intent.patch) =>
        TaskSuccess(task),
      _ => const TaskFailure(_unresolved),
    };
  },
);

const _unresolved = TaskProblem(
  TaskProblemCode.conflict,
  mutationMayHaveOccurred: true,
);
