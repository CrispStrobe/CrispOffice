import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

MailSavedHeaderSearch _search({
  String id = 'view',
  String name = 'Important mail',
  String query = 'is:unread OR is:flagged',
  List<String> accountIds = const ['account-a', 'account-b'],
  int revision = 0,
}) => MailSavedHeaderSearch(
  id: id,
  name: name,
  query: query,
  accountIds: accountIds,
  revision: revision,
);

void main() {
  test('owns the exact ordered scope and does not expose mutable aliases', () {
    final accounts = ['second', 'first'];
    final saved = _search(accountIds: accounts);
    accounts
      ..clear()
      ..add('new-account');
    expect(saved.accountIds, ['second', 'first']);
    expect(() => saved.accountIds.add('new-account'), throwsUnsupportedError);
    expect(saved.isValid, isTrue);
  });

  test('accepts an empty query for all headers in the explicit scope', () {
    expect(_search(query: '').isValid, isTrue);
    expect(_search(query: '').accountIds, ['account-a', 'account-b']);
  });

  test('copy retains ID and revision while replacing independent values', () {
    final original = _search(revision: 67);
    final next = original.copyWith(name: 'Flagged', query: 'is:flagged');
    expect(next.id, original.id);
    expect(next.revision, 67);
    expect(next.accountIds, original.accountIds);
    expect(next.name, 'Flagged');
    expect(next.query, 'is:flagged');
    expect(original.name, 'Important mail');
    expect(next.copyWith(accountIds: ['other'], revision: 68).revision, 68);
  });

  test(
    'names have explicit case-insensitive keys and redacted diagnostics',
    () {
      expect(_search(name: 'ÄRGER').nameKey, 'ärger');
      expect(_search(name: 'رسائل').nameKey, 'رسائل');
      expect(_search().toString(), 'MailSavedHeaderSearch(redacted)');
    },
  );

  for (final (label, search) in [
    ('missing ID', _search(id: '')),
    ('long ID', _search(id: 'x' * 1025)),
    ('control in ID', _search(id: 'bad\nidentity')),
    ('missing name', _search(name: '')),
    ('name whitespace', _search(name: ' ')),
    ('untrimmed name', _search(name: ' Name ')),
    ('long name', _search(name: 'x' * 129)),
    ('long Unicode name', _search(name: '📨' * 65)),
    ('control in name', _search(name: 'Safe\u0000Hidden')),
    ('empty scope', _search(accountIds: [])),
    ('duplicate scope', _search(accountIds: ['a', 'a'])),
    ('untrimmed account', _search(accountIds: [' a'])),
    ('long account', _search(accountIds: ['a' * 1025])),
    ('too many accounts', _search(accountIds: List.generate(101, (i) => '$i'))),
    ('malformed Boolean query', _search(query: '(is:read OR)')),
    ('long query', _search(query: 'x' * 1025)),
    ('negative revision', _search(revision: -1)),
    ('inexact JS revision', _search(revision: 9007199254740992)),
  ]) {
    test('rejects $label', () => expect(search.isValid, isFalse));
  }

  test('admits exact name, identity, account-count and revision ceilings', () {
    expect(
      _search(
        id: 'i' * 1024,
        name: '📨' * 64,
        accountIds: List.generate(100, (i) => '${'a' * 1020}$i'),
        revision: MailSavedHeaderSearch.maxRevision,
      ).isValid,
      isTrue,
    );
  });

  for (final (kind, surrogate) in [('high', '\uD800'), ('low', '\uDC00')]) {
    for (final field in ['id', 'name', 'query', 'account']) {
      test('refuses lone $kind surrogate in $field before persistence', () {
        final broken = 'prefix${surrogate}suffix';
        final search = _search(
          id: field == 'id' ? broken : 'view',
          name: field == 'name' ? broken : 'Saved search',
          query: field == 'query' ? broken : '',
          accountIds: [field == 'account' ? broken : 'account'],
        );
        expect(search.isValid, isFalse);
      });
    }
  }

  test('valid surrogate pairs remain exact in every definition field', () {
    final search = _search(
      id: 'view-📨',
      name: 'رسائل 📨',
      query: 'subject:"📨"',
      accountIds: ['account-📨'],
    );
    expect(search.isValid, isTrue);
    expect(search.id, 'view-\uD83D\uDCE8');
    expect(search.name, 'رسائل \uD83D\uDCE8');
    expect(search.query, 'subject:"\uD83D\uDCE8"');
    expect(search.accountIds, ['account-\uD83D\uDCE8']);
  });
}
