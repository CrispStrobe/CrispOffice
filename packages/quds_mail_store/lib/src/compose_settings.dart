part of 'repository.dart';

const _composeQuickTextColumns = <String, int>{
  'id': MailQuickText.maxIdCodeUnits,
  'name': MailQuickText.maxNameCodeUnits,
  'name_key': MailQuickText.maxNameCodeUnits * 4,
  'text': MailQuickText.maxTextCodeUnits,
};
const _composeSenderColumns = <String, int>{
  'id': MailSenderIdentity.maxIdCodeUnits,
  'name': MailSenderIdentity.maxNameCodeUnits,
  'name_key': MailSenderIdentity.maxNameCodeUnits * 4,
  'address': MailSenderIdentity.maxAddressCodeUnits,
  'display_name': MailSenderIdentity.maxDisplayNameCodeUnits,
  'reply_to': MailSenderIdentity.maxAddressCodeUnits,
};
const _composeTemplateColumns = <String, int>{
  'id': MailMessageTemplate.maxIdCodeUnits,
  'name': MailMessageTemplate.maxNameCodeUnits,
  'name_key': MailMessageTemplate.maxNameCodeUnits * 4,
  'to_text': MailMessageTemplate.maxRecipientCodeUnits,
  'cc_text': MailMessageTemplate.maxRecipientCodeUnits,
  'bcc_text': MailMessageTemplate.maxRecipientCodeUnits,
  'subject': MailMessageTemplate.maxSubjectCodeUnits,
  'body': MailMessageTemplate.maxBodyCodeUnits,
  'sender_identity': MailSenderIdentity.maxIdCodeUnits,
};

/// Durable compose preferences belonging to one existing account. The complete
/// signature/snippet/sender/template snapshot shares one atomic revision. These
/// local settings never change drafts, queued messages or provider mail.
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

  String? _composeStoredOptionalText(QueryRow row, String column) {
    final bytes = row.readNullable<Uint8List>(column);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: false);
  }

  // Table and column names come only from the fixed internal definitions above.
  // Counts, scalar types and byte lengths are checked before authored content
  // crosses the SQLite boundary. UTF-16 budgets are checked by the DTO after
  // strict UTF-8 decoding; length(TEXT) alone would ignore a trailing NUL.
  Future<({int count, int bytes})> _preflightComposeRows(
    MailAccountId account,
    String table,
    int maximumCount,
    Map<String, int> columns, {
    Set<String> nullableColumns = const {},
  }) async {
    final count = (await _rows(
      'SELECT count(*) AS n FROM $table WHERE account=?',
      [account.value],
    )).single.read<int>('n');
    if (count > maximumCount) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final invalidConditions = <String>[
      "typeof(position)!='integer' OR position<0 OR position>=?",
      for (final column in columns.keys)
        '${nullableColumns.contains(column) ? '$column IS NOT NULL AND ' : ''}'
            "(typeof($column)!='text' OR length(CAST($column AS BLOB))>?)",
    ];
    final invalid = await _rows(
      'SELECT 1 AS invalid FROM $table WHERE account=? AND '
      '(${invalidConditions.map((condition) => '($condition)').join(' OR ')}) '
      'LIMIT 1',
      [
        account.value,
        maximumCount,
        ...columns.values.map((units) => units * 4),
      ],
    );
    if (invalid.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final expression = columns.keys
        .map((column) => 'coalesce(length(CAST($column AS BLOB)),0)')
        .join('+');
    final bytes = (await _rows(
      'SELECT coalesce(sum($expression),0) AS bytes FROM $table WHERE account=?',
      [account.value],
    )).single.read<int>('bytes');
    return (count: count, bytes: bytes);
  }

  Future<List<QueryRow>> _readComposeRows(
    MailAccountId account,
    String table,
    int maximumCount,
    Map<String, int> columns,
  ) => _rows(
    'SELECT position,${columns.keys.map((column) => 'CAST($column AS BLOB) AS $column').join(',')} '
    'FROM $table WHERE account=? ORDER BY position LIMIT ${maximumCount + 1}',
    [account.value],
  );

  Future<MailComposeSettings> _readComposeSettings(
    MailAccountId account,
  ) async {
    final settingsCount = (await _rows(
      'SELECT count(*) AS n FROM account_compose_settings WHERE account=?',
      [account.value],
    )).single.read<int>('n');
    final textsInfo = await _preflightComposeRows(
      account,
      'account_quick_texts',
      MailComposeSettings.maxQuickTexts,
      _composeQuickTextColumns,
    );
    final sendersInfo = await _preflightComposeRows(
      account,
      'account_sender_identities',
      MailComposeSettings.maxSenderIdentities,
      _composeSenderColumns,
    );
    final templatesInfo = await _preflightComposeRows(
      account,
      'account_message_templates',
      MailComposeSettings.maxTemplates,
      _composeTemplateColumns,
      nullableColumns: const {'sender_identity'},
    );
    if (settingsCount > 1 ||
        (settingsCount == 0 &&
            textsInfo.count + sendersInfo.count + templatesInfo.count != 0)) {
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
      "typeof(signature_replies)!='integer' OR signature_replies NOT IN (0,1) OR "
      '(default_sender_identity IS NOT NULL AND '
      "(typeof(default_sender_identity)!='text' OR "
      'length(CAST(default_sender_identity AS BLOB))>?))) LIMIT 1',
      [
        account.value,
        MailComposeSettings.maxRevision,
        MailComposeSettings.maxSignatureCodeUnits * 4,
        MailSenderIdentity.maxIdCodeUnits * 4,
      ],
    );
    if (invalid.isNotEmpty) {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
    final baseBytes = (await _rows(
      'SELECT length(CAST(signature AS BLOB))+'
      'coalesce(length(CAST(default_sender_identity AS BLOB)),0) AS bytes '
      'FROM account_compose_settings WHERE account=?',
      [account.value],
    )).single.read<int>('bytes');
    if (baseBytes + textsInfo.bytes + sendersInfo.bytes + templatesInfo.bytes >
        _composeMetadataBudget * 4) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final row = (await _rows(
      'SELECT revision,CAST(signature AS BLOB) AS signature,'
      'signature_new,signature_replies,'
      'CAST(default_sender_identity AS BLOB) AS default_sender_identity '
      'FROM account_compose_settings WHERE account=?',
      [account.value],
    )).single;
    final texts = await _readComposeRows(
      account,
      'account_quick_texts',
      MailComposeSettings.maxQuickTexts,
      _composeQuickTextColumns,
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
    final senders = await _readComposeRows(
      account,
      'account_sender_identities',
      MailComposeSettings.maxSenderIdentities,
      _composeSenderColumns,
    );
    final senderIdentities = <MailSenderIdentity>[];
    for (var index = 0; index < senders.length; index++) {
      final sender = senders[index];
      final item = MailSenderIdentity(
        id: _composeStoredText(sender, 'id'),
        name: _composeStoredText(sender, 'name'),
        address: _composeStoredText(sender, 'address'),
        displayName: _composeStoredText(sender, 'display_name'),
        replyTo: _composeStoredText(sender, 'reply_to'),
      );
      if (sender.read<int>('position') != index ||
          item.nameKey != _composeStoredText(sender, 'name_key')) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      senderIdentities.add(item);
    }
    final storedTemplates = await _readComposeRows(
      account,
      'account_message_templates',
      MailComposeSettings.maxTemplates,
      _composeTemplateColumns,
    );
    final templates = <MailMessageTemplate>[];
    for (var index = 0; index < storedTemplates.length; index++) {
      final template = storedTemplates[index];
      final item = MailMessageTemplate(
        id: _composeStoredText(template, 'id'),
        name: _composeStoredText(template, 'name'),
        to: _composeStoredText(template, 'to_text'),
        cc: _composeStoredText(template, 'cc_text'),
        bcc: _composeStoredText(template, 'bcc_text'),
        subject: _composeStoredText(template, 'subject'),
        body: _composeStoredText(template, 'body'),
        senderIdentityId: _composeStoredOptionalText(
          template,
          'sender_identity',
        ),
      );
      if (template.read<int>('position') != index ||
          item.nameKey != _composeStoredText(template, 'name_key')) {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      templates.add(item);
    }
    final settings = MailComposeSettings(
      account: account,
      revision: row.read<int>('revision'),
      signature: _composeStoredText(row, 'signature'),
      signatureForNewMessages: row.read<int>('signature_new') == 1,
      signatureForReplies: row.read<int>('signature_replies') == 1,
      quickTexts: quickTexts,
      senderIdentities: senderIdentities,
      templates: templates,
      defaultSenderIdentityId: _composeStoredOptionalText(
        row,
        'default_sender_identity',
      ),
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
      'signature_new,signature_replies,default_sender_identity) VALUES(?,?,?,?,?,?) '
      'ON CONFLICT(account) DO UPDATE SET revision=excluded.revision,'
      'signature=excluded.signature,signature_new=excluded.signature_new,'
      'signature_replies=excluded.signature_replies,'
      'default_sender_identity=excluded.default_sender_identity',
      [
        saved.account.value,
        saved.revision,
        saved.signature,
        saved.signatureForNewMessages ? 1 : 0,
        saved.signatureForReplies ? 1 : 0,
        saved.defaultSenderIdentityId,
      ],
    );
    // Templates reference identities. Replace both collections within the same
    // transaction, removing dependent rows first and inserting owners first.
    for (final table in [
      'account_message_templates',
      'account_sender_identities',
      'account_quick_texts',
    ]) {
      await _db.customStatement('DELETE FROM $table WHERE account=?', [
        saved.account.value,
      ]);
    }
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
    for (var index = 0; index < saved.senderIdentities.length; index++) {
      final item = saved.senderIdentities[index];
      await _db.customStatement(
        'INSERT INTO account_sender_identities(account,position,id,name,name_key,'
        'address,display_name,reply_to) VALUES(?,?,?,?,?,?,?,?)',
        [
          saved.account.value,
          index,
          item.id,
          item.name,
          item.nameKey,
          item.address,
          item.displayName,
          item.replyTo,
        ],
      );
    }
    for (var index = 0; index < saved.templates.length; index++) {
      final item = saved.templates[index];
      await _db.customStatement(
        'INSERT INTO account_message_templates(account,position,id,name,name_key,'
        'to_text,cc_text,bcc_text,subject,body,sender_identity) '
        'VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          saved.account.value,
          index,
          item.id,
          item.name,
          item.nameKey,
          item.to,
          item.cc,
          item.bcc,
          item.subject,
          item.body,
          item.senderIdentityId,
        ],
      );
    }
    await _quota(saved.account);
    return saved;
  });
}
