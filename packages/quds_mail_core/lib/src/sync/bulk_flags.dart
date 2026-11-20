import '../model/identity.dart';
import '../model/result.dart';
import '../ports/provider.dart';
import 'cancellation.dart';

/// Foreground changes assign a value; they never toggle an unknown snapshot.
enum MailBulkFlagAction { markRead, markUnread, flag, unflag }

/// Every selected identity receives exactly one of these terminal outcomes.
enum MailBulkFlagOutcome { confirmed, failed, uncertain, unattempted }

enum MailBulkFlagStopReason {
  cancelled,
  staleScope,
  invalidScope,
  scopeCheckFailed,
  uncertain,
  rateLimited,
}

/// An immutable, bounded selection in one account, folder and provider.
///
/// Duplicate identities are rejected rather than silently changing the user's
/// selected count. IMAP selections must share one mailbox and UIDVALIDITY.
/// Opaque provider IDs retain their original account/provider namespaces; the
/// host must separately guard the original folder generation during execution.
final class MailBulkFlagPlan {
  MailBulkFlagPlan({
    required this.id,
    required this.mailbox,
    required this.provider,
    required List<MailRemoteIdentity> messages,
    required this.action,
  }) : messages = _freezeMessages(messages) {
    if (id.trim().isEmpty ||
        id.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(id)) {
      throw ArgumentError('A bounded, nonempty bulk operation ID is required.');
    }
    if (provider == MailProviderKind.local) {
      throw ArgumentError(
        'Local messages cannot receive remote flag commands.',
      );
    }
    final unique = <MailRemoteIdentity>{};
    int? uidValidity;
    for (final message in this.messages) {
      if (message.account != mailbox.account || message.provider != provider) {
        throw ArgumentError('Bulk selections cannot cross accounts/providers.');
      }
      if (!unique.add(message)) {
        throw ArgumentError(
          'Bulk selections cannot contain duplicate identities.',
        );
      }
      if (message is MailImapIdentity) {
        uidValidity ??= message.uidValidity;
        if (message.mailbox != mailbox || message.uidValidity != uidValidity) {
          throw ArgumentError(
            'Bulk IMAP selections require one folder generation.',
          );
        }
      }
    }
  }

  static const int maxMessages = 1000;

  static List<MailRemoteIdentity> _freezeMessages(
    List<MailRemoteIdentity> messages,
  ) {
    if (messages.isEmpty || messages.length > maxMessages) {
      throw ArgumentError('Bulk selections require 1 to 1000 messages.');
    }
    return List.unmodifiable(messages);
  }

  final String id;
  final MailMailboxId mailbox;
  final MailProviderKind provider;
  final List<MailRemoteIdentity> messages;
  final MailBulkFlagAction action;

  /// IDs are stable within this frozen plan and contain no message identifiers.
  MailOperation operationAt(int index) {
    final message = messages[index];
    final operationId = '$id:$index';
    return switch (action) {
      MailBulkFlagAction.markRead => MailSetRead(
        id: operationId,
        message: message,
        read: true,
      ),
      MailBulkFlagAction.markUnread => MailSetRead(
        id: operationId,
        message: message,
        read: false,
      ),
      MailBulkFlagAction.flag => MailSetFlagged(
        id: operationId,
        message: message,
        flagged: true,
      ),
      MailBulkFlagAction.unflag => MailSetFlagged(
        id: operationId,
        message: message,
        flagged: false,
      ),
    };
  }
}

/// A transport adapter's explicit knowledge about one attempted command.
///
/// [failed] requires proof that the remote mutation did not occur. In particular,
/// an arbitrary [MailFailure] from [MailProvider.apply] does not establish that:
/// cancellation, a stale lease, or a lost reply may follow remote acceptance.
/// An adapter without definite rejection evidence must return [uncertain].
/// An explicit possible-mutation problem contradicts a failed certificate and
/// is conservatively retained as uncertain by the coordinator.
final class MailBulkFlagAttempt {
  /// Only explicit no-mutation evidence makes a provider failure definite.
  /// Codes such as permission denied or cancelled cannot establish delivery.
  factory MailBulkFlagAttempt.fromResult(MailResult<MailUnit> result) =>
      switch (result) {
        MailSuccess<MailUnit>() => const MailBulkFlagAttempt.confirmed(),
        MailFailure<MailUnit>(:final problem) =>
          problem.mutationMayHaveOccurred == false
              ? MailBulkFlagAttempt.failed(problem)
              : MailBulkFlagAttempt.uncertain(problem),
      };

  const MailBulkFlagAttempt.confirmed()
    : outcome = MailBulkFlagOutcome.confirmed,
      problem = null;

  const MailBulkFlagAttempt.failed(MailProblem this.problem)
    : outcome = MailBulkFlagOutcome.failed;

  const MailBulkFlagAttempt.uncertain(MailProblem this.problem)
    : outcome = MailBulkFlagOutcome.uncertain;

  final MailBulkFlagOutcome outcome;
  final MailProblem? problem;
}

typedef MailBulkFlagApply =
    Future<MailBulkFlagAttempt> Function(
      MailOperation operation,
      MailOperationLease lease,
    );

final class MailBulkFlagItemResult {
  const MailBulkFlagItemResult._(this.operation, this.outcome, this.problem);

  final MailOperation operation;
  final MailBulkFlagOutcome outcome;
  final MailProblem? problem;
  MailRemoteIdentity get message => operation.message;
}

/// Results preserve original selection order, including every unattempted item.
///
/// A confirmed reply is retained even if the user leaves the folder while the
/// command is in flight. Hosts must recheck the original account/folder
/// generation before publishing this report to a view or a cache. A report is
/// evidence about the frozen identities, not permission to update a new scope.
final class MailBulkFlagReport {
  MailBulkFlagReport._(
    this.plan,
    List<MailBulkFlagItemResult> items,
    this.stopReason,
  ) : items = List.unmodifiable(items);

  final MailBulkFlagPlan plan;
  final List<MailBulkFlagItemResult> items;
  final MailBulkFlagStopReason? stopReason;

  int count(MailBulkFlagOutcome outcome) =>
      items.where((item) => item.outcome == outcome).length;

  int get confirmedCount => count(MailBulkFlagOutcome.confirmed);
  int get failedCount => count(MailBulkFlagOutcome.failed);
  int get uncertainCount => count(MailBulkFlagOutcome.uncertain);
  int get unattemptedCount => count(MailBulkFlagOutcome.unattempted);

  /// Unknown outcomes or an invalidated scope require a fresh observation before
  /// another write. A known reply followed by user cancellation does not.
  /// Hosts must still reject publication into a retired account/folder scope.
  bool get requiresRefresh =>
      uncertainCount != 0 ||
      stopReason == MailBulkFlagStopReason.staleScope ||
      stopReason == MailBulkFlagStopReason.invalidScope ||
      stopReason == MailBulkFlagStopReason.scopeCheckFailed;
}

/// A single-use, sequential foreground batch with no retry or background work.
///
/// [run] awaits an in-flight attempt even after cancellation. Stopping only
/// prevents later dispatches: it cannot retract a command already sent. The
/// adapter owns transport timeouts and must classify a lost reply as uncertain.
/// No raw thrown exception or server text is retained in the report.
///
/// The host captures [run]'s lease and original folder generation before
/// accepting the command. Its synchronous scope check must include that
/// generation (and IMAP UIDVALIDITY), not just an account/folder name that can
/// return after an A-to-B-to-A transition. A separate cancellation token lets
/// the user stop later dispatches without cancelling the transport's lease.
/// The optional `shouldStop` predicate offers the same foreground stop boundary;
/// an exception in that predicate stops dispatch without erasing prior receipts.
/// Progress observers receive immutable, full-order snapshots and cannot cause
/// a retry or erase a settled result if they throw.
final class MailBulkFlagCoordinator {
  bool _started = false;

  Future<MailBulkFlagReport> run({
    required MailBulkFlagPlan plan,
    required MailOperationLease lease,
    required bool Function() isScopeCurrent,
    required MailBulkFlagApply apply,
    MailCancellationToken? cancellation,
    bool Function()? shouldStop,
    void Function(MailBulkFlagReport report)? onProgress,
  }) async {
    if (_started) throw StateError('A bulk coordinator can run only once.');
    _started = true;

    final items = [
      for (var index = 0; index < plan.messages.length; index++)
        MailBulkFlagItemResult._(
          plan.operationAt(index),
          MailBulkFlagOutcome.unattempted,
          null,
        ),
    ];
    MailBulkFlagStopReason? stopReason;

    MailBulkFlagReport snapshot() =>
        MailBulkFlagReport._(plan, items, stopReason);

    void publish() {
      if (onProgress == null) return;
      try {
        onProgress(snapshot());
      } catch (_) {
        // Display failures must not change delivery evidence or replay work.
      }
    }

    MailBulkFlagStopReason? leaseInterruption() {
      if (lease.account != plan.mailbox.account) {
        return MailBulkFlagStopReason.invalidScope;
      }
      final reason = cancellation?.reason ?? lease.cancellation?.reason;
      if (reason != null) {
        return reason == MailCancellationReason.accountChanged ||
                reason == MailCancellationReason.disposed
            ? MailBulkFlagStopReason.staleScope
            : MailBulkFlagStopReason.cancelled;
      }
      if (!lease.isCurrent) return MailBulkFlagStopReason.staleScope;
      return null;
    }

    MailBulkFlagStopReason? interruption() {
      final initial = leaseInterruption();
      if (initial != null) return initial;
      try {
        if (!isScopeCurrent()) return MailBulkFlagStopReason.staleScope;
      } catch (_) {
        return MailBulkFlagStopReason.scopeCheckFailed;
      }
      try {
        if (shouldStop?.call() ?? false) {
          return MailBulkFlagStopReason.cancelled;
        }
      } catch (_) {
        return MailBulkFlagStopReason.cancelled;
      }
      // A synchronous caller guard can retire the lease while returning a
      // permissive value. Recheck it before accepting the next dispatch.
      return leaseInterruption();
    }

    publish();
    for (var index = 0; index < plan.messages.length; index++) {
      stopReason = interruption();
      if (stopReason != null) break;

      final operation = items[index].operation;
      MailBulkFlagAttempt attempt;
      try {
        attempt = await apply(operation, lease);
      } catch (_) {
        // Once the adapter is invoked there is no generic proof of non-delivery,
        // including for a synchronous exception or MailCancelled.
        attempt = const MailBulkFlagAttempt.uncertain(
          MailProblem(MailProblemCode.providerFailure),
        );
      }
      final problem = attempt.problem;
      final outcome =
          attempt.outcome == MailBulkFlagOutcome.failed &&
              problem?.mutationMayHaveOccurred == true
          ? MailBulkFlagOutcome.uncertain
          : attempt.outcome;
      items[index] = MailBulkFlagItemResult._(operation, outcome, problem);
      if (outcome == MailBulkFlagOutcome.uncertain) {
        stopReason = MailBulkFlagStopReason.uncertain;
      } else if (outcome == MailBulkFlagOutcome.failed) {
        stopReason = switch (problem?.code) {
          MailProblemCode.cancelled => MailBulkFlagStopReason.cancelled,
          MailProblemCode.staleOperation => MailBulkFlagStopReason.staleScope,
          MailProblemCode.quotaExceeded => MailBulkFlagStopReason.rateLimited,
          _ => null,
        };
      }
      stopReason ??= interruption();
      publish();
      if (stopReason != null) break;
    }

    // A progress observer can retire the scope after any result, including the
    // last one. Keep its receipt but never present that as a current-scope batch.
    stopReason ??= interruption();
    return snapshot();
  }
}
