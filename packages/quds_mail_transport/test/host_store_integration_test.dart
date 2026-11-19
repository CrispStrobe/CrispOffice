@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

final _profile = MailProfileId('integration', hostId: 'quds.office.test');
final _account = MailAccountId('primary', profile: _profile);
final _inbox = MailMailboxId('INBOX', account: _account);

void main() {
  late Directory directory;
  late File databaseFile;
  late SqliteMailRepository store;
  MailStoreCheckpoint? failAt;

  Future<void> open() async {
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase(databaseFile),
        profile: _profile,
        faultInjector: (checkpoint) {
          if (checkpoint == failAt) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
  }

  Future<void> register(MailCredentialReference credential) async {
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: credential.account,
          provider: MailProviderKind.imap,
          displayName: 'Controlled integration account',
          credentialReference: credential.key,
        ),
      ),
    );
  }

  Future<MailResult<MailSyncPage>> pull(
    MailProvider provider,
    MailAccountSession session, {
    MailMailboxId? mailbox,
    int limit = 2,
  }) => const MailSyncCoordinator().pullPage(
    provider: provider,
    repository: store,
    session: session,
    mailbox: mailbox ?? _inbox,
    limit: limit,
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    failAt = null;
    directory = await Directory.systemTemp.createTemp('quds-mail-host-store-');
    databaseFile = File('${directory.path}/mail.sqlite3');
    await open();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'native UID pages preserve flags and resume the durable cursor after reopen',
    () async {
      final fixture = ImapFixture(
        uidNext: 4,
        messages: {
          1: _message('First', flags: [r'\Seen', r'\Flagged']),
          3: _message('Third', flags: [r'\Answered', r'\Draft']),
        },
      );
      final provider = fixture.provider(account: _account);
      final session = MailAccountSession(_account);
      await register(provider.configuration.credential);

      final firstPage = _value(await pull(provider, session));
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.upserts.map(_uid), [1]);
      expect(
        firstPage.tombstones.single,
        MailImapIdentity(mailbox: _inbox, uidValidity: 41, uid: 2),
      );
      final firstCursor = _value(await store.readCursor(_inbox))!.value;
      final firstId = _value(await store.listHeaders(_inbox)).single.id;
      expect(
        _value(await store.listHeaders(_inbox)).single.flags,
        const MailMessageFlags(isRead: true, isFlagged: true),
      );

      await store.close();
      await open();
      expect(_value(await store.readCursor(_inbox))!.value, firstCursor);
      expect(_value(await store.listHeaders(_inbox)).single.id, firstId);
      expect(
        _value(await store.listHeaders(_inbox)).single.flags,
        const MailMessageFlags(isRead: true, isFlagged: true),
      );

      final secondPage = _value(await pull(provider, session));
      expect(secondPage.hasMore, isFalse);
      expect(secondPage.upserts.map(_uid), [3]);
      final completed = _byUid(_value(await store.listHeaders(_inbox)));
      expect(completed.keys, unorderedEquals([1, 3]));
      expect(
        completed[3]!.flags,
        const MailMessageFlags(isAnswered: true, isDraft: true),
      );
      expect(_value(await store.readCursor(_inbox))!.value, isNot(firstCursor));

      // An observed empty FLAGS response clears known bits on a later sweep.
      // The unvisited next page retains its own prior observation.
      fixture.messages[1] = _message('First updated');
      _value(await pull(provider, session));
      await store.close();
      await open();
      final refreshed = _byUid(_value(await store.listHeaders(_inbox)));
      expect(refreshed[1]!.id, firstId);
      expect(refreshed[1]!.flags, const MailMessageFlags());
      expect(
        refreshed[3]!.flags,
        const MailMessageFlags(isAnswered: true, isDraft: true),
      );
      expect(_fetchRanges(fixture), ['1:2', '3:3', '1:2']);
    },
  );

  test(
    'failed store transaction retains the cursor and retries the same UID window',
    () async {
      final fixture = ImapFixture(
        uidNext: 3,
        messages: {
          1: _message('Committed', flags: [r'\Seen']),
          2: _message('Next page', flags: [r'\Flagged']),
        },
      );
      final provider = fixture.provider(account: _account);
      final session = MailAccountSession(_account);
      await register(provider.configuration.credential);
      _value(await pull(provider, session, limit: 1));
      final cursor = _value(await store.readCursor(_inbox))!.value;

      failAt = MailStoreCheckpoint.beforeSyncCursor;
      _problem(
        await pull(provider, session, limit: 1),
        MailProblemCode.storageFailure,
      );
      expect(_value(await store.readCursor(_inbox))!.value, cursor);
      final retained = _value(await store.listHeaders(_inbox));
      expect(retained.map(_uid), [1]);
      expect(retained.single.flags, const MailMessageFlags(isRead: true));
      expect(_fetchRanges(fixture), ['1:1', '2:2']);

      failAt = null;
      final retried = _value(await pull(provider, session, limit: 1));
      expect(retried.hasMore, isFalse);
      final committed = _byUid(_value(await store.listHeaders(_inbox)));
      expect(committed.keys, unorderedEquals([1, 2]));
      expect(committed[2]!.flags, const MailMessageFlags(isFlagged: true));
      expect(_value(await store.readCursor(_inbox))!.value, isNot(cursor));
      expect(_fetchRanges(fixture), ['1:1', '2:2', '2:2']);
    },
  );

  test(
    'UIDVALIDITY reset replaces only its own account and mailbox membership',
    () async {
      final inboxFixture = ImapFixture(
        uidNext: 2,
        messages: {
          1: _message('Inbox before reset', flags: [r'\Seen']),
        },
      );
      final archiveFixture = ImapFixture(
        uidNext: 2,
        messages: {
          1: _message('Archive retained', flags: [r'\Flagged']),
        },
      );
      final otherFixture = ImapFixture(
        uidNext: 2,
        messages: {
          1: _message('Other account retained', flags: [r'\Answered']),
        },
      );
      final otherAccount = MailAccountId('secondary', profile: _profile);
      final otherInbox = MailMailboxId('INBOX', account: otherAccount);
      final archive = MailMailboxId('Archive', account: _account);
      final inboxProvider = inboxFixture.provider(account: _account);
      final archiveProvider = archiveFixture.provider(account: _account);
      final otherProvider = otherFixture.provider(account: otherAccount);
      final session = MailAccountSession(_account);
      final otherSession = MailAccountSession(otherAccount);
      await register(inboxProvider.configuration.credential);
      await register(otherProvider.configuration.credential);

      _value(await pull(inboxProvider, session));
      _value(await pull(archiveProvider, session, mailbox: archive));
      _value(await pull(otherProvider, otherSession, mailbox: otherInbox));
      final original = _value(await store.listHeaders(_inbox)).single;
      final archiveBefore = _value(await store.listHeaders(archive)).single;
      final otherBefore = _value(await store.listHeaders(otherInbox)).single;
      final archiveCursor = _value(await store.readCursor(archive))!.value;
      final otherCursor = _value(await store.readCursor(otherInbox))!.value;
      expect({original.id, archiveBefore.id, otherBefore.id}, hasLength(3));

      inboxFixture.uidValidity = 42;
      inboxFixture.messages[1] = _message('New identity', flags: [r'\Draft']);
      final reset = _value(await pull(inboxProvider, session));
      expect(reset.resetRequired, isTrue);
      final replacement = _value(await store.listHeaders(_inbox)).single;
      expect(replacement.id, isNot(original.id));
      expect(
        replacement.remote,
        MailImapIdentity(mailbox: _inbox, uidValidity: 42, uid: 1),
      );
      expect(replacement.flags, const MailMessageFlags(isDraft: true));
      expect(
        _value(await store.listHeaders(archive)).single.id,
        archiveBefore.id,
      );
      expect(
        _value(await store.listHeaders(archive)).single.flags,
        const MailMessageFlags(isFlagged: true),
      );
      expect(
        _value(await store.listHeaders(otherInbox)).single.id,
        otherBefore.id,
      );
      expect(
        _value(await store.listHeaders(otherInbox)).single.flags,
        const MailMessageFlags(isAnswered: true),
      );
      expect(_value(await store.readCursor(archive))!.value, archiveCursor);
      expect(_value(await store.readCursor(otherInbox))!.value, otherCursor);

      final requests = inboxFixture.commands.length;
      _problem(
        await pull(inboxProvider, otherSession, mailbox: otherInbox),
        MailProblemCode.invalidInput,
      );
      expect(inboxFixture.commands, hasLength(requests));
    },
  );

  test(
    'account invalidation during a blocked IMAP response cannot commit later',
    () async {
      final fixture = ImapFixture(
        uidNext: 2,
        messages: {
          1: _message('Held response', flags: [r'\Seen']),
        },
      );
      final provider = fixture.provider(account: _account);
      final session = MailAccountSession(_account);
      await register(provider.configuration.credential);
      final arrived = Completer<void>();
      final release = Completer<void>();
      final released = Completer<void>();
      fixture.beforeReply = (command) async {
        if (command.startsWith('UID FETCH ')) {
          if (!arrived.isCompleted) arrived.complete();
          await release.future;
          if (!released.isCompleted) released.complete();
        }
      };

      final pending = pull(provider, session);
      try {
        await arrived.future.timeout(const Duration(seconds: 2));
        session.invalidate();
        _problem(
          await pending.timeout(const Duration(seconds: 2)),
          MailProblemCode.staleOperation,
        );
        expect(_value(await store.readCursor(_inbox)), isNull);
        expect(_value(await store.listHeaders(_inbox)), isEmpty);
        expect(fixture.clients.single.socket.closed, isTrue);
      } finally {
        release.complete();
      }
      await released.future.timeout(const Duration(seconds: 2));
      expect(_value(await store.readCursor(_inbox)), isNull);
      expect(_value(await store.listHeaders(_inbox)), isEmpty);

      fixture.beforeReply = null;
      _value(await pull(provider, session));
      expect(
        _value(await store.listHeaders(_inbox)).single.flags,
        const MailMessageFlags(isRead: true),
      );
      expect(_fetchRanges(fixture), ['1:1', '1:1']);
    },
  );

  test(
    'host-scoped credentials are checked before protocol work and on every pull',
    () async {
      final fixture = ImapFixture(
        uidNext: 2,
        messages: {
          1: _message('Authorized fixture', flags: [r'\Seen']),
        },
      );
      final vault = _ScopedVault();
      final provider = fixture.provider(
        account: _account,
        credentialStore: vault,
      );
      final credential = provider.configuration.credential;
      final session = MailAccountSession(_account);
      await register(credential);
      final otherHostAccount = MailAccountId(
        _account.value,
        profile: MailProfileId(_profile.value, hostId: 'other.host.test'),
      );
      vault.forcedRecord = MailCredentialRecord(
        reference: MailCredentialReference(
          account: otherHostAccount,
          key: credential.key,
        ),
        opaqueData: MailBytes(fixtureBytes('wrong-host-fixture-password')),
      );

      _problem(await pull(provider, session), MailProblemCode.invalidInput);
      expect(vault.loads.single.account, _account);
      expect(vault.loads.single.key, credential.key);
      expect(fixture.commands, isEmpty);
      expect(_value(await store.readCursor(_inbox)), isNull);
      expect(_value(await store.listHeaders(_inbox)), isEmpty);

      vault.forcedRecord = null;
      _value(
        await vault.store(
          MailCredentialRecord(
            reference: credential,
            opaqueData: MailBytes(fixtureBytes('authorized-fixture-password')),
          ),
        ),
      );
      _value(await pull(provider, session));
      final cursor = _value(await store.readCursor(_inbox))!.value;
      final requests = fixture.commands.length;
      expect(
        _value(await store.listAccounts()).single.credentialReference,
        credential.key,
      );

      _value(await vault.delete(credential));
      _problem(
        await pull(provider, session),
        MailProblemCode.authenticationRequired,
      );
      expect(vault.loads, hasLength(3));
      expect(fixture.commands, hasLength(requests));
      expect(_value(await store.readCursor(_inbox))!.value, cursor);
      expect(
        _value(await store.listHeaders(_inbox)).single.flags,
        const MailMessageFlags(isRead: true),
      );
    },
  );
}

FixtureMessage _message(String subject, {List<String>? flags = const []}) {
  final headers =
      'From: Sender <sender@example.test>\r\n'
      'To: Reader <reader@example.test>\r\n'
      'Subject: $subject\r\n\r\n';
  return FixtureMessage(
    headers: fixtureBytes(headers),
    raw: fixtureBytes('${headers}Synthetic message body.\r\n'),
    flags: flags,
  );
}

int _uid(MailHeaderRecord record) => (record.remote as MailImapIdentity).uid;

Map<int, MailHeaderRecord> _byUid(List<MailHeaderRecord> records) => {
  for (final record in records) _uid(record): record,
};

List<String> _fetchRanges(ImapFixture fixture) => [
  for (final command in fixture.commands)
    if (command.startsWith('UID FETCH ')) command.split(' ')[2],
];

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode expected) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, expected);
}

/// A host-owned, account/profile-scoped fixture vault, independent of protocol
/// state. The injected wrong-record case exercises the provider's trust boundary.
final class _ScopedVault implements MailCredentialStore {
  final Map<(MailAccountId, String), MailCredentialRecord> _records = {};
  final List<MailCredentialReference> loads = [];
  MailCredentialRecord? forcedRecord;

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async {
    loads.add(reference);
    return MailSuccess(
      forcedRecord ?? _records[(reference.account, reference.key)],
    );
  }

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async {
    _records[(record.reference.account, record.reference.key)] = record;
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> delete(MailCredentialReference reference) async {
    _records.remove((reference.account, reference.key));
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async {
    _records.removeWhere((key, _) => key.$1 == account);
    return const MailSuccess(MailUnit.value);
  }
}
