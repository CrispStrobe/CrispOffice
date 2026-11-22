part of 'repository.dart';

/// Account routing preferences are independent of cached mailbox lifetime.
/// A retained path is never proof that a provider folder still exists.
extension _MailArchiveSettingsStorage on SqliteMailRepository {
  Future<void> _archiveSettingsAccount(MailAccountId account) async {
    if (!MailArchiveDestinationSettings(account: account).isValid) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final row = await _account(account);
    if (!const ['active', 'loggedOut'].contains(row.read<String>('state'))) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final marker = (await _rows('SELECT removed FROM store_profile')).single;
    if (marker.read<int>('removed') != 0) {
      SqliteMailRepository._fail(MailProblemCode.unavailable);
    }
  }

  int get _archiveSettingsMetadataBudget =>
      limits.maxMetadataCodeUnits <
          MailArchiveDestinationSettings.maxMetadataCodeUnits
      ? limits.maxMetadataCodeUnits
      : MailArchiveDestinationSettings.maxMetadataCodeUnits;

  Future<MailArchiveDestinationSettings> _readArchiveSettings(
    MailAccountId account,
  ) async {
    // Read only bounded type/size metadata before transferring folder text.
    // length(TEXT) alone is unsafe for NUL, malformed UTF-8 and astral text.
    final rows = await _rows(
      'SELECT typeof(revision) AS revision_type,'
      "CASE WHEN typeof(revision)='integer' THEN revision ELSE NULL END AS revision,"
      'typeof(destination) AS destination_type,'
      'length(CAST(destination AS BLOB)) AS destination_bytes '
      'FROM account_archive_settings WHERE account=? LIMIT 2',
      [account.value],
    );
    if (rows.length > 1) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (rows.isEmpty) {
      final defaults = MailArchiveDestinationSettings(account: account);
      if (defaults.metadataCodeUnits > _archiveSettingsMetadataBudget) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      return defaults;
    }
    final row = rows.single;
    final type = row.read<String>('destination_type');
    if (row.read<String>('revision_type') != 'integer' ||
        row.read<int>('revision') < 1 ||
        row.read<int>('revision') >
            MailArchiveDestinationSettings.maxRevision ||
        (type != 'null' && type != 'text') ||
        (type == 'text' &&
            (row.read<int>('destination_bytes') < 1 ||
                row.read<int>('destination_bytes') >
                    MailArchiveDestinationSettings.maxDestinationCodeUnits *
                        4))) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (type == 'text' &&
        row.read<int>('destination_bytes') >
            _archiveSettingsMetadataBudget * 4) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    MailMailboxId? destination;
    if (type == 'text') {
      final text = (await _rows(
        'SELECT CAST(destination AS BLOB) AS destination '
        'FROM account_archive_settings WHERE account=?',
        [account.value],
      )).single;
      destination = MailMailboxId(
        utf8.decode(text.read<Uint8List>('destination'), allowMalformed: false),
        account: account,
      );
    }
    final settings = MailArchiveDestinationSettings(
      account: account,
      revision: row.read<int>('revision'),
      destination: destination,
    );
    if (!settings.isValid) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (settings.metadataCodeUnits > _archiveSettingsMetadataBudget) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    return settings;
  }

  Future<MailResult<MailArchiveDestinationSettings>> _loadArchiveSettings(
    MailAccountId account,
  ) => _run(
    () => _db.transaction(() async {
      await _archiveSettingsAccount(account);
      return _readArchiveSettings(account);
    }),
  );

  Future<MailResult<MailArchiveDestinationSettings>> _saveArchiveSettings(
    MailArchiveDestinationSettings settings, {
    required int expectedRevision,
  }) => _write(() async {
    if (!settings.isValid ||
        expectedRevision < 0 ||
        expectedRevision > MailArchiveDestinationSettings.maxRevision ||
        settings.revision != expectedRevision) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    await _archiveSettingsAccount(settings.account);
    final current = await _readArchiveSettings(settings.account);
    if (current.revision != expectedRevision) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (expectedRevision == MailArchiveDestinationSettings.maxRevision ||
        settings.metadataCodeUnits > _archiveSettingsMetadataBudget) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final saved = settings.copyWith(revision: expectedRevision + 1);
    await _db.customStatement(
      'INSERT INTO account_archive_settings(account,revision,destination) '
      'VALUES(?,?,?) ON CONFLICT(account) DO UPDATE SET '
      'revision=excluded.revision,destination=excluded.destination',
      [saved.account.value, saved.revision, saved.destination?.value],
    );
    await _quota(saved.account);
    return saved;
  });
}
