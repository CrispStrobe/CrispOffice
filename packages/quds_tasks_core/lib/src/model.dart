import 'identity.dart';

enum TaskStatus {
  notStarted,
  inProgress,
  completed,
  waitingOnOthers,
  deferred,
  cancelled,
}

enum TaskPriority { low, normal, high }

enum TaskTextFormat { text, html }

final class TaskText {
  const TaskText(this.value, {this.format = TaskTextFormat.text});
  final String value;
  final TaskTextFormat format;

  @override
  bool operator ==(Object other) =>
      other is TaskText && other.value == value && other.format == format;
  @override
  int get hashCode => Object.hash(value, format);
  @override
  String toString() => 'TaskText(${format.name}, redacted)';
}

/// A civil date and a wall-clock time are different values. Neither consults
/// the machine's timezone or implies conversion to an instant.
sealed class TaskDateValue {
  const TaskDateValue();
}

final class TaskDate extends TaskDateValue {
  TaskDate(this.year, this.month, this.day) {
    _validateDate(year, month, day);
  }

  final int year;
  final int month;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is TaskDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() => 'TaskDate(redacted)';
}

/// ISO wall time with seconds and optional fractional seconds, without Z or an
/// offset. [timeZone] retains the provider's Windows/IANA identifier verbatim;
/// `UTC` represents UTC and null represents a floating time. This type does not
/// claim that different timezone identifiers denote the same timezone.
final class TaskDateTime extends TaskDateValue {
  TaskDateTime(this.localDateTime, {this.timeZone}) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?$',
    ).firstMatch(localDateTime);
    if (match == null) {
      throw ArgumentError('Expected an ISO wall time without an offset.');
    }
    _validateDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (int.parse(match.group(4)!) > 23 ||
        int.parse(match.group(5)!) > 59 ||
        int.parse(match.group(6)!) > 59 ||
        (timeZone != null &&
            (timeZone!.isEmpty ||
                timeZone!.length > 255 ||
                timeZone!.contains(RegExp(r'[\x00-\x1f\x7f]'))))) {
      throw ArgumentError('Invalid task wall time or timezone identifier.');
    }
  }

  final String localDateTime;
  final String? timeZone;

  String get _comparableTime => localDateTime.contains('.')
      ? localDateTime
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '')
      : localDateTime;

  @override
  bool operator ==(Object other) =>
      other is TaskDateTime &&
      other._comparableTime == _comparableTime &&
      other.timeZone == timeZone;
  @override
  int get hashCode => Object.hash(_comparableTime, timeZone);
  @override
  String toString() => 'TaskDateTime(redacted)';
}

void _validateDate(int year, int month, int day) {
  if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
    throw ArgumentError('Invalid civil task date.');
  }
  final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  final days = <int>[
    31,
    leap ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];
  if (day > days[month - 1]) throw ArgumentError('Invalid civil task date.');
}

/// The common editable projection. Provider-specific fields remain in
/// [TaskProviderData]; an adapter writes only explicitly changed fields.
final class TaskFields {
  const TaskFields({
    required this.title,
    this.notes,
    this.status = TaskStatus.notStarted,
    this.priority = TaskPriority.normal,
    this.start,
    this.due,
    this.reminder,
    this.completedAt,
  });

  final String title;
  final TaskText? notes;
  final TaskStatus status;
  final TaskPriority priority;
  final TaskDateValue? start;
  final TaskDateValue? due;
  final TaskDateValue? reminder;
  final TaskDateValue? completedAt;

  @override
  bool operator ==(Object other) =>
      other is TaskFields &&
      other.title == title &&
      other.notes == notes &&
      other.status == status &&
      other.priority == priority &&
      other.start == start &&
      other.due == due &&
      other.reminder == reminder &&
      other.completedAt == completedAt;
  @override
  int get hashCode => Object.hash(
    title,
    notes,
    status,
    priority,
    start,
    due,
    reminder,
    completedAt,
  );
  @override
  String toString() => 'TaskFields(redacted)';
}

/// Exact retained provider representation. This can contain personal content;
/// it belongs in protected application storage, never routine diagnostics.
final class TaskProviderData {
  TaskProviderData({required this.format, required this.raw}) {
    validateTaskIdentity(format);
  }
  final String format;
  final String raw;
  @override
  String toString() => 'TaskProviderData(redacted)';
}

final class RemoteTask {
  const RemoteTask({
    required this.id,
    required this.fields,
    this.revision,
    this.providerData,
  });
  final TaskId id;
  final TaskFields fields;
  final String? revision;
  final TaskProviderData? providerData;
  @override
  String toString() => 'RemoteTask(redacted)';
}

final class TaskList {
  const TaskList({
    required this.id,
    required this.name,
    this.readOnly = false,
    this.revision,
    this.providerData,
  });
  final TaskListId id;
  final String name;
  final bool readOnly;
  final String? revision;
  final TaskProviderData? providerData;
  @override
  String toString() => 'TaskList(redacted)';
}

enum TaskCapability {
  listTasks,
  createTasks,
  updateTasks,
  deleteTasks,
  delta,
  conditionalWrites,
  notes,
  htmlNotes,
  startDates,
  dueDates,
  reminders,
  recurrence,
  checklist,
  attachments,
  sharedLists,
}

final class TaskCapabilities {
  TaskCapabilities(Iterable<TaskCapability> supported)
    : supported = Set.unmodifiable(supported);
  const TaskCapabilities.none() : supported = const {};
  final Set<TaskCapability> supported;
  bool supports(TaskCapability capability) => supported.contains(capability);
}
