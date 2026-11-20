import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 11, 20);
final _later = _now.add(const Duration(minutes: 1));

MailOutboxEntry _queued({bool inherited = false}) => MailOutboxEntry.queued(
  id: 'queue',
  prepared: MailPreparedMessage(
    account: MailAccountId(
      'account',
      profile: MailProfileId('profile', hostId: 'office'),
    ),
    draftId: 'original',
    draftRevision: 3,
    wire: MailBytes(utf8.encode('From: a@example.test\r\n\r\nFrozen')),
    envelope: MailTransportEnvelope(
      sender: 'a@example.test',
      recipients: ['to@example.test', 'hidden@example.test'],
    ),
  ),
  now: _now,
  priorSubmissionUncertain: inherited,
);

MailOutboxEntry _restore(MailOutboxEntry entry) => MailOutboxEntry.restore(
  id: entry.id,
  prepared: entry.prepared,
  state: entry.state,
  createdAt: entry.createdAt,
  updatedAt: entry.updatedAt,
  attemptNumber: entry.attemptNumber,
  attemptId: entry.attemptId,
  result: entry.result,
  priorSubmissionUncertain: entry.priorSubmissionUncertain,
);

void _expectClosed(MailOutboxEntry original) {
  final closed = original.closeUncertain(now: _later);
  expect(closed.state, MailOutboxState.closedUncertain);
  expect(identical(closed.prepared, original.prepared), isTrue);
  expect(identical(closed.result, original.result), isTrue);
  expect(closed.attemptNumber, original.attemptNumber);
  expect(closed.attemptId, original.attemptId);
  expect(closed.priorSubmissionUncertain, original.priorSubmissionUncertain);
  expect(closed.createdAt, original.createdAt);
  expect(closed.updatedAt, _later);
  expect(closed.canBeginAttempt, isFalse);
  expect(closed.canBeginAcknowledgedAttempt, isFalse);
  expect(closed.canCloseUncertain, isFalse);
  expect(closed.canCancel, isFalse);
  expect(closed.canRemove, isTrue);
  expect(() => closed.cancel(now: _later), throwsStateError);
  expect(() => closed.closeUncertain(now: _later), throwsStateError);
  expect(
    () => closed.beginAttempt(attemptId: 'another', now: _later),
    throwsStateError,
  );
  expect(
    () => closed.beginAcknowledgedAttempt(attemptId: 'another', now: _later),
    throwsStateError,
  );
  final restored = _restore(closed);
  expect(restored.state, MailOutboxState.closedUncertain);
  expect(restored.prepared.wireHash, original.prepared.wireHash);
  expect(restored.result?.outcome, original.result?.outcome);
  expect(identical(restored.recoverInterrupted(now: _later), restored), isTrue);
}

void main() {
  test('closing first uncertainty retains the unknown actual result', () {
    final uncertain = _queued()
        .beginAttempt(attemptId: 'first', now: _now)
        .recoverInterrupted(now: _now);
    expect(uncertain.canCloseUncertain, isTrue);
    expect(uncertain.priorSubmissionUncertain, isFalse);
    _expectClosed(uncertain);
  });

  test('inherited uncertainty closes without inventing an attempt', () {
    final inherited = _queued(inherited: true);
    expect(inherited.attemptNumber, 0);
    expect(inherited.result, isNull);
    _expectClosed(inherited);
  });

  for (final outcome in [
    MailSubmissionOutcome.rejected,
    MailSubmissionOutcome.retryableFailure,
    MailSubmissionOutcome.uncertain,
  ]) {
    test('closing later ${outcome.name} preserves older uncertainty', () {
      final retry = _queued(inherited: true)
          .beginAcknowledgedAttempt(attemptId: 'retry', now: _now)
          .complete(
            MailSubmissionResult(attemptId: 'retry', outcome: outcome),
            now: _now,
          );
      expect(retry.priorSubmissionUncertain, isTrue);
      _expectClosed(retry);
    });
  }

  test('ordinary queued, active, accepted and cancelled work cannot close', () {
    final queued = _queued();
    final pending = queued.beginAttempt(attemptId: 'first', now: _now);
    final states = [
      queued,
      pending,
      queued.cancel(now: _now),
      for (final outcome in [
        MailSubmissionOutcome.accepted,
        MailSubmissionOutcome.rejected,
        MailSubmissionOutcome.retryableFailure,
      ])
        pending.complete(
          MailSubmissionResult(attemptId: 'first', outcome: outcome),
          now: _now,
        ),
      _queued(
        inherited: true,
      ).beginAcknowledgedAttempt(attemptId: 'acknowledged-live', now: _now),
      _queued(inherited: true)
          .beginAcknowledgedAttempt(attemptId: 'accepted-retry', now: _now)
          .complete(
            MailSubmissionResult(
              attemptId: 'accepted-retry',
              outcome: MailSubmissionOutcome.accepted,
            ),
            now: _now,
          ),
    ];
    for (final entry in states) {
      expect(entry.canCloseUncertain, isFalse, reason: entry.state.name);
      expect(() => entry.closeUncertain(now: _later), throwsStateError);
    }
  });

  test('restoration rejects closure without retained uncertain history', () {
    final queued = _queued();
    for (final (attempts, outcome, inherited) in [
      (0, null, false),
      (1, null, true),
      (1, MailSubmissionOutcome.accepted, true),
      (1, MailSubmissionOutcome.rejected, false),
      (1, MailSubmissionOutcome.retryableFailure, false),
    ]) {
      expect(
        () => MailOutboxEntry.restore(
          id: queued.id,
          prepared: queued.prepared,
          state: MailOutboxState.closedUncertain,
          createdAt: _now,
          updatedAt: _later,
          attemptNumber: attempts,
          attemptId: attempts == 0 ? null : 'attempt',
          result: outcome == null
              ? null
              : MailSubmissionResult(attemptId: 'attempt', outcome: outcome),
          priorSubmissionUncertain: inherited,
        ),
        throwsArgumentError,
      );
    }
  });
}
