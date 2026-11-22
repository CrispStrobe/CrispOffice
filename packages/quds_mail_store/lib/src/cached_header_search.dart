part of 'repository.dart';

/// An in-memory continuation for one unchanged account/query/repository owner.
///
/// Any committed domain change invalidates it. It cannot be serialized or used
/// after reopen; start a fresh search then. Retrying the same cursor is safe and
/// returns the same page while its repository remains unchanged.
final class MailCachedHeaderSearchCursor {
  const MailCachedHeaderSearchCursor._(
    this._owner,
    this._revision,
    this._account,
    this._query,
    this._mailboxScope,
    this._afterId,
  );

  final Object _owner;
  final Object _revision;
  final MailAccountId _account;
  final String _query;
  final String? _mailboxScope;
  final String _afterId;

  @override
  String toString() => 'MailCachedHeaderSearchCursor(redacted)';
}

/// A canonical saved header, listed once even when it belongs to many labels.
/// Folder membership is a local observation. Body availability is an existence
/// check only; opening the message separately must verify its retained bytes.
final class MailCachedHeaderSearchHit {
  MailCachedHeaderSearchHit({
    required this.header,
    required List<MailMailbox> folders,
    required this.hasCachedBody,
  }) : folders = List.unmodifiable(folders);

  final MailHeaderRecord header;
  final List<MailMailbox> folders;
  final bool hasCachedBody;
}

/// One bounded scan over an account's saved browse/synchronization memberships.
///
/// [scannedCount] counts candidates inspected in this call, not all matches.
/// [totalCount] is the number of distinct eligible saved headers. Empty [hits]
/// with a non-null [nextCursor] still requires continuation. A null cursor means
/// all local candidates have been inspected, never that all server mail exists
/// locally. Coverage lists retain independent browse and synchronization times
/// and provider continuation; legacy memberships can lack either checkpoint.
final class MailCachedHeaderSearchPage {
  MailCachedHeaderSearchPage({
    required List<MailCachedHeaderSearchHit> hits,
    required this.scannedCount,
    required this.totalCount,
    required this.nextCursor,
    required List<MailCachedMailboxSummary> browsed,
    required List<MailMailboxSyncSummary> synchronized,
    List<MailMailboxId> missingMailboxIds = const [],
  }) : hits = List.unmodifiable(hits),
       browsed = List.unmodifiable(browsed),
       synchronized = List.unmodifiable(synchronized),
       missingMailboxIds = List.unmodifiable(missingMailboxIds);

  final List<MailCachedHeaderSearchHit> hits;
  final int scannedCount;
  final int totalCount;
  final MailCachedHeaderSearchCursor? nextCursor;
  final List<MailCachedMailboxSummary> browsed;
  final List<MailMailboxSyncSummary> synchronized;

  /// Explicitly selected folders absent from the local catalog. This is not
  /// evidence of server deletion. Present selected folders can still yield
  /// hits; absent folders are never replaced by an account-wide search.
  final List<MailMailboxId> missingMailboxIds;
}

/// Account-wide discovery over saved headers, independent of the loaded UI
/// page. It never reads body/blob/draft/Outbox payloads or contacts a provider.
extension MailCachedHeaderSearch on SqliteMailRepository {
  static const maxScanSize = 1000;
  static const maxResultSize = 200;
  static const maxCachedSearchMailboxes = 2000;
  static const _maxFoldersPerMessage = 2000;
  static const _eligible =
      '(EXISTS (SELECT 1 FROM memberships s '
      'WHERE s.account=m.account AND s.message=m.id) OR '
      'EXISTS (SELECT 1 FROM mailbox_view_members v JOIN mailbox_views w '
      'ON w.account=v.account AND w.mailbox=v.mailbox '
      'WHERE v.account=m.account AND v.message=m.id))';

  int get _cachedSearchMetadataLimit =>
      limits.maxMetadataCodeUnits < 2 * 1024 * 1024
      ? limits.maxMetadataCodeUnits
      : 2 * 1024 * 1024;

  /// Lists all known local folder identities without opening bodies or calling
  /// a provider. An empty catalog and a known folder with zero retained headers
  /// remain distinct. An oversized catalog is rejected instead of truncated.
  Future<MailResult<List<MailMailbox>>> listCachedSearchMailboxes(
    MailAccountId account, {
    int limit = maxCachedSearchMailboxes,
  }) => _run(() async {
    if (limit < 1 || limit > maxCachedSearchMailboxes) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    return _db.transaction(() async {
      await _account(account);
      return _readCachedSearchMailboxes(account, limit: limit);
    });
  });

  Future<List<MailMailbox>> _readCachedSearchMailboxes(
    MailAccountId account, {
    List<String>? mailboxIds,
    int limit = maxCachedSearchMailboxes,
  }) async {
    final scope = mailboxIds == null
        ? ''
        : ' AND id IN (${List.filled(mailboxIds.length, '?').join(',')})';
    final args = <Object?>[account.value, ...?mailboxIds];
    final select =
        'SELECT id,display_name,is_label FROM mailboxes WHERE account=?$scope';
    final preflight = (await _rows(
      'SELECT count(*) AS n,coalesce(sum(length(CAST(id AS BLOB))+'
      'length(CAST(display_name AS BLOB))),0) AS bytes,'
      'coalesce(sum(CASE WHEN '
      "typeof(id)!='text' OR typeof(display_name)!='text' OR "
      "typeof(is_label)!='integer' OR is_label NOT IN (0,1) OR "
      'length(CAST(id AS BLOB))>4096 OR '
      'length(CAST(display_name AS BLOB))>16384 '
      'THEN 1 ELSE 0 END),0) AS invalid FROM ($select)',
      args,
    )).single;
    if (preflight.read<int>('invalid') != 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (preflight.read<int>('n') > limit ||
        preflight.read<int>('bytes') > _cachedSearchMetadataLimit * 4) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final result = <MailMailbox>[];
    var units = 0;
    for (final row in await _rows('$select ORDER BY id', args)) {
      final id = row.read<String>('id');
      final name = row.read<String>('display_name');
      if (!MailSavedHeaderSearchFolder.isValidMailboxId(id) ||
          !MailSavedHeaderSearchFolder.isValidDisplayName(name)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      units += id.length + name.length;
      if (units > _cachedSearchMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      result.add(
        MailMailbox(
          id: MailMailboxId(id, account: account),
          displayName: name,
          isLabel: row.read<int>('is_label') == 1,
        ),
      );
    }
    return List<MailMailbox>.unmodifiable(result);
  }

  List<String>? _cachedSearchMailboxScope(
    MailAccountId account,
    List<MailMailboxId>? mailboxIds,
  ) {
    if (mailboxIds == null) return null;
    if (mailboxIds.isEmpty ||
        mailboxIds.length > MailSavedHeaderSearch.maxFolders) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final values = <String>{};
    for (final mailbox in mailboxIds) {
      if (mailbox.account != account ||
          !MailSavedHeaderSearchFolder.isValidMailboxId(mailbox.value) ||
          !values.add(mailbox.value)) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
    }
    return values.toList()..sort();
  }

  String _cachedSearchEligible(List<String>? mailboxIds) {
    if (mailboxIds == null) return _eligible;
    final placeholders = List.filled(mailboxIds.length, '?').join(',');
    return '(EXISTS (SELECT 1 FROM memberships s '
        'WHERE s.account=m.account AND s.message=m.id '
        'AND s.mailbox IN ($placeholders)) OR '
        'EXISTS (SELECT 1 FROM mailbox_view_members v JOIN mailbox_views w '
        'ON w.account=v.account AND w.mailbox=v.mailbox '
        'WHERE v.account=m.account AND v.message=m.id '
        'AND v.mailbox IN ($placeholders)))';
  }

  /// Parses the entire bounded Boolean query before reading any message. The
  /// shared evaluator retains unknown flags/dates and local-calendar semantics.
  /// Stable local IDs provide keyset ordering, not chronological ordering.
  /// [limit] bounds returned matches; [scanLimit] bounds inspected candidates.
  /// A content change, account/query change or different owner rejects a cursor
  /// with conflict instead of skipping or duplicating a changing result set.
  /// [folderIds] preserves the published string-ID API: any unavailable folder
  /// fails the account query. [mailboxIds] additionally reports missing folders
  /// as explicit coverage while retaining hits in present selected folders.
  /// Supply only one of the two scope parameters.
  Future<MailResult<MailCachedHeaderSearchPage>> searchCachedHeaders(
    MailAccountId account,
    String query, {
    List<MailMailboxId>? mailboxIds,
    List<String>? folderIds,
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) => _run(() async {
    if (limit < 1 ||
        limit > maxResultSize ||
        limit > limits.maxSearchResults ||
        scanLimit < 1 ||
        scanLimit > maxScanSize ||
        scanLimit > limits.maxPageSize) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    if (mailboxIds != null && folderIds != null) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    if (folderIds != null &&
        (folderIds.isEmpty ||
            folderIds.length > MailSavedHeaderSearch.maxFolders ||
            folderIds.any(
              (id) => !MailSavedHeaderSearchFolder.isValidMailboxId(id),
            ))) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final selected = _cachedSearchMailboxScope(
      account,
      mailboxIds ??
          (folderIds == null
              ? null
              : [
                  for (final id in folderIds)
                    MailMailboxId(id, account: account),
                ]),
    );
    final scopeKey = selected == null ? null : jsonEncode(selected);
    final eligible = _cachedSearchEligible(selected);
    // At most 403 parameters, bounded by the published 200-folder contract.
    // Both membership sources use the same canonical exact folder set.
    final scopeArguments = <Object?>[...?selected, ...?selected];
    final MailHeaderSearchQuery parsed;
    try {
      parsed = MailHeaderSearchQuery.parse(query);
    } on MailHeaderSearchException {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    return _db.transaction(() async {
      final accountRow = await _account(account);
      final revision = _cachedSearchRevision;
      if (cursor != null &&
          (!identical(cursor._owner, _cachedSearchOwner) ||
              !identical(cursor._revision, revision) ||
              cursor._account != account ||
              cursor._query != query ||
              cursor._mailboxScope != scopeKey)) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final allBrowsed = switch (await listMailboxViews(account)) {
        MailSuccess<List<MailCachedMailboxSummary>>(:final value) => value,
        MailFailure<List<MailCachedMailboxSummary>>(:final problem) =>
          SqliteMailRepository._fail(problem.code),
      };
      final allSynchronized = switch (await listSyncMailboxes(account)) {
        MailSuccess<List<MailMailboxSyncSummary>>(:final value) => value,
        MailFailure<List<MailMailboxSyncSummary>>(:final problem) =>
          SqliteMailRepository._fail(problem.code),
      };
      final selectedSet = selected?.toSet();
      final browsed = selectedSet == null
          ? allBrowsed
          : allBrowsed
                .where((item) => selectedSet.contains(item.mailbox.id.value))
                .toList();
      final synchronized = selectedSet == null
          ? allSynchronized
          : allSynchronized
                .where((item) => selectedSet.contains(item.mailbox.id.value))
                .toList();
      final missingMailboxIds = <MailMailboxId>[];
      if (selected != null) {
        final catalog = await _readCachedSearchMailboxes(
          account,
          mailboxIds: selected,
        );
        final present = {for (final mailbox in catalog) mailbox.id.value};
        for (final id in selected) {
          if (!present.contains(id)) {
            missingMailboxIds.add(MailMailboxId(id, account: account));
          }
        }
        if (folderIds != null && missingMailboxIds.isNotEmpty) {
          SqliteMailRepository._fail(MailProblemCode.unavailable);
        }
      }
      var metadataUnits =
          selected?.fold<int>(0, (sum, id) => sum + id.length) ?? 0;
      for (final mailbox in [
        for (final item in browsed) item.mailbox,
        for (final item in synchronized) item.mailbox,
      ]) {
        metadataUnits += mailbox.id.value.length + mailbox.displayName.length;
      }
      if (metadataUnits > _cachedSearchMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      await _checkCachedSearchMemberships(account, mailboxIds: selected);
      final total = (await _rows(
        'SELECT count(*) AS n FROM messages m WHERE m.account=? AND $eligible',
        [account.value, ...scopeArguments],
      )).single.read<int>('n');
      if (total > limits.maxMessagesPerAccount) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final after = cursor?._afterId;
      final where =
          'm.account=? AND $eligible${after == null ? '' : ' AND m.id>?'}';
      final arguments = <Object?>[
        account.value,
        ...scopeArguments,
        ?after,
        scanLimit,
      ];
      final candidates =
          'SELECT m.id,m.remote,m.envelope,m.flags FROM messages m '
          'WHERE $where ORDER BY m.id LIMIT ?';
      // The metadata preflight transfers numbers only. Oversized or malformed
      // stored text is rejected before decoding or allocating candidate DTOs.
      final preflight = (await _rows(
        'SELECT coalesce(sum(length(CAST(id AS BLOB))+'
        'length(CAST(remote AS BLOB))+length(CAST(envelope AS BLOB))),0) AS bytes,'
        'coalesce(sum(CASE WHEN '
        "typeof(id)!='text' OR typeof(remote)!='text' OR typeof(envelope)!='text' OR "
        'length(CAST(id AS BLOB))>4096 OR length(CAST(remote AS BLOB))>32768 OR '
        "(flags IS NOT NULL AND (typeof(flags)!='integer' OR flags<0 OR flags>31)) "
        'THEN 1 ELSE 0 END),0) AS invalid FROM ($candidates)',
        arguments,
      )).single;
      if (preflight.read<int>('invalid') != 0) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      if (preflight.read<int>('bytes') >
          (_cachedSearchMetadataLimit - metadataUnits) * 4) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final hits = <MailCachedHeaderSearchHit>[];
      var scanned = 0;
      String? last;
      for (final row in await _rows(candidates, arguments)) {
        metadataUnits +=
            row.read<String>('id').length +
            row.read<String>('remote').length +
            row.read<String>('envelope').length;
        if (metadataUnits > _cachedSearchMetadataLimit) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        final header = _header(row, account);
        if (header.id.value.length > 1024 ||
            header.remote.provider.name !=
                accountRow.read<String>('provider') ||
            (header.remote is MailOpaqueIdentity &&
                (header.remote as MailOpaqueIdentity).value.length > 1024)) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
        _remoteKey(header.remote);
        _envelopeUnits(header.envelope);
        // Validate IMAP folder ownership before evaluating filters, so a
        // malformed membership cannot disappear behind a nonmatching query.
        // UID/UIDVALIDITY ranges were already checked while decoding remote.
        if (header.remote case MailImapIdentity(:final mailbox)) {
          final wrongFolder = await _rows(
            'SELECT 1 AS invalid FROM memberships '
            'WHERE account=? AND message=? AND mailbox!=? '
            'UNION ALL SELECT 1 AS invalid FROM mailbox_view_members '
            'WHERE account=? AND message=? AND mailbox!=? LIMIT 1',
            [
              account.value,
              header.id.value,
              mailbox.value,
              account.value,
              header.id.value,
              mailbox.value,
            ],
          );
          if (wrongFolder.isNotEmpty) {
            SqliteMailRepository._fail(MailProblemCode.storageFailure);
          }
        }
        scanned++;
        last = header.id.value;
        if (!parsed.matches(_cachedSearchDocument(header))) continue;
        final folders = await _cachedSearchFolders(
          account,
          header,
          _cachedSearchMetadataLimit - metadataUnits,
          mailboxIds: selected,
        );
        for (final folder in folders) {
          metadataUnits += folder.id.value.length + folder.displayName.length;
        }
        final hasBody =
            (await _rows(
              'SELECT EXISTS(SELECT 1 FROM cached_messages '
              'WHERE account=? AND message=?) AS present',
              [account.value, header.id.value],
            )).single.read<int>('present') ==
            1;
        hits.add(
          MailCachedHeaderSearchHit(
            header: header,
            folders: folders,
            hasCachedBody: hasBody,
          ),
        );
        if (hits.length == limit) break;
      }
      final hasMore =
          last != null &&
          (await _rows(
                'SELECT EXISTS(SELECT 1 FROM messages m '
                'WHERE m.account=? AND $eligible AND m.id>?) AS present',
                [account.value, ...scopeArguments, last],
              )).single.read<int>('present') ==
              1;
      return MailCachedHeaderSearchPage(
        hits: hits,
        scannedCount: scanned,
        totalCount: total,
        nextCursor: hasMore
            ? MailCachedHeaderSearchCursor._(
                _cachedSearchOwner,
                revision,
                account,
                query,
                scopeKey,
                last,
              )
            : null,
        browsed: browsed,
        synchronized: synchronized,
        missingMailboxIds: missingMailboxIds,
      );
    });
  });

  static MailHeaderSearchDocument _cachedSearchDocument(
    MailHeaderRecord header,
  ) {
    String addresses(List<MailAddress> values) => values
        .map((value) => '${value.displayName ?? ''} ${value.address}')
        .join(' ');
    return MailHeaderSearchDocument(
      subject: header.envelope.subject,
      sender: addresses(header.envelope.from),
      to: addresses(header.envelope.to),
      cc: addresses(header.envelope.cc),
      date: header.envelope.sentAt,
      isRead: header.flags?.isRead,
      isFlagged: header.flags?.isFlagged,
    );
  }

  Future<void> _checkCachedSearchMemberships(
    MailAccountId account, {
    List<String>? mailboxIds,
  }) async {
    String scope(String alias) => mailboxIds == null
        ? ''
        : ' AND $alias.mailbox IN (${List.filled(mailboxIds.length, '?').join(',')})';
    final args = <Object?>[account.value, ...?mailboxIds];
    for (final table in const ['memberships', 'mailbox_view_members']) {
      final isView = table == 'mailbox_view_members';
      final parentJoin = isView
          ? 'LEFT JOIN mailbox_views v ON v.account=s.account AND v.mailbox=s.mailbox '
          : '';
      final parentCheck = isView
          ? "v.mailbox IS NULL OR typeof(s.position)!='integer' OR "
          : '';
      final invalid = await _rows(
        'SELECT 1 AS invalid FROM $table s '
        'LEFT JOIN messages m ON m.account=s.account AND m.id=s.message '
        'LEFT JOIN mailboxes b ON b.account=s.account AND b.id=s.mailbox '
        '${parentJoin}WHERE s.account=?${scope('s')} AND ($parentCheck m.id IS NULL OR b.id IS NULL OR '
        "typeof(s.mailbox)!='text' OR typeof(s.message)!='text' OR "
        "typeof(b.display_name)!='text' OR length(CAST(s.mailbox AS BLOB))>4096 OR "
        'length(CAST(b.display_name AS BLOB))>16384 OR '
        "typeof(b.is_label)!='integer' OR b.is_label NOT IN (0,1)) LIMIT 1",
        args,
      );
      if (invalid.isNotEmpty) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
    }
    final brokenViews = await _rows(
      'SELECT 1 AS invalid FROM mailbox_views v WHERE v.account=?${scope('v')} AND '
      '(v.header_count!=(SELECT count(*) FROM mailbox_view_members s '
      'WHERE s.account=v.account AND s.mailbox=v.mailbox) OR '
      'EXISTS(SELECT 1 FROM mailbox_view_members s WHERE s.account=v.account '
      'AND s.mailbox=v.mailbox AND (s.position<0 OR s.position>=v.header_count))) '
      'LIMIT 1',
      args,
    );
    if (brokenViews.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
  }

  Future<List<MailMailbox>> _cachedSearchFolders(
    MailAccountId account,
    MailHeaderRecord header,
    int remainingUnits, {
    List<String>? mailboxIds,
  }) async {
    final scope = mailboxIds == null
        ? ''
        : ' AND b.id IN (${List.filled(mailboxIds.length, '?').join(',')})';
    final select =
        'SELECT b.id,b.display_name,b.is_label FROM mailboxes b '
        'JOIN (SELECT mailbox FROM memberships WHERE account=? AND message=? '
        'UNION SELECT mailbox FROM mailbox_view_members '
        'WHERE account=? AND message=?) s ON s.mailbox=b.id WHERE b.account=?$scope';
    final args = <Object?>[
      account.value,
      header.id.value,
      account.value,
      header.id.value,
      account.value,
      ...?mailboxIds,
    ];
    final preflight = (await _rows(
      'SELECT count(*) AS n,coalesce(sum(length(CAST(id AS BLOB))+'
      'length(CAST(display_name AS BLOB))),0) AS bytes FROM ($select)',
      args,
    )).single;
    if (preflight.read<int>('n') == 0) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (preflight.read<int>('n') > _maxFoldersPerMessage ||
        preflight.read<int>('bytes') > remainingUnits * 4) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final folders = <MailMailbox>[];
    var units = 0;
    for (final row in await _rows('$select ORDER BY b.id', args)) {
      final id = row.read<String>('id');
      final name = row.read<String>('display_name');
      if (!MailSavedHeaderSearchFolder.isValidMailboxId(id) ||
          !MailSavedHeaderSearchFolder.isValidDisplayName(name)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      units += id.length + name.length;
      if (units > remainingUnits) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final mailbox = MailMailboxId(id, account: account);
      if (header.remote case MailImapIdentity(mailbox: final remoteMailbox)) {
        if (mailbox != remoteMailbox) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
      }
      folders.add(
        MailMailbox(
          id: mailbox,
          displayName: name,
          isLabel: row.read<int>('is_label') == 1,
        ),
      );
    }
    return folders;
  }
}
