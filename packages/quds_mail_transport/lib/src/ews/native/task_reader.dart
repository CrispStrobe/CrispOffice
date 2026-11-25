part of 'provider.dart';

final class NativeEwsTaskReader implements EwsTaskReader {
  NativeEwsTaskReader({required this.account, required this.connection});

  final TaskAccountId account;
  final NativeMailEwsProvider connection;
  final _folders = <TaskListId>{};

  EwsSoap get _soap => connection._soap;

  @override
  Future<TaskResult<List<TaskList>>> taskLists(MailOperationLease lease) async {
    final result = await connection._run(lease, (client, operation) async {
      final defaultList = await _readDefaultList(client, operation);
      final result = <TaskListId, TaskList>{defaultList.id: defaultList};
      final folders = await connection._findFolders(
        client,
        operation,
        taskFolders: true,
      );
      for (final folder in folders) {
        final list = _toList(folder);
        result[list.id] = list;
      }
      if (result.length > connection.limits.maxMailboxes) {
        throw const EwsException(MailProblemCode.quotaExceeded);
      }
      return List<TaskList>.unmodifiable(result.values);
    });
    if (result case MailSuccess(:final value)) {
      _folders
        ..clear()
        ..addAll(value.map((list) => list.id));
    }
    return _taskResult(result);
  }

  @override
  Future<TaskResult<TaskList>> defaultTaskList(MailOperationLease lease) async {
    final result = await connection._run(lease, _readDefaultList);
    if (result case MailSuccess(:final value)) _folders.add(value.id);
    return _taskResult(result);
  }

  Future<TaskList> _readDefaultList(
    EwsHttpClient client,
    _Operation operation,
  ) async {
    final xml = await operation.post(
      client,
      'GetFolder',
      _soap.getFolder('tasks', distinguished: true),
    );
    final page = _soap.folders(xml, 'GetFolder');
    final folder = page.folders.singleOrNull;
    if (folder == null) {
      throw const EwsException(MailProblemCode.providerFailure);
    }
    return _toList(folder);
  }

  TaskList _toList(EwsFolder folder) {
    if (folder.folderClass != 'IPF.Task') {
      throw const EwsException(MailProblemCode.providerFailure);
    }
    return TaskList(
      id: TaskListId(folder.id, account: account),
      name: folder.displayName,
      readOnly: true,
      revision: folder.changeKey,
    );
  }

  @override
  Future<TaskResult<TaskSyncPage>> pullTasks(
    TaskListId list, {
    String? cursor,
    required MailOperationLease lease,
  }) async {
    if (!_folders.contains(list)) {
      return const TaskFailure(TaskProblem(TaskProblemCode.invalidInput));
    }
    final mailbox = MailMailboxId(list.value, account: connection.account);
    final limits = connection.limits;
    final configuration = connection.configuration;
    final EwsSyncCursor? position;
    try {
      position = EwsSyncCursor.decode(
        cursor == null ? null : MailCursor(mailbox: mailbox, value: cursor),
        configuration,
        mailbox,
        limits,
      );
    } on EwsException catch (error) {
      return _taskResult(MailFailure<TaskSyncPage>(MailProblem(error.code)));
    }
    final result = await connection._run(lease, (client, operation) async {
      final EwsSyncChanges page;
      try {
        page = _soap.sync(
          await operation.post(
            client,
            'SyncFolderItems',
            _soap.syncFolderItems(
              list.value,
              syncState: position?.state,
              limit: limits.maxPageSize,
            ),
          ),
          tasks: true,
        );
      } on EwsException catch (error) {
        if (!error.invalidSyncState || position == null) rethrow;
        return TaskSyncPage(
          list: list,
          upserts: [],
          tombstones: [],
          resetRequired: true,
        );
      }
      if (!page.includesLast && page.syncState == position?.state) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      final changes = {
        for (final change in page.changes) change.id: change.kind,
      };
      final ids = [
        for (final entry in changes.entries)
          if (entry.value != EwsChangeKind.delete) entry.key,
      ];
      final deleted = [
        for (final entry in changes.entries)
          if (entry.value == EwsChangeKind.delete)
            TaskId(entry.key, list: list),
      ];
      final items = ids.isEmpty
          ? const <RemoteTask?>[]
          : _soap.tasks(
              await operation.post(client, 'GetItem', _soap.getTasks(ids)),
              list,
              ids,
            );
      final tasks = <RemoteTask>[];
      for (var i = 0; i < ids.length; i++) {
        if (items[i] case final item?) {
          tasks.add(item);
        } else {
          deleted.add(TaskId(ids[i], list: list));
        }
      }
      final next = EwsSyncCursor(
        state: page.syncState,
        revision: (position?.revision ?? 0) + 1,
      ).encode(configuration, mailbox, limits).value;
      return TaskSyncPage(
        list: list,
        upserts: tasks,
        tombstones: deleted,
        nextCursor: page.includesLast ? null : next,
        checkpoint: page.includesLast ? next : null,
      );
    });
    return _taskResult(result);
  }
}

TaskResult<T> _taskResult<T>(MailResult<T> result) => switch (result) {
  MailSuccess(:final value) => TaskSuccess(value),
  MailFailure(:final problem) => TaskFailure(
    TaskProblem(
      TaskProblemCode.values.byName(problem.code.name),
      retryAfter: problem.retryAfter,
      mutationMayHaveOccurred: problem.mutationMayHaveOccurred,
    ),
  ),
};
