part of 'provider.dart';

final class CalDavCalendar {
  const CalDavCalendar._(this.account, this.url, this.name);

  final TaskAccountId account;
  final Uri url;
  final String name;

  @override
  String toString() => 'CalDavCalendar(redacted)';
}

/// Read-only calendar discovery and bounded agenda queries using the same
/// authenticated DAV connection rules as Tasks.
final class CalDavCalendarProvider {
  CalDavCalendarProvider({
    required TaskAccountId account,
    required CalDavConnectionSettings settings,
    required http.Client client,
    required Future<String?> Function() appPassword,
  }) : _connection = CalDavTaskProvider(
         account: account,
         settings: settings,
         client: client,
         appPassword: appPassword,
       );

  final CalDavTaskProvider _connection;

  Future<TaskResult<List<CalDavCalendar>>> discoverCalendars() =>
      _run(() async {
        final rows = await _connection._discoverCollectionRows();
        return List.unmodifiable([
          for (final entry in rows.entries)
            if (_supportsComponent(entry.value, 'VEVENT'))
              CalDavCalendar._(
                _connection.account,
                entry.key,
                _collectionName(entry.value, entry.key),
              ),
        ]);
      });

  Future<TaskResult<CalDavAgenda>> agenda(
    CalDavCalendar calendar, {
    required DateTime start,
    required DateTime end,
  }) => _run(() async {
    if (calendar.account != _connection.account ||
        !safeDavUri(calendar.url, _connection.settings.discoveryUrl) ||
        !start.isUtc ||
        !end.isUtc ||
        !start.isBefore(end) ||
        end.difference(start) > const Duration(days: 45) ||
        start.year < 1 ||
        end.year > 9999) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    final range = 'start="${_icalUtc(start)}" end="${_icalUtc(end)}"';
    final data = await _connection._multi(
      'REPORT',
      calendar.url,
      '<C:calendar-query $namespaces><D:prop>'
          '<C:calendar-data><C:expand $range/></C:calendar-data>'
          '</D:prop><C:filter><C:comp-filter name="VCALENDAR">'
          '<C:comp-filter name="VEVENT"><C:time-range $range/></C:comp-filter>'
          '</C:comp-filter></C:filter></C:calendar-query>',
      depth: '1',
    );
    final events = <CalDavEvent>[];
    final seen = <Uri>{};
    var unexpanded = 0;
    for (final row in data.rows) {
      if (row.status case final status?) davStatusCode(status);
      final uri = _connection._remoteUri(calendar.url, row.href);
      if (!directMember(calendar.url, uri) || !seen.add(uri)) {
        throw const FormatException(
          'Calendar report contains an unexpected resource.',
        );
      }
      final agenda = readCalDavAgenda(_requiredText(row, cal, 'calendar-data'));
      unexpanded += agenda.unexpandedSeries;
      events.addAll(agenda.events);
      if (events.length > maxDavRows) {
        throw const DavFailure(TaskProblemCode.quotaExceeded);
      }
    }
    events.sort((a, b) => a.start.value.compareTo(b.start.value));
    return CalDavAgenda(events, unexpandedSeries: unexpanded);
  });
}

String _icalUtc(DateTime date) =>
    '${date.toIso8601String().split('.').first.replaceAll('-', '').replaceAll(':', '')}Z';
