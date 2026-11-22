part of 'repository.dart';

/// Authority for one explicit read-only check of one historical uncertain item.
/// It cannot dispatch the original command or authorize a different identity.
final class MailFlagReconciliationHandle {
  MailFlagReconciliationHandle._(
    this.account,
    this.id,
    this.index,
    this.message,
    this._owner,
    this._revision,
    this._epoch,
    this._startedAt,
    this._lease,
    this._isCurrent,
  );

  final MailAccountId account;
  final String id;
  final int index;
  final MailRemoteIdentity message;
  final Object _owner;
  final int _revision;
  final int _epoch;
  final int _startedAt;
  final MailOperationLease _lease;
  final bool Function()? _isCurrent;
}

extension MailFlagReconciliation on SqliteMailRepository {
  void _checkObservationScope(
    MailOperationLease lease,
    bool Function()? isCurrent,
  ) {
    if (_closed) SqliteMailRepository._fail(MailProblemCode.unavailable);
    lease.checkCurrent();
    if (isCurrent != null && !isCurrent()) {
      SqliteMailRepository._fail(MailProblemCode.staleOperation);
    }
  }

  Future<int> _flagObservationEpoch() async {
    final epoch = (await _rows(
      'SELECT flag_observation_epoch FROM store_profile',
    )).single.read<int>('flag_observation_epoch');
    if (epoch < 0 || epoch > MailFlagCommandJournal._maxFlagRevision) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return epoch;
  }

  Future<MailStoredFlagBatch> _unresolvedFlagBatch(
    MailAccountId account,
    String id,
    int index,
    int expectedRevision,
  ) async {
    final loaded = await loadFlagBatch(account, id);
    final batch = switch (loaded) {
      MailSuccess<MailStoredFlagBatch?>(:final value) => value,
      MailFailure<MailStoredFlagBatch?>(:final problem) =>
        throw MailStoreStorageException(problem.code),
    };
    if (batch == null ||
        !batch.summary.complete ||
        batch.summary.revision != expectedRevision ||
        expectedRevision < 1 ||
        expectedRevision >= MailFlagCommandJournal._maxFlagRevision ||
        index < 0 ||
        index >= batch.report.results.length ||
        batch.report.results[index].outcome != MailBulkFlagOutcome.uncertain ||
        batch.resolutions.any((resolution) => resolution.index == index)) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (!batch.summary.canCheckFlags) {
      // A flag read cannot establish a move's destination or the provider's
      // delete semantics. Retain the original uncertainty until a dedicated
      // membership-observation workflow is implemented.
      SqliteMailRepository._fail(MailProblemCode.unsupported);
    }
    return batch;
  }

  /// Captures authority before the host performs a fresh provider observation.
  /// No provider write, replay, draft, payload or cache eviction is performed.
  /// Move/delete receipts are unsupported and remain unresolved.
  Future<MailResult<MailFlagReconciliationHandle>> beginFlagReconciliation(
    MailAccountId account,
    String id,
    int index, {
    required int expectedRevision,
    required MailOperationLease lease,
    bool Function()? isCurrent,
  }) => _run(
    () => _db.transaction(() async {
      _checkObservationScope(lease, isCurrent);
      if (lease.account != account) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final accountRow = await _account(account, active: true);
      _checkObservationScope(lease, isCurrent);
      final batch = await _unresolvedFlagBatch(
        account,
        id,
        index,
        expectedRevision,
      );
      _checkObservationScope(lease, isCurrent);
      if (accountRow.read<String>('provider') != batch.summary.provider.name) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final epoch = await _flagObservationEpoch();
      _checkObservationScope(lease, isCurrent);
      final now = _flagNow();
      if (now < batch.summary.updatedAt.millisecondsSinceEpoch) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      return MailFlagReconciliationHandle._(
        account,
        id,
        index,
        batch.report.plan.messages[index],
        _flagJournalOwner,
        expectedRevision,
        epoch,
        now,
        lease,
        isCurrent,
      );
    }),
  );

  /// Records a current exact-identity observation without rewriting the receipt.
  /// Only its requested bit may update an existing known cache snapshot. Missing
  /// messages or replaced IMAP generations leave the cached message untouched.
  Future<MailResult<MailUnit>> recordFlagObservation(
    MailFlagReconciliationHandle handle,
    MailFlagObservation observation, {
    required MailOperationLease lease,
    bool Function()? isCurrent,
  }) => _run(
    () => _commit(() async {
      void guard() {
        _checkObservationScope(handle._lease, handle._isCurrent);
        _checkObservationScope(lease, isCurrent);
        if (!identical(handle._owner, _flagJournalOwner) ||
            !identical(handle._lease, lease)) {
          SqliteMailRepository._fail(MailProblemCode.conflict);
        }
      }

      guard();
      if (lease.account != handle.account ||
          observation.identity != handle.message) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final accountRow = await _account(handle.account, active: true);
      guard();
      final batch = await _unresolvedFlagBatch(
        handle.account,
        handle.id,
        handle.index,
        handle._revision,
      );
      guard();
      if (accountRow.read<String>('provider') != batch.summary.provider.name ||
          batch.report.plan.messages[handle.index] != handle.message) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final epoch = await _flagObservationEpoch();
      guard();
      if (epoch != handle._epoch) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final now = _flagNow();
      if (now < handle._startedAt ||
          now < batch.summary.updatedAt.millisecondsSinceEpoch) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final original = batch.report.plan.operationAt(handle.index);
      final MailFlagResolutionKind kind;
      MailOperation? projection;
      switch (observation.kind) {
        case MailFlagObservationKind.present:
          final flags = observation.flags;
          if (flags == null) {
            SqliteMailRepository._fail(MailProblemCode.invalidInput);
          }
          final (requested, observed) = switch (original) {
            MailSetRead(:final read) => (read, flags.isRead),
            MailSetFlagged(:final flagged) => (flagged, flags.isFlagged),
            _ => throw const MailStoreStorageException(
              MailProblemCode.invalidInput,
            ),
          };
          kind = requested == observed
              ? MailFlagResolutionKind.matches
              : MailFlagResolutionKind.differs;
          projection = switch (original) {
            MailSetRead() => MailSetRead(
              id: original.id,
              message: handle.message,
              read: observed,
            ),
            MailSetFlagged() => MailSetFlagged(
              id: original.id,
              message: handle.message,
              flagged: observed,
            ),
            _ => null,
          };
        case MailFlagObservationKind.missing:
          kind = MailFlagResolutionKind.missing;
        case MailFlagObservationKind.identityChanged:
          if (handle.message is! MailImapIdentity) {
            SqliteMailRepository._fail(MailProblemCode.invalidInput);
          }
          kind = MailFlagResolutionKind.identityChanged;
      }
      await _db.customStatement(
        'INSERT INTO flag_item_resolutions(account,batch,position,kind,checked_at) VALUES(?,?,?,?,?)',
        [handle.account.value, handle.id, handle.index, kind.name, now],
      );
      guard();
      await _db.customStatement(
        'UPDATE flag_batches SET revision=?,updated_at=? WHERE account=? AND id=?',
        [handle._revision + 1, now, handle.account.value, handle.id],
      );
      guard();
      if (projection != null) {
        await _projectFlagConfirmation(projection);
        guard();
      }
      await _pruneCleanFlagBatches(handle.account, preserving: handle.id);
      guard();
      await _quota(handle.account);
      guard();
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      guard();
      return MailUnit.value;
    }),
  );
}
