import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_draft.dart';

/// Optional capability of the account's existing draft-store owner. The same
/// repository lease owns drafts and the outbox; no second database opener runs.
abstract interface class StudioMailOutboxStore {
  MailAccountId get account;

  Future<List<MailOutboxEntry>> loadOutbox();

  /// Freezes the validated draft and atomically replaces its saved revision
  /// with a cleared tombstone. A failed transfer retains the original draft.
  Future<MailOutboxEntry> enqueueOutbox(StudioMailDraft draft, String sender);

  Future<MailOutboxEntry> beginOutboxAttempt(
    MailOutboxEntry entry, {
    bool acknowledgeUncertain = false,
  });

  Future<MailOutboxEntry> completeOutboxAttempt(
    MailOutboxEntry entry,
    MailSubmissionResult result,
  );

  Future<MailOutboxEntry> cancelOutbox(MailOutboxEntry entry);
  Future<void> removeOutbox(MailOutboxEntry entry);
}

/// Optional local management on the same account owner. Editing atomically
/// disables the original queue entry and selects a new durable draft. It is
/// available only when no previous attempt may have been accepted.
abstract interface class StudioMailOutboxManagementStore {
  Future<StudioMailDraft> editOutboxAsDraft(MailOutboxEntry entry);
  Future<MailOutboxEntry> closeUncertainOutbox(MailOutboxEntry entry);
}

typedef StudioMailOutboxSubmit =
    Future<MailSubmissionResult> Function(
      MailPreparedMessage message, {
      required String attemptId,
    });

/// One explicit foreground attempt. Persist before the network boundary and
/// retain ambiguous/malformed outcomes without guessing that delivery failed.
Future<MailOutboxEntry> submitStudioMailOutbox({
  required StudioMailOutboxStore store,
  required MailOutboxEntry entry,
  required StudioMailOutboxSubmit submit,
  required bool Function() isCurrent,
  bool acknowledgeUncertain = false,
  void Function(MailOutboxEntry attempt)? onAttemptPersisted,
}) async {
  final attempt = await store.beginOutboxAttempt(
    entry,
    acknowledgeUncertain: acknowledgeUncertain,
  );
  final id = attempt.attemptId!;
  MailSubmissionResult result;
  try {
    onAttemptPersisted?.call(attempt);
    if (!isCurrent()) {
      // No provider was called. Older uncertainty remains on the durable entry.
      result = MailSubmissionResult(
        attemptId: id,
        outcome: MailSubmissionOutcome.retryableFailure,
      );
    } else {
      result = await submit(attempt.prepared, attemptId: id);
      if (result.attemptId != id ||
          result.recipients.any(
            (response) => !attempt.prepared.envelope.recipients.contains(
              response.recipient,
            ),
          )) {
        result = MailSubmissionResult(
          attemptId: id,
          outcome: MailSubmissionOutcome.uncertain,
        );
      }
    }
  } on Object {
    result = MailSubmissionResult(
      attemptId: id,
      outcome: MailSubmissionOutcome.uncertain,
    );
  }
  // If this commit fails, the persisted submitting marker remains guarded and
  // is recovered as uncertain before any later explicit attempt.
  return store.completeOutboxAttempt(attempt, result);
}
