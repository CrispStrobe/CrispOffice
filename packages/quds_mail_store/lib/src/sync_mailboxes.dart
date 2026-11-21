part of 'repository.dart';

/// Durable synchronization checkpoints and authoritative local memberships.
/// These APIs neither contact providers nor reinterpret saved browse windows.
extension MailSynchronizedMailboxes on SqliteMailRepository {
  static const maxSyncMailboxes = 1000;
  static const maxSyncHeaders = 1000;
  static const _maxSyncRevision = 9007199254740991;

  int get _syncHeaderLimit =>
      limits.maxPageSize < maxSyncHeaders ? limits.maxPageSize : maxSyncHeaders;

  int get _syncMetadataLimit => limits.maxMetadataCodeUnits < 2 * 1024 * 1024
      ? limits.maxMetadataCodeUnits
      : 2 * 1024 * 1024;

  static const _syncSummarySelect =
      'SELECT s.*,b.display_name,b.is_label,'
      '(SELECT count(*) FROM memberships m '
      'WHERE m.account=s.account AND m.mailbox=s.mailbox) AS header_count '
      'FROM mailbox_sync_state s JOIN mailboxes b '
      'ON b.account=s.account AND b.id=s.mailbox ';

  Future<void> _checkSyncMailboxes(
    MailAccountId account, {
    MailMailboxId? mailbox,
  }) async {
    final scope = mailbox == null ? '' : ' AND s.mailbox=?';
    final args = <Object?>[account.value, if (mailbox != null) mailbox.value];
    final count = (await _rows(
      'SELECT count(*) AS n FROM mailbox_sync_state s WHERE s.account=?$scope',
      args,
    )).single.read<int>('n');
    if (count > maxSyncMailboxes) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    // Validate types and encoded sizes before transferring stored text. A
    // checkpoint without its mailbox or cursor is corruption, not absence.
    final invalid = (await _rows(
      'SELECT count(*) AS n FROM mailbox_sync_state s LEFT JOIN mailboxes b '
      'ON b.account=s.account AND b.id=s.mailbox LEFT JOIN cursors c '
      'ON c.account=s.account AND c.mailbox=s.mailbox '
      'WHERE s.account=?$scope AND ('
      "b.id IS NULL OR c.mailbox IS NULL OR typeof(s.mailbox)!='text' OR "
      "typeof(b.display_name)!='text' OR length(CAST(s.mailbox AS BLOB))>4096 OR "
      'length(CAST(b.display_name AS BLOB))>16384 OR '
      "typeof(b.is_label)!='integer' OR b.is_label NOT IN (0,1) OR "
      "typeof(s.revision)!='integer' OR s.revision<1 OR s.revision>9007199254740991 OR "
      "typeof(s.updated_at)!='integer' OR s.updated_at<0 OR "
      's.updated_at>8640000000000000 OR '
      "typeof(s.has_more)!='integer' OR s.has_more NOT IN (0,1) OR "
      "typeof(c.cursor)!='text' OR length(CAST(c.cursor AS BLOB))>65536)",
      args,
    )).single.read<int>('n');
    if (invalid != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
  }

  MailMailboxSyncSummary _syncMailboxSummary(
    QueryRow row,
    MailAccountId account,
  ) {
    final id = row.read<String>('mailbox');
    final name = row.read<String>('display_name');
    if (id.isEmpty ||
        id.length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(id) ||
        name.length > 4096) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final count = row.read<int>('header_count');
    if (count > limits.maxMessagesPerAccount) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    return MailMailboxSyncSummary(
      mailbox: MailMailbox(
        id: MailMailboxId(id, account: account),
        displayName: name,
        isLabel: row.read<int>('is_label') == 1,
      ),
      revision: row.read<int>('revision'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
      hasMore: row.read<int>('has_more') == 1,
      headerCount: count,
    );
  }

  /// Called only inside commitSyncPage, after its cursor write and before the
  /// final quota/fault/lease gates. Any failure rolls back the entire page.
  Future<void> _saveSyncCheckpoint(MailSyncPage page) async {
    final account = page.mailbox.account;
    await _checkSyncMailboxes(account);
    final rows = await _rows(
      'SELECT revision FROM mailbox_sync_state WHERE account=? AND mailbox=?',
      [account.value, page.mailbox.value],
    );
    final previous = rows.isEmpty ? 0 : rows.single.read<int>('revision');
    if (previous >= _maxSyncRevision) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    if (rows.isEmpty) {
      final count = (await _rows(
        'SELECT count(*) AS n FROM mailbox_sync_state WHERE account=?',
        [account.value],
      )).single.read<int>('n');
      if (count >= maxSyncMailboxes) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
    }
    final now = _clock().toUtc().millisecondsSinceEpoch;
    if (now < 0 || now > 8640000000000000) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    await _db.customStatement(
      'INSERT INTO mailbox_sync_state(account,mailbox,revision,updated_at,has_more) '
      'VALUES(?,?,?,?,?) ON CONFLICT(account,mailbox) DO UPDATE SET '
      'revision=excluded.revision,updated_at=excluded.updated_at,has_more=excluded.has_more',
      [
        account.value,
        page.mailbox.value,
        previous + 1,
        now,
        page.hasMore ? 1 : 0,
      ],
    );
  }

  /// Lists only mailboxes with a checkpoint written by this schema. A legacy
  /// cursor alone does not imply known completion or synchronization time.
  /// Results are ordered by updatedAt descending, then mailbox ID ascending.
  /// Exceeding [limit] is explicit, rather than silently truncating the catalog.
  Future<MailResult<List<MailMailboxSyncSummary>>> listSyncMailboxes(
    MailAccountId account, {
    int limit = maxSyncMailboxes,
  }) => _run(
    () => _db.transaction(() async {
      await _account(account);
      if (limit < 1 || limit > maxSyncMailboxes) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      await _checkSyncMailboxes(account);
      final bytes = (await _rows(
        'SELECT coalesce(sum(length(CAST(s.mailbox AS BLOB))+'
        'length(CAST(b.display_name AS BLOB))),0) AS n FROM mailbox_sync_state s '
        'JOIN mailboxes b ON b.account=s.account AND b.id=s.mailbox WHERE s.account=?',
        [account.value],
      )).single.read<int>('n');
      if (bytes > _syncMetadataLimit * 4) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final rows = await _rows(
        '${_syncSummarySelect}WHERE s.account=? '
        'ORDER BY s.updated_at DESC,s.mailbox LIMIT ?',
        [account.value, limit + 1],
      );
      if (rows.length > limit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      var units = 0;
      final summaries = <MailMailboxSyncSummary>[];
      for (final row in rows) {
        final summary = _syncMailboxSummary(row, account);
        units +=
            summary.mailbox.id.value.length +
            summary.mailbox.displayName.length;
        if (units > _syncMetadataLimit) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        summaries.add(summary);
      }
      return List.unmodifiable(summaries);
    }),
  );

  /// Reads one bounded page in stable local-message-ID ascending order. A null
  /// result means no known synchronization checkpoint, distinct from an empty
  /// synchronized folder. The snapshot and its total count share a transaction.
  /// Bodies, attachments, drafts and Outbox payloads are never read here.
  Future<MailResult<MailMailboxSyncSnapshot?>> loadSyncMailbox(
    MailMailboxId mailbox, {
    int limit = maxSyncHeaders,
    int offset = 0,
  }) => _run(
    () => _db.transaction(() async {
      final account = mailbox.account;
      final accountRow = await _account(account);
      _id(mailbox.value);
      if (limit < 1 ||
          limit > _syncHeaderLimit ||
          offset < 0 ||
          offset > limits.maxMessagesPerAccount) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      await _checkSyncMailboxes(account, mailbox: mailbox);
      final states = await _rows(
        '${_syncSummarySelect}WHERE s.account=? AND s.mailbox=?',
        [account.value, mailbox.value],
      );
      if (states.isEmpty) return null;
      final summary = _syncMailboxSummary(states.single, account);
      var units =
          summary.mailbox.id.value.length + summary.mailbox.displayName.length;
      if (units > _syncMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final arguments = <Object?>[account.value, mailbox.value, limit, offset];
      final preflight = (await _rows(
        'SELECT count(*) AS n,count(id) AS existing,'
        'coalesce(sum(length(CAST(id AS BLOB))+length(CAST(remote AS BLOB))+'
        'length(CAST(envelope AS BLOB))),0) AS bytes,'
        'coalesce(sum(CASE WHEN '
        "typeof(id)!='text' OR typeof(remote)!='text' OR typeof(envelope)!='text' OR "
        'length(CAST(id AS BLOB))>4096 OR length(CAST(remote AS BLOB))>32768 OR '
        "(flags IS NOT NULL AND (typeof(flags)!='integer' OR flags<0 OR flags>31)) "
        'THEN 1 ELSE 0 END),0) AS invalid '
        'FROM (SELECT m.id,m.remote,m.envelope,m.flags FROM memberships s '
        'LEFT JOIN messages m ON m.account=s.account AND m.id=s.message '
        'WHERE s.account=? AND s.mailbox=? ORDER BY s.message LIMIT ? OFFSET ?)',
        arguments,
      )).single;
      if (preflight.read<int>('n') != preflight.read<int>('existing') ||
          preflight.read<int>('invalid') != 0) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      if (preflight.read<int>('bytes') > _syncMetadataLimit * 4) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final headers = <MailHeaderRecord>[];
      final remotes = <MailRemoteIdentity>{};
      int? validity;
      for (final row in await _rows(
        'SELECT m.* FROM messages m JOIN memberships s '
        'ON s.account=m.account AND s.message=m.id '
        'WHERE s.account=? AND s.mailbox=? ORDER BY m.id LIMIT ? OFFSET ?',
        arguments,
      )) {
        units +=
            row.read<String>('id').length +
            row.read<String>('remote').length +
            row.read<String>('envelope').length;
        if (units > _syncMetadataLimit) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        final header = _header(row, account);
        if (header.id.value.length > 1024 ||
            header.remote.provider.name !=
                accountRow.read<String>('provider') ||
            (header.remote is MailOpaqueIdentity &&
                (header.remote as MailOpaqueIdentity).value.length > 1024) ||
            !remotes.add(header.remote)) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
        if (header.remote case MailImapIdentity(
          :final mailbox,
          :final uidValidity,
        )) {
          if (mailbox != summary.mailbox.id ||
              (validity != null && validity != uidValidity)) {
            SqliteMailRepository._fail(MailProblemCode.storageFailure);
          }
          validity = uidValidity;
        }
        _remoteKey(header.remote);
        _envelopeUnits(header.envelope);
        headers.add(header);
      }
      return MailMailboxSyncSnapshot(
        summary: summary,
        headers: headers,
        offset: offset,
        hasMoreHeaders: offset + headers.length < summary.headerCount,
      );
    }),
  );

  /// Observes the same bounded catalog after successful domain commits. Reads
  /// coalesce while paused; cancellation drains an active read; close completes.
  Stream<MailResult<List<MailMailboxSyncSummary>>> watchSyncMailboxes(
    MailAccountId account, {
    int limit = maxSyncMailboxes,
  }) => _watchMailboxSnapshot(() => listSyncMailboxes(account, limit: limit));

  /// Observes one synchronized page with the same absence, bounds and ordering
  /// as loadSyncMailbox. Failed transactions never publish a partial checkpoint.
  Stream<MailResult<MailMailboxSyncSnapshot?>> watchSyncMailbox(
    MailMailboxId mailbox, {
    int limit = maxSyncHeaders,
    int offset = 0,
  }) => _watchMailboxSnapshot(
    () => loadSyncMailbox(mailbox, limit: limit, offset: offset),
  );
}
