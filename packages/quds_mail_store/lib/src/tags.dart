part of 'repository.dart';

/// Local tags/categories for retained messages. Tag storage is account-scoped,
/// never contacts a provider and never changes mailbox membership or flags.
extension MailLocalTags on SqliteMailRepository {
  static const int _maxTags = MailTag.maxTagsPerMessage;
  static const int _maxListedTags = 1000;

  Future<List<String>> _messageTagNames(
    MailAccountId account,
    MailMessageId message,
  ) async {
    final rows = await _rows(
      'SELECT name FROM message_tags WHERE account=? AND message=? '
      'ORDER BY tag_key LIMIT ?',
      [account.value, message.value, _maxTags],
    );
    return List.unmodifiable([
      for (final row in rows) row.read<String>('name'),
    ]);
  }

  Future<MailResult<List<MailTag>>> loadMessageTags(
    MailAccountId account,
    MailMessageId message,
  ) => _run(() async {
    await _account(account);
    if (message.value.isEmpty || message.value.length > 4096) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final exists = await _rows(
      'SELECT 1 AS present FROM messages WHERE account=? AND id=?',
      [account.value, message.value],
    );
    if (exists.isEmpty) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final names = await _messageTagNames(account, message);
    return List.unmodifiable(names.map(MailTag.parse));
  });

  Future<MailResult<List<MailTag>>> listMessageTags(
    MailAccountId account, {
    int limit = 200,
  }) => _run(() async {
    await _account(account);
    if (limit < 1 || limit > _maxListedTags) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final rows = await _rows(
      'SELECT tag_key,MIN(name) AS name FROM message_tags WHERE account=? '
      'GROUP BY tag_key ORDER BY tag_key LIMIT ?',
      [account.value, limit],
    );
    if (rows.length > _maxListedTags) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    final result = <MailTag>[];
    var units = 0;
    for (final row in rows) {
      final tag = MailTag.parse(row.read<String>('name'));
      units += tag.name.length;
      if (units > limits.maxMetadataCodeUnits) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      result.add(tag);
    }
    return List.unmodifiable(result);
  });

  /// Replaces the complete local tag set for one retained message.
  Future<MailResult<MailUnit>> setMessageTags(
    MailAccountId account,
    MailMessageId message,
    Iterable<String> tags, {
    MailOperationLease? lease,
  }) => _run(
    () => _commit(() async {
      await _account(account);
      if (lease != null && lease.account != account) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      lease?.checkCurrent();
      if (message.value.isEmpty || message.value.length > 4096) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final List<MailTag> parsed;
      try {
        parsed = MailTag.parseAll(tags);
      } on FormatException {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      if (parsed.length > _maxTags) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final exists = await _rows(
        'SELECT 1 AS present FROM messages WHERE account=? AND id=?',
        [account.value, message.value],
      );
      if (exists.isEmpty) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      await _db.customStatement(
        'DELETE FROM message_tags WHERE account=? AND message=?',
        [account.value, message.value],
      );
      for (final tag in parsed) {
        await _db.customStatement(
          'INSERT INTO message_tags(account,message,tag_key,name) '
          'VALUES(?,?,?,?)',
          [account.value, message.value, tag.key, tag.name],
        );
      }
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      lease?.checkCurrent();
      return MailUnit.value;
    }),
  );

  /// Attaches local tag display names to a bounded header page. One query per
  /// 500 rows; never reads bodies or contacts a provider.
  Future<List<MailHeaderRecord>> attachTagsToHeaders(
    MailAccountId account,
    List<MailHeaderRecord> headers,
  ) async {
    if (headers.isEmpty) return headers;
    final byMessage = <String, List<String>>{};
    for (var start = 0; start < headers.length; start += 500) {
      final page = headers.skip(start).take(500).toList(growable: false);
      final ids = [for (final header in page) header.id.value];
      final rows = await _rows(
        'SELECT message,name FROM message_tags WHERE account=? AND message IN '
        '(${List.filled(ids.length, '?').join(',')}) '
        'ORDER BY message,tag_key LIMIT ?',
        [account.value, ...ids, page.length * MailTag.maxTagsPerMessage],
      );
      for (final row in rows) {
        final tag = MailTag.parse(row.read<String>('name'));
        (byMessage[row.read<String>('message')] ??= <String>[]).add(tag.name);
      }
    }
    return List.unmodifiable([
      for (final header in headers)
        header.copyWith(tags: byMessage[header.id.value] ?? const []),
    ]);
  }

  /// Applies multiple tag replacements in one transaction. The host uses this
  /// for ordered-rule application so a failure leaves every previous tag set
  /// intact. Empty updates are a successful no-op.
  Future<MailResult<MailUnit>> setMessageTagsBatch(
    MailAccountId account,
    Map<MailMessageId, Iterable<String>> updates, {
    MailOperationLease? lease,
  }) => _run(
    () => _commit(() async {
      await _account(account);
      if (lease != null && lease.account != account) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      lease?.checkCurrent();
      if (updates.length > 1000) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      final parsed = <(MailMessageId, List<MailTag>)>[];
      var units = 0;
      for (final entry in updates.entries) {
        final message = entry.key;
        if (message.value.isEmpty || message.value.length > 4096) {
          SqliteMailRepository._fail(MailProblemCode.invalidInput);
        }
        final List<MailTag> tags;
        try {
          tags = MailTag.parseAll(entry.value);
        } on FormatException {
          SqliteMailRepository._fail(MailProblemCode.invalidInput);
        }
        units += tags.fold<int>(0, (total, tag) => total + tag.name.length);
        if (units > limits.maxMetadataCodeUnits) {
          SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
        }
        parsed.add((message, tags));
      }
      for (final (message, _) in parsed) {
        final exists = await _rows(
          'SELECT 1 AS present FROM messages WHERE account=? AND id=?',
          [account.value, message.value],
        );
        if (exists.isEmpty) {
          SqliteMailRepository._fail(MailProblemCode.invalidInput);
        }
      }
      for (final (message, tags) in parsed) {
        await _db.customStatement(
          'DELETE FROM message_tags WHERE account=? AND message=?',
          [account.value, message.value],
        );
        for (final tag in tags) {
          await _db.customStatement(
            'INSERT INTO message_tags(account,message,tag_key,name) '
            'VALUES(?,?,?,?)',
            [account.value, message.value, tag.key, tag.name],
          );
        }
      }
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      lease?.checkCurrent();
      return MailUnit.value;
    }),
  );
}
