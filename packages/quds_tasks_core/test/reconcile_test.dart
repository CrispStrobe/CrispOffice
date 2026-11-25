import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

final _account = TaskAccountId('account', provider: 'graph');
final _list = TaskListId('list', account: _account);
final _id = TaskId('task', list: _list);
const _baseFields = TaskFields(title: 'Original', notes: TaskText('Base note'));

RemoteTask _remote(TaskFields fields, {String revision = 'r1'}) => RemoteTask(
  id: _id,
  fields: fields,
  revision: revision,
  providerData: TaskProviderData(format: 'test', raw: 'payload-$revision'),
);

TaskReconciliation _reconcile(TaskFields? local, RemoteTask? remote) {
  final result = reconcileTask(
    snapshot: TaskSyncSnapshot(
      base: _remote(_baseFields),
      local: local,
      localRevision: 4,
    ),
    remote: remote,
    expectedLocalRevision: 4,
  );
  expect(result, isA<TaskSuccess<TaskReconciliation>>());
  return (result as TaskSuccess<TaskReconciliation>).value;
}

void main() {
  test('unchanged task advances fresh opaque metadata without a write', () {
    final result = _reconcile(
      _baseFields,
      _remote(_baseFields, revision: 'r2'),
    );
    expect(result.kind, TaskReconciliationKind.unchanged);
    expect(result.remote!.revision, 'r2');
    expect(result.remote!.providerData!.raw, 'payload-r2');
    expect(result.merged, _baseFields);
    expect(result.needsRemoteWrite, isFalse);
  });

  test('clean local copy fast-forwards a remote edit without echoing it', () {
    final changed = const TaskPatch(
      title: TaskFieldPatch.set('Remote title'),
    ).applyTo(_baseFields);
    final result = _reconcile(_baseFields, _remote(changed, revision: 'r2'));
    expect(result.kind, TaskReconciliationKind.acceptRemote);
    expect(result.merged, changed);
    expect(result.pendingChanges.isEmpty, isTrue);
  });

  test(
    'local edit produces only its changed fields against the fresh remote',
    () {
      final changed = const TaskPatch(
        priority: TaskFieldPatch.set(TaskPriority.high),
      ).applyTo(_baseFields);
      final result = _reconcile(changed, _remote(_baseFields, revision: 'r2'));
      expect(result.kind, TaskReconciliationKind.pushLocal);
      expect(result.pendingChanges.changedFields, {TaskField.priority});
      expect(result.pendingChanges.applyTo(result.remote!.fields), changed);
      expect(result.localRevision, 4);
    },
  );

  test('independent local and remote edits merge without losing either', () {
    final local = const TaskPatch(
      title: TaskFieldPatch.set('Local title'),
    ).applyTo(_baseFields);
    final theirs = TaskPatch(
      due: TaskFieldPatch.set(TaskDate(2026, 12, 1)),
      notes: const TaskFieldPatch.clear(),
    ).applyTo(_baseFields);
    final result = _reconcile(local, _remote(theirs, revision: 'r2'));
    expect(result.kind, TaskReconciliationKind.merged);
    expect(result.merged!.title, 'Local title');
    expect(result.merged!.due, TaskDate(2026, 12, 1));
    expect(result.merged!.notes, isNull);
    expect(result.pendingChanges.changedFields, {TaskField.title});
    expect(result.pendingChanges.applyTo(theirs), result.merged);
  });

  test(
    'identical concurrent changes converge without a repeated remote write',
    () {
      final changed = const TaskPatch(
        status: TaskFieldPatch.set(TaskStatus.completed),
      ).applyTo(_baseFields);
      final result = _reconcile(changed, _remote(changed, revision: 'r2'));
      expect(result.kind, TaskReconciliationKind.acceptRemote);
      expect(result.merged, changed);
      expect(result.needsRemoteWrite, isFalse);
    },
  );

  test(
    'competing edits report the exact fields and expose no executable patch',
    () {
      final local = const TaskPatch(
        title: TaskFieldPatch.set('Ours'),
        notes: TaskFieldPatch.clear(),
      ).applyTo(_baseFields);
      final theirs = const TaskPatch(
        title: TaskFieldPatch.set('Theirs'),
        notes: TaskFieldPatch.set(TaskText('Remote note')),
      ).applyTo(_baseFields);
      final result = _reconcile(local, _remote(theirs));
      expect(result.kind, TaskReconciliationKind.conflict);
      expect(result.conflicts, {TaskField.title, TaskField.notes});
      expect(result.deletionConflict, isFalse);
      expect(result.merged, isNull);
      expect(result.pendingChanges.isEmpty, isTrue);
      expect(result.needsRemoteWrite, isFalse);
      expect(() => result.conflicts.clear(), throwsUnsupportedError);
    },
  );

  test(
    'every supported editable field participates in the three-way merge',
    () {
      final local = TaskFields(
        title: 'Local',
        notes: const TaskText('Local'),
        status: TaskStatus.completed,
        priority: TaskPriority.high,
        start: TaskDate(2026, 1, 1),
        due: TaskDate(2026, 1, 2),
        reminder: TaskDateTime('2026-01-01T09:00:00', timeZone: 'UTC'),
        completedAt: TaskDateTime('2026-01-01T10:00:00', timeZone: 'UTC'),
      );
      final theirs = TaskFields(
        title: 'Remote',
        notes: const TaskText('Remote'),
        status: TaskStatus.deferred,
        priority: TaskPriority.low,
        start: TaskDate(2027, 1, 1),
        due: TaskDate(2027, 1, 2),
        reminder: TaskDateTime('2027-01-01T09:00:00', timeZone: 'UTC'),
        completedAt: TaskDateTime('2027-01-01T10:00:00', timeZone: 'UTC'),
      );
      expect(
        _reconcile(local, _remote(theirs)).conflicts,
        TaskField.values.toSet(),
      );
    },
  );

  test(
    'authoritative remote deletion accepts clean or already deleted local state',
    () {
      expect(
        _reconcile(_baseFields, null).kind,
        TaskReconciliationKind.deleted,
      );
      expect(_reconcile(null, null).kind, TaskReconciliationKind.deleted);
      expect(_reconcile(_baseFields, null).needsRemoteWrite, isFalse);
    },
  );

  test('remote deletion conflicts with a pending local edit', () {
    final changed = const TaskPatch(
      title: TaskFieldPatch.set('Unsynced'),
    ).applyTo(_baseFields);
    final result = _reconcile(changed, null);
    expect(result.hasConflict, isTrue);
    expect(result.deletionConflict, isTrue);
    expect(result.needsRemoteWrite, isFalse);
  });

  test(
    'local deletion is planned only when the remote observation is unchanged',
    () {
      final result = _reconcile(null, _remote(_baseFields));
      expect(result.kind, TaskReconciliationKind.deleteRemote);
      expect(result.remote!.revision, 'r1');
      expect(result.needsRemoteWrite, isTrue);
      final changed = const TaskPatch(
        notes: TaskFieldPatch.set(TaskText('Do not lose this')),
      ).applyTo(_baseFields);
      final conflict = _reconcile(null, _remote(changed));
      expect(conflict.hasConflict, isTrue);
      expect(conflict.deletionConflict, isTrue);
      expect(conflict.needsRemoteWrite, isFalse);
    },
  );

  test(
    'local deletion preserves changed unknown provider content and revisions',
    () {
      final changedPayload = RemoteTask(
        id: _id,
        fields: _baseFields,
        revision: 'r1',
        providerData: TaskProviderData(
          format: 'test',
          raw: 'unknown-field-changed',
        ),
      );
      final changedRevision = RemoteTask(
        id: _id,
        fields: _baseFields,
        revision: 'r2',
        providerData: TaskProviderData(format: 'test', raw: 'payload-r1'),
      );
      for (final remote in <RemoteTask>[
        changedPayload,
        changedRevision,
        RemoteTask(id: _id, fields: _baseFields, revision: 'r2'),
      ]) {
        final result = _reconcile(null, remote);
        expect(result.hasConflict, isTrue);
        expect(result.deletionConflict, isTrue);
        expect(result.needsRemoteWrite, isFalse);
      }
    },
  );

  test(
    'missing payload requires an unchanged non-null revision before deletion',
    () {
      for (final revision in <String?>['r1', null]) {
        final base = RemoteTask(
          id: _id,
          fields: _baseFields,
          revision: revision,
        );
        final result =
            reconcileTask(
                  snapshot: TaskSyncSnapshot(
                    base: base,
                    local: null,
                    localRevision: 0,
                  ),
                  remote: base,
                  expectedLocalRevision: 0,
                )
                as TaskSuccess<TaskReconciliation>;
        expect(
          result.value.kind,
          revision == null
              ? TaskReconciliationKind.conflict
              : TaskReconciliationKind.deleteRemote,
        );
      }
    },
  );

  test(
    'stale local revision and foreign remote identity fail without a plan',
    () {
      final snapshot = TaskSyncSnapshot(
        base: _remote(_baseFields),
        local: _baseFields,
        localRevision: 5,
      );
      final stale = reconcileTask(
        snapshot: snapshot,
        remote: _remote(_baseFields),
        expectedLocalRevision: 4,
      );
      expect(stale, isA<TaskFailure<TaskReconciliation>>());
      expect(
        (stale as TaskFailure<TaskReconciliation>).problem.code,
        TaskProblemCode.staleOperation,
      );
      final foreign = reconcileTask(
        snapshot: snapshot,
        remote: RemoteTask(
          id: TaskId('task', list: TaskListId('moved', account: _account)),
          fields: _baseFields,
        ),
        expectedLocalRevision: 5,
      );
      expect(
        (foreign as TaskFailure<TaskReconciliation>).problem.code,
        TaskProblemCode.invalidInput,
      );
      expect(
        () => TaskSyncSnapshot(
          base: _remote(_baseFields),
          local: null,
          localRevision: -1,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'reopen plus remote completion timestamp becomes a coupled conflict',
    () {
      const baseFields = TaskFields(
        title: 'Task',
        status: TaskStatus.completed,
      );
      final local = const TaskPatch(
        status: TaskFieldPatch.set(TaskStatus.notStarted),
      ).applyTo(baseFields);
      final theirs = TaskPatch(
        completedAt: TaskFieldPatch.set(
          TaskDateTime('2026-11-25T12:00:00', timeZone: 'UTC'),
        ),
      ).applyTo(baseFields);
      final result =
          reconcileTask(
                snapshot: TaskSyncSnapshot(
                  base: _remote(baseFields),
                  local: local,
                  localRevision: 1,
                ),
                remote: _remote(theirs),
                expectedLocalRevision: 1,
              )
              as TaskSuccess<TaskReconciliation>;
      expect(result.value.hasConflict, isTrue);
      expect(result.value.conflicts, {TaskField.status, TaskField.completedAt});
      expect(result.value.pendingChanges.isEmpty, isTrue);
      expect(result.value.merged, isNull);
    },
  );

  test('independent start and due changes cannot produce reversed dates', () {
    final examples =
        <(TaskDateValue, TaskDateValue, TaskDateValue, TaskDateValue)>[
          (
            TaskDate(2026, 11, 25),
            TaskDate(2026, 11, 30),
            TaskDate(2026, 11, 28),
            TaskDate(2026, 11, 26),
          ),
          (
            TaskDateTime('2026-11-25T10:00:00', timeZone: 'Europe/Berlin'),
            TaskDateTime('2026-11-25T14:00:00', timeZone: 'Europe/Berlin'),
            TaskDateTime('2026-11-25T13:00:00.001', timeZone: 'Europe/Berlin'),
            TaskDateTime(
              '2026-11-25T13:00:00.0000000',
              timeZone: 'Europe/Berlin',
            ),
          ),
        ];
    for (final example in examples) {
      final baseFields = TaskFields(
        title: 'Task',
        start: example.$1,
        due: example.$2,
      );
      final local = TaskPatch(
        start: TaskFieldPatch.set(example.$3),
      ).applyTo(baseFields);
      final theirs = TaskPatch(
        due: TaskFieldPatch.set(example.$4),
      ).applyTo(baseFields);
      final result =
          reconcileTask(
                snapshot: TaskSyncSnapshot(
                  base: _remote(baseFields),
                  local: local,
                  localRevision: 1,
                ),
                remote: _remote(theirs),
                expectedLocalRevision: 1,
              )
              as TaskSuccess<TaskReconciliation>;
      expect(result.value.hasConflict, isTrue);
      expect(result.value.conflicts, {TaskField.start, TaskField.due});
      expect(result.value.needsRemoteWrite, isFalse);
    }
  });

  test('date comparisons do not invent timezone or value-kind conversions', () {
    final examples = <(TaskDateValue, TaskDateValue)>[
      (
        TaskDateTime('2026-11-25T13:00:00', timeZone: 'Europe/Berlin'),
        TaskDateTime('2026-11-25T12:30:00', timeZone: 'UTC'),
      ),
      (
        TaskDate(2026, 11, 25),
        TaskDateTime('2026-11-25T12:30:00', timeZone: 'UTC'),
      ),
    ];
    for (final example in examples) {
      final baseFields = TaskFields(title: 'Task', due: example.$2);
      final local = TaskPatch(
        start: TaskFieldPatch.set(example.$1),
      ).applyTo(baseFields);
      final result =
          reconcileTask(
                snapshot: TaskSyncSnapshot(
                  base: _remote(baseFields),
                  local: local,
                  localRevision: 1,
                ),
                remote: _remote(baseFields),
                expectedLocalRevision: 1,
              )
              as TaskSuccess<TaskReconciliation>;
      expect(result.value.hasConflict, isFalse);
      expect(result.value.merged, local);
    }
  });

  test(
    'acknowledged merged state is stable when the same change is seen again',
    () {
      final changed = const TaskPatch(
        title: TaskFieldPatch.set('Acknowledged'),
      ).applyTo(_baseFields);
      final acknowledged = _remote(changed, revision: 'r3');
      final result =
          reconcileTask(
                snapshot: TaskSyncSnapshot(
                  base: acknowledged,
                  local: changed,
                  localRevision: 6,
                ),
                remote: acknowledged,
                expectedLocalRevision: 6,
              )
              as TaskSuccess<TaskReconciliation>;
      expect(result.value.kind, TaskReconciliationKind.unchanged);
      expect(result.value.pendingChanges.isEmpty, isTrue);
    },
  );
}
