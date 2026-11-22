part of 'repository.dart';

/// One explicit read-only check of an uncertain membership command. The
/// original repository owner, lease, revision and persisted epoch fence it.
final class MailMembershipReconciliationHandle {
  MailMembershipReconciliationHandle._(
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

extension MailMembershipReconciliation on SqliteMailRepository {
  Future<void> _checkMembershipObservations(MailAccountId account) async {
    // Bound and validate SQL fields before transferring provider metadata. This
    // check reads no message bodies and does not turn evidence into resolution.
    final invalid = (await _rows(
      'SELECT count(*) AS n FROM membership_item_observations o '
      'LEFT JOIN flag_batches b ON b.account=o.account AND b.id=o.batch '
      'LEFT JOIN flag_batch_items i ON i.account=o.account AND i.batch=o.batch AND i.position=o.position '
      'WHERE o.account=? AND ('
      "typeof(o.batch)!='text' OR length(CAST(o.batch AS BLOB)) NOT BETWEEN 1 AND 1024 OR "
      "typeof(o.position)!='integer' OR o.position NOT BETWEEN 0 AND 999 OR "
      "typeof(o.kind)!='text' OR o.kind NOT IN ('present','missing','identityChanged') OR "
      "typeof(o.mailboxes)!='text' OR length(CAST(o.mailboxes AS BLOB)) NOT BETWEEN 2 AND 262144 OR "
      "(o.deletion_mailbox IS NOT NULL AND (typeof(o.deletion_mailbox)!='text' OR "
      'length(CAST(o.deletion_mailbox AS BLOB)) NOT BETWEEN 1 AND 8192)) OR '
      "(o.is_deleted IS NOT NULL AND (typeof(o.is_deleted)!='integer' OR o.is_deleted NOT IN (0,1))) OR "
      "(o.kind!='present' AND (o.mailboxes!='[]' OR o.deletion_mailbox IS NOT NULL OR o.is_deleted IS NOT NULL)) OR "
      "typeof(o.checked_at)!='integer' OR o.checked_at NOT BETWEEN 0 AND 8640000000000000 OR "
      'b.id IS NULL OR i.position IS NULL OR b.complete!=1 OR '
      "b.action NOT IN ('move','delete','archive') OR i.state!='uncertain' OR "
      "(o.kind='identityChanged' AND b.provider!='imap') OR "
      'o.checked_at<b.created_at OR o.checked_at>b.updated_at)',
      [account.value],
    )).single.read<int>('n');
    if (invalid != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final oversized = await _rows(
      'SELECT 1 AS invalid FROM membership_item_observations WHERE account=? '
      'GROUP BY batch HAVING sum(length(CAST(mailboxes AS BLOB))+'
      'coalesce(length(CAST(deletion_mailbox AS BLOB)),0))>? LIMIT 1',
      [account.value, _flagMetadataLimit * 4],
    );
    if (oversized.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
  }

  MailMembershipObservation _decodeMembershipObservation(
    QueryRow row,
    MailRemoteIdentity identity,
  ) {
    try {
      final kind = MailMembershipObservationKind.values.byName(
        row.read<String>('kind'),
      );
      final Object? decoded = jsonDecode(row.read<String>('mailboxes'));
      if (decoded is! List<Object?> ||
          decoded.length > MailMembershipObservation.maxMailboxes ||
          decoded.any((value) => value is! String)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      final mailboxes = [
        for (final value in decoded)
          MailMailboxId(value! as String, account: identity.account),
      ];
      final deletionValue = row.readNullable<String>('deletion_mailbox');
      final deleted = row.readNullable<int>('is_deleted');
      if (kind != MailMembershipObservationKind.present) {
        if (mailboxes.isNotEmpty || deletionValue != null || deleted != null) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
        if (kind == MailMembershipObservationKind.missing) {
          return MailMembershipObservation.missing(identity: identity);
        }
        if (identity is! MailImapIdentity) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
        return MailMembershipObservation.identityChanged(identity: identity);
      }
      final MailMembershipObservation observation;
      switch (identity) {
        case MailImapIdentity():
          if (mailboxes.length != 1 ||
              mailboxes.single != identity.mailbox ||
              deletionValue != null ||
              deleted == null) {
            SqliteMailRepository._fail(MailProblemCode.storageFailure);
          }
          observation = MailMembershipObservation.imap(
            identity: identity,
            isDeleted: deleted == 1,
          );
        case MailOpaqueIdentity():
          observation = MailMembershipObservation.folders(
            identity: identity,
            mailboxes: mailboxes,
            deletionMailbox: deletionValue == null
                ? null
                : MailMailboxId(deletionValue, account: identity.account),
          );
      }
      if (observation.isDeleted != (deleted == null ? null : deleted == 1)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      return observation;
    } on Object {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
  }

  Future<List<MailStoredMembershipObservation>> _loadMembershipObservations(
    MailAccountId account,
    String id,
    MailBulkFlagPlan plan,
  ) async {
    final result = <MailStoredMembershipObservation>[];
    var units = 0;
    for (final row in await _rows(
      'SELECT position,kind,mailboxes,deletion_mailbox,is_deleted,checked_at '
      'FROM membership_item_observations WHERE account=? AND batch=? ORDER BY position',
      [account.value, id],
    )) {
      units += row.read<String>('mailboxes').length;
      units += row.readNullable<String>('deletion_mailbox')?.length ?? 0;
      if (units > _flagMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final index = row.read<int>('position');
      if (index < 0 || index >= plan.messages.length) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      result.add(
        MailStoredMembershipObservation(
          index: index,
          observation: _decodeMembershipObservation(row, plan.messages[index]),
          checkedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('checked_at'),
            isUtc: true,
          ),
        ),
      );
    }
    return result;
  }

  Future<MailStoredFlagBatch> _unresolvedMembershipBatch(
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
        batch.report.results[index].outcome != MailBulkFlagOutcome.uncertain) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (!batch.summary.canCheckMembership) {
      SqliteMailRepository._fail(MailProblemCode.unsupported);
    }
    return batch;
  }

  /// Capture authority before an explicit exact-identity provider read. Existing
  /// evidence can be refreshed; neither observation nor restart replays work.
  Future<MailResult<MailMembershipReconciliationHandle>>
  beginMembershipReconciliation(
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
      final batch = await _unresolvedMembershipBatch(
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
      return MailMembershipReconciliationHandle._(
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

  /// Atomically replace only the latest current-location evidence. The original
  /// receipt, uncertainty count and cleanup protection remain unchanged. This
  /// does not alter cached headers, memberships, bodies, drafts or sync cursors;
  /// those remain dated observations until explicit refresh/synchronization.
  Future<MailResult<MailUnit>> recordMembershipObservation(
    MailMembershipReconciliationHandle handle,
    MailMembershipObservation observation, {
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
      final batch = await _unresolvedMembershipBatch(
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
      final mailboxes = jsonEncode([
        for (final mailbox in observation.mailboxes) mailbox.value,
      ]);
      final deletion = observation.deletionMailbox?.value;
      var remaining = 0;
      for (final saved in batch.membershipObservations) {
        if (saved.index == handle.index) continue;
        remaining += jsonEncode([
          for (final mailbox in saved.observation.mailboxes) mailbox.value,
        ]).length;
        remaining += saved.observation.deletionMailbox?.value.length ?? 0;
      }
      if (remaining + mailboxes.length + (deletion?.length ?? 0) >
          _flagMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      await _db.customStatement(
        'INSERT INTO membership_item_observations'
        '(account,batch,position,kind,mailboxes,deletion_mailbox,is_deleted,checked_at) '
        'VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(account,batch,position) DO UPDATE SET '
        'kind=excluded.kind,mailboxes=excluded.mailboxes,deletion_mailbox=excluded.deletion_mailbox,'
        'is_deleted=excluded.is_deleted,checked_at=excluded.checked_at',
        [
          handle.account.value,
          handle.id,
          handle.index,
          observation.kind.name,
          mailboxes,
          deletion,
          switch (observation.isDeleted) {
            true => 1,
            false => 0,
            null => null,
          },
          now,
        ],
      );
      guard();
      await _db.customStatement(
        'UPDATE flag_batches SET revision=?,updated_at=? WHERE account=? AND id=?',
        [handle._revision + 1, now, handle.account.value, handle.id],
      );
      guard();
      await _quota(handle.account);
      guard();
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      guard();
      return MailUnit.value;
    }),
  );
}
