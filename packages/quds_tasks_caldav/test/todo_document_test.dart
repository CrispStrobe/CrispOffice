import 'dart:convert';

import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

String calendar(String properties) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//fixture//EN\r\n'
    'BEGIN:VTODO\r\nUID:task-1\r\n$properties'
    'END:VTODO\r\nEND:VCALENDAR\r\n';

void main() {
  group('resource fidelity', () {
    test('unchanged resource and unrelated data are retained exactly', () {
      const timeZone =
          'BEGIN:VTIMEZONE\r\nTZID:Europe/Berlin\r\n'
          'BEGIN:STANDARD\r\nDTSTART:19701025T030000\r\n'
          'TZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\n'
          'END:STANDARD\r\nEND:VTIMEZONE\r\n';
      const alarm =
          'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\n'
          'DESCRIPTION:Do not remove this reminder\r\nEND:VALARM\r\n';
      const extension =
          'X-EXAMPLE;X-META="a;b:c":first\\nline\r\n'
          ' second part\r\nX-EXAMPLE:second value\r\n';
      final source = calendar(
        'SUMMARY;LANGUAGE=de:Alte Aufgabe\r\n'
        'DESCRIPTION:Note\\nline two\\, comma\\; semi\\\\slash\r\n'
        'PRIORITY:3\r\n'
        'DTSTART;TZID=Europe/Berlin:20261125T143000\r\n'
        'DUE;TZID=Europe/Berlin:20261125T150000\r\n'
        '$extension$alarm',
      ).replaceFirst('BEGIN:VTODO', '${timeZone}BEGIN:VTODO');
      final document = CalDavTodoDocument.parse(source);
      expect(document.encode(), source);
      expect(document.description, 'Note\nline two, comma; semi\\slash');
      final changed = document.apply(
        const TaskPatch(title: TaskFieldPatch.set('Neue Aufgabe')),
      );
      expect(changed.summary, 'Neue Aufgabe');
      expect(
        changed.encode(),
        contains('SUMMARY;LANGUAGE=de:Neue Aufgabe\r\n'),
      );
      expect(changed.encode(), contains(timeZone));
      expect(changed.encode(), contains(extension));
      expect(changed.encode(), contains(alarm));
      expect(
        changed.priority,
        3,
        reason: 'Unchanged numeric priority is not flattened.',
      );
      expect(changed.uid, 'task-1');
      expect(document.encode(), source, reason: 'Patches are immutable.');
    });

    test(
      'LF input and final missing newline survive a no-op byte-for-byte',
      () {
        final source = calendar(
          'SUMMARY:task\r\n',
        ).replaceAll('\r\n', '\n').trimRight();
        final document = CalDavTodoDocument.parse(source);
        expect(document.apply(const TaskPatch()), same(document));
        expect(document.encode(), source);
      },
    );

    test('text escaping prevents content-line injection', () {
      final changed = CalDavTodoDocument.parse(calendar('')).apply(
        const TaskPatch(
          title: TaskFieldPatch.set('A, B; \\ C\r\nEND:VTODO'),
          notes: TaskFieldPatch.set(TaskText('line one\nline two')),
        ),
      );
      expect(changed.summary, 'A, B; \\ C\nEND:VTODO');
      expect(changed.description, 'line one\nline two');
      expect(changed.encode(), contains(r'SUMMARY:A\, B\; \\ C\nEND:VTODO'));
      expect(
        RegExp(
          r'^END:VTODO$',
          multiLine: true,
        ).allMatches(changed.encode().replaceAll('\r', '')).length,
        1,
      );
    });

    test(
      'new Unicode lines fold at 75 octets without splitting code points',
      () {
        final title = List.filled(80, 'مرحبا 🗂️ ä').join(' / ');
        final changed = CalDavTodoDocument.parse(
          calendar(''),
        ).apply(TaskPatch(title: TaskFieldPatch.set(title)));
        expect(changed.summary, title);
        for (final line in changed.encode().split('\r\n')) {
          expect(utf8.encode(line).length, lessThanOrEqualTo(75));
        }
        expect(utf8.decode(utf8.encode(changed.encode())), changed.encode());
      },
    );

    test('clearing notes removes just DESCRIPTION', () {
      final document = CalDavTodoDocument.parse(
        calendar('SUMMARY:Title\r\nDESCRIPTION:Note\r\nX-KEEP:yes\r\n'),
      );
      final changed = document.apply(
        const TaskPatch(notes: TaskFieldPatch.clear()),
      );
      expect(changed.description, isNull);
      expect(changed.encode(), contains('X-KEEP:yes\r\n'));
      expect(changed.summary, 'Title');
    });
  });

  group('dates and completion', () {
    test('new zoned values require a matching retained VTIMEZONE', () {
      final zoned = TaskDateTime(
        '2026-11-25T12:00:00',
        timeZone: 'Europe/Berlin',
      );
      expect(
        () => CalDavTodoDocument.create(
          uid: 'zoned',
          fields: TaskFields(title: 'New', due: zoned),
          timestamp: DateTime.utc(2026, 11, 25),
        ),
        throwsUnsupportedError,
      );
      final plain = CalDavTodoDocument.parse(calendar(''));
      expect(
        () => plain.apply(TaskPatch(due: TaskFieldPatch.set(zoned))),
        throwsUnsupportedError,
      );
      const timezone =
          'BEGIN:VTIMEZONE\r\nTZID:Europe/Berlin\r\n'
          'BEGIN:STANDARD\r\nDTSTART:19701025T030000\r\n'
          'TZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\n'
          'END:STANDARD\r\nEND:VTIMEZONE\r\n';
      final withZone = CalDavTodoDocument.parse(
        calendar('').replaceFirst('BEGIN:VTODO', '${timezone}BEGIN:VTODO'),
      );
      final changed = withZone.apply(TaskPatch(due: TaskFieldPatch.set(zoned)));
      expect(changed.encode(), contains(timezone));
      expect(changed.toTaskFields().due, zoned);
      expect(
        () => withZone.apply(
          TaskPatch(
            due: TaskFieldPatch.set(
              TaskDateTime('2026-11-25T12:00:00', timeZone: 'America/New_York'),
            ),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('DUE must be strictly later than a directly comparable DTSTART', () {
      final dateOnly = CalDavTodoDocument.parse(
        calendar('DTSTART;VALUE=DATE:20261125\r\n'),
      );
      expect(
        () => dateOnly.apply(
          TaskPatch(due: TaskFieldPatch.set(TaskDate(2026, 11, 25))),
        ),
        throwsArgumentError,
      );
      final utc = CalDavTodoDocument.parse(
        calendar('DTSTART:20261125T120000Z\r\n'),
      );
      expect(
        () => utc.apply(
          TaskPatch(
            due: TaskFieldPatch.set(
              TaskDateTime('2026-11-25T12:00:00', timeZone: 'UTC'),
            ),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('implicit progress updates preserve unknown progress parameters', () {
      final document = CalDavTodoDocument.parse(
        calendar('PERCENT-COMPLETE;X-SERVICE-HINT=keep:25\r\n'),
      );
      final done = document.apply(
        const TaskPatch(status: TaskFieldPatch.set(TaskStatus.completed)),
      );
      expect(
        done.encode(),
        contains('PERCENT-COMPLETE;X-SERVICE-HINT=keep:100\r\n'),
      );
      final reopened = done.apply(
        const TaskPatch(status: TaskFieldPatch.set(TaskStatus.notStarted)),
      );
      expect(
        reopened.encode(),
        contains('PERCENT-COMPLETE;X-SERVICE-HINT=keep:0\r\n'),
      );
    });

    test('all-day, floating, zoned, and UTC date values stay distinct', () {
      final allDay = CalDavTodoDocument.parse(
        calendar('DUE;VALUE=DATE:20261125\r\n'),
      );
      final floating = CalDavTodoDocument.parse(
        calendar('DUE:20261125T090000\r\n'),
      );
      final zoned = CalDavTodoDocument.parse(
        calendar('DUE;TZID="Europe/Berlin":20261125T090000\r\n'),
      );
      final utc = CalDavTodoDocument.parse(
        calendar('DUE:20261125T090000Z\r\n'),
      );
      expect(allDay.due!.kind, CalDavDateKind.date);
      expect(allDay.toTaskFields().due, TaskDate(2026, 11, 25));
      expect(floating.toTaskFields().due, TaskDateTime('2026-11-25T09:00:00'));
      expect(
        zoned.toTaskFields().due,
        TaskDateTime('2026-11-25T09:00:00', timeZone: 'Europe/Berlin'),
      );
      expect(
        utc.toTaskFields().due,
        TaskDateTime('2026-11-25T09:00:00', timeZone: 'UTC'),
      );
    });

    test(
      'a date patch preserves unrelated date parameters and removes TZID',
      () {
        final document = CalDavTodoDocument.parse(
          calendar(
            'DUE;TZID=Europe/Berlin;X-META="keep:me":20261125T090000\r\n',
          ),
        );
        final changed = document.apply(
          TaskPatch(due: TaskFieldPatch.set(TaskDate(2026, 11, 26))),
        );
        expect(
          changed.encode(),
          contains('DUE;VALUE=DATE;X-META="keep:me":20261126\r\n'),
        );
        expect(changed.due!.timeZone, isNull);
      },
    );

    test('completion and reopening keep status/progress/time consistent', () {
      final document = CalDavTodoDocument.parse(calendar('SUMMARY:Do it\r\n'));
      final completed = document.apply(
        TaskPatch(
          status: const TaskFieldPatch.set(TaskStatus.completed),
          completedAt: TaskFieldPatch.set(
            TaskDateTime('2026-11-25T12:00:00', timeZone: 'UTC'),
          ),
        ),
      );
      expect(completed.status, 'COMPLETED');
      expect(completed.percentComplete, 100);
      expect(completed.completed!.value, '20261125T120000Z');
      final reopened = completed.apply(
        const TaskPatch(status: TaskFieldPatch.set(TaskStatus.notStarted)),
      );
      expect(reopened.status, 'NEEDS-ACTION');
      expect(reopened.percentComplete, 0);
      expect(reopened.completed, isNull);
    });

    test('invalid and lossy date conversions are rejected', () {
      for (final property in [
        'DUE;VALUE=DATE:20260230',
        'DUE;VALUE=DATE;TZID=Europe/Berlin:20261125',
        'DUE;TZID=Europe/Berlin:20261125T120000Z',
        'DUE:20261125T240000',
        'DUE:20261125T120000+0100',
        'COMPLETED;VALUE=DATE:20261125',
        'DUE;VALUE=DATE;VALUE=DATE:20261125',
      ]) {
        expect(
          () => CalDavTodoDocument.parse(calendar('$property\r\n')),
          throwsFormatException,
          reason: property,
        );
      }
      expect(
        () => CalDavDateValue.fromTaskDate(
          TaskDateTime('2026-11-25T12:00:00.123'),
        ),
        throwsFormatException,
      );
      expect(
        CalDavDateValue.fromTaskDate(
          TaskDateTime('2026-11-25T12:00:00.000', timeZone: 'UTC'),
        ).value,
        '20261125T120000Z',
      );
    });

    test('refuses mixed date types and due before start when comparable', () {
      final document = CalDavTodoDocument.parse(
        calendar('DTSTART;VALUE=DATE:20261125\r\n'),
      );
      expect(
        () => document.apply(
          TaskPatch(due: TaskFieldPatch.set(TaskDate(2026, 11, 24))),
        ),
        throwsArgumentError,
      );
      expect(
        () => document.apply(
          TaskPatch(
            due: TaskFieldPatch.set(TaskDateTime('2026-11-26T09:00:00')),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => document.apply(
          TaskPatch(
            completedAt: TaskFieldPatch.set(
              TaskDateTime('2026-11-25T12:00:00', timeZone: 'UTC'),
            ),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('explicit unsupported-feature guards', () {
    for (final entry in {
      'RRULE:FREQ=WEEKLY': CalDavTodoMutationBlocker.recurrence,
      'RECURRENCE-ID:20261125T120000Z': CalDavTodoMutationBlocker.recurrence,
      'DURATION:PT30M': CalDavTodoMutationBlocker.duration,
      'ATTENDEE:mailto:person@example.test':
          CalDavTodoMutationBlocker.participants,
      'ORGANIZER:mailto:person@example.test':
          CalDavTodoMutationBlocker.participants,
      'RELATED-TO:parent-task': CalDavTodoMutationBlocker.relatedTasks,
      'STATUS:X-CUSTOM': CalDavTodoMutationBlocker.unknownStatus,
    }.entries) {
      test('preserves but refuses to mutate ${entry.key.split(':').first}', () {
        final source = calendar('SUMMARY:Keep\r\n${entry.key}\r\n');
        final document = CalDavTodoDocument.parse(source);
        expect(document.encode(), source);
        expect(document.mutationBlockers, contains(entry.value));
        expect(document.apply(const TaskPatch()), same(document));
        expect(
          () => document.apply(
            const TaskPatch(title: TaskFieldPatch.set('Change')),
          ),
          throwsUnsupportedError,
        );
      });
    }

    test(
      'does not flatten HTML, reminders, or statuses with no equivalent',
      () {
        final document = CalDavTodoDocument.parse(
          calendar('SUMMARY:Title\r\n'),
        );
        for (final patch in [
          const TaskPatch(
            notes: TaskFieldPatch.set(
              TaskText('<b>Note</b>', format: TaskTextFormat.html),
            ),
          ),
          const TaskPatch(reminder: TaskFieldPatch.clear()),
          const TaskPatch(
            status: TaskFieldPatch.set(TaskStatus.waitingOnOthers),
          ),
          const TaskPatch(status: TaskFieldPatch.set(TaskStatus.deferred)),
        ]) {
          expect(() => document.apply(patch), throwsUnsupportedError);
        }
        expect(
          () => document.apply(const TaskPatch(title: TaskFieldPatch.clear())),
          throwsArgumentError,
        );
      },
    );
  });

  group('structure and common projection', () {
    test('rejects malformed or ambiguous resources before exposing tasks', () {
      for (final source in [
        calendar('UID:second\r\n'),
        calendar('SUMMARY:first\r\nSUMMARY:second\r\n'),
        calendar('PRIORITY:10\r\n'),
        calendar('PERCENT-COMPLETE:-1\r\n'),
        calendar('').replaceAll('UID:task-1\r\n', ''),
        calendar('').replaceFirst('END:VTODO', 'END:VEVENT'),
        calendar('').replaceFirst('END:VCALENDAR', ''),
        calendar('').replaceFirst(
          'END:VCALENDAR',
          'BEGIN:VTODO\r\nUID:second\r\nEND:VTODO\r\nEND:VCALENDAR',
        ),
        calendar('').replaceAll('VTODO', 'VEVENT'),
        calendar('').replaceFirst('VERSION:2.0\r\n', ''),
        calendar('').replaceFirst('VERSION:2.0', 'VERSION:1.0'),
        calendar('').replaceFirst('VERSION:2.0', 'VERSION:2.0\r\nVERSION:2.0'),
        ' ${calendar('')}',
        calendar('SUMMARY:Bad\\escape\r\n'),
      ]) {
        expect(() => CalDavTodoDocument.parse(source), throwsFormatException);
      }
    });

    test(
      'creation and remote projection preserve scoped resource identity',
      () {
        final document = CalDavTodoDocument.create(
          uid: 'generated-uid',
          fields: TaskFields(
            title: 'Created task',
            notes: const TaskText('Note'),
            priority: TaskPriority.high,
            due: TaskDate(2026, 11, 26),
          ),
          timestamp: DateTime.utc(2026, 11, 25, 12),
        );
        final account = TaskAccountId('alice', provider: 'caldav');
        final list = TaskListId('/calendars/alice/tasks/', account: account);
        final id = TaskId('/calendars/alice/tasks/resource.ics', list: list);
        final remote = document.toRemoteTask(id, etag: '"version-1"');
        expect(remote.id, id);
        expect(remote.fields.title, 'Created task');
        expect(remote.fields.priority, TaskPriority.high);
        expect(remote.revision, '"version-1"');
        expect(remote.providerData!.format, 'text/calendar');
        expect(remote.providerData!.raw, document.encode());
        expect(document.uid, 'generated-uid');
        expect(document.encode(), contains('DTSTAMP:20261125T120000Z\r\n'));
      },
    );
  });
}
