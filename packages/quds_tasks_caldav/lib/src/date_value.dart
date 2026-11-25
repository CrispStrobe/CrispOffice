import 'package:quds_tasks_core/quds_tasks_core.dart';

/// iCalendar distinguishes a calendar date from three forms of date-time.
enum CalDavDateKind { date, floating, utc, zoned }

/// An iCalendar date without implicit conversion to the machine's time zone.
final class CalDavDateValue {
  const CalDavDateValue._(this.value, this.kind, this.timeZone);

  factory CalDavDateValue.parse(
    String value, {
    String? valueType,
    String? timeZone,
  }) {
    final type = valueType?.toUpperCase();
    if (type != null && type != 'DATE' && type != 'DATE-TIME') {
      throw const FormatException('Unsupported iCalendar date value type.');
    }
    final isDate = type == 'DATE';
    final pattern = isDate
        ? RegExp(r'^([0-9]{4})([0-9]{2})([0-9]{2})$')
        : RegExp(
            r'^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})(Z?)$',
          );
    final match = pattern.firstMatch(value);
    if (match == null) {
      throw const FormatException('Invalid iCalendar date or date-time.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = isDate ? 0 : int.parse(match.group(4)!);
    final minute = isDate ? 0 : int.parse(match.group(5)!);
    final second = isDate ? 0 : int.parse(match.group(6)!);
    final normalized = DateTime.utc(year, month, day, hour, minute, second);
    if (year < 1 ||
        normalized.year != year ||
        normalized.month != month ||
        normalized.day != day ||
        normalized.hour != hour ||
        normalized.minute != minute ||
        normalized.second != second) {
      throw const FormatException('Out-of-range iCalendar date or date-time.');
    }
    final isUtc = !isDate && match.group(7) == 'Z';
    if (timeZone != null &&
        (timeZone.isEmpty ||
            timeZone.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
            isDate ||
            isUtc)) {
      throw const FormatException('Invalid TZID for this date value.');
    }
    return CalDavDateValue._(
      value,
      isDate
          ? CalDavDateKind.date
          : isUtc
          ? CalDavDateKind.utc
          : timeZone == null
          ? CalDavDateKind.floating
          : CalDavDateKind.zoned,
      timeZone,
    );
  }

  factory CalDavDateValue.fromTaskDate(TaskDateValue date) {
    return switch (date) {
      TaskDate(:final year, :final month, :final day) => CalDavDateValue.parse(
        '${year.toString().padLeft(4, '0')}'
        '${month.toString().padLeft(2, '0')}'
        '${day.toString().padLeft(2, '0')}',
        valueType: 'DATE',
      ),
      TaskDateTime(:final localDateTime, :final timeZone) => _fromTaskDateTime(
        localDateTime,
        timeZone,
      ),
    };
  }

  /// Basic iCalendar form, e.g. `20261125` or `20261125T143000Z`.
  final String value;
  final CalDavDateKind kind;
  final String? timeZone;

  TaskDateValue toTaskDate() {
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(4, 6));
    final day = int.parse(value.substring(6, 8));
    if (kind == CalDavDateKind.date) return TaskDate(year, month, day);
    final wallTime =
        '${value.substring(0, 4)}-${value.substring(4, 6)}-'
        '${value.substring(6, 8)}T${value.substring(9, 11)}:'
        '${value.substring(11, 13)}:${value.substring(13, 15)}';
    return TaskDateTime(
      wallTime,
      timeZone: kind == CalDavDateKind.utc ? 'UTC' : timeZone,
    );
  }

  /// The containing resource needs a matching VTIMEZONE for a zoned value,
  /// unless its server negotiated timezone-by-reference.
  String contentLine(String property) {
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(property)) {
      throw ArgumentError('Invalid iCalendar date property name.');
    }
    return switch (kind) {
      CalDavDateKind.date => '$property;VALUE=DATE:$value',
      CalDavDateKind.zoned =>
        '$property;TZID=${_encodeParameter(timeZone!)}:$value',
      CalDavDateKind.floating || CalDavDateKind.utc => '$property:$value',
    };
  }

  static CalDavDateValue _fromTaskDateTime(String value, String? zone) {
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.0{1,9})?$',
    ).hasMatch(value)) {
      throw const FormatException(
        'CalDAV task date-times require whole seconds and no numeric offset.',
      );
    }
    final basic = value
        .split('.')
        .first
        .replaceAll('-', '')
        .replaceAll(':', '');
    return CalDavDateValue.parse(
      zone == 'UTC' ? '${basic}Z' : basic,
      timeZone: zone == 'UTC' ? null : zone,
    );
  }

  static String _encodeParameter(String value) {
    final escaped = value.replaceAll('^', '^^').replaceAll('"', "^'");
    return escaped.contains(RegExp(r'[:,;]')) ? '"$escaped"' : escaped;
  }
}
