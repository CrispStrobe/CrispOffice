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
