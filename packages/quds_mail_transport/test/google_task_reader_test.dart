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
    expect(request.method, 'GET');
    expect(NativeMailCloudHttpTransport.allowedUri(request.uri), isTrue);
    expect(request.headers['authorization'], 'Bearer fixture');
    final reply = replies.removeAt(0);
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
