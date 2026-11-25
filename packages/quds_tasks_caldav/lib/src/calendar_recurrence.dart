part of 'todo_document.dart';

const _calendarWeekdays = {
  'MO': DateTime.monday,
  'TU': DateTime.tuesday,
  'WE': DateTime.wednesday,
  'TH': DateTime.thursday,
  'FR': DateTime.friday,
  'SA': DateTime.saturday,
  'SU': DateTime.sunday,
};

/// Expands the daily and weekly subset in a bounded query window. UTC is an
/// instant for UTC events, and a surrogate for DATE and floating wall values.
List<CalDavEvent>? _expandCalendarSeries(
  _AgendaComponent component,
  List<_AgendaComponent> overrides,
  ({DateTime start, DateTime end}) window,
) {
  const maxInstances = 512;
  try {
    final event = _readEvent(component.properties);
    final kind = event.start.kind;
    if (kind == CalDavDateKind.zoned ||
        event.recurrenceId != null ||
        component.properties.containsKey('DURATION') ||
        (event.end != null && event.end!.kind != kind) ||
        component.recurrence.length > maxInstances ||
        overrides.length > maxInstances) {
      return null;
    }
    final anchor = _calendarClock(event.start);
    final duration = _calendarDuration(event);
    if (duration.isNegative) return null;
    final first = _calendarBoundary(window.start, kind);
    final limit = _calendarBoundary(window.end, kind);
    if (!first.isBefore(limit)) return null;
    bool overlaps(DateTime start) =>
        start.isBefore(limit) &&
        (duration == Duration.zero
            ? !start.isBefore(first)
            : start.add(duration).isAfter(first));

    final excluded = <DateTime>{};
    final included = <DateTime>{if (overlaps(anchor)) anchor};
    _CalendarRule? rule;
    var suppliedDates = 0;
    for (final property in component.recurrence) {
      switch (property.name) {
        case 'RRULE':
          if (rule != null || property.rawParameters.isNotEmpty) return null;
          rule = _CalendarRule.parse(property.value, event.start, anchor);
        case 'RDATE' || 'EXDATE':
          final target = property.name == 'EXDATE' ? excluded : included;
          final values = property.value.split(',');
          suppliedDates += values.length;
          if (suppliedDates > maxInstances) return null;
          for (final value in values) {
            final date = _eventDate(property, value)!;
            if (date.kind != kind) return null;
            final clock = _calendarClock(date);
            if (overlaps(clock)) target.add(clock);
            if (target.length > maxInstances) return null;
          }
        default:
          return null;
      }
    }

    final overrideDates = <DateTime>{};
    for (final override in overrides) {
      final property = override.recurrenceId!;
      if (property.parameter('RANGE') != null) return null;
      final id = _eventDate(property)!;
      if (id.kind != kind || !overrideDates.add(_calendarClock(id))) {
        return null;
      }
    }
    if (rule != null) {
      for (final start in rule.inWindow(first.subtract(duration), limit)) {
        if (overlaps(start)) included.add(start);
        if (included.length > maxInstances) return null;
      }
    }
    included
      ..removeAll(excluded)
      ..removeAll(overrideDates);
    final ordered = included.toList()..sort();
    if (ordered.any((start) => start.add(duration).year > 9999)) return null;
    return [
      for (final start in ordered)
        CalDavEvent._(
          uid: event.uid,
          title: event.title,
          start: _calendarDate(start, kind),
          end: event.end == null
              ? null
              : _calendarDate(start.add(duration), kind),
          location: event.location,
          description: event.description,
          recurrenceId: _calendarDate(start, kind),
        ),
    ];
  } on FormatException {
    return null;
  }
}

Duration _calendarDuration(CalDavEvent event) {
  final end = event.end;
  if (end != null) {
    return _calendarClock(end).difference(_calendarClock(event.start));
  }
  return event.start.kind == CalDavDateKind.date
      ? const Duration(days: 1)
      : Duration.zero;
}

DateTime _calendarBoundary(DateTime value, CalDavDateKind kind) {
  if (kind == CalDavDateKind.utc) return value;
  final local = value.toLocal();
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );
}

bool _overlapsCalendarWindow(
  CalDavEvent event,
  ({DateTime start, DateTime end}) window,
) {
  final kind = event.start.kind;
  if (kind == CalDavDateKind.zoned ||
      event.end != null && event.end!.kind != kind) {
    return true;
  }
  final from = _calendarClock(event.start);
  final duration = _calendarDuration(event);
  final start = _calendarBoundary(window.start, kind);
  return from.isBefore(_calendarBoundary(window.end, kind)) &&
      (duration == Duration.zero
          ? !from.isBefore(start)
          : from.add(duration).isAfter(start));
}

DateTime _calendarClock(CalDavDateValue value) => DateTime.parse(
  value.kind == CalDavDateKind.date
      ? '${value.value}T000000Z'
      : value.kind == CalDavDateKind.utc
      ? value.value
      : '${value.value}Z',
);

CalDavDateValue _calendarDate(DateTime clock, CalDavDateKind kind) {
  final basic = clock
      .toIso8601String()
      .split('.')
      .first
      .replaceAll('-', '')
      .replaceAll(':', '');
  return CalDavDateValue.parse(switch (kind) {
    CalDavDateKind.date => basic.substring(0, 8),
    CalDavDateKind.utc => '${basic}Z',
    _ => basic,
  }, valueType: kind == CalDavDateKind.date ? 'DATE' : null);
}

final class _CalendarRule {
  const _CalendarRule(
    this.anchor,
    this.base,
    this.period,
    this.offsets,
    this.count,
    this.until,
  );

  final DateTime anchor;
  final DateTime base;
  final int period;
  final List<int> offsets;
  final int? count;
  final DateTime? until;

  factory _CalendarRule.parse(
    String value,
    CalDavDateValue start,
    DateTime anchor,
  ) {
    const unsupported = FormatException(
      'Unsupported calendar recurrence rule.',
    );
    final fields = <String, String>{};
    for (final part in value.toUpperCase().split(';')) {
      final pair = part.split('=');
      if (pair.length != 2 || fields.containsKey(pair.first)) throw unsupported;
      fields[pair.first] = pair.last;
    }
    if (fields.keys.any(
      (key) => !const {
        'FREQ',
        'INTERVAL',
        'COUNT',
        'UNTIL',
        'WKST',
        'BYDAY',
      }.contains(key),
    )) {
      throw unsupported;
    }
    int positive(String text) {
      final number = int.tryParse(text);
      if (number == null ||
          number < 1 ||
          number > 2147483647 ||
          !RegExp(r'^[0-9]+$').hasMatch(text)) {
        throw unsupported;
      }
      return number;
    }

    final interval = positive(fields['INTERVAL'] ?? '1');
    final count = fields['COUNT'] == null ? null : positive(fields['COUNT']!);
    final untilValue = fields['UNTIL'];
    if (count != null && untilValue != null) throw unsupported;
    final until = untilValue == null
        ? null
        : CalDavDateValue.parse(
            untilValue,
            valueType: start.kind == CalDavDateKind.date ? 'DATE' : null,
          );
    if (until != null && until.kind != start.kind) throw unsupported;
    final last = until == null ? null : _calendarClock(until);
    if (last != null && last.isBefore(anchor)) throw unsupported;
    final weekStart = _calendarWeekdays[fields['WKST'] ?? 'MO'];
    if (weekStart == null) throw unsupported;
    final weekdays = fields['BYDAY']?.split(',').map(_calendarWeekdaysForRule);
    final selected = weekdays?.toSet();
    if (selected != null && !selected.contains(anchor.weekday)) {
      throw unsupported;
    }
    switch (fields['FREQ']) {
      case 'DAILY':
        if (selected == null) {
          return _CalendarRule(anchor, anchor, interval, [0], count, last);
        }
        // After seven intervals the weekday sequence repeats.
        final offsets = [
          for (var step = 0; step < 7; step++)
            if (selected.contains(
              (anchor.weekday - 1 + step * interval) % 7 + 1,
            ))
              step * interval,
        ];
        return _CalendarRule(
          anchor,
          anchor,
          interval * 7,
          offsets,
          count,
          last,
        );
      case 'WEEKLY':
        final offsets =
            (selected ?? {anchor.weekday})
                .map((day) => (day - weekStart) % 7)
                .toList()
              ..sort();
        final base = anchor.subtract(
          Duration(days: (anchor.weekday - weekStart) % 7),
        );
        return _CalendarRule(anchor, base, interval * 7, offsets, count, last);
      default:
        throw unsupported;
    }
  }

  static int _calendarWeekdaysForRule(String value) {
    final weekday = _calendarWeekdays[value];
    if (weekday == null) {
      throw const FormatException('Invalid recurrence weekday.');
    }
    return weekday;
  }

  Iterable<DateTime> inWindow(DateTime first, DateTime limit) sync* {
    var cycle = first.isAfter(base)
        ? first.difference(base).inDays ~/ period
        : 0;
    final beforeAnchor = anchor.difference(base).inDays;
    final omitted = offsets.where((day) => day < beforeAnchor).length;
    final lastDay = limit.difference(base).inDays;
    // Compare the cycle numerically before constructing dates. A valid rule
    // can have an interval far larger than the supported calendar window.
    while (cycle * period <= lastDay) {
      for (var index = 0; index < offsets.length; index++) {
        final day = cycle * period + offsets[index];
        if (day < beforeAnchor) continue;
        final ordinal = cycle * offsets.length + index - omitted;
        if (count != null && ordinal >= count!) return;
        final candidate = base.add(Duration(days: day));
        if (!candidate.isBefore(limit) ||
            (until != null && candidate.isAfter(until!))) {
          return;
        }
        if (!candidate.isBefore(first)) yield candidate;
      }
      cycle++;
    }
  }
}
