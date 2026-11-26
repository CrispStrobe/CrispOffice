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
    this.appointmentRevision,
    this.description,
    this.categories = const [],
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final String? description;
  final List<String> categories;

  /// Present only for a standalone timed appointment without invitations.
  final String? appointmentRevision;

  EwsAppointmentFields get appointmentFields => (
    title: title,
    start: start,
    end: end,
    location: location,
    description: description,
  );

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

typedef EwsAppointmentFields = ({
  String title,
  DateTime start,
  DateTime end,
  String? location,
  String? description,
});

abstract interface class EwsCalendarWriter implements EwsCalendarReader {
  bool get canDeleteAppointments;

  Future<TaskResult<EwsCalendarEvent>> openAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    MailOperationLease lease,
  );

  Future<TaskResult<TaskUnit>> createAppointment(
    TaskListId calendar,
    EwsAppointmentFields fields,
    MailOperationLease lease, {
    bool Function()? canWrite,
  });

  Future<TaskResult<TaskUnit>> updateAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    EwsAppointmentFields fields,
    MailOperationLease lease, {
    bool Function()? canWrite,
  });

  Future<TaskResult<TaskUnit>> deleteAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    MailOperationLease lease, {
    bool Function()? canWrite,
  });
}
