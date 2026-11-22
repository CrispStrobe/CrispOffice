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
    this._folderScopeKey,
    this._afterId,
  );

  final Object _owner;
  final Object _revision;
  final MailAccountId _account;
  final String _query;
  final String? _folderScopeKey;
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
  }) : hits = List.unmodifiable(hits),
       browsed = List.unmodifiable(browsed),
       synchronized = List.unmodifiable(synchronized);

  final List<MailCachedHeaderSearchHit> hits;
  final int scannedCount;
  final int totalCount;
  final MailCachedHeaderSearchCursor? nextCursor;
  final List<MailCachedMailboxSummary> browsed;
  final List<MailMailboxSyncSummary> synchronized;
}

/// Account-wide discovery over saved headers, independent of the loaded UI
/// page. It never reads body/blob/draft/Outbox payloads or contacts a provider.
extension MailCachedHeaderSearch on SqliteMailRepository {
  static const maxScanSize = 1000;
  static const maxResultSize = 200;
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

  /// Parses the entire bounded Boolean query before reading any message. The
  /// shared evaluator retains unknown flags/dates and local-calendar semantics.
  /// Stable local IDs provide keyset ordering, not chronological ordering.
  /// [limit] bounds returned matches; [scanLimit] bounds inspected candidates.
  /// A content change, account/query change or different owner rejects a cursor
  /// with conflict instead of skipping or duplicating a changing result set.
  Future<MailResult<MailCachedHeaderSearchPage>> searchCachedHeaders(
    MailAccountId account,
    String query, {
    MailCachedHeaderSearchCursor? cursor,
    List<String>? folderIds,
    int limit = 100,
    int scanLimit = 500,
  }) => _run(() async {
    // Null means legacy all retained folders; an explicit empty set never
    // becomes an account-wide query. Bind every ID, never interpolate it.
    final scopedFolders = folderIds == null
        ? null
        : List<String>.unmodifiable(folderIds);
    if (scopedFolders != null &&
        (scopedFolders.isEmpty ||
            scopedFolders.length > MailSavedHeaderSearch.maxFolderScopes ||
            scopedFolders.toSet().length != scopedFolders.length ||
            scopedFolders.any((id) => !MailSavedHeaderSearch.isValidId(id)))) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final folderScopeKey = scopedFolders == null ? null : jsonEncode(scopedFolders);
    if (limit < 1 ||
        limit > maxResultSize ||
        limit > limits.maxSearchResults ||
        scanLimit < 1 ||
        scanLimit > maxScanSize ||
        scanLimit > limits.maxPageSize) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
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
              cursor._folderScopeKey != folderScopeKey)) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final browsed = switch (await listMailboxViews(account)) {
        MailSuccess<List<MailCachedMailboxSummary>>(:final value) => value,
        MailFailure<List<MailCachedMailboxSummary>>(:final problem) =>
          SqliteMailRepository._fail(problem.code),
      };
      final synchronized = switch (await listSyncMailboxes(account)) {
        MailSuccess<List<MailMailboxSyncSummary>>(:final value) => value,
        MailFailure<List<MailMailboxSyncSummary>>(:final problem) =>
          SqliteMailRepository._fail(problem.code),
      };
      var metadataUnits = 0;
      for (final mailbox in [
        for (final item in browsed) item.mailbox,
        for (final item in synchronized) item.mailbox,
      ]) {
        metadataUnits += mailbox.id.value.length + mailbox.displayName.length;
      }
      if (metadataUnits > _cachedSearchMetadataLimit) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      if (scopedFolders != null) {
        final known = <String>{
          for (final item in browsed) item.mailbox.id.value,
          for (final item in synchronized) item.mailbox.id.value,
        };
        if (scopedFolders.any((id) => !known.contains(id))) {
          SqliteMailRepository._fail(MailProblemCode.unavailable);
        }
      }
      await _checkCachedSearchMemberships(account);
      // Membership tables can both contain one header. EXISTS deduplicates at
      // the message level and scopes both sources to the same exact folder IDs.
      final eligible = scopedFolders == null
          ? _eligible
          : '(EXISTS (SELECT 1 FROM memberships s '
                'WHERE s.account=m.account AND s.message=m.id AND '
                's.mailbox IN (${List.filled(scopedFolders.length, '?').join(',')})) OR '
                'EXISTS (SELECT 1 FROM mailbox_view_members v JOIN mailbox_views w '
                'ON w.account=v.account AND w.mailbox=v.mailbox '
                'WHERE v.account=m.account AND v.message=m.id AND '
                'v.mailbox IN (${List.filled(scopedFolders.length, '?').join(',')})))';
      final scopeArgs = <Object?>[
        if (scopedFolders != null) ...scopedFolders,
        if (scopedFolders != null) ...scopedFolders,
      ];
      final total = (await _rows(
        'SELECT count(*) AS n FROM messages m WHERE m.account=? AND $eligible',
        [account.value, ...scopeArgs],
      )).single.read<int>('n');
      if (total > limits.maxMessagesPerAccount) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      final after = cursor?._afterId;
      final where =
          'm.account=? AND $eligible${after == null ? '' : ' AND m.id>?'}';
      final arguments = <Object?>[
        account.value,
        ...scopeArgs,
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
        final discovered = await _cachedSearchFolders(
          account,
          header,
          _cachedSearchMetadataLimit - metadataUnits,
        );
        final folders = scopedFolders == null
            ? discovered
            : [
                for (final folder in discovered)
                  if (scopedFolders.contains(folder.id.value)) folder,
              ];
        if (folders.isEmpty) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
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
                [account.value, ...scopeArgs, last],
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
                folderScopeKey,
                last,
              )
            : null,
        browsed: browsed,
        synchronized: synchronized,
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

  Future<void> _checkCachedSearchMemberships(MailAccountId account) async {
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
        '${parentJoin}WHERE s.account=? AND ($parentCheck m.id IS NULL OR b.id IS NULL OR '
        "typeof(s.mailbox)!='text' OR typeof(s.message)!='text' OR "
        "typeof(b.display_name)!='text' OR length(CAST(s.mailbox AS BLOB))>4096 OR "
        'length(CAST(b.display_name AS BLOB))>16384 OR '
        "typeof(b.is_label)!='integer' OR b.is_label NOT IN (0,1)) LIMIT 1",
        [account.value],
      );
      if (invalid.isNotEmpty) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
    }
    final brokenViews = await _rows(
      'SELECT 1 AS invalid FROM mailbox_views v WHERE v.account=? AND '
      '(v.header_count!=(SELECT count(*) FROM mailbox_view_members s '
      'WHERE s.account=v.account AND s.mailbox=v.mailbox) OR '
      'EXISTS(SELECT 1 FROM mailbox_view_members s WHERE s.account=v.account '
      'AND s.mailbox=v.mailbox AND (s.position<0 OR s.position>=v.header_count))) '
      'LIMIT 1',
      [account.value],
    );
    if (brokenViews.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
  }

  Future<List<MailMailbox>> _cachedSearchFolders(
    MailAccountId account,
    MailHeaderRecord header,
    int remainingUnits,
  ) async {
    const select =
        'SELECT b.id,b.display_name,b.is_label FROM mailboxes b '
        'JOIN (SELECT mailbox FROM memberships WHERE account=? AND message=? '
        'UNION SELECT mailbox FROM mailbox_view_members '
        'WHERE account=? AND message=?) s ON s.mailbox=b.id WHERE b.account=?';
    final args = <Object?>[
      account.value,
      header.id.value,
      account.value,
      header.id.value,
      account.value,
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
      if (id.length > 1024 || name.length > 4096) {
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
