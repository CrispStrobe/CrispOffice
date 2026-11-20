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
  }) : recipients = List.unmodifiable(recipients) {
    if (attemptId.isEmpty) {
      throw ArgumentError('An attempt identity is required.');
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
}

/// Immutable state transitions to persist transactionally before network work.
/// No transition retries an uncertain attempt. Cancellation is pre-submission.
final class MailOutboxEntry {
  const MailOutboxEntry._({
    required this.id,
    required this.prepared,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.attemptNumber,
    this.attemptId,
    this.result,
  });

  factory MailOutboxEntry.queued({
    required String id,
    required MailPreparedMessage prepared,
    required DateTime now,
  }) {
    if (id.isEmpty) throw ArgumentError('An outbox identity is required.');
    return MailOutboxEntry._(
      id: id,
      prepared: prepared,
      state: MailOutboxState.queued,
      createdAt: now,
      updatedAt: now,
      attemptNumber: 0,
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
  }) {
    if (id.isEmpty ||
        attemptNumber < 0 ||
        (attemptNumber == 0 && (attemptId != null || result != null)) ||
        (attemptNumber > 0 && (attemptId == null || attemptId.isEmpty))) {
      throw ArgumentError('Invalid persisted outbox attempt identity.');
    }
    final needsAttempt =
        state != MailOutboxState.queued && state != MailOutboxState.cancelled;
    if ((needsAttempt && attemptNumber == 0) ||
        (state == MailOutboxState.queued && attemptNumber != 0) ||
        (state == MailOutboxState.submitting && result != null)) {
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
  bool get canBeginAttempt =>
      state == MailOutboxState.queued ||
      state == MailOutboxState.retryableFailure;

  MailOutboxEntry beginAttempt({
    required String attemptId,
    required DateTime now,
  }) {
    if (!canBeginAttempt) {
      throw StateError('This outbox state cannot be submitted automatically.');
    }
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
    if (!canBeginAttempt) {
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
    );
  }
}
