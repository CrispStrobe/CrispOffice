import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

void main() {
  final account = TaskAccountId('account', provider: 'graph');
  final list = TaskListId('list', account: account);
  final id = TaskId('task', list: list);

  test('identities include provider, account and list at every level', () {
    final same = TaskAccountId('account', provider: 'graph');
    expect(account, same);
    expect(account.hashCode, same.hashCode);
    expect(account, isNot(TaskAccountId('account', provider: 'caldav')));
    expect(
      id,
      isNot(TaskId('task', list: TaskListId('other', account: account))),
    );
    expect(
      list,
      isNot(
        TaskListId('list', account: TaskAccountId('other', provider: 'graph')),
      ),
    );
    expect(() => TaskAccountId('', provider: 'graph'), throwsArgumentError);
    expect(() => TaskId('line\nbreak', list: list), throwsArgumentError);
    expect(id.toString(), isNot(contains('task')));
  });

  test(
    'civil dates retain date-only semantics and reject normalized overflow',
    () {
      expect(TaskDate(2024, 2, 29), TaskDate(2024, 2, 29));
      expect(() => TaskDate(2023, 2, 29), throwsArgumentError);
      expect(() => TaskDate(1900, 2, 29), throwsArgumentError);
      expect(TaskDate(2000, 2, 29).day, 29);
      expect(() => TaskDate(2026, 13, 1), throwsArgumentError);
      expect(() => TaskDate(2026, 4, 31), throwsArgumentError);
      expect(() => TaskDate(0, 1, 1), throwsArgumentError);
      expect(
        TaskDate(2026, 11, 25),
        isNot(TaskDateTime('2026-11-25T00:00:00', timeZone: 'UTC')),
      );
    },
  );

  test(
    'wall times preserve provider timezone names without machine conversion',
    () {
      final time = TaskDateTime(
        '2026-10-25T02:30:00.0000000',
        timeZone: 'Europe/Berlin',
      );
      final equivalent = TaskDateTime(
        '2026-10-25T02:30:00',
        timeZone: 'Europe/Berlin',
      );
      expect(time.localDateTime, '2026-10-25T02:30:00.0000000');
      expect(time.timeZone, 'Europe/Berlin');
      expect(time, equivalent);
      expect(time.hashCode, equivalent.hashCode);
      expect(time, isNot(TaskDateTime('2026-10-25T02:30:00')));
      expect(time, isNot(TaskDateTime('2026-10-25T02:30:00', timeZone: 'UTC')));
      expect(() => TaskDateTime('2026-11-25T25:00:00'), throwsArgumentError);
      expect(() => TaskDateTime('2026-11-25T12:00:00Z'), throwsArgumentError);
      expect(
        () => TaskDateTime('2026-11-25T12:00:00+01:00'),
        throwsArgumentError,
      );
      expect(
        () => TaskDateTime('2026-11-25T12:00:00', timeZone: ''),
        throwsArgumentError,
      );
    },
  );

  test(
    'a sparse patch distinguishes omitted, set and explicitly cleared fields',
    () {
      final before = TaskFields(
        title: 'Original',
        notes: const TaskText('<b>Keep</b>', format: TaskTextFormat.html),
        due: TaskDate(2026, 12, 1),
      );
      const patch = TaskPatch(
        title: TaskFieldPatch.set('Changed'),
        due: TaskFieldPatch.clear(),
      );
      final after = patch.applyTo(before);
      expect(after.title, 'Changed');
      expect(after.notes, before.notes);
      expect(after.due, isNull);
      expect(patch.notes.kind, TaskPatchKind.unchanged);
      expect(patch.changedFields, {TaskField.title, TaskField.due});
      final difference = TaskPatch.between(before, after);
      expect(difference.applyTo(before), after);
      expect(difference.notes.isChanged, isFalse);
      expect(difference.due.isClear, isTrue);
      expect(TaskPatch.between(after, after).isEmpty, isTrue);
    },
  );

  test(
    'required fields cannot be cleared and optional empty text is not null',
    () {
      const before = TaskFields(title: 'Task', notes: TaskText('Existing'));
      for (final patch in <TaskPatch>[
        const TaskPatch(title: TaskFieldPatch.clear()),
        const TaskPatch(status: TaskFieldPatch.clear()),
        const TaskPatch(priority: TaskFieldPatch.clear()),
      ]) {
        expect(() => patch.applyTo(before), throwsArgumentError);
      }
      final emptied = const TaskPatch(
        notes: TaskFieldPatch.set(TaskText('')),
      ).applyTo(before);
      final cleared = const TaskPatch(
        notes: TaskFieldPatch.clear(),
      ).applyTo(before);
      expect(emptied.notes, const TaskText(''));
      expect(cleared.notes, isNull);
      expect(emptied, isNot(cleared));
    },
  );

  test('provider payload is exact and its display omits personal content', () {
    const raw = '{ "unknown": [1, 2], "title": "private-title" }';
    final data = TaskProviderData(format: 'graph-json', raw: raw);
    final remote = RemoteTask(
      id: id,
      fields: const TaskFields(title: 'private-title'),
      providerData: data,
    );
    expect(remote.providerData!.raw, raw);
    expect(data.toString(), isNot(contains('private-title')));
    expect(remote.fields.toString(), isNot(contains('private-title')));
  });

  test(
    'sync pages own their lists and reject foreign account/list records',
    () {
      final remote = RemoteTask(
        id: id,
        fields: const TaskFields(title: 'Task'),
      );
      final upserts = <RemoteTask>[remote];
      final tombstones = <TaskId>[];
      final page = TaskSyncPage(
        list: list,
        upserts: upserts,
        tombstones: tombstones,
        checkpoint: 'opaque-checkpoint',
      );
      upserts.clear();
      tombstones.add(id);
      expect(page.upserts, [remote]);
      expect(page.tombstones, isEmpty);
      expect(() => page.upserts.clear(), throwsUnsupportedError);
      expect(page.complete, isTrue);
      expect(
        () => TaskSyncPage(
          list: TaskListId('other', account: account),
          upserts: [remote],
          tombstones: [],
        ),
        throwsArgumentError,
      );
      expect(
        () => TaskSyncPage(
          list: list,
          upserts: [],
          tombstones: [],
          nextCursor: 'next',
          checkpoint: 'done',
        ),
        throwsArgumentError,
      );
      expect(
        () => TaskListSyncPage(
          account: TaskAccountId('other', provider: 'graph'),
          upserts: [TaskList(id: list, name: 'Tasks')],
          tombstones: [],
        ),
        throwsArgumentError,
      );
    },
  );

  test('capabilities own their supported set', () {
    final input = <TaskCapability>{TaskCapability.listTasks};
    final capabilities = TaskCapabilities(input);
    input.add(TaskCapability.deleteTasks);
    expect(capabilities.supports(TaskCapability.listTasks), isTrue);
    expect(capabilities.supports(TaskCapability.deleteTasks), isFalse);
    expect(
      () => capabilities.supported.add(TaskCapability.deleteTasks),
      throwsUnsupportedError,
    );
  });
}
