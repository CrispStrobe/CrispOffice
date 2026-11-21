import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_cached_search.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

StudioMailDraftAccount _identity(String provider, String sender) =>
    StudioMailDraftAccount(
      provider: provider,
      endpoint: provider == 'imap'
          ? 'imaps://mail.example.test:993'
          : 'https://mail.example.test/$provider',
      login: sender,
      sender: sender,
    );

MailHeaderRecord _header(
  StudioMailDraftAccount identity,
  int number, {
  String folder = 'inbox',
  String subject = 'Quarterly report',
}) => MailHeaderRecord(
  id: MailMessageId('message-${number.toString().padLeft(4, '0')}'),
  remote: identity.provider == MailProviderKind.imap
      ? MailImapIdentity(
          mailbox: MailMailboxId(folder, account: identity.account),
          uidValidity: 17,
          uid: number,
        )
      : MailOpaqueIdentity(
          account: identity.account,
          provider: identity.provider,
          value: 'message-$number',
        ),
  envelope: MailEnvelope(
    subject: subject,
    from: const [MailAddress('team@example.test', displayName: 'Team')],
    to: [MailAddress(identity.sender)],
    messageId: '<same-rfc-id@example.test>',
    sentAt: DateTime.utc(2026, 11, 21),
  ),
  flags: const MailMessageFlags(isRead: false, isFlagged: true),
);

Matcher _problem(MailProblemCode code) => isA<StudioMailMailboxStoreException>()
    .having((error) => error.code, 'code', code);

/// Real native account ownership with a spy proving discovery never loads or
/// writes a composer. Close behavior can be injected without changing SQLite.
final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.delegate);

  final StudioMailDraftStore delegate;
  int closeCalls = 0;
  bool failClose = false;

  @override
  StudioMailMailboxStore get mailboxStore =>
      (delegate as StudioMailMailboxStoreOwner).mailboxStore;

  @override
  Future<void> close() async {
    closeCalls++;
    if (failClose) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    await delegate.close();
  }

  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Search must never read drafts');
  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Search must never save drafts');
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Search must never submit');
  @override
  Future<void> clear() => throw StateError('Search must never clear drafts');
}

void main() {
  late Directory files;
  late NativeStudioMailLocalAccountStore directory;
  final owners = <_Owner>[];
  final sessions = <StudioMailCachedSearchSession>[];
  var current = true;

  setUp(() async {
    files = await Directory.systemTemp.createTemp('mail-unified-search-');
    directory = NativeStudioMailLocalAccountStore(appDirectory: files);
    current = true;
  });

  tearDown(() async {
    for (final owner in owners) {
      owner.failClose = false;
    }
    for (final session in sessions) {
      await session.close();
    }
    for (final owner in owners) {
      await owner.delegate.close();
    }
    sessions.clear();
    owners.clear();
    await files.delete(recursive: true);
  });

  Future<StudioMailDraftStore> open(StudioMailDraftAccount identity) async {
    final owner = _Owner(
      await openStudioMailDraftStore(identity, appDirectory: files),
    );
    owners.add(owner);
    return owner;
  }

  Future<void> seed(
    StudioMailDraftAccount identity,
    List<MailHeaderRecord> headers, {
    bool saveBodies = false,
    bool partial = false,
  }) async {
    final owner = await openStudioMailDraftStore(identity, appDirectory: files);
    try {
      final mailbox = (owner as StudioMailMailboxStoreOwner).mailboxStore;
      final lease = MailAccountSession(identity.account).begin();
      await mailbox.saveView(
        MailMailbox(
          id: MailMailboxId('inbox', account: identity.account),
          displayName: 'Inbox',
        ),
        headers,
        hasMore: partial,
        lease: lease,
      );
      if (saveBodies) {
        for (final header in headers) {
          await mailbox.cacheMessage(
            header,
            MailMessage(
              raw: MailBytes(utf8.encode('Subject: Saved\r\n\r\nSaved body')),
              envelope: header.envelope,
              body: MailBody(plainText: 'Saved body for ${identity.sender}'),
              localId: header.id,
              remoteIdentity: header.remote,
            ),
            lease: lease,
          );
        }
      }
    } finally {
      await owner.close();
    }
    await directory.remember(identity);
  }

  Future<StudioMailCachedSearchSession> session({
    String query = '',
    List<MailLocalAccountRecord>? accounts,
    StudioMailDraftStoreFactory? factory,
  }) async {
    final value = StudioMailCachedSearchSession(
      query: query,
      accounts: accounts ?? await directory.load(),
      directory: directory,
      openStore: factory ?? open,
      isCurrent: () => current,
    );
    sessions.add(value);
    return value;
  }

  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    test('$provider saved search and body survive native reopen', () async {
      final identity = _identity(provider, '$provider@example.test');
      await seed(
        identity,
        [_header(identity, 1)],
        saveBodies: true,
        partial: true,
      );
      final search = await session(query: 'from:team AND NOT is:read');
      final hits = await search.nextPage();
      expect(hits, hasLength(1));
      expect(hits.single.result.header.remote.provider.name, provider);
      expect(hits.single.result.hasCachedBody, isTrue);
      expect(hits.single.result.folders.single.displayName, 'Inbox');
      expect(search.hasMore, isFalse);
      expect(search.coverage.single.complete, isTrue);
      expect(search.coverage.single.browsed.single.hasMore, isTrue);
      expect(owners.single.closeCalls, 1);
      final message = await search.loadMessage(hits.single);
      expect(message!.body.plainText, contains(identity.sender));
      expect(message.remoteIdentity, hits.single.result.header.remote);
      expect(owners, hasLength(2));
      expect(owners.last.closeCalls, 1);
      await search.close();
      final restarted = await session(query: 'is:unread');
      expect(await restarted.nextPage(), hasLength(1));
    });
  }

  test(
    'unified results keep colliding IDs and RFC IDs in separate accounts',
    () async {
      final one = _identity('imap', 'one@example.test');
      final two = _identity('graph', 'two@example.test');
      await seed(one, [_header(one, 1)], saveBodies: true);
      await seed(two, [_header(two, 1)], saveBodies: true);
      final search = await session(query: 'subject:report');
      final hits = <StudioMailCachedSearchHit>[];
      while (search.hasMore) {
        hits.addAll(await search.nextPage());
      }
      expect(hits, hasLength(2));
      expect(hits.map((hit) => hit.key).toSet(), hasLength(2));
      expect(hits.map((hit) => hit.result.header.id).toSet(), hasLength(1));
      expect(search.coverage, hasLength(2));
      for (final hit in hits) {
        final message = await search.loadMessage(hit);
        expect(message!.body.plainText, contains(hit.account.sender));
        expect(message.remoteIdentity!.account.value, hit.account.id);
      }
    },
  );

  test('selected account scope never acquires other account owners', () async {
    final one = _identity('imap', 'one@example.test');
    final two = _identity('gmail', 'two@example.test');
    await seed(one, [_header(one, 1)]);
    await seed(two, [_header(two, 1)]);
    final chosen = (await directory.load())
        .where((row) => row.id == two.account.value)
        .toList();
    final search = await session(accounts: chosen);
    final hit = (await search.nextPage()).single;
    expect(hit.account.id, two.account.value);
    expect(search.hasMore, isFalse);
    expect(owners.single.mailboxStore.account, two.account);
    expect(await search.loadMessage(hit), isNull);
  });

  test('zero-match scan pages retain continuation and owner', () async {
    final identity = _identity('imap', 'scan@example.test');
    await seed(identity, [
      _header(identity, 1, subject: 'First'),
      _header(identity, 2, subject: 'Second'),
      _header(identity, 3, subject: 'Target'),
    ]);
    final search = await session(query: 'subject:Target');
    expect(await search.nextPage(limit: 1, scanLimit: 1), isEmpty);
    expect(search.hasMore, isTrue);
    expect(search.coverage.single.scannedCount, 1);
    expect(owners.single.closeCalls, 0);
    expect(await search.nextPage(limit: 1, scanLimit: 1), isEmpty);
    final hits = await search.nextPage(limit: 1, scanLimit: 1);
    expect(hits.single.result.header.envelope.subject, 'Target');
    expect(search.coverage.single.scannedCount, 3);
    expect(search.coverage.single.totalCount, 3);
    expect(search.hasMore, isFalse);
    expect(owners.single.closeCalls, 1);
  });

  test('invalid syntax is rejected before any account opens', () async {
    final identity = _identity('imap', 'invalid@example.test');
    await seed(identity, [_header(identity, 1)]);
    await expectLater(
      session(query: 'from:team OR'),
      throwsA(isA<MailHeaderSearchException>()),
    );
    expect(owners, isEmpty);
  });

  test(
    'failed account remains in coverage while other accounts continue',
    () async {
      final one = _identity('imap', 'one@example.test');
      final two = _identity('ews', 'two@example.test');
      await seed(one, [_header(one, 1)]);
      await seed(two, [_header(two, 1)]);
      final search = await session(
        factory: (identity) async {
          if (identity.account == one.account) {
            throw const StudioMailDraftStoreException(MailProblemCode.conflict);
          }
          return open(identity);
        },
      );
      final hits = <StudioMailCachedSearchHit>[];
      while (search.hasMore) {
        hits.addAll(await search.nextPage());
      }
      expect(hits.single.account.id, two.account.value);
      expect(search.coverage.where((value) => value.complete), hasLength(1));
      expect(
        search.coverage
            .singleWhere((value) => value.account.id == one.account.value)
            .problem,
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'removed or re-registered directory entry cannot reopen a result',
    () async {
      final identity = _identity('imap', 'removed@example.test');
      await seed(identity, [_header(identity, 1)], saveBodies: true);
      final search = await session();
      final hit = (await search.nextPage()).single;
      await directory.forget(hit.account);
      await expectLater(
        search.loadMessage(hit),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await directory.remember(identity);
      await expectLater(
        search.loadMessage(hit),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect(owners, hasLength(1));
    },
  );

  test('query sessions cannot exchange result capabilities', () async {
    final identity = _identity('imap', 'scope@example.test');
    await seed(identity, [_header(identity, 1)]);
    final first = await session();
    final hit = (await first.nextPage()).single;
    final second = await session(query: 'subject:report');
    await expectLater(
      second.loadMessage(hit),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    expect(owners, hasLength(1));
  });

  test('close fences late owner acquisition and waits for release', () async {
    final identity = _identity('imap', 'close@example.test');
    await seed(identity, [_header(identity, 1)]);
    final entered = Completer<void>();
    final proceed = Completer<void>();
    final search = await session(
      factory: (identity) async {
        entered.complete();
        await proceed.future;
        return open(identity);
      },
    );
    final reading = search.nextPage();
    final rejected = expectLater(
      reading,
      throwsA(_problem(MailProblemCode.staleOperation)),
    );
    await entered.future;
    var closed = false;
    final closing = search.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    proceed.complete();
    await rejected;
    await closing;
    expect(owners.single.closeCalls, 1);
    expect(search.coverage, isEmpty);
    await expectLater(
      search.nextPage(),
      throwsA(_problem(MailProblemCode.staleOperation)),
    );
  });

  test(
    'failed owner close remains retryable and prevents account advancement',
    () async {
      final identity = _identity('imap', 'close-failure@example.test');
      await seed(identity, [_header(identity, 1)]);
      final search = await session(
        factory: (identity) async {
          final owner = await open(identity) as _Owner;
          owner.failClose = true;
          return owner;
        },
      );
      await expectLater(
        search.nextPage(),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      expect(search.hasMore, isTrue);
      expect(search.coverage, isEmpty);
      await expectLater(
        search.close(),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      owners.single.failClose = false;
      await search.close();
      expect(owners.single.closeCalls, 3);
    },
  );
}
