part of 'repository.dart';

/// An opaque capability for one batch created by this repository owner.
/// Reopening storage, logging out, or finishing the batch retires its authority.
final class MailFlagBatchHandle {
  MailFlagBatchHandle._(this.account, this.id, this._owner);
  final MailAccountId account;
  final String id;
  final Object _owner;
  int _revision = 1;
  bool _complete = false;
  final Map<int, int> _moveProjectionEpochs = {};
}

/// Durable evidence for foreground commands. There is deliberately no method
/// to resume a stored batch or turn an uncertain result back into queued work.
extension MailFlagCommandJournal on SqliteMailRepository {
  static const maxRetainedCleanFlagBatches = 100;
  static const maxUnresolvedFlagBatches = 100;
  static const maxStoredFlagBatches = 200;
  static const _maxFlagRevision = 9007199254740991;
  static const _maxFlagTime = 8640000000000000;

  int get _flagMetadataLimit => limits.maxMetadataCodeUnits < 2 * 1024 * 1024
      ? limits.maxMetadataCodeUnits
      : 2 * 1024 * 1024;

  int _flagNow() {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    if (now < 0 || now > _maxFlagTime) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    return now;
  }

  static const _cleanFlagBatch =
      'b.complete=1 AND NOT EXISTS (SELECT 1 FROM flag_batch_items i '
      'WHERE i.account=b.account AND i.batch=b.id AND '
      "(i.state='applying' OR (i.state='uncertain' AND NOT EXISTS "
      '(SELECT 1 FROM flag_item_resolutions r WHERE r.account=i.account '
      'AND r.batch=i.batch AND r.position=i.position))))';

  Future<void> _pruneCleanFlagBatches(
    MailAccountId account, {
    String? preserving,
  }) async {
    await _db.customStatement(
      'DELETE FROM flag_batches WHERE account=? AND id IN '
      '(SELECT b.id FROM flag_batches b WHERE b.account=? AND $_cleanFlagBatch '
      '${preserving == null ? '' : 'AND b.id!=? '}'
      'ORDER BY b.rowid DESC LIMIT -1 OFFSET ?)',
      [
        account.value,
        account.value,
        ?preserving,
        maxRetainedCleanFlagBatches - (preserving == null ? 0 : 1),
      ],
    );
  }

  Future<void> _checkFlagBatches(MailAccountId account) async {
    final count = (await _rows(
      'SELECT count(*) AS n FROM flag_batches WHERE account=?',
      [account.value],
    )).single.read<int>('n');
    if (count > maxStoredFlagBatches) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final invalid = (await _rows(
      'SELECT count(*) AS n FROM flag_batches b WHERE b.account=? AND ('
      "typeof(b.id)!='text' OR length(CAST(b.id AS BLOB))>1024 OR "
      "typeof(b.mailbox)!='text' OR length(CAST(b.mailbox AS BLOB))>4096 OR "
      "b.provider NOT IN ('imap','ews','gmail','graph') OR "
      "b.action NOT IN ('markRead','markUnread','flag','unflag','move','delete') OR "
      "(b.action='move' AND (b.destination IS NULL OR typeof(b.destination)!='text' OR "
      'length(CAST(b.destination AS BLOB)) NOT BETWEEN 1 AND 4096 OR b.destination=b.mailbox)) OR '
      "(b.action!='move' AND b.destination IS NOT NULL) OR "
      "typeof(b.revision)!='integer' OR b.revision<1 OR b.revision>9007199254740991 OR "
      "typeof(b.created_at)!='integer' OR b.created_at<0 OR b.created_at>8640000000000000 OR "
      "typeof(b.updated_at)!='integer' OR b.updated_at<0 OR b.updated_at>8640000000000000 OR "
      "typeof(b.complete)!='integer' OR b.complete NOT IN (0,1) OR "
      "typeof(b.interrupted)!='integer' OR b.interrupted NOT IN (0,1) OR "
      "(b.stop_reason IS NOT NULL AND (typeof(b.stop_reason)!='text' OR length(CAST(b.stop_reason AS BLOB))>64)) OR "
      "(b.problem_code IS NOT NULL AND (typeof(b.problem_code)!='text' OR length(CAST(b.problem_code AS BLOB))>64)) OR "
      "(b.persistence_problem IS NOT NULL AND (typeof(b.persistence_problem)!='text' OR length(CAST(b.persistence_problem AS BLOB))>64)) OR "
      "(b.retry_after_us IS NOT NULL AND (typeof(b.retry_after_us)!='integer' OR b.retry_after_us<0 OR b.retry_after_us>9007199254740991)) OR "
      "(b.mutation_possible IS NOT NULL AND (typeof(b.mutation_possible)!='integer' OR b.mutation_possible NOT IN (0,1))) OR "
      "typeof(b.item_count)!='integer' OR b.item_count<1 OR b.item_count>1000 OR "
      'b.item_count!=(SELECT count(*) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id) OR '
      '(SELECT min(position) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id)!=0 OR '
      '(SELECT max(position) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id)!=b.item_count-1 OR '
      "EXISTS (SELECT 1 FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state NOT IN ('unattempted','applying','confirmed','failed','uncertain')) OR "
      "(SELECT count(*) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='applying')>1 OR "
      "(b.complete=1 AND EXISTS (SELECT 1 FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='applying'))) ",
      [account.value],
    )).single.read<int>('n');
    if (invalid != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    // SQL bounds the text before transfer. Typed validation also rejects
    // controls and oversized code-unit identities before cleanup or dispatch.
    for (final row in await _rows(
      'SELECT action,mailbox,destination FROM flag_batches WHERE account=?',
      [account.value],
    )) {
      _flagDestination(row, account);
    }
    final invalidResolutions = (await _rows(
      'SELECT count(*) AS n FROM flag_item_resolutions r '
      'LEFT JOIN flag_batches b ON b.account=r.account AND b.id=r.batch '
      'LEFT JOIN flag_batch_items i ON i.account=r.account AND i.batch=r.batch AND i.position=r.position '
      'WHERE r.account=? AND ('
      "typeof(r.batch)!='text' OR length(CAST(r.batch AS BLOB))>1024 OR "
      "typeof(r.position)!='integer' OR r.position<0 OR r.position>999 OR "
      "typeof(r.kind)!='text' OR r.kind NOT IN ('matches','differs','missing','identityChanged') OR "
      "typeof(r.checked_at)!='integer' OR r.checked_at<0 OR r.checked_at>8640000000000000 OR "
      'b.id IS NULL OR i.position IS NULL OR b.complete!=1 OR '
      "b.action NOT IN ('markRead','markUnread','flag','unflag') OR "
      "i.state!='uncertain' OR (r.kind='identityChanged' AND b.provider!='imap') OR "
      'r.checked_at<b.created_at OR r.checked_at>b.updated_at)',
      [account.value],
    )).single.read<int>('n');
    if (invalidResolutions != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    await _checkMembershipObservations(account);
    await _checkMoveIdentityTransitions(account);
  }

  /// Saves the complete frozen selection atomically before any dispatch marker.
  /// Typed outcome space is reserved in the logical quota at creation.
  Future<MailResult<MailFlagBatchHandle>> createFlagBatch(
    MailBulkFlagPlan plan, {
    required List<String> subjects,
    required MailOperationLease lease,
  }) {
    final frozenSubjects = List<String>.unmodifiable(subjects);
    return _run(
      () => _commit(() async {
        final account = plan.mailbox.account;
        final accountRow = await _account(account, active: true);
        if (lease.account != account ||
            accountRow.read<String>('provider') != plan.provider.name ||
            frozenSubjects.length != plan.messages.length ||
            plan.messages.length > limits.maxPageSize) {
          SqliteMailRepository._fail(MailProblemCode.invalidInput);
        }
        if (plan.provider == MailProviderKind.jmap) {
          SqliteMailRepository._fail(MailProblemCode.unsupported);
        }
        lease.checkCurrent();
        _id(plan.id);
        _id(plan.mailbox.value);
        final destination = plan.destination?.value;
        if (destination != null) _id(destination);
        var units =
            plan.id.length +
            plan.mailbox.value.length +
            (destination?.length ?? 0);
        final remotes = <String>[];
        for (var i = 0; i < plan.messages.length; i++) {
          final remote = _remoteKey(plan.messages[i]);
          if (frozenSubjects[i].length > 4096) {
            SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
          }
          remotes.add(remote);
          units += remote.length + frozenSubjects[i].length;
        }
        if (units > _flagMetadataLimit) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        await _checkFlagBatches(account);
        final unresolved = (await _rows(
          'SELECT count(*) AS n FROM flag_batches b WHERE b.account=? AND NOT ($_cleanFlagBatch)',
          [account.value],
        )).single.read<int>('n');
        if (unresolved >= maxUnresolvedFlagBatches) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        await _pruneCleanFlagBatches(account);
        final now = _flagNow();
        await _db.customStatement(
          'INSERT INTO flag_batches(account,id,mailbox,provider,action,destination,created_at,updated_at,revision,complete,interrupted,item_count) '
          'VALUES(?,?,?,?,?,?,?,?,1,0,0,?)',
          [
            account.value,
            plan.id,
            plan.mailbox.value,
            plan.provider.name,
            plan.action.name,
            destination,
            now,
            now,
            plan.messages.length,
          ],
        );
        for (var i = 0; i < remotes.length; i++) {
          await _db.customStatement(
            'INSERT INTO flag_batch_items(account,batch,position,remote,subject,state) '
            "VALUES(?,?,?,?,?,'unattempted')",
            [account.value, plan.id, i, remotes[i], frozenSubjects[i]],
          );
        }
        await _quota(account);
        await _db.fault(MailStoreCheckpoint.beforeCommit);
        lease.checkCurrent();
        return MailFlagBatchHandle._(account, plan.id, _flagJournalOwner);
      }),
    );
  }

  Future<MailResult<MailUnit>> _flagMutation(
    MailFlagBatchHandle handle,
    Future<void> Function(QueryRow batch) body, {
    MailOperationLease? lease,
    bool complete = false,
    int? captureMoveProjection,
  }) async {
    int? projectionEpoch;
    final expected = handle._revision;
    final result = await _run(
      () => _commit(() async {
        if (!identical(handle._owner, _flagJournalOwner) || handle._complete) {
          SqliteMailRepository._fail(MailProblemCode.conflict);
        }
        await _account(handle.account, active: true);
        if (lease != null && lease.account != handle.account) {
          SqliteMailRepository._fail(MailProblemCode.invalidInput);
        }
        lease?.checkCurrent();
        await _checkFlagBatches(handle.account);
        final rows = await _rows(
          'SELECT * FROM flag_batches WHERE account=? AND id=?',
          [handle.account.value, handle.id],
        );
        if (rows.isEmpty ||
            rows.single.read<int>('complete') != 0 ||
            rows.single.read<int>('revision') != expected ||
            expected >= _maxFlagRevision) {
          SqliteMailRepository._fail(MailProblemCode.conflict);
        }
        _flagDestination(rows.single, handle.account);
        await body(rows.single);
        final now = _flagNow();
        final latestTransition = (await _rows(
          'SELECT max(recorded_at) AS newest FROM move_identity_transitions '
          'WHERE account=? AND batch=?',
          [handle.account.value, handle.id],
        )).single.readNullable<int>('newest');
        // A wall-clock correction between receipt capture and this final write
        // must roll back the entire settlement, not persist an unreadable date.
        if (now < rows.single.read<int>('created_at') ||
            now < rows.single.read<int>('updated_at') ||
            latestTransition != null && now < latestTransition) {
          SqliteMailRepository._fail(MailProblemCode.conflict);
        }
        await _db.customStatement(
          'UPDATE flag_batches SET revision=?,updated_at=? WHERE account=? AND id=?',
          [expected + 1, now, handle.account.value, handle.id],
        );
        await _quota(handle.account);
        await _db.fault(MailStoreCheckpoint.beforeCommit);
        lease?.checkCurrent();
        if (captureMoveProjection != null) {
          projectionEpoch = await _flagObservationEpoch();
        }
        return MailUnit.value;
      }),
    );
    if (result is MailSuccess<MailUnit>) {
      handle._revision = expected + 1;
      handle._complete = complete;
      if (projectionEpoch != null) {
        handle._moveProjectionEpochs[captureMoveProjection!] = projectionEpoch!;
      }
    }
    return result;
  }

  /// An acknowledged applying marker is mandatory before calling a provider.
  /// At most one item is in flight, and skipped/uncertain work cannot be replayed.
  Future<MailResult<MailUnit>> beginFlagAttempt(
    MailFlagBatchHandle handle,
    int index, {
    required MailOperationLease lease,
  }) => _flagMutation(
    handle,
    (batch) async {
      if (index < 0 || index >= batch.read<int>('item_count')) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final blocked = (await _rows(
        'SELECT count(*) AS n FROM flag_batch_items WHERE account=? AND batch=? AND '
        "(state IN ('applying','uncertain') OR (position<? AND state='unattempted') OR "
        "(state='failed' AND problem_code IN ('cancelled','staleOperation','quotaExceeded')))",
        [handle.account.value, handle.id, index],
      )).single.read<int>('n');
      final item = (await _rows(
        'SELECT state FROM flag_batch_items WHERE account=? AND batch=? AND position=?',
        [handle.account.value, handle.id, index],
      )).single;
      if (blocked != 0 || item.read<String>('state') != 'unattempted') {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      await _db.customStatement(
        "UPDATE flag_batch_items SET state='applying' WHERE account=? AND batch=? AND position=?",
        [handle.account.value, handle.id, index],
      );
    },
    lease: lease,
    captureMoveProjection: index,
  );

  MailOperation _flagOperation(
    QueryRow batch,
    QueryRow item,
    MailAccountId account,
  ) {
    final action = MailBulkFlagAction.values.byName(
      batch.read<String>('action'),
    );
    final remote = MailStoreCodec.decodeRemote(
      item.read<String>('remote'),
      account: account,
    );
    final id = '${batch.read<String>('id')}:${item.read<int>('position')}';
    return switch (action) {
      MailBulkFlagAction.markRead ||
      MailBulkFlagAction.markUnread => MailSetRead(
        id: id,
        message: remote,
        read: action == MailBulkFlagAction.markRead,
      ),
      MailBulkFlagAction.flag || MailBulkFlagAction.unflag => MailSetFlagged(
        id: id,
        message: remote,
        flagged: action == MailBulkFlagAction.flag,
      ),
      MailBulkFlagAction.move => MailMove(
        id: id,
        message: remote,
        destination: _flagDestination(batch, account)!,
      ),
      MailBulkFlagAction.delete => MailDelete(id: id, message: remote),
    };
  }

  bool _sameFlagOperation(MailOperation a, MailOperation b) =>
      a.id == b.id &&
      a.message == b.message &&
      switch ((a, b)) {
        (final MailSetRead a, final MailSetRead b) => a.read == b.read,
        (final MailSetFlagged a, final MailSetFlagged b) =>
          a.flagged == b.flagged,
        (final MailMove a, final MailMove b) => a.destination == b.destination,
        (MailDelete(), MailDelete()) => true,
        _ => false,
      };

  MailMailboxId? _flagDestination(QueryRow batch, MailAccountId account) {
    final action = batch.read<String>('action');
    final destination = batch.readNullable<String>('destination');
    if (!MailBulkFlagAction.values.any((value) => value.name == action) ||
        (action == MailBulkFlagAction.move.name) != (destination != null) ||
        (destination != null &&
            (destination.isEmpty ||
                destination.length > 1024 ||
                destination.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
                destination == batch.read<String>('mailbox')))) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return destination == null
        ? null
        : MailMailboxId(destination, account: account);
  }

  List<Object?> _flagProblem(MailProblem? problem) {
    final retry = problem?.retryAfter?.inMicroseconds;
    if (retry != null && (retry < 0 || retry > _maxFlagRevision)) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    return [
      problem?.code.name,
      retry,
      switch (problem?.mutationMayHaveOccurred) {
        true => 1,
        false => 0,
        null => null,
      },
    ];
  }

  MailProblem? _readFlagProblem(QueryRow row) {
    final code = row.readNullable<String>('problem_code');
    final retry = row.readNullable<int>('retry_after_us');
    final mutation = row.readNullable<int>('mutation_possible');
    if ((retry != null && (retry < 0 || retry > _maxFlagRevision)) ||
        (mutation != null && mutation != 0 && mutation != 1) ||
        (code == null && (retry != null || mutation != null))) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return code == null
        ? null
        : MailProblem(
            MailProblemCode.values.byName(code),
            retryAfter: retry == null ? null : Duration(microseconds: retry),
            mutationMayHaveOccurred: mutation == null ? null : mutation == 1,
          );
  }

  bool _sameFlagProblem(MailProblem? a, MailProblem? b) =>
      a?.code == b?.code &&
      a?.retryAfter == b?.retryAfter &&
      a?.mutationMayHaveOccurred == b?.mutationMayHaveOccurred;

  Future<void> _writeFlagResult(
    MailFlagBatchHandle handle,
    QueryRow batch,
    QueryRow item,
    MailBulkFlagItemResult result, {
    bool finishing = false,
  }) async {
    final expected = _flagOperation(batch, item, handle.account);
    MailBulkFlagItemResult.restore(
      operation: result.operation,
      outcome: result.outcome,
      problem: result.problem,
      identityTransition: result.identityTransition,
    );
    if (result.identityTransition case final transition?) {
      if (!transition.matches(
        expected,
        sourceMailbox: MailMailboxId(
          batch.read<String>('mailbox'),
          account: handle.account,
        ),
      )) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
    }
    if (!_sameFlagOperation(expected, result.operation)) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    final state = item.read<String>('state');
    if (state != 'applying') {
      if (finishing &&
          state == result.outcome.name &&
          _sameFlagProblem(_readFlagProblem(item), result.problem)) {
        final stored = await _loadMoveIdentityTransition(
          handle.account,
          batch,
          item,
        );
        if (stored?.transition != result.identityTransition) {
          SqliteMailRepository._fail(MailProblemCode.conflict);
        }
        return;
      }
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (!finishing && result.outcome == MailBulkFlagOutcome.unattempted) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    final canProjectMove =
        result.identityTransition != null &&
        handle._moveProjectionEpochs[item.read<int>('position')] ==
            await _flagObservationEpoch();
    await _db.customStatement(
      'UPDATE flag_batch_items SET state=?,problem_code=?,retry_after_us=?,mutation_possible=? '
      'WHERE account=? AND batch=? AND position=?',
      [
        result.outcome.name,
        ..._flagProblem(result.problem),
        handle.account.value,
        handle.id,
        item.read<int>('position'),
      ],
    );
    if (result.outcome == MailBulkFlagOutcome.confirmed) {
      await _projectFlagConfirmation(expected);
      if (result.identityTransition case final transition?) {
        await _writeMoveIdentityTransition(
          handle.account,
          batch,
          item,
          transition,
          canProject: canProjectMove,
        );
      }
    }
  }

  /// Atomically retains provider evidence and patches only confirmed flag bits.
  /// Membership unit acknowledgements retain dated cache observations. Exact
  /// move mappings are stored with the reply and project only when the original
  /// dispatch fence still holds and both retained folders can be reconciled.
  /// A retired view lease does not discard an already settled provider reply.
  Future<MailResult<MailUnit>> recordFlagResult(
    MailFlagBatchHandle handle,
    int index,
    MailBulkFlagItemResult result,
  ) => _flagMutation(handle, (batch) async {
    final rows = await _rows(
      'SELECT * FROM flag_batch_items WHERE account=? AND batch=? AND position=?',
      [handle.account.value, handle.id, index],
    );
    if (rows.isEmpty) SqliteMailRepository._fail(MailProblemCode.invalidInput);
    await _writeFlagResult(handle, batch, rows.single, result);
  });

  Future<void> _projectFlagConfirmation(MailOperation operation) async {
    if (operation is MailMove || operation is MailDelete) return;
    final (bit, enabled) = switch (operation) {
      MailSetRead(:final read) => (1, read),
      MailSetFlagged(:final flagged) => (2, flagged),
      _ => throw const MailStoreStorageException(MailProblemCode.invalidInput),
    };
    final account = operation.message.account;
    final remote = _remoteKey(operation.message);
    // Null is a wholly unknown observation, not an empty flag set. A single
    // confirmed flag cannot make the other four unknown values authoritative.
    final rows = await _rows(
      'SELECT id,flags FROM messages WHERE account=? AND remote=?',
      [account.value, remote],
    );
    if (rows.isEmpty) return;
    final id = rows.single.read<String>('id');
    final old = rows.single.readNullable<int>('flags');
    if (old != null) {
      MailStoreCodec.decodeFlags(old);
      final updated = enabled ? old | bit : old & ~bit;
      if (updated != old) {
        await _db.customStatement(
          'UPDATE messages SET flags=? WHERE account=? AND id=? AND remote=?',
          [updated, account.value, id, remote],
        );
      }
    }
    final affected = await _rows(
      'SELECT mailbox FROM mailbox_view_members WHERE account=? AND message=?',
      [account.value, id],
    );
    if (affected.isEmpty) return;
    final counter = (await _rows(
      'SELECT mailbox_view_revision FROM store_profile',
    )).single.read<int>('mailbox_view_revision');
    if (counter < 0 || counter >= _maxFlagRevision) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    await _db.customStatement(
      'UPDATE store_profile SET mailbox_view_revision=?',
      [counter + 1],
    );
    for (final view in affected) {
      // The original capture time/completeness are preserved. Only the CAS
      // revision changes, rejecting a stale cached-view writer even when the
      // snapshot is unknown or its target bit already matches the confirmation.
      await _db.customStatement(
        'UPDATE mailbox_views SET revision=? WHERE account=? AND mailbox=?',
        [counter + 1, account.value, view.read<String>('mailbox')],
      );
    }
  }

  /// Finalizes the known outcomes and the untouched tail in one transaction.
  /// If an earlier result write failed, a still-applying marker may be settled
  /// once by its original live owner. A reopened owner cannot obtain a handle.
  Future<MailResult<MailUnit>> finishFlagBatch(
    MailFlagBatchHandle handle,
    MailBulkFlagReport report,
  ) => _flagMutation(handle, (batch) async {
    if (report.plan.id != handle.id ||
        report.plan.mailbox.account != handle.account ||
        report.plan.mailbox.value != batch.read<String>('mailbox') ||
        report.plan.provider.name != batch.read<String>('provider') ||
        report.plan.action.name != batch.read<String>('action') ||
        report.plan.destination != _flagDestination(batch, handle.account) ||
        report.results.length != batch.read<int>('item_count')) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    final items = await _rows(
      'SELECT * FROM flag_batch_items WHERE account=? AND batch=? ORDER BY position',
      [handle.account.value, handle.id],
    );
    for (var i = 0; i < items.length; i++) {
      await _writeFlagResult(
        handle,
        batch,
        items[i],
        report.results[i],
        finishing: true,
      );
    }
    await _db.customStatement(
      'UPDATE flag_batches SET complete=1,stop_reason=?,problem_code=?,retry_after_us=?,mutation_possible=?,persistence_problem=? '
      'WHERE account=? AND id=?',
      [
        report.stopReason?.name,
        ..._flagProblem(report.stopProblem),
        report.persistenceProblem?.code.name,
        handle.account.value,
        handle.id,
      ],
    );
    await _pruneCleanFlagBatches(handle.account, preserving: handle.id);
  }, complete: true);

  MailStoredFlagBatchSummary _flagSummary(QueryRow row, MailAccountId account) {
    _id(row.read<String>('id'));
    _id(row.read<String>('mailbox'));
    if (row.read<String>('id').trim().isEmpty ||
        row.read<String>('id').length > 256) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return MailStoredFlagBatchSummary(
      id: row.read<String>('id'),
      mailbox: MailMailboxId(row.read<String>('mailbox'), account: account),
      provider: MailProviderKind.values.byName(row.read<String>('provider')),
      action: MailBulkFlagAction.values.byName(row.read<String>('action')),
      destination: _flagDestination(row, account),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
      revision: row.read<int>('revision'),
      complete: row.read<int>('complete') == 1,
      interrupted: row.read<int>('interrupted') == 1,
      confirmedCount: row.read<int>('confirmed_count'),
      failedCount: row.read<int>('failed_count'),
      uncertainCount: row.read<int>('uncertain_count'),
      reconciledCount: row.read<int>('reconciled_count'),
      unattemptedCount: row.read<int>('unattempted_count'),
      stopReason: switch (row.readNullable<String>('stop_reason')) {
        final String reason => MailBulkFlagStopReason.values.byName(reason),
        null => null,
      },
      persistenceProblem: switch (row.readNullable<String>(
        'persistence_problem',
      )) {
        final String code => MailProblem(MailProblemCode.values.byName(code)),
        null => null,
      },
    );
  }

  static const _flagSummarySelect =
      'SELECT b.*, '
      "(SELECT count(*) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='confirmed') AS confirmed_count, "
      "(SELECT count(*) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='failed') AS failed_count, "
      "(SELECT count(*) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state IN ('uncertain','applying')) AS uncertain_count, "
      '(SELECT count(*) FROM flag_item_resolutions r WHERE r.account=b.account AND r.batch=b.id) AS reconciled_count, '
      "(SELECT count(*) FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='unattempted') AS unattempted_count "
      'FROM flag_batches b ';

  Future<MailResult<MailStoredFlagBatchPage>> listFlagBatches(
    MailAccountId account, {
    int limit = 20,
    int offset = 0,
  }) => _run(
    () => _db.transaction(() async {
      await _account(account);
      if (limit < 1 ||
          limit > 100 ||
          offset < 0 ||
          offset > maxStoredFlagBatches) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      await _checkFlagBatches(account);
      final rows = await _rows(
        '$_flagSummarySelect WHERE b.account=? ORDER BY b.created_at DESC,b.id DESC LIMIT ? OFFSET ?',
        [account.value, limit + 1, offset],
      );
      return MailStoredFlagBatchPage(
        batches: [
          for (final row in rows.take(limit)) _flagSummary(row, account),
        ],
        nextOffset: rows.length > limit ? offset + limit : null,
      );
    }),
  );

  Future<MailResult<MailStoredFlagBatch?>> loadFlagBatch(
    MailAccountId account,
    String id,
  ) => _run(
    () => _db.transaction(() async {
      await _account(account);
      _id(id);
      await _checkFlagBatches(account);
      final batches = await _rows(
        '$_flagSummarySelect WHERE b.account=? AND b.id=?',
        [account.value, id],
      );
      if (batches.isEmpty) return null;
      final batch = batches.single;
      final sizes = (await _rows(
        'SELECT coalesce(sum(length(CAST(remote AS BLOB))+length(CAST(subject AS BLOB))),0) AS bytes, '
        "coalesce(sum(CASE WHEN typeof(remote)!='text' OR typeof(subject)!='text' OR "
        'length(CAST(remote AS BLOB))>32768 OR length(CAST(subject AS BLOB))>16384 '
        "OR (problem_code IS NOT NULL AND (typeof(problem_code)!='text' OR length(CAST(problem_code AS BLOB))>64)) "
        "OR (retry_after_us IS NOT NULL AND (typeof(retry_after_us)!='integer' OR retry_after_us<0 OR retry_after_us>9007199254740991)) "
        "OR (mutation_possible IS NOT NULL AND (typeof(mutation_possible)!='integer' OR mutation_possible NOT IN (0,1))) "
        'THEN 1 ELSE 0 END),0) AS invalid FROM flag_batch_items WHERE account=? AND batch=?',
        [account.value, id],
      )).single;
      if (sizes.read<int>('invalid') != 0) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      if (sizes.read<int>('bytes') > _flagMetadataLimit * 4) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final items = await _rows(
        'SELECT * FROM flag_batch_items WHERE account=? AND batch=? ORDER BY position',
        [account.value, id],
      );
      final summary = _flagSummary(batch, account);
      var units =
          id.length +
          summary.mailbox.value.length +
          (summary.destination?.value.length ?? 0);
      for (final item in items) {
        units +=
            item.read<String>('remote').length +
            item.read<String>('subject').length;
        if (item.read<String>('subject').length > 4096) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
      }
      if (units > _flagMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final plan = MailBulkFlagPlan(
        id: id,
        mailbox: summary.mailbox,
        provider: summary.provider,
        action: summary.action,
        destination: summary.destination,
        messages: [
          for (final item in items)
            MailStoreCodec.decodeRemote(
              item.read<String>('remote'),
              account: account,
            ),
        ],
      );
      final reason = batch.readNullable<String>('stop_reason');
      final persistence = batch.readNullable<String>('persistence_problem');
      final resolutions = <MailStoredFlagResolution>[];
      for (final row in await _rows(
        'SELECT position,kind,checked_at FROM flag_item_resolutions WHERE account=? AND batch=? ORDER BY position',
        [account.value, id],
      )) {
        final index = row.read<int>('position');
        final kind = MailFlagResolutionKind.values.byName(
          row.read<String>('kind'),
        );
        if (kind == MailFlagResolutionKind.identityChanged &&
            plan.messages[index] is! MailImapIdentity) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
        resolutions.add(
          MailStoredFlagResolution(
            index: index,
            kind: kind,
            checkedAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('checked_at'),
              isUtc: true,
            ),
          ),
        );
      }
      final identityTransitions = await _loadMoveIdentityTransitions(
        account,
        batch,
        items,
      );
      final transitionsByIndex = {
        for (final stored in identityTransitions)
          stored.index: stored.transition,
      };
      return MailStoredFlagBatch(
        summary: summary,
        identityTransitions: identityTransitions,
        membershipObservations: await _loadMembershipObservations(
          account,
          id,
          plan,
        ),
        subjects: [for (final item in items) item.read<String>('subject')],
        resolutions: resolutions,
        report: MailBulkFlagReport.restore(
          plan: plan,
          results: [
            for (var i = 0; i < items.length; i++)
              MailBulkFlagItemResult.restore(
                operation: plan.operationAt(i),
                identityTransition: transitionsByIndex[i],
                outcome: items[i].read<String>('state') == 'applying'
                    ? MailBulkFlagOutcome.uncertain
                    : MailBulkFlagOutcome.values.byName(
                        items[i].read<String>('state'),
                      ),
                problem: items[i].read<String>('state') == 'applying'
                    ? const MailProblem(
                        MailProblemCode.providerFailure,
                        mutationMayHaveOccurred: true,
                      )
                    : _readFlagProblem(items[i]),
              ),
          ],
          stopReason: reason == null
              ? null
              : MailBulkFlagStopReason.values.byName(reason),
          stopProblem: _readFlagProblem(batch),
          persistenceProblem: persistence == null
              ? null
              : MailProblem(MailProblemCode.values.byName(persistence)),
        ),
      );
    }),
  );

  /// Local history cleanup preserves running and unresolved uncertain work.
  /// Later definitive observations make completed uncertain receipts eligible.
  Future<MailResult<int>> clearCompletedFlagBatches(
    MailAccountId account,
  ) => _write(() async {
    await _account(account);
    await _checkFlagBatches(account);
    await _db.customStatement(
      'DELETE FROM flag_batches WHERE account=? AND id IN '
      '(SELECT b.id FROM flag_batches b WHERE b.account=? AND $_cleanFlagBatch)',
      [account.value, account.value],
    );
    return (await _rows('SELECT changes() AS n')).single.read<int>('n');
  });

  /// Called only by exclusive-open recovery or logout. Existing acknowledgements
  /// survive; dispatch markers become uncertain and untouched items stay so.
  Future<void> _recoverFlagBatches({MailAccountId? account}) async {
    final scope = account == null ? '' : ' AND account=?';
    final args = <Object?>[if (account != null) account.value];
    final unfinished = (await _rows(
      'SELECT count(*) AS n FROM flag_batches WHERE complete=0$scope',
      args,
    )).single.read<int>('n');
    if (unfinished == 0) return;
    final now = _flagNow();
    await _db.customStatement(
      "UPDATE flag_batch_items SET state='uncertain',problem_code='providerFailure',"
      "retry_after_us=NULL,mutation_possible=1 WHERE state='applying'$scope",
      args,
    );
    await _db.customStatement(
      'UPDATE flag_batches AS b SET complete=1,interrupted=1,revision=revision+1,updated_at=?, '
      "stop_reason=CASE WHEN EXISTS (SELECT 1 FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='uncertain') THEN 'uncertain' ELSE 'cancelled' END, "
      "problem_code=CASE WHEN EXISTS (SELECT 1 FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='uncertain') THEN 'providerFailure' ELSE 'cancelled' END, "
      'retry_after_us=NULL,mutation_possible=CASE WHEN EXISTS '
      "(SELECT 1 FROM flag_batch_items i WHERE i.account=b.account AND i.batch=b.id AND i.state='uncertain') THEN 1 ELSE 0 END "
      'WHERE complete=0$scope',
      [now, ...args],
    );
  }
}
