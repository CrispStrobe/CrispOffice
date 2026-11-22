import 'package:quds_mail_core/quds_mail_core.dart';

/// A later read-only observation, separate from the original dispatch receipt.
enum MailFlagResolutionKind { matches, differs, missing, identityChanged }

final class MailStoredFlagResolution {
  const MailStoredFlagResolution({
    required this.index,
    required this.kind,
    required this.checkedAt,
  });

  final int index;
  final MailFlagResolutionKind kind;
  final DateTime checkedAt;
}

/// Latest read-only location evidence for an uncertain membership command.
/// This does not resolve its historical outcome or authorize command replay.
final class MailStoredMembershipObservation {
  const MailStoredMembershipObservation({
    required this.index,
    required this.observation,
    required this.checkedAt,
  });

  final int index;
  final MailMembershipObservation observation;
  final DateTime checkedAt;
}

/// An acknowledged move mapping and whether its exact retained cache could be
/// updated in the same transaction. A skipped projection still preserves the
/// provider acknowledgement; an explicit refresh obtains a current view.
final class MailStoredMoveIdentityTransition {
  const MailStoredMoveIdentityTransition({
    required this.index,
    required this.transition,
    required this.recordedAt,
    required this.cacheProjected,
  });

  final int index;
  final MailMoveIdentityTransition transition;
  final DateTime recordedAt;
  final bool cacheProjected;
}

/// Content-light metadata for one retained foreground command receipt.
/// Listing history never fetches message bodies, attachments or all item text.
final class MailStoredFlagBatchSummary {
  const MailStoredFlagBatchSummary({
    required this.id,
    required this.mailbox,
    required this.provider,
    required this.action,
    this.destination,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.complete,
    required this.interrupted,
    required this.confirmedCount,
    required this.failedCount,
    required this.uncertainCount,
    required this.unattemptedCount,
    this.reconciledCount = 0,
    this.stopReason,
    this.persistenceProblem,
  });

  final String id;
  final MailMailboxId mailbox;
  final MailProviderKind provider;
  final MailBulkFlagAction action;
  final MailMailboxId? destination;

  /// Membership changes need provider-specific reconciliation, not flag reads.
  bool get canCheckFlags => action.isFlagAction;
  bool get canCheckMembership => !action.isFlagAction;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final bool complete;
  final bool interrupted;
  final int confirmedCount;
  final int failedCount;

  /// Includes an in-flight marker without a durable acknowledgement.
  final int uncertainCount;
  final int reconciledCount;
  int get unresolvedCount => uncertainCount - reconciledCount;
  final int unattemptedCount;
  final MailBulkFlagStopReason? stopReason;
  final MailProblem? persistenceProblem;
  int get totalCount =>
      confirmedCount + failedCount + uncertainCount + unattemptedCount;
  bool get requiresRefresh =>
      (!action.isFlagAction && confirmedCount != 0) ||
      unresolvedCount != 0 ||
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
    List<MailStoredFlagResolution> resolutions = const [],
    List<MailStoredMembershipObservation> membershipObservations = const [],
    List<MailStoredMoveIdentityTransition> identityTransitions = const [],
  }) : subjects = List.unmodifiable(subjects),
       resolutions = List.unmodifiable(resolutions),
       membershipObservations = List.unmodifiable(membershipObservations),
       identityTransitions = List.unmodifiable(identityTransitions);

  final MailStoredFlagBatchSummary summary;
  final MailBulkFlagReport report;
  final List<String> subjects;
  final List<MailStoredFlagResolution> resolutions;
  final List<MailStoredMembershipObservation> membershipObservations;
  final List<MailStoredMoveIdentityTransition> identityTransitions;
}
