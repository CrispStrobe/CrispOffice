part of 'provider.dart';

final class NativeEwsCalendarReader implements EwsCalendarReader {
  NativeEwsCalendarReader({required this.account, required this.connection});

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
}
