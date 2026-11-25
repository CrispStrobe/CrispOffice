import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    await tester.tap(find.text('Exchange EWS (read-only)').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'EWS endpoint'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(DropdownButton<String>, 'Exchange EWS (read-only)'),
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
