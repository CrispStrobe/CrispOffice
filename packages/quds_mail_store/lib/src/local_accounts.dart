part of 'repository.dart';

/// Bounded local account metadata, deliberately separate from credentials and
/// the account rows that own message content. No method invokes a provider.
extension MailLocalAccountDirectory on SqliteMailRepository {
  static const maxAccounts = 100;

  int _localAccountCodeUnits(MailLocalAccountRecord record) =>
      record.id.length +
      record.endpoint.length +
      record.login.length +
      record.sender.length;

  Future<void> _checkLocalAccountSizes() async {
    // Inspect sizes before transferring stored text to Dart. Corrupt metadata
    // must fail explicitly, rather than disappear from a filtered result.
    // SQLite length(TEXT) stops at NUL and counts code points, not UTF-16 units.
    // Conservative byte ceilings bound transfer before exact Dart validation.
    final bad = (await _rows(
      'SELECT count(*) AS n FROM local_accounts WHERE '
      "typeof(id)!='text' OR typeof(provider)!='text' OR "
      "typeof(endpoint)!='text' OR typeof(login)!='text' OR "
      "typeof(sender)!='text' OR provider NOT IN ('imap','ews','gmail','graph') OR "
      'length(id)>1024 OR length(endpoint)>4096 OR length(login)>4096 OR '
      'length(sender)>320 OR length(CAST(id AS BLOB))>4096 OR '
      'length(CAST(endpoint AS BLOB))>16384 OR '
      'length(CAST(login AS BLOB))>16384 OR '
      'length(CAST(sender AS BLOB))>1280',
    )).single.read<int>('n');
    if (bad != 0) SqliteMailRepository._fail(MailProblemCode.storageFailure);
    // All fields together admit at most 9,536 code units. Cap before
    // multiplication so an enormous valid host budget cannot overflow.
    final transferBudget = limits.maxMetadataCodeUnits < 9536
        ? limits.maxMetadataCodeUnits * 4
        : 38144;
    final overBudget = (await _rows(
      'SELECT count(*) AS n FROM local_accounts WHERE '
      'length(CAST(id AS BLOB))+length(CAST(endpoint AS BLOB))+'
      'length(CAST(login AS BLOB))+length(CAST(sender AS BLOB))>?',
      [transferBudget],
    )).single.read<int>('n');
    if (overBudget != 0) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
  }

  MailLocalAccountRecord _localAccount(QueryRow row) {
    final record = MailLocalAccountRecord(
      id: row.read<String>('id'),
      provider: MailProviderKind.values.byName(row.read<String>('provider')),
      endpoint: row.read<String>('endpoint'),
      login: row.read<String>('login'),
      sender: row.read<String>('sender'),
      lastConnectedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('connected_at'),
        isUtc: true,
      ),
      revision: row.read<int>('revision'),
    );
    if (!record.isValid) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (_localAccountCodeUnits(record) > limits.maxMetadataCodeUnits) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    return record;
  }

  Future<MailResult<List<MailLocalAccountRecord>>> listLocalAccounts() =>
      _run(() async {
        await _checkLocalAccountSizes();
        final rows = await _rows(
          'SELECT * FROM local_accounts ORDER BY connected_at DESC,id LIMIT ?',
          [maxAccounts + 1],
        );
        if (rows.length > maxAccounts) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        return List.unmodifiable(rows.map(_localAccount));
      });

  /// Only a host that has established the connection may register its route.
  /// An existing ID can refresh its timestamp but cannot change its identity.
  /// When [expectedRecord] is supplied, the selected directory snapshot must
  /// still exist with exactly the same identity, revision and connection time.
  /// The comparison and refresh share one transaction, so a selected route
  /// removed during sign-in cannot be recreated by its late completion.
  Future<MailResult<MailUnit>> rememberLocalAccount(
    MailLocalAccountRecord record, {
    MailLocalAccountRecord? expectedRecord,
  }) => _write(() async {
    if (!record.isValid ||
        (expectedRecord != null && !expectedRecord.isValid)) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    if (expectedRecord != null && !expectedRecord.hasSameIdentity(record)) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (_localAccountCodeUnits(record) > limits.maxMetadataCodeUnits) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    await _checkLocalAccountSizes();
    final profileRow = (await _rows(
      'SELECT removed,local_account_revision FROM store_profile',
    )).single;
    if (profileRow.read<int>('removed') != 0) {
      SqliteMailRepository._fail(MailProblemCode.unavailable);
    }
    final counter = profileRow.read<int>('local_account_revision');
    if (counter < 0 || counter > 9007199254740991) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (counter == 9007199254740991) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final existing = await _rows('SELECT * FROM local_accounts WHERE id=?', [
      record.id,
    ]);
    if (expectedRecord != null) {
      if (existing.isEmpty) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
      final current = _localAccount(existing.single);
      if (!current.hasSameIdentity(expectedRecord) ||
          current.revision != expectedRecord.revision ||
          current.lastConnectedAt.millisecondsSinceEpoch !=
              expectedRecord.lastConnectedAt.millisecondsSinceEpoch) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
    }
    if (existing.isNotEmpty) {
      if (!_localAccount(existing.single).hasSameIdentity(record)) {
        SqliteMailRepository._fail(MailProblemCode.conflict);
      }
    } else {
      final count = (await _rows(
        'SELECT count(*) AS n FROM local_accounts',
      )).single.read<int>('n');
      if (count >= maxAccounts) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
    }
    await _db.customStatement(
      'INSERT INTO local_accounts(id,provider,endpoint,login,sender,connected_at,revision) '
      'VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
      'connected_at=MAX(local_accounts.connected_at,excluded.connected_at),'
      'revision=excluded.revision',
      [
        record.id,
        record.provider.name,
        record.endpoint,
        record.login,
        record.sender,
        record.lastConnectedAt.millisecondsSinceEpoch,
        counter + 1,
      ],
    );
    // This counter survives shortcut deletion, preventing remove/re-add ABA
    // even when the wall clock returns the exact previous connection time.
    await _db.customStatement(
      'UPDATE store_profile SET local_account_revision=?',
      [counter + 1],
    );
    return MailUnit.value;
  });

  /// Compare the displayed snapshot before removing just this directory row.
  /// A concurrent reconnect requires a fresh explicit selection.
  Future<MailResult<MailUnit>> forgetLocalAccount(
    MailLocalAccountRecord record,
  ) => _write(() async {
    if (!record.isValid) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    await _checkLocalAccountSizes();
    final rows = await _rows('SELECT * FROM local_accounts WHERE id=?', [
      record.id,
    ]);
    if (rows.isEmpty) SqliteMailRepository._fail(MailProblemCode.conflict);
    final current = _localAccount(rows.single);
    if (!current.hasSameIdentity(record) ||
        current.revision != record.revision ||
        current.lastConnectedAt.millisecondsSinceEpoch !=
            record.lastConnectedAt.millisecondsSinceEpoch) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    await _db.customStatement('DELETE FROM local_accounts WHERE id=?', [
      record.id,
    ]);
    return MailUnit.value;
  });
}
