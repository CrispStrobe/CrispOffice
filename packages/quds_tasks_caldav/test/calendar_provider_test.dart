import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

const _event = r'''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:all-day
DTSTART;VALUE=DATE:20261125
DTEND;VALUE=DATE:20261126
SUMMARY:Review\, then plan
LOCATION:Office
BEGIN:VALARM
SUMMARY:Alarm label
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:series
RECURRENCE-ID:20261125T230000Z
DTSTART:20261125T230000Z
DTEND:20261126T000000Z
SUMMARY:Expanded event
END:VEVENT
BEGIN:VEVENT
UID:unsupported-series
DTSTART:20261125T120000Z
RRULE:FREQ=MONTHLY
SUMMARY:Series
END:VEVENT
BEGIN:VEVENT
UID:cancelled
STATUS:CANCELLED
DTSTART:20261125T100000Z
SUMMARY:Cancelled event
END:VEVENT
END:VCALENDAR''';

String _multi(String rows) =>
    '<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">$rows</D:multistatus>';

String _row(String href, String props) =>
    '<D:response><D:href>$href</D:href><D:propstat><D:prop>$props</D:prop>'
    '<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>';

String _collection(String href, String name, String kind) => _row(
  href,
  '<D:resourcetype><C:calendar/></D:resourcetype><D:displayname>$name</D:displayname>'
  '<C:supported-calendar-component-set><C:comp name="$kind"/></C:supported-calendar-component-set>',
);

void main() {
  _recurrenceTests();
  _calendarWriteTests();
  test(
    'preserves all-day dates and reads expanded instances without cancelled events',
    () {
      final events = readCalDavAgenda(_event);
      expect(events.events.map((event) => event.title), [
        'Review, then plan',
        'Expanded event',
      ]);
      expect(events.events.first.start.kind, CalDavDateKind.date);
      expect(events.events[1].recurrenceId?.kind, CalDavDateKind.utc);
      expect(events.unexpandedSeries, 1);
    },
  );

  test('rejects malformed or ambiguous event bounds', () {
    expect(
      () =>
          readCalDavAgenda(_event.replaceFirst('UID:all-day', 'UID:a\nUID:b')),
      throwsFormatException,
    );
    expect(
      () => readCalDavAgenda(
        _event.replaceFirst('20261126\nSUMMARY', '20261131\nSUMMARY'),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          readCalDavAgenda(_event.replaceFirst('END:VEVENT', 'END:VCALENDAR')),
      throwsFormatException,
    );
  });

  test(
    'uses DAV discovery for VEVENT and asks the server to expand the requested window',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final response = switch ((request.method, request.url.path)) {
          ('PROPFIND', '/') => _row(
            '/',
            '<C:calendar-home-set><D:href>/calendars/</D:href></C:calendar-home-set>',
          ),
          ('PROPFIND', '/calendars/') =>
            _collection('/calendars/events/', 'Work', 'VEVENT') +
                _collection('/calendars/tasks/', 'To do', 'VTODO'),
          ('REPORT', '/calendars/events/') => _row(
            '/calendars/events/event.ics',
            '<C:calendar-data>$_event</C:calendar-data>',
          ),
          _ => throw StateError('Unexpected request.'),
        };
        return http.Response(_multi(response), 207, request: request);
      });
      final provider = CalDavCalendarProvider(
        account: TaskAccountId('fixture', provider: 'caldav'),
        settings: CalDavConnectionSettings(
          profile: CalDavServerProfile.generic,
          username: 'fixture',
          discoveryUrl: Uri.https('dav.example.test', '/'),
        ),
        client: client,
        appPassword: () async => 'fixture',
      );
      final calendars =
          (await provider.discoverCalendars()
                  as TaskSuccess<List<CalDavCalendar>>)
              .value;
      expect(calendars.single.name, 'Work');
      final report = await provider.agenda(
        calendars.single,
        start: DateTime.utc(2026, 11, 24),
        end: DateTime.utc(2026, 12, 1),
      );
      expect((report as TaskSuccess<CalDavAgenda>).value.events, hasLength(2));
      expect(
        requests.last.body,
        contains('<C:expand start="20261124T000000Z" end="20261201T000000Z"/>'),
      );
      expect(requests.last.body, contains('name="VEVENT"'));
      expect(requests.last.followRedirects, isFalse);
      final rejected = await provider.agenda(
        calendars.single,
        start: DateTime(2026, 11, 24),
        end: DateTime.utc(2026, 12, 1),
      );
      expect(
        (rejected as TaskFailure<CalDavAgenda>).problem.code,
        TaskProblemCode.invalidInput,
      );
      expect(requests, hasLength(3));
    },
  );
}

void _recurrenceTests() {
  test('expands a daily series with exclusions and moved exceptions', () {
    final agenda = readCalDavAgenda(
      r'''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:daily
DTSTART:20261123T090000Z
DTEND:20261123T100000Z
RRULE:FREQ=DAILY;COUNT=5
EXDATE:20261124T090000Z
RDATE:20261127T090000Z,20261130T090000Z
DESCRIPTION:Bring the form\nMeet at reception
SUMMARY:Daily appointment
END:VEVENT
BEGIN:VEVENT
UID:daily
RECURRENCE-ID:20261125T090000Z
DTSTART:20261125T110000Z
DTEND:20261125T120000Z
SUMMARY:Moved appointment
END:VEVENT
BEGIN:VEVENT
UID:daily
RECURRENCE-ID:20261126T090000Z
STATUS:CANCELLED
END:VEVENT
BEGIN:VEVENT
UID:daily
RECURRENCE-ID:20261127T090000Z
DTSTART:20261201T110000Z
DTEND:20261201T120000Z
SUMMARY:Moved out of range
END:VEVENT
END:VCALENDAR''',
      window: (
        start: DateTime.utc(2026, 11, 23),
        end: DateTime.utc(2026, 12, 1),
      ),
    );
    expect(agenda.unexpandedSeries, 0);
    expect(agenda.events.map((event) => event.start.value), [
      '20261123T090000Z',
      '20261130T090000Z',
      '20261125T110000Z',
    ]);
    expect(agenda.events.first.end?.value, '20261123T100000Z');
    expect(
      agenda.events.first.description,
      'Bring the form\nMeet at reception',
    );
    expect(agenda.events.last.recurrenceId?.value, '20261125T090000Z');
  });

  test('counts weekdays from DTSTART and fast-forwards old series', () {
    final agenda = readCalDavAgenda(
      '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:weekly
DTSTART:20261125T090000Z
RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;COUNT=4
SUMMARY:Weekly appointment
END:VEVENT
BEGIN:VEVENT
UID:old
DTSTART:19000101T143000Z
RRULE:FREQ=DAILY;UNTIL=20261211T143000Z
SUMMARY:Old series
END:VEVENT
END:VCALENDAR''',
      window: (
        start: DateTime.utc(2026, 12, 6),
        end: DateTime.utc(2026, 12, 13),
      ),
    );
    expect(agenda.unexpandedSeries, 0);
    expect(
      agenda.events
          .where((event) => event.uid == 'weekly')
          .map((event) => event.start.value),
      ['20261207T090000Z', '20261209T090000Z'],
    );
    expect(agenda.events.where((event) => event.uid == 'old'), hasLength(6));
  });

  test('keeps floating weekday events at the same wall-clock time', () {
    final agenda = readCalDavAgenda(
      '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:weekday
DTSTART:20260327T090000
RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=3
SUMMARY:Weekday appointment
END:VEVENT
END:VCALENDAR''',
      window: (
        start: DateTime(2026, 3, 27).toUtc(),
        end: DateTime(2026, 4, 2).toUtc(),
      ),
    );
    expect(agenda.unexpandedSeries, 0);
    expect(agenda.events.map((event) => event.start.value), [
      '20260327T090000',
      '20260330T090000',
      '20260331T090000',
    ]);
    expect(
      agenda.events.every(
        (event) => event.start.kind == CalDavDateKind.floating,
      ),
      isTrue,
    );
  });

  test('preserves exclusive all-day bounds for a continuation', () {
    final agenda = readCalDavAgenda(
      '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:days
DTSTART;VALUE=DATE:20261123
DTEND;VALUE=DATE:20261125
RRULE:FREQ=WEEKLY
SUMMARY:Multi-day appointment
END:VEVENT
END:VCALENDAR''',
      window: (
        start: DateTime(2026, 11, 24).toUtc(),
        end: DateTime(2026, 11, 25).toUtc(),
      ),
    );
    final event = agenda.events.single;
    expect(event.start.value, '20261123');
    expect(event.end?.value, '20261125');
    expect(event.recurrenceId?.kind, CalDavDateKind.date);
    expect(agenda.unexpandedSeries, 0);
  });

  test('leaves unsafe recurrence rules and ranged exceptions unexpanded', () {
    for (final parts in [
      ('DTSTART;TZID=Europe/Berlin:20261123T090000', 'RRULE:FREQ=DAILY', ''),
      ('DTSTART:20261123T090000Z', 'RRULE:FREQ=MONTHLY;BYDAY=2MO', ''),
      ('DTSTART:20261123T090000Z', 'RRULE:FREQ=DAILY;INTERVAL=0', ''),
      (
        'DTSTART:20261123T090000Z',
        'RRULE:FREQ=DAILY',
        '''BEGIN:VEVENT
UID:unsupported
RECURRENCE-ID;RANGE=THISANDFUTURE:20261125T090000Z
DTSTART:20261125T110000Z
END:VEVENT''',
      ),
    ]) {
      final agenda = readCalDavAgenda(
        '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:unsupported
${parts.$1}
${parts.$2}
END:VEVENT
${parts.$3.isEmpty ? '' : '${parts.$3}\n'}END:VCALENDAR''',
        window: (
          start: DateTime.utc(2026, 11, 23),
          end: DateTime.utc(2026, 12, 1),
        ),
      );
      expect(agenda.unexpandedSeries, 1);
      expect(agenda.events, isEmpty);
    }
  });
}

void _calendarWriteTests() {
  final now = DateTime.utc(2026, 11, 25, 8);
  final from = CalDavDateValue.parse('20261125T090000Z');
  final to = CalDavDateValue.parse('20261125T100000Z');
  CalDavEventFields fields(String title) => CalDavEventFields(
    title: title,
    start: from,
    end: to,
    location: 'Lab; restricted',
    description: 'First line\nSecond line',
  );

  test(
    'appointment edits preserve the resource UID, alarms, and unknown properties',
    () {
      final raw =
          CalDavEventDocument.create(
            uid: 'fixture-event',
            fields: fields('Original'),
            timestamp: now,
          ).replaceFirst(
            'END:VEVENT',
            'X-PROVIDER:opaque\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\n'
                'TRIGGER:-PT15M\r\nDESCRIPTION:Reminder\r\nEND:VALARM\r\nEND:VEVENT',
          );
      final document = CalDavEventDocument.parse(raw);
      expect(document.update(fields('Original'), timestamp: now), raw);
      final updated = document.update(fields('Changed, yes'), timestamp: now);
      expect(updated, contains('UID:fixture-event'));
      expect(updated, contains('X-PROVIDER:opaque\r\n'));
      expect(updated, contains('BEGIN:VALARM\r\nACTION:DISPLAY\r\n'));
      final event = CalDavEventDocument.parse(updated).event;
      expect(event.title, 'Changed, yes');
      expect(event.location, 'Lab; restricted');
      expect(event.description, 'First line\nSecond line');
      for (final extra in [
        'RRULE:FREQ=DAILY',
        'ORGANIZER:mailto:organizer@example.test',
        'ATTENDEE:mailto:attendee@example.test',
      ]) {
        expect(
          () => CalDavEventDocument.parse(
            raw.replaceFirst('END:VEVENT', '$extra\r\nEND:VEVENT'),
          ),
          throwsUnsupportedError,
        );
      }
    },
  );

  test(
    'CalDAV creation, update, and deletion enforce their own preconditions',
    () async {
      const path = '/home/events/crispoffice-event-operation.ics';
      const privileges =
          '<D:current-user-privilege-set><D:privilege><D:write/>'
          '</D:privilege></D:current-user-privilege-set>';
      String? raw;
      var revision = 0;
      String tag() => '"v$revision"';
      var loseWriteResponse = false;
      final methods = <String>[];
      final client = MockClient((request) async {
        final url = request.url.path;
        final method = request.method;
        methods.add(method);
        http.Response response(
          String body,
          int status, {
          Map<String, String> headers = const {},
        }) => http.Response(body, status, headers: headers, request: request);
        switch ((method, url)) {
          case ('PROPFIND', '/'):
            return response(
              _multi(
                _row(
                  '/',
                  '<C:calendar-home-set>'
                      '<D:href>/home/</D:href></C:calendar-home-set>',
                ),
              ),
              207,
            );
          case ('PROPFIND', '/home/'):
            return response(
              _multi(
                _row(
                      '/home/events/',
                      '<D:resourcetype><C:calendar/></D:resourcetype>'
                          '<C:supported-calendar-component-set><C:comp name="VEVENT"/>'
                          '</C:supported-calendar-component-set>$privileges',
                    ) +
                    _collection('/home/readonly/', 'Read only', 'VEVENT'),
              ),
              207,
            );
          case ('REPORT', '/home/events/'):
            expect(request.body, contains('<D:getetag/>'));
            return response(
              _multi(
                raw == null
                    ? ''
                    : _row(
                        path,
                        '<D:getetag>${tag()}</D:getetag>'
                        '<C:calendar-data><![CDATA[$raw]]></C:calendar-data>',
                      ),
              ),
              207,
            );
          case ('GET', path):
            return raw == null
                ? response('', 404)
                : response(raw!, 200, headers: {'etag': tag()});
          case ('PUT', path):
            if (loseWriteResponse) {
              throw http.ClientException('lost acknowledgement');
            }
            if (raw == null) {
              expect(request.headers['if-none-match'], '*');
              raw = request.body.replaceFirst(
                'END:VEVENT',
                'X-SERVER:keep\r\nEND:VEVENT',
              );
              revision++;
              return response('', 201);
            }
            if (request.headers['if-match'] != tag()) return response('', 412);
            expect(request.body, contains('X-SERVER:keep'));
            raw = request.body;
            revision++;
            return response('', 204);
          case ('DELETE', path):
            if (request.headers['if-match'] != tag()) return response('', 412);
            raw = null;
            return response('', 204);
          default:
            throw StateError('Unexpected test request.');
        }
      });
      final provider = CalDavCalendarProvider(
        account: TaskAccountId('calendar', provider: 'caldav'),
        settings: CalDavConnectionSettings(
          profile: CalDavServerProfile.generic,
          username: 'fixture',
          discoveryUrl: Uri.https('dav.example.test', '/'),
        ),
        client: client,
        appPassword: () async => 'fixture',
      );
      final discovered =
          await provider.discoverCalendars()
              as TaskSuccess<List<CalDavCalendar>>;
      final writable = discovered.value.first;
      final readOnly = discovered.value.last;
      Future<CalDavEditableEvent> open() async {
        final agenda =
            await provider.agenda(
                  writable,
                  start: now,
                  end: now.add(const Duration(days: 1)),
                )
                as TaskSuccess<CalDavAgenda>;
        final event = agenda.value.events.single;
        expect(provider.hasEventRevision(writable, event), isTrue);
        expect(provider.hasEventRevision(readOnly, event), isFalse);
        return (await provider.openEvent(writable, event)
                as TaskSuccess<CalDavEditableEvent>)
            .value;
      }

      expect(readOnly.canCreate, isFalse);
      final denied =
          await provider.createEvent(
                readOnly,
                operationId: 'operation',
                fields: fields('Draft'),
                timestamp: now,
              )
              as TaskFailure<TaskUnit>;
      expect(denied.problem.code, TaskProblemCode.permissionDenied);
      expect(methods, ['PROPFIND', 'PROPFIND']);
      final created = await provider.createEvent(
        writable,
        operationId: 'operation',
        fields: fields('Draft'),
        timestamp: now,
      );
      expect(created, isA<TaskSuccess<TaskUnit>>());
      final stale = await open();
      expect(stale.event.title, 'Draft');

      expect(
        await provider.updateEvent(
          stale,
          fields: fields('Revised'),
          timestamp: now,
        ),
        isA<TaskSuccess<TaskUnit>>(),
      );
      final rejected =
          await provider.updateEvent(
                stale,
                fields: fields('Stale'),
                timestamp: now,
              )
              as TaskFailure<TaskUnit>;
      expect(rejected.problem.code, TaskProblemCode.conflict);
      expect(rejected.problem.mutationMayHaveOccurred, isFalse);
      final staleDelete =
          await provider.deleteEvent(stale) as TaskFailure<TaskUnit>;
      expect(staleDelete.problem.code, TaskProblemCode.conflict);
      final current = await open();
      expect(current.event.title, 'Revised');
      expect(await provider.deleteEvent(current), isA<TaskSuccess<TaskUnit>>());
      expect(raw, isNull);

      loseWriteResponse = true;
      final failed =
          await provider.createEvent(
                writable,
                operationId: 'operation',
                fields: fields('Unknown outcome'),
                timestamp: now,
              )
              as TaskFailure<TaskUnit>;
      expect(failed.problem.mutationMayHaveOccurred, isTrue);
      expect(methods.where((method) => method == 'PUT'), hasLength(4));
    },
  );
}
