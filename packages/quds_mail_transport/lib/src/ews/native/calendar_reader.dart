part of 'provider.dart';

final class NativeEwsCalendarReader implements EwsCalendarWriter {
  NativeEwsCalendarReader({
    required this.account,
    required this.connection,
    this.canDeleteAppointments = false,
  });

  @override
  final bool canDeleteAppointments;

  final TaskAccountId account;
  final NativeMailEwsProvider connection;
  final _folders = <TaskListId>{};

  @override
  Future<TaskResult<List<EwsCalendar>>> calendars(
    MailOperationLease lease,
  ) async {
    final result = await connection._run(lease, (client, operation) async {
      final soap = connection._soap;
      final xml = await operation.post(
        client,
        'GetFolder',
        soap.getFolder('calendar', distinguished: true),
      );
      final primary = soap.folders(xml, 'GetFolder').folders.singleOrNull;
      if (primary == null || primary.folderClass != 'IPF.Appointment') {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      final folders = {primary.id: primary};
      final additional = await connection._findFolders(
        client,
        operation,
        folderClass: 'IPF.Appointment',
      );
      for (final folder in additional) {
        if (folder.folderClass != 'IPF.Appointment') {
          throw const EwsException(MailProblemCode.providerFailure);
        }
        folders.putIfAbsent(folder.id, () => folder);
      }
      if (folders.length > connection.limits.maxMailboxes) {
        throw const EwsException(MailProblemCode.quotaExceeded);
      }
      return List<EwsCalendar>.unmodifiable(
        folders.values.map(
          (folder) => EwsCalendar(
            id: TaskListId(folder.id, account: account),
            name: folder.displayName,
          ),
        ),
      );
    });
    if (result case MailSuccess(:final value) when lease.isCurrent) {
      _folders
        ..clear()
        ..addAll(value.map((calendar) => calendar.id));
    }
    return _taskResult(result);
  }

  @override
  Future<TaskResult<List<EwsCalendarEvent>>> agenda(
    TaskListId calendar, {
    required DateTime start,
    required DateTime end,
    required MailOperationLease lease,
  }) async {
    if (!_folders.contains(calendar) ||
        !start.isUtc ||
        !end.isUtc ||
        !start.isBefore(end) ||
        start.year < 1 ||
        end.year > 9999 ||
        end.difference(start) > const Duration(days: 45)) {
      return _invalidTask();
    }
    return _taskResult(
      await connection._run(lease, (client, operation) async {
        final soap = connection._soap;
        final events = <String, EwsCalendarEvent>{};
        var requests = 0;
        // CalendarView expands recurrence but has no offset. Split a truncated
        // range and deduplicate events spanning both halves by Exchange item ID.
        Future<void> read(DateTime from, DateTime to) async {
          if (++requests > 31) {
            throw const EwsException(MailProblemCode.quotaExceeded);
          }
          final xml = await operation.post(
            client,
            'FindItem',
            soap.findCalendarEvents(calendar.value, start: from, end: to),
          );
          final page = soap.calendarEvents(xml);
          if (!page.complete) {
            final width = to.difference(from);
            if (width <= const Duration(minutes: 1)) {
              throw const EwsException(MailProblemCode.quotaExceeded);
            }
            final mid = from.add(
              Duration(microseconds: width.inMicroseconds ~/ 2),
            );
            await read(from, mid);
            await read(mid, to);
            return;
          }
          for (final event in page.events) {
            if (event.start.isBefore(end) && !event.end.isBefore(start)) {
              events.putIfAbsent(event.id, () => event);
            }
          }
          if (events.length > 4096) {
            throw const EwsException(MailProblemCode.quotaExceeded);
          }
        }

        await read(start, end);
        final ordered = events.values.toList()
          ..sort((a, b) {
            final byStart = a.start.compareTo(b.start);
            return byStart == 0 ? a.id.compareTo(b.id) : byStart;
          });
        return List<EwsCalendarEvent>.unmodifiable(ordered);
      }),
    );
  }

  @override
  Future<TaskResult<EwsCalendarEvent>> openAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    MailOperationLease lease,
  ) async {
    if (!_validAppointment(calendar, observed)) return _invalidTask();
    return _taskResult(
      await connection._run(
        lease,
        (client, operation) => _open(client, operation, calendar, observed),
      ),
    );
  }

  @override
  Future<TaskResult<TaskUnit>> createAppointment(
    TaskListId calendar,
    EwsAppointmentFields fields,
    MailOperationLease lease, {
    bool Function()? canWrite,
  }) async {
    if (!_folders.contains(calendar) || !_validFields(fields)) {
      return _invalidTask();
    }
    return _taskResult(
      await connection._run(lease, (client, operation) async {
        if (canWrite?.call() == false) {
          throw const EwsException(MailProblemCode.staleOperation);
        }
        final soap = connection._soap;
        final xml = await operation.post(
          client,
          'CreateItem',
          soap.createCalendarAppointment(calendar.value, fields),
          mutation: true,
        );
        soap.calendarMutation(xml, 'CreateItem');
        return TaskUnit.value;
      }),
    );
  }

  @override
  Future<TaskResult<TaskUnit>> updateAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    EwsAppointmentFields fields,
    MailOperationLease lease, {
    bool Function()? canWrite,
  }) async {
    if (!_validAppointment(calendar, observed) || !_validFields(fields)) {
      return _invalidTask();
    }
    return _taskResult(
      await connection._run(lease, (client, operation) async {
        final current = await _open(client, operation, calendar, observed);
        final changes = ewsAppointmentChanges(
          current.appointmentFields,
          fields,
        );
        if (changes.isEmpty) return TaskUnit.value;
        if (canWrite?.call() == false) {
          throw const EwsException(MailProblemCode.staleOperation);
        }
        final soap = connection._soap;
        final xml = await operation.post(
          client,
          'UpdateItem',
          soap.updateCalendarAppointment(
            current.id,
            current.appointmentRevision!,
            changes,
          ),
          mutation: true,
        );
        if (soap.calendarMutation(xml, 'UpdateItem')?.id != current.id) {
          throw const EwsException(MailProblemCode.conflict);
        }
        return TaskUnit.value;
      }),
    );
  }

  @override
  Future<TaskResult<TaskUnit>> deleteAppointment(
    TaskListId calendar,
    EwsCalendarEvent observed,
    MailOperationLease lease, {
    bool Function()? canWrite,
  }) async {
    if (!canDeleteAppointments) {
      return const TaskFailure(
        TaskProblem(
          TaskProblemCode.unsupported,
          mutationMayHaveOccurred: false,
        ),
      );
    }
    if (!_validAppointment(calendar, observed)) return _invalidTask();
    return _taskResult(
      await connection._run(lease, (client, operation) async {
        final current = await _open(client, operation, calendar, observed);
        if (canWrite?.call() == false) {
          throw const EwsException(MailProblemCode.staleOperation);
        }
        final soap = connection._soap;
        final xml = await operation.post(
          client,
          'DeleteItem',
          soap.deleteCalendarAppointment(
            current.id,
            current.appointmentRevision!,
          ),
          mutation: true,
        );
        soap.calendarMutation(xml, 'DeleteItem');
        return TaskUnit.value;
      }),
    );
  }

  bool _validAppointment(TaskListId calendar, EwsCalendarEvent observed) =>
      _folders.contains(calendar) &&
      connection._validId(observed.id) &&
      observed.appointmentRevision != null &&
      connection._validId(observed.appointmentRevision!);

  Future<EwsCalendarEvent> _open(
    EwsHttpClient client,
    _Operation operation,
    TaskListId calendar,
    EwsCalendarEvent observed,
  ) async {
    final soap = connection._soap;
    final xml = await operation.post(
      client,
      'GetItem',
      soap.getCalendarAppointment(observed.id),
    );
    return soap.calendarAppointment(
      xml,
      folder: calendar.value,
      id: observed.id,
      revision: observed.appointmentRevision!,
    );
  }

  bool _validFields(EwsAppointmentFields fields) =>
      fields.title.trim().isNotEmpty &&
      fields.title.length <= 250 &&
      (fields.location?.length ?? 0) <= 1024 &&
      (fields.description?.length ?? 0) <= 8192 &&
      [fields.title, fields.location, fields.description].nonNulls.every(
        (text) =>
            !text.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]')),
      ) &&
      fields.start.isUtc &&
      fields.end.isUtc &&
      fields.start.year >= 1 &&
      fields.end.year <= 9999 &&
      fields.end.isAfter(fields.start);
}
