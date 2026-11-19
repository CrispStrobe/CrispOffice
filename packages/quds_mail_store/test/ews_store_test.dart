import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:test/test.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final _profile = MailProfileId('personal', hostId: 'office');
final _account = MailAccountId('exchange', profile: _profile);
final _inbox = MailMailboxId('AAMkInbox+/==', account: _account);

MailOpaqueIdentity _remote(String item, {MailAccountId? account}) =>
    MailOpaqueIdentity(
      account: account ?? _account,
      provider: MailProviderKind.ews,
      value: 'AAMk$item+/==',
    );

MailHeaderRecord _header(
  String item, {
  MailAccountId? account,
  String subject = 'Exchange message',
  MailMessageFlags? flags,
}) => MailHeaderRecord(
  id: MailMessageId('ews-local-$item'),
  remote: _remote(item, account: account),
  envelope: MailEnvelope(subject: subject),
  flags: flags,
);

MailSyncPage _page(
  String state, {
  MailMailboxId? mailbox,
  List<MailHeaderRecord> upserts = const [],
  List<MailRemoteIdentity> tombstones = const [],
  bool reset = false,
}) {
  final folder = mailbox ?? _inbox;
  return MailSyncPage(
    mailbox: folder,
    upserts: upserts,
    tombstones: tombstones,
    next: MailCursor(mailbox: folder, value: state),
    hasMore: false,
    resetRequired: reset,
  );
}

void main() {
  late SqliteMailRepository store;
  late MailAccountSession session;
  MailStoreCheckpoint? failAt;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    failAt = null;
    session = MailAccountSession(_account);
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
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
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.ews,
          displayName: 'On-premises Exchange',
          credentialReference: 'vault-exchange',
        ),
      ),
    );
    _value(
      await store.saveMailbox(MailMailbox(id: _inbox, displayName: 'Inbox')),
    );
  });

  tearDown(() async => store.close());

  test(
    'EWS account and opaque item keys round trip without migration',
    () async {
      final account = _value(await store.listAccounts()).single;
      expect(account.provider, MailProviderKind.ews);
      expect(account.credentialReference, 'vault-exchange');
      final identity = _remote('Item');
      final encoded = MailStoreCodec.encodeRemote(identity);
      expect(encoded, '{"provider":"ews","value":"AAMkItem+/=="}');
      expect(MailStoreCodec.decodeRemote(encoded, account: _account), identity);
    },
  );

  test(
    'incremental read changes preserve local identity and exact sync state',
    () async {
      _value(
        await store.commitSyncPage(
          _page('opaque-state+/==:1', upserts: [_header('One')]),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      final cursor = _value(await store.readCursor(_inbox));
      _value(
        await store.commitSyncPage(
          _page(
            'opaque-state+/==:2',
            upserts: [
              _header(
                'One',
                subject: 'Updated message',
                flags: const MailMessageFlags(isRead: true),
              ),
              _header('Two'),
            ],
          ),
          expectedCursor: cursor,
          lease: session.begin(),
        ),
      );
      final messages = _value(await store.listHeaders(_inbox));
      expect(messages, hasLength(2));
      final updated = messages.singleWhere(
        (entry) => entry.remote == _remote('One'),
      );
      expect(updated.id, _header('One').id);
      expect(updated.flags?.isRead, isTrue);
      expect(updated.envelope.subject, 'Updated message');
      expect(
        _value(await store.readCursor(_inbox))!.value,
        'opaque-state+/==:2',
      );
    },
  );

  test(
    'upserts, deletions and Exchange sync state roll back together',
    () async {
      _value(
        await store.commitSyncPage(
          _page('s1', upserts: [_header('One'), _header('Two')]),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      final previous = _value(await store.readCursor(_inbox));
      final change = _page(
        's2',
        upserts: [_header('Three')],
        tombstones: [_remote('One')],
      );
      failAt = MailStoreCheckpoint.beforeSyncCursor;
      _problem(
        await store.commitSyncPage(
          change,
          expectedCursor: previous,
          lease: session.begin(),
        ),
        MailProblemCode.storageFailure,
      );
      expect(
        _value(
          await store.listHeaders(_inbox),
        ).map((entry) => entry.remote).toSet(),
        {_remote('One'), _remote('Two')},
      );
      expect(_value(await store.readCursor(_inbox))!.value, 's1');
      failAt = null;
      _value(
        await store.commitSyncPage(
          change,
          expectedCursor: previous,
          lease: session.begin(),
        ),
      );
      expect(
        _value(
          await store.listHeaders(_inbox),
        ).map((entry) => entry.remote).toSet(),
        {_remote('Two'), _remote('Three')},
      );
      expect(_value(await store.readCursor(_inbox))!.value, 's2');
    },
  );

  test(
    'a stale Exchange page cannot replace an already committed cursor',
    () async {
      _value(
        await store.commitSyncPage(
          _page('s1', upserts: [_header('One')]),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      _problem(
        await store.commitSyncPage(
          _page('stale', tombstones: [_remote('One')]),
          expectedCursor: null,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.listHeaders(_inbox)).single.remote,
        _remote('One'),
      );
      expect(_value(await store.readCursor(_inbox))!.value, 's1');
    },
  );

  test('an EWS tombstone affects only its folder membership', () async {
    final archive = MailMailboxId('AAMkArchive+/==', account: _account);
    _value(
      await store.commitSyncPage(
        _page('inbox1', upserts: [_header('One')]),
        expectedCursor: null,
        lease: session.begin(),
      ),
    );
    _value(
      await store.commitSyncPage(
        _page('archive1', mailbox: archive, upserts: [_header('One')]),
        expectedCursor: null,
        lease: session.begin(),
      ),
    );
    _value(
      await store.commitSyncPage(
        _page('inbox2', tombstones: [_remote('One')]),
        expectedCursor: _value(await store.readCursor(_inbox)),
        lease: session.begin(),
      ),
    );
    expect(_value(await store.listHeaders(_inbox)), isEmpty);
    expect(
      _value(await store.listHeaders(archive)).single.remote,
      _remote('One'),
    );
    expect(_value(await store.readCursor(archive))!.value, 'archive1');
  });

  test(
    'equal server IDs in separate Exchange accounts remain independent',
    () async {
      final other = MailAccountId('other-exchange', profile: _profile);
      final otherInbox = MailMailboxId(_inbox.value, account: other);
      _value(
        await store.createAccount(
          MailStoreAccount(
            id: other,
            provider: MailProviderKind.ews,
            displayName: 'Second Exchange',
          ),
        ),
      );
      _value(
        await store.commitSyncPage(
          _page('a1', upserts: [_header('One')]),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      _value(
        await store.commitSyncPage(
          _page(
            'b1',
            mailbox: otherInbox,
            upserts: [_header('One', account: other)],
          ),
          expectedCursor: null,
          lease: MailAccountSession(other).begin(),
        ),
      );
      _value(
        await store.commitSyncPage(
          _page('a2', tombstones: [_remote('One')]),
          expectedCursor: _value(await store.readCursor(_inbox)),
          lease: session.begin(),
        ),
      );
      expect(_value(await store.listHeaders(_inbox)), isEmpty);
      expect(
        _value(await store.listHeaders(otherInbox)).single.remote.account,
        other,
      );
      expect(_value(await store.readCursor(otherInbox))!.value, 'b1');
    },
  );

  test(
    'sync reset reconciles pending edits to removed EWS identities',
    () async {
      _value(
        await store.commitSyncPage(
          _page('expired', upserts: [_header('One')]),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      _value(
        await store.enqueueOperation(
          MailSetRead(id: 'pending-read', message: _remote('One'), read: true),
          session.begin(),
        ),
      );
      _value(
        await store.commitSyncPage(
          _page('reset1', reset: true, upserts: [_header('Two')]),
          expectedCursor: _value(await store.readCursor(_inbox)),
          lease: session.begin(),
        ),
      );
      expect(
        _value(await store.listHeaders(_inbox)).single.remote,
        _remote('Two'),
      );
      expect(
        _value(await store.pendingOperations(_account)).single.state,
        MailPendingState.reconcile,
      );
      expect(_value(await store.readCursor(_inbox))!.value, 'reset1');
    },
  );

  test(
    'a conflicting local ID cannot hide an Exchange ItemId replacement',
    () async {
      _value(
        await store.commitSyncPage(
          _page('s1', upserts: [_header('One')]),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      _problem(
        await store.commitSyncPage(
          _page(
            's2',
            upserts: [
              MailHeaderRecord(
                id: _header('One').id,
                remote: _remote('ChangedAfterMove'),
                envelope: MailEnvelope(),
              ),
            ],
          ),
          expectedCursor: _value(await store.readCursor(_inbox)),
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.listHeaders(_inbox)).single.remote,
        _remote('One'),
      );
      expect(_value(await store.readCursor(_inbox))!.value, 's1');
    },
  );
}
