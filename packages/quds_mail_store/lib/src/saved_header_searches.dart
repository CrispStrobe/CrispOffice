part of 'repository.dart';

/// Durable query definitions, separate from saved results and message storage.
/// Account IDs name the host directory's exact scope, not this profile's rows.
extension MailSavedHeaderSearches on SqliteMailRepository {
  static const maxSearches = 100;

  int _savedHeaderSearchUnits(MailSavedHeaderSearch search) =>
      search.id.length +
      search.name.length +
      search.nameKey.length +
      search.query.length +
      search.accountIds.fold<int>(0, (sum, id) => sum + id.length);

  Future<({int revision, bool removed})> _savedHeaderSearchMarker() async {
    final row = (await _rows(
      'SELECT removed,saved_header_search_revision FROM store_profile',
    )).single;
    final removed = row.read<int>('removed');
    final revision = row.read<int>('saved_header_search_revision');
    if ((removed != 0 && removed != 1) ||
        revision < 0 ||
        revision > MailSavedHeaderSearch.maxRevision) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    return (revision: revision, removed: removed == 1);
  }

  Future<List<MailSavedHeaderSearch>> _readSavedHeaderSearches(
    int counter,
  ) async {
    // Counts and byte/type checks precede transfer of any stored text. SQLite
    // length(TEXT) stops at NUL and counts code points; byte caps bound the
    // transfer, then DTO validation checks exact UTF-16 limits and controls.
    final counts = (await _rows(
      'SELECT (SELECT count(*) FROM saved_header_searches) AS searches,'
      '(SELECT count(*) FROM saved_header_search_accounts) AS accounts',
    )).single;
    if (counts.read<int>('searches') > maxSearches ||
        counts.read<int>('accounts') >
            maxSearches * MailSavedHeaderSearch.maxAccountIds) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final invalid = await _rows(
      'SELECT 1 AS invalid FROM saved_header_searches WHERE '
      "typeof(id)!='text' OR typeof(name)!='text' OR "
      "typeof(name_key)!='text' OR typeof(query)!='text' OR "
      'length(CAST(id AS BLOB))>4096 OR '
      'length(CAST(name AS BLOB))>512 OR '
      'length(CAST(name_key AS BLOB))>2048 OR '
      'length(CAST(query AS BLOB))>4096 OR '
      "typeof(revision)!='integer' OR revision<1 OR revision>? "
      'UNION ALL SELECT 1 AS invalid FROM saved_header_search_accounts a '
      'LEFT JOIN saved_header_searches s ON s.id=a.search WHERE '
      "s.id IS NULL OR typeof(a.search)!='text' OR "
      "typeof(a.account_id)!='text' OR typeof(a.position)!='integer' OR "
      'a.position<0 OR a.position>=100 OR '
      'length(CAST(a.search AS BLOB))>4096 OR '
      'length(CAST(a.account_id AS BLOB))>4096 LIMIT 1',
      [counter],
    );
    if (invalid.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final bytes = (await _rows(
      'SELECT (SELECT coalesce(sum(length(CAST(id AS BLOB))+'
      'length(CAST(name AS BLOB))+length(CAST(name_key AS BLOB))+'
      'length(CAST(query AS BLOB))),0) FROM saved_header_searches)+'
      '(SELECT coalesce(sum(length(CAST(account_id AS BLOB))),0) '
      'FROM saved_header_search_accounts) AS bytes',
    )).single.read<int>('bytes');
    // No valid catalog needs more than this, even with every permitted ID at
    // its maximum. Capping before multiplication prevents host-limit overflow.
    const maxCatalogUnits =
        maxSearches * (1024 + 128 + 512 + 1024 + 100 * 1024);
    final budget = limits.maxMetadataCodeUnits < maxCatalogUnits
        ? limits.maxMetadataCodeUnits
        : maxCatalogUnits;
    if (bytes > budget * 4) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final result = <MailSavedHeaderSearch>[];
    final names = <String>{};
    final ids = <String>{};
    var units = 0;
    for (final row in await _rows(
      'SELECT id,name,name_key,query,revision FROM saved_header_searches '
      'ORDER BY name_key,id',
    )) {
      final id = row.read<String>('id');
      final accounts = await _rows(
        'SELECT position,account_id FROM saved_header_search_accounts '
        'WHERE search=? ORDER BY position LIMIT 101',
        [id],
      );
      if (accounts.isEmpty ||
          accounts.length > MailSavedHeaderSearch.maxAccountIds) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      for (var i = 0; i < accounts.length; i++) {
        if (accounts[i].read<int>('position') != i) {
          SqliteMailRepository._fail(MailProblemCode.storageFailure);
        }
      }
      final search = MailSavedHeaderSearch(
        id: id,
        name: row.read<String>('name'),
        query: row.read<String>('query'),
        accountIds: [
          for (final account in accounts) account.read<String>('account_id'),
        ],
        revision: row.read<int>('revision'),
      );
      if (!search.isValid ||
          search.nameKey != row.read<String>('name_key') ||
          !names.add(search.nameKey) ||
          !ids.add(search.id)) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      units += _savedHeaderSearchUnits(search);
      if (units > limits.maxMetadataCodeUnits) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      result.add(search);
    }
    return List<MailSavedHeaderSearch>.unmodifiable(result);
  }

  Future<MailResult<List<MailSavedHeaderSearch>>> listSavedHeaderSearches() =>
      _run(
        () => _db.transaction(() async {
          final marker = await _savedHeaderSearchMarker();
          final searches = await _readSavedHeaderSearches(marker.revision);
          if (marker.removed && searches.isNotEmpty) {
            SqliteMailRepository._fail(MailProblemCode.storageFailure);
          }
          return searches;
        }),
      );

  /// Create with revision zero and no [expectedRevision]. Update requires the
  /// exact displayed revision in both fields. A conflicting ID or name, missing
  /// update target or stale revision returns conflict without changing data.
  ///
  /// Revisions come from a monotonic persisted counter, including after a
  /// definition was deleted. Old callbacks cannot affect a recreated ID.
  Future<MailResult<MailSavedHeaderSearch>> saveSavedHeaderSearch(
    MailSavedHeaderSearch search, {
    int? expectedRevision,
  }) => _write(() async {
    if (!search.isValid ||
        (expectedRevision == null
            ? search.revision != 0
            : expectedRevision < 1 ||
                  expectedRevision > MailSavedHeaderSearch.maxRevision ||
                  search.revision != expectedRevision)) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final marker = await _savedHeaderSearchMarker();
    if (marker.removed) SqliteMailRepository._fail(MailProblemCode.unavailable);
    final current = await _readSavedHeaderSearches(marker.revision);
    final existing = current.where((item) => item.id == search.id).firstOrNull;
    if (expectedRevision == null
        ? existing != null
        : existing == null || existing.revision != expectedRevision) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (current.any(
      (item) => item.id != search.id && item.nameKey == search.nameKey,
    )) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (existing == null && current.length >= maxSearches) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    var units = _savedHeaderSearchUnits(search);
    for (final item in current) {
      if (item.id != search.id) units += _savedHeaderSearchUnits(item);
    }
    if (units > limits.maxMetadataCodeUnits ||
        marker.revision == MailSavedHeaderSearch.maxRevision) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final saved = search.copyWith(revision: marker.revision + 1);
    await _db.customStatement(
      'INSERT INTO saved_header_searches(id,name,name_key,query,revision) '
      'VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
      'name=excluded.name,name_key=excluded.name_key,query=excluded.query,'
      'revision=excluded.revision',
      [saved.id, saved.name, saved.nameKey, saved.query, saved.revision],
    );
    await _db.customStatement(
      'DELETE FROM saved_header_search_accounts WHERE search=?',
      [saved.id],
    );
    for (var i = 0; i < saved.accountIds.length; i++) {
      await _db.customStatement(
        'INSERT INTO saved_header_search_accounts(search,position,account_id) VALUES(?,?,?)',
        [saved.id, i, saved.accountIds[i]],
      );
    }
    await _db.customStatement(
      'UPDATE store_profile SET saved_header_search_revision=?',
      [saved.revision],
    );
    return saved;
  });

  /// Removes only the selected definition. No account, message, draft, Outbox,
  /// cached body, provider state or credentials are changed.
  Future<MailResult<MailUnit>> deleteSavedHeaderSearch(
    String id, {
    required int expectedRevision,
  }) => _write(() async {
    if (!MailSavedHeaderSearch.isValidId(id) ||
        expectedRevision < 1 ||
        expectedRevision > MailSavedHeaderSearch.maxRevision) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final marker = await _savedHeaderSearchMarker();
    if (marker.removed) SqliteMailRepository._fail(MailProblemCode.unavailable);
    final searches = await _readSavedHeaderSearches(marker.revision);
    final existing = searches.where((item) => item.id == id).firstOrNull;
    if (existing == null || existing.revision != expectedRevision) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    await _db.customStatement('DELETE FROM saved_header_searches WHERE id=?', [
      id,
    ]);
    return MailUnit.value;
  });
}
