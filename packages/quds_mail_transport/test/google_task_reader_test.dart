import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_transport/src/cloud/http.dart';
import 'package:quds_mail_transport/src/cloud/native/http.dart';
import 'package:quds_mail_transport/src/cloud/task_reader.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

final _account = TaskAccountId('fixture', provider: 'google');
final _mail = MailAccountId(
  'fixture',
  profile: MailProfileId('tasks', hostId: 'studio'),
);

T _value<T>(TaskResult<T> result) {
  expect(result, isA<TaskSuccess<T>>());
  return (result as TaskSuccess<T>).value;
}

final class _Tokens implements MailCloudTokenSource {
  var requests = 0;

  @override
  Future<MailResult<MailCloudAccessToken>> accessToken(
    MailOperationLease lease, {
    bool forceRefresh = false,
  }) async {
    requests++;
    return MailSuccess(
      MailCloudAccessToken(value: 'fixture', expiresAt: DateTime.utc(2035)),
    );
  }

  @override
  void dispose() {}
}

final class _Transport implements MailCloudHttpTransport {
  final requests = <MailCloudHttpRequest>[];
  final replies = <Object>[];

  @override
  Future<MailCloudHttpResponse> send(
    MailCloudHttpRequest request, {
    required MailOperationLease lease,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    requests.add(request);
    expect(NativeMailCloudHttpTransport.allowedUri(request.uri), isTrue);
    expect(request.headers['authorization'], 'Bearer fixture');
    final reply = replies.removeAt(0);
    if (reply is MailCloudException) throw reply;
    return reply is MailCloudHttpResponse
        ? reply
        : MailCloudHttpResponse(
            statusCode: 200,
            body: utf8.encode(jsonEncode(reply)),
          );
  }

  @override
  void close() {}
}

void main() {
  final session = MailAccountSession(_mail);
  late _Transport transport;
  late _Tokens tokens;
  late GoogleTaskReader reader;

  setUp(() {
    transport = _Transport();
    tokens = _Tokens();
    reader = ApiGoogleTaskReader(
      account: _account,
      mailAccount: _mail,
      tokens: tokens,
      transport: transport,
    );
  });

  GoogleTaskProvider writer() => ApiGoogleTaskReader(
    account: _account,
    mailAccount: _mail,
    tokens: tokens,
    transport: transport,
    enableWrites: true,
  );

  final list = TaskListId('personal', account: _account);
  final id = TaskId('task-1', list: list);

  Map<String, Object?> task({
    String revision = 'rev-1',
    String title = 'Fixture',
    String status = 'needsAction',
    bool assigned = false,
  }) => {
    'id': id.value,
    'etag': revision,
    'title': title,
    'status': status,
    if (assigned) 'assignmentInfo': {'surfaceType': 'SPACE'},
  };

  test('opt-in Google Tasks writes use a Tasks-only grant', () {
    final grant = MailOAuthConfiguration(
      service: MailCloudService.gmail,
      clientId: 'fixture',
      tasksOnly: true,
      googleTaskWrites: true,
    );
    expect(grant.scopes, ['https://www.googleapis.com/auth/tasks']);
    expect(
      () => MailOAuthConfiguration(
        service: MailCloudService.gmail,
        clientId: 'fixture',
        googleTaskWrites: true,
      ),
      throwsArgumentError,
    );
  });

  test(
    'creates, sends a sparse conditional update, and conditionally deletes',
    () async {
      final provider = writer();
      final due = TaskDate(2027, 1, 15);
      transport.replies.addAll([
        {
          'items': [
            {'id': list.value, 'title': 'Personal'},
          ],
        },
        {
          ...task(),
          'due': '2027-01-15T00:00:00.000Z',
          'notes': 'Original notes',
        },
        task(),
        task(revision: 'rev-2', title: 'Edited'),
        task(revision: 'rev-2', title: 'Edited'),
        MailCloudHttpResponse(statusCode: 204),
      ]);

      final discovered = _value(await provider.lists(session.begin()));
      expect(discovered.lists.single.readOnly, isFalse);
      final created = _value(
        await provider.create(
          list,
          TaskFields(
            title: 'Fixture',
            notes: const TaskText('Original notes'),
            due: due,
          ),
          session.begin(),
        ),
      );
      final updated = _value(
        await provider.update(
          created.id,
          const TaskPatch(
            title: TaskFieldPatch.set('Edited'),
            notes: TaskFieldPatch.clear(),
          ),
          revision: created.revision!,
          lease: session.begin(),
        ),
      );
      expect(updated.fields.title, 'Edited');
      _value(
        await provider.delete(
          id,
          revision: updated.revision!,
          lease: session.begin(),
        ),
      );
      expect(transport.requests.map((request) => request.method), [
        'GET',
        'POST',
        'GET',
        'PATCH',
        'GET',
        'DELETE',
      ]);
      expect(jsonDecode(utf8.decode(transport.requests[1].body)), {
        'title': 'Fixture',
        'notes': 'Original notes',
        'due': '2027-01-15T00:00:00.000Z',
      });
      expect(
        transport.requests[3].uri.path,
        '/tasks/v1/lists/personal/tasks/task-1',
      );
      expect(transport.requests[3].headers['if-match'], '"rev-1"');
      expect(jsonDecode(utf8.decode(transport.requests[3].body)), {
        'title': 'Edited',
        'notes': null,
      });
      expect(transport.requests.last.headers['if-match'], '"rev-2"');
      expect(transport.requests.last.body, isEmpty);
    },
  );

  test('refuses assigned tasks and stale revisions before writing', () async {
    final provider = writer();
    transport.replies.addAll([task(assigned: true), task(revision: 'new')]);
    final assigned = await provider.delete(
      id,
      revision: 'rev-1',
      lease: session.begin(),
    );
    final problem = (assigned as TaskFailure<TaskUnit>).problem;
    expect(problem.code, TaskProblemCode.permissionDenied);
    expect(problem.mutationMayHaveOccurred, isFalse);
    final stale = await provider.update(
      id,
      const TaskPatch(title: TaskFieldPatch.set('Edited')),
      revision: 'rev-1',
      lease: session.begin(),
    );
    expect(
      (stale as TaskFailure<RemoteTask>).problem.code,
      TaskProblemCode.conflict,
    );
    expect(stale.problem.mutationMayHaveOccurred, isFalse);
    expect(transport.requests.map((request) => request.method), ['GET', 'GET']);
  });

  test(
    'keeps lost inserts uncertain and known preconditions retry-safe',
    () async {
      final provider = writer();
      transport.replies.addAll([
        const MailCloudException(
          MailProblem(MailProblemCode.unavailable),
          requestMayHaveReachedServer: true,
        ),
        task(),
        MailCloudHttpResponse(statusCode: 412),
      ]);
      final lost = await provider.create(
        list,
        const TaskFields(title: 'Maybe'),
        session.begin(),
      );
      expect(
        (lost as TaskFailure<RemoteTask>).problem.mutationMayHaveOccurred,
        isTrue,
      );
      expect(transport.requests, hasLength(1));
      final rejected = await provider.update(
        id,
        const TaskPatch(title: TaskFieldPatch.set('Edited')),
        revision: 'rev-1',
        lease: session.begin(),
      );
      expect(
        (rejected as TaskFailure<RemoteTask>).problem.code,
        TaskProblemCode.conflict,
      );
      expect(rejected.problem.mutationMayHaveOccurred, isFalse);
    },
  );

  test(
    'read-only grants and unsafe entity tags never dispatch requests',
    () async {
      final disabled = await (reader as GoogleTaskProvider).create(
        list,
        const TaskFields(title: 'Fixture'),
        session.begin(),
      );
      expect(
        (disabled as TaskFailure<RemoteTask>).problem.code,
        TaskProblemCode.permissionDenied,
      );
      final rejected = await writer().delete(
        id,
        revision: '*',
        lease: session.begin(),
      );
      expect(
        (rejected as TaskFailure<TaskUnit>).problem.code,
        TaskProblemCode.invalidInput,
      );
      expect(transport.requests, isEmpty);
      expect(tokens.requests, 0);
    },
  );

  test('Google Tasks gives no permission to read or modify Gmail', () {
    final configuration = MailOAuthConfiguration(
      service: MailCloudService.gmail,
      clientId: 'fixture',
      tasksOnly: true,
    );
    expect(configuration.scopes, [
      'https://www.googleapis.com/auth/tasks.readonly',
    ]);
    final mailConfiguration = MailOAuthConfiguration(
      service: MailCloudService.gmail,
      clientId: 'fixture',
    );
    expect(mailConfiguration.scopes, [
      'https://www.googleapis.com/auth/gmail.modify',
    ]);
  });

  test(
    'discovers lists and retrieves all pages with dates and assignment data',
    () async {
      transport.replies.addAll([
        {
          'items': [
            {'id': 'list', 'title': 'Work', 'etag': 'list-etag'},
          ],
        },
        {
          'nextPageToken': 'next+token=',
          'items': [
            {
              'id': 'task-1',
              'title': 'Completed',
              'notes': 'Some notes',
              'status': 'completed',
              'due': '2026-11-25T00:00:00.000Z',
              'completed': '2026-11-25T12:30:00Z',
              'assignmentInfo': {'surfaceType': 'SPACE'},
            },
          ],
        },
        {
          'items': [
            {'id': 'task-2', 'title': 'Open', 'status': 'needsAction'},
          ],
        },
      ]);
      final list = _value(await reader.lists(session.begin())).lists.single;
      expect(list.readOnly, isTrue);
      expect(list.revision, 'list-etag');
      expect(transport.requests.first.uri.path, '/tasks/v1/users/@me/lists');
      final first = _value(await reader.pull(list.id, lease: session.begin()));
      final task = first.upserts.single;
      expect(task.fields.due, TaskDate(2026, 11, 25));
      expect(
        task.fields.completedAt,
        TaskDateTime('2026-11-25T12:30:00', timeZone: 'UTC'),
      );
      expect(task.fields.notes, const TaskText('Some notes'));
      expect(task.providerData?.raw, contains('assignmentInfo'));
      expect(first.checkpoint, isNull);
      expect(
        transport.requests.last.uri.queryParameters['showCompleted'],
        'true',
      );
      expect(transport.requests.last.uri.queryParameters['showHidden'], 'true');
      expect(
        transport.requests.last.uri.queryParameters['showAssigned'],
        'true',
      );

      final otherList = TaskListId('other', account: _account);
      final bad = await reader.pull(
        otherList,
        lease: session.begin(),
        cursor: first.nextCursor,
      );
      expect(
        (bad as TaskFailure<TaskSyncPage>).problem.code,
        TaskProblemCode.invalidInput,
      );
      expect(tokens.requests, 2);
      final last = _value(
        await reader.pull(
          list.id,
          lease: session.begin(),
          cursor: first.nextCursor,
        ),
      );
      expect(last.complete, isTrue);
      expect(last.upserts.single.fields.title, 'Open');
      expect(
        transport.requests.last.uri.queryParameters['pageToken'],
        'next+token=',
      );
    },
  );

  test(
    'rejects malformed pages without returning an authoritative empty snapshot',
    () async {
      transport.replies.add({
        'items': [
          {'id': 'one', 'title': 'Malformed', 'status': 'unknown'},
        ],
      });
      final list = TaskListId('list', account: _account);
      final result = await reader.pull(list, lease: session.begin());
      expect(
        (result as TaskFailure<TaskSyncPage>).problem.code,
        TaskProblemCode.invalidResponse,
      );
      transport.replies.add(MailCloudHttpResponse(statusCode: 403));
      final denied = await reader.pull(list, lease: session.begin());
      expect(
        (denied as TaskFailure<TaskSyncPage>).problem.code,
        TaskProblemCode.permissionDenied,
      );
    },
  );
}
