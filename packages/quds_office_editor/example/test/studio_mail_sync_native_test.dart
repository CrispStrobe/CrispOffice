import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_body_download.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';

typedef _MessageFetch =
    Future<MailResult<MailMessage>> Function(
      MailRemoteIdentity,
      MailReadBudget,
      MailOperationLease,
    );

final class _Provider extends Fake implements MailProvider {
  _Provider(this.account, this.answer, {this.fetch});
  @override
  final MailAccountId account;
  final Future<MailResult<MailSyncPage>> Function(
    MailMailboxId,
    MailCursor?,
    MailOperationLease,
  )
  answer;
  final _MessageFetch? fetch;
  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) => answer(mailbox, cursor, lease);

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async => fetch == null
      ? const MailFailure(MailProblem(MailProblemCode.unsupported))
      : fetch!(identity, budget, lease);
}

MailSyncPage _page(
  MailMailboxId mailbox, {
  int validity = 7,
  String cursor = 'next',
  bool hasMore = false,
  bool reset = false,
}) => MailSyncPage(
  mailbox: mailbox,
  upserts: [
    MailHeaderRecord(
      id: MailMessageId('provider-$validity'),
      remote: MailImapIdentity(mailbox: mailbox, uidValidity: validity, uid: 1),
      envelope: MailEnvelope(subject: 'Generation $validity'),
    ),
  ],
  tombstones: [],
  next: MailCursor(mailbox: mailbox, value: cursor),
  hasMore: hasMore,
  resetRequired: reset,
  imapRange: MailImapSyncRange(
    mailbox: mailbox,
    uidValidity: validity,
    firstUid: 1,
    lastUid: 1,
  ),
);

MailMessage _message(
  MailRemoteIdentity identity, {
  String body = 'Downloaded IMAP body مرحبا',
}) => MailMessage(
  raw: MailBytes(Uint8List.fromList([0, 13, 10, 128, 255])),
  envelope: MailEnvelope(subject: 'Generation 7'),
  body: MailBody(plainText: body, html: '<p>$body</p>'),
  attachments: [
    MailAttachment(
      partPath: '2',
      mediaType: 'application/octet-stream',
      displayName: 'imap-original.bin',
      content: MailBytes(Uint8List.fromList([0, 1, 2, 128, 255])),
    ),
  ],
  localId: MailMessageId('provider-body-id'),
  remoteIdentity: identity,
);

void main() {
  late Directory directory;
  late StudioMailDraftAccount identity;
  late StudioMailDraftStore owner;
  late StudioMailSyncStore store;
  final loaders = <NativeStudioMailMessageLoader>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studio-sync-native-');
    identity = StudioMailDraftAccount(
      provider: 'imap',
      endpoint: 'imaps://mail.example.test:993',
      login: 'reader@example.test',
      sender: 'reader@example.test',
    );
    owner = await openStudioMailDraftStore(identity, appDirectory: directory);
    store =
        (owner as StudioMailMailboxStoreOwner).mailboxStore
            as StudioMailSyncStore;
  });
  tearDown(() async {
    for (final loader in loaders) {
      loader.dispose();
    }
    loaders.clear();
    await owner.close();
    await directory.delete(recursive: true);
  });

  NativeStudioMailMessageLoader loader(
    Future<MailResult<MailSyncPage>> Function(
      MailMailboxId,
      MailCursor?,
      MailOperationLease,
    )
    answer, {
    _MessageFetch? fetch,
  }) {
    final result = NativeStudioMailMessageLoader(
      mail.MailAccount.fromManualSettings(
        name: 'Reader',
        email: 'reader@example.test',
        incomingHost: 'mail.example.test',
        outgoingHost: 'mail.example.test',
        password: 'test-secret',
      ),
      persistentAccount: identity.account,
      providerFactory:
          ({
            required configuration,
            required credentialStore,
            required limits,
          }) => _Provider(configuration.account, answer, fetch: fetch),
    );
    loaders.add(result);
    return result;
  }

  mail.Mailbox box() => mail.Mailbox(
    encodedName: 'Inbox',
    encodedPath: 'INBOX',
    flags: [mail.MailboxFlag.inbox],
    pathSeparator: '/',
    uidValidity: 7,
  );
  Future<MailSyncRunReport> run(
    NativeStudioMailMessageLoader value, {
    MailCancellationSource? cancel,
    void Function(MailSyncRunProgress)? progress,
  }) => value.synchronizeMailbox(
    box(),
    repository: store,
    cancellation: (cancel ?? MailCancellationSource()).token,
    onProgress: progress ?? (_) {},
  );

  test(
    'native IMAP body download uses canonical synced IDs and skips retained content',
    () async {
      var syncCalls = 0;
      final fetched = <MailRemoteIdentity>[];
      MailMessage? source;
      final value = loader(
        (mailbox, cursor, lease) async {
          syncCalls++;
          return MailSuccess(_page(mailbox));
        },
        fetch: (remote, budget, lease) async {
          lease.checkCurrent();
          expect(lease.account, identity.account);
          expect(budget.maxRawBytes, const MailReadBudget().maxRawBytes);
          fetched.add(remote);
          source = _message(remote);
          return MailSuccess(source!);
        },
      );
      expect((await run(value)).status, MailSyncRunStatus.completed);
      final mailbox = MailMailboxId('INBOX', account: identity.account);
      final before =
          (await store.loadSyncMailbox(mailbox)
                  as MailSuccess<MailMailboxSyncSnapshot?>)
              .value!;
      final header = before.headers.single;
      expect(header.id, isNot(MailMessageId('provider-7')));
      final cache = StudioMailBodyDownloadCache(
        (owner as StudioMailMailboxStoreOwner).mailboxStore,
      );
      expect(
        (await cache.load(header) as MailSuccess<MailMessage?>).value,
        isNull,
      );
      final progress = <MailBodyDownloadProgress>[];
      final report = await value.downloadMessages(
        box(),
        headers: before.headers,
        cache: cache,
        cancellation: MailCancellationSource().token,
        onProgress: progress.add,
        isCurrent: () => true,
      );
      expect(report.status, MailBodyDownloadStatus.completed);
      expect(report.downloaded, 1);
      expect(report.alreadyCached, 0);
      expect(fetched, [header.remote]);
      expect(progress.single.downloaded, 1);
      final restored =
          (await cache.load(header) as MailSuccess<MailMessage?>).value!;
      expect(restored.localId, header.id);
      expect(restored.remoteIdentity, header.remote);
      expect(source!.localId, MailMessageId('provider-body-id'));
      expect(restored.raw.bytes, source!.raw.bytes);
      expect(restored.raw.sha256, source!.raw.sha256);
      expect(restored.body.plainText, source!.body.plainText);
      expect(restored.body.html, source!.body.html);
      expect(
        restored.attachments.single.content.bytes,
        source!.attachments.single.content.bytes,
      );
      expect(restored.attachments.single.displayName, 'imap-original.bin');

      final repeated = await value.downloadMessages(
        box(),
        headers: before.headers,
        cache: cache,
        cancellation: MailCancellationSource().token,
        onProgress: (_) {},
        isCurrent: () => true,
      );
      expect(repeated.status, MailBodyDownloadStatus.completed);
      expect(repeated.downloaded, 0);
      expect(repeated.alreadyCached, 1);
      expect(repeated.retainedBytes, 0);
      expect(fetched, [header.remote]);
      expect(syncCalls, 1);
      final after =
          (await store.loadSyncMailbox(mailbox)
                  as MailSuccess<MailMailboxSyncSnapshot?>)
              .value!;
      expect(after.revision, before.revision);
      expect(after.headerCount, before.headerCount);
      expect(after.hasMore, before.hasMore);
      expect(
        (await store.readCursor(mailbox) as MailSuccess<MailCursor?>)
            .value!
            .value,
        'next',
      );
    },
  );

  test(
    'disposed native loader cannot overwrite the successor cached body',
    () async {
      final reached = Completer<MailRemoteIdentity>();
      final response = Completer<MailResult<MailMessage>>();
      final first = loader(
        (mailbox, cursor, lease) async => MailSuccess(_page(mailbox)),
        fetch: (remote, budget, lease) {
          reached.complete(remote);
          return response.future;
        },
      );
      expect((await run(first)).status, MailSyncRunStatus.completed);
      final mailbox = MailMailboxId('INBOX', account: identity.account);
      final snapshot =
          (await store.loadSyncMailbox(mailbox)
                  as MailSuccess<MailMailboxSyncSnapshot?>)
              .value!;
      final header = snapshot.headers.single;
      final cache = StudioMailBodyDownloadCache(
        (owner as StudioMailMailboxStoreOwner).mailboxStore,
      );
      final staleProgress = <MailBodyDownloadProgress>[];
      final pending = first.downloadMessages(
        box(),
        headers: snapshot.headers,
        cache: cache,
        cancellation: MailCancellationSource().token,
        onProgress: staleProgress.add,
        isCurrent: () => true,
      );
      final remote = await reached.future;
      expect(remote, header.remote);
      first.dispose();
      expect(
        (await cache.load(header) as MailSuccess<MailMessage?>).value,
        isNull,
      );
      final second = loader(
        (mailbox, cursor, lease) async =>
            throw StateError('No resync requested'),
        fetch: (remote, budget, lease) async =>
            MailSuccess(_message(remote, body: 'Current connection body')),
      );
      expect(second.account, first.account);
      final current = await second.downloadMessages(
        box(),
        headers: snapshot.headers,
        cache: cache,
        cancellation: MailCancellationSource().token,
        onProgress: (_) {},
        isCurrent: () => true,
      );
      expect(current.status, MailBodyDownloadStatus.completed);
      response.complete(
        MailSuccess(_message(remote, body: 'Stale connection body')),
      );
      final retired = await pending;
      expect(retired.status, MailBodyDownloadStatus.cancelled);
      expect(retired.problem!.code, MailProblemCode.staleOperation);
      expect(retired.downloaded, 0);
      expect(staleProgress, isEmpty);
      final cached =
          (await cache.load(header) as MailSuccess<MailMessage?>).value!;
      expect(cached.localId, header.id);
      expect(cached.body.plainText, 'Current connection body');
      expect(
        (await store.readCursor(mailbox) as MailSuccess<MailCursor?>)
            .value!
            .value,
        'next',
      );
    },
  );

  test(
    'IMAP reconnect resumes the persisted cursor under a stable account',
    () async {
      final stop = MailCancellationSource();
      final first = loader((mailbox, cursor, lease) async {
        expect(cursor, isNull);
        return MailSuccess(
          _page(mailbox, cursor: 'interrupted', hasMore: true),
        );
      });
      final report = await run(
        first,
        cancel: stop,
        progress: (_) => stop.cancel(),
      );
      expect(report.committedPages, 1);
      expect(report.status, MailSyncRunStatus.cancelled);
      first.dispose();
      final second = loader((mailbox, cursor, lease) async {
        expect(cursor!.value, 'interrupted');
        return MailSuccess(_page(mailbox, cursor: 'finished'));
      });
      expect(second.account, first.account);
      expect((await run(second)).status, MailSyncRunStatus.completed);
      final saved = await store.loadSyncMailbox(
        MailMailboxId('INBOX', account: identity.account),
      );
      expect(
        (saved as MailSuccess<MailMailboxSyncSnapshot?>).value!.hasMore,
        isFalse,
      );
    },
  );

  test(
    'IMAP synchronization accepts a provider-verified UIDVALIDITY reset',
    () async {
      final value = loader(
        (mailbox, cursor, lease) async => MailSuccess(
          _page(
            mailbox,
            validity: cursor == null ? 7 : 8,
            cursor: cursor == null ? 'old' : 'new',
            reset: cursor != null,
          ),
        ),
      );
      expect((await run(value)).resetCount, 0);
      // The foreground browse still has validity 7, but pullChanges selects the
      // server independently and authoritatively replaces that sync generation.
      expect((await run(value)).resetCount, 1);
      final snapshot =
          (await store.loadSyncMailbox(
                    MailMailboxId('INBOX', account: identity.account),
                  )
                  as MailSuccess<MailMailboxSyncSnapshot?>)
              .value!;
      expect(snapshot.headerCount, 1);
      expect(
        (snapshot.headers.single.remote as MailImapIdentity).uidValidity,
        8,
      );
    },
  );

  test(
    'disposal fences an old loader even when its successor has the same account',
    () async {
      final reached = Completer<MailMailboxId>();
      final late = Completer<MailResult<MailSyncPage>>();
      final first = loader((mailbox, cursor, lease) {
        reached.complete(mailbox);
        return late.future;
      });
      final pending = run(first);
      final mailbox = await reached.future;
      first.dispose();
      final second = loader(
        (mailbox, cursor, lease) async =>
            MailSuccess(_page(mailbox, cursor: 'current')),
      );
      expect((await run(second)).status, MailSyncRunStatus.completed);
      late.complete(MailSuccess(_page(mailbox, cursor: 'stale')));
      expect((await pending).status, MailSyncRunStatus.cancelled);
      expect(
        ((await store.readCursor(mailbox)) as MailSuccess<MailCursor?>)
            .value!
            .value,
        'current',
      );
    },
  );
}
