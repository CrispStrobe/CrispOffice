part of 'studio_mail_flag_journal.dart';

/// Optional read-only membership checks. They retain historical uncertainty and
/// never replay Move/Delete or project an unverified destination into a cache.
abstract interface class StudioMailMembershipReconciliationStore {
  Future<MailStoredFlagBatch> reconcileMembership({
    required String id,
    required int expectedRevision,
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required MailMembershipObserver observer,
    required bool Function() isCurrent,
    MailCancellationToken? cancellation,
  });
}

typedef StudioMailReconcileMembershipBatch =
    Future<MailStoredFlagBatch> Function(
      MailStoredFlagBatch batch,
      MailCancellationToken cancellation,
      bool Function() isCurrent,
    );

StudioMailReconcileMembershipBatch? studioMailMembershipRecovery({
  required StudioMailFlagJournalStore store,
  required Object? observer,
  required MailProviderKind provider,
  required bool Function() isCurrent,
  void Function()? onChecked,
}) {
  if (store is! StudioMailMembershipReconciliationStore ||
      observer is! MailMembershipObserver) {
    return null;
  }
  final recovery = store as StudioMailMembershipReconciliationStore;
  final sourceAccount = observer.account;
  return (batch, cancellation, viewCurrent) async {
    if (!batch.summary.canCheckMembership) {
      throw const StudioMailFlagJournalException(MailProblemCode.unsupported);
    }
    bool current() => isCurrent() && viewCurrent();
    try {
      return await recovery.reconcileMembership(
        id: batch.summary.id,
        expectedRevision: batch.summary.revision,
        sourceAccount: sourceAccount,
        provider: provider,
        observer: observer,
        isCurrent: current,
        cancellation: cancellation,
      );
    } finally {
      if (isCurrent()) onChecked?.call();
    }
  };
}

Future<MailMembershipObservation> _observeMembershipStatus(
  MailMembershipObserver observer,
  MailRemoteIdentity identity,
  MailOperationLease lease,
  void Function() check,
) async {
  final stopped = Completer<MailResult<MailMembershipObservation>>();
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
    return SqliteStudioMailFlagJournalStore._value<MailMembershipObservation>(
      await Future.any<MailResult<MailMembershipObservation>>([
        observer.observeMembership(identity, lease: lease),
        stopped.future,
      ]),
    );
  } finally {
    timer.cancel();
  }
}

MailMembershipObservation _membershipForAccount(
  MailMembershipObservation observed,
  MailRemoteIdentity identity,
) => switch (observed.kind) {
  MailMembershipObservationKind.missing => MailMembershipObservation.missing(
    identity: identity,
  ),
  MailMembershipObservationKind.identityChanged => switch (identity) {
    final MailImapIdentity imap => MailMembershipObservation.identityChanged(
      identity: imap,
    ),
    _ => throw const StudioMailFlagJournalException(MailProblemCode.conflict),
  },
  MailMembershipObservationKind.present => switch (identity) {
    final MailImapIdentity imap => MailMembershipObservation.imap(
      identity: imap,
      isDeleted: observed.isDeleted!,
    ),
    final MailOpaqueIdentity opaque => MailMembershipObservation.folders(
      identity: opaque,
      mailboxes: [
        for (final folder in observed.mailboxes)
          MailMailboxId(folder.value, account: identity.account),
      ],
      deletionMailbox: observed.deletionMailbox == null
          ? null
          : MailMailboxId(
              observed.deletionMailbox!.value,
              account: identity.account,
            ),
    ),
  },
};

Future<MailStoredFlagBatch> _reconcileMembershipBatch(
  SqliteStudioMailFlagJournalStore store, {
  required String id,
  required int expectedRevision,
  required MailAccountId sourceAccount,
  required MailProviderKind provider,
  required MailMembershipObserver observer,
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
    var batch = await load();
    if (!batch.summary.canCheckMembership) {
      throw const StudioMailFlagJournalException(MailProblemCode.unsupported);
    }
    if (batch.summary.revision != expectedRevision ||
        batch.summary.uncertainCount == 0) {
      throw const StudioMailFlagJournalException(MailProblemCode.conflict);
    }
    final localLease = localSession.begin(cancellation: cancellation);
    final sourceLease = sourceSession.begin(cancellation: cancellation);
    for (var index = 0; index < batch.report.items.length; index++) {
      if (batch.report.items[index].outcome != MailBulkFlagOutcome.uncertain) {
        continue;
      }
      check();
      final handle = await store._serialize(() async {
        check();
        return SqliteStudioMailFlagJournalStore._value(
          await store._repository.beginMembershipReconciliation(
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
      final observed = await _observeMembershipStatus(
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
      final local = _membershipForAccount(observed, handle.message);
      await store._serialize(() async {
        check();
        SqliteStudioMailFlagJournalStore._value(
          await store._repository.recordMembershipObservation(
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
