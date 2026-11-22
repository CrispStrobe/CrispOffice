part of 'repository.dart';

/// Authoritative mutation replies are historical evidence, separate from later
/// read-only observations. Projection is deliberately conditional; losing a
/// local cache fence cannot erase an already acknowledged provider operation.
extension MailMoveIdentityTransitions on SqliteMailRepository {
  Future<int> _mailboxMoveRevision(MailMailboxId mailbox) async {
    final rows = await _rows(
      'SELECT revision,typeof(revision) AS type FROM mailbox_move_revisions '
      'WHERE account=? AND mailbox=?',
      [mailbox.account.value, mailbox.value],
    );
    if (rows.isEmpty) return 0;
    final row = rows.single;
    if (row.read<String>('type') != 'integer') {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final revision = row.read<int>('revision');
    if (revision < 1 || revision > MailFlagCommandJournal._maxFlagRevision) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return revision;
  }

  Future<void> _advanceMailboxMoveRevision(MailMailboxId mailbox) async {
    final previous = await _mailboxMoveRevision(mailbox);
    if (previous >= MailFlagCommandJournal._maxFlagRevision) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    await _db.customStatement(
      'INSERT INTO mailbox_move_revisions(account,mailbox,revision) VALUES(?,?,?) '
      'ON CONFLICT(account,mailbox) DO UPDATE SET revision=excluded.revision',
      [mailbox.account.value, mailbox.value, previous + 1],
    );
  }

  Future<void> _checkMoveIdentityTransitions(MailAccountId account) async {
    final invalidFences = (await _rows(
      'SELECT count(*) AS n FROM mailbox_move_revisions WHERE account=? AND ('
      "typeof(mailbox)!='text' OR length(CAST(mailbox AS BLOB)) NOT BETWEEN 1 AND 4096 OR "
      "typeof(revision)!='integer' OR revision NOT BETWEEN 1 AND 9007199254740991)",
      [account.value],
    )).single.read<int>('n');
    if (invalidFences != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    for (final row in await _rows(
      'SELECT mailbox FROM mailbox_move_revisions WHERE account=?',
      [account.value],
    )) {
      final mailbox = row.read<String>('mailbox');
      if (mailbox.length > 1024 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(mailbox)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
    }
    final invalid = (await _rows(
      'SELECT count(*) AS n FROM move_identity_transitions t '
      'LEFT JOIN flag_batches b ON b.account=t.account AND b.id=t.batch '
      'LEFT JOIN flag_batch_items i ON i.account=t.account AND i.batch=t.batch AND i.position=t.position '
      'WHERE t.account=? AND ('
      "typeof(t.batch)!='text' OR length(CAST(t.batch AS BLOB)) NOT BETWEEN 1 AND 1024 OR "
      "typeof(t.position)!='integer' OR t.position NOT BETWEEN 0 AND 999 OR "
      "typeof(t.destination_remote)!='text' OR length(CAST(t.destination_remote AS BLOB)) NOT BETWEEN 1 AND 32768 OR "
      "typeof(t.destination_message)!='text' OR length(CAST(t.destination_message AS BLOB)) NOT BETWEEN 1 AND 8192 OR "
      "typeof(t.recorded_at)!='integer' OR t.recorded_at NOT BETWEEN 0 AND 8640000000000000 OR "
      "typeof(t.cache_projected)!='integer' OR t.cache_projected NOT IN (0,1) OR "
      "b.id IS NULL OR i.position IS NULL OR b.action!='move' OR i.state!='confirmed' OR "
      "b.provider NOT IN ('imap','ews','graph') OR "
      't.recorded_at<b.created_at OR t.recorded_at>b.updated_at)',
      [account.value],
    )).single.read<int>('n');
    if (invalid != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final oversized = await _rows(
      'SELECT 1 AS invalid FROM move_identity_transitions WHERE account=? '
      'GROUP BY batch HAVING sum(length(CAST(destination_remote AS BLOB))+'
      'length(CAST(destination_message AS BLOB)))>? LIMIT 1',
      [account.value, _flagMetadataLimit * 4],
    );
    if (oversized.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    // Validate exact identity semantics even on content-light history reads.
    for (final row in await _rows(
      'SELECT t.*,b.mailbox,b.destination,b.provider,i.remote '
      'FROM move_identity_transitions t JOIN flag_batches b '
      'ON b.account=t.account AND b.id=t.batch JOIN flag_batch_items i '
      'ON i.account=t.account AND i.batch=t.batch AND i.position=t.position '
      'WHERE t.account=?',
      [account.value],
    )) {
      _decodeMoveIdentityTransition(account, row);
    }
  }

  MailStoredMoveIdentityTransition _decodeMoveIdentityTransition(
    MailAccountId account,
    QueryRow row,
  ) {
    try {
      final source = MailStoreCodec.decodeRemote(
        row.read<String>('remote'),
        account: account,
      );
      final destinationEncoded = row.read<String>('destination_remote');
      final destination = MailStoreCodec.decodeRemote(
        destinationEncoded,
        account: account,
      );
      final position = row.read<int>('position');
      final transition = MailMoveIdentityTransition(
        operationId: '${row.read<String>('batch')}:$position',
        source: source,
        sourceMailbox: MailMailboxId(
          row.read<String>('mailbox'),
          account: account,
        ),
        destination: destination,
        destinationMailbox: MailMailboxId(
          row.read<String>('destination'),
          account: account,
        ),
        destinationMessageId: MailMessageId(
          row.read<String>('destination_message'),
        ),
      );
      if (source.provider.name != row.read<String>('provider') ||
          MailStoreCodec.encodeRemote(destination) != destinationEncoded) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      return MailStoredMoveIdentityTransition(
        index: position,
        transition: transition,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('recorded_at'),
          isUtc: true,
        ),
        cacheProjected: row.read<int>('cache_projected') == 1,
      );
    } on Object {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
  }

  static const _moveTransitionSelect =
      'SELECT t.*,b.mailbox,b.destination,b.provider,i.remote '
      'FROM move_identity_transitions t JOIN flag_batches b '
      'ON b.account=t.account AND b.id=t.batch JOIN flag_batch_items i '
      'ON i.account=t.account AND i.batch=t.batch AND i.position=t.position ';

  Future<MailStoredMoveIdentityTransition?> _loadMoveIdentityTransition(
    MailAccountId account,
    QueryRow batch,
    QueryRow item,
  ) async {
    final rows = await _rows(
      '${_moveTransitionSelect}WHERE t.account=? AND t.batch=? AND t.position=?',
      [account.value, batch.read<String>('id'), item.read<int>('position')],
    );
    return rows.isEmpty
        ? null
        : _decodeMoveIdentityTransition(account, rows.single);
  }

  Future<List<MailStoredMoveIdentityTransition>> _loadMoveIdentityTransitions(
    MailAccountId account,
    QueryRow batch,
    List<QueryRow> items,
  ) async {
    final result = <MailStoredMoveIdentityTransition>[];
    var units = 0;
    for (final row in await _rows(
      '${_moveTransitionSelect}WHERE t.account=? AND t.batch=? ORDER BY t.position',
      [account.value, batch.read<String>('id')],
    )) {
      units +=
          row.read<String>('destination_remote').length +
          row.read<String>('destination_message').length;
      if (units > _flagMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final stored = _decodeMoveIdentityTransition(account, row);
      if (stored.index < 0 ||
          stored.index >= items.length ||
          items[stored.index].read<String>('state') != 'confirmed' ||
          !stored.transition.matches(
            _flagOperation(batch, items[stored.index], account),
            sourceMailbox: MailMailboxId(
              batch.read<String>('mailbox'),
              account: account,
            ),
          )) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      result.add(stored);
    }
    return result;
  }

  Future<void> _writeMoveIdentityTransition(
    MailAccountId account,
    QueryRow batch,
    QueryRow item,
    MailMoveIdentityTransition transition, {
    required bool canProject,
  }) async {
    final now = _flagNow();
    if (now < batch.read<int>('created_at') ||
        now < batch.read<int>('updated_at')) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    final encoded = MailStoreCodec.encodeRemote(transition.destination);
    final sizes = (await _rows(
      'SELECT coalesce(sum(length(CAST(destination_remote AS BLOB))+'
      'length(CAST(destination_message AS BLOB))),0) AS n '
      'FROM move_identity_transitions WHERE account=? AND batch=?',
      [account.value, batch.read<String>('id')],
    )).single.read<int>('n');
    if (sizes > _flagMetadataLimit * 4 ||
        encoded.length + transition.destinationMessageId.value.length >
            _flagMetadataLimit) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    var units = encoded.length + transition.destinationMessageId.value.length;
    for (final row in await _rows(
      'SELECT destination_remote,destination_message FROM move_identity_transitions '
      'WHERE account=? AND batch=?',
      [account.value, batch.read<String>('id')],
    )) {
      units +=
          row.read<String>('destination_remote').length +
          row.read<String>('destination_message').length;
      if (units > _flagMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
    }
    await _db.customStatement(
      'INSERT INTO move_identity_transitions('
      'account,batch,position,destination_remote,destination_message,recorded_at,cache_projected) '
      'VALUES(?,?,?,?,?,?,?)',
      [
        account.value,
        batch.read<String>('id'),
        item.read<int>('position'),
        encoded,
        transition.destinationMessageId.value,
        now,
        0,
      ],
    );
    if (canProject) {
      try {
        // Keep the provider receipt in the outer journal transaction. Optional
        // cache growth can roll back independently when it exhausts the quota.
        // Requiring a savepoint prevents a partially applied projection.
        await _db.transaction(() async {
          if (!await _projectMoveIdentityTransition(transition)) return;
          await _db.customStatement(
            'UPDATE move_identity_transitions SET cache_projected=1 '
            'WHERE account=? AND batch=? AND position=?',
            [
              account.value,
              batch.read<String>('id'),
              item.read<int>('position'),
            ],
          );
          await _quota(account);
        }, requireNew: true);
      } on MailStoreStorageException catch (error) {
        if (error.code != MailProblemCode.quotaExceeded) rethrow;
        // The outer quota check still rejects a receipt that cannot itself fit.
      }
    }
  }

  Future<bool> _projectMoveIdentityTransition(
    MailMoveIdentityTransition transition,
  ) async {
    final account = transition.source.account;
    // A valid receipt may carry a provider ID beyond the older cache's bound.
    // Keep that receipt without silently truncating it to make a cache key.
    if (transition.destinationMessageId.value.length > 1024 ||
        transition.destination is MailOpaqueIdentity &&
            (transition.destination as MailOpaqueIdentity).value.length >
                1024) {
      return false;
    }
    final sourceRemote = _remoteKey(transition.source);
    final destinationRemote = _remoteKey(transition.destination);
    final sources = await _rows(
      'SELECT * FROM messages WHERE account=? AND remote=?',
      [account.value, sourceRemote],
    );
    if (sources.isEmpty) return false;
    final source = sources.single;
    final sourceId = source.read<String>('id');
    final destinationId = transition.destinationMessageId.value;
    final sourceView = await _loadMailboxView(transition.sourceMailbox);
    final destinationView = await _loadMailboxView(
      transition.destinationMailbox,
    );
    // An absent browse view has no CAS revision. A request that read a null
    // revision before this move could otherwise publish stale membership after
    // it. Keep the receipt and defer projection until both views can be fenced.
    if (sourceView == null || destinationView == null) return false;
    await _checkSyncMailboxes(account);
    final sourceSync = await _rows(
      'SELECT revision FROM mailbox_sync_state WHERE account=? AND mailbox=?',
      [account.value, transition.sourceMailbox.value],
    );
    final destinationSync = await _rows(
      'SELECT revision FROM mailbox_sync_state WHERE account=? AND mailbox=?',
      [account.value, transition.destinationMailbox.value],
    );
    final sourceMembership = await _rows(
      'SELECT 1 AS present FROM memberships WHERE account=? AND mailbox=? AND message=?',
      [account.value, transition.sourceMailbox.value, sourceId],
    );
    final inSourceView = sourceView.headers.any(
      (header) => header.id.value == sourceId,
    );
    if (sourceMembership.isNotEmpty && sourceSync.isEmpty ||
        !inSourceView && sourceMembership.isEmpty) {
      return false;
    }
    final targets = await _rows(
      'SELECT * FROM messages WHERE account=? AND (id=? OR remote=?)',
      [account.value, destinationId, destinationRemote],
    );
    if (targets.any(
      (row) =>
          row.read<String>('id') != destinationId ||
          row.read<String>('remote') != destinationRemote,
    )) {
      return false;
    }
    final destinationInView = destinationView.headers.any(
      (header) => header.id.value == destinationId,
    );
    if (!destinationInView &&
        destinationView.headers.length >= _viewHeaderLimit) {
      return false;
    }
    // Use the exact stored UTF-16 code-unit lengths read by the view loader,
    // including a previously observed target's metadata when it is reused.
    // Count and account quotas alone do not bound an individual retained view.
    if (!destinationInView) {
      var units =
          destinationView.mailbox.id.value.length +
          destinationView.mailbox.displayName.length +
          destinationId.length +
          destinationRemote.length +
          (targets.isEmpty ? source : targets.single)
              .read<String>('envelope')
              .length;
      if (units > _viewMetadataLimit) return false;
      for (final row in await _rows(
        'SELECT m.id,m.remote,m.envelope FROM mailbox_view_members v '
        'JOIN messages m ON m.account=v.account AND m.id=v.message '
        'WHERE v.account=? AND v.mailbox=? LIMIT ?',
        [account.value, transition.destinationMailbox.value, _viewHeaderLimit],
      )) {
        units +=
            row.read<String>('id').length +
            row.read<String>('remote').length +
            row.read<String>('envelope').length;
        if (units > _viewMetadataLimit) return false;
      }
    }
    if (destinationSync.isNotEmpty) {
      final members = await _rows(
        'SELECT m.id,m.remote,m.envelope FROM messages m JOIN memberships s '
        'ON s.account=m.account AND s.message=m.id WHERE s.account=? AND s.mailbox=? LIMIT ?',
        [
          account.value,
          transition.destinationMailbox.value,
          _syncHeaderLimit + 1,
        ],
      );
      // A projection is bounded to one retained page; larger destinations use
      // explicit synchronization rather than an unbounded metadata scan.
      if (members.length > _syncHeaderLimit) return false;
      var units =
          transition.destinationMailbox.value.length +
          destinationView.mailbox.displayName.length;
      var present = false;
      for (final member in members) {
        present |= member.read<String>('id') == destinationId;
        units +=
            member.read<String>('id').length +
            member.read<String>('remote').length +
            member.read<String>('envelope').length;
      }
      if (!present) {
        if (members.length >= _syncHeaderLimit) return false;
        units +=
            destinationId.length +
            destinationRemote.length +
            (targets.isEmpty
                ? source.read<String>('envelope').length
                : targets.single.read<String>('envelope').length);
      }
      if (units > _syncMetadataLimit) return false;
    }
    if (transition.destination case MailImapIdentity(:final uidValidity)) {
      if (destinationView.headers.any(
        (header) =>
            header.remote is! MailImapIdentity ||
            (header.remote as MailImapIdentity).uidValidity != uidValidity,
      )) {
        return false;
      }
      final members = await _rows(
        'SELECT m.remote FROM messages m JOIN memberships s '
        'ON s.account=m.account AND s.message=m.id WHERE s.account=? AND s.mailbox=? LIMIT ?',
        [
          account.value,
          transition.destinationMailbox.value,
          _syncHeaderLimit + 1,
        ],
      );
      // Projection does not scan an unbounded retained mailbox. A fresh sync
      // can safely handle a larger destination using its own bounded pages.
      if (members.length > _syncHeaderLimit) return false;
      for (final member in members) {
        final identity = MailStoreCodec.decodeRemote(
          member.read<String>('remote'),
          account: account,
        );
        if (identity is! MailImapIdentity ||
            identity.mailbox != transition.destinationMailbox ||
            identity.uidValidity != uidValidity) {
          return false;
        }
      }
    }
    if (sourceSync.any(
          (row) =>
              row.read<int>('revision') >=
              MailSynchronizedMailboxes._maxSyncRevision,
        ) ||
        destinationSync.any(
          (row) =>
              row.read<int>('revision') >=
              MailSynchronizedMailboxes._maxSyncRevision,
        )) {
      return false;
    }
    for (final mailbox in [
      transition.sourceMailbox,
      transition.destinationMailbox,
    ]) {
      if (await _mailboxMoveRevision(mailbox) >=
          MailFlagCommandJournal._maxFlagRevision) {
        return false;
      }
    }
    final counter = (await _rows(
      'SELECT mailbox_view_revision FROM store_profile',
    )).single.read<int>('mailbox_view_revision');
    if (counter < 0 || counter >= MailFlagCommandJournal._maxFlagRevision) {
      return false;
    }
    final envelope = MailStoreCodec.decodeEnvelope(
      source.read<String>('envelope'),
    );
    if (_envelopeUnits(envelope) > _viewMetadataLimit) return false;
    MailStoreCodec.decodeFlags(source.readNullable<int>('flags'));
    if (targets.isEmpty) {
      final count = (await _rows(
        'SELECT count(*) AS n FROM messages WHERE account=?',
        [account.value],
      )).single.read<int>('n');
      if (count >= limits.maxMessagesPerAccount) return false;
    }
    // All eligibility checks precede writes. The surrounding savepoint rolls
    // back membership, header/index and revision changes together on quota loss.
    if (targets.isEmpty) {
      await _db.customStatement(
        'INSERT INTO messages(account,id,remote,envelope,flags,conversation) '
        'VALUES(?,?,?,?,?,?)',
        [
          account.value,
          destinationId,
          destinationRemote,
          source.read<String>('envelope'),
          source.readNullable<int>('flags'),
          source.readNullable<String>('conversation'),
        ],
      );
      await _index(account, transition.destinationMessageId, envelope, null);
    }
    if (sourceMembership.isNotEmpty) {
      await _db.customStatement(
        'DELETE FROM memberships WHERE account=? AND mailbox=? AND message=?',
        [account.value, transition.sourceMailbox.value, sourceId],
      );
    }
    if (destinationSync.isNotEmpty) {
      await _db.customStatement(
        'INSERT INTO memberships(account,mailbox,message) VALUES(?,?,?) ON CONFLICT DO NOTHING',
        [account.value, transition.destinationMailbox.value, destinationId],
      );
    }
    // A source window that omitted this synchronized member still advances its
    // revision, so an older browse response cannot reintroduce the moved row.
    await _replaceMoveViewMembers(transition.sourceMailbox, [
      for (final header in sourceView.headers)
        if (header.id.value != sourceId) header.id.value,
    ], counter + 1);
    await _replaceMoveViewMembers(transition.destinationMailbox, [
      for (final header in destinationView.headers) header.id.value,
      if (!destinationInView) destinationId,
    ], counter + 1);
    await _db.customStatement(
      'UPDATE store_profile SET mailbox_view_revision=?',
      [counter + 1],
    );
    for (final mailbox in [
      transition.sourceMailbox,
      transition.destinationMailbox,
    ]) {
      await _advanceMailboxMoveRevision(mailbox);
      await _db.customStatement(
        'UPDATE mailbox_sync_state SET revision=revision+1 WHERE account=? AND mailbox=?',
        [account.value, mailbox.value],
      );
    }
    await _recordTombstone(account, transition.sourceMailbox, sourceRemote);
    await _db.customStatement(
      'DELETE FROM tombstones WHERE account=? AND mailbox=? AND remote=?',
      [account.value, transition.destinationMailbox.value, destinationRemote],
    );
    // Source message rows, retained bodies, blob references, archives, drafts
    // and Outbox entries remain untouched. No destination body is fabricated.
    return true;
  }

  Future<void> _replaceMoveViewMembers(
    MailMailboxId mailbox,
    List<String> messages,
    int revision,
  ) async {
    await _db.customStatement(
      'DELETE FROM mailbox_view_members WHERE account=? AND mailbox=?',
      [mailbox.account.value, mailbox.value],
    );
    for (var position = 0; position < messages.length; position++) {
      await _db.customStatement(
        'INSERT INTO mailbox_view_members(account,mailbox,position,message) VALUES(?,?,?,?)',
        [mailbox.account.value, mailbox.value, position, messages[position]],
      );
    }
    await _db.customStatement(
      'UPDATE mailbox_views SET revision=?,header_count=? WHERE account=? AND mailbox=?',
      [revision, messages.length, mailbox.account.value, mailbox.value],
    );
  }
}
