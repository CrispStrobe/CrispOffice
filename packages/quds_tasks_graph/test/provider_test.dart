import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_graph/quds_tasks_graph.dart';
import 'package:test/test.dart';

void main() {
  late TaskAccountId account;
  late TaskListId list;
  late TaskId task;
  late _Transport transport;
  late _Tokens tokens;
  late GraphTaskProvider provider;

  setUp(() {
    account = TaskAccountId('account-a', provider: 'microsoftGraph');
    list = TaskListId('list-a', account: account);
    task = TaskId('task-a', list: list);
    transport = _Transport();
    tokens = _Tokens();
    provider = GraphTaskProvider(
      account: account,
      transport: transport,
      tokens: tokens,
    );
  });

  test(
    'lists ordinary and protected flagged-email lists, retaining metadata',
    () async {
      transport.replies.add(
        _json({
          'value': [
            {'id': 'list-a', 'displayName': 'Work', 'isShared': true},
            {
              'id': 'flagged',
              'displayName': 'Flagged email',
              'wellknownListName': 'flaggedEmails',
            },
          ],
        }),
      );
      final page = _success(await provider.listTaskLists());
      expect(page.lists.first.id.account, account);
      expect(page.lists.first.readOnly, isFalse);
      expect(page.lists.last.readOnly, isTrue);
      expect(page.lists.first.providerData!.raw, contains('isShared'));
      expect(transport.requests.single.uri.path, '/v1.0/me/todo/lists');
    },
  );

  test('list delta distinguishes ID-only tombstones and checkpoint', () async {
    transport.replies.add(
      _json({
        'value': [
          {'id': 'list-a', 'displayName': 'Work'},
          {
            'id': 'removed',
            '@removed': {'reason': 'deleted'},
          },
        ],
        '@odata.deltaLink':
            'https://graph.microsoft.com/v1.0/me/todo/lists/delta?\$deltatoken=opaque',
      }),
    );
    final page = _success(await provider.pullListChanges());
    expect(page.upserts.single.id, list);
    expect(page.tombstones.single.value, 'removed');
    expect(page.complete, isTrue);
    expect(page.checkpoint, isNotNull);
    expect(
      transport.requests.single.uri.queryParameters.containsKey(r'$top'),
      isFalse,
    );
  });

  test('empty delta page continues and exact opaque link is retained', () async {
    const next =
        'https://graph.microsoft.com/v1.0/me/todo/lists/list-a/tasks/delta?\$skiptoken=opaque%2B%2F%3D';
    transport.replies.addAll([
      _json({'value': [], '@odata.nextLink': next}),
      _json({
        'value': [
          _task(),
          {
            'id': 'gone',
            '@removed': {'reason': 'deleted'},
          },
        ],
        '@odata.deltaLink': _delta,
      }),
    ]);
    final first = _success(await provider.pullTaskChanges(list));
    expect(first.upserts, isEmpty);
    expect(first.complete, isFalse);
    expect(first.checkpoint, isNull);
    final second = _success(
      await provider.pullTaskChanges(list, cursor: first.nextCursor),
    );
    expect(transport.requests.last.uri.toString(), next);
    expect(second.upserts.single.id, task);
    expect(second.tombstones.single.value, 'gone');
    expect(second.complete, isTrue);
    expect(second.checkpoint, isNotNull);
  });

  test('delta requires exactly one next link or checkpoint', () async {
    for (final data in <Map<String, Object?>>[
      {'value': []},
      {'value': [], '@odata.nextLink': _delta, '@odata.deltaLink': _delta},
    ]) {
      transport.replies.add(_json(data));
      expect(
        _failure(await provider.pullTaskChanges(list)).code,
        TaskProblemCode.invalidResponse,
      );
    }
  });

  test('task delta keeps final observed event when an ID repeats', () async {
    final removed = <String, Object?>{
      'id': 'task-a',
      '@removed': {'reason': 'deleted'},
    };
    transport.replies.addAll([
      _json({
        'value': [_task(), removed],
        '@odata.deltaLink': _delta,
      }),
      _json({
        'value': [removed, _task()],
        '@odata.deltaLink': _delta,
      }),
    ]);
    final deleted = _success(await provider.pullTaskChanges(list));
    expect(deleted.upserts, isEmpty);
    expect(deleted.tombstones, [task]);
    final restored = _success(await provider.pullTaskChanges(list));
    expect(restored.upserts.single.id, task);
    expect(restored.tombstones, isEmpty);
  });

  test('list delta keeps final event and forwards requested page size', () async {
    final removed = <String, Object?>{
      'id': 'list-a',
      '@removed': {'reason': 'deleted'},
    };
    final entry = <String, Object?>{'id': 'list-a', 'displayName': 'Work'};
    const checkpoint =
        'https://graph.microsoft.com/v1.0/me/todo/lists/delta?\$deltatoken=opaque';
    transport.replies.addAll([
      _json({
        'value': [entry, removed],
        '@odata.deltaLink': checkpoint,
      }),
      _json({
        'value': [removed, entry],
        '@odata.deltaLink': checkpoint,
      }),
    ]);
    final deleted = _success(await provider.pullListChanges(limit: 7));
    expect(deleted.upserts, isEmpty);
    expect(deleted.tombstones, [list]);
    expect(transport.requests.single.headers['Prefer'], 'odata.maxpagesize=7');
    final restored = _success(await provider.pullListChanges(limit: 7));
    expect(restored.upserts.single.id, list);
    expect(restored.tombstones, isEmpty);
  });

  test('foreign response cursor is rejected without following it', () async {
    transport.replies.add(
      _json({'value': [], '@odata.nextLink': 'https://evil.invalid/steal'}),
    );
    expect(
      _failure(await provider.pullTaskChanges(list)).code,
      TaskProblemCode.invalidResponse,
    );
    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.uri.host, 'graph.microsoft.com');
  });

  test(
    'cursor is account, operation, collection and origin scoped before token access',
    () async {
      transport.replies.add(_json({'value': [], '@odata.deltaLink': _delta}));
      final cursor = _success(await provider.pullTaskChanges(list)).checkpoint!;
      final before = tokens.refreshes.length;
      final otherList = TaskListId('different', account: account);
      expect(
        _failure(
          await provider.pullTaskChanges(otherList, cursor: cursor),
        ).code,
        TaskProblemCode.invalidInput,
      );
      expect(
        _failure(await provider.listTaskLists(cursor: cursor)).code,
        TaskProblemCode.invalidInput,
      );
      final otherTokens = _Tokens();
      final other = GraphTaskProvider(
        account: TaskAccountId('other', provider: 'microsoftGraph'),
        transport: transport,
        tokens: otherTokens,
      );
      expect(
        _failure(
          await other.pullTaskChanges(
            TaskListId('list-a', account: other.account),
            cursor: cursor,
          ),
        ).code,
        TaskProblemCode.invalidInput,
      );
      final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(cursor)));
      final envelope = Map<String, Object?>.from(
        decoded! as Map<String, Object?>,
      );
      envelope['url'] =
          'https://graph.microsoft.com.evil.invalid/v1.0/me/todo/lists/list-a/tasks/delta';
      final tampered = base64Url.encode(utf8.encode(jsonEncode(envelope)));
      expect(
        _failure(await provider.pullTaskChanges(list, cursor: tampered)).code,
        TaskProblemCode.invalidInput,
      );
      expect(tokens.refreshes.length, before);
      expect(otherTokens.refreshes, isEmpty);
      expect(transport.requests, hasLength(1));
    },
  );

  test('encodes remote IDs as single path segments', () async {
    final specialList = TaskListId('list/+ =ü', account: account);
    final specialTask = TaskId('task/+ =ß', list: specialList);
    transport.replies.add(_json(_task(id: specialTask.value)));
    expect(_success(await provider.getTask(specialTask))!.id, specialTask);
    expect(transport.requests.single.uri.pathSegments, [
      'v1.0',
      'me',
      'todo',
      'lists',
      specialList.value,
      'tasks',
      specialTask.value,
    ]);
    expect(transport.requests.single.uri.toString(), contains('%2F'));
  });

  test(
    'preserves wall time, zone, HTML, status and unsupported provider fields',
    () async {
      transport.replies.add(
        _json(
          _task(
            extra: {
              'status': 'waitingOnOthers',
              'body': {'contentType': 'html', 'content': '<b>Keep this</b>'},
              'dueDateTime': {
                'dateTime': '2026-03-29T00:00:00.0000000',
                'timeZone': 'Europe/Berlin',
              },
              'recurrence': {
                'pattern': {'type': 'daily', 'interval': 1},
              },
              'categories': ['Original'],
            },
          ),
        ),
      );
      final value = _success(await provider.getTask(task))!;
      expect(value.fields.status, TaskStatus.waitingOnOthers);
      expect(
        value.fields.notes,
        const TaskText('<b>Keep this</b>', format: TaskTextFormat.html),
      );
      final due = value.fields.due! as TaskDateTime;
      expect(due.localDateTime, '2026-03-29T00:00:00.0000000');
      expect(due.timeZone, 'Europe/Berlin');
      expect(value.providerData!.raw, contains('recurrence'));
      expect(value.providerData!.raw, contains('Original'));
      expect(value.revision, 'W/"version-1"');
    },
  );

  test(
    'unknown status fails rather than silently rewriting it as notStarted',
    () async {
      transport.replies.add(_json(_task(extra: {'status': 'futureStatus'})));
      expect(
        _failure(await provider.getTask(task)).code,
        TaskProblemCode.unsupported,
      );
    },
  );

  test(
    'sparse title update does not send notes, dates, recurrence or defaults',
    () async {
      transport.replies.add(_json(_task(extra: {'title': 'Renamed'})));
      _success(
        await provider.updateTask(
          task,
          const TaskPatch(title: TaskFieldPatch.set('Renamed')),
        ),
      );
      expect(_body(transport.requests.single), {'title': 'Renamed'});
      expect(transport.requests.single.method, 'PATCH');
    },
  );

  test(
    'cleared due date differs from unchanged fields; reminder clear is explicit',
    () async {
      transport.replies.add(_json(_task()));
      _success(
        await provider.updateTask(
          task,
          const TaskPatch(
            due: TaskFieldPatch.clear(),
            reminder: TaskFieldPatch.clear(),
          ),
        ),
      );
      expect(_body(transport.requests.single), {
        'dueDateTime': null,
        'isReminderOn': false,
        'reminderDateTime': null,
      });
    },
  );

  test(
    'date-only writes use an explicit zone and never host-local conversion',
    () async {
      final configured = GraphTaskProvider(
        account: account,
        transport: transport,
        tokens: tokens,
        dateOnlyTimeZone: 'Europe/Berlin',
      );
      transport.replies.add(_json(_task()));
      _success(
        await configured.updateTask(
          task,
          TaskPatch(due: TaskFieldPatch.set(TaskDate(2026, 10, 25))),
        ),
      );
      expect(_body(transport.requests.single)['dueDateTime'], {
        'dateTime': '2026-10-25T00:00:00',
        'timeZone': 'Europe/Berlin',
      });
      final unsupported = await provider.updateTask(
        task,
        TaskPatch(due: TaskFieldPatch.set(TaskDateTime('2026-10-25T01:00:00'))),
      );
      expect(_failure(unsupported).code, TaskProblemCode.unsupported);
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'plain notes become escaped HTML and HTML notes remain unchanged',
    () async {
      transport.replies.addAll([_json(_task()), _json(_task())]);
      _success(
        await provider.updateTask(
          task,
          const TaskPatch(
            notes: TaskFieldPatch.set(TaskText('<script>&\nNext')),
          ),
        ),
      );
      expect(_body(transport.requests.first)['body'], {
        'contentType': 'html',
        'content': '<div>&lt;script&gt;&amp;<br>Next</div>',
      });
      _success(
        await provider.updateTask(
          task,
          const TaskPatch(
            notes: TaskFieldPatch.set(
              TaskText('<p>Original</p>', format: TaskTextFormat.html),
            ),
          ),
        ),
      );
      expect(_body(transport.requests.last)['body'], {
        'contentType': 'html',
        'content': '<p>Original</p>',
      });
    },
  );

  test(
    'unverified conditional writes, cancelled status and empty updates are rejected',
    () async {
      expect(
        provider.capabilities.supports(TaskCapability.conditionalWrites),
        isFalse,
      );
      expect(
        _failure(
          await provider.updateTask(
            task,
            const TaskPatch(title: TaskFieldPatch.set('New')),
            expectedRevision: 'version',
          ),
        ).code,
        TaskProblemCode.unsupported,
      );
      expect(
        _failure(
          await provider.deleteTask(task, expectedRevision: 'version'),
        ).code,
        TaskProblemCode.unsupported,
      );
      expect(
        _failure(
          await provider.updateTask(
            task,
            const TaskPatch(status: TaskFieldPatch.set(TaskStatus.cancelled)),
          ),
        ).code,
        TaskProblemCode.unsupported,
      );
      expect(
        _failure(await provider.updateTask(task, const TaskPatch())).code,
        TaskProblemCode.invalidInput,
      );
      expect(tokens.refreshes, isEmpty);
      expect(transport.requests, isEmpty);
    },
  );

  test('recurring completion and reopening are blocked before PATCH', () async {
    transport.replies.addAll([
      _json(
        _task(
          extra: {
            'recurrence': {
              'pattern': {'type': 'daily'},
            },
          },
        ),
      ),
      _json(
        _task(
          extra: {
            'recurrence': {
              'pattern': {'type': 'daily'},
            },
          },
        ),
      ),
    ]);
    for (final status in [TaskStatus.completed, TaskStatus.notStarted]) {
      final failure = _failure(
        await provider.updateTask(
          task,
          TaskPatch(status: TaskFieldPatch.set(status)),
        ),
      );
      expect(failure.code, TaskProblemCode.unsupported);
      expect(failure.mutationMayHaveOccurred, isFalse);
    }
    expect(transport.requests.map((request) => request.method), ['GET', 'GET']);
  });

  test(
    'ordinary completion performs a fresh recurrence check then a sparse PATCH',
    () async {
      transport.replies.addAll([
        _json(_task()),
        _json(_task(extra: {'status': 'completed'})),
      ]);
      final result = _success(
        await provider.updateTask(
          task,
          const TaskPatch(status: TaskFieldPatch.set(TaskStatus.completed)),
        ),
      );
      expect(result.fields.status, TaskStatus.completed);
      expect(transport.requests.map((request) => request.method), [
        'GET',
        'PATCH',
      ]);
      expect(_body(transport.requests.last), {'status': 'completed'});
    },
  );

  test(
    'create embeds one static extension with durable operation identity',
    () async {
      transport.replies.add(_json(_task(), status: 201));
      final created = _success(
        await provider.createTask(
          list,
          const TaskFields(title: 'Task'),
          operationId: 'operation-1',
          localTaskId: 'local-1',
        ),
      );
      expect(created.id, task);
      final body = _body(transport.requests.single);
      final extensions = body['extensions']! as List<Object?>;
      expect(extensions, hasLength(1));
      expect(extensions.single, {
        '@odata.type': 'microsoft.graph.openTypeExtension',
        'extensionName': GraphTaskProvider.createMarkerName,
        'version': 1,
        'operationId': 'operation-1',
        'localTaskId': 'local-1',
      });
    },
  );

  test(
    'lost create response is uncertain and recovered with GET, never another POST',
    () async {
      transport.replies.addAll([
        TimeoutException('not surfaced'),
        _json({
          'value': [
            _task(
              extra: {
                'extensions': [
                  {
                    'extensionName': GraphTaskProvider.createMarkerName,
                    'version': 1,
                    'operationId': 'operation-1',
                    'localTaskId': 'local-1',
                  },
                ],
              },
            ),
          ],
        }),
      ]);
      final failure = _failure(
        await provider.createTask(
          list,
          const TaskFields(title: 'Task'),
          operationId: 'operation-1',
          localTaskId: 'local-1',
        ),
      );
      expect(failure.code, TaskProblemCode.unavailable);
      expect(failure.mutationMayHaveOccurred, isTrue);
      final recovered = _success(
        await provider.findCreateOperation(
          list,
          operationId: 'operation-1',
          localTaskId: 'local-1',
        ),
      );
      expect(recovered.matches.single.id, task);
      expect(transport.requests.map((request) => request.method), [
        'POST',
        'GET',
      ]);
      expect(
        transport.requests.last.uri.queryParameters[r'$expand'],
        contains(GraphTaskProvider.createMarkerName),
      );
    },
  );

  test(
    'recovery retains empty continuation and multiple matches for host conflict handling',
    () async {
      const next =
          'https://graph.microsoft.com/v1.0/me/todo/lists/list-a/tasks?\$skiptoken=next';
      final marker = {
        'extensionName': GraphTaskProvider.createMarkerName,
        'version': 1,
        'operationId': 'operation-1',
        'localTaskId': 'local-1',
      };
      transport.replies.addAll([
        _json({'value': [], '@odata.nextLink': next}),
        _json({
          'value': [
            _task(
              id: 'first',
              extra: {
                'extensions': [marker],
              },
            ),
            _task(
              id: 'second',
              extra: {
                'extensions': [marker],
              },
            ),
          ],
        }),
      ]);
      final first = _success(
        await provider.findCreateOperation(
          list,
          operationId: 'operation-1',
          localTaskId: 'local-1',
        ),
      );
      expect(first.matches, isEmpty);
      expect(first.nextCursor, isNotNull);
      final second = _success(
        await provider.findCreateOperation(
          list,
          operationId: 'operation-1',
          localTaskId: 'local-1',
          cursor: first.nextCursor,
        ),
      );
      expect(second.matches, hasLength(2));
      expect(second.nextCursor, isNull);
    },
  );

  test('safe GET refreshes once; writes never refresh or retry', () async {
    transport.replies.addAll([
      _json({}, status: 401),
      _json(_task()),
      _json({}, status: 401),
    ]);
    _success(await provider.getTask(task));
    expect(tokens.refreshes, [false, true]);
    expect(
      transport.requests[0].headers['Authorization'],
      'Bearer initial-token',
    );
    expect(
      transport.requests[1].headers['Authorization'],
      'Bearer refreshed-token',
    );
    final problem = _failure(
      await provider.updateTask(
        task,
        const TaskPatch(title: TaskFieldPatch.set('Changed')),
      ),
    );
    expect(problem.code, TaskProblemCode.authenticationRequired);
    expect(problem.mutationMayHaveOccurred, isFalse);
    expect(tokens.refreshes, [false, true, false]);
    expect(transport.requests, hasLength(3));
  });

  test('persistent 401 stops after one safe read refresh', () async {
    transport.replies.addAll([_json({}, status: 401), _json({}, status: 401)]);
    expect(
      _failure(await provider.getTask(task)).code,
      TaskProblemCode.authenticationRequired,
    );
    expect(tokens.refreshes, [false, true]);
    expect(transport.requests, hasLength(2));
  });

  test('explicit HTTP failures are typed, bounded and not retried', () async {
    for (final pair in <(int, TaskProblemCode)>[
      (403, TaskProblemCode.permissionDenied),
      (409, TaskProblemCode.conflict),
      (412, TaskProblemCode.conflict),
      (503, TaskProblemCode.unavailable),
    ]) {
      transport.replies.add(_json({}, status: pair.$1));
      final problem = _failure(
        await provider.updateTask(
          task,
          const TaskPatch(title: TaskFieldPatch.set('Changed')),
        ),
      );
      expect(problem.code, pair.$2);
      expect(problem.mutationMayHaveOccurred, pair.$1 == 503);
    }
    expect(transport.requests, hasLength(4));
  });

  test('429 retains Retry-After without retrying', () async {
    transport.replies.add(
      _json({}, status: 429, headers: {'Retry-After': '42'}),
    );
    final failure = _failure(await provider.getTask(task));
    expect(failure.code, TaskProblemCode.throttled);
    expect(failure.retryAfter, const Duration(seconds: 42));
    expect(transport.requests, hasLength(1));
  });

  test('HTTP-date Retry-After uses an injected clock', () async {
    final clocked = GraphTaskProvider(
      account: account,
      transport: transport,
      tokens: tokens,
      clock: () => DateTime.utc(2026, 11, 25, 12),
    );
    transport.replies.add(
      _json(
        {},
        status: 429,
        headers: {'retry-after': 'Wed, 25 Nov 2026 12:00:15 GMT'},
      ),
    );
    expect(
      _failure(await clocked.getTask(task)).retryAfter,
      const Duration(seconds: 15),
    );
  });

  test(
    'expired delta never masquerades as an empty successful collection',
    () async {
      transport.replies.addAll([
        _json({}, status: 410),
        _json({
          'error': {'code': 'SyncStateNotFound'},
        }, status: 400),
      ]);
      expect(
        _failure(await provider.pullTaskChanges(list)).code,
        TaskProblemCode.cursorExpired,
      );
      expect(
        _failure(await provider.pullListChanges()).code,
        TaskProblemCode.cursorExpired,
      );
    },
  );

  test(
    'successful write with malformed JSON is uncertain; known pre-send failure is not',
    () async {
      transport.replies.addAll([
        GraphTaskHttpResponse(statusCode: 201, body: utf8.encode('{broken')),
        const GraphTaskTransportException(
          GraphTaskTransportProblem.unavailable,
          requestMayHaveReachedServer: false,
        ),
      ]);
      final malformed = _failure(
        await provider.createTask(
          list,
          const TaskFields(title: 'Task'),
          operationId: 'op-1',
          localTaskId: 'local-1',
        ),
      );
      expect(malformed.code, TaskProblemCode.invalidResponse);
      expect(malformed.mutationMayHaveOccurred, isTrue);
      final presend = _failure(await provider.deleteTask(task));
      expect(presend.mutationMayHaveOccurred, isFalse);
    },
  );

  test('request and response budgets fail closed', () async {
    final bounded = GraphTaskProvider(
      account: account,
      transport: transport,
      tokens: tokens,
      limits: GraphTaskLimits(maxRequestBytes: 128, maxResponseBytes: 1024),
    );
    final large = await bounded.createTask(
      list,
      TaskFields(title: 'x' * 256),
      operationId: 'op',
      localTaskId: 'local',
    );
    expect(_failure(large).code, TaskProblemCode.invalidInput);
    expect(tokens.refreshes, isEmpty);
    transport.replies.add(
      GraphTaskHttpResponse(statusCode: 200, body: List.filled(1025, 32)),
    );
    expect(
      _failure(await bounded.getTask(task)).code,
      TaskProblemCode.invalidResponse,
    );
    expect(transport.responseLimits.single, 1024);
  });

  test(
    'page item budget and incomplete task rows cannot advance a cursor',
    () async {
      final bounded = GraphTaskProvider(
        account: account,
        transport: transport,
        tokens: tokens,
        limits: GraphTaskLimits(maxPageSize: 1, maxResponseItems: 1),
      );
      transport.replies.addAll([
        _json({
          'value': [_task(), _task(id: 'second')],
          '@odata.deltaLink': _delta,
        }),
        _json({
          'value': [
            {'id': 'task-a', 'status': 'completed'},
          ],
          '@odata.deltaLink': _delta,
        }),
      ]);
      expect(
        _failure(await bounded.pullTaskChanges(list, limit: 1)).code,
        TaskProblemCode.invalidResponse,
      );
      expect(
        _failure(await bounded.pullTaskChanges(list, limit: 1)).code,
        TaskProblemCode.invalidResponse,
      );
    },
  );

  test(
    '204 delete does not parse JSON; 404 get means unobserved, not deleted',
    () async {
      transport.replies.addAll([
        GraphTaskHttpResponse(statusCode: 204),
        _json({}, status: 404),
      ]);
      expect(_success(await provider.deleteTask(task)), TaskUnit.value);
      expect(_success(await provider.getTask(task)), isNull);
    },
  );

  test('diagnostic strings do not expose tokens, URLs or task text', () async {
    transport.replies.add(_json(_task()));
    final remote = _success(await provider.getTask(task))!;
    final request = transport.requests.single;
    for (final value in [
      request.toString(),
      remote.toString(),
      remote.providerData.toString(),
    ]) {
      expect(value, isNot(contains('initial-token')));
      expect(value, isNot(contains('graph.microsoft.com')));
      expect(value, isNot(contains('Private task title')));
    }
  });
}

const _delta =
    'https://graph.microsoft.com/v1.0/me/todo/lists/list-a/tasks/delta?\$deltatoken=checkpoint';

Map<String, Object?> _task({
  String id = 'task-a',
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'title': 'Private task title',
  'status': 'notStarted',
  'importance': 'normal',
  '@odata.etag': 'W/"version-1"',
  'isReminderOn': false,
  'body': {'contentType': 'text', 'content': ''},
  ...extra,
};

GraphTaskHttpResponse _json(
  Map<String, Object?> value, {
  int status = 200,
  Map<String, String> headers = const {},
}) => GraphTaskHttpResponse(
  statusCode: status,
  headers: headers,
  body: utf8.encode(jsonEncode(value)),
);

Map<String, Object?> _body(GraphTaskHttpRequest request) =>
    jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;

T _success<T>(TaskResult<T> result) {
  if (result is TaskSuccess<T>) return result.value;
  throw TestFailure(
    'Expected success; got ${(result as TaskFailure<T>).problem.code}.',
  );
}

TaskProblem _failure<T>(TaskResult<T> result) {
  if (result is TaskFailure<T>) return result.problem;
  throw TestFailure('Expected failure.');
}

final class _Tokens implements GraphTaskTokenSource {
  final List<bool> refreshes = [];

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    refreshes.add(forceRefresh);
    return forceRefresh ? 'refreshed-token' : 'initial-token';
  }
}

final class _Transport implements GraphTaskHttpTransport {
  final Queue<Object> replies = Queue<Object>();
  final List<GraphTaskHttpRequest> requests = [];
  final List<int> responseLimits = [];

  @override
  Future<GraphTaskHttpResponse> send(
    GraphTaskHttpRequest request, {
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    requests.add(request);
    responseLimits.add(maxResponseBytes);
    final reply = replies.removeFirst();
    if (reply is GraphTaskHttpResponse) return reply;
    throw reply;
  }
}
