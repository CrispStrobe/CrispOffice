@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('rules', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('inbox', account: _account);
final _now = DateTime.utc(2026, 11, 22, 12);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailHeaderRecord _header(int uid) => MailHeaderRecord(
  id: MailMessageId('message-$uid'),
  remote: MailImapIdentity(mailbox: _mailbox, uidValidity: 9, uid: uid),
  envelope: MailEnvelope(subject: 'Subject $uid'),
);

MailRule _rule(
  String id,
  int position, {
  String query = 'subject:Subject',
  bool enabled = true,
  List<String> add = const ['Work'],
  List<String> remove = const [],
}) => MailRule.parse(
  id: id,
  name: 'Rule $id',
  query: query,
  enabled: enabled,
  position: position,
  addTags: add,
  removeTags: remove,
);

void main() {
  late sqlite.Database database;
  late SqliteMailRepository store;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: _profile,
        clock: () => _now,
      ),
    );
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Rules',
        ),
      ),
    );
    _value(
      await store.saveMailboxView(
        MailMailbox(id: _mailbox, displayName: 'Inbox'),
        [_header(1), _header(2)],
        expectedRevision: null,
        hasMore: false,
        lease: MailAccountSession(_account).begin(),
      ),
    );
  });

  tearDown(() async {
    await store.close();
    database.close();
  });

  test('persists and replaces ordered rules atomically', () async {
    final lease = MailAccountSession(_account).begin();
    _value(
      await store.replaceMailRules(_account, [
        _rule('b', 1, query: 'tag:work', add: ['Receipts']),
        _rule('a', 0),
      ], lease: lease),
    );
    final first = _value(await store.listMailRules(_account));
    expect(first.map((rule) => rule.id), ['a', 'b']);
    expect(first.first.addTags.single.name, 'Work');
    expect(first.last.query, 'tag:work');

    _value(
      await store.replaceMailRules(_account, [
        _rule('c', 0, enabled: false, add: const [], remove: ['Work']),
      ]),
    );
    final second = _value(await store.listMailRules(_account));
    expect(second.single.id, 'c');
    expect(second.single.enabled, isFalse);
    expect(second.single.removeTags.single.name, 'Work');
  });

  test('rejects invalid or duplicate rule sets without replacing', () async {
    _value(await store.replaceMailRules(_account, [_rule('a', 0)]));
    _problem(
      await store.replaceMailRules(_account, [_rule('a', 0), _rule('a', 1)]),
      MailProblemCode.invalidInput,
    );
    final after = _value(await store.listMailRules(_account));
    expect(after.single.id, 'a');
  });

  test('rules stay inside their account', () async {
    final other = MailAccountId('other', profile: _profile);
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: other,
          provider: MailProviderKind.imap,
          displayName: 'Other',
        ),
      ),
    );
    _value(await store.replaceMailRules(_account, [_rule('a', 0)]));
    expect(_value(await store.listMailRules(other)), isEmpty);
  });

  test('v17 upgrade adds tags and rules and preserves existing data', () async {
    await store.close();
    database.execute('DROP TABLE message_tags');
    database.execute('DROP TABLE mail_rules');
    database.execute('DROP INDEX IF EXISTS messages_conversation');
    database.execute('ALTER TABLE messages DROP COLUMN conversation');
    database.userVersion = 17;

    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: _profile,
        clock: () => _now,
      ),
    );
    expect(_value(await store.listMailRules(_account)), isEmpty);
    expect(
      _value(await store.loadMessageTags(_account, MailMessageId('message-1'))),
      isEmpty,
    );
    expect(database.select('PRAGMA user_version').single.values.single, 21);
    expect(
      database
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('message_tags','mail_rules') ORDER BY name",
          )
          .map((row) => row['name']),
      ['mail_rules', 'message_tags'],
    );
  });

  test('v18 upgrade adds rules and preserves existing data', () async {
    await store.close();
    database.execute('DROP INDEX IF EXISTS mail_rules_order');
    database.execute('DROP TABLE mail_rules');
    database.execute('DROP INDEX IF EXISTS messages_conversation');
    database.execute('ALTER TABLE messages DROP COLUMN conversation');
    database.userVersion = 18;

    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: _profile,
        clock: () => _now,
      ),
    );
    expect(_value(await store.listMailRules(_account)), isEmpty);
    expect(database.select('PRAGMA user_version').single.values.single, 21);
    expect(
      database
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='mail_rules'",
          )
          .single['name'],
      'mail_rules',
    );
  });

  test(
    'batch tag updates are atomic and preserve untouched messages',
    () async {
      _value(
        await store.setMessageTags(_account, MailMessageId('message-2'), [
          'Keep',
        ]),
      );
      _value(
        await store.setMessageTagsBatch(_account, {
          MailMessageId('message-1'): ['Work', 'Receipts'],
          MailMessageId('message-2'): ['Travel'],
        }),
      );
      expect(
        _value(
          await store.loadMessageTags(_account, MailMessageId('message-1')),
        ).map((tag) => tag.name),
        ['Receipts', 'Work'],
      );
      expect(
        _value(
          await store.loadMessageTags(_account, MailMessageId('message-2')),
        ).map((tag) => tag.name),
        ['Travel'],
      );

      _problem(
        await store.setMessageTagsBatch(_account, {
          MailMessageId('message-1'): ['Changed'],
          MailMessageId('missing'): ['Work'],
        }),
        MailProblemCode.invalidInput,
      );
      expect(
        _value(
          await store.loadMessageTags(_account, MailMessageId('message-1')),
        ).map((tag) => tag.name),
        ['Receipts', 'Work'],
      );
      expect(
        _value(
          await store.loadMessageTags(_account, MailMessageId('message-2')),
        ).map((tag) => tag.name),
        ['Travel'],
      );
    },
  );
}
