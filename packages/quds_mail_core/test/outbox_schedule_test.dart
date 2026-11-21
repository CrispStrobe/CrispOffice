import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 11, 21, 12);
final _deadline = _now.add(const Duration(hours: 2));

MailOutboxEntry _queued({bool uncertain = false}) => MailOutboxEntry.queued(
  id: 'outgoing',
  prepared: MailPreparedMessage(
    account: MailAccountId(
      'account',
      profile: MailProfileId('profile', hostId: 'office'),
    ),
    draftId: 'draft',
    draftRevision: 7,
    wire: MailBytes(utf8.encode('From: a@example.test\r\n\r\nFrozen')),
    envelope: MailTransportEnvelope(
      sender: 'a@example.test',
      recipients: ['to@example.test', 'hidden@example.test'],
    ),
  ),
  now: _now,
  priorSubmissionUncertain: uncertain,
);

void _expectSchedule(MailOutboxEntry entry, MailOutboxEntry scheduled) {
  expect(entry.sendNotBefore, _deadline);
  expect(entry.sendNotBefore!.isUtc, isTrue);
  expect(entry.scheduleRevision, scheduled.scheduleRevision);
  expect(identical(entry.prepared, scheduled.prepared), isTrue);
  expect(entry.createdAt, _now);
}

void main() {
  test(
    'deadline is a UTC instant and every edit retains a monotonic token',
    () {
      final queued = _queued();
      final local = _deadline.toLocal();
      expect(local.isUtc, isFalse);
      final scheduled = queued.schedule(sendNotBefore: local, now: _now);
      expect(queued.sendNotBefore, isNull);
      expect(queued.scheduleRevision, 0);
      expect(scheduled.canSchedule, isTrue);
      expect(scheduled.sendNotBefore, _deadline);
      expect(scheduled.sendNotBefore!.isUtc, isTrue);
      expect(scheduled.scheduleRevision, 1);
      expect(identical(scheduled.prepared, queued.prepared), isTrue);
      final repeated = scheduled.schedule(sendNotBefore: local, now: _now);
      expect(repeated.scheduleRevision, 2);
      final cleared = repeated.schedule(sendNotBefore: null, now: _now);
      expect(cleared.sendNotBefore, isNull);
      expect(cleared.scheduleRevision, 3);
      expect(cleared.isDueAt(_now), isTrue);
      final clearedAgain = cleared.schedule(sendNotBefore: null, now: _now);
      expect(clearedAgain.scheduleRevision, 4);
      expect(identical(clearedAgain.prepared, queued.prepared), isTrue);
    },
  );

  test('ordinary attempts are blocked until the exact deadline', () {
    final scheduled = _queued().schedule(sendNotBefore: _deadline, now: _now);
    final early = _deadline.subtract(const Duration(microseconds: 1));
    expect(scheduled.canBeginAttempt, isTrue);
    expect(scheduled.isDueAt(early), isFalse);
    expect(scheduled.isDueAt(_deadline), isTrue);
    expect(
      scheduled.isDueAt(_deadline.add(const Duration(microseconds: 1))),
      isTrue,
    );
    expect(
      () => scheduled.beginAttempt(attemptId: 'early', now: early),
      throwsStateError,
    );
    final pending = scheduled.beginAttempt(
      attemptId: 'on-time',
      now: _deadline,
    );
    _expectSchedule(pending, scheduled);
    expect(pending.attemptNumber, 1);
    expect(pending.canSchedule, isFalse);
    expect(pending.isDueAt(_deadline), isFalse);
  });

  test('past, present and nonmonotonic schedule edits are rejected', () {
    for (final deadline in [_now, _now.subtract(const Duration(seconds: 1))]) {
      expect(
        () => _queued().schedule(sendNotBefore: deadline, now: _now),
        throwsArgumentError,
      );
    }
    expect(
      () => _queued().schedule(
        sendNotBefore: _deadline,
        now: _now.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
    final exhausted = MailOutboxEntry.restore(
      id: 'outgoing',
      prepared: _queued().prepared,
      state: MailOutboxState.queued,
      createdAt: _now,
      updatedAt: _now,
      attemptNumber: 0,
      scheduleRevision: MailOutboxEntry.maxScheduleRevision,
    );
    expect(
      () => exhausted.schedule(sendNotBefore: _deadline, now: _now),
      throwsStateError,
    );
  });

  test(
    'every outcome retains the schedule without authorizing rescheduling',
    () {
      final scheduled = _queued().schedule(sendNotBefore: _deadline, now: _now);
      _expectSchedule(scheduled.cancel(now: _now), scheduled);
      final pending = scheduled.beginAttempt(
        attemptId: 'first',
        now: _deadline,
      );
      for (final outcome in MailSubmissionOutcome.values) {
        final completed = pending.complete(
          MailSubmissionResult(attemptId: 'first', outcome: outcome),
          now: _deadline,
        );
        _expectSchedule(completed, scheduled);
        expect(completed.canSchedule, isFalse);
        expect(
          () => completed.schedule(sendNotBefore: null, now: _deadline),
          throwsStateError,
        );
        if (completed.canBeginAttempt) {
          final retry = completed.beginAttempt(
            attemptId: 'retry',
            now: _deadline,
          );
          _expectSchedule(retry, scheduled);
        }
        if (completed.canCloseUncertain) {
          _expectSchedule(completed.closeUncertain(now: _deadline), scheduled);
        }
        if (completed.canBeginAcknowledgedAttempt) {
          final retry = completed.beginAcknowledgedAttempt(
            attemptId: 'acknowledged',
            now: _deadline,
          );
          _expectSchedule(retry, scheduled);
          expect(retry.priorSubmissionUncertain, isTrue);
          _expectSchedule(retry.recoverInterrupted(now: _deadline), scheduled);
        }
      }
      final recovered = pending.recoverInterrupted(now: _deadline);
      _expectSchedule(recovered, scheduled);
      expect(recovered.canBeginAttempt, isFalse);
      expect(recovered.canSchedule, isFalse);
    },
  );

  test('inherited uncertainty and cancelled work cannot be scheduled', () {
    for (final entry in [
      _queued(uncertain: true),
      _queued().cancel(now: _now),
    ]) {
      expect(entry.canSchedule, isFalse);
      expect(
        () => entry.schedule(sendNotBefore: _deadline, now: _now),
        throwsStateError,
      );
    }
  });

  test('restoration rejects inconsistent schedule metadata', () {
    for (final (revision, deadline, uncertain) in [
      (-1, null, false),
      (MailOutboxEntry.maxScheduleRevision + 1, null, false),
      (0, _deadline, false),
      (1, _now, false),
      (1, _deadline, true),
      (1, null, true),
    ]) {
      expect(
        () => MailOutboxEntry.restore(
          id: 'outgoing',
          prepared: _queued().prepared,
          state: MailOutboxState.queued,
          createdAt: _now,
          updatedAt: _now,
          attemptNumber: 0,
          priorSubmissionUncertain: uncertain,
          sendNotBefore: deadline,
          scheduleRevision: revision,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => MailOutboxEntry.restore(
        id: 'outgoing',
        prepared: _queued().prepared,
        state: MailOutboxState.queued,
        createdAt: _now,
        updatedAt: _deadline,
        attemptNumber: 0,
        sendNotBefore: _deadline,
        scheduleRevision: 1,
      ),
      throwsArgumentError,
    );
  });
}
