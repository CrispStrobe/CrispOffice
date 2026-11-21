import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';

final class _Provider extends Fake implements MailProvider {
  _Provider(this.account, this.answer);
  @override
  final MailAccountId account;
  final Future<MailResult<MailSyncPage>> Function(
    MailMailboxId,
    MailCursor?,
    MailOperationLease,
  )
  answer;
  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) => answer(mailbox, cursor, lease);
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
    answer,
  ) {
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
          }) => _Provider(configuration.account, answer),
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
