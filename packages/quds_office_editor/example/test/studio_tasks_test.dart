import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_credential_storage.dart';
import 'package:quds_office_studio/studio_tasks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('device task survives reopening, filters, and can be removed', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('crisp-tasks-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = '${directory.path}/tasks.sqlite';
    Widget page() => MaterialApp(
      home: StudioTasksPage(
        title: 'Tasks',
        openDatabase: () async => sqlite3.open(file),
      ),
    );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Plan the fixture',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'Follow up Monday',
    );
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.enterText(find.byType(TextField), 'nonexistent');
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsNothing);
    await tester.enterText(find.byType(TextField), 'monday');
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsOneWidget);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsNothing);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('native Tasks pane exposes its close action', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StudioTasksPage(
          title: 'Tasks',
          onClose: () => closed = true,
          openDatabase: () async => sqlite3.openInMemory(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    expect(closed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('task setup exposes separate Exchange and Google credentials', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudioTasksPage(
          title: 'Tasks',
          openDatabase: () async => sqlite3.openInMemory(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButton<String>, 'CalDAV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exchange EWS').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'EWS endpoint'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(
              CheckboxListTile,
              'Allow deleting Exchange tasks',
            ),
          )
          .value,
      isFalse,
    );
    await tester.tap(
      find.widgetWithText(DropdownButton<String>, 'Exchange EWS'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Tasks (read-only)').last);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Google desktop client ID'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Exchange edits push through the outbox and background refresh visits all lists',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final selection = StudioCredentialStorage(
        systemStorageFactory: () async => InMemorySecureStorage(),
      );
      addTearDown(selection.dispose);
      late _EwsFixture provider;
      await tester.pumpWidget(
        MaterialApp(
          home: StudioTasksPage(
            title: 'Tasks',
            openDatabase: () async => sqlite3.openInMemory(),
            credentialStorage: selection,
            openEwsProvider: (account, config, credentials) {
              expect(config.endpoint.path, '/EWS/Exchange.asmx');
              return provider = _EwsFixture(account);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButton<String>, 'CalDAV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exchange EWS').last);
      await tester.pumpAndSettle();
      final allowDelete = find.widgetWithText(
        CheckboxListTile,
        'Allow deleting Exchange tasks',
      );
      await tester.ensureVisible(allowDelete);
      await tester.tap(allowDelete);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'EWS endpoint'),
        'https://exchange.example.test/EWS/Exchange.asmx',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'fixture',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'fixture-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(provider.pulls, [provider.primary.id]);

      await tester.tap(find.byTooltip('Add task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Push from Studio',
      );
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();
      expect(provider.task?.fields.title, 'Push from Studio');
      expect(provider.createCount, 1);
      expect(
        find.text('Checking if the server accepted this change'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pumpAndSettle();
      expect(provider.createCount, 1);
      expect(
        find.text('Checking if the server accepted this change'),
        findsNothing,
      );
      expect(find.text('Push from Studio'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(provider.task?.fields.status, TaskStatus.completed);
      expect(provider.updateCount, 1);
      await tester.tap(find.byTooltip('Delete task'));
      await tester.pumpAndSettle();
      expect(provider.deleteCount, 1);
      expect(find.text('Push from Studio'), findsNothing);

      provider.pulls.clear();
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(provider.pulls, [provider.primary.id, provider.secondary.id]);
      await tester.tap(
        find.widgetWithText(DropdownButton<TaskListId>, 'Exchange Tasks'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other Exchange list').last);
      await tester.pumpAndSettle();
      expect(find.text('Read-only list'), findsOneWidget);
      expect(find.text('Due 2027-01-15'), findsOneWidget);
      expect(find.byTooltip('Add task'), findsNothing);
      await tester.tap(find.text('Shared task'));
      await tester.pumpAndSettle();
      expect(find.text('Visible private fixture note'), findsOneWidget);
      expect(find.text('Save task'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('CalDAV connect and disconnect use the selected credential vault', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final vault = InMemorySecureStorage();
    final selection = StudioCredentialStorage(
      systemStorageFactory: () async => vault,
    );
    addTearDown(selection.dispose);
    const key = 'crispoffice.tasks.account.v1';
    const login = 'fixture-user';
    const password = 'fixture-app-password';
    const exact = 'https://dav.mailbox.org/tasks/';
    final requests = <String>[];
    final database = sqlite3.openInMemory();
    await tester.pumpWidget(
      MaterialApp(
        home: StudioTasksPage(
          title: 'Tasks',
          openDatabase: () async => database,
          credentialStorage: selection,
          openDavClient: () => MockClient((request) async {
            expect(request.url.toString(), exact);
            expect(
              request.headers['authorization'],
              'Basic ${base64.encode(utf8.encode('$login:$password'))}',
            );
            requests.add(request.method);
            final values = request.method != 'PROPFIND'
                ? ''
                : '<d:response><d:href>/tasks/</d:href><d:propstat><d:prop>'
                      '<d:resourcetype><c:calendar/></d:resourcetype><d:displayname>Fixture list</d:displayname>'
                      '<c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>'
                      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
            return http.Response(
              '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
              '$values</d:multistatus>',
              207,
            );
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Exact task-list URL (optional)'),
      exact,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      login,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'App password'),
      password,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture list'), findsOneWidget);
    expect(requests, ['PROPFIND', 'REPORT']);
    final saved = jsonDecode((await vault.read(key))!) as Map<String, Object?>;
    expect(saved['secret'], password);
    expect(saved['davProfile'], 'mailbox.org');
    expect(
      database.select('SELECT account FROM task_accounts').toString(),
      isNot(contains(password)),
    );
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(await vault.read(key), isNull);
    expect(find.text('Connect account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _EwsFixture implements EwsTaskProvider {
  _EwsFixture(TaskAccountId account)
    : primary = TaskList(
        id: TaskListId('primary', account: account),
        name: 'Exchange Tasks',
      ),
      secondary = TaskList(
        id: TaskListId('secondary', account: account),
        name: 'Other Exchange list',
        readOnly: true,
      );

  final TaskList primary;
  final TaskList secondary;
  final pulls = <TaskListId>[];
  RemoteTask? task;
  int createCount = 0;
  int updateCount = 0;
  int deleteCount = 0;

  @override
  Future<TaskResult<List<TaskList>>> taskLists(
    MailOperationLease lease,
  ) async => TaskSuccess([primary, secondary]);

  @override
  Future<TaskResult<TaskSyncPage>> pullTasks(
    TaskListId list, {
    String? cursor,
    required MailOperationLease lease,
  }) async {
    pulls.add(list);
    return TaskSuccess(
      TaskSyncPage(
        list: list,
        upserts: [
          if (task case final current? when current.id.list == list) current,
          if (list == secondary.id)
            RemoteTask(
              id: TaskId('read-only-task', list: list),
              fields: TaskFields(
                title: 'Shared task',
                notes: const TaskText('Visible private fixture note'),
                due: TaskDate(2027, 1, 15),
              ),
              revision: 'ro1',
            ),
        ],
        tombstones: [],
        checkpoint: 'live',
      ),
    );
  }

  @override
  Future<TaskResult<RemoteTask>> createTask(
    TaskListId list,
    TaskFields fields, {
    required String operationId,
    required MailOperationLease lease,
  }) async {
    createCount++;
    task = RemoteTask(
      id: TaskId('created', list: list),
      fields: fields,
      revision: 'v1',
      providerData: TaskProviderData(
        format: 'ews-task-operation',
        raw: operationId,
      ),
    );
    return const TaskFailure(
      TaskProblem(TaskProblemCode.conflict, mutationMayHaveOccurred: true),
    );
  }

  @override
  Future<TaskResult<RemoteTask>> updateTask(
    TaskId id,
    TaskPatch patch, {
    required String revision,
    required MailOperationLease lease,
  }) async {
    expect(revision, 'v1');
    updateCount++;
    return TaskSuccess(
      task = RemoteTask(
        id: id,
        fields: patch.applyTo(task!.fields),
        revision: 'v2',
        providerData: task!.providerData,
      ),
    );
  }

  @override
  Future<TaskResult<TaskUnit>> deleteTask(
    TaskId id, {
    required String revision,
    required MailOperationLease lease,
  }) async {
    expect(revision, 'v2');
    expect(id, task?.id);
    deleteCount++;
    task = null;
    return const TaskSuccess(TaskUnit.value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
