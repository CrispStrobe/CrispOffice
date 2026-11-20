import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

const providers = [
  MailProviderKind.imap,
  MailProviderKind.ews,
  MailProviderKind.gmail,
  MailProviderKind.graph,
];

StudioMailDraftAccount _identity(
  MailProviderKind provider, {
  String user = 'a',
}) => StudioMailDraftAccount(
  provider: provider.name,
  endpoint: provider == MailProviderKind.imap
      ? 'imaps://mail.example.test:993'
      : 'https://mail.example.test/${provider.name}',
  login: '$user@example.test',
  sender: '$user@example.test',
);

MailAccountId _session(String id) =>
    MailAccountId(id, profile: MailProfileId('transient', hostId: 'test-host'));

MailHeaderRecord _header(
  MailProviderKind provider,
  MailAccountId source, {
  String value = 'message-one',
  String folder = 'inbox',
  int validity = 7,
  int uid = 20,
  String subject = 'Retained message',
  MailMessageFlags? flags = const MailMessageFlags(isFlagged: true),
}) => MailHeaderRecord(
  id: MailMessageId('session-dependent-${source.value}-$value-$uid'),
  remote: provider == MailProviderKind.imap
      ? MailImapIdentity(
          mailbox: MailMailboxId(folder, account: source),
          uidValidity: validity,
          uid: uid,
        )
      : MailOpaqueIdentity(account: source, provider: provider, value: value),
  envelope: MailEnvelope(
    subject: subject,
    from: [const MailAddress('writer@example.test', displayName: 'Writer')],
    sentAt: DateTime.utc(2026, 11, 20, 10),
  ),
  flags: flags,
);

MailMessage _message(MailHeaderRecord header) => MailMessage(
  raw: MailBytes(Uint8List.fromList([0, 10, 13, 128, 255])),
  envelope: header.envelope,
  body: const MailBody(plainText: 'Offline body مرحبا', html: '<p>Offline</p>'),
  attachments: [
    MailAttachment(
      partPath: '2',
      mediaType: 'application/octet-stream',
      displayName: 'original.bin',
      content: MailBytes(Uint8List.fromList([0, 1, 2, 128, 255])),
    ),
  ],
  localId: header.id,
  remoteIdentity: header.remote,
);

void main() {
  late Directory directory;
  final stores = <StudioMailDraftStore>[];
  final captures = <StudioMailMailboxCapture>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mail-view-host-');
  });

  tearDown(() async {
    for (final capture in captures) {
      capture.dispose();
    }
    captures.clear();
    for (final store in stores.reversed) {
      await store.close();
    }
    stores.clear();
    await directory.delete(recursive: true);
  });

  Future<StudioMailDraftStore> open(
    MailProviderKind provider, {
    String user = 'a',
    MailStoreFaultInjector? fault,
    MailStoreLimits limits = const MailStoreLimits(),
  }) async {
    final result = await openStudioMailDraftStore(
      _identity(provider, user: user),
      appDirectory: directory,
      faultInjector: fault,
      limits: limits,
    );
    stores.add(result);
    return result;
  }

  StudioMailMailboxStore cache(StudioMailDraftStore store) =>
      (store as StudioMailMailboxStoreOwner).mailboxStore;

  StudioMailMailboxCapture capture(
    StudioMailDraftStore store,
    MailProviderKind provider,
    MailAccountId source, {
    bool Function()? current,
  }) {
    final result = StudioMailMailboxCapture(
      store: cache(store),
      sourceAccount: source,
      provider: provider,
      isCurrent: current ?? () => true,
    );
    captures.add(result);
    return result;
  }

  Future<void> save(
    StudioMailMailboxCapture capture,
    List<MailHeaderRecord> headers, {
    String folder = 'inbox',
    bool more = true,
  }) => capture.saveView(
    MailMailbox(
      id: MailMailboxId(folder, account: capture.sourceAccount),
      displayName: folder == 'inbox' ? 'Inbox' : folder,
      isLabel: capture.provider == MailProviderKind.gmail,
    ),
    headers,
    hasMore: more,
  );

  for (final provider in providers) {
    test(
      '${provider.name} reconnect keeps body identity and exact bytes',
      () async {
        final first = await open(provider);
        await first.load();
        await first.save(
          StudioMailDraft(
            to: '',
            subject: 'Preserved draft',
            body: 'Unfinished',
          ),
          submissionUncertain: true,
        );
        final source = _session('first');
        final live = capture(first, provider, source);
        final header = _header(provider, source);
        await save(live, [header]);
        await live.cacheMessage(header, _message(header));
        final initial = (await cache(first).listViews()).single;
        final old = (await cache(first).loadView(initial.mailbox.id))!;
        live.dispose();
        await first.close();

        final second = await open(provider);
        final restoredDraft = (await second.load())!;
        expect(restoredDraft.draft.subject, 'Preserved draft');
        expect(restoredDraft.submissionUncertain, isTrue);
        final nextSource = _session('second');
        final next = capture(second, provider, nextSource);
        final nextHeader = _header(provider, nextSource);
        expect(nextHeader.id, isNot(header.id));
        await save(next, [nextHeader], more: false);
        final summary = (await cache(second).listViews()).single;
        final view = (await cache(second).loadView(summary.mailbox.id))!;
        expect(view.headers.single.id, old.headers.single.id);
        expect(view.headers.single.remote.account, _identity(provider).account);
        expect(view.revision, old.revision + 1);
        expect(view.hasMore, isFalse);
        expect(summary.headerCount, 1);
        expect(summary.mailbox.isLabel, provider == MailProviderKind.gmail);
        final restored = (await cache(
          second,
        ).loadMessage(view.headers.single))!;
        expect(restored.raw.copyBytes(), [0, 10, 13, 128, 255]);
        expect(restored.body.plainText, 'Offline body مرحبا');
        expect(restored.attachments.single.content.copyBytes(), [
          0,
          1,
          2,
          128,
          255,
        ]);
        expect(restored.remoteIdentity, view.headers.single.remote);
      },
    );

    test(
      '${provider.name} body remains absent until explicitly opened',
      () async {
        final store = await open(provider);
        final source = _session('first');
        final live = capture(store, provider, source);
        final newer = _header(provider, source, value: 'z', uid: 30);
        final older = _header(provider, source, value: 'a', uid: 10);
        await save(live, [newer, older]);
        final summary = (await cache(store).listViews()).single;
        final view = (await cache(store).loadView(summary.mailbox.id))!;
        expect(view.headers.map((h) => h.remote), [
          provider == MailProviderKind.imap
              ? MailImapIdentity(
                  mailbox: summary.mailbox.id,
                  uidValidity: 7,
                  uid: 30,
                )
              : MailOpaqueIdentity(
                  account: cache(store).account,
                  provider: provider,
                  value: 'z',
                ),
          provider == MailProviderKind.imap
              ? MailImapIdentity(
                  mailbox: summary.mailbox.id,
                  uidValidity: 7,
                  uid: 10,
                )
              : MailOpaqueIdentity(
                  account: cache(store).account,
                  provider: provider,
                  value: 'a',
                ),
        ]);
        expect(view.hasMore, isTrue);
        expect(await cache(store).loadMessage(view.headers.first), isNull);
        await live.cacheMessage(newer, _message(newer));
        expect(await cache(store).loadMessage(view.headers.first), isNotNull);
        expect(await cache(store).loadMessage(view.headers.last), isNull);
      },
    );

    test(
      '${provider.name} foreign session/header/body cannot populate cache',
      () async {
        final store = await open(provider);
        final source = _session('first');
        final live = capture(store, provider, source);
        final header = _header(provider, source);
        final foreign = _header(provider, _session('foreign'));
        await expectLater(
          save(live, [foreign]),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
        expect(await cache(store).listViews(), isEmpty);
        await save(live, [header]);
        await expectLater(
          live.cacheMessage(header, _message(foreign)),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
        final view = (await cache(
          store,
        ).loadView((await cache(store).listViews()).single.mailbox.id))!;
        expect(await cache(store).loadMessage(view.headers.single), isNull);
      },
    );

    test(
      '${provider.name} same remote identity remains isolated by account',
      () async {
        final first = await open(provider);
        final second = await open(provider, user: 'b');
        final source = _session('first');
        final header = _header(provider, source);
        final a = capture(first, provider, source);
        final b = capture(second, provider, source);
        await save(a, [header]);
        await save(b, [header]);
        await a.cacheMessage(header, _message(header));
        final aView = (await cache(
          first,
        ).loadView((await cache(first).listViews()).single.mailbox.id))!;
        final bView = (await cache(
          second,
        ).loadView((await cache(second).listViews()).single.mailbox.id))!;
        expect(aView.headers.single.id, bView.headers.single.id);
        expect(await cache(first).loadMessage(aView.headers.single), isNotNull);
        expect(await cache(second).loadMessage(bView.headers.single), isNull);
        await expectLater(
          cache(second).loadMessage(aView.headers.single),
          throwsA(isA<StudioMailMailboxStoreException>()),
        );
      },
    );
  }

  test('IMAP UIDVALIDITY and mailbox both isolate identical UIDs', () async {
    final store = await open(MailProviderKind.imap);
    final source = _session('first');
    final live = capture(store, MailProviderKind.imap, source);
    final old = _header(MailProviderKind.imap, source);
    await save(live, [old]);
    await live.cacheMessage(old, _message(old));
    await save(live, [_header(MailProviderKind.imap, source, validity: 8)]);
    await save(live, [
      _header(MailProviderKind.imap, source, folder: 'archive'),
    ], folder: 'archive');
    final ids = <MailMessageId>{};
    for (final row in await cache(store).listViews()) {
      final view = (await cache(store).loadView(row.mailbox.id))!;
      ids.add(view.headers.single.id);
      expect(await cache(store).loadMessage(view.headers.single), isNull);
    }
    expect(ids, hasLength(2));
  });

  test(
    'cancelled capture rolls back a body transaction before commit',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      var pause = false;
      final store = await open(
        MailProviderKind.ews,
        fault: (point) async {
          if (pause && point == MailStoreCheckpoint.beforeCommit) {
            reached.complete();
            await release.future;
          }
        },
      );
      final source = _session('first');
      final live = capture(store, MailProviderKind.ews, source);
      final header = _header(MailProviderKind.ews, source);
      await save(live, [header]);
      pause = true;
      final result = live.cacheMessage(header, _message(header));
      final rejected = expectLater(
        result,
        throwsA(isA<StudioMailMailboxStoreException>()),
      );
      await reached.future;
      live.dispose();
      release.complete();
      await rejected;
      pause = false;
      final view = (await cache(
        store,
      ).loadView((await cache(store).listViews()).single.mailbox.id))!;
      expect(await cache(store).loadMessage(view.headers.single), isNull);
    },
  );

  test(
    'disposed capture refuses queued views and retains prior snapshot',
    () async {
      final store = await open(MailProviderKind.graph);
      final source = _session('first');
      var current = true;
      final live = capture(
        store,
        MailProviderKind.graph,
        source,
        current: () => current,
      );
      await save(live, [_header(MailProviderKind.graph, source)]);
      current = false;
      await expectLater(save(live, []), throwsA(isA<MailCancelled>()));
      final summary = (await cache(store).listViews()).single;
      expect(summary.headerCount, 1);
      expect(summary.revision, 1);
    },
  );

  test(
    'failed snapshot preserves body and previous window after reopen',
    () async {
      var fail = false;
      final store = await open(
        MailProviderKind.gmail,
        fault: (point) {
          if (fail && point == MailStoreCheckpoint.beforeCommit) {
            throw StateError('private failure');
          }
        },
      );
      final source = _session('first');
      final live = capture(store, MailProviderKind.gmail, source);
      final header = _header(MailProviderKind.gmail, source);
      await save(live, [header]);
      await live.cacheMessage(header, _message(header));
      fail = true;
      await expectLater(
        save(live, [], more: false),
        throwsA(isA<StudioMailMailboxStoreException>()),
      );
      live.dispose();
      await store.close();
      final next = await open(MailProviderKind.gmail);
      final summary = (await cache(next).listViews()).single;
      expect(summary.headerCount, 1);
      expect(summary.hasMore, isTrue);
      final view = (await cache(next).loadView(summary.mailbox.id))!;
      expect(await cache(next).loadMessage(view.headers.single), isNotNull);
    },
  );

  test('same profile cannot be opened twice while cache owns it', () async {
    final store = await open(MailProviderKind.ews);
    expect(await cache(store).listViews(), isEmpty);
    await expectLater(
      open(MailProviderKind.ews),
      throwsA(isA<StudioMailDraftStoreException>()),
    );
    await store.close();
    expect(await cache(await open(MailProviderKind.ews)).listViews(), isEmpty);
  });

  test(
    'closed shared owner rejects cache calls without affecting reopen',
    () async {
      final store = await open(MailProviderKind.ews);
      final mailbox = cache(store);
      await store.close();
      await expectLater(
        mailbox.listViews(),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      expect(
        await cache(await open(MailProviderKind.ews)).listViews(),
        isEmpty,
      );
    },
  );
}
