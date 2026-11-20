import '../model/identity.dart';
import '../model/result.dart';
import '../ports/provider.dart';
import 'cancellation.dart';

/// Explicit desired states, never a toggle based on a possibly stale flag.
enum MailBulkFlagAction { markRead, markUnread, flag, unflag }

enum MailBulkFlagOutcome { confirmed, failed, uncertain, unattempted }

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
  }) : messages = _freeze(messages) {
    if (id.isEmpty ||
        id.length > 1000 ||
        id.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw ArgumentError('Bulk flags require an ID and 1–1000 identities.');
    }
    final identities = <MailRemoteIdentity>{};
    final provider = this.messages.first.provider;
    int? validity;
    for (final message in this.messages) {
      if (message.account != mailbox.account ||
          message.provider != provider ||
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
  final List<MailRemoteIdentity> messages;

  MailOperation _operation(int index) {
    final operationId = '$id-$index';
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
    };
  }
}

final class MailBulkFlagItemResult {
  const MailBulkFlagItemResult({
    required this.message,
    required this.outcome,
    this.problem,
  });

  final MailRemoteIdentity message;
  final MailBulkFlagOutcome outcome;
  final MailProblem? problem;
}

/// Immutable receipt for every identity, always in the original selection order.
final class MailBulkFlagReport {
  MailBulkFlagReport._({
    required this.plan,
    required List<MailBulkFlagItemResult> results,
    this.stopProblem,
  }) : results = List.unmodifiable(results);

  final MailBulkFlagPlan plan;
  final List<MailBulkFlagItemResult> results;

  /// Why further dispatch stopped. Null also permits definite individual
  /// failures: those do not automatically prevent independent later commands.
  final MailProblem? stopProblem;

  int count(MailBulkFlagOutcome outcome) =>
      results.where((result) => result.outcome == outcome).length;
  int get confirmedCount => count(MailBulkFlagOutcome.confirmed);
  int get failedCount => count(MailBulkFlagOutcome.failed);
  int get uncertainCount => count(MailBulkFlagOutcome.uncertain);
  int get unattemptedCount => count(MailBulkFlagOutcome.unattempted);
  bool get requiresRefresh => uncertainCount != 0;
}

/// Foreground sequential execution without retries, storage or body fetching.
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
  }) async {
    final results = [
      for (final message in plan.messages)
        MailBulkFlagItemResult(
          message: message,
          outcome: MailBulkFlagOutcome.unattempted,
        ),
    ];
    MailProblem? stopProblem;
    MailBulkFlagReport snapshot() => MailBulkFlagReport._(
      plan: plan,
      results: results,
      stopProblem: stopProblem,
    );
    void publish() {
      try {
        onProgress?.call(snapshot());
      } on Object {
        // A display observer cannot erase an outcome or cause a command replay.
      }
    }

    MailProblem? currentProblem() {
      if (lease.account != plan.mailbox.account) {
        return const MailProblem(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        );
      }
      try {
        lease.checkCurrent();
        if (!isScopeCurrent()) {
          return const MailProblem(
            MailProblemCode.staleOperation,
            mutationMayHaveOccurred: false,
          );
        }
      } on MailCancelled catch (cancelled) {
        return MailProblem(
          cancelled.reason == MailCancellationReason.user ||
                  cancelled.reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
          mutationMayHaveOccurred: false,
        );
      } on Object {
        return const MailProblem(
          MailProblemCode.staleOperation,
          mutationMayHaveOccurred: false,
        );
      }
      try {
        if (shouldStop?.call() ?? false) {
          return const MailProblem(
            MailProblemCode.cancelled,
            mutationMayHaveOccurred: false,
          );
        }
      } on Object {
        return const MailProblem(
          MailProblemCode.cancelled,
          mutationMayHaveOccurred: false,
        );
      }
      return null;
    }

    publish();
    for (var index = 0; index < plan.messages.length; index++) {
      stopProblem = currentProblem();
      if (stopProblem != null) break;
      MailResult<MailUnit> result;
      try {
        result = await apply(plan._operation(index), lease);
      } on Object {
        // The callback might throw after dispatch. An exception does not prove
        // that the remote state stayed unchanged, even for cancellation.
        result = const MailFailure(
          MailProblem(MailProblemCode.providerFailure),
        );
      }
      switch (result) {
        case MailSuccess<MailUnit>():
          results[index] = MailBulkFlagItemResult(
            message: plan.messages[index],
            outcome: MailBulkFlagOutcome.confirmed,
          );
        case MailFailure<MailUnit>(:final problem):
          final definite = problem.mutationMayHaveOccurred == false;
          results[index] = MailBulkFlagItemResult(
            message: plan.messages[index],
            outcome: definite
                ? MailBulkFlagOutcome.failed
                : MailBulkFlagOutcome.uncertain,
            problem: problem,
          );
          if (!definite ||
              problem.code == MailProblemCode.cancelled ||
              problem.code == MailProblemCode.staleOperation) {
            stopProblem = problem;
          }
      }
      stopProblem ??= currentProblem();
      publish();
      if (stopProblem != null) break;
    }
    // A progress observer can retire the scope, including after the last item.
    stopProblem ??= currentProblem();
    final report = snapshot();
    return report;
  }
}
