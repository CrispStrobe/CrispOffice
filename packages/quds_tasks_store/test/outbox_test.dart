import 'dart:io';

import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

final _account = TaskAccountId('fixture', provider: 'graph');
final _list = TaskListId('list', account: _account);
final _id = TaskId('remote', list: _list);

T _ok<T>(TaskResult<T> result) {
  expect(
    result,
    isA<TaskSuccess<T>>(),
    reason: result is TaskFailure<T> ? result.problem.code.name : null,
  );
  return (result as TaskSuccess<T>).value;
}

TaskProblemCode _code<T>(TaskResult<T> outcome) =>
    (outcome as TaskFailure<T>).problem.code;

RemoteTask _remote(TaskFields fields, String revision) =>
    RemoteTask(id: _id, fields: fields, revision: revision);

void _pull(
  TaskPullStore store,
  TaskAccountLease lease, {
  List<RemoteTask> tasks = const [],
  List<TaskId> deleted = const [],
  String cursor = 'delta',
}) => _ok(
  store.apply(
    _ok(store.position(lease, _list)),
    TaskSyncPage(
      list: _list,
      upserts: tasks,
      tombstones: deleted,
      checkpoint: cursor,
    ),
  ),
);

void main() {
  late TaskPullStore store;
  late Database db;
  late TaskAccountLease lease;
  setUp(() {
    db = sqlite3.openInMemory();
    addTearDown(db.close);
    store = TaskPullStore(db);
    lease = _ok(store.connect(_account));
  });

  test(
    'a lost create is recovered after closing the database without replay',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-task-outbox-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = '${directory.path}/tasks.sqlite';
      final first = sqlite3.open(file);
      final original = TaskPullStore(first);
      final oldLease = _ok(original.connect(_account));
      _pull(original, oldLease);
      final draft = _ok(
        original.saveEdit(
          oldLease,
          _list,
          fields: const TaskFields(title: 'Local draft'),
        ),
      );
      final claimed = _ok(original.nextWrite(oldLease, _list))!;
      expect(claimed.recovery, isFalse);
      first.close();

      final reopened = sqlite3.open(file);
      addTearDown(reopened.close);
      final restarted = TaskPullStore(reopened);
      final fresh = _ok(restarted.connect(_account));
      var recovered = 0;
      expect(
        _ok(
          await TaskSyncWorker(restarted).synchronize(
            fresh,
            _list,
            pull: (_) async => TaskSuccess(
              TaskSyncPage(
                list: _list,
                upserts: [],
                tombstones: [],
                checkpoint: 'next',
              ),
            ),
            write: (_) async => throw StateError(
              'A previously attempted create may not replay.',
            ),
            recover: (intent) async {
              recovered++;
              expect(intent.localId, draft.id);
              expect(intent.operationId, claimed.operationId);
              return TaskSuccess(_remote(intent.fields!, 'created'));
            },
          ),
        ),
        isTrue,
      );
      expect(recovered, 1);
      expect(_ok(restarted.edits(_list)), isEmpty);
      final remote = _ok(restarted.tasks(_list)).single;
      final changed = _ok(
        restarted.saveEdit(
          fresh,
          _list,
          remote: remote,
          fields: const TaskFields(title: 'Next'),
        ),
      );
      expect(changed.id, draft.id);
    },
  );

  test(
    'canonical acknowledgment preserves a later edit and an independent server change',
    () {
      final base = _remote(const TaskFields(title: 'Base'), 'one');
      _pull(store, lease, tasks: [base]);
      final first = _ok(
        store.saveEdit(
          lease,
          _list,
          remote: base,
          fields: TaskFields(title: 'First', due: TaskDate(2030, 3, 3)),
        ),
      );
      _pull(
        store,
        lease,
        tasks: [
          _remote(
            const TaskFields(title: 'Base', notes: TaskText('Server')),
            'two',
          ),
        ],
      );
      final write = _ok(store.nextWrite(lease, _list))!;
      expect(write.patch.notes.isChanged, isFalse);
      expect(write.fields!.notes?.value, 'Server');
      _ok(
        store.saveEdit(
          lease,
          _list,
          edit: first,
          fields: TaskFields(title: 'Newer', due: TaskDate(2030, 3, 3)),
        ),
      );
      final normalized = _remote(
        TaskFields(
          title: 'First',
          notes: const TaskText('Server'),
          due: TaskDateTime('2030-03-03T00:00:00', timeZone: 'UTC'),
        ),
        'three',
      );
      final oldPull = _ok(store.position(lease, _list));
      _ok(store.finishWrite(lease, write, TaskSuccess(normalized)));
      expect(
        _code(
          store.apply(
            oldPull,
            TaskSyncPage(list: _list, upserts: [], tombstones: []),
          ),
        ),
        TaskProblemCode.staleOperation,
      );
      final next = _ok(store.nextWrite(lease, _list))!;
      expect(next.patch.changedFields, {TaskField.title});
      expect(next.fields?.title, 'Newer');
      expect(next.fields?.due, normalized.fields.due);
      expect(next.fields?.notes, normalized.fields.notes);
    },
  );

  test(
    'competing edits are retained and keeping local preserves other server fields',
    () {
      final base = _remote(const TaskFields(title: 'Before'), 'one');
      _pull(store, lease, tasks: [base]);
      _ok(
        store.saveEdit(
          lease,
          _list,
          remote: base,
          fields: const TaskFields(title: 'Mine'),
        ),
      );
      _pull(
        store,
        lease,
        tasks: [
          _remote(
            const TaskFields(title: 'Theirs', notes: TaskText('Shared')),
            'two',
          ),
        ],
      );
      expect(_ok(store.nextWrite(lease, _list)), isNull);
      final blocked = _ok(store.edits(_list)).single;
      expect(blocked.state, TaskEditState.blocked);
      _ok(store.resolveEdit(lease, _list, blocked, keepLocal: true));
      final write = _ok(store.nextWrite(lease, _list))!;
      expect(write.patch.changedFields, {TaskField.title});
      expect(write.fields!.notes?.value, 'Shared');
    },
  );

  test('a migrated v1 database keeps rows and cursor', () {
    _pull(
      store,
      lease,
      tasks: [_remote(const TaskFields(title: 'Old'), 'version')],
    );
    db.execute('DROP TABLE task_edits');
    db.execute('DROP TABLE task_bindings');
    db.execute('ALTER TABLE task_lists DROP COLUMN retry_at');
    db.userVersion = 1;
    final upgraded = TaskPullStore(db);
    expect(db.userVersion, 2);
    expect(_ok(upgraded.position(lease, _list)).cursor, 'delta');
    expect(_ok(upgraded.tasks(_list)).single.fields.title, 'Old');
    expect(_ok(upgraded.edits(_list)), isEmpty);
  });

  test(
    'throttling persists a deadline and forbids immediate another pull',
    () async {
      _pull(store, lease);
      final worker = TaskSyncWorker(store);
      const throttle = TaskProblem(
        TaskProblemCode.throttled,
        retryAfter: Duration(minutes: 3),
      );
      Future<TaskResult<RemoteTask?>> unused(TaskWriteIntent _) async =>
          throw StateError('No write expected.');
      final failed = await worker.synchronize(
        lease,
        _list,
        pull: (_) async => const TaskFailure(throttle),
        write: unused,
        recover: unused,
      );
      expect(_code(failed), TaskProblemCode.throttled);
      final reopened = TaskPullStore(db);
      expect(
        _ok(reopened.retryDelay(lease, _list))!.inSeconds,
        greaterThan(160),
      );
      final stillWaiting = await TaskSyncWorker(reopened).synchronize(
        lease,
        _list,
        pull: (_) async => throw StateError('Retry deadline was ignored.'),
        write: unused,
        recover: unused,
      );
      expect(_code(stillWaiting), TaskProblemCode.throttled);
    },
  );

  test('a remote tombstone conflicts with a dirty update', () {
    final base = _remote(const TaskFields(title: 'Server'), 'one');
    _pull(store, lease, tasks: [base]);
    _ok(
      store.saveEdit(
        lease,
        _list,
        remote: base,
        fields: const TaskFields(title: 'Offline'),
      ),
    );
    _pull(store, lease, deleted: [_id]);
    expect(_ok(store.nextWrite(lease, _list)), isNull);
    final edit = _ok(store.edits(_list)).single;
    expect(edit.fields?.title, 'Offline');
    expect(edit.problem, TaskProblemCode.conflict);
    _ok(store.resolveEdit(lease, _list, edit, keepLocal: false));
    expect(_ok(store.edits(_list)), isEmpty);
  });

  test(
    'disconnect fences acknowledgment and a repeated claim is read-only',
    () {
      _pull(store, lease);
      _ok(
        store.saveEdit(
          lease,
          _list,
          fields: const TaskFields(title: 'Pending'),
        ),
      );
      final intent = _ok(store.nextWrite(lease, _list))!;
      final second = _ok(store.nextWrite(lease, _list))!;
      expect(second.operationId, intent.operationId);
      expect(second.recovery, isTrue);
      _ok(store.disconnect(lease));
      final late = store.finishWrite(
        lease,
        intent,
        TaskSuccess(_remote(intent.fields!, 'late')),
      );
      expect(_code(late), TaskProblemCode.staleOperation);
      final fresh = _ok(store.connect(_account));
      expect(_ok(store.nextWrite(fresh, _list))!.recovery, isTrue);
    },
  );
  test(
    'an unresolved create does not block independent pending writes',
    () async {
      _pull(store, lease);
      final first = _ok(
        store.saveEdit(lease, _list, fields: const TaskFields(title: 'First')),
      );
      _ok(store.nextWrite(lease, _list));
      _ok(
        store.saveEdit(lease, _list, fields: const TaskFields(title: 'Second')),
      );
      final outcome = await TaskSyncWorker(store).synchronize(
        lease,
        _list,
        pull: (_) async => TaskSuccess(
          TaskSyncPage(
            list: _list,
            upserts: [],
            tombstones: [],
            checkpoint: 'next',
          ),
        ),
        recover: (intent) async {
          expect(intent.localId, first.id);
          return const TaskFailure(
            TaskProblem(
              TaskProblemCode.conflict,
              mutationMayHaveOccurred: true,
            ),
          );
        },
        write: (intent) async =>
            TaskSuccess(_remote(intent.fields!, 'created')),
      );
      expect(_code(outcome), TaskProblemCode.conflict);
      expect(_ok(store.tasks(_list)).single.fields.title, 'Second');
      expect(_ok(store.edits(_list)).single.id, first.id);
    },
  );

  test(
    'a stale edit handle cannot overwrite a new edit for the same stable ID',
    () {
      final base = _remote(const TaskFields(title: 'Before'), 'one');
      _pull(store, lease, tasks: [base]);
      final old = _ok(
        store.saveEdit(
          lease,
          _list,
          remote: base,
          fields: const TaskFields(title: 'Earlier'),
        ),
      );
      final write = _ok(store.nextWrite(lease, _list))!;
      final canonical = _remote(const TaskFields(title: 'Earlier'), 'two');
      _ok(store.finishWrite(lease, write, TaskSuccess(canonical)));
      final fresh = _ok(
        store.saveEdit(
          lease,
          _list,
          remote: canonical,
          fields: const TaskFields(title: 'Fresh'),
        ),
      );
      expect(fresh.id, old.id);
      expect(fresh.revision, old.revision);
      expect(
        _code(
          store.saveEdit(
            lease,
            _list,
            edit: old,
            fields: const TaskFields(title: 'Stale'),
          ),
        ),
        TaskProblemCode.staleOperation,
      );
    },
  );
}
