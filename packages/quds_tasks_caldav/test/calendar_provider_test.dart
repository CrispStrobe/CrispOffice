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
RRULE:FREQ=DAILY
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
