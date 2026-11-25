import 'dart:convert';

import 'package:quds_tasks_core/quds_tasks_core.dart';

String encodeFields(TaskFields fields) => jsonEncode({
  'title': fields.title,
  'notes': [
    if (fields.notes case final text?) ...[text.value, text.format.name],
  ],
  'status': fields.status.name,
  'priority': fields.priority.name,
  'start': _date(fields.start),
  'due': _date(fields.due),
  'reminder': _date(fields.reminder),
  'completed': _date(fields.completedAt),
});

TaskFields decodeFields(String json) {
  final map = jsonDecode(json) as Map<String, Object?>;
  return TaskFields(
    title: map['title'] as String,
    notes: switch (map['notes']) {
      [] => null,
      [final String value, final String format] => TaskText(
        value,
        format: TaskTextFormat.values.byName(format),
      ),
      _ => throw const FormatException('Malformed stored task notes.'),
    },
    status: TaskStatus.values.byName(map['status'] as String),
    priority: TaskPriority.values.byName(map['priority'] as String),
    start: _readDate(map['start']),
    due: _readDate(map['due']),
    reminder: _readDate(map['reminder']),
    completedAt: _readDate(map['completed']),
  );
}

Object? _date(TaskDateValue? date) => switch (date) {
  TaskDate(:final year, :final month, :final day) => [year, month, day],
  TaskDateTime(:final localDateTime, :final timeZone) => [
    localDateTime,
    timeZone,
  ],
  null => null,
};

TaskDateValue? _readDate(Object? stored) => switch (stored) {
  [final int year, final int month, final int day] => TaskDate(
    year,
    month,
    day,
  ),
  [final String time, final String? zone] => TaskDateTime(time, timeZone: zone),
  null => null,
  _ => throw const FormatException('Malformed stored task date.'),
};
