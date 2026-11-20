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
    MailProviderKind? provider,
    required List<MailRemoteIdentity> messages,
    required this.action,
  }) : messages = _freezeMessages(messages) {
    if (id.trim().isEmpty ||
        id.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(id)) {
      throw ArgumentError('A bounded, nonempty bulk operation ID is required.');
    }
    this.provider = provider ?? this.messages.first.provider;
    if (this.provider == MailProviderKind.local) {
      throw ArgumentError(
        'Local messages cannot receive remote flag commands.',
      );
    }
    final unique = <MailRemoteIdentity>{};
    int? uidValidity;
    for (final message in this.messages) {
      if (message.account != mailbox.account ||
          message.provider != this.provider) {
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
  late final MailProviderKind provider;
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
final class MailBulkFlagAttempt {
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
    this.stopProblem,
  ) : items = List.unmodifiable(items);

  final MailBulkFlagPlan plan;
  final List<MailBulkFlagItemResult> items;
  final MailBulkFlagStopReason? stopReason;

  /// Provider evidence or a content-free explanation of why dispatch stopped.
  /// A definite failure of one independent message need not stop the batch.
  final MailProblem? stopProblem;

  /// Both entry points share the same immutable, ordered result objects.
  List<MailBulkFlagItemResult> get results => items;

  int count(MailBulkFlagOutcome outcome) =>
      items.where((item) => item.outcome == outcome).length;

  int get confirmedCount => count(MailBulkFlagOutcome.confirmed);
  int get failedCount => count(MailBulkFlagOutcome.failed);
  int get uncertainCount => count(MailBulkFlagOutcome.uncertain);
  int get unattemptedCount => count(MailBulkFlagOutcome.unattempted);
  bool get requiresRefresh => uncertainCount != 0;
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
    MailProblem? stopProblem;

    MailBulkFlagReport snapshot() => MailBulkFlagReport._(
      plan,
      items,
      stopReason,
      stopProblem ??
          switch (stopReason) {
            MailBulkFlagStopReason.cancelled => const MailProblem(
              MailProblemCode.cancelled,
              mutationMayHaveOccurred: false,
            ),
            MailBulkFlagStopReason.invalidScope => const MailProblem(
              MailProblemCode.invalidInput,
              mutationMayHaveOccurred: false,
            ),
            MailBulkFlagStopReason.staleScope ||
            MailBulkFlagStopReason.scopeCheckFailed => const MailProblem(
              MailProblemCode.staleOperation,
              mutationMayHaveOccurred: false,
            ),
            _ => null,
          },
    );
    void publish() {
      try {
        onProgress?.call(snapshot());
      } on Object {
        // A display observer cannot erase receipts or cause a command replay.
      }
    }

    MailBulkFlagStopReason? interruption() {
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
      try {
        if (!isScopeCurrent()) return MailBulkFlagStopReason.staleScope;
      } catch (_) {
        return MailBulkFlagStopReason.scopeCheckFailed;
      }
      try {
        if (shouldStop?.call() ?? false) {
          return MailBulkFlagStopReason.cancelled;
        }
      } on Object {
        return MailBulkFlagStopReason.cancelled;
      }
      return null;
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
      items[index] = MailBulkFlagItemResult._(
        operation,
        attempt.outcome,
        attempt.problem,
      );
      if (attempt.outcome == MailBulkFlagOutcome.uncertain) {
        stopReason = MailBulkFlagStopReason.uncertain;
        stopProblem = attempt.problem;
      } else if (attempt.outcome == MailBulkFlagOutcome.failed &&
          (attempt.problem?.code == MailProblemCode.cancelled ||
              attempt.problem?.code == MailProblemCode.staleOperation)) {
        // Explicit provider cancellation/scope retirement stops the tail even
        // if a host lease has not yet observed the same transition.
        stopReason = attempt.problem!.code == MailProblemCode.cancelled
            ? MailBulkFlagStopReason.cancelled
            : MailBulkFlagStopReason.staleScope;
        stopProblem = attempt.problem;
      }
      stopReason ??= interruption();
      publish();
      if (stopReason != null) break;
    }
    // An observer may retire the scope after the final settled result.
    stopReason ??= interruption();
    return snapshot();
  }
}

/// Provider-result adapter over the same single-use foreground coordinator.
///
/// Each explicit invocation creates one coordinator. A failed provider result
/// is definite only when its mutation-boundary evidence certifies no write;
/// absent evidence and thrown exceptions remain uncertain. Progress snapshots
/// include every selected identity, with unattempted entries also representing
/// pending work while the host is running. Hosts must guard final publication
/// against their captured account/folder generation.
final class MailBulkFlagRunner {
  const MailBulkFlagRunner();

  Future<MailBulkFlagReport> run({
    required MailBulkFlagPlan plan,
    required MailOperationLease lease,
    required Future<MailResult<MailUnit>> Function(
      MailOperation operation,
      MailOperationLease lease,
    )
    apply,
    required bool Function() isScopeCurrent,
    bool Function()? shouldStop,
    void Function(MailBulkFlagReport report)? onProgress,
  }) => MailBulkFlagCoordinator().run(
    plan: plan,
    lease: lease,
    isScopeCurrent: isScopeCurrent,
    shouldStop: shouldStop,
    onProgress: onProgress,
    apply: (operation, operationLease) async {
      final result = await apply(operation, operationLease);
      return switch (result) {
        MailSuccess<MailUnit>() => const MailBulkFlagAttempt.confirmed(),
        MailFailure<MailUnit>(:final problem) =>
          problem.mutationMayHaveOccurred == false
              ? MailBulkFlagAttempt.failed(problem)
              : MailBulkFlagAttempt.uncertain(problem),
      };
    },
  );
}
