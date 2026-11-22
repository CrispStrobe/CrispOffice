part of 'repository.dart';

/// Ordered local mail rules. Persistence is account-scoped and transactional;
/// rules never contact a provider or mutate messages until the host explicitly
/// previews/applies them.
extension MailLocalRules on SqliteMailRepository {
  static const int _maxRules = MailRule.maxRules;
  static const int _maxRulePayload = 256 * 1024;

  Future<MailResult<List<MailRule>>> listMailRules(
    MailAccountId account, {
    int limit = MailRule.maxRules,
  }) => _run(() async {
    await _account(account);
    if (limit < 1 || limit > _maxRules) {
      SqliteMailRepository._fail(MailProblemCode.invalidInput);
    }
    final rows = await _rows(
      'SELECT id,position,name,enabled,query,add_tags,remove_tags '
      'FROM mail_rules WHERE account=? ORDER BY position,id LIMIT ?',
      [account.value, limit],
    );
    final result = <MailRule>[];
    var units = 0;
    for (final row in rows) {
      final id = row.read<String>('id');
      final name = row.read<String>('name');
      final query = row.read<String>('query');
      final add = _ruleTags(row.read<String>('add_tags'), id);
      final remove = _ruleTags(row.read<String>('remove_tags'), id);
      try {
        result.add(
          MailRule.parse(
            id: id,
            name: name,
            query: query,
            enabled: row.read<int>('enabled') == 1,
            position: row.read<int>('position'),
            addTags: add,
            removeTags: remove,
          ),
        );
      } on FormatException {
        SqliteMailRepository._fail(MailProblemCode.storageFailure);
      }
      units += _ruleUnits(result.last);
      if (units > _maxRulePayload) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
    }
    if (rows.length > _maxRules) {
      SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
    }
    return List.unmodifiable(result);
  });

  static List<String> _ruleTags(String encoded, String ruleId) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List || decoded.length > MailRule.maxActions) {
        throw const FormatException('Invalid rule tags.');
      }
      final result = <String>[];
      for (final value in decoded) {
        if (value is! String) throw const FormatException('Invalid rule tag.');
        result.add(value);
      }
      return result;
    } on FormatException {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    } on Object {
      SqliteMailRepository._fail(MailProblemCode.storageFailure);
    }
  }

  static int _ruleUnits(MailRule rule) =>
      rule.id.length +
      rule.name.length +
      rule.query.length +
      rule.addTags.fold<int>(0, (total, tag) => total + tag.name.length) +
      rule.removeTags.fold<int>(0, (total, tag) => total + tag.name.length);

  /// Replaces the complete ordered rule set for one account. Positions must be
  /// unique and fit [MailRule.maxRules]. The whole replacement is atomic.
  Future<MailResult<MailUnit>> replaceMailRules(
    MailAccountId account,
    Iterable<MailRule> rules, {
    MailOperationLease? lease,
  }) => _run(
    () => _commit(() async {
      await _account(account);
      if (lease != null && lease.account != account) {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      lease?.checkCurrent();
      final MailRuleSet set;
      try {
        set = MailRuleSet.parse(rules);
      } on FormatException {
        SqliteMailRepository._fail(MailProblemCode.invalidInput);
      }
      var units = 0;
      for (final rule in set.rules) {
        units += _ruleUnits(rule);
      }
      if (units > _maxRulePayload) {
        SqliteMailRepository._fail(MailProblemCode.quotaExceeded);
      }
      await _db.customStatement('DELETE FROM mail_rules WHERE account=?', [
        account.value,
      ]);
      for (final rule in set.rules) {
        await _db.customStatement(
          'INSERT INTO mail_rules(account,id,position,name,enabled,query,'
          'add_tags,remove_tags) VALUES(?,?,?,?,?,?,?,?)',
          [
            account.value,
            rule.id,
            rule.position,
            rule.name,
            rule.enabled ? 1 : 0,
            rule.query,
            jsonEncode([for (final tag in rule.addTags) tag.name]),
            jsonEncode([for (final tag in rule.removeTags) tag.name]),
          ],
        );
      }
      await _db.fault(MailStoreCheckpoint.beforeCommit);
      lease?.checkCurrent();
      return MailUnit.value;
    }),
  );
}
