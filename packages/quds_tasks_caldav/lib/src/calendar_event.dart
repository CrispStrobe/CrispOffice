part of 'todo_document.dart';

/// An event or an expanded recurrence instance. Dates retain their source zone.
final class CalDavEvent {
  const CalDavEvent({
    required this.uid,
    required this.title,
    required this.start,
    this.end,
    this.location,
    this.description,
    this.recurrenceId,
  });

  final String uid;
  final String title;
  final CalDavDateValue start;
  final CalDavDateValue? end;
  final String? location;
  final String? description;
  final CalDavDateValue? recurrenceId;
}

final class CalDavAgenda {
  CalDavAgenda(List<CalDavEvent> events, {required this.unexpandedSeries})
    : events = List.unmodifiable(events);

  final List<CalDavEvent> events;
  final int unexpandedSeries;
}

/// Reads VEVENTs from a server-expanded iCalendar report, including VTIMEZONE
/// and VALARM siblings and children. A bounded [window] also allows local
/// expansion of supported series the server returned unexpanded.
CalDavAgenda readCalDavAgenda(
  String source, {
  ({DateTime start, DateTime end})? window,
}) {
  if (window != null &&
      (!window.start.isUtc ||
          !window.end.isUtc ||
          !window.start.isBefore(window.end) ||
          window.end.difference(window.start) > const Duration(days: 45))) {
    throw ArgumentError('Calendar expansion requires a bounded UTC window.');
  }
  _validateSource(source);
  final stack = <String>[];
  final components = <_AgendaComponent>[];
  var properties = <String, _Property>{};
  var recurrence = <_Property>[];
  var roots = 0;
  var versions = 0;
  const fields = {
    'UID',
    'SUMMARY',
    'DTSTART',
    'DTEND',
    'LOCATION',
    'DESCRIPTION',
    'DURATION',
    'RECURRENCE-ID',
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
          if (component == 'VEVENT') {
            properties = {};
            recurrence = [];
          }
          stack.add(component);
        } else {
          if (stack.isEmpty || stack.removeLast() != component) {
            throw const FormatException('Unbalanced calendar component.');
          }
          if (component == 'VEVENT') {
            components.add(_AgendaComponent(properties, recurrence));
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
        if (stack.length == 2 && stack.last == 'VEVENT') {
          if (const {
            'RRULE',
            'RDATE',
            'EXDATE',
            'EXRULE',
          }.contains(property.name)) {
            recurrence.add(property);
          } else if (fields.contains(property.name)) {
            if (properties.containsKey(property.name)) {
              throw const FormatException('Duplicate VEVENT property.');
            }
            properties[property.name] = property;
          }
        }
    }
  }
  if (stack.isNotEmpty || roots != 1 || versions != 1) {
    throw const FormatException('Incomplete iCalendar resource.');
  }
  final events = <CalDavEvent>[];
  final related = <String, List<_AgendaComponent>>{};
  final masters = <String, int>{};
  for (final component in components) {
    final uid = component.uid;
    if (uid == null) continue;
    if (component.recurrenceId != null) {
      related.putIfAbsent(uid, () => []).add(component);
    } else if (component.recurrence.isNotEmpty && !component.cancelled) {
      masters.update(uid, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final unresolvedRanges = <String?>{};
  var unexpanded = 0;
  for (final component in components) {
    final uid = component.uid;
    if (component.recurrenceId?.parameter('RANGE') != null) {
      if (!masters.containsKey(uid) && unresolvedRanges.add(uid)) unexpanded++;
      continue;
    }
    if (component.cancelled) continue;
    if (component.recurrence.isEmpty) {
      final event = _readEvent(component.properties);
      if (window == null ||
          event.recurrenceId == null ||
          !masters.containsKey(uid) ||
          component.properties.containsKey('DURATION') ||
          _overlapsCalendarWindow(event, window)) {
        events.add(event);
      }
      continue;
    }
    final instances = window == null || masters[uid] != 1
        ? null
        : _expandCalendarSeries(component, related[uid] ?? const [], window);
    if (instances == null) {
      unexpanded++;
    } else {
      events.addAll(instances);
    }
    if (events.length > 4096) {
      throw const FormatException('Too many event instances in one resource.');
    }
  }
  return CalDavAgenda(events, unexpandedSeries: unexpanded);
}

final class _AgendaComponent {
  const _AgendaComponent(this.properties, this.recurrence);

  final Map<String, _Property> properties;
  final List<_Property> recurrence;

  String? get uid => _eventText(properties['UID']);
  _Property? get recurrenceId => properties['RECURRENCE-ID'];
  bool get cancelled =>
      properties['STATUS']?.value.toUpperCase() == 'CANCELLED';
}

String? _eventText(_Property? property) =>
    property == null ? null : _decodeText(property.value);

CalDavDateValue? _eventDate(_Property? property, [String? value]) =>
    property == null
    ? null
    : CalDavDateValue.parse(
        value ?? property.value,
        valueType: property.parameter('VALUE'),
        timeZone: property.parameter('TZID'),
      );

CalDavEvent _readEvent(Map<String, _Property> properties) {
  String? text(String key) => _eventText(properties[key]);
  CalDavDateValue? date(String key) => _eventDate(properties[key]);
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
  return CalDavEvent(
    uid: uid,
    title: text('SUMMARY') ?? '',
    start: start,
    end: end,
    location: text('LOCATION'),
    description: text('DESCRIPTION'),
    recurrenceId: date('RECURRENCE-ID'),
  );
}
