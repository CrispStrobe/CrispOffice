part of 'repository.dart';

/// A bounded cache of foreground browse windows, independent of sync cursors.
/// Saving a new window neither declares absent server messages deleted nor
/// removes authoritative memberships, drafts, Outbox entries or cached bodies.
extension MailCachedMailboxViews on SqliteMailRepository {
  static const maxMailboxViews = 1000;
  static const maxViewHeaders = 1000;
  static const _maxRevision = 9007199254740991;

  int get _viewHeaderLimit =>
      limits.maxPageSize < maxViewHeaders ? limits.maxPageSize : maxViewHeaders;

  // An independently bounded view remains safe even when another store feature
  // is deliberately configured with a much larger metadata budget.
  int get _viewMetadataLimit => limits.maxMetadataCodeUnits < 2 * 1024 * 1024
      ? limits.maxMetadataCodeUnits
      : 2 * 1024 * 1024;

  Future<void> _checkMailboxViews(
    MailAccountId account, {
    MailMailboxId? mailbox,
  }) async {
    final scope = mailbox == null ? '' : ' AND v.mailbox=?';
    final args = <Object?>[account.value, if (mailbox != null) mailbox.value];
    final count = (await _rows(
      'SELECT count(*) AS n FROM mailbox_views v WHERE v.account=?$scope',
      args,
    )).single.read<int>('n');
    if (count > maxMailboxViews) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    // Check SQLite types and byte lengths before transferring text to Dart.
    // A missing referenced folder is corrupt storage, not an absent view.
    final invalid = (await _rows(
      'SELECT count(*) AS n FROM mailbox_views v LEFT JOIN mailboxes b '
      'ON b.account=v.account AND b.id=v.mailbox WHERE v.account=?$scope AND ('
      "b.id IS NULL OR typeof(v.mailbox)!='text' OR "
      "typeof(b.display_name)!='text' OR length(CAST(v.mailbox AS BLOB))>4096 OR "
      'length(CAST(b.display_name AS BLOB))>16384 OR '
      "typeof(b.is_label)!='integer' OR b.is_label NOT IN (0,1) OR "
      "typeof(v.revision)!='integer' OR v.revision<1 OR v.revision>9007199254740991 OR "
      "typeof(v.captured_at)!='integer' OR v.captured_at<0 OR "
      'v.captured_at>8640000000000000 OR '
      "typeof(v.header_count)!='integer' OR v.header_count<0 OR v.header_count>1000 OR "
      "typeof(v.has_more)!='integer' OR v.has_more NOT IN (0,1))",
      args,
    )).single.read<int>('n');
    if (invalid != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
  }

  MailCachedMailboxSummary _mailboxViewSummary(
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
    return MailCachedMailboxSummary(
      mailbox: MailMailbox(
        id: MailMailboxId(id, account: account),
        displayName: name,
        isLabel: row.read<int>('is_label') == 1,
      ),
      revision: row.read<int>('revision'),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('captured_at'),
        isUtc: true,
      ),
      headerCount: row.read<int>('header_count'),
      hasMore: row.read<int>('has_more') == 1,
    );
  }

  /// Lists visited folders without reading headers or body/attachment blobs.
  /// Exceeding [limit] is explicit rather than a silently truncated catalog.
  Future<MailResult<List<MailCachedMailboxSummary>>> listMailboxViews(
    MailAccountId account, {
    int limit = maxMailboxViews,
  }) => _run(
    () => _db.transaction(() async {
      await _account(account);
      if (limit < 1 || limit > maxMailboxViews) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      await _checkMailboxViews(account);
      final bytes = (await _rows(
        'SELECT coalesce(sum(length(CAST(v.mailbox AS BLOB))+'
        'length(CAST(b.display_name AS BLOB))),0) AS n FROM mailbox_views v '
        'JOIN mailboxes b ON b.account=v.account AND b.id=v.mailbox WHERE v.account=?',
        [account.value],
      )).single.read<int>('n');
      if (bytes > _viewMetadataLimit * 4) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final rows = await _rows(
        'SELECT v.*,b.display_name,b.is_label FROM mailbox_views v JOIN mailboxes b '
        'ON b.account=v.account AND b.id=v.mailbox WHERE v.account=? '
        'ORDER BY v.captured_at DESC,v.mailbox LIMIT ?',
        [account.value, limit + 1],
      );
      if (rows.length > limit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      var units = 0;
      final summaries = <MailCachedMailboxSummary>[];
      for (final row in rows) {
        final summary = _mailboxViewSummary(row, account);
        units +=
            summary.mailbox.id.value.length +
            summary.mailbox.displayName.length;
        if (units > _viewMetadataLimit) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        summaries.add(summary);
      }
      return List.unmodifiable(summaries);
    }),
  );

  Future<MailCachedMailboxView?> _loadMailboxView(MailMailboxId mailbox) async {
    final account = mailbox.account;
    final accountRow = await _account(account);
    _id(mailbox.value);
    await _checkMailboxViews(account, mailbox: mailbox);
    final rows = await _rows(
      'SELECT v.*,b.display_name,b.is_label FROM mailbox_views v JOIN mailboxes b '
      'ON b.account=v.account AND b.id=v.mailbox WHERE v.account=? AND v.mailbox=?',
      [account.value, mailbox.value],
    );
    if (rows.isEmpty) return null;
    final summary = _mailboxViewSummary(rows.single, account);
    if (summary.mailbox.id.value.length + summary.mailbox.displayName.length >
        _viewMetadataLimit) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    if (summary.headerCount > _viewHeaderLimit) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final counts = (await _rows(
      'SELECT count(*) AS n,count(m.id) AS existing,'
      'coalesce(sum(length(CAST(m.id AS BLOB))+length(CAST(m.remote AS BLOB))+'
      'length(CAST(m.envelope AS BLOB))),0) AS bytes '
      'FROM mailbox_view_members v LEFT JOIN messages m '
      'ON m.account=v.account AND m.id=v.message WHERE v.account=? AND v.mailbox=?',
      [account.value, mailbox.value],
    )).single;
    if (counts.read<int>('n') != summary.headerCount ||
        counts.read<int>('existing') != summary.headerCount) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (counts.read<int>('bytes') > _viewMetadataLimit * 4) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final invalid = (await _rows(
      'SELECT count(*) AS n FROM mailbox_view_members v JOIN messages m '
      'ON m.account=v.account AND m.id=v.message WHERE v.account=? AND v.mailbox=? '
      "AND (typeof(v.position)!='integer' OR v.position<0 OR v.position>999 OR "
      "typeof(m.id)!='text' OR typeof(m.remote)!='text' OR typeof(m.envelope)!='text' OR "
      'length(CAST(m.id AS BLOB))>4096 OR length(CAST(m.remote AS BLOB))>32768)',
      [account.value, mailbox.value],
    )).single.read<int>('n');
    if (invalid != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final headers = <MailHeaderRecord>[];
    final ids = <MailMessageId>{};
    final remotes = <MailRemoteIdentity>{};
    var units =
        summary.mailbox.id.value.length + summary.mailbox.displayName.length;
    for (final row in await _rows(
      'SELECT m.*,v.position FROM mailbox_view_members v JOIN messages m '
      'ON m.account=v.account AND m.id=v.message WHERE v.account=? AND v.mailbox=? '
      'ORDER BY v.position LIMIT ?',
      [account.value, mailbox.value, _viewHeaderLimit + 1],
    )) {
      if (row.read<int>('position') != headers.length) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      units +=
          row.read<String>('id').length +
          row.read<String>('remote').length +
          row.read<String>('envelope').length;
      if (units > _viewMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final header = _header(row, account);
      if (header.id.value.length > 1024 ||
          header.remote.provider.name != accountRow.read<String>('provider') ||
          (header.remote is MailOpaqueIdentity &&
              (header.remote as MailOpaqueIdentity).value.length > 1024) ||
          (header.remote is MailImapIdentity &&
              (header.remote as MailImapIdentity).mailbox != mailbox) ||
          !ids.add(header.id) ||
          !remotes.add(header.remote)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      _remoteKey(header.remote);
      _envelopeUnits(header.envelope);
      if (header.remote case MailImapIdentity(:final uidValidity)) {
        if (headers.isNotEmpty &&
            (headers.first.remote as MailImapIdentity).uidValidity !=
                uidValidity) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
      }
      headers.add(header);
    }
    return MailCachedMailboxView(
      mailbox: summary.mailbox,
      revision: summary.revision,
      capturedAt: summary.capturedAt,
      headers: headers,
      hasMore: summary.hasMore,
    );
  }

  /// Returns the complete retained window or null when it has never been saved.
  Future<MailResult<MailCachedMailboxView?>> loadMailboxView(
    MailMailboxId mailbox,
  ) => _run(() => _db.transaction(() => _loadMailboxView(mailbox)));

  /// Atomically replace the ordered loaded window. Null [expectedRevision]
  /// requires no existing view. Capturing an empty folder still advances the
  /// revision; old confirmations cannot replace a newer empty observation.
  Future<MailResult<MailCachedMailboxView>> saveMailboxView(
    MailMailbox mailbox,
    List<MailHeaderRecord> orderedHeaders, {
    required int? expectedRevision,
    required bool hasMore,
    required MailOperationLease lease,
  }) {
    if (orderedHeaders.length > _viewHeaderLimit) {
      return Future.value(
        const MailFailure(MailProblem(MailProblemCode.quotaExceeded)),
      );
    }
    final headers = List<MailHeaderRecord>.unmodifiable(orderedHeaders);
    return _run(
      () => _commit(() async {
        final account = mailbox.id.account;
        final accountRow = await _account(account, active: true);
        _id(mailbox.id.value);
        if (lease.account != account ||
            mailbox.displayName.length > 4096 ||
            (expectedRevision != null &&
                (expectedRevision < 1 || expectedRevision > _maxRevision))) {
          SqliteMailRepository._fail(MailProblemCode.invalidInput);
        }
        lease.checkCurrent();
        await _checkMailboxViews(account);
        final existing = await _rows(
          'SELECT revision FROM mailbox_views WHERE account=? AND mailbox=?',
          [account.value, mailbox.id.value],
        );
        final currentRevision = existing.isEmpty
            ? null
            : existing.single.read<int>('revision');
        if (currentRevision != expectedRevision) {
          SqliteMailRepository._fail(MailProblemCode.conflict);
        }
        if (currentRevision == _maxRevision) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        if (existing.isEmpty) {
          final count = (await _rows(
            'SELECT count(*) AS n FROM mailbox_views WHERE account=?',
            [account.value],
          )).single.read<int>('n');
          if (count >= maxMailboxViews) {
            SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
          }
        }
        final ids = <MailMessageId>{};
        final remotes = <String>{};
        final encoded = <(MailHeaderRecord, String, String)>[];
        var units = mailbox.id.value.length + mailbox.displayName.length;
        for (final header in headers) {
          _id(header.id.value);
          if (header.remote.account != account ||
              header.remote.provider.name !=
                  accountRow.read<String>('provider') ||
              (header.remote is MailImapIdentity &&
                  (header.remote as MailImapIdentity).mailbox != mailbox.id)) {
            SqliteMailRepository._fail(MailProblemCode.invalidInput);
          }
          if (header.remote case MailImapIdentity(:final uidValidity)) {
            final previous = encoded.isEmpty
                ? uidValidity
                : (encoded.first.$1.remote as MailImapIdentity).uidValidity;
            if (previous != uidValidity) {
              SqliteMailRepository._fail(MailProblemCode.invalidInput);
            }
          }
          if (_envelopeUnits(header.envelope) > _viewMetadataLimit - units) {
            SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
          }
          final remote = _remoteKey(header.remote);
          final envelope = MailStoreCodec.encodeEnvelope(header.envelope);
          if (!ids.add(header.id) || !remotes.add(remote)) {
            SqliteMailRepository._fail(MailProblemCode.invalidInput);
          }
          units += header.id.value.length + remote.length + envelope.length;
          if (units > _viewMetadataLimit) {
            SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
          }
          encoded.add((header, remote, envelope));
        }
        if (units > _viewMetadataLimit) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        final now = _clock().toUtc().millisecondsSinceEpoch;
        if (now < 0) SqliteMailRepository._fail(MailProblemCode.invalidInput);
        await _db.customStatement(
          'INSERT INTO mailboxes(account,id,display_name,is_label) VALUES(?,?,?,?) '
          'ON CONFLICT(account,id) DO UPDATE SET display_name=excluded.display_name,is_label=excluded.is_label',
          [
            account.value,
            mailbox.id.value,
            mailbox.displayName,
            mailbox.isLabel ? 1 : 0,
          ],
        );
        for (final (header, remote, envelope) in encoded) {
          final conflicts = await _rows(
            'SELECT id,remote FROM messages WHERE account=? AND (id=? OR remote=?)',
            [account.value, header.id.value, remote],
          );
          if (conflicts.any(
            (row) =>
                row.read<String>('id') != header.id.value ||
                row.read<String>('remote') != remote,
          )) {
            SqliteMailRepository._fail(MailProblemCode.conflict);
          }
          await _db.customStatement(
            'INSERT INTO messages(account,id,remote,envelope,flags) VALUES(?,?,?,?,?) '
            'ON CONFLICT(account,id) DO UPDATE SET envelope=excluded.envelope,'
            'flags=coalesce(excluded.flags,messages.flags)',
            [
              account.value,
              header.id.value,
              remote,
              envelope,
              MailStoreCodec.encodeFlags(header.flags),
            ],
          );
          await _index(
            account,
            header.id,
            header.envelope,
            await _cachedPlain(account, header.id),
          );
        }
        final revision = (currentRevision ?? 0) + 1;
        await _db.customStatement(
          'INSERT INTO mailbox_views(account,mailbox,revision,captured_at,header_count,has_more) '
          'VALUES(?,?,?,?,?,?) ON CONFLICT(account,mailbox) DO UPDATE SET '
          'revision=excluded.revision,captured_at=excluded.captured_at,'
          'header_count=excluded.header_count,has_more=excluded.has_more',
          [
            account.value,
            mailbox.id.value,
            revision,
            now,
            headers.length,
            hasMore ? 1 : 0,
          ],
        );
        await _db.customStatement(
          'DELETE FROM mailbox_view_members WHERE account=? AND mailbox=?',
          [account.value, mailbox.id.value],
        );
        for (var i = 0; i < headers.length; i++) {
          await _db.customStatement(
            'INSERT INTO mailbox_view_members(account,mailbox,position,message) VALUES(?,?,?,?)',
            [account.value, mailbox.id.value, i, headers[i].id.value],
          );
        }
        await _quota(account);
        final result = await _loadMailboxView(mailbox.id);
        await _db.fault(MailStoreCheckpoint.beforeCommit);
        lease.checkCurrent();
        return result!;
      }),
    );
  }
}
