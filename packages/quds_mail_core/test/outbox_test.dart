import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18);
  late MailPreparedMessage prepared;
  late MailOutboxEntry queued;
  setUp(() {
    prepared = MailPreparedMessage(
      account: MailAccountId(
        'a',
        profile: MailProfileId('p', hostId: 'office'),
      ),
      draftId: 'draft',
      draftRevision: 4,
      wire: MailBytes(
        Uint8List.fromList(
          ascii.encode('From: author@example.test\r\n\r\nBody\r\n'),
        ),
      ),
      envelope: MailTransportEnvelope(
        sender: 'author@example.test',
        recipients: ['one@example.test', 'hidden@example.test'],
      ),
    );
    queued = MailOutboxEntry.queued(
      id: 'queue-1',
      prepared: prepared,
      now: now,
    );
  });

  test(
    'queued revision, wire and envelope remain frozen through submission',
    () {
      final pending = queued.beginAttempt(attemptId: 'attempt-1', now: now);
      expect(queued.state, MailOutboxState.queued);
      expect(pending.state, MailOutboxState.submitting);
      expect(pending.attemptNumber, 1);
      expect(identical(pending.prepared, prepared), isTrue);
      expect(pending.prepared.draftRevision, 4);
      expect(() => pending.prepared.wire.bytes[0] = 0, throwsUnsupportedError);
      expect(
        () => pending.prepared.envelope.recipients.clear(),
        throwsUnsupportedError,
      );
      final submitted = pending.complete(
        MailSubmissionResult(
          attemptId: 'attempt-1',
          outcome: MailSubmissionOutcome.accepted,
          recipients: const [
            MailRecipientResponse(
              recipient: 'one@example.test',
              acceptance: MailRecipientAcceptance.accepted,
              responseCode: 250,
            ),
            MailRecipientResponse(
              recipient: 'hidden@example.test',
              acceptance: MailRecipientAcceptance.accepted,
              responseCode: 250,
            ),
          ],
        ),
        now: now,
      );
      expect(submitted.state, MailOutboxState.submitted);
      expect(
        submitted.result!.submissionFor('hidden@example.test'),
        MailRecipientSubmission.submitted,
      );
      expect(submitted.canBeginAttempt, isFalse);
    },
  );

  test('mixed 250/550 RCPT responses abort every recipient before DATA', () {
    final result = MailSubmissionResult(
      attemptId: 'attempt-1',
      outcome: MailSubmissionOutcome.rejected,
      recipients: const [
        MailRecipientResponse(
          recipient: 'one@example.test',
          acceptance: MailRecipientAcceptance.accepted,
          responseCode: 250,
        ),
        MailRecipientResponse(
          recipient: 'hidden@example.test',
          acceptance: MailRecipientAcceptance.rejected,
          responseCode: 550,
        ),
      ],
    );
    final finished = queued
        .beginAttempt(attemptId: 'attempt-1', now: now)
        .complete(result, now: now);
    expect(finished.state, MailOutboxState.permanentFailure);
    expect(
      result.acceptanceFor('one@example.test'),
      MailRecipientAcceptance.accepted,
    );
    expect(
      result.submissionFor('one@example.test'),
      MailRecipientSubmission.notSubmitted,
    );
    expect(
      result.submissionFor('hidden@example.test'),
      MailRecipientSubmission.notSubmitted,
    );
    expect(
      () => MailSubmissionResult(
        attemptId: 'attempt-1',
        outcome: MailSubmissionOutcome.accepted,
        recipients: result.recipients,
      ),
      throwsArgumentError,
    );
  });

  test('aggregate response does not fabricate recipient-level acceptance', () {
    final result = MailSubmissionResult(
      attemptId: 'a',
      outcome: MailSubmissionOutcome.accepted,
    );
    expect(
      result.acceptanceFor('one@example.test'),
      MailRecipientAcceptance.unknown,
    );
    expect(
      result.submissionFor('one@example.test'),
      MailRecipientSubmission.unknown,
    );
  });

  test('missing recipient responses stay unknown on aggregate failure', () {
    final result = MailSubmissionResult(
      attemptId: 'a',
      outcome: MailSubmissionOutcome.rejected,
    );
    expect(
      result.submissionFor('one@example.test'),
      MailRecipientSubmission.unknown,
    );
    expect(
      () => MailSubmissionResult(
        attemptId: 'a',
        outcome: MailSubmissionOutcome.rejected,
        recipients: const [
          MailRecipientResponse(
            recipient: 'one@example.test',
            acceptance: MailRecipientAcceptance.accepted,
            responseCode: 550,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test(
    'connection loss after possible acceptance is uncertain and cannot retry',
    () {
      final result = MailSubmissionResult(
        attemptId: 'a',
        outcome: MailSubmissionOutcome.uncertain,
      );
      final uncertain = queued
          .beginAttempt(attemptId: 'a', now: now)
          .complete(result, now: now);
      expect(uncertain.state, MailOutboxState.uncertain);
      expect(uncertain.canBeginAttempt, isFalse);
      expect(
        result.submissionFor('one@example.test'),
        MailRecipientSubmission.unknown,
      );
      expect(
        () => uncertain.beginAttempt(attemptId: 'b', now: now),
        throwsStateError,
      );
      expect(() => uncertain.cancel(now: now), throwsStateError);
    },
  );

  test('interrupted submitting state recovers as uncertain, never queued', () {
    final recovered = queued
        .beginAttempt(attemptId: 'a', now: now)
        .recoverInterrupted(now: now);
    expect(recovered.state, MailOutboxState.uncertain);
    expect(recovered.attemptId, 'a');
    expect(identical(queued.recoverInterrupted(now: now), queued), isTrue);
  });

  test(
    'definite non-acceptance retries with a fresh attempt identity only',
    () {
      final failed = queued
          .beginAttempt(attemptId: 'a', now: now)
          .complete(
            MailSubmissionResult(
              attemptId: 'a',
              outcome: MailSubmissionOutcome.retryableFailure,
            ),
            now: now,
          );
      expect(failed.canBeginAttempt, isTrue);
      expect(
        () => failed.beginAttempt(attemptId: 'a', now: now),
        throwsArgumentError,
      );
      final retry = failed.beginAttempt(attemptId: 'b', now: now);
      expect(retry.attemptNumber, 2);
      expect(
        () => retry.complete(
          MailSubmissionResult(
            attemptId: 'a',
            outcome: MailSubmissionOutcome.accepted,
          ),
          now: now,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'validated restoration preserves a pending attempt and recovers uncertain',
    () {
      final pending = queued.beginAttempt(
        attemptId: 'persisted-attempt',
        now: now,
      );
      final restored = MailOutboxEntry.restore(
        id: pending.id,
        prepared: pending.prepared,
        state: pending.state,
        createdAt: pending.createdAt,
        updatedAt: pending.updatedAt,
        attemptNumber: pending.attemptNumber,
        attemptId: pending.attemptId,
      );
      expect(
        restored.recoverInterrupted(now: now).state,
        MailOutboxState.uncertain,
      );
      expect(restored.prepared.wireHash, pending.prepared.wireHash);
      expect(
        () => MailOutboxEntry.restore(
          id: 'bad',
          prepared: prepared,
          state: MailOutboxState.submitted,
          createdAt: now,
          updatedAt: now,
          attemptNumber: 1,
          attemptId: 'a',
        ),
        throwsArgumentError,
      );
      expect(
        () => MailOutboxEntry.restore(
          id: 'bad',
          prepared: prepared,
          state: MailOutboxState.queued,
          createdAt: now,
          updatedAt: now,
          attemptNumber: 1,
          attemptId: 'a',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'legacy draft uncertainty requires acknowledgement before queue send',
    () {
      final inherited = MailOutboxEntry.queued(
        id: 'legacy',
        prepared: prepared,
        now: now,
        priorSubmissionUncertain: true,
      );
      expect(inherited.canBeginAttempt, isFalse);
      expect(inherited.canBeginAcknowledgedAttempt, isTrue);
      expect(inherited.canCancel, isFalse);
      expect(
        () => inherited.beginAttempt(attemptId: 'a', now: now),
        throwsStateError,
      );
      expect(() => inherited.cancel(now: now), throwsStateError);
      final pending = inherited.beginAcknowledgedAttempt(
        attemptId: 'a',
        now: now,
      );
      expect(pending.priorSubmissionUncertain, isTrue);
      expect(pending.attemptNumber, 1);
      expect(pending.canBeginAcknowledgedAttempt, isFalse);
    },
  );

  for (final outcome in MailSubmissionOutcome.values) {
    test(
      'acknowledged retry preserves older uncertainty after ${outcome.name}',
      () {
        final uncertain = queued
            .beginAttempt(attemptId: 'a', now: now)
            .recoverInterrupted(now: now);
        final retry = uncertain.beginAcknowledgedAttempt(
          attemptId: 'b',
          now: now,
        );
        expect(retry.attemptNumber, 2);
        expect(identical(retry.prepared, prepared), isTrue);
        final completed = retry.complete(
          MailSubmissionResult(attemptId: 'b', outcome: outcome),
          now: now,
        );
        expect(completed.priorSubmissionUncertain, isTrue);
        expect(completed.result!.outcome, outcome);
        expect(completed.canBeginAttempt, isFalse);
        expect(completed.canCancel, isFalse);
        expect(() => completed.cancel(now: now), throwsStateError);
        expect(
          () => completed.beginAttempt(attemptId: 'c', now: now),
          throwsStateError,
        );
        expect(
          completed.canBeginAcknowledgedAttempt,
          outcome != MailSubmissionOutcome.accepted,
        );
        if (completed.canBeginAcknowledgedAttempt) {
          expect(
            () => completed.beginAcknowledgedAttempt(attemptId: 'b', now: now),
            throwsArgumentError,
          );
          final third = completed.beginAcknowledgedAttempt(
            attemptId: 'c',
            now: now,
          );
          expect(third.attemptNumber, 3);
          expect(
            third.recoverInterrupted(now: now).priorSubmissionUncertain,
            isTrue,
          );
        }
      },
    );
  }

  test('acknowledgement cannot restart ordinary or accepted work', () {
    expect(queued.canBeginAcknowledgedAttempt, isFalse);
    expect(
      () => queued.beginAcknowledgedAttempt(attemptId: 'a', now: now),
      throwsStateError,
    );
    final accepted = queued
        .beginAttempt(attemptId: 'a', now: now)
        .complete(
          MailSubmissionResult(
            attemptId: 'a',
            outcome: MailSubmissionOutcome.accepted,
          ),
          now: now,
        );
    expect(
      () => accepted.beginAcknowledgedAttempt(attemptId: 'b', now: now),
      throwsStateError,
    );
    expect(
      () => MailOutboxEntry.restore(
        id: queued.id,
        prepared: prepared,
        state: MailOutboxState.cancelled,
        createdAt: now,
        updatedAt: now,
        attemptNumber: 0,
        priorSubmissionUncertain: true,
      ),
      throwsArgumentError,
    );
  });

  test('undo send only cancels work before submission', () {
    expect(queued.cancel(now: now).state, MailOutboxState.cancelled);
    expect(
      () => queued.beginAttempt(attemptId: 'a', now: now).cancel(now: now),
      throwsStateError,
    );
    expect(
      () => queued.cancel(now: now).beginAttempt(attemptId: 'a', now: now),
      throwsStateError,
    );
  });

  test(
    'unrelated/duplicate recipient results and control injection are rejected',
    () {
      final pending = queued.beginAttempt(attemptId: 'a', now: now);
      expect(
        () => pending.complete(
          MailSubmissionResult(
            attemptId: 'a',
            outcome: MailSubmissionOutcome.accepted,
            recipients: const [
              MailRecipientResponse(
                recipient: 'other@example.test',
                acceptance: MailRecipientAcceptance.accepted,
              ),
            ],
          ),
          now: now,
        ),
        throwsArgumentError,
      );
      expect(
        () => MailSubmissionResult(
          attemptId: 'a',
          outcome: MailSubmissionOutcome.rejected,
          recipients: const [
            MailRecipientResponse(
              recipient: 'one@example.test',
              acceptance: MailRecipientAcceptance.rejected,
            ),
            MailRecipientResponse(
              recipient: 'one@example.test',
              acceptance: MailRecipientAcceptance.rejected,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => MailTransportEnvelope(
          sender: 'one@example.test\r\nRCPT TO:<other@example.test>',
          recipients: ['one@example.test'],
        ),
        throwsArgumentError,
      );
      expect(
        () => MailTransportEnvelope(sender: 'one@example.test', recipients: []),
        throwsArgumentError,
      );
    },
  );
}
