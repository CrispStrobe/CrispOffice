import 'package:quds_mail_core/quds_mail_core.dart';

/// Content-light metadata for one retained foreground command receipt.
/// Listing history never fetches message bodies, attachments or all item text.
final class MailStoredFlagBatchSummary {
  const MailStoredFlagBatchSummary({
    required this.id,
    required this.mailbox,
    required this.provider,
    required this.action,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.complete,
    required this.interrupted,
    required this.confirmedCount,
    required this.failedCount,
    required this.uncertainCount,
    required this.unattemptedCount,
    this.stopReason,
    this.persistenceProblem,
  });

  final String id;
  final MailMailboxId mailbox;
  final MailProviderKind provider;
  final MailBulkFlagAction action;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final bool complete;
  final bool interrupted;
  final int confirmedCount;
  final int failedCount;

  /// Includes an in-flight marker without a durable acknowledgement.
  final int uncertainCount;
  final int unattemptedCount;
  final MailBulkFlagStopReason? stopReason;
  final MailProblem? persistenceProblem;
  int get totalCount =>
      confirmedCount + failedCount + uncertainCount + unattemptedCount;
  bool get requiresRefresh =>
      uncertainCount != 0 ||
      persistenceProblem != null ||
      stopReason == MailBulkFlagStopReason.persistenceFailure ||
      stopReason == MailBulkFlagStopReason.staleScope ||
      stopReason == MailBulkFlagStopReason.invalidScope ||
      stopReason == MailBulkFlagStopReason.scopeCheckFailed;
}

/// A bounded page with an explicit continuation. Its ordering is newest first.
final class MailStoredFlagBatchPage {
  MailStoredFlagBatchPage({
    required List<MailStoredFlagBatchSummary> batches,
    this.nextOffset,
  }) : batches = List.unmodifiable(batches);

  final List<MailStoredFlagBatchSummary> batches;
  final int? nextOffset;
}

/// Read-only evidence about a frozen selection; never an executable retry plan.
final class MailStoredFlagBatch {
  MailStoredFlagBatch({
    required this.summary,
    required this.report,
    required List<String> subjects,
  }) : subjects = List.unmodifiable(subjects);

  final MailStoredFlagBatchSummary summary;
  final MailBulkFlagReport report;
  final List<String> subjects;
}
