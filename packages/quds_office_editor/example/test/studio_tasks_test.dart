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
import 'package:quds_office_studio/studio_device_tasks.dart';
import 'package:quds_office_studio/studio_tasks.dart';
import 'package:quds_office_studio/studio_chrome.dart';
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
    await tester.tap(find.byTooltip('Export automation snapshot'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('currently displayed task list and filter'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Choose file'), findsNothing);
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
    await tester.tap(find.text('All tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open').last);
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the fixture'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'follow-up capture refreshes mounted Tasks and supports due views',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('crisp-follow-up-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = '${directory.path}/tasks.sqlite';
      final today = DateTime.now();
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      await tester.pumpWidget(
        MaterialApp(
          home: StudioTasksPage(
            title: 'Tasks',
            openDatabase: () async => sqlite3.open(file),
            chromeBuilder: (context) => TextButton(
              onPressed: () => createStudioFollowUpTask(
                context,
                title: 'Follow up on appointment',
                notes: 'Meeting room',
                due: TaskDate(today.year, today.month, today.day),
                openDatabase: () async => sqlite3.open(file),
              ),
              child: const Text('Capture'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('No tasks in this list.'), findsOneWidget);

      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Follow up on appointment'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Meeting room'), findsOneWidget);
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();
      expect(find.text('Follow up on appointment'), findsOneWidget);

      final database = sqlite3.open(file);
      try {
        expect(
          saveStudioDeviceTask(
                database,
                TaskFields(
                  title: 'Late follow-up',
                  due: TaskDate(yesterday.year, yesterday.month, yesterday.day),
                ),
              )
              is TaskSuccess,
          isTrue,
        );
        expect(
          saveStudioDeviceTask(
                database,
                TaskFields(
                  title: 'Finished follow-up',
                  due: TaskDate(today.year, today.month, today.day),
                  status: TaskStatus.completed,
                ),
              )
              is TaskSuccess,
          isTrue,
        );
      } finally {
        database.close();
      }
      studioDeviceTaskChanges.value++;
      await tester.pumpAndSettle();

      await tester.tap(find.text('All tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Due today').last);
      await tester.pumpAndSettle();
      expect(find.text('Follow up on appointment'), findsOneWidget);
      expect(find.text('Late follow-up'), findsNothing);
      expect(find.text('Finished follow-up'), findsNothing);

      await tester.tap(find.text('Due today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overdue').last);
      await tester.pumpAndSettle();
      expect(find.text('Late follow-up'), findsOneWidget);
      expect(find.text('Follow up on appointment'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Tasks uses the shell ribbon and theme surface, and supports both swipes',
    (tester) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: Colors.grey,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: StudioTasksPage(
            title: 'Tasks',
            chromeBuilder: (_) => const Text('Shared shell'),
            openDatabase: () async => sqlite3.openInMemory(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared shell'), findsOneWidget);
      expect(find.byType(StudioTabChip), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StudioRibbonStrip),
          matching: find.byKey(const ValueKey('studio-task-list-selector')),
        ),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        theme.colorScheme.surface,
      );
      await tester.tap(find.byTooltip('Add task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Swipe fixture',
      );
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Swipe fixture'), const Offset(520, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.drag(find.text('Swipe fixture'), const Offset(-520, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete task?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Swipe fixture'), findsOneWidget);
      await tester.drag(find.text('Swipe fixture'), const Offset(-520, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete task'));
      await tester.pumpAndSettle();
      expect(find.text('Swipe fixture'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
    await tester.tap(find.text('Google Tasks').last);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Google desktop client ID'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Allow Google task edits'),
          )
          .value,
      isFalse,
    );
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

  testWidgets('adds an account without overwriting the saved mailbox and switches back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final vault = InMemorySecureStorage();
    final selection = StudioCredentialStorage(
      systemStorageFactory: () async => vault,
    );
    addTearDown(selection.dispose);
    await vault.write(
      'crispoffice.tasks.account.v1',
      jsonEncode({
        'id': 'legacy-mailbox',
        'provider': 'caldav',
        'url': 'https://dav.mailbox.org/',
        'collection': 'https://dav.mailbox.org/first/',
        'login': 'First mailbox',
        'secret': 'first-password',
        'lists': [
          ['https://dav.mailbox.org/first/', 'First list', false],
        ],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StudioTasksPage(
          title: 'Tasks',
          openDatabase: () async => sqlite3.openInMemory(),
          credentialStorage: selection,
          openDavClient: () => MockClient((request) async {
            final first = request.url.path == '/first/';
            final label = first ? 'First list' : 'Second list';
            final username = first ? 'First mailbox' : 'Second mailbox';
            final password = first ? 'first-password' : 'second-password';
            expect(
              request.headers['authorization'],
              'Basic ${base64.encode(utf8.encode('$username:$password'))}',
            );
            final value = request.method != 'PROPFIND'
                ? ''
                : '<d:response><d:href>${request.url.path}</d:href><d:propstat><d:prop>'
                      '<d:resourcetype><c:calendar/></d:resourcetype><d:displayname>$label</d:displayname>'
                      '<c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>'
                      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
            return http.Response(
              '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">$value</d:multistatus>',
              207,
            );
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First list'), findsOneWidget);
    expect(await vault.read('crispoffice.tasks.account.v1'), isNull);
    await tester.tap(find.text('Add account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Exact task-list URL (optional)'),
      'https://dav.mailbox.org/second/',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'Second mailbox',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'App password'),
      'second-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Second list'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(DropdownButton<TaskAccountId>, 'Second mailbox'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('First mailbox').last);
    await tester.pumpAndSettle();
    expect(find.text('First list'), findsOneWidget);
    final saved =
        jsonDecode((await vault.read('crispoffice.tasks.accounts.v2'))!) as Map;
    expect(saved['accounts'], hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('CalDAV connect and disconnect use the selected credential vault', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final vault = InMemorySecureStorage();
    final selection = StudioCredentialStorage(
      systemStorageFactory: () async => vault,
    );
    addTearDown(selection.dispose);
    const key = 'crispoffice.tasks.accounts.v2';
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
    final catalog =
        jsonDecode((await vault.read(key))!) as Map<String, Object?>;
    final saved = (catalog['accounts'] as List).single as Map<String, Object?>;
    expect(saved['secret'], password);
    expect(saved['davProfile'], 'mailbox.org');
    expect(
      database.select('SELECT account FROM task_accounts').toString(),
      isNot(contains(password)),
    );
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect((jsonDecode((await vault.read(key))!) as Map)['accounts'], isEmpty);
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
