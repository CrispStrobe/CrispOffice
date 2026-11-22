import '../model/identity.dart';
import '../model/result.dart';
import '../ports/mutation_receipt.dart';
import '../ports/provider.dart';
import 'cancellation.dart';

/// Explicit foreground commands, never a toggle based on possibly stale state.
///
/// The original flag API name is retained for existing consumers. Membership
/// commands share its durable dispatch ordering and conservative receipts.
enum MailBulkFlagAction {
  markRead,
  markUnread,
  flag,
  unflag,
  move,
  delete,
  archive;

  /// Only these actions can be checked through a [MailFlagObserver].
  bool get isFlagAction => switch (this) {
    markRead || markUnread || flag || unflag => true,
    move || delete || archive => false,
  };
}

enum MailBulkFlagOutcome { confirmed, failed, uncertain, unattempted }

/// Why a foreground run stopped. Uncertainty takes precedence over a stop or
/// scope change observed while its current request was in flight.
enum MailBulkFlagStopReason {
  cancelled,
  staleScope,
  invalidScope,
  scopeCheckFailed,
  uncertain,
  rateLimited,
  persistenceFailure,
}

/// Frozen identities selected from one observed foreground mailbox.
///
/// The host must freeze the remote identities from its loaded rows before
/// starting work. Opaque provider identities do not themselves prove folder
/// membership; that remains part of the host's selected-folder snapshot.
/// No body, display text or nullable flag observation is needed for a plan.
final class MailBulkFlagPlan {
  MailBulkFlagPlan({
    required this.id,
    required this.mailbox,
    required this.action,
    required List<MailRemoteIdentity> messages,
    MailProviderKind? provider,
    this.destination,
  }) : messages = _freeze(messages) {
    if (id.trim().isEmpty ||
        id.length > 256 ||
        id.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw ArgumentError(
        'Bulk flags require a nonblank ID of 1–256 characters.',
      );
    }
    if (this.provider == MailProviderKind.local ||
        (provider != null && provider != this.provider)) {
      throw ArgumentError('Bulk flags require the selected remote provider.');
    }
    if ((action == MailBulkFlagAction.move) != (destination != null) ||
        (destination != null &&
            (destination!.account != mailbox.account ||
                destination == mailbox))) {
      throw ArgumentError(
        'Only move requires a different destination in the same account.',
      );
    }
    if (action == MailBulkFlagAction.archive &&
        (this.provider != MailProviderKind.gmail || mailbox.value != 'INBOX')) {
      throw ArgumentError(
        'Native Archive requires a Gmail Inbox selection; folder providers '
        'must freeze a move destination.',
      );
    }
    final identities = <MailRemoteIdentity>{};
    int? validity;
    for (final message in this.messages) {
      if (message.account != mailbox.account ||
          message.provider != this.provider ||
          !identities.add(message)) {
        throw ArgumentError(
          'Bulk identities must be unique and belong to one account/provider.',
        );
      }
      if (message is MailImapIdentity) {
        validity ??= message.uidValidity;
        if (message.mailbox != mailbox || message.uidValidity != validity) {
          throw ArgumentError(
            'Bulk IMAP identities must share the selected mailbox generation.',
          );
        }
      }
    }
  }

  static const int maxMessages = 1000;

  static List<MailRemoteIdentity> _freeze(List<MailRemoteIdentity> messages) {
    if (messages.isEmpty || messages.length > maxMessages) {
      throw ArgumentError('Bulk flags require 1–1000 identities.');
    }
    return List.unmodifiable(messages);
  }

  final String id;
  final MailMailboxId mailbox;
  final MailBulkFlagAction action;
  final MailMailboxId? destination;
  final List<MailRemoteIdentity> messages;

  /// The frozen provider namespace, optionally checked by the constructor.
  MailProviderKind get provider => messages.first.provider;

  /// Reconstructs the explicit desired state and stable `planId:index` ID.
  MailOperation operationAt(int index) {
    final operationId = '$id:$index';
    final message = messages[index];
    return switch (action) {
      MailBulkFlagAction.markRead ||
      MailBulkFlagAction.markUnread => MailSetRead(
        id: operationId,
        message: message,
        read: action == MailBulkFlagAction.markRead,
      ),
      MailBulkFlagAction.flag || MailBulkFlagAction.unflag => MailSetFlagged(
        id: operationId,
        message: message,
        flagged: action == MailBulkFlagAction.flag,
      ),
      MailBulkFlagAction.move => MailMove(
        id: operationId,
        message: message,
        destination: destination!,
      ),
      MailBulkFlagAction.delete => MailDelete(
        id: operationId,
        message: message,
      ),
      MailBulkFlagAction.archive => MailArchive(
        id: operationId,
        message: message,
      ),
    };
  }
}

/// An adapter's evidence about one dispatched write.
///
/// [MailBulkFlagAttempt.failed] certifies that the operation had no remote
/// effect. Use [MailBulkFlagAttempt.uncertain] whenever delivery or acceptance
/// is unknown. Explicit `mutationMayHaveOccurred: true` on a failed problem
/// contradicts that certificate and is conservatively treated as uncertain.
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

  factory MailBulkFlagAttempt.fromReceiptResult(
    MailResult<MailMutationReceipt> result,
  ) => switch (result) {
    MailSuccess<MailMutationReceipt>(:final value) =>
      MailBulkFlagAttempt.confirmed(
        identityTransition: value.identityTransition,
      ),
    MailFailure<MailMutationReceipt>(:final problem) =>
      problem.mutationMayHaveOccurred == false
          ? MailBulkFlagAttempt.failed(problem)
          : MailBulkFlagAttempt.uncertain(problem),
  };

  const MailBulkFlagAttempt.confirmed({this.identityTransition})
    : outcome = MailBulkFlagOutcome.confirmed,
      problem = null;

  const MailBulkFlagAttempt.failed(MailProblem this.problem)
    : outcome = MailBulkFlagOutcome.failed,
      identityTransition = null;

  const MailBulkFlagAttempt.uncertain(MailProblem this.problem)
    : outcome = MailBulkFlagOutcome.uncertain,
      identityTransition = null;

  final MailBulkFlagOutcome outcome;
  final MailProblem? problem;
  final MailMoveIdentityTransition? identityTransition;
}

typedef MailBulkFlagApply =
    Future<MailBulkFlagAttempt> Function(
      MailOperation operation,
      MailOperationLease lease,
    );

final class MailBulkFlagItemResult {
  const MailBulkFlagItemResult({
    required this.operation,
    required this.outcome,
    this.problem,
    this.identityTransition,
  });

  factory MailBulkFlagItemResult.restore({
    required MailOperation operation,
    required MailBulkFlagOutcome outcome,
    MailProblem? problem,
    MailMoveIdentityTransition? identityTransition,
  }) {
    if (operation is! MailSetRead &&
            operation is! MailSetFlagged &&
            operation is! MailMove &&
            operation is! MailDelete &&
            operation is! MailArchive ||
        ((outcome == MailBulkFlagOutcome.confirmed ||
                outcome == MailBulkFlagOutcome.unattempted) &&
            problem != null) ||
        (outcome == MailBulkFlagOutcome.failed &&
            (problem == null || problem.mutationMayHaveOccurred == true)) ||
        (identityTransition != null &&
            (outcome != MailBulkFlagOutcome.confirmed ||
                !identityTransition.matches(operation)))) {
      throw ArgumentError('Invalid flag receipt evidence.');
    }
    return MailBulkFlagItemResult(
      operation: operation,
      outcome: outcome,
      problem: problem,
      identityTransition: identityTransition,
    );
  }

  final MailOperation operation;
  MailRemoteIdentity get message => operation.message;
  final MailBulkFlagOutcome outcome;
  final MailProblem? problem;
  final MailMoveIdentityTransition? identityTransition;
}

/// Immutable receipt for every identity, always in the original selection order.
final class MailBulkFlagReport {
  MailBulkFlagReport._({
    required this.plan,
    required List<MailBulkFlagItemResult> results,
    this.stopProblem,
    this.stopReason,
    this.persistenceProblem,
  }) : results = List.unmodifiable(results);

  /// Restores read-only evidence. Result commands and ordering must exactly
  /// match the frozen plan; this factory never executes that plan.
  factory MailBulkFlagReport.restore({
    required MailBulkFlagPlan plan,
    required List<MailBulkFlagItemResult> results,
    MailProblem? stopProblem,
    MailBulkFlagStopReason? stopReason,
    MailProblem? persistenceProblem,
  }) {
    if (results.length != plan.messages.length) {
      throw ArgumentError('A receipt requires every frozen result.');
    }
    for (var i = 0; i < results.length; i++) {
      MailBulkFlagItemResult.restore(
        operation: results[i].operation,
        outcome: results[i].outcome,
        problem: results[i].problem,
        identityTransition: results[i].identityTransition,
      );
      if (results[i].identityTransition case final transition?) {
        if (!transition.matches(
          results[i].operation,
          sourceMailbox: plan.mailbox,
        )) {
          throw ArgumentError('Move evidence must retain its frozen source.');
        }
      }
      final expected = plan.operationAt(i);
      final actual = results[i].operation;
      if (actual.id != expected.id ||
          actual.message != expected.message ||
          switch ((actual, expected)) {
            (final MailSetRead a, final MailSetRead b) => a.read != b.read,
            (final MailSetFlagged a, final MailSetFlagged b) =>
              a.flagged != b.flagged,
            (final MailMove a, final MailMove b) =>
              a.destination != b.destination,
            (MailDelete(), MailDelete()) => false,
            (MailArchive(), MailArchive()) => false,
            _ => true,
          }) {
        throw ArgumentError('A receipt must retain its frozen commands.');
      }
    }
    return MailBulkFlagReport._(
      plan: plan,
      results: results,
      stopProblem: stopProblem,
      stopReason: stopReason,
      persistenceProblem: persistenceProblem,
    );
  }

  final MailBulkFlagPlan plan;
  final List<MailBulkFlagItemResult> results;
  List<MailBulkFlagItemResult> get items => results;

  /// Why further dispatch stopped. Null also permits definite individual
  /// failures: those do not automatically prevent independent later commands.
  final MailProblem? stopProblem;

  /// Uncertainty wins over any concurrent cancellation or scope change.
  /// Otherwise a certified cancelled/stale provider result wins, followed by
  /// foreign-account lease, cancellation, stale lease, scope and stop checks.
  /// Per-message acknowledgements are retained regardless of this reason.
  final MailBulkFlagStopReason? stopReason;

  /// A local write failed. This never erases a provider acknowledgement.
  final MailProblem? persistenceProblem;

  int count(MailBulkFlagOutcome outcome) =>
      results.where((result) => result.outcome == outcome).length;
  int get confirmedCount => count(MailBulkFlagOutcome.confirmed);
  int get failedCount => count(MailBulkFlagOutcome.failed);
  int get uncertainCount => count(MailBulkFlagOutcome.uncertain);
  int get unattemptedCount => count(MailBulkFlagOutcome.unattempted);
  bool get requiresRefresh =>
      (!plan.action.isFlagAction && confirmedCount != 0) ||
      uncertainCount != 0 ||
      persistenceProblem != null ||
      stopReason == MailBulkFlagStopReason.persistenceFailure ||
      stopReason == MailBulkFlagStopReason.staleScope ||
      stopReason == MailBulkFlagStopReason.invalidScope ||
      stopReason == MailBulkFlagStopReason.scopeCheckFailed;
}

/// Durable lifecycle for a foreground attempt. Every callback must commit
/// before succeeding. Restored receipts never authorize a retry or dispatch.
abstract interface class MailBulkFlagJournal {
  Future<MailResult<MailUnit>> prepare(MailBulkFlagPlan plan);
  Future<MailResult<MailUnit>> beginAttempt(int index);
  Future<MailResult<MailUnit>> recordResult(
    int index,
    MailBulkFlagItemResult result,
  );
  Future<MailResult<MailUnit>> finish(MailBulkFlagReport report);
}

/// Foreground sequential execution with an optional durable journal and no
/// retries or body fetching.
///
/// The host supplies a fresh lease and a predicate bound to the captured account,
/// folder and generation. Both are checked before each dispatch. The predicate
/// must remain false once its scope is retired. An acknowledged in-flight result
/// is retained even if the host leaves that scope; hosts must separately reject
/// projecting such results into a newer view. Uncertainty stops the batch and
/// requires a new observation before another mutation. [run]'s optional
/// `shouldStop` callback requests a stop after the current message settles,
/// without cancelling the provider lease or discarding its acknowledgement.
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
    MailBulkFlagJournal? journal,
  }) => _runBulkFlags(
    plan: plan,
    lease: lease,
    isScopeCurrent: isScopeCurrent,
    shouldStop: shouldStop,
    onProgress: onProgress,
    journal: journal,
    apply: (operation, lease) async =>
        MailBulkFlagAttempt.fromResult(await apply(operation, lease)),
  );
}

/// Single-use adapter for transports that already classify write outcomes.
///
/// It shares the runner's execution engine, progress and scope checks. A
/// separate [run] `cancellation` token requests a stop after the current reply
/// without cancelling the provider's lease. Neither overlapping invocation nor
/// replay of a completed coordinator is permitted.
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
    MailBulkFlagJournal? journal,
  }) async {
    if (_started) {
      throw StateError('A bulk flag coordinator can only run once.');
    }
    _started = true;
    return _runBulkFlags(
      plan: plan,
      lease: lease,
      isScopeCurrent: isScopeCurrent,
      apply: apply,
      cancellation: cancellation,
      shouldStop: shouldStop,
      onProgress: onProgress,
      journal: journal,
    );
  }
}

typedef _BulkInterruption = ({
  MailProblem problem,
  MailBulkFlagStopReason reason,
});

/// One dispatch algorithm for both provider results and certified adapters.
Future<MailBulkFlagReport> _runBulkFlags({
  required MailBulkFlagPlan plan,
  required MailOperationLease lease,
  required MailBulkFlagApply apply,
  required bool Function() isScopeCurrent,
  MailCancellationToken? cancellation,
  bool Function()? shouldStop,
  void Function(MailBulkFlagReport report)? onProgress,
  MailBulkFlagJournal? journal,
}) async {
  final results = [
    for (var index = 0; index < plan.messages.length; index++)
      MailBulkFlagItemResult(
        operation: plan.operationAt(index),
        outcome: MailBulkFlagOutcome.unattempted,
      ),
  ];
  MailProblem? stopProblem;
  MailBulkFlagStopReason? stopReason;
  MailProblem? persistenceProblem;
  MailBulkFlagReport snapshot() => MailBulkFlagReport._(
    plan: plan,
    results: results,
    stopProblem: stopProblem,
    stopReason: stopReason,
    persistenceProblem: persistenceProblem,
  );
  void publish() {
    try {
      onProgress?.call(snapshot());
    } on Object {
      // A display observer cannot erase an outcome or cause a command replay.
    }
  }

  _BulkInterruption cancelled(MailCancellationReason reason) {
    final userStop =
        reason == MailCancellationReason.user ||
        reason == MailCancellationReason.budgetExpired;
    return (
      problem: MailProblem(
        userStop ? MailProblemCode.cancelled : MailProblemCode.staleOperation,
        mutationMayHaveOccurred: false,
      ),
      reason: userStop
          ? MailBulkFlagStopReason.cancelled
          : MailBulkFlagStopReason.staleScope,
    );
  }

  _BulkInterruption? leaseInterruption() {
    if (lease.account != plan.mailbox.account) {
      return (
        problem: const MailProblem(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        ),
        reason: MailBulkFlagStopReason.invalidScope,
      );
    }
    final cancellationReason =
        cancellation?.reason ?? lease.cancellation?.reason;
    if (cancellationReason != null) return cancelled(cancellationReason);
    if (!lease.isCurrent) {
      return (
        problem: const MailProblem(
          MailProblemCode.staleOperation,
          mutationMayHaveOccurred: false,
        ),
        reason: MailBulkFlagStopReason.staleScope,
      );
    }
    return null;
  }

  _BulkInterruption? interruption() {
    final initial = leaseInterruption();
    if (initial != null) return initial;
    try {
      if (!isScopeCurrent()) {
        return (
          problem: const MailProblem(
            MailProblemCode.staleOperation,
            mutationMayHaveOccurred: false,
          ),
          reason: MailBulkFlagStopReason.staleScope,
        );
      }
    } on Object {
      return (
        problem: const MailProblem(
          MailProblemCode.staleOperation,
          mutationMayHaveOccurred: false,
        ),
        reason: MailBulkFlagStopReason.scopeCheckFailed,
      );
    }
    try {
      if (shouldStop?.call() ?? false) {
        return cancelled(MailCancellationReason.user);
      }
    } on Object {
      return cancelled(MailCancellationReason.user);
    }
    // A caller's synchronous predicate can trigger cancellation or retire its
    // lease. Do not dispatch after such a reentrant change.
    return leaseInterruption();
  }

  void observeInterruption() {
    if (stopProblem != null) return;
    final current = interruption();
    if (current == null) return;
    stopProblem = current.problem;
    stopReason = current.reason;
  }

  Future<bool> persist(Future<MailResult<MailUnit>> Function() write) async {
    MailResult<MailUnit> result;
    try {
      result = await write();
    } on Object {
      result = const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
    if (result case MailFailure<MailUnit>(:final problem)) {
      persistenceProblem ??= problem;
      if (stopReason != MailBulkFlagStopReason.uncertain) {
        stopProblem = problem;
        stopReason = MailBulkFlagStopReason.persistenceFailure;
      }
      return false;
    }
    return true;
  }

  publish();
  var prepared = false;
  if (journal != null) {
    observeInterruption();
    if (stopProblem == null) {
      prepared = await persist(() => journal.prepare(plan));
      // A persisted intent is not permission to dispatch into a retired view.
      observeInterruption();
    }
  }
  for (var index = 0; index < plan.messages.length; index++) {
    observeInterruption();
    if (stopProblem != null) break;
    if (journal != null) {
      if (!await persist(() => journal.beginAttempt(index))) break;
      // Cancellation can arrive while SQLite commits the dispatch marker.
      // finish() then retains this item as definitely not attempted.
      observeInterruption();
      if (stopProblem != null) break;
    }
    MailBulkFlagAttempt attempt;
    try {
      attempt = await apply(results[index].operation, lease);
    } on Object {
      // The callback might throw after dispatch. An exception does not prove
      // that the remote state stayed unchanged, even for cancellation.
      attempt = const MailBulkFlagAttempt.uncertain(
        MailProblem(MailProblemCode.providerFailure),
      );
    }
    if (attempt.identityTransition case final transition?) {
      if (attempt.outcome != MailBulkFlagOutcome.confirmed ||
          !transition.matches(
            results[index].operation,
            sourceMailbox: plan.mailbox,
          )) {
        // Malformed acknowledgements cannot authorize projection or a retry.
        attempt = const MailBulkFlagAttempt.uncertain(
          MailProblem(MailProblemCode.conflict, mutationMayHaveOccurred: true),
        );
      }
    }
    final problem = attempt.problem;
    final outcome =
        attempt.outcome == MailBulkFlagOutcome.failed &&
            problem?.mutationMayHaveOccurred == true
        ? MailBulkFlagOutcome.uncertain
        : attempt.outcome;
    results[index] = MailBulkFlagItemResult(
      operation: results[index].operation,
      outcome: outcome,
      problem: problem,
      identityTransition: attempt.identityTransition,
    );
    if (outcome == MailBulkFlagOutcome.uncertain) {
      stopProblem = problem;
      stopReason = MailBulkFlagStopReason.uncertain;
    } else if (problem?.code == MailProblemCode.cancelled) {
      stopProblem = problem;
      stopReason = MailBulkFlagStopReason.cancelled;
    } else if (problem?.code == MailProblemCode.staleOperation) {
      stopProblem = problem;
      stopReason = MailBulkFlagStopReason.staleScope;
    } else if (outcome == MailBulkFlagOutcome.failed &&
        problem?.code == MailProblemCode.quotaExceeded) {
      stopProblem = problem;
      stopReason = MailBulkFlagStopReason.rateLimited;
    }
    if (journal != null) {
      await persist(() => journal.recordResult(index, results[index]));
    }
    observeInterruption();
    publish();
    if (stopProblem != null) break;
  }
  // A progress observer can retire the scope, including after the last item.
  observeInterruption();
  if (prepared && journal != null) {
    await persist(() => journal.finish(snapshot()));
  }
  if (journal != null) publish();
  return snapshot();
}
