part of 'store.dart';

enum TaskWriteKind { create, update, delete }

enum TaskEditState { pending, uncertain, blocked }

final class LocalTaskEdit {
  LocalTaskEdit._(
    this.id,
    this._nonce,
    this.revision,
    this.remoteId,
    this.fields,
    this.state,
    this.problem,
  );

  final String id;
  final String _nonce;
  final int revision;
  final TaskId? remoteId;
  final TaskFields? fields;
  final TaskEditState state;
  final TaskProblemCode? problem;
}

/// A durable write attempt. Once claimed, recovery is read-only until the
/// original outcome is established. A delayed or absent result cannot replay it.
final class TaskWriteIntent {
  TaskWriteIntent._(
    this.list,
    this.localId,
    this.operationId,
    this.kind,
    this.revision,
    this.base,
    this.fields,
    this.attemptedAt,
    this.recovery,
  );

  final TaskListId list;
  final String localId;
  final String operationId;
  final TaskWriteKind kind;
  final int revision;
  final RemoteTask? base;
  final TaskFields? fields;
  final DateTime attemptedAt;
  final bool recovery;
  TaskPatch get patch => TaskPatch.between(base!.fields, fields!);
}

extension TaskOutbox on TaskPullStore {
  /// Saves an offline create or edit. Supply the last displayed edit to fence
  /// overlapping local changes, or the cached remote task for a first edit.
  TaskResult<LocalTaskEdit> saveEdit(
    TaskAccountLease lease,
    TaskListId list, {
    required TaskFields? fields,
    LocalTaskEdit? edit,
    RemoteTask? remote,
  }) => _run(() {
    _assertScope(lease, list);
    _ensureList(list);
    if ((remote != null && remote.id.list != list) ||
        (edit != null && remote != null)) {
      throw const _StoreFailure(TaskProblemCode.invalidInput);
    }
    final key = _listKey(list);
    if (edit != null) {
      final row = _editRow(list, edit.id);
      if (row?['revision'] != edit.revision ||
          row?['edit_nonce'] != edit._nonce) {
        throw const _StoreFailure(TaskProblemCode.staleOperation);
      }
      _db.execute(
        '''UPDATE task_edits SET desired = ?, revision = revision + 1
        WHERE provider = ? AND account = ? AND list = ? AND local_id = ?''',
        [_fieldsJson(fields), ...key, edit.id],
      );
      return _local(list, _editRow(list, edit.id)!);
    }
    if (remote != null) {
      final current = _remote(list, remote.id.value);
      if (current == null ||
          current.revision != remote.revision ||
          current.fields != remote.fields ||
          current.providerData?.raw != remote.providerData?.raw ||
          current.providerData?.format != remote.providerData?.format ||
          _db
              .select(
                '''SELECT 1 FROM task_edits WHERE provider = ? AND account = ?
            AND list = ? AND remote_id = ?''',
                [...key, remote.id.value],
              )
              .isNotEmpty) {
        throw const _StoreFailure(TaskProblemCode.staleOperation);
      }
    }
    if (remote == null && fields == null) {
      throw const _StoreFailure(TaskProblemCode.invalidInput);
    }
    final localId = remote == null ? _newId() : _binding(remote.id);
    if (remote != null) _bind(remote.id, localId);
    _db.execute(
      '''INSERT INTO task_edits
       (provider, account, list, local_id, edit_nonce, remote_id, base, desired)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        ...key,
        localId,
        _newId(),
        remote?.id.value,
        _remoteJson(remote),
        _fieldsJson(fields),
      ],
    );
    return _local(list, _editRow(list, localId)!);
  });

  TaskResult<RemoteTask?> cachedTask(TaskId id) =>
      _result(() => _remote(id.list, id.value));

  TaskResult<List<LocalTaskEdit>> edits(TaskListId list) => _result(
    () => List.unmodifiable(
      _db
          .select(
            '''SELECT * FROM task_edits
      WHERE provider = ? AND account = ? AND list = ? ORDER BY rowid''',
            _listKey(list),
          )
          .map((row) => _local(list, row)),
    ),
  );

  /// Clears a definite problem after explicit user choice. Keeping the local
  /// copy establishes the currently shown server state as the new merge base.
  TaskResult<TaskUnit> resolveEdit(
    TaskAccountLease lease,
    TaskListId list,
    LocalTaskEdit edit, {
    required bool keepLocal,
  }) => _run(() {
    _assertScope(lease, list);
    final row = _editRow(list, edit.id);
    if (row == null ||
        row['revision'] != edit.revision ||
        row['edit_nonce'] != edit._nonce ||
        row['operation'] != null ||
        row['problem'] == null) {
      throw const _StoreFailure(TaskProblemCode.staleOperation);
    }
    if (!keepLocal) {
      _removeEdit(list, edit.id);
    } else {
      if (edit.problem == TaskProblemCode.conflict) {
        final current = _remote(list, row['remote_id'] as String?);
        final base = _readRemote(list, row['base'] as String?);
        final fields = edit.fields;
        final rebased = current != null && base != null && fields != null
            ? TaskPatch.between(base.fields, fields).applyTo(current.fields)
            : fields;
        _rebaseEdit(list, edit.id, current, rebased);
      } else {
        _db.execute(
          '''UPDATE task_edits SET problem = NULL, revision = revision + 1
          WHERE provider = ? AND account = ? AND list = ? AND local_id = ?''',
          [..._listKey(list), edit.id],
        );
      }
    }
    return TaskUnit.value;
  });

  TaskResult<TaskWriteIntent?> nextWrite(
    TaskAccountLease lease,
    TaskListId list, {
    Set<String> excluding = const {},
  }) => _run(() {
    _assertScope(lease, list);
    _ensureList(list);
    final position = _position(list);
    if (position['baseline'] == 1 || position['continuation'] != null) {
      throw const _StoreFailure(TaskProblemCode.staleOperation);
    }
    final key = _listKey(list);
    for (final row in _db.select('''SELECT * FROM task_edits
        WHERE provider = ? AND account = ? AND list = ? AND problem IS NULL
        ORDER BY rowid''', key)) {
      final id = row['local_id'] as String;
      if (excluding.contains(id)) continue;
      final operation = row['operation'] as String?;
      if (operation != null) return _intent(list, row, recovery: true);
      final local = _optionalFields(row['desired']);
      final base = _readRemote(list, row['base'] as String?);
      final RemoteTask? current;
      final TaskFields? sending;
      if (base == null) {
        if (local == null) {
          _removeEdit(list, id);
          continue;
        }
        current = null;
        sending = local;
      } else {
        current = _remote(list, base.id.value);
        final revision = row['revision'] as int;
        final plan =
            (reconcileTask(
                      snapshot: TaskSyncSnapshot(
                        base: base,
                        local: local,
                        localRevision: revision,
                      ),
                      remote: current,
                      expectedLocalRevision: revision,
                    )
                    as TaskSuccess<TaskReconciliation>)
                .value;
        if (plan.hasConflict) {
          _block(list, id, TaskProblemCode.conflict);
          continue;
        }
        if (!plan.needsRemoteWrite) {
          _removeEdit(list, id);
          continue;
        }
        sending = plan.merged;
        // A deletion plan has no merged fields.
        if (current == null) {
          throw const _StoreFailure(TaskProblemCode.storageFailure);
        }
      }
      final kind = current == null
          ? TaskWriteKind.create
          : sending == null
          ? TaskWriteKind.delete
          : TaskWriteKind.update;
      _db.execute(
        '''UPDATE task_edits SET operation = ?, attempt_kind = ?,
        attempt_at = ?, attempt_revision = revision, attempt_base = ?, attempt_fields = ?, attempt_desired = ?
        WHERE provider = ? AND account = ? AND list = ? AND local_id = ?''',
        [
          _newId(),
          kind.name,
          DateTime.now().toUtc().millisecondsSinceEpoch,
          _remoteJson(current),
          _fieldsJson(sending),
          _fieldsJson(local),
          ...key,
          id,
        ],
      );
      return _intent(list, _editRow(list, id)!, recovery: false);
    }
    return null;
  });

  TaskResult<TaskUnit> finishWrite(
    TaskAccountLease lease,
    TaskWriteIntent intent,
    TaskResult<RemoteTask?> result,
  ) => _run(() {
    final list = intent.list;
    _assertScope(lease, list);
    final row = _editRow(list, intent.localId);
    if (row == null || row['operation'] != intent.operationId) {
      throw const _StoreFailure(TaskProblemCode.staleOperation);
    }
    if (result case TaskFailure(:final problem)) {
      if (!intent.recovery && problem.mutationMayHaveOccurred == false) {
        if (_temporary(problem.code)) {
          _db.execute(
            '''UPDATE task_edits SET operation = NULL WHERE
             provider = ? AND account = ? AND list = ? AND local_id = ?''',
            [..._listKey(list), intent.localId],
          );
        } else {
          _block(list, intent.localId, problem.code);
        }
      }
      return TaskUnit.value;
    }
    final observed = (result as TaskSuccess<RemoteTask?>).value;
    if ((observed == null) != (intent.kind == TaskWriteKind.delete) ||
        (observed != null && observed.id.list != list) ||
        (observed != null &&
            intent.base != null &&
            observed.id != intent.base!.id)) {
      throw const _StoreFailure(TaskProblemCode.invalidResponse);
    }
    final key = _listKey(list);
    final position = _position(list);
    if (observed != null) {
      _putRemote(observed, position['epoch'] as int);
      _bind(observed.id, intent.localId);
    } else {
      _db.execute(
        '''DELETE FROM task_remote WHERE provider = ? AND account = ?
        AND list = ? AND remote_id = ?''',
        [...key, intent.base!.id.value],
      );
    }
    // Fence a pull started before this acknowledgment. Its older page cannot
    // overwrite the just-observed server state or advance the cursor.
    _db.execute('''UPDATE task_lists SET revision = revision + 1 WHERE
      provider = ? AND account = ? AND list = ?''', key);
    if (row['revision'] == intent.revision) {
      _removeEdit(list, intent.localId);
    } else {
      final later = _optionalFields(row['desired']);
      final sent = _optionalFields(row['attempt_desired']);
      final rebased = later != null && sent != null && observed != null
          ? TaskPatch.between(sent, later).applyTo(observed.fields)
          : later;
      if (rebased == observed?.fields) {
        _removeEdit(list, intent.localId);
      } else {
        _rebaseEdit(list, intent.localId, observed, rebased);
      }
    }
    return TaskUnit.value;
  });

  TaskResult<Duration?> retryDelay(TaskAccountLease lease, TaskListId list) =>
      _run(() {
        _assertScope(lease, list);
        _ensureList(list);
        final retry = _positionRetry(list);
        if (retry == null) return null;
        final remaining = DateTime.fromMillisecondsSinceEpoch(
          retry,
          isUtc: true,
        ).difference(DateTime.now().toUtc());
        return remaining.isNegative || remaining == Duration.zero
            ? null
            : remaining;
      });

  TaskResult<TaskUnit> deferSync(
    TaskAccountLease lease,
    TaskListId list,
    TaskProblem problem,
  ) => _run(() {
    _assertScope(lease, list);
    if (!_temporary(problem.code) && problem.retryAfter == null) {
      return TaskUnit.value;
    }
    _ensureList(list);
    final time = DateTime.now()
        .toUtc()
        .add(problem.retryAfter ?? const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    if ((_positionRetry(list) ?? 0) < time) {
      _db.execute(
        '''UPDATE task_lists SET retry_at = ? WHERE provider = ? AND
        account = ? AND list = ?''',
        [time, ..._listKey(list)],
      );
    }
    return TaskUnit.value;
  });

  int? _positionRetry(TaskListId list) =>
      _db.select(
            '''SELECT retry_at FROM task_lists
    WHERE provider = ? AND account = ? AND list = ?''',
            _listKey(list),
          ).single['retry_at']
          as int?;

  String _binding(TaskId id) =>
      (_db
              .select(
                '''SELECT local_id FROM task_bindings
    WHERE provider = ? AND account = ? AND list = ? AND remote_id = ?''',
                [..._listKey(id.list), id.value],
              )
              .singleOrNull?['local_id']
          as String?) ??
      _newId();

  void _bind(TaskId remote, String localId) {
    final key = _listKey(remote.list);
    _db.execute(
      '''DELETE FROM task_bindings WHERE provider = ? AND account = ?
      AND list = ? AND local_id = ? AND remote_id != ?''',
      [...key, localId, remote.value],
    );
    _db.execute(
      '''INSERT INTO task_bindings(provider, account, list, remote_id, local_id)
      VALUES (?, ?, ?, ?, ?) ON CONFLICT(provider, account, list, remote_id)
      DO UPDATE SET local_id = excluded.local_id''',
      [...key, remote.value, localId],
    );
  }

  void _ensureList(TaskListId list) => _db.execute(
    '''INSERT INTO task_lists(provider, account, list) VALUES (?, ?, ?)
       ON CONFLICT(provider, account, list) DO NOTHING''',
    _listKey(list),
  );

  Row? _editRow(TaskListId list, String id) => _db
      .select(
        '''SELECT * FROM task_edits WHERE provider = ? AND account = ? AND list = ?
       AND local_id = ?''',
        [..._listKey(list), id],
      )
      .singleOrNull;

  RemoteTask? _remote(TaskListId list, String? id) {
    if (id == null) return null;
    final row = _db
        .select(
          '''SELECT * FROM task_remote WHERE provider = ? AND
      account = ? AND list = ? AND remote_id = ?''',
          [..._listKey(list), id],
        )
        .singleOrNull;
    if (row == null) return null;
    final format = row['raw_format'] as String?;
    return RemoteTask(
      id: TaskId(id, list: list),
      fields: decodeFields(row['fields'] as String),
      revision: row['etag'] as String?,
      providerData: format == null
          ? null
          : TaskProviderData(format: format, raw: row['raw'] as String),
    );
  }

  String _newId() =>
      _db.select('SELECT lower(hex(randomblob(16))) AS id').single['id']
          as String;

  void _removeEdit(TaskListId list, String id) => _db.execute(
    '''DELETE FROM task_edits WHERE provider = ? AND account = ? AND list = ?
       AND local_id = ?''',
    [..._listKey(list), id],
  );

  void _block(TaskListId list, String id, TaskProblemCode code) => _db.execute(
    '''UPDATE task_edits SET problem = ?, operation = NULL, revision = revision + 1
       WHERE provider = ? AND account = ? AND list = ? AND local_id = ?''',
    [code.name, ..._listKey(list), id],
  );

  void _rebaseEdit(
    TaskListId list,
    String id,
    RemoteTask? base,
    TaskFields? desired,
  ) => _db.execute(
    '''UPDATE task_edits SET base = ?, remote_id = ?, desired = ?,
      operation = NULL, problem = NULL, revision = revision + 1
      WHERE provider = ? AND account = ? AND list = ? AND local_id = ?''',
    [
      _remoteJson(base),
      base?.id.value,
      _fieldsJson(desired),
      ..._listKey(list),
      id,
    ],
  );
}

String? _fieldsJson(TaskFields? fields) =>
    fields == null ? null : encodeFields(fields);
TaskFields? _optionalFields(Object? fields) =>
    fields == null ? null : decodeFields(fields as String);

String? _remoteJson(RemoteTask? task) => task == null
    ? null
    : jsonEncode([
        task.id.value,
        task.revision,
        encodeFields(task.fields),
        task.providerData?.format,
        task.providerData?.raw,
      ]);

RemoteTask? _readRemote(TaskListId list, String? json) {
  if (json == null) return null;
  final values = jsonDecode(json) as List<Object?>;
  return RemoteTask(
    id: TaskId(values[0] as String, list: list),
    revision: values[1] as String?,
    fields: decodeFields(values[2] as String),
    providerData: values[3] == null
        ? null
        : TaskProviderData(
            format: values[3] as String,
            raw: values[4] as String,
          ),
  );
}

LocalTaskEdit _local(TaskListId list, Row row) {
  final remote = row['remote_id'] as String?;
  final problem = row['problem'] as String?;
  return LocalTaskEdit._(
    row['local_id'] as String,
    row['edit_nonce'] as String,
    row['revision'] as int,
    remote == null ? null : TaskId(remote, list: list),
    _optionalFields(row['desired']),
    problem != null
        ? TaskEditState.blocked
        : row['operation'] != null
        ? TaskEditState.uncertain
        : TaskEditState.pending,
    problem == null ? null : TaskProblemCode.values.byName(problem),
  );
}

TaskWriteIntent _intent(TaskListId list, Row row, {required bool recovery}) =>
    TaskWriteIntent._(
      list,
      row['local_id'] as String,
      row['operation'] as String,
      TaskWriteKind.values.byName(row['attempt_kind'] as String),
      row['attempt_revision'] as int,
      _readRemote(list, row['attempt_base'] as String?),
      _optionalFields(row['attempt_fields']),
      DateTime.fromMillisecondsSinceEpoch(
        row['attempt_at'] as int,
        isUtc: true,
      ),
      recovery,
    );

const _outboxSchema = '''CREATE TABLE task_edits (
  provider TEXT NOT NULL, account TEXT NOT NULL, list TEXT NOT NULL,
  local_id TEXT NOT NULL, edit_nonce TEXT NOT NULL, remote_id TEXT, base TEXT, desired TEXT,
  revision INTEGER NOT NULL DEFAULT 1, operation TEXT, problem TEXT,
  attempt_kind TEXT, attempt_at INTEGER, attempt_revision INTEGER,
  attempt_base TEXT, attempt_fields TEXT, attempt_desired TEXT,
  PRIMARY KEY (provider, account, list, local_id),
  UNIQUE (provider, account, list, remote_id),
  FOREIGN KEY (provider, account, list) REFERENCES task_lists(provider, account, list)
)''';

bool _temporary(TaskProblemCode code) =>
    code == TaskProblemCode.throttled ||
    code == TaskProblemCode.unavailable ||
    code == TaskProblemCode.providerFailure;

const _bindingSchema = '''CREATE TABLE task_bindings (
  provider TEXT NOT NULL, account TEXT NOT NULL, list TEXT NOT NULL,
  remote_id TEXT NOT NULL, local_id TEXT NOT NULL,
  PRIMARY KEY (provider, account, list, remote_id),
  UNIQUE (provider, account, list, local_id),
  FOREIGN KEY (provider, account, list) REFERENCES task_lists(provider, account, list)
)''';
