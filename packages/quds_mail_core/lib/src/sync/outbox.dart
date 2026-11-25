import '../model/bytes.dart';
import '../model/identity.dart';
import '../model/message.dart';
import '../model/result.dart';

void _validateMailbox(String mailbox) {
  if (mailbox.trim().isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(mailbox)) {
    throw ArgumentError(
      'Envelope mailboxes must be nonempty and contain no controls.',
    );
  }
}

/// Explicit submission envelope, including Bcc recipients absent from wire MIME.
/// Full mailbox syntax and SMTPUTF8 negotiation belong to the prepared codec and
/// provider; this boundary rejects control-character command injection.
final class MailTransportEnvelope {
  MailTransportEnvelope({
    required this.sender,
    required List<String> recipients,
  }) : recipients = List.unmodifiable(recipients) {
    _validateMailbox(sender);
    if (recipients.isEmpty) {
      throw ArgumentError('Submission requires recipients.');
    }
    final unique = <String>{};
    for (final recipient in recipients) {
      _validateMailbox(recipient);
      if (!unique.add(recipient)) {
        throw ArgumentError('Envelope recipients must be unique.');
      }
    }
  }
  final String sender;
  final List<String> recipients;
}

/// Lossless editor input that is not yet a validated transport envelope.
///
/// Incomplete recipient text must survive autosave without being promoted to an
/// address. Uncertain submission is durable and never grants permission to
/// resend. A cleared marker retains the revision after explicit removal, so a
/// stale editor cannot recreate deleted content through a revision ABA race.
final class MailDraftEditorState {
  MailDraftEditorState({
    this.to = '',
    this.cc = '',
    this.bcc = '',
    this.submissionUncertain = false,
    this.isCleared = false,
  }) {
    if (isCleared &&
        (to.isNotEmpty ||
            cc.isNotEmpty ||
            bcc.isNotEmpty ||
            submissionUncertain)) {
      throw ArgumentError('A cleared draft cannot contain editor input.');
    }
  }

  final String to;
  final String cc;
  final String bcc;
  final bool submissionUncertain;
  final bool isCleared;
}

/// A local draft revision. All attachment payloads are already frozen snapshots.
final class MailDraft {
  MailDraft({
    required this.id,
    required this.account,
    required this.revision,
    required this.envelope,
    required this.body,
    List<MailAttachment> attachments = const [],
    this.editorState,
  }) : attachments = List.unmodifiable(attachments) {
    if (id.isEmpty || revision < 0) {
      throw ArgumentError('Invalid draft identity or revision.');
    }
  }
  final String id;
  final MailAccountId account;
  final int revision;
  final MailEnvelope envelope;
  final MailBody body;
  final List<MailAttachment> attachments;
  final MailDraftEditorState? editorState;
}

/// Frozen bytes/revision/envelope. Later edits cannot modify queued submission.
final class MailPreparedMessage {
  MailPreparedMessage({
    required this.account,
    required this.draftId,
    required this.draftRevision,
    required this.wire,
    required this.envelope,
  }) {
    if (draftId.isEmpty || draftRevision < 0 || wire.length == 0) {
      throw ArgumentError(
        'Prepared message requires draft identity, revision and wire bytes.',
      );
    }
  }
  final MailAccountId account;
  final String draftId;
  final int draftRevision;
  final MailBytes wire;
  final MailTransportEnvelope envelope;
  String get wireHash => wire.sha256;
}

enum MailRecipientAcceptance { accepted, rejected, unknown, notAttempted }

enum MailRecipientSubmission { submitted, notSubmitted, unknown }

/// RCPT acceptance is not submission and never establishes final delivery.
final class MailRecipientResponse {
  const MailRecipientResponse({
    required this.recipient,
    required this.acceptance,
    this.responseCode,
  });
  final String recipient;
  final MailRecipientAcceptance acceptance;
  final int? responseCode;
}

enum MailSubmissionOutcome { accepted, rejected, retryableFailure, uncertain }

/// A submitted result means only that the submission server accepted DATA.
/// Missing recipient responses remain unknown, never synthesized as accepted.
final class MailSubmissionResult {
  MailSubmissionResult({
    required this.attemptId,
    required this.outcome,
    List<MailRecipientResponse> recipients = const [],
    this.problem,
    this.sentCopySaved,
  }) : recipients = List.unmodifiable(recipients) {
    if (attemptId.isEmpty) {
      throw ArgumentError('An attempt identity is required.');
    }
    if (sentCopySaved != null && outcome != MailSubmissionOutcome.accepted) {
      throw ArgumentError('Sent filing requires an accepted submission.');
    }
    final addresses = <String>{};
    for (final response in recipients) {
      _validateMailbox(response.recipient);
      if (!addresses.add(response.recipient)) {
        throw ArgumentError('Duplicate recipient results are ambiguous.');
      }
      final code = response.responseCode;
      if (code != null && (code < 200 || code > 599)) {
        throw ArgumentError('Invalid SMTP response code.');
      }
      if (code != null &&
          ((response.acceptance == MailRecipientAcceptance.accepted &&
                  (code < 200 || code >= 300)) ||
              (response.acceptance == MailRecipientAcceptance.rejected &&
                  code < 400))) {
        throw ArgumentError(
          'Recipient acceptance contradicts its SMTP response.',
        );
      }
    }
    if (outcome == MailSubmissionOutcome.accepted &&
        recipients.any(
          (response) =>
              response.acceptance == MailRecipientAcceptance.rejected ||
              response.acceptance == MailRecipientAcceptance.notAttempted,
        )) {
      throw ArgumentError(
        'All-or-abort submission cannot accept rejected or unattempted recipients.',
      );
    }
  }
  final String attemptId;
  final MailSubmissionOutcome outcome;

  /// Whether the client confirmed filing in Sent. Null means unreported.
  final bool? sentCopySaved;
  final List<MailRecipientResponse> recipients;
  final MailProblem? problem;

  MailRecipientAcceptance acceptanceFor(String recipient) {
    for (final response in recipients) {
      if (response.recipient == recipient) return response.acceptance;
    }
    return MailRecipientAcceptance.unknown;
  }

  MailRecipientSubmission submissionFor(String recipient) {
    switch (outcome) {
      case MailSubmissionOutcome.accepted:
        // Aggregate adapters may know the final DATA result without exposing
        // complete RCPT attempts. Do not invent a recipient-specific result.
        return acceptanceFor(recipient) == MailRecipientAcceptance.accepted
            ? MailRecipientSubmission.submitted
            : MailRecipientSubmission.unknown;
      case MailSubmissionOutcome.rejected:
      case MailSubmissionOutcome.retryableFailure:
        return recipients.any((response) => response.recipient == recipient)
            ? MailRecipientSubmission.notSubmitted
            : MailRecipientSubmission.unknown;
      case MailSubmissionOutcome.uncertain:
        return MailRecipientSubmission.unknown;
    }
  }
}

enum MailOutboxState {
  queued,
  submitting,
  submitted,
  retryableFailure,
  permanentFailure,
  uncertain,
  cancelled,

  /// Sending has been stopped explicitly; earlier delivery remains unknown.
  closedUncertain,
}

/// Immutable state transitions to persist transactionally before network work.
/// Ordinary attempts never retry uncertainty. An explicit acknowledgement is
/// required for each new attempt once an earlier submission may have succeeded.
/// Cancellation is only possible when no attempt may already have succeeded.
final class MailOutboxEntry {
  const MailOutboxEntry._({
    required this.id,
    required this.prepared,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.attemptNumber,
    required this.priorSubmissionUncertain,
    this.sendNotBefore,
    this.scheduleRevision = 0,
    this.attemptId,
    this.result,
  });

  factory MailOutboxEntry.queued({
    required String id,
    required MailPreparedMessage prepared,
    required DateTime now,
    bool priorSubmissionUncertain = false,
  }) {
    if (id.isEmpty) throw ArgumentError('An outbox identity is required.');
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: MailOutboxState.queued,
      createdAt: now,
      updatedAt: now,
      attemptNumber: 0,
      priorSubmissionUncertain: priorSubmissionUncertain,
    );
  }

  /// Reconstruct validated persisted DTOs without invoking a provider. An
  /// in-flight restored entry still requires [recoverInterrupted] before retry.
  factory MailOutboxEntry.restore({
    required String id,
    required MailPreparedMessage prepared,
    required MailOutboxState state,
    required DateTime createdAt,
    required DateTime updatedAt,
    required int attemptNumber,
    String? attemptId,
    MailSubmissionResult? result,
    bool priorSubmissionUncertain = false,
    DateTime? sendNotBefore,
    int scheduleRevision = 0,
  }) {
    if (id.isEmpty ||
        attemptNumber < 0 ||
        (attemptNumber == 0 && (attemptId != null || result != null)) ||
        (attemptNumber > 0 && (attemptId == null || attemptId.isEmpty))) {
      throw ArgumentError('Invalid persisted outbox attempt identity.');
    }
    if (scheduleRevision < 0 ||
        scheduleRevision > maxScheduleRevision ||
        (sendNotBefore != null &&
            (scheduleRevision == 0 ||
                !sendNotBefore.isAfter(createdAt) ||
                (state == MailOutboxState.queued &&
                    !sendNotBefore.isAfter(updatedAt)) ||
                (attemptNumber > 0 && sendNotBefore.isAfter(updatedAt)))) ||
        (scheduleRevision > 0 &&
            attemptNumber == 0 &&
            priorSubmissionUncertain)) {
      throw ArgumentError('Invalid persisted outbox schedule.');
    }
    final needsAttempt =
        state != MailOutboxState.queued &&
        state != MailOutboxState.cancelled &&
        state != MailOutboxState.closedUncertain;
    if ((needsAttempt && attemptNumber == 0) ||
        (state == MailOutboxState.queued && attemptNumber != 0) ||
        (state == MailOutboxState.submitting && result != null) ||
        (state == MailOutboxState.cancelled && priorSubmissionUncertain)) {
      throw ArgumentError('Persisted outbox state contradicts its attempt.');
    }
    final requiredOutcome = switch (state) {
      MailOutboxState.submitted => MailSubmissionOutcome.accepted,
      MailOutboxState.permanentFailure => MailSubmissionOutcome.rejected,
      MailOutboxState.retryableFailure =>
        MailSubmissionOutcome.retryableFailure,
      MailOutboxState.uncertain => MailSubmissionOutcome.uncertain,
      _ => null,
    };
    if ((requiredOutcome != null && result?.outcome != requiredOutcome) ||
        (result != null && result.attemptId != attemptId) ||
        (state == MailOutboxState.cancelled &&
            result != null &&
            result.outcome != MailSubmissionOutcome.retryableFailure)) {
      throw ArgumentError('Persisted outbox outcome contradicts its state.');
    }
    if (state == MailOutboxState.closedUncertain &&
        ((!priorSubmissionUncertain &&
                result?.outcome != MailSubmissionOutcome.uncertain) ||
            (attemptNumber > 0 && result == null) ||
            result?.outcome == MailSubmissionOutcome.accepted)) {
      throw ArgumentError('A closed uncertain entry must retain uncertainty.');
    }
    if (result != null &&
        result.recipients.any(
          (response) =>
              !prepared.envelope.recipients.contains(response.recipient),
        )) {
      throw ArgumentError(
        'Persisted recipient does not belong to the envelope.',
      );
    }
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: state,
      createdAt: createdAt,
      updatedAt: updatedAt,
      attemptNumber: attemptNumber,
      attemptId: attemptId,
      result: result,
      priorSubmissionUncertain: priorSubmissionUncertain,
      sendNotBefore: sendNotBefore?.toUtc(),
      scheduleRevision: scheduleRevision,
    );
  }

  final String id;
  final MailPreparedMessage prepared;
  final MailOutboxState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int attemptNumber;
  final String? attemptId;
  final MailSubmissionResult? result;

  /// Earliest permitted submission instant. Stored in UTC; null is unscheduled.
  /// Keeping the deadline after an attempt records the original send intent,
  /// but does not grant permission to retry that attempt automatically.
  final DateTime? sendNotBefore;

  /// Monotonic compare-and-set token, retained even after clearing a deadline.
  /// This prevents a stale timer or editor from acting after schedule changes.
  final int scheduleRevision;

  /// Largest exact integer supported by every host, including JavaScript.
  static const int maxScheduleRevision = 0x1fffffffffffff;

  /// An older attempt may have been accepted, even if the latest attempt was
  /// definitely rejected. This survives explicit retries and their outcomes.
  /// It may also originate in a recovered composer from before outbox support.
  final bool priorSubmissionUncertain;

  bool get canBeginAttempt =>
      !priorSubmissionUncertain &&
      (state == MailOutboxState.queued ||
          state == MailOutboxState.retryableFailure);

  bool get canBeginAcknowledgedAttempt =>
      state == MailOutboxState.uncertain ||
      (priorSubmissionUncertain &&
          (state == MailOutboxState.queued ||
              state == MailOutboxState.retryableFailure ||
              state == MailOutboxState.permanentFailure));

  bool get canCancel => canBeginAttempt;

  /// Only work that has never reached a provider can receive a new schedule.
  bool get canSchedule =>
      state == MailOutboxState.queued &&
      attemptNumber == 0 &&
      !priorSubmissionUncertain;

  /// Eligibility for an ordinary attempt at [now], including its deadline.
  /// Automated scheduling must additionally require [canSchedule] and a
  /// nonnull [sendNotBefore]; retryable failures remain manual-only work.
  bool isDueAt(DateTime now) =>
      canBeginAttempt &&
      (sendNotBefore == null || !now.isBefore(sendNotBefore!));

  /// Set, replace or clear a deadline without changing the frozen message.
  /// Every call increments the revision, including a repeat or clear, so a
  /// schedule changed away and back cannot revive a stale submission decision.
  MailOutboxEntry schedule({
    required DateTime? sendNotBefore,
    required DateTime now,
  }) {
    if (!canSchedule || scheduleRevision == maxScheduleRevision) {
      throw StateError('This outbox entry cannot be scheduled.');
    }
    if (now.isBefore(updatedAt) ||
        (sendNotBefore != null && !sendNotBefore.isAfter(now))) {
      throw ArgumentError('A send deadline must be in the future.');
    }
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: state,
      createdAt: createdAt,
      updatedAt: now,
      attemptNumber: attemptNumber,
      attemptId: attemptId,
      result: result,
      priorSubmissionUncertain: priorSubmissionUncertain,
      sendNotBefore: sendNotBefore?.toUtc(),
      scheduleRevision: scheduleRevision + 1,
    );
  }

  /// Explicitly stopping retries records no new provider result. This is also
  /// available for a definite later failure with unresolved earlier acceptance.
  bool get canCloseUncertain => canBeginAcknowledgedAttempt;

  /// Local cleanup never recalls a message or proves delivery/non-delivery.
  bool get canRemove =>
      state == MailOutboxState.submitted ||
      state == MailOutboxState.cancelled ||
      state == MailOutboxState.closedUncertain ||
      (state == MailOutboxState.permanentFailure && !priorSubmissionUncertain);

  MailOutboxEntry beginAttempt({
    required String attemptId,
    required DateTime now,
  }) {
    if (!isDueAt(now)) {
      throw StateError('This outbox state cannot be submitted automatically.');
    }
    return _beginAttempt(attemptId: attemptId, now: now, uncertain: false);
  }

  /// Call only after the user checks delivery and explicitly accepts the risk
  /// of a duplicate. This does not establish that the earlier send failed and
  /// does not authorize a later retry after another rejection or interruption.
  MailOutboxEntry beginAcknowledgedAttempt({
    required String attemptId,
    required DateTime now,
  }) {
    if (!canBeginAcknowledgedAttempt) {
      throw StateError('This outbox state has no uncertain attempt to retry.');
    }
    return _beginAttempt(attemptId: attemptId, now: now, uncertain: true);
  }

  MailOutboxEntry _beginAttempt({
    required String attemptId,
    required DateTime now,
    required bool uncertain,
  }) {
    if (attemptId.isEmpty || attemptId == this.attemptId) {
      throw ArgumentError(
        'Every submission attempt requires a fresh identity.',
      );
    }
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: MailOutboxState.submitting,
      createdAt: createdAt,
      updatedAt: now,
      attemptNumber: attemptNumber + 1,
      attemptId: attemptId,
      priorSubmissionUncertain: uncertain,
      sendNotBefore: sendNotBefore,
      scheduleRevision: scheduleRevision,
    );
  }

  MailOutboxEntry complete(
    MailSubmissionResult result, {
    required DateTime now,
  }) {
    if (state != MailOutboxState.submitting || attemptId != result.attemptId) {
      throw StateError('Stale submission result.');
    }
    for (final recipient in result.recipients) {
      if (!prepared.envelope.recipients.contains(recipient.recipient)) {
        throw ArgumentError(
          'Submission result contains an unrelated recipient.',
        );
      }
    }
    final next = switch (result.outcome) {
      MailSubmissionOutcome.accepted => MailOutboxState.submitted,
      MailSubmissionOutcome.rejected => MailOutboxState.permanentFailure,
      MailSubmissionOutcome.retryableFailure =>
        MailOutboxState.retryableFailure,
      MailSubmissionOutcome.uncertain => MailOutboxState.uncertain,
    };
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: next,
      createdAt: createdAt,
      updatedAt: now,
      attemptNumber: attemptNumber,
      attemptId: attemptId,
      result: result,
      priorSubmissionUncertain: priorSubmissionUncertain,
      sendNotBefore: sendNotBefore,
      scheduleRevision: scheduleRevision,
    );
  }

  /// A crash with an in-flight attempt cannot establish non-acceptance.
  MailOutboxEntry recoverInterrupted({required DateTime now}) {
    if (state != MailOutboxState.submitting) return this;
    return complete(
      MailSubmissionResult(
        attemptId: attemptId!,
        outcome: MailSubmissionOutcome.uncertain,
      ),
      now: now,
    );
  }

  MailOutboxEntry cancel({required DateTime now}) {
    if (!canCancel) {
      throw StateError(
        'Cancelling a UI wait does not cancel server acceptance.',
      );
    }
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: MailOutboxState.cancelled,
      createdAt: createdAt,
      updatedAt: now,
      attemptNumber: attemptNumber,
      attemptId: attemptId,
      result: result,
      priorSubmissionUncertain: priorSubmissionUncertain,
      sendNotBefore: sendNotBefore,
      scheduleRevision: scheduleRevision,
    );
  }

  /// Ends this local submission workflow without sending, cancelling a live
  /// provider call, or claiming that an earlier message was or was not accepted.
  /// Frozen bytes and the latest actual outcome remain available for review.
  MailOutboxEntry closeUncertain({required DateTime now}) {
    if (!canCloseUncertain) {
      throw StateError(
        'This outbox state has no unresolved delivery to close.',
      );
    }
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: MailOutboxState.closedUncertain,
      createdAt: createdAt,
      updatedAt: now,
      attemptNumber: attemptNumber,
      attemptId: attemptId,
      result: result,
      priorSubmissionUncertain: priorSubmissionUncertain,
      sendNotBefore: sendNotBefore,
      scheduleRevision: scheduleRevision,
    );
  }
}
