part of 'provider.dart';

final class CalDavCalendar {
  const CalDavCalendar._(this.account, this.url, this.name, this._privileges);

  final TaskAccountId account;
  final Uri url;
  final String name;
  final (bool, bool, bool) _privileges;

  bool get canCreate => _privileges.$1;
  bool get canUpdate => _privileges.$2;
  bool get canDelete => _privileges.$3;

  @override
  String toString() => 'CalDavCalendar(redacted)';
}

/// Bounded calendar queries and conditional single-event writes over CalDAV.
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
  final _eventTargets = Expando<_CalendarEventTarget>();

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
                _writePrivileges(entry.value),
              ),
        ]);
      });

  Future<TaskResult<CalDavAgenda>> agenda(
    CalDavCalendar calendar, {
    required DateTime start,
    required DateTime end,
  }) => _run(() async {
    if (!_validCalendar(calendar) ||
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
      '<C:calendar-query $namespaces><D:prop><D:getetag/>'
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
      final agenda = readCalDavAgenda(
        _requiredText(row, cal, 'calendar-data'),
        window: (start: start, end: end),
      );
      unexpanded += agenda.unexpandedSeries;
      events.addAll(agenda.events);
      final tag = _connection._etag(xmlValue(row.property(dav, 'getetag')));
      if (tag != null &&
          _strong(tag) &&
          agenda.events.length == 1 &&
          agenda.unexpandedSeries == 0) {
        final event = agenda.events.single;
        if (event.recurrenceId == null &&
            (event.start.kind == CalDavDateKind.date ||
                event.start.kind == CalDavDateKind.utc)) {
          _eventTargets[event] = _CalendarEventTarget(calendar.url, uri, tag);
        }
      }
      if (events.length > maxDavRows) {
        throw const DavFailure(TaskProblemCode.quotaExceeded);
      }
    }
    events.sort((a, b) => a.start.value.compareTo(b.start.value));
    return CalDavAgenda(events, unexpandedSeries: unexpanded);
  });

  /// True for report entries backed by a strong DAV revision. The
  /// authoritative resource is validated before the editor opens.
  bool hasEventRevision(CalDavCalendar calendar, CalDavEvent event) =>
      _validCalendar(calendar) &&
      _eventTargets[event]?.calendar == calendar.url;

  Future<TaskResult<CalDavEditableEvent>> openEvent(
    CalDavCalendar calendar,
    CalDavEvent event,
  ) => _run(() async {
    if (!calendar.canUpdate && !calendar.canDelete) {
      throw const DavFailure(TaskProblemCode.permissionDenied);
    }
    final target = _eventTargets[event];
    if (!hasEventRevision(calendar, event) || target == null) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    final response = await _connection._http.send(
      'GET',
      target.url,
      headers: {'accept': 'text/calendar'},
    );
    if (response.statusCode != 200) davStatus(response);
    if (_connection._etag(response.headers['etag']) != target.tag) {
      throw const DavFailure(TaskProblemCode.conflict);
    }
    final raw = utf8.decode(response.bodyBytes);
    final document = CalDavEventDocument.parse(raw);
    if (document.event.uid != event.uid) {
      throw const DavFailure(TaskProblemCode.conflict);
    }
    return CalDavEditableEvent._(this, calendar, target, document, raw);
  });

  Future<TaskResult<TaskUnit>> createEvent(
    CalDavCalendar calendar, {
    required String operationId,
    required CalDavEventFields fields,
    required DateTime timestamp,
  }) => _run(() async {
    if (!_validCalendar(calendar) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(operationId)) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    if (!calendar.canCreate) {
      throw const DavFailure(TaskProblemCode.permissionDenied);
    }
    final raw = _eventMutationBody(
      () => CalDavEventDocument.create(
        uid: 'event-$operationId@crispoffice',
        fields: fields,
        timestamp: timestamp,
      ),
    );
    final uri = collectionUri(
      calendar.url,
    ).resolve('crispoffice-event-$operationId.ics');
    await _writeEvent('PUT', uri, {'if-none-match': '*'}, body: raw);
    return TaskUnit.value;
  }, mutation: true);

  Future<TaskResult<TaskUnit>> updateEvent(
    CalDavEditableEvent editable, {
    required CalDavEventFields fields,
    required DateTime timestamp,
  }) => _run(() async {
    _checkEditable(editable, editable.calendar.canUpdate);
    final raw = _eventMutationBody(
      () => editable._document.update(fields, timestamp: timestamp),
    );
    if (raw != editable._raw) {
      await _writeEvent('PUT', editable._target.url, {
        'if-match': editable._target.tag,
      }, body: raw);
    }
    return TaskUnit.value;
  }, mutation: true);

  Future<TaskResult<TaskUnit>> deleteEvent(CalDavEditableEvent editable) =>
      _run(() async {
        _checkEditable(editable, editable.calendar.canDelete);
        await _writeEvent('DELETE', editable._target.url, {
          'if-match': editable._target.tag,
        });
        return TaskUnit.value;
      }, mutation: true);

  bool _validCalendar(CalDavCalendar calendar) =>
      calendar.account == _connection.account &&
      safeDavUri(calendar.url, _connection.settings.discoveryUrl);

  void _checkEditable(CalDavEditableEvent editable, bool allowed) {
    if (!identical(editable._provider, this) ||
        !_validCalendar(editable.calendar) ||
        !directMember(editable.calendar.url, editable._target.url)) {
      throw const DavFailure(TaskProblemCode.invalidInput);
    }
    if (!allowed) throw const DavFailure(TaskProblemCode.permissionDenied);
  }

  Future<void> _writeEvent(
    String method,
    Uri uri,
    Map<String, String> condition, {
    String? body,
  }) async {
    final response = await _connection._http.send(
      method,
      uri,
      body: body,
      headers: {
        ...condition,
        if (body != null) 'content-type': 'text/calendar; charset=utf-8',
      },
      mutation: true,
    );
    final success = method == 'DELETE'
        ? const {200, 204}
        : const {200, 201, 204};
    if (!success.contains(response.statusCode)) {
      davStatus(response, mutation: true);
    }
  }
}

/// An authoritative revision of a single appointment.
final class CalDavEditableEvent {
  const CalDavEditableEvent._(
    this._provider,
    this.calendar,
    this._target,
    this._document,
    this._raw,
  );

  final CalDavCalendarProvider _provider;
  final _CalendarEventTarget _target;
  final CalDavEventDocument _document;
  final String _raw;
  final CalDavCalendar calendar;

  CalDavEvent get event => _document.event;
}

final class _CalendarEventTarget {
  const _CalendarEventTarget(this.calendar, this.url, this.tag);

  final Uri calendar;
  final Uri url;
  final String tag;
}

String _eventMutationBody(String Function() encode) {
  try {
    return encode();
  } on FormatException {
    throw const DavFailure(TaskProblemCode.invalidInput);
  }
}

String _icalUtc(DateTime date) =>
    '${date.toIso8601String().split('.').first.replaceAll('-', '').replaceAll(':', '')}Z';
