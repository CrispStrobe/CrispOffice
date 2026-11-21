import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

T _value<T>(MailResult<T> result) => (result as MailSuccess<T>).value;

StudioMailDraftAccount _account(MailProviderKind provider) =>
    StudioMailDraftAccount(
      provider: provider.name,
      endpoint: provider == MailProviderKind.imap
          ? 'imaps://mail.example.test:993'
          : 'https://mail.example.test/${provider.name}',
      login: 'reader@example.test',
      sender: 'reader@example.test',
    );

MailHeaderRecord _header(
  MailAccountId account,
  MailProviderKind provider, {
  int number = 1,
  String? id,
  String subject = 'Saved header',
}) => MailHeaderRecord(
  id: MailMessageId(id ?? 'provider-$number'),
  remote: provider == MailProviderKind.imap
      ? MailImapIdentity(
          mailbox: MailMailboxId('inbox', account: account),
          uidValidity: 7,
          uid: number,
        )
      : MailOpaqueIdentity(
          account: account,
          provider: provider,
          value: 'remote-$number',
        ),
  envelope: MailEnvelope(subject: subject),
  flags: const MailMessageFlags(isRead: true),
);

final class _Provider extends Fake implements MailProvider {
  _Provider(this.account, this.page);
  @override
  final MailAccountId account;
  final Future<MailResult<MailSyncPage>> Function(MailCursor?) page;
  final cursors = <MailCursor?>[];
  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lease.checkCurrent();
    cursors.add(cursor);
    return page(cursor);
  }
}

void main() {
  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    test(
      '${kind.name}: interrupted sync resumes after reopen and reuses cached body IDs',
      () async {
        final directory = await Directory.systemTemp.createTemp('studio-sync-');
        final identity = _account(kind);
        StudioMailDraftStore? owner;
        final session = MailAccountSession(identity.account);
        addTearDown(() async {
          session.dispose();
          await owner?.close();
          await directory.delete(recursive: true);
        });
        owner = await openStudioMailDraftStore(
          identity,
          appDirectory: directory,
        );
        await owner.load();
        await owner.save(
          StudioMailDraft(
            to: 'recipient@example.test',
            subject: 'Keep this draft',
            body: 'Unsaved provider work',
          ),
          submissionUncertain: false,
        );
        var mailboxStore = (owner as StudioMailMailboxStoreOwner).mailboxStore;
        var syncStore = mailboxStore as StudioMailSyncStore;
        final mailbox = MailMailbox(
          id: MailMailboxId('inbox', account: identity.account),
          displayName: 'Inbox',
        );

        // A previous transient browsing session has already retained a body.
        final oldAccount = MailAccountId(
          'old-session',
          profile: MailProfileId('transient', hostId: 'test'),
        );
        final oldHeader = _header(oldAccount, kind, id: 'old-local-id');
        final capture = StudioMailMailboxCapture(
          store: mailboxStore,
          sourceAccount: oldAccount,
          provider: kind,
          isCurrent: () => true,
        );
        final saved = await capture.saveView(
          MailMailbox(
            id: MailMailboxId('inbox', account: oldAccount),
            displayName: 'Inbox',
          ),
          [oldHeader],
          hasMore: true,
        );
        await capture.cacheMessage(
          oldHeader,
          MailMessage(
            raw: MailBytes(Uint8List.fromList([13, 10, 128, 255])),
            envelope: oldHeader.envelope,
            body: const MailBody(plainText: 'Cached original body'),
            localId: oldHeader.id,
            remoteIdentity: oldHeader.remote,
          ),
        );
        capture.dispose();
        _value(await syncStore.saveSyncMailbox(mailbox));
        final first = _Provider(identity.account, (cursor) async {
          expect(cursor, isNull);
          return MailSuccess(
            MailSyncPage(
              mailbox: mailbox.id,
              upserts: [_header(identity.account, kind)],
              tombstones: [],
              next: MailCursor(mailbox: mailbox.id, value: 'checkpoint-1'),
              hasMore: true,
            ),
          );
        });
        final paused = await const MailSyncRunner().run(
          provider: first,
          repository: syncStore,
          session: session,
          mailbox: mailbox.id,
          maxPages: 1,
        );
        expect(paused.status, MailSyncRunStatus.paused);
        expect(paused.committedPages, 1);
        final partial = _value(await syncStore.loadSyncMailbox(mailbox.id))!;
        expect(partial.hasMore, isTrue);
        expect(partial.headers.single.id, saved.headers.single.id);
        expect(
          (await mailboxStore.loadMessage(
            partial.headers.single,
          ))!.body.plainText,
          'Cached original body',
        );

        await owner.close();
        owner = await openStudioMailDraftStore(
          identity,
          appDirectory: directory,
        );
        mailboxStore = (owner as StudioMailMailboxStoreOwner).mailboxStore;
        syncStore = mailboxStore as StudioMailSyncStore;
        final recovered = _value(await syncStore.loadSyncMailbox(mailbox.id))!;
        expect(recovered.hasMore, isTrue);
        expect(recovered.revision, partial.revision);
        expect(
          _value(
            await syncStore.listSyncMailboxes(),
          ).single.mailbox.displayName,
          'Inbox',
        );
        final second = _Provider(identity.account, (cursor) async {
          expect(cursor!.value, 'checkpoint-1');
          return MailSuccess(
            MailSyncPage(
              mailbox: mailbox.id,
              upserts: [_header(identity.account, kind, number: 2)],
              tombstones: [],
              next: MailCursor(mailbox: mailbox.id, value: 'checkpoint-2'),
              hasMore: false,
            ),
          );
        });
        final completed = await const MailSyncRunner().run(
          provider: second,
          repository: syncStore,
          session: session,
          mailbox: mailbox.id,
        );
        expect(completed.status, MailSyncRunStatus.completed);
        final full = _value(await syncStore.loadSyncMailbox(mailbox.id))!;
        expect(full.headerCount, 2);
        expect(full.hasMore, isFalse);
        expect(full.revision, partial.revision + 1);
        expect((await owner.load())!.draft.subject, 'Keep this draft');
        final retained = full.headers.singleWhere(
          (header) => header.id == saved.headers.single.id,
        );
        expect((await mailboxStore.loadMessage(retained))!.raw.copyBytes(), [
          13,
          10,
          128,
          255,
        ]);
      },
    );
  }

  test(
    'host sync store rejects cross-account scope and duplicate provider IDs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'studio-sync-scope-',
      );
      final identity = _account(MailProviderKind.imap);
      final owner = await openStudioMailDraftStore(
        identity,
        appDirectory: directory,
      );
      addTearDown(() async {
        await owner.close();
        await directory.delete(recursive: true);
      });
      final store =
          (owner as StudioMailMailboxStoreOwner).mailboxStore
              as StudioMailSyncStore;
      final mailbox = MailMailboxId('inbox', account: identity.account);
      final foreign = MailMailboxId(
        'inbox',
        account: MailAccountId('other', profile: identity.profile),
      );
      expect(await store.readCursor(foreign), isA<MailFailure<MailCursor?>>());
      expect(await store.loadSyncMailbox(foreign), isA<MailFailure<Object?>>());
      final session = MailAccountSession(identity.account);
      addTearDown(session.dispose);
      final result = await store.commitSyncPage(
        MailSyncPage(
          mailbox: mailbox,
          upserts: [
            _header(identity.account, MailProviderKind.imap, id: 'duplicate'),
            _header(
              identity.account,
              MailProviderKind.imap,
              number: 2,
              id: 'duplicate',
            ),
          ],
          tombstones: [],
          next: MailCursor(mailbox: mailbox, value: 'bad'),
          hasMore: false,
        ),
        expectedCursor: null,
        lease: session.begin(),
      );
      expect(result, isA<MailFailure<MailUnit>>());
      expect(_value(await store.readCursor(mailbox)), isNull);
      expect(_value(await store.loadSyncMailbox(mailbox)), isNull);
    },
  );

  test(
    'late provider page after account disposal never becomes durable',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'studio-sync-late-',
      );
      final identity = _account(MailProviderKind.graph);
      final owner = await openStudioMailDraftStore(
        identity,
        appDirectory: directory,
      );
      addTearDown(() async {
        await owner.close();
        await directory.delete(recursive: true);
      });
      final store =
          (owner as StudioMailMailboxStoreOwner).mailboxStore
              as StudioMailSyncStore;
      final mailbox = MailMailboxId('inbox', account: identity.account);
      final session = MailAccountSession(identity.account);
      final reached = Completer<void>();
      final page = Completer<MailResult<MailSyncPage>>();
      final provider = _Provider(identity.account, (_) {
        reached.complete();
        return page.future;
      });
      final running = const MailSyncRunner().run(
        provider: provider,
        repository: store,
        session: session,
        mailbox: mailbox,
      );
      await reached.future;
      session.dispose();
      page.complete(
        MailSuccess(
          MailSyncPage(
            mailbox: mailbox,
            upserts: [_header(identity.account, MailProviderKind.graph)],
            tombstones: [],
            next: MailCursor(mailbox: mailbox, value: 'too-late'),
            hasMore: false,
          ),
        ),
      );
      expect((await running).status, MailSyncRunStatus.cancelled);
      expect(_value(await store.readCursor(mailbox)), isNull);
    },
  );
}
