import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

final class EwsCalendar {
  const EwsCalendar({required this.id, required this.name});

  final TaskListId id;
  final String name;
}

/// CalendarView returns individual events, including expanded occurrences.
final class EwsCalendarEvent {
  const EwsCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    this.allDayStart,
    this.allDayEnd,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;

  /// Civil dates represented at midnight UTC. The end date is exclusive.
  final DateTime? allDayStart;
  final DateTime? allDayEnd;
}

abstract interface class EwsCalendarReader {
  Future<TaskResult<List<EwsCalendar>>> calendars(MailOperationLease lease);

  Future<TaskResult<List<EwsCalendarEvent>>> agenda(
    TaskListId calendar, {
    required DateTime start,
    required DateTime end,
    required MailOperationLease lease,
  });
}
