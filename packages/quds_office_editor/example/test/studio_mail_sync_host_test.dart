import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_cached_mail.dart';
import 'package:quds_office_studio/studio_mail_cloud.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_sync_dialog.dart';
import 'package:quds_office_studio/studio_mail_sync_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_local_accounts.dart';
import 'support/mail_outbox_store.dart' show awaitOutboxOperation;

const _strings = StudioStrings(StudioLanguage.en);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

/// The provider seam is fake; host routing, cursor coordination, account IDs,
/// repository observers and SQLite persistence below are production code.
final class _Provider extends Fake
    implements MailEwsProvider, MailCloudProvider {
  _Provider(this.originalAccount, this.kind);
  final MailAccountId originalAccount;
  final MailProviderKind kind;
  MailAccountId? accountOverride;
  final cursors = <MailCursor?>[];
  int headerReads = 0;
  int bodyReads = 0;
  bool serveBodies = false;
  int disposals = 0;
  MailOperationLease? syncLease;
  Completer<MailResult<MailSyncPage>>? syncGate;

  @override
  MailAccountId get account => accountOverride ?? originalAccount;

  MailMailboxId get inbox => MailMailboxId('inbox', account: originalAccount);

  MailHeaderRecord header(int number) => MailHeaderRecord(
    id: MailMessageId('provider-message-$number'),
    remote: MailOpaqueIdentity(
      account: originalAccount,
      provider: kind,
      value: 'remote-message-$number',
    ),
    envelope: MailEnvelope(subject: 'Synchronized message $number'),
    flags: const MailMessageFlags(isRead: true),
  );

  MailSyncPage page(String cursor, {required int number, bool more = false}) =>
      MailSyncPage(
        mailbox: inbox,
        upserts: [header(number)],
        tombstones: const [],
        next: MailCursor(mailbox: inbox, value: cursor),
        hasMore: more,
      );

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => MailSuccess(
    MailCapabilities(const [MailCapability.mail, MailCapability.folders]),
  );

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([MailMailbox(id: inbox, displayName: 'Inbox')]);

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    headerReads++;
    // Foreground browsing deliberately sees an empty window. The sync result
    // must come from authoritative persisted memberships, not this cache.
    return MailSuccess(MailHeaderPage(messages: const []));
  }

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    expect(mailbox, inbox);
    expect(lease.account, originalAccount);
    expect(limit, inInclusiveRange(1, 1000));
    cursors.add(cursor);
    syncLease = lease;
    if (syncGate case final gate?) return gate.future;
    return MailSuccess(switch (cursor?.value) {
      null => page('page-1', number: 1, more: true),
      'page-1' => page('page-2', number: 2),
      'page-2' => page('page-3', number: 3),
      _ => throw StateError('Unexpected fixture sync cursor.'),
    });
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    bodyReads++;
    if (serveBodies) {
      lease.checkCurrent();
      expect(identity.account, account);
      final number = (identity as MailOpaqueIdentity).value.endsWith('1')
          ? 1
          : 2;
      final source = header(number);
      return MailSuccess(
        MailMessage(
          raw: MailBytes(utf8.encode('Original $number\r\n\r\nRetained body')),
          envelope: source.envelope,
          localId: source.id,
          remoteIdentity: source.remote,
          body: MailBody(plainText: 'Downloaded offline body $number'),
          attachments: [
            MailAttachment(
              partPath: '2',
              mediaType: 'application/octet-stream',
              displayName: 'retained.bin',
              content: MailBytes([0, 128, 255, number]),
            ),
          ],
        ),
      );
    }
    return const MailFailure(MailProblem(MailProblemCode.unavailable));
  }

  @override
  void dispose() => disposals++;
}

final class _Tokens extends Fake implements MailCloudTokenSource {
  @override
  void dispose() {}
}

/// Observe actual owner close without racing the host's pending read drain.
final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.delegate);
  final SqliteStudioMailDraftStore delegate;
  final _closed = Completer<void>();
  bool closed = false;
  Future<void> get whenClosed => _closed.future;

  @override
  StudioMailMailboxStore get mailboxStore => delegate.mailboxStore;
  StudioMailSyncStore get syncStore => mailboxStore as StudioMailSyncStore;
  @override
  Future<StudioMailStoredDraft?> load() => delegate.load();
  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => delegate.save(draft, submissionUncertain: submissionUncertain);
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => delegate.saveRejectedDraft(
    draft,
    wasPreviouslyUncertain: wasPreviouslyUncertain,
  );
  @override
  Future<void> clear() => delegate.clear();
  @override
  Future<void> close() {
    if (!_closed.isCompleted) {
      _closed.complete(() async {
        await delegate.close();
        closed = true;
      }());
    }
    return whenClosed;
  }
}

final class _Harness {
  _Harness(this.kind, this.directory);
  final MailProviderKind kind;
  final Directory directory;
  final providers = <_Provider>[];
  final owners = <_Owner>[];
  final identities = <StudioMailDraftAccount>[];
  final localAccounts = MemoryMailLocalAccounts();
  int authorizations = 0;

  Future<StudioMailDraftStore> open(StudioMailDraftAccount identity) async {
    identities.add(identity);
    final store = await openStudioMailDraftStore(
      identity,
      appDirectory: directory,
    );
    final owner = _Owner(store as SqliteStudioMailDraftStore);
    owners.add(owner);
    return owner;
  }

  _Provider create(MailAccountId account) {
    final provider = _Provider(account, kind);
    providers.add(provider);
    return provider;
  }

  Widget dialog() => kind == MailProviderKind.ews
      ? StudioMailEwsDialog(
          strings: _strings,
          draftStoreFactory: open,
          localAccountStore: localAccounts,
          providerFactory: (configuration, credentials) =>
              create(configuration.account),
        )
      : StudioMailCloudDialog(
          strings: _strings,
          service: kind == MailProviderKind.gmail
              ? MailCloudService.gmail
              : MailCloudService.microsoft365,
          draftStoreFactory: open,
          localAccountStore: localAccounts,
          initialClientId: 'sync-host-client',
          openBrowser: (_) async => true,
          authorizer:
              ({
                required configuration,
                required account,
                required openBrowser,
                required lease,
                log,
              }) async {
                authorizations++;
                expect(lease.account, account);
                return MailSuccess(_Tokens());
              },
          providerFactory: ({
            required configuration,
            required tokenSource,
            log,
          }) => create(configuration.account),
        );
}

Finder _key(String name) => find.byKey(ValueKey(name));

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 5));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(ready(), isTrue, reason: 'The real sync host operation must settle.');
  await tester.pump(const Duration(milliseconds: 350));
}

bool _buttonReady(WidgetTester tester, String key) {
  final finder = _key(key);
  if (finder.evaluate().isEmpty) return false;
  final button = tester.widget(finder);
  return switch (button) {
    IconButton() => button.onPressed != null,
    ButtonStyleButton() => button.onPressed != null,
    _ => false,
  };
}

Future<_Harness> _fixture(WidgetTester tester, MailProviderKind kind) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('mail-sync-host-'),
  ))!;
  final harness = _Harness(kind, directory);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    for (final provider in harness.providers) {
      final gate = provider.syncGate;
      if (gate != null && !gate.isCompleted) {
        gate.complete(
          const MailFailure(MailProblem(MailProblemCode.cancelled)),
        );
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    for (final owner in harness.owners.reversed) {
      await awaitOutboxOperation(tester, owner.whenClosed);
    }
    await tester.runAsync(() => directory.delete(recursive: true));
    await tester.binding.setSurfaceSize(null);
  });
  return harness;
}

Future<void> _showHost(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => harness.dialog(),
            ),
            child: const Text('Open sync host'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open sync host'));
  await tester.pumpAndSettle();
  if (harness.kind == MailProviderKind.ews) {
    await tester.enterText(
      _key('ews-endpoint'),
      'https://mail.example.test/EWS/Exchange.asmx',
    );
    await tester.enterText(_key('ews-mailbox'), 'reader@example.test');
    await tester.enterText(_key('ews-login'), r'EXAMPLE\reader');
    await tester.enterText(_key('ews-password'), 'session-only-password');
    await tester.ensureVisible(_key('ews-connect'));
    await tester.tap(_key('ews-connect'));
  } else {
    await tester.enterText(_key('cloud-mailbox'), 'reader@example.test');
    await tester.ensureVisible(_key('cloud-connect'));
    await tester.tap(_key('cloud-connect'));
  }
  await _until(tester, () => _buttonReady(tester, 'studio-mail-open-sync'));
}

Future<void> _openSync(WidgetTester tester) async {
  await tester.tap(_key('studio-mail-open-sync'));
  await _until(tester, () => _buttonReady(tester, 'studio-mail-sync-start'));
}

Future<void> _startSync(WidgetTester tester) async {
  await tester.tap(_key('studio-mail-sync-start'));
  await _until(
    tester,
    () =>
        _key('studio-mail-sync-result').evaluate().isNotEmpty &&
        _buttonReady(tester, 'studio-mail-sync-start'),
  );
}

Future<void> _closeSync(WidgetTester tester) async {
  await tester.tap(_key('studio-mail-sync-close'));
  await _until(
    tester,
    () => find.byType(StudioMailSyncDialog).evaluate().isEmpty,
  );
}

Future<void> _disconnect(WidgetTester tester, _Harness harness) async {
  await tester.tap(find.byTooltip(_strings.disconnect));
  await _until(tester, () => harness.owners.every((owner) => owner.closed));
}

Future<MailMailboxSyncSnapshot?> _readSync(
  WidgetTester tester,
  _Harness harness,
) async => _value(
  await awaitOutboxOperation(
    tester,
    harness.owners.last.syncStore.loadSyncMailbox(harness.providers.last.inbox),
  ),
);

MailMessageList _syncList(WidgetTester tester) =>
    tester.widget<MailMessageList>(
      find.descendant(
        of: find.byType(StudioMailSyncDialog),
        matching: find.byType(MailMessageList),
      ),
    );

void main() {
  for (final kind in [
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    testWidgets(
      '${kind.name} host downloads synchronized bodies explicitly and reopens them offline',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        final provider = harness.providers.single;
        final identity = harness.identities.single;
        await _openSync(tester);
        await _startSync(tester);
        final before = (await _readSync(tester, harness))!;
        final selected = _syncList(tester).items.first;
        _syncList(tester).onOpen(selected.id);
        await _until(
          tester,
          () => _key('studio-mail-download-message').evaluate().isNotEmpty,
        );
        expect(provider.bodyReads, 0);
        provider.serveBodies = true;
        await tester.tap(_key('studio-mail-download-page'));
        await _until(
          tester,
          () =>
              _key('studio-mail-download-result').evaluate().isNotEmpty &&
              _buttonReady(tester, 'studio-mail-download-page'),
        );
        expect(provider.bodyReads, 2);
        expect(find.text(_strings.mailDownloadFinished), findsOneWidget);
        expect(find.byType(MailMessageView), findsOneWidget);
        final after = (await _readSync(tester, harness))!;
        expect(after.revision, before.revision);
        expect(after.headerCount, before.headerCount);
        await tester.tap(_key('studio-mail-download-page'));
        await _until(
          tester,
          () => find
              .text(_strings.mailDownloadProgress(0, 2, 0))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          provider.bodyReads,
          2,
          reason: 'Already retained messages must not be fetched again.',
        );
        await _closeSync(tester);
        await _disconnect(tester, harness);

        // Reopen with no provider or credential source. Only the owned local
        // repository and production sync dialog/reader are involved.
        final owner = await awaitOutboxOperation(
          tester,
          harness.open(identity),
        );
        final cache = (owner as StudioMailMailboxStoreOwner).mailboxStore;
        final sync = cache as StudioMailSyncStore;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => StudioMailSyncDialog(
                      strings: _strings,
                      mailboxStore: cache,
                      syncStore: sync,
                      isCurrent: () => true,
                    ),
                  ),
                  child: const Text('Open downloaded mail'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open downloaded mail'));
        await _until(
          tester,
          () => _key('studio-mail-sync-checkpoint').evaluate().isNotEmpty,
        );
        expect(_key('studio-mail-download-page'), findsNothing);
        final offline = _syncList(tester).items.first;
        _syncList(tester).onOpen(offline.id);
        await _until(
          tester,
          () => find.byType(MailMessageView).evaluate().isNotEmpty,
        );
        final reader = tester
            .widget<MailMessageView>(find.byType(MailMessageView))
            .controller;
        expect(
          reader.result.message!.body.plainText,
          startsWith('Downloaded offline body'),
        );
        expect(
          reader.result.message!.attachments.single.content.copyBytes().take(3),
          [0, 128, 255],
        );
        expect(harness.providers, hasLength(1));
        expect(provider.bodyReads, 2);
        await _closeSync(tester);
        await awaitOutboxOperation(tester, owner.close());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} host sync persists, resumes after reconnect and opens offline without a provider',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        final firstProvider = harness.providers.single;
        final identity = harness.identities.single;
        expect(firstProvider.account, identity.account);
        expect(firstProvider.cursors, isEmpty);
        await _openSync(tester);
        expect(
          firstProvider.cursors,
          isEmpty,
          reason: 'Opening sync must not contact the provider.',
        );
        expect(find.text(_strings.mailSyncNotStarted), findsOneWidget);
        await _startSync(tester);
        expect(firstProvider.cursors.map((cursor) => cursor?.value), [
          null,
          'page-1',
        ]);
        expect(find.text(_strings.mailSyncFinished), findsOneWidget);
        final first = (await _readSync(tester, harness))!;
        expect(first.revision, 2);
        expect(first.headerCount, 2);
        expect(first.hasMore, isFalse);
        expect(
          first.headers.map((header) => header.envelope.subject),
          unorderedEquals(['Synchronized message 1', 'Synchronized message 2']),
        );
        expect(
          first.headers.every(
            (header) =>
                header.id ==
                studioMailCachedHeader(
                  firstProvider.header(
                    header.envelope.subject.endsWith('1') ? 1 : 2,
                  ),
                ).id,
          ),
          isTrue,
        );
        expect(firstProvider.bodyReads, 0);
        await _closeSync(tester);
        await _disconnect(tester, harness);

        await _showHost(tester, harness);
        expect(harness.providers, hasLength(2));
        expect(harness.identities.last.account, identity.account);
        expect(harness.providers.last.account, firstProvider.account);
        await _openSync(tester);
        expect(find.text(_strings.mailSyncComplete), findsOneWidget);
        expect(harness.providers.last.cursors, isEmpty);
        await _startSync(tester);
        expect(harness.providers.last.cursors.single!.value, 'page-2');
        final resumed = (await _readSync(tester, harness))!;
        expect(resumed.revision, 3);
        expect(resumed.headerCount, 3);
        expect(resumed.hasMore, isFalse);
        await _closeSync(tester);
        // Remove every foreground browse window to prove the offline sync
        // catalog does not accidentally depend on that separate feature.
        await awaitOutboxOperation(
          tester,
          harness.owners.last.mailboxStore.clearCache(),
        );
        expect(
          await awaitOutboxOperation(
            tester,
            harness.owners.last.mailboxStore.listViews(),
          ),
          isEmpty,
        );
        await _disconnect(tester, harness);
        final providerCount = harness.providers.length;
        final authorizations = harness.authorizations;
        final headerReads = harness.providers
            .map((provider) => provider.headerReads)
            .toList();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => StudioMailCachedMailDialog(
                      strings: _strings,
                      identity: identity,
                      isCurrent: () => true,
                      draftStoreFactory: harness.open,
                    ),
                  ),
                  child: const Text('Open saved mail'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open saved mail'));
        await _until(
          tester,
          () => _buttonReady(tester, 'studio-mail-open-sync'),
        );
        await tester.tap(_key('studio-mail-open-sync'));
        await _until(
          tester,
          () => _key('studio-mail-sync-checkpoint').evaluate().isNotEmpty,
        );
        expect(find.text(_strings.mailSyncOffline), findsOneWidget);
        expect(_key('studio-mail-sync-start'), findsNothing);
        expect(_syncList(tester).items, hasLength(3));
        expect(
          tester
              .widget<DropdownButton<MailMailboxId>>(
                _key('studio-mail-sync-folders'),
              )
              .items,
          hasLength(1),
        );
        expect(harness.providers, hasLength(providerCount));
        expect(harness.authorizations, authorizations);
        expect(
          harness.providers.map((provider) => provider.headerReads),
          headerReads,
        );
        expect(
          harness.providers.every((provider) => provider.bodyReads == 0),
          isTrue,
        );
        await _closeSync(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'host rejects a provider whose account changes before starting sync',
    (tester) async {
      final harness = await _fixture(tester, MailProviderKind.graph);
      await _showHost(tester, harness);
      await _openSync(tester);
      final provider = harness.providers.single;
      provider.accountOverride = MailAccountId(
        'different-account',
        profile: provider.originalAccount.profile,
      );
      await _startSync(tester);
      expect(provider.cursors, isEmpty);
      expect(await _readSync(tester, harness), isNull);
      expect(find.text(_strings.mailSyncFinished), findsNothing);
      provider.accountOverride = null;
      await _closeSync(tester);
      await _disconnect(tester, harness);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposed host session cannot commit a late provider sync page', (
    tester,
  ) async {
    final harness = await _fixture(tester, MailProviderKind.ews);
    await _showHost(tester, harness);
    final provider = harness.providers.single;
    final gate = Completer<MailResult<MailSyncPage>>();
    provider.syncGate = gate;
    await _openSync(tester);
    await tester.tap(_key('studio-mail-sync-start'));
    await _until(tester, () => provider.cursors.isNotEmpty);
    final lease = provider.syncLease!;
    expect(lease.isCurrent, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(lease.isCurrent, isFalse);
    gate.complete(MailSuccess(provider.page('late', number: 99)));
    await _until(tester, () => harness.owners.single.closed);
    await _showHost(tester, harness);
    expect(harness.providers.last.account, provider.originalAccount);
    expect(await _readSync(tester, harness), isNull);
    expect(
      _value(
        await awaitOutboxOperation(
          tester,
          harness.owners.last.syncStore.readCursor(
            harness.providers.last.inbox,
          ),
        ),
      ),
      isNull,
    );
    await _disconnect(tester, harness);
    expect(tester.takeException(), isNull);
  });
}
