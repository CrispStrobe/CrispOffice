@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('conversations', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _inbox = MailMailboxId('inbox', account: _account);
final _sent = MailMailboxId('sent', account: _account);
final _now = DateTime.utc(2026, 11, 22, 12);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

MailHeaderRecord _header(
  String id,
  MailMailboxId mailbox, {
  required String subject,
  String? messageId,
  String? inReplyTo,
  List<String> references = const [],
}) => MailHeaderRecord(
  id: MailMessageId(id),
  remote: MailImapIdentity(
    mailbox: mailbox,
    uidValidity: 9,
    uid: id.hashCode & 0xffff,
  ),
  envelope: MailEnvelope(
    subject: subject,
    messageId: messageId,
    inReplyTo: inReplyTo,
    references: references,
  ),
);

void main() {
  late sqlite.Database database;
  late SqliteMailRepository store;

  Future<SqliteMailRepository> open() async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase.opened(database, closeUnderlyingOnClose: false),
      profile: _profile,
      clock: () => _now,
    ),
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Conversations',
        ),
      ),
    );
  });

  tearDown(() async {
    await store.close();
    database.close();
  });

  test('persists one conversation across folders and search', () async {
    final root = _header(
      'sent-root',
      _sent,
      subject: 'Plan',
      messageId: '<root@example.test>',
    );
    final reply = _header(
      'inbox-reply',
      _inbox,
      subject: 'Re: Plan',
      messageId: '<reply@example.test>',
      references: const ['<root@example.test>'],
    );
    final noIds = _header('inbox-local', _inbox, subject: 'Unthreaded');
    final lease = MailAccountSession(_account).begin();
    _value(
      await store.saveMailboxView(
        MailMailbox(id: _sent, displayName: 'Sent'),
        [root],
        expectedRevision: null,
        hasMore: false,
        lease: lease,
      ),
    );
    _value(
      await store.saveMailboxView(
        MailMailbox(id: _inbox, displayName: 'Inbox'),
        [reply, noIds],
        expectedRevision: null,
        hasMore: false,
        lease: lease,
      ),
    );

    final inbox = _value(await store.loadMailboxView(_inbox))!.headers;
    final sent = _value(await store.loadMailboxView(_sent))!.headers;
    expect(inbox[0].conversationId, '<root@example.test>');
    expect(sent.single.conversationId, '<root@example.test>');
    expect(inbox[1].conversationId, 'local:inbox-local');

    final hits = _value(
      await store.searchCachedHeaders(_account, 'subject:Plan'),
    ).hits;
    expect(hits.map((hit) => hit.header.conversationId).toSet(), {
      '<root@example.test>',
    });
    expect(hits, hasLength(2));
  });

  test('v19 upgrade backfills persisted conversation keys', () async {
    _value(
      await store.saveMailboxView(
        MailMailbox(id: _inbox, displayName: 'Inbox'),
        [
          _header(
            'reply',
            _inbox,
            subject: 'Re: Report',
            messageId: '<reply@example.test>',
            inReplyTo: '<root@example.test>',
          ),
        ],
        expectedRevision: null,
        hasMore: false,
        lease: MailAccountSession(_account).begin(),
      ),
    );
    await store.close();
    database.execute('DROP INDEX IF EXISTS messages_conversation');
    database.execute('ALTER TABLE messages DROP COLUMN conversation');
    database.userVersion = 19;

    store = await open();
    final header = _value(await store.loadMailboxView(_inbox))!.headers.single;
    expect(header.conversationId, '<root@example.test>');
    expect(database.select('PRAGMA user_version').single.values.single, 20);
  });
}
