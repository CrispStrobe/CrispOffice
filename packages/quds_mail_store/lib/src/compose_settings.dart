part of 'repository.dart';

/// Durable plain-text compose preferences belonging to one existing account.
/// This storage never changes drafts, queued messages or remote provider mail.
extension MailComposeSettingsStorage on SqliteMailRepository {
  Future<void> _composeAccount(MailAccountId account) async {
    if (!MailComposeSettings(account: account).isValid) {
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

  int get _composeMetadataBudget =>
      limits.maxMetadataCodeUnits < MailComposeSettings.maxMetadataCodeUnits
      ? limits.maxMetadataCodeUnits
      : MailComposeSettings.maxMetadataCodeUnits;

  String _composeStoredText(QueryRow row, String column) =>
      utf8.decode(row.read<Uint8List>(column), allowMalformed: false);

  Future<MailComposeSettings> _readComposeSettings(
    MailAccountId account,
  ) async {
    // Count, type and byte checks run before transferring user-authored text.
    // SQLite length(TEXT) stops at NUL and counts Unicode code points, so byte
    // lengths bound transfer and the DTO subsequently checks exact UTF-16 units.
    final counts = (await _rows(
      'SELECT (SELECT count(*) FROM account_compose_settings WHERE account=?) '
      'AS settings,(SELECT count(*) FROM account_quick_texts WHERE account=?) '
      'AS quick_texts',
      [account.value, account.value],
    )).single;
    final settingsCount = counts.read<int>('settings');
    final quickTextCount = counts.read<int>('quick_texts');
    if (settingsCount > 1 ||
        quickTextCount > MailComposeSettings.maxQuickTexts ||
        (settingsCount == 0 && quickTextCount != 0)) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (settingsCount == 0) {
      final defaults = MailComposeSettings(account: account);
      if (defaults.metadataCodeUnits > _composeMetadataBudget) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      return defaults;
    }
    final invalid = await _rows(
      'SELECT 1 AS invalid FROM account_compose_settings WHERE account=? AND ('
      "typeof(revision)!='integer' OR revision<1 OR revision>? OR "
      "typeof(signature)!='text' OR length(CAST(signature AS BLOB))>? OR "
      "typeof(signature_new)!='integer' OR signature_new NOT IN (0,1) OR "
      "typeof(signature_replies)!='integer' OR signature_replies NOT IN (0,1)) "
      'UNION ALL SELECT 1 AS invalid FROM account_quick_texts WHERE account=? '
      "AND (typeof(position)!='integer' OR position<0 OR position>=? OR "
      "typeof(id)!='text' OR length(CAST(id AS BLOB))>? OR "
      "typeof(name)!='text' OR length(CAST(name AS BLOB))>? OR "
      "typeof(name_key)!='text' OR length(CAST(name_key AS BLOB))>? OR "
      "typeof(text)!='text' OR length(CAST(text AS BLOB))>?) LIMIT 1",
      [
        account.value,
        MailComposeSettings.maxRevision,
        MailComposeSettings.maxSignatureCodeUnits * 4,
        account.value,
        MailComposeSettings.maxQuickTexts,
        MailQuickText.maxIdCodeUnits * 4,
        MailQuickText.maxNameCodeUnits * 4,
        MailQuickText.maxNameCodeUnits * 16,
        MailQuickText.maxTextCodeUnits * 4,
      ],
    );
    if (invalid.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final bytes = (await _rows(
      'SELECT length(CAST(signature AS BLOB))+'
      '(SELECT coalesce(sum(length(CAST(id AS BLOB))+'
      'length(CAST(name AS BLOB))+length(CAST(name_key AS BLOB))+'
      'length(CAST(text AS BLOB))),0) FROM account_quick_texts WHERE account=?) '
      'AS bytes FROM account_compose_settings WHERE account=?',
      [account.value, account.value],
    )).single.read<int>('bytes');
    if (bytes > _composeMetadataBudget * 4) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    // Transfer the bounded text as bytes, then decode strictly. A corrupt SQLite
    // TEXT value containing invalid UTF-8 must not become replacement characters.
    final row = (await _rows(
      'SELECT revision,CAST(signature AS BLOB) AS signature,'
      'signature_new,signature_replies FROM account_compose_settings '
      'WHERE account=?',
      [account.value],
    )).single;
    final texts = await _rows(
      'SELECT position,CAST(id AS BLOB) AS id,CAST(name AS BLOB) AS name,'
      'CAST(name_key AS BLOB) AS name_key,CAST(text AS BLOB) AS text '
      'FROM account_quick_texts WHERE account=? ORDER BY position LIMIT 33',
      [account.value],
    );
    final quickTexts = <MailQuickText>[];
    for (var index = 0; index < texts.length; index++) {
      final text = texts[index];
      final item = MailQuickText(
        id: _composeStoredText(text, 'id'),
        name: _composeStoredText(text, 'name'),
        text: _composeStoredText(text, 'text'),
      );
      if (text.read<int>('position') != index ||
          item.nameKey != _composeStoredText(text, 'name_key')) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      quickTexts.add(item);
    }
    final settings = MailComposeSettings(
      account: account,
      revision: row.read<int>('revision'),
      signature: _composeStoredText(row, 'signature'),
      signatureForNewMessages: row.read<int>('signature_new') == 1,
      signatureForReplies: row.read<int>('signature_replies') == 1,
      quickTexts: quickTexts,
    );
    if (!settings.isValid) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    if (settings.metadataCodeUnits > _composeMetadataBudget) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    return settings;
  }

  /// Returns revision-zero defaults only for an existing active/logged-out
  /// account with no saved settings. Removed, missing and foreign owners fail.
  Future<MailResult<MailComposeSettings>> loadComposeSettings(
    MailAccountId account,
  ) => _run(
    () => _db.transaction(() async {
      await _composeAccount(account);
      return _readComposeSettings(account);
    }),
  );

  /// Replaces this account's snapshot only at the displayed revision. Both the
  /// supplied DTO and [expectedRevision] must equal the current revision; the
  /// saved revision increases atomically. Resetting preferences is an ordinary
  /// save of empty settings, never deletion/recreation of a revision counter.
  Future<MailResult<MailComposeSettings>> saveComposeSettings(
    MailComposeSettings settings, {
    required int expectedRevision,
  }) => _write(() async {
    if (!settings.isValid ||
        expectedRevision < 0 ||
        expectedRevision > MailComposeSettings.maxRevision ||
        settings.revision != expectedRevision) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    await _composeAccount(settings.account);
    final current = await _readComposeSettings(settings.account);
    if (current.revision != expectedRevision) {
      SqliteMailRepository._fail(MailProblemCode.conflict);
    }
    if (expectedRevision == MailComposeSettings.maxRevision ||
        settings.metadataCodeUnits > _composeMetadataBudget) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final saved = settings.copyWith(revision: expectedRevision + 1);
    await _db.customStatement(
      'INSERT INTO account_compose_settings(account,revision,signature,'
      'signature_new,signature_replies) VALUES(?,?,?,?,?) '
      'ON CONFLICT(account) DO UPDATE SET revision=excluded.revision,'
      'signature=excluded.signature,signature_new=excluded.signature_new,'
      'signature_replies=excluded.signature_replies',
      [
        saved.account.value,
        saved.revision,
        saved.signature,
        saved.signatureForNewMessages ? 1 : 0,
        saved.signatureForReplies ? 1 : 0,
      ],
    );
    await _db.customStatement('DELETE FROM account_quick_texts WHERE account=?', [
      saved.account.value,
    ]);
    for (var index = 0; index < saved.quickTexts.length; index++) {
      final item = saved.quickTexts[index];
      await _db.customStatement(
        'INSERT INTO account_quick_texts(account,position,id,name,name_key,text) '
        'VALUES(?,?,?,?,?,?)',
        [
          saved.account.value,
          index,
          item.id,
          item.name,
          item.nameKey,
          item.text,
        ],
      );
    }
    await _quota(saved.account);
    return saved;
  });
}
