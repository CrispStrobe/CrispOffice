import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_calendar.dart';
import 'package:quds_office_studio/studio_calendar_grid.dart';
import 'package:quds_office_studio/studio_credential_storage.dart';
import 'package:quds_office_studio/studio_productivity_accounts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _collection = '/calendars/appointments/';
const _resource = '/calendars/appointments/event.ics';

String _row(String href, String props) =>
    '<D:response><D:href>$href</D:href><D:propstat><D:prop>$props</D:prop>'
    '<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>';

String _multi(String rows) =>
    '<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
    '$rows</D:multistatus>';

Map<String, String> _account(String id, String name) => {
  'id': id,
  'provider': 'caldav',
  'url': 'https://dav.example.test/',
  'login': '$id@example.test',
  'label': name,
  'secret': '$id-specific-secret',
};

String _authorization(String id) =>
    'Basic ${base64.encode(utf8.encode('$id@example.test:$id-specific-secret'))}';

String _event(String subject, String description) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n'
    'UID:same-uid\r\nDTSTART:20261125T090000Z\r\nDTEND:20261125T100000Z\r\n'
    'SUMMARY:$subject\r\nDESCRIPTION:$description\r\nEND:VEVENT\r\nEND:VCALENDAR';

final class _ExchangeReader implements EwsCalendarReader {
  _ExchangeReader(this.account, this.configuration, this.credentials);

  final TaskAccountId account;
  final MailEwsConfiguration configuration;
  final MailCredentialStore credentials;
  final leases = <MailOperationLease>[];
  var activeReads = 0;
  var reads = 0;
  Completer<void>? pauseAgenda;

  String? get appointmentRevision => null;
  String get appointmentTitle => 'Exchange appointment';

  @override
  Future<TaskResult<List<EwsCalendar>>> calendars(
    MailOperationLease lease,
  ) async {
    leases.add(lease);
    final secret = await credentials.load(configuration.credential);
    final record = (secret as MailSuccess<MailCredentialRecord?>).value;
    expect(utf8.decode(record!.opaqueData.bytes), 'exchange-secret');
    return TaskSuccess([
      EwsCalendar(
        id: TaskListId('main', account: account),
        name: 'Calendar',
      ),
      EwsCalendar(
        id: TaskListId('second', account: account),
        name: 'Team',
      ),
    ]);
  }

  @override
  Future<TaskResult<List<EwsCalendarEvent>>> agenda(
    TaskListId calendar, {
    required DateTime start,
    required DateTime end,
    required MailOperationLease lease,
  }) async {
    leases.add(lease);
    expect(lease.account, configuration.account);
    expect(calendar.account, account);
    expect(++activeReads, 1);
    reads++;
    await (pauseAgenda?.future ?? Future<void>.delayed(Duration.zero));
    activeReads--;
    return TaskSuccess([
      EwsCalendarEvent(
        id: 'same-event-id',
        title: calendar.value == 'main' ? appointmentTitle : 'Team appointment',
        start: DateTime.utc(2026, 11, 25, 12),
        end: DateTime.utc(2026, 11, 25, 13),
        location: 'Meeting room',
        appointmentRevision: appointmentRevision,
      ),
    ]);
  }
}

final class _ExchangeWriter extends _ExchangeReader
    implements EwsCalendarWriter {
  _ExchangeWriter(super.account, super.configuration, super.credentials);

  @override
  String get appointmentRevision => 'key';

  @override
  String appointmentTitle = 'Exchange appointment';

  @override
  bool get canDeleteAppointments => false;

  @override
  Future<TaskResult<EwsCalendarEvent>> openAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    MailOperationLease lease,
  ) async {
    expect(calendar.value, 'main');
    expect(observed.appointmentRevision, 'key');
    return TaskSuccess(observed);
  }

  @override
  Future<TaskResult<TaskUnit>> createAppointment(
    TaskListId calendar,
    EwsAppointmentFields fields,
    MailOperationLease lease, {
    bool Function()? canWrite,
  }) async => throw StateError('Unexpected creation');

  @override
  Future<TaskResult<TaskUnit>> updateAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    EwsAppointmentFields fields,
    MailOperationLease lease, {
    bool Function()? canWrite,
  }) async {
    expect(calendar.value, 'main');
    expect(canWrite?.call(), isTrue);
    expect(fields.start, observed.start);
    expect(fields.end, observed.end);
    appointmentTitle = fields.title;
    return const TaskSuccess(TaskUnit.value);
  }

  @override
  Future<TaskResult<TaskUnit>> deleteAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    MailOperationLease lease, {
    bool Function()? canWrite,
  }) async => throw StateError('Unexpected deletion');
}

void main() {
  testWidgets(
    'combines accounts with identical DAV paths and routes edits to the owning account',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final vault = InMemorySecureStorage();
      await vault.write(
        studioTasksAccountsKey,
        jsonEncode({
          'active': ['caldav', 'personal'],
          'accounts': [
            _account('personal', 'Personal account'),
            _account('work', 'Work account'),
          ],
        }),
      );
      final storage = StudioCredentialStorage(
        systemStorageFactory: () async => vault,
      );
      addTearDown(storage.dispose);
      var personal = _event('Lunch booking', 'Offsite lunch');
      var work = _event('Team meeting', 'Quarterly agenda');
      var workTag = '"work-initial"';
      var workUnavailable = false;
      var reportCount = 0;
      final writes = <String>[];
      final client = MockClient((request) async {
        final auth = request.headers['authorization'];
        final isWork = auth == _authorization('work');
        expect(isWork || auth == _authorization('personal'), isTrue);
        final source = isWork ? 'work' : 'personal';
        final event = isWork ? work : personal;
        final tag = isWork ? workTag : '"personal"';
        final path = request.url.path;
        http.Response response(
          String body,
          int status, {
          Map<String, String> headers = const {},
        }) => http.Response(body, status, headers: headers, request: request);
        switch ((request.method, path)) {
          case ('PROPFIND', '/'):
            return response(
              _multi(
                _row(
                  '/',
                  '<C:calendar-home-set>'
                      '<D:href>/calendars/</D:href></C:calendar-home-set>',
                ),
              ),
              207,
            );
          case ('PROPFIND', '/calendars/'):
            return response(
              _multi(
                _row(
                  _collection,
                  '<D:resourcetype><C:calendar/></D:resourcetype>'
                  '<D:displayname>Appointments</D:displayname>'
                  '<C:supported-calendar-component-set><C:comp name="VEVENT"/>'
                  '</C:supported-calendar-component-set><D:current-user-privilege-set>'
                  '<D:privilege><D:write/></D:privilege></D:current-user-privilege-set>',
                ),
              ),
              207,
            );
          case ('REPORT', _collection):
            reportCount++;
            if (isWork && workUnavailable) return response('', 503);
            return response(
              _multi(
                _row(
                  _resource,
                  '<D:getetag>$tag</D:getetag>'
                  '<C:calendar-data><![CDATA[$event]]></C:calendar-data>',
                ),
              ),
              207,
            );
          case ('GET', _resource):
            return response(event, 200, headers: {'etag': tag});
          case ('PUT', _resource):
            expect(request.headers['if-match'], tag);
            writes.add(source);
            if (isWork) {
              work = request.body;
              workTag = '"work-updated"';
            } else {
              personal = request.body;
            }
            return response('', 204);
          default:
            throw StateError('Unexpected fixture request.');
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StudioCalendarPage(
            title: 'Calendar',
            initialDate: DateTime(2026, 11, 25),
            chromeBuilder: (_) => const SizedBox.shrink(),
            openConnections: () {},
            credentialStorage: storage,
            openDavClient: () => client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lunch booking'), findsOneWidget);
      expect(find.text('Team meeting'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('studio-calendar-picker')));
      await tester.pumpAndSettle();
      expect(find.text('Personal account'), findsOneWidget);
      expect(find.text('Work account'), findsOneWidget);
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();
      expect(find.text('2 calendars'), findsOneWidget);
      expect(find.text('Team meeting'), findsOneWidget);
      expect(find.text('Lunch booking'), findsOneWidget);

      final reportsBeforeFilter = reportCount;
      await tester.enterText(find.byType(TextField), 'OFFSITE');
      await tester.pumpAndSettle();
      expect(find.text('Team meeting'), findsNothing);
      expect(find.text('Lunch booking'), findsOneWidget);
      expect(reportCount, reportsBeforeFilter);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Show grid'));
      await tester.pumpAndSettle();
      final grid = tester.widget<StudioCalendarGrid>(
        find.byType(StudioCalendarGrid),
      );
      final styles = grid.events
          .map((event) => grid.appearanceOf!(event)!)
          .toList();
      expect(styles.map((style) => style.label).toSet(), {
        'Appointments (Personal account)',
        'Appointments (Work account)',
      });
      expect(styles.map((style) => style.color).toSet(), hasLength(2));
      await tester.tap(find.byTooltip('Show agenda'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New event'));
      await tester.pumpAndSettle();
      expect(find.text('Create in calendar'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(SimpleDialogOption, 'Appointments (Work account)'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Appointments (Work account)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);

      await tester.tap(find.text('Team meeting'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Revised work meeting',
      );
      await tester.tap(find.text('Save event'));
      await tester.pumpAndSettle();
      expect(writes, ['work']);
      expect(find.text('Revised work meeting'), findsOneWidget);
      expect(find.text('Lunch booking'), findsOneWidget);

      workUnavailable = true;
      final refresh = find.byTooltip('Refresh');
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('One calendar source could not load'), findsOneWidget);
      expect(find.text('Lunch booking'), findsOneWidget);
      expect(find.text('Revised work meeting'), findsNothing);
      await tester.tap(find.text('One calendar source could not load'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Appointments (Work account)'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'uses saved EWS credentials and loads multiple read-only calendars',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final vault = InMemorySecureStorage();
      await vault.write(
        studioTasksAccountsKey,
        jsonEncode({
          'active': ['ews', 'work'],
          'accounts': [
            {
              'id': 'work',
              'provider': 'ews',
              'url': 'https://exchange.example.test/EWS/Exchange.asmx',
              'login': 'work-login',
              'domain': 'WORK',
              'mailbox': 'work@example.test',
              'label': 'Exchange account',
              'secret': 'exchange-secret',
            },
          ],
        }),
      );
      final storage = StudioCredentialStorage(
        systemStorageFactory: () async => vault,
      );
      addTearDown(storage.dispose);
      late _ExchangeReader exchange;
      Completer<void>? pauseAgenda;
      await tester.pumpWidget(
        MaterialApp(
          home: StudioCalendarPage(
            title: 'Calendar',
            chromeBuilder: (_) => const SizedBox.shrink(),
            openConnections: () {},
            initialDate: DateTime(2026, 11, 25),
            credentialStorage: storage,
            openDavClient: () =>
                throw StateError('EWS needs no CalDAV client.'),
            openEwsReader: (account, configuration, credentials) {
              expect(configuration.domain, 'WORK');
              expect(configuration.mailboxAddress, 'work@example.test');
              return exchange = _ExchangeReader(
                account,
                configuration,
                credentials,
              )..pauseAgenda = pauseAgenda;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(exchange.reads, 1);
      expect(find.text('Exchange appointment'), findsOneWidget);

      final refresh = find.byTooltip('Refresh');
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      final originalExchange = exchange;
      pauseAgenda = Completer<void>();
      await tester.tap(refresh);
      await tester.pump();
      expect(find.text('Exchange appointment'), findsOneWidget);
      expect(exchange, isNot(same(originalExchange)));
      pauseAgenda!.complete();
      pauseAgenda = null;
      exchange.pauseAgenda = null;
      await tester.pumpAndSettle();
      expect(find.text('Exchange appointment'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('studio-calendar-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();
      expect(exchange.reads, 3);
      expect(find.text('Exchange appointment'), findsOneWidget);
      expect(find.text('Team appointment'), findsOneWidget);

      final share = find.byTooltip('Export automation snapshot');
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('currently displayed calendars and date range'),
        findsOneWidget,
      );
      expect(find.text('Choose file'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Choose file'), findsNothing);

      final live = find.byTooltip('Live MCP access');
      await tester.ensureVisible(live);
      await tester.tap(live);
      await tester.pumpAndSettle();
      expect(find.text('Grant live read access'), findsOneWidget);
      expect(
        find.textContaining('displayed calendars and date range'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Grant read access'), findsNothing);

      await tester.tap(find.text('Team appointment'));
      await tester.pumpAndSettle();
      expect(find.text('Meeting room'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(exchange.leases.every((lease) => !lease.isCurrent), isTrue);
    },
  );
  testWidgets('edits the selected timed EWS appointment', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final vault = InMemorySecureStorage();
    await vault.write(
      studioTasksAccountsKey,
      jsonEncode({
        'active': ['ews', 'work'],
        'accounts': [
          {
            'id': 'work',
            'provider': 'ews',
            'url': 'https://exchange.example.test/EWS/Exchange.asmx',
            'login': 'work-login',
            'domain': 'WORK',
            'secret': 'exchange-secret',
          },
        ],
      }),
    );
    final storage = StudioCredentialStorage(
      systemStorageFactory: () async => vault,
    );
    addTearDown(storage.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StudioCalendarPage(
          title: 'Calendar',
          chromeBuilder: (_) => const SizedBox.shrink(),
          openConnections: () {},
          initialDate: DateTime(2026, 11, 25),
          credentialStorage: storage,
          openEwsReader: _ExchangeWriter.new,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exchange appointment'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('All day'), findsNothing);
    expect(find.byTooltip('Remove end'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Changed appointment',
    );
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(find.text('Changed appointment'), findsOneWidget);
  });
  testWidgets('fits month rows and expands event overflow inside its week', (
    tester,
  ) async {
    final date = CalDavDateValue.fromTaskDate(TaskDate(2026, 11, 25));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioCalendarGrid(
            period: StudioCalendarPeriod.month,
            start: DateTime(2026, 11),
            end: DateTime(2026, 12),
            events: [
              for (var index = 1; index <= 6; index++)
                CalDavEvent(
                  uid: '$index',
                  title: 'Agenda item $index',
                  start: date,
                ),
            ],
            openEvent: (_) {},
            openDay: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('30'), findsOneWidget);
    expect(find.text('Agenda item 6'), findsNothing);
    await tester.tap(find.textContaining(RegExp(r'^\+\d+$')));
    await tester.pumpAndSettle();
    expect(find.text('Agenda item 6'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('−'));
    await tester.pumpAndSettle();
    expect(find.text('Agenda item 6'), findsNothing);
  });
}
