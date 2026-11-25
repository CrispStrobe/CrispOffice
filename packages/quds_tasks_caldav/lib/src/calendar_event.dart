part of 'todo_document.dart';

/// An event or an expanded recurrence instance. Dates retain their source zone.
final class CalDavEvent {
  const CalDavEvent._({
    required this.uid,
    required this.title,
    required this.start,
    this.end,
    this.location,
    this.recurrenceId,
  });

  final String uid;
  final String title;
  final CalDavDateValue start;
  final CalDavDateValue? end;
  final String? location;
  final CalDavDateValue? recurrenceId;
}

final class CalDavAgenda {
  CalDavAgenda(List<CalDavEvent> events, {required this.unexpandedSeries})
    : events = List.unmodifiable(events);

  final List<CalDavEvent> events;
  final int unexpandedSeries;
}

/// Reads VEVENTs from a server-expanded iCalendar report, including VTIMEZONE
/// and VALARM siblings and children. Series the server did not expand are
/// reported separately rather than shown only once.
CalDavAgenda readCalDavAgenda(String source) {
  _validateSource(source);
  final stack = <String>[];
  final events = <CalDavEvent>[];
  final properties = <String, _Property>{};
  var roots = 0;
  var versions = 0;
  var unexpanded = 0;
  const fields = {
    'UID',
    'SUMMARY',
    'DTSTART',
    'DTEND',
    'LOCATION',
    'RECURRENCE-ID',
    'RRULE',
    'RDATE',
    'STATUS',
  };
  for (final line in _readLines(source)) {
    final property = _Property.parse(line.content);
    switch (property.name) {
      case 'BEGIN' || 'END':
        if (property.rawParameters.isNotEmpty) {
          throw const FormatException('Invalid calendar component marker.');
        }
        final component = property.value.toUpperCase();
        if (property.name == 'BEGIN') {
          if (stack.length == CalDavCodecLimits.maxComponentDepth ||
              (stack.isEmpty && (component != 'VCALENDAR' || ++roots != 1)) ||
              (stack.isNotEmpty && component == 'VCALENDAR') ||
              (component == 'VEVENT' && stack.length != 1)) {
            throw const FormatException(
              'Invalid calendar component hierarchy.',
            );
          }
          if (component == 'VEVENT') properties.clear();
          stack.add(component);
        } else {
          if (stack.isEmpty || stack.removeLast() != component) {
            throw const FormatException('Unbalanced calendar component.');
          }
          if (component == 'VEVENT') {
            if (properties.containsKey('RRULE') ||
                properties.containsKey('RDATE')) {
              unexpanded++;
            } else if (properties['STATUS']?.value.toUpperCase() !=
                'CANCELLED') {
              events.add(_readEvent(properties));
            }
          }
        }
      default:
        if (stack.isEmpty) {
          throw const FormatException('Calendar property has no component.');
        }
        if (stack.length == 1 &&
            property.name == 'VERSION' &&
            (property.value != '2.0' || ++versions != 1)) {
          throw const FormatException('Expected one iCalendar VERSION:2.0.');
        }
        if (stack.length == 2 &&
            stack.last == 'VEVENT' &&
            fields.contains(property.name)) {
          if (properties.containsKey(property.name) &&
              !const {'RRULE', 'RDATE'}.contains(property.name)) {
            throw const FormatException('Duplicate VEVENT property.');
          }
          properties[property.name] = property;
        }
    }
  }
  if (stack.isNotEmpty || roots != 1 || versions != 1) {
    throw const FormatException('Incomplete iCalendar resource.');
  }
  return CalDavAgenda(events, unexpandedSeries: unexpanded);
}

CalDavEvent _readEvent(Map<String, _Property> properties) {
  String? text(String key) => switch (properties[key]) {
    final entry? => _decodeText(entry.value),
    null => null,
  };
  CalDavDateValue? date(String key) => switch (properties[key]) {
    final entry? => CalDavDateValue.parse(
      entry.value,
      valueType: entry.parameter('VALUE'),
      timeZone: entry.parameter('TZID'),
    ),
    null => null,
  };
  final uid = text('UID');
  final start = date('DTSTART');
  if (uid == null || uid.isEmpty || start == null) {
    throw const FormatException('VEVENT requires UID and DTSTART.');
  }
  final end = date('DTEND');
  if (end != null &&
      (start.kind == CalDavDateKind.date) !=
          (end.kind == CalDavDateKind.date)) {
    throw const FormatException(
      'VEVENT date and time bounds are incompatible.',
    );
  }
  return CalDavEvent._(
    uid: uid,
    title: text('SUMMARY') ?? '',
    start: start,
    end: end,
    location: text('LOCATION'),
    recurrenceId: date('RECURRENCE-ID'),
  );
}
