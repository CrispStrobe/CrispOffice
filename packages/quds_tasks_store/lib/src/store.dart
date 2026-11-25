import 'dart:convert';

import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:sqlite3/common.dart';

import 'codec.dart';

part 'outbox.dart';

/// The current generation of one connected account. A disconnect invalidates
/// every lease already held by workers, including workers using another handle.
final class TaskAccountLease {
  TaskAccountLease._(this.account, this.generation, this._databaseId);

  final TaskAccountId account;
  final int generation;
  final String _databaseId;
}

/// State captured atomically before making a provider request.
final class TaskPullPosition {
  TaskPullPosition._({
    required this.list,
    required this.cursor,
    required this.baseline,
    required this.knownRevisions,
    required this._revision,
    required this._checkpoint,
    required this._epoch,
    required this._lease,
  });

  final TaskListId list;
  final String? cursor;
  final bool baseline;

  /// During a baseline the provider must enumerate every current task. During
  /// incremental sync the provider can skip tasks with unchanged revisions.
  final Map<TaskId, String?> knownRevisions;
  final int _revision;
  final String? _checkpoint;
  final int _epoch;
  final TaskAccountLease _lease;
}

/// Stores authoritative provider snapshots in a dedicated SQLite database.
/// Supply a connection opened in the application's private data directory.
/// The caller owns the connection. All DB methods are synchronous and should
/// run on the host's storage isolate when task collections can be large.
final class TaskPullStore {
  TaskPullStore(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _db.execute('PRAGMA busy_timeout = 1500');
    _databaseId = _transaction(() {
      final version = _db.userVersion;
      if (version == 0) {
        for (final statement in _schema) {
          _db.execute(statement);
        }
      } else if (version != 1 && version != 2) {
        throw const FormatException('Unsupported Tasks database schema.');
      }
      if (version < 2) {
        _db.execute(_outboxSchema);
        _db.execute(_bindingSchema);
        _db.execute('ALTER TABLE task_lists ADD COLUMN retry_at INTEGER');
        _db.userVersion = 2;
      }
      return _db.select('SELECT id FROM task_database_identity').single['id']
          as String;
    });
  }

  final CommonDatabase _db;
  late final String _databaseId;

  /// Connects or resumes this account. Finished checkpoints survive restart.
  TaskResult<TaskAccountLease> connect(TaskAccountId account) => _run(() {
    _db.execute(
      '''INSERT INTO task_accounts(provider, account, connected, generation)
         VALUES (?, ?, 1, 1)
         ON CONFLICT(provider, account) DO UPDATE SET connected = 1''',
      _accountKey(account),
    );
    final generation = _account(account)!['generation'] as int;
    return TaskAccountLease._(account, generation, _databaseId);
  });

  /// Invalidates writes from outstanding provider requests. Cached rows and
  /// checkpoints remain stored for the same account if it reconnects.
  TaskResult<TaskUnit> disconnect(TaskAccountLease lease) => _run(() {
    _assertCurrent(lease);
    _db.execute(
      '''UPDATE task_accounts SET connected = 0, generation = generation + 1
         WHERE provider = ? AND account = ?''',
      _accountKey(lease.account),
    );
    return TaskUnit.value;
  });

  TaskResult<TaskPullPosition> position(
    TaskAccountLease lease,
    TaskListId list,
  ) => _run(() {
    _assertScope(lease, list);
    final key = _listKey(list);
    _db.execute(
      '''INSERT INTO task_lists(provider, account, list) VALUES (?, ?, ?)
             ON CONFLICT(provider, account, list) DO NOTHING''',
      key,
    );
    final row = _position(list);
    final baseline = row['baseline'] == 1;
    final checkpoint = row['checkpoint'] as String?;
    final continuation = row['continuation'] as String?;
    return TaskPullPosition._(
      list: list,
      cursor: continuation ?? (baseline ? null : checkpoint),
      baseline: baseline,
      knownRevisions: Map.unmodifiable({
        if (!baseline)
          for (final task in _db.select(
            '''SELECT remote_id, etag FROM task_remote
                   WHERE provider = ? AND account = ? AND list = ?''',
            key,
          ))
            TaskId(task['remote_id'] as String, list: list):
                task['etag'] as String?,
      }),
      revision: row['revision'] as int,
      epoch: row['epoch'] as int,
      checkpoint: checkpoint,
      lease: lease,
    );
  });

  /// Commits task rows and the cursor together. A stale request can never apply
  /// after another page, a reset, or a disconnect.
  TaskResult<TaskUnit> apply(TaskPullPosition position, TaskSyncPage page) =>
      _run(() {
        final list = position.list;
        _assertScope(position._lease, list);
        final key = _listKey(list);
        if (_position(list)['revision'] != position._revision) {
          throw const _StoreFailure(TaskProblemCode.staleOperation);
        }
        if (page.list != list ||
            (page.nextCursor != null && page.nextCursor == position.cursor)) {
          throw const _StoreFailure(TaskProblemCode.invalidResponse);
        }
        if (page.resetRequired) {
          if (position.cursor == null ||
              page.upserts.isNotEmpty ||
              page.tombstones.isNotEmpty ||
              page.nextCursor != null ||
              page.checkpoint != null) {
            throw const _StoreFailure(TaskProblemCode.invalidResponse);
          }
          _advance(
            position,
            checkpoint: position._checkpoint,
            baseline: true,
            epoch: position._epoch + 1,
          );
          return TaskUnit.value;
        }

        final touched = <TaskId>{};
        for (final task in page.upserts) {
          if (!touched.add(task.id)) {
            throw const _StoreFailure(TaskProblemCode.invalidResponse);
          }
          _putRemote(task, position._epoch);
        }
        for (final id in page.tombstones) {
          if (!touched.add(id)) {
            throw const _StoreFailure(TaskProblemCode.invalidResponse);
          }
          _db.execute(
            '''DELETE FROM task_remote
           WHERE provider = ? AND account = ? AND list = ? AND remote_id = ?''',
            [...key, id.value],
          );
        }
        if (page.complete && position.baseline) {
          _db.execute(
            '''DELETE FROM task_remote
           WHERE provider = ? AND account = ? AND list = ? AND epoch != ?''',
            [...key, position._epoch],
          );
        }
        final repeatsSnapshot = page.complete && page.checkpoint == null;
        _advance(
          position,
          checkpoint: page.complete ? page.checkpoint : position._checkpoint,
          continuation: page.nextCursor,
          baseline: repeatsSnapshot || (!page.complete && position.baseline),
          epoch: position._epoch + (repeatsSnapshot ? 1 : 0),
        );
        return TaskUnit.value;
      });

  /// Cached tasks are available offline for an explicitly scoped list.
  TaskResult<List<RemoteTask>> tasks(TaskListId list) => _result(() {
    final rows = _db.select(
      '''SELECT remote_id, etag, fields, raw_format, raw FROM task_remote
         WHERE provider = ? AND account = ? AND list = ? ORDER BY remote_id''',
      _listKey(list),
    );
    return List<RemoteTask>.unmodifiable(
      rows.map(
        (row) => RemoteTask(
          id: TaskId(row['remote_id'] as String, list: list),
          revision: row['etag'] as String?,
          fields: decodeFields(row['fields'] as String),
          providerData: switch (row['raw_format']) {
            final String format => TaskProviderData(
              format: format,
              raw: row['raw'] as String,
            ),
            _ => null,
          },
        ),
      ),
    );
  });

  void _putRemote(RemoteTask task, int epoch) => _db.execute(
    '''INSERT INTO task_remote
       (provider, account, list, remote_id, etag, fields, raw_format, raw, epoch)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(provider, account, list, remote_id) DO UPDATE SET
         etag = excluded.etag, fields = excluded.fields, raw_format = excluded.raw_format,
         raw = excluded.raw, epoch = excluded.epoch''',
    [
      ..._listKey(task.id.list),
      task.id.value,
      task.revision,
      encodeFields(task.fields),
      task.providerData?.format,
      task.providerData?.raw,
      epoch,
    ],
  );

  void _advance(
    TaskPullPosition position, {
    required String? checkpoint,
    String? continuation,
    required bool baseline,
    required int epoch,
  }) {
    _db.execute(
      '''UPDATE task_lists SET checkpoint = ?, continuation = ?, baseline = ?,
         epoch = ?, revision = revision + 1
         WHERE provider = ? AND account = ? AND list = ?''',
      [
        checkpoint,
        continuation,
        baseline ? 1 : 0,
        epoch,
        ..._listKey(position.list),
      ],
    );
  }

  Row _position(TaskListId list) {
    final rows = _db.select(
      '''SELECT checkpoint, continuation, baseline, epoch, revision FROM task_lists
         WHERE provider = ? AND account = ? AND list = ?''',
      _listKey(list),
    );
    if (rows.isEmpty) throw const _StoreFailure(TaskProblemCode.staleOperation);
    return rows.single;
  }

  Row? _account(TaskAccountId account) => _db.select(
    '''SELECT generation, connected FROM task_accounts
       WHERE provider = ? AND account = ?''',
    _accountKey(account),
  ).singleOrNull;

  void _assertScope(TaskAccountLease lease, TaskListId list) {
    if (lease.account != list.account) {
      throw const _StoreFailure(TaskProblemCode.invalidInput);
    }
    _assertCurrent(lease);
  }

  void _assertCurrent(TaskAccountLease lease) {
    final account = _account(lease.account);
    if (lease._databaseId != _databaseId ||
        account?['connected'] != 1 ||
        account?['generation'] != lease.generation) {
      throw const _StoreFailure(TaskProblemCode.staleOperation);
    }
  }

  TaskResult<T> _run<T>(T Function() work) => _result(() => _transaction(work));

  T _transaction<T>(T Function() work) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final value = work();
      _db.execute('COMMIT');
      return value;
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}

List<Object> _accountKey(TaskAccountId account) => [
  account.provider,
  account.value,
];

List<Object> _listKey(TaskListId list) => [
  ..._accountKey(list.account),
  list.value,
];

final class _StoreFailure implements Exception {
  const _StoreFailure(this.code);

  final TaskProblemCode code;
}

TaskResult<T> _result<T>(T Function() work) {
  try {
    return TaskSuccess(work());
  } on _StoreFailure catch (error) {
    return TaskFailure(TaskProblem(error.code));
  } on SqliteException {
    return const TaskFailure(TaskProblem(TaskProblemCode.storageFailure));
  } on FormatException {
    return const TaskFailure(TaskProblem(TaskProblemCode.storageFailure));
  } on ArgumentError {
    return const TaskFailure(TaskProblem(TaskProblemCode.storageFailure));
  } on TypeError {
    return const TaskFailure(TaskProblem(TaskProblemCode.storageFailure));
  }
}

const _schema = [
  'CREATE TABLE task_database_identity(id TEXT PRIMARY KEY)',
  'INSERT INTO task_database_identity VALUES (hex(randomblob(16)))',
  '''CREATE TABLE task_accounts (
       provider TEXT NOT NULL, account TEXT NOT NULL,
       connected INTEGER NOT NULL, generation INTEGER NOT NULL,
       PRIMARY KEY(provider, account)
     )''',
  '''CREATE TABLE task_lists (
       provider TEXT NOT NULL, account TEXT NOT NULL, list TEXT NOT NULL,
       checkpoint TEXT, continuation TEXT, baseline INTEGER NOT NULL DEFAULT 1,
       epoch INTEGER NOT NULL DEFAULT 1, revision INTEGER NOT NULL DEFAULT 0,
       PRIMARY KEY(provider, account, list),
       FOREIGN KEY(provider, account) REFERENCES task_accounts(provider, account)
     )''',
  '''CREATE TABLE task_remote (
       provider TEXT NOT NULL, account TEXT NOT NULL, list TEXT NOT NULL,
       remote_id TEXT NOT NULL, etag TEXT, fields TEXT NOT NULL,
       raw_format TEXT, raw TEXT, epoch INTEGER NOT NULL,
       PRIMARY KEY(provider, account, list, remote_id),
       FOREIGN KEY(provider, account, list) REFERENCES task_lists(provider, account, list)
     )''',
];
