import 'dart:async';
import 'dart:io';

import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

final _account = TaskAccountId('account', provider: 'test');
final _list = TaskListId('list', account: _account);

RemoteTask _task(String id, {String? revision, TaskListId? list}) => RemoteTask(
  id: TaskId(id, list: list ?? _list),
  revision: revision,
  fields: TaskFields(
    title: id,
    notes: const TaskText('<p>Ä</p>', format: TaskTextFormat.html),
    start: TaskDate(2026, 11, 25),
    due: TaskDateTime('2026-11-26T12:00:00.023', timeZone: 'Europe/Berlin'),
    reminder: TaskDateTime('2026-11-25T08:00:00'),
  ),
  providerData: TaskProviderData(
    format: 'application/json',
    raw: '{"unknown":true}',
  ),
);

T _success<T>(TaskResult<T> result) {
  expect(result, isA<TaskSuccess<T>>());
  return (result as TaskSuccess<T>).value;
}

TaskProblemCode _failure<T>(TaskResult<T> result) =>
    (result as TaskFailure<T>).problem.code;

TaskSyncPage _page({
  List<RemoteTask> upserts = const [],
  List<TaskId> tombstones = const [],
  String? next,
  String? checkpoint,
  bool reset = false,
  TaskListId? list,
}) => TaskSyncPage(
  list: list ?? _list,
  upserts: upserts,
  tombstones: tombstones,
  nextCursor: next,
  checkpoint: checkpoint,
  resetRequired: reset,
);

List<String> _ids(TaskPullStore store, [TaskListId? list]) =>
    _success(store.tasks(list ?? _list)).map((task) => task.id.value).toList();

void main() {
  late TaskPullStore store;
  late TaskAccountLease lease;

  setUp(() {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    store = TaskPullStore(database);
    lease = _success(store.connect(_account));
  });

  test(
    'resumes a paginated round after reopening the SQLite database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'quds-tasks-store-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/tasks.sqlite';
      final first = sqlite3.open(path);
      try {
        final store = TaskPullStore(first);
        final lease = _success(store.connect(_account));
        final worker = TaskPullWorker(store);
        expect(
          _success(
            await worker.refresh(lease, _list, (position) async {
              expect(position.cursor, isNull);
              expect(position.baseline, isTrue);
              return TaskSuccess(
                _page(
                  upserts: [_task('first', revision: 'one')],
                  next: 'page-2',
                ),
              );
            }, maxPages: 1),
          ),
          isFalse,
        );
      } finally {
        first.close();
      }
      final reopened = sqlite3.open(path);
      addTearDown(reopened.close);
      final store = TaskPullStore(reopened);
      final lease = _success(store.connect(_account));
      final worker = TaskPullWorker(store);
      expect(
        _success(
          await worker.refresh(lease, _list, (position) async {
            expect(position.cursor, 'page-2');
            expect(position.baseline, isTrue);
            expect(position.knownRevisions, isEmpty);
            return TaskSuccess(
              _page(upserts: [_task('second')], checkpoint: 'delta-1'),
            );
          }),
        ),
        isTrue,
      );
      expect(_ids(store), ['first', 'second']);
      final item = _success(store.tasks(_list)).first;
      final expected = _task('first', revision: 'one');
      expect(item.fields, expected.fields);
      expect(item.revision, expected.revision);
      expect(item.providerData?.raw, expected.providerData?.raw);
      expect(item.providerData?.format, expected.providerData?.format);
      final position = _success(store.position(lease, _list));
      expect(position.cursor, 'delta-1');
      expect(position.knownRevisions[item.id], 'one');
    },
  );

  test('rebaseline keeps unseen tasks until the final page commits', () async {
    final worker = TaskPullWorker(store);
    final a = _task('a');
    final b = _task('b');
    _success(
      store.apply(
        _success(store.position(lease, _list)),
        _page(upserts: [a, b], checkpoint: 'expired'),
      ),
    );
    expect(
      _success(
        await worker.refresh(lease, _list, (position) async {
          expect(position.cursor, 'expired');
          return const TaskFailure(TaskProblem(TaskProblemCode.cursorExpired));
        }, maxPages: 1),
      ),
      isFalse,
    );
    expect(_ids(store), ['a', 'b']);
    expect(
      _success(
        await worker.refresh(lease, _list, (position) async {
          expect(position.cursor, isNull);
          return TaskSuccess(_page(upserts: [b], next: 'next'));
        }, maxPages: 1),
      ),
      isFalse,
    );
    expect(_ids(store), ['a', 'b']);
    final failed = await worker.refresh(
      lease,
      _list,
      (_) async =>
          const TaskFailure(TaskProblem(TaskProblemCode.permissionDenied)),
    );
    expect(_failure(failed), TaskProblemCode.permissionDenied);
    expect(_ids(store), ['a', 'b']);
    expect(_success(store.position(lease, _list)).cursor, 'next');

    expect(
      _success(
        await worker.refresh(
          lease,
          _list,
          (_) async => TaskSuccess(_page(checkpoint: 'new')),
        ),
      ),
      isTrue,
    );
    expect(_ids(store), ['b']);
  });

  test(
    'snapshot-only rounds prune absent rows on each successful snapshot',
    () {
      final a = _task('a');
      final b = _task('b');
      _success(
        store.apply(
          _success(store.position(lease, _list)),
          _page(upserts: [a, b]),
        ),
      );
      expect(_ids(store), ['a', 'b']);
      final second = _success(store.position(lease, _list));
      expect(second.baseline, isTrue);
      expect(second.cursor, isNull);
      _success(store.apply(second, _page(upserts: [a])));
      expect(_ids(store), ['a']);
    },
  );

  test('a duplicate page item rolls back both the rows and the cursor', () {
    final position = _success(store.position(lease, _list));
    final a = _task('a');
    final failed = store.apply(
      position,
      _page(upserts: [a], tombstones: [a.id], checkpoint: 'bad'),
    );
    expect(_failure(failed), TaskProblemCode.invalidResponse);
    expect(_ids(store), isEmpty);
    expect(_success(store.position(lease, _list)).cursor, isNull);
    _success(store.apply(position, _page(upserts: [a], checkpoint: 'good')));
    expect(_ids(store), ['a']);
  });

  test(
    'concurrent commits only apply once and incremental absence retains rows',
    () {
      final a = _task('a');
      final before = _success(store.position(lease, _list));
      final rival = _success(store.position(lease, _list));
      _success(store.apply(before, _page(upserts: [a], checkpoint: 'good')));
      expect(
        _failure(store.apply(rival, _page(checkpoint: 'bad'))),
        TaskProblemCode.staleOperation,
      );
      final started = _success(store.position(lease, _list));
      _success(store.apply(started, _page(checkpoint: 'next')));
      expect(_ids(store), ['a']);
      _success(
        store.apply(
          _success(store.position(lease, _list)),
          _page(tombstones: [a.id], checkpoint: 'last'),
        ),
      );
      expect(_ids(store), isEmpty);
    },
  );

  test('disconnect fences in-flight work across database handles', () async {
    final directory = await Directory.systemTemp.createTemp(
      'quds-tasks-fence-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/tasks.sqlite';
    final one = sqlite3.open(path);
    final two = sqlite3.open(path);
    addTearDown(one.close);
    addTearDown(two.close);
    final first = TaskPullStore(one);
    final second = TaskPullStore(two);
    final old = _success(first.connect(_account));
    final inFlight = Completer<TaskResult<TaskSyncPage>>();
    final started = Completer<void>();
    final pending = TaskPullWorker(first).refresh(old, _list, (_) {
      started.complete();
      return inFlight.future;
    });
    await started.future;
    _success(second.disconnect(old));
    final fresh = _success(second.connect(_account));
    expect(fresh.generation, greaterThan(old.generation));
    inFlight.complete(
      TaskSuccess(_page(upserts: [_task('late')], checkpoint: 'bad')),
    );
    expect(_failure(await pending), TaskProblemCode.staleOperation);
    expect(_ids(second), isEmpty);
  });

  test('list, account and database scopes are independent', () {
    final secondAccount = TaskAccountId('other', provider: _account.provider);
    final secondList = TaskListId(_list.value, account: secondAccount);
    final secondLease = _success(store.connect(secondAccount));
    expect(
      _failure(store.position(lease, secondList)),
      TaskProblemCode.invalidInput,
    );
    final row = _task('a', list: secondList);
    _success(
      store.apply(
        _success(store.position(secondLease, secondList)),
        _page(upserts: [row], checkpoint: 'token', list: secondList),
      ),
    );
    expect(_ids(store), isEmpty);
    expect(_ids(store, secondList), ['a']);
    final separate = sqlite3.openInMemory();
    addTearDown(separate.close);
    final otherStore = TaskPullStore(separate);
    _success(otherStore.connect(_account));
    expect(
      _failure(otherStore.position(lease, _list)),
      TaskProblemCode.staleOperation,
    );
  });
}
