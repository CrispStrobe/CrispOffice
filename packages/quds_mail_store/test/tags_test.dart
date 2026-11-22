@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('tags', hostId: 'test-office');
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
          displayName: 'Tags',
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

  test('sets, loads, lists and replaces local tags', () async {
    final lease = MailAccountSession(_account).begin();
    _value(
      await store.setMessageTags(_account, MailMessageId('message-1'), [
        ' Work ',
        'work',
        'Receipts',
      ], lease: lease),
    );
    final tags = _value(
      await store.loadMessageTags(_account, MailMessageId('message-1')),
    );
    expect(tags.map((tag) => tag.name), ['Receipts', 'Work']);
    expect(
      _value(await store.listMessageTags(_account)).map((tag) => tag.name),
      ['Receipts', 'Work'],
    );

    _value(
      await store.setMessageTags(_account, MailMessageId('message-1'), [
        'Travel',
      ], lease: lease),
    );
    expect(
      _value(
        await store.loadMessageTags(_account, MailMessageId('message-1')),
      ).map((tag) => tag.name),
      ['Travel'],
    );
    expect(
      _value(await store.loadMessageTags(_account, MailMessageId('message-2'))),
      isEmpty,
    );
  });

  test('cached search matches complete tags without reading bodies', () async {
    _value(
      await store.setMessageTags(_account, MailMessageId('message-1'), [
        'Work',
        'Receipts',
      ]),
    );
    final work = _value(await store.searchCachedHeaders(_account, 'tag:work'));
    expect(work.hits.single.header.id.value, 'message-1');
    expect(
      _value(await store.searchCachedHeaders(_account, 'tag:wor')).hits,
      isEmpty,
    );
    expect(
      _value(
        await store.searchCachedHeaders(
          _account,
          'subject:"Subject 1" AND tag:receipts',
        ),
      ).hits.single.header.id.value,
      'message-1',
    );
    expect(
      _value(
        await store.searchCachedHeaders(_account, 'tag:work OR tag:none'),
      ).hits.single.header.id.value,
      'message-1',
    );
  });

  test('rejects invalid tags and missing messages atomically', () async {
    final before = _value(
      await store.loadMessageTags(_account, MailMessageId('message-1')),
    );
    _problem(
      await store.setMessageTags(_account, MailMessageId('message-1'), [
        'ok',
        'bad\ntag',
      ]),
      MailProblemCode.invalidInput,
    );
    _problem(
      await store.setMessageTags(_account, MailMessageId('missing'), ['ok']),
      MailProblemCode.invalidInput,
    );
    expect(
      _value(await store.loadMessageTags(_account, MailMessageId('message-1'))),
      before,
    );
  });

  test('tags stay inside their account', () async {
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
    _value(
      await store.setMessageTags(_account, MailMessageId('message-1'), [
        'Work',
      ]),
    );
    expect(
      _value(await store.listMessageTags(other)).map((tag) => tag.name),
      isEmpty,
    );
    _problem(
      await store.setMessageTags(other, MailMessageId('message-1'), ['Work']),
      MailProblemCode.invalidInput,
    );
  });
}
