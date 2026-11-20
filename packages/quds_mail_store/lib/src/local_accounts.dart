part of 'repository.dart';

/// Bounded local account metadata, deliberately separate from credentials and
/// the account rows that own message content. No method invokes a provider.
extension MailLocalAccountDirectory on SqliteMailRepository {
  static const maxAccounts = 100;

  Future<void> _checkLocalAccountSizes() async {
    // Inspect sizes before transferring stored text to Dart. Corrupt metadata
    // must fail explicitly, rather than disappear from a filtered result.
    final bad = (await _rows(
      'SELECT count(*) AS n FROM local_accounts WHERE '
      'length(id)>1024 OR length(endpoint)>4096 OR length(login)>4096 OR '
      'length(sender)>320 OR length(id)+length(endpoint)+length(login)+'
      'length(sender)>?',
      [limits.maxMetadataCodeUnits],
    )).single.read<int>('n');
    if (bad != 0) SqliteMailRepository._fail(MailProblemCode.storageFailure);
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
  Future<MailResult<MailUnit>> rememberLocalAccount(
    MailLocalAccountRecord record,
  ) => _write(() async {
    if (!record.isValid) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    if (record.id.length +
            record.endpoint.length +
            record.login.length +
            record.sender.length >
        limits.maxMetadataCodeUnits) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    await _checkLocalAccountSizes();
    final profileRow = (await _rows(
      'SELECT removed FROM store_profile',
    )).single;
    if (profileRow.read<int>('removed') != 0) {
      SqliteMailRepository._fail(MailProblemCode.unavailable);
    }
    final existing = await _rows('SELECT * FROM local_accounts WHERE id=?', [
      record.id,
    ]);
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
      'INSERT INTO local_accounts(id,provider,endpoint,login,sender,connected_at) '
      'VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
      'connected_at=MAX(local_accounts.connected_at,excluded.connected_at),'
      'revision=local_accounts.revision+1',
      [
        record.id,
        record.provider.name,
        record.endpoint,
        record.login,
        record.sender,
        record.lastConnectedAt.millisecondsSinceEpoch,
      ],
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
