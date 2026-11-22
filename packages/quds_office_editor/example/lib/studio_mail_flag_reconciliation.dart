part of 'studio_mail_flag_journal.dart';

/// Optional connected recovery capability. Reading cached activity does not
/// require this port or construct a provider. A check never replays a command.
abstract interface class StudioMailFlagReconciliationStore {
  Future<MailStoredFlagBatch> reconcile({
    required String id,
    required int expectedRevision,
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required MailFlagObserver observer,
    required bool Function() isCurrent,
    MailCancellationToken? cancellation,
  });
}

/// A dialog supplies its own cancellation and lifetime fence, in addition to
/// the connected host's account/provider/owner checks.
typedef StudioMailReconcileFlagBatch =
    Future<MailStoredFlagBatch> Function(
      MailStoredFlagBatch batch,
      MailCancellationToken cancellation,
      bool Function() isCurrent,
    );

StudioMailReconcileFlagBatch? studioMailFlagRecovery({
  required StudioMailFlagJournalStore store,
  required Object? observer,
  required MailProviderKind provider,
  required bool Function() isCurrent,
  void Function()? onChecked,
}) {
  if (store is! StudioMailFlagReconciliationStore ||
      observer is! MailFlagObserver) {
    return null;
  }
  final recovery = store as StudioMailFlagReconciliationStore;
  final sourceAccount = observer.account;
  return (batch, cancellation, viewCurrent) async {
    if (!batch.summary.canCheckFlags) {
      throw const StudioMailFlagJournalException(MailProblemCode.unsupported);
    }
    bool current() => isCurrent() && viewCurrent();
    try {
      return await recovery.reconcile(
        id: batch.summary.id,
        expectedRevision: batch.summary.revision,
        sourceAccount: sourceAccount,
        provider: provider,
        observer: observer,
        isCurrent: current,
        cancellation: cancellation,
      );
    } finally {
      // A fresh status observation can differ from the live loaded page. The
      // host asks for a normal folder refresh instead of patching stale rows.
      if (isCurrent()) onChecked?.call();
    }
  };
}

MailRemoteIdentity _flagIdentityForAccount(
  MailRemoteIdentity identity,
  MailAccountId account,
) => switch (identity) {
  MailImapIdentity(:final mailbox, :final uidValidity, :final uid) =>
    MailImapIdentity(
      mailbox: MailMailboxId(mailbox.value, account: account),
      uidValidity: uidValidity,
      uid: uid,
    ),
  MailOpaqueIdentity(:final provider, :final value) => MailOpaqueIdentity(
    account: account,
    provider: provider,
    value: value,
  ),
};

Future<MailFlagObservation> _observeFlagStatus(
  MailFlagObserver observer,
  MailRemoteIdentity identity,
  MailOperationLease lease,
  void Function() check,
) async {
  final stopped = Completer<MailResult<MailFlagObservation>>();
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    if (stopped.isCompleted) return;
    try {
      check();
      lease.checkCurrent();
    } on Object catch (error) {
      final code = switch (error) {
        StudioMailFlagJournalException(:final code) => code,
        MailCancelled(:final reason) =>
          reason == MailCancellationReason.user ||
                  reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        _ => MailProblemCode.providerFailure,
      };
      stopped.complete(MailFailure(MailProblem(code)));
    }
  });
  try {
    check();
    lease.checkCurrent();
    // Cancellation can finish a read-only check even if an injected provider
    // does not cooperate. Its late future remains observed and cannot publish.
    return SqliteStudioMailFlagJournalStore._value<MailFlagObservation>(
      await Future.any<MailResult<MailFlagObservation>>([
        observer.observeFlags(identity, lease: lease),
        stopped.future,
      ]),
    );
  } finally {
    timer.cancel();
  }
}

Future<MailStoredFlagBatch> _reconcileFlagBatch(
  SqliteStudioMailFlagJournalStore store, {
  required String id,
  required int expectedRevision,
  required MailAccountId sourceAccount,
  required MailProviderKind provider,
  required MailFlagObserver observer,
  required bool Function() isCurrent,
  MailCancellationToken? cancellation,
}) async {
  final localSession = MailAccountSession(store.account);
  final sourceSession = MailAccountSession(sourceAccount);
  void check() {
    cancellation?.throwIfCancelled();
    if (!isCurrent()) {
      localSession.dispose();
      sourceSession.dispose();
      throw const StudioMailFlagJournalException(
        MailProblemCode.staleOperation,
      );
    }
    if (observer.account != sourceAccount) {
      throw const StudioMailFlagJournalException(
        MailProblemCode.permissionDenied,
      );
    }
  }

  Future<MailStoredFlagBatch> load() async {
    check();
    final batch = await store.load(id);
    check();
    if (batch == null ||
        batch.summary.id != id ||
        batch.summary.mailbox.account != store.account ||
        batch.report.plan.mailbox.account != store.account ||
        batch.summary.provider != provider ||
        batch.report.plan.provider != provider ||
        !batch.summary.complete) {
      throw const StudioMailFlagJournalException(MailProblemCode.conflict);
    }
    return batch;
  }

  try {
    check();
    var batch = await load();
    if (!batch.summary.canCheckFlags) {
      throw const StudioMailFlagJournalException(MailProblemCode.unsupported);
    }
    if (batch.summary.revision != expectedRevision ||
        batch.summary.unresolvedCount == 0) {
      throw const StudioMailFlagJournalException(MailProblemCode.conflict);
    }
    final localLease = localSession.begin(cancellation: cancellation);
    final sourceLease = sourceSession.begin(cancellation: cancellation);
    for (var index = 0; index < batch.report.items.length; index++) {
      if (batch.report.items[index].outcome != MailBulkFlagOutcome.uncertain ||
          batch.resolutions.any((resolution) => resolution.index == index)) {
        continue;
      }
      check();
      final handle = await store._serialize(() async {
        check();
        return SqliteStudioMailFlagJournalStore._value(
          await store._repository.beginFlagReconciliation(
            store.account,
            id,
            index,
            expectedRevision: batch.summary.revision,
            lease: localLease,
            isCurrent: isCurrent,
          ),
        );
      });
      check();
      final remote = _flagIdentityForAccount(handle.message, sourceAccount);
      if (remote.provider != provider) {
        throw const StudioMailFlagJournalException(
          MailProblemCode.permissionDenied,
        );
      }
      // The provider call is outside the storage queue. A concurrent cache or
      // command write is rejected by the repository's observation fence.
      final observed = await _observeFlagStatus(
        observer,
        remote,
        sourceLease,
        check,
      );
      check();
      sourceLease.checkCurrent();
      if (observed.identity != remote) {
        throw const StudioMailFlagJournalException(MailProblemCode.conflict);
      }
      final local = switch (observed.kind) {
        MailFlagObservationKind.present => MailFlagObservation.present(
          identity: handle.message,
          flags: observed.flags!,
        ),
        MailFlagObservationKind.missing => MailFlagObservation.missing(
          identity: handle.message,
        ),
        MailFlagObservationKind.identityChanged => switch (handle.message) {
          final MailImapIdentity identity =>
            MailFlagObservation.identityChanged(identity: identity),
          _ => throw const StudioMailFlagJournalException(
            MailProblemCode.conflict,
          ),
        },
      };
      await store._serialize(() async {
        check();
        SqliteStudioMailFlagJournalStore._value(
          await store._repository.recordFlagObservation(
            handle,
            local,
            lease: localLease,
            isCurrent: isCurrent,
          ),
        );
      });
      batch = await load();
    }
    return batch;
  } on MailCancelled catch (error) {
    throw StudioMailFlagJournalException(
      error.reason == MailCancellationReason.user ||
              error.reason == MailCancellationReason.budgetExpired
          ? MailProblemCode.cancelled
          : MailProblemCode.staleOperation,
    );
  } finally {
    localSession.dispose();
    sourceSession.dispose();
  }
}
