import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_cached_mail.dart';
import 'package:quds_office_studio/studio_mail_cached_strings.dart';
import 'package:quds_office_studio/studio_mail_cloud.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart' show awaitOutboxOperation;

const _strings = StudioStrings(StudioLanguage.en);
const _providers = [
  MailProviderKind.imap,
  MailProviderKind.ews,
  MailProviderKind.gmail,
  MailProviderKind.graph,
];

enum _MessageMismatch { remote, localId }

final class _Provider extends Fake
    implements MailEwsProvider, MailCloudProvider, MailImapHeaderBrowser {
  _Provider(this.account, this.kind);
  @override
  final MailAccountId account;
  final MailProviderKind kind;
  int headerReads = 0;
  int bodyReads = 0;
  int disposals = 0;
  int bodyVersion = 1;
  _MessageMismatch? messageMismatch;
  Completer<MailResult<MailMessage>>? bodyGate;

  MailMailboxId box(String value) => MailMailboxId(value, account: account);
  MailRemoteIdentity remote(int id, {String? folder}) =>
      kind == MailProviderKind.imap
      ? MailImapIdentity(
          mailbox: box(folder ?? 'INBOX'),
          uidValidity: 41,
          uid: id,
        )
      : MailOpaqueIdentity(
          account: account,
          provider: kind,
          value: 'remote-$id',
        );

  MailHeaderRecord header(int id, {String? folder}) => MailHeaderRecord(
    id: MailMessageId('provider-$id'),
    remote: remote(id, folder: folder),
    envelope: MailEnvelope(
      subject: id == 2 ? 'Message two' : 'Message one',
      from: [const MailAddress('writer@example.test')],
    ),
    flags: id == 2 ? const MailMessageFlags(isRead: true) : null,
  );

  MailMessage message(MailRemoteIdentity identity) {
    final id = switch (identity) {
      MailImapIdentity(:final uid) => uid,
      MailOpaqueIdentity(:final value) => int.parse(value.split('-').last),
    };
    final parsed = const QudsMimeCodec()
        .parse(
          utf8.encode(
            'From: Writer <writer@example.test>\r\n'
            'To: Reader <reader@example.test>\r\n'
            'Subject: ${id == 2 ? 'Message two' : 'Message one'}\r\n'
            'X-Original:  keep folding\r\n\tand octets\r\n'
            'MIME-Version: 1.0\r\n'
            'Content-Type: multipart/mixed; boundary=cached-fixture\r\n\r\n'
            '--cached-fixture\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n'
            'Body version $bodyVersion from ${kind.name}.\r\n'
            '--cached-fixture\r\nContent-Type: application/octet-stream\r\n'
            'Content-Disposition: attachment; filename=original.bin\r\n'
            'Content-Transfer-Encoding: base64\r\n\r\nAAEC/w0K\r\n'
            '--cached-fixture--\r\n',
          ),
        )
        .message!;
    return MailMessage(
      raw: parsed.raw,
      envelope: parsed.envelope,
      body: parsed.body,
      attachments: parsed.attachments,
      localId: MailMessageId(
        messageMismatch == _MessageMismatch.localId
            ? 'unexpected-provider-id'
            : 'provider-$id',
      ),
      remoteIdentity: messageMismatch == _MessageMismatch.remote
          ? remote(id == 2 ? 1 : 2)
          : identity,
    );
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => MailSuccess(
    MailCapabilities(const [MailCapability.mail, MailCapability.folders]),
  );

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([MailMailbox(id: box('inbox'), displayName: 'Inbox')]);

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    headerReads++;
    return MailSuccess(
      MailHeaderPage(
        messages: [
          header(2, folder: mailbox.value),
          header(1, folder: mailbox.value),
        ],
        next: MailCursor(mailbox: mailbox, value: 'more-headers'),
      ),
    );
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchNewestHeaders(
    MailMailboxId mailbox, {
    required int uidValidity,
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) => fetchHeaders(mailbox, cursor: cursor, limit: limit, lease: lease);

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    bodyReads++;
    return bodyGate == null ? MailSuccess(message(identity)) : bodyGate!.future;
  }

  @override
  void dispose() => disposals++;
}

final class _Tokens extends Fake implements MailCloudTokenSource {
  @override
  void dispose() {}
}

final class _Credentials extends Fake implements StudioMailCredentialStore {
  @override
  Future<StudioMailCredentials?> load() async => null;
  @override
  Future<bool> save(StudioMailCredentials credentials) async => true;
  @override
  Future<bool> clear() async => true;
}

final class _Client extends Fake implements mail.MailClient {
  final inbox = mail.Mailbox(
    encodedName: 'INBOX',
    encodedPath: 'INBOX',
    flags: <mail.MailboxFlag>[],
    pathSeparator: '/',
    uidValidity: 41,
  );
  int disconnects = 0;
  @override
  mail.Mailbox get selectedMailbox => inbox;
  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {}
  @override
  Future<void> disconnect() async => disconnects++;
  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => [inbox];
  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async => inbox;
}

/// Forward to the real file store and observe its completed close, without
/// changing its persistence, serialization, account checks or fault behavior.
final class _Owner
    implements
        StudioMailDraftStore,
        StudioMailDraftCatalog,
        StudioMailMailboxStoreOwner {
  _Owner(this.delegate, {this.foreign});
  final SqliteStudioMailDraftStore delegate;
  final _ForeignCache? foreign;
  bool closed = false;
  int loads = 0;
  @override
  MailAccountId get account => delegate.account;
  @override
  String get selectedDraftId => delegate.selectedDraftId;
  @override
  int get selectionEpoch => delegate.selectionEpoch;
  @override
  StudioMailMailboxStore get mailboxStore => foreign ?? delegate.mailboxStore;
  @override
  Future<StudioMailStoredDraft?> load() {
    loads++;
    return delegate.load();
  }

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
  Future<StudioMailDraftCatalogPage> listDrafts({String? afterId}) =>
      delegate.listDrafts(afterId: afterId);
  @override
  Future<StudioMailStoredDraft> selectDraft(StudioMailDraftSummary summary) =>
      delegate.selectDraft(summary);
  @override
  Future<StudioMailStoredDraft> createDraft(StudioMailDraft initial) =>
      delegate.createDraft(initial);
  @override
  Future<void> discardDraft(StudioMailDraftSummary summary) =>
      delegate.discardDraft(summary);
  @override
  Future<void> close() async {
    await delegate.close();
    closed = true;
  }
}

final class _ForeignCache extends Fake implements StudioMailMailboxStore {
  _ForeignCache(this.account);
  @override
  final MailAccountId account;
  int writes = 0;
  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) async {
    writes++;
    throw StateError('A foreign mailbox store must never be invoked.');
  }

  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) async {
    writes++;
    throw StateError('A foreign mailbox store must never be invoked.');
  }
}

final class _Stores {
  _Stores(this.directory);
  final Directory directory;
  final owners = <_Owner>[];
  StudioMailDraftAccount? identity;
  bool seedUncertain = false;
  bool failFirstView = false;
  bool failNextCommit = false;
  bool foreignCache = false;
  Completer<void>? holdCommit;
  Completer<void>? blockedCommit;
  Completer<void>? reachedCommit;

  Future<StudioMailDraftStore> open(StudioMailDraftAccount account) async {
    if (identity != null) expectSync(account.account, identity!.account);
    identity = account;
    final delegate =
        await openStudioMailDraftStore(
              account,
              appDirectory: directory,
              faultInjector: (checkpoint) async {
                if (checkpoint != MailStoreCheckpoint.beforeCommit) return;
                final gate = holdCommit;
                if (gate != null) {
                  holdCommit = null;
                  blockedCommit = gate;
                  reachedCommit!.complete();
                  await gate.future;
                  blockedCommit = null;
                }
                if (failNextCommit) {
                  failNextCommit = false;
                  throw const MailStoreStorageException(
                    MailProblemCode.storageFailure,
                  );
                }
              },
            )
            as SqliteStudioMailDraftStore;
    final owner = _Owner(
      delegate,
      foreign: foreignCache
          ? _ForeignCache(
              MailAccountId('foreign-cache', profile: account.profile),
            )
          : null,
    );
    if (owners.isEmpty && seedUncertain) {
      await owner.load();
      await owner.save(
        StudioMailDraft(
          to: 'recipient@example.test',
          subject: 'Uncertain draft',
          body: 'Keep this draft.',
        ),
        submissionUncertain: true,
      );
    }
    if (owners.isEmpty && failFirstView) failNextCommit = true;
    owners.add(owner);
    return owner;
  }
}

final class _Harness {
  _Harness(this.kind, this.stores);
  final MailProviderKind kind;
  final _Stores stores;
  _Provider? provider;
  int authorizations = 0;
  int providerCreations = 0;
  final client = _Client();

  _Provider create(MailAccountId account) {
    if (provider?.account != account) {
      provider = _Provider(account, kind);
      providerCreations++;
    }
    return provider!;
  }

  Widget dialog() => switch (kind) {
    MailProviderKind.imap => StudioMailDialog(
      strings: _strings,
      draftStoreFactory: stores.open,
      credentialStore: _Credentials(),
      clientFactory: (_) => client,
      messageLoaderFactory: (account) => NativeStudioMailMessageLoader(
        account,
        providerFactory:
            ({
              required configuration,
              required credentialStore,
              required limits,
            }) => create(configuration.account),
      ),
    ),
    MailProviderKind.ews => StudioMailEwsDialog(
      strings: _strings,
      draftStoreFactory: stores.open,
      providerFactory: (configuration, credentials) =>
          create(configuration.account),
    ),
    MailProviderKind.gmail || MailProviderKind.graph => StudioMailCloudDialog(
      strings: _strings,
      draftStoreFactory: stores.open,
      service: kind == MailProviderKind.gmail
          ? MailCloudService.gmail
          : MailCloudService.microsoft365,
      initialClientId: 'test-cached-mail-client',
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
            return MailSuccess(_Tokens());
          },
      providerFactory: ({required configuration, required tokenSource, log}) =>
          create(configuration.account),
    ),
    _ => throw StateError(
      'Only native remote providers belong to this fixture.',
    ),
  };
}

Finder _key(String name) => find.byKey(ValueKey(name));
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var turn = 0; turn < 1000 && !ready(); turn++) {
    await tester.pump(const Duration(milliseconds: 5));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(
    ready(),
    isTrue,
    reason: 'The native cached-mail operation must settle.',
  );
  await tester.pump(const Duration(milliseconds: 350));
}

bool _listReady(WidgetTester tester) =>
    find.byType(MailMessageList).evaluate().isNotEmpty &&
    !tester.widget<MailMessageList>(find.byType(MailMessageList)).busy;

Future<_Harness> _fixture(WidgetTester tester, MailProviderKind kind) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('mail-cached-host-'),
  ))!;
  final stores = _Stores(directory);
  final harness = _Harness(kind, stores);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    final blocked = stores.blockedCommit;
    if (blocked != null && !blocked.isCompleted) blocked.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    for (final owner in stores.owners.reversed) {
      await awaitOutboxOperation(tester, owner.close());
    }
    await tester.runAsync(() => directory.delete(recursive: true));
    await tester.binding.setSurfaceSize(null);
  });
  return harness;
}

Future<void> _showHost(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => harness.dialog(),
            ),
            child: const Text('Connect fixture'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Connect fixture'));
  await tester.pumpAndSettle();
  if (harness.kind == MailProviderKind.imap) {
    await tester.enterText(
      _field(_strings.emailAddress),
      'reader@example.test',
    );
    await tester.enterText(_field(_strings.password), 'session-password');
    await tester.tap(
      find.widgetWithText(SwitchListTile, _strings.manualServers),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field(_strings.imapHost), 'imap.example.test');
    await tester.enterText(_field(_strings.smtpHost), 'smtp.example.test');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, _strings.connect),
    );
    await tester.tap(find.widgetWithText(FilledButton, _strings.connect));
  } else if (harness.kind == MailProviderKind.ews) {
    await tester.enterText(
      _key('ews-endpoint'),
      'https://mail.example.test/EWS/Exchange.asmx',
    );
    await tester.enterText(_key('ews-mailbox'), 'reader@example.test');
    await tester.enterText(_key('ews-login'), r'EXAMPLE\reader');
    await tester.enterText(_key('ews-password'), 'session-password');
    await tester.ensureVisible(_key('ews-connect'));
    await tester.tap(_key('ews-connect'));
  } else {
    await tester.enterText(_key('cloud-mailbox'), 'reader@example.test');
    await tester.ensureVisible(_key('cloud-connect'));
    await tester.tap(_key('cloud-connect'));
  }
  await _until(tester, () => _listReady(tester));
}

Future<void> _tapMessage(WidgetTester tester, String subject) async {
  final row = find.descendant(
    of: find.byType(MailMessageList),
    matching: find.text(subject),
  );
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pump();
}

Future<void> _refresh(WidgetTester tester, _Harness harness) async {
  final before = harness.provider!.headerReads;
  await tester.tap(find.byTooltip(_strings.refresh));
  await tester.pump();
  await _until(
    tester,
    () => harness.provider!.headerReads > before && _listReady(tester),
  );
}

MailMessage _readMessage(WidgetTester tester) => tester
    .widget<MailMessageView>(find.byType(MailMessageView))
    .controller
    .result
    .message!;

Future<void> _disconnect(WidgetTester tester, _Harness harness) async {
  await tester.tap(find.byTooltip(_strings.disconnect));
  await _until(
    tester,
    () => harness.stores.owners.every((owner) => owner.closed),
  );
  expect(find.byType(MailMessageView), findsNothing);
}

Future<void> _showOffline(WidgetTester tester, _Harness harness) async {
  // Model a later application entry with a fresh Navigator. Retaining the
  // connected host's dialog route would obscure the offline launch button.
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
                identity: harness.stores.identity!,
                isCurrent: () => true,
                draftStoreFactory: harness.stores.open,
              ),
            ),
            child: const Text('Open offline fixture'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open offline fixture'));
  await _until(tester, () => _listReady(tester));
}

void main() {
  for (final kind in _providers) {
    testWidgets(
      '${kind.name} persists visited headers and explicitly opened bytes across native close/reopen',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        final provider = harness.provider!;
        expect(provider.bodyReads, 0);
        final sourceHeader = provider.header(2);
        final original = provider.message(sourceHeader.remote);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(_readMessage(tester).raw.copyBytes(), original.raw.copyBytes());
        await _disconnect(tester, harness);
        final before = (
          provider.bodyReads,
          provider.headerReads,
          harness.providerCreations,
          harness.authorizations,
        );
        await _showOffline(tester, harness);
        final list = tester.widget<MailMessageList>(
          find.byType(MailMessageList),
        );
        expect(list.items.map((item) => item.subject), [
          'Message two',
          'Message one',
        ]);
        expect(list.items.last.isRead, isNull);
        expect(find.text(_strings.mailCachePartial), findsOneWidget);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        final cached = _readMessage(tester);
        expect(cached.raw.copyBytes(), original.raw.copyBytes());
        expect(
          cached.attachments.single.content.copyBytes(),
          original.attachments.single.content.copyBytes(),
        );
        expect(
          cached.remoteIdentity!.account,
          harness.stores.identity!.account,
        );
        expect(cached.localId, isNot(sourceHeader.id));
        await _tapMessage(tester, 'Message one');
        await _until(tester, () => _listReady(tester));
        expect(find.text(_strings.mailCacheMissingBody), findsOneWidget);
        expect(find.byType(MailMessageView), findsNothing);
        expect((
          provider.bodyReads,
          provider.headerReads,
          harness.providerCreations,
          harness.authorizations,
        ), before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} rejects conflicting body identities before reader or cache adoption',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        final original = _readMessage(tester).raw.copyBytes();
        for (final mismatch in _MessageMismatch.values) {
          harness.provider!
            ..bodyVersion = 2
            ..messageMismatch = mismatch;
          await _tapMessage(tester, 'Message two');
          await _until(tester, () => _listReady(tester));
          expect(
            _readMessage(tester).raw.copyBytes(),
            original,
            reason:
                '${mismatch.name} mismatch must retain the verified reader.',
          );
          expect(find.text(_strings.mailMessageFailed), findsOneWidget);
          expect(find.text(_strings.mailCacheSaveFailed), findsNothing);
        }
        await _disconnect(tester, harness);
        await _showOffline(tester, harness);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(_readMessage(tester).raw.copyBytes(), original);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} failed body cache keeps online reader and previous durable body',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        final original = _readMessage(tester).raw.copyBytes();
        harness.provider!.bodyVersion = 2;
        harness.stores.failNextCommit = true;
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(_readMessage(tester).body.plainText, contains('Body version 2'));
        expect(find.text(_strings.mailCacheSaveFailed), findsOneWidget);
        expect(_readMessage(tester).raw.copyBytes(), isNot(original));
        await _disconnect(tester, harness);
        await _showOffline(tester, harness);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(_readMessage(tester).raw.copyBytes(), original);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} disconnect invalidates a body write held before SQLite commit',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        final gate = Completer<void>();
        final reached = Completer<void>();
        harness.stores
          ..holdCommit = gate
          ..reachedCommit = reached;
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => reached.isCompleted);
        expect(find.byType(MailMessageView), findsOneWidget);
        await tester.tap(find.byTooltip(_strings.disconnect));
        await tester.pump();
        expect(harness.stores.owners.single.closed, isFalse);
        gate.complete();
        await _until(tester, () => harness.stores.owners.single.closed);
        await _showOffline(tester, harness);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(find.text(_strings.mailCacheMissingBody), findsOneWidget);
        expect(find.byType(MailMessageView), findsNothing);
        expect(harness.provider!.bodyReads, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} failed initial view save preserves uncertainty and online reader',
      (tester) async {
        final harness = await _fixture(tester, kind);
        harness.stores
          ..seedUncertain = true
          ..failFirstView = true;
        await _showHost(tester, harness);
        expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
        expect(find.text(_strings.mailCacheSaveFailed), findsOneWidget);
        expect(
          tester.widget<MailMessageList>(find.byType(MailMessageList)).items,
          hasLength(2),
        );
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(find.byType(MailMessageView), findsOneWidget);
        expect(find.text(_strings.mailCacheSaveFailed), findsOneWidget);
        final restored = await awaitOutboxOperation(
          tester,
          harness.stores.owners.single.load(),
        );
        expect(restored!.submissionUncertain, isTrue);
        expect(restored.draft.subject, 'Uncertain draft');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} view and body save warnings survive success in the other scope',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        harness.stores.failNextCommit = true;
        await _refresh(tester, harness);
        expect(find.text(_strings.mailCacheSaveFailed), findsOneWidget);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(find.text(_strings.mailCacheSaveFailed), findsOneWidget);
        final cache = harness.stores.owners.single.mailboxStore;
        final folders = await awaitOutboxOperation(tester, cache.listViews());
        final view = await awaitOutboxOperation(
          tester,
          cache.loadView(folders.single.mailbox.id),
        );
        final message = await awaitOutboxOperation(
          tester,
          cache.loadMessage(view!.headers.first),
        );
        expect(
          message,
          isNotNull,
          reason:
              'The body success must be durable despite the failed refresh.',
        );
        await _refresh(tester, harness);
        expect(find.text(_strings.mailCacheSaveFailed), findsNothing);
        harness.stores.failNextCommit = true;
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(find.text(_strings.mailCacheSaveFailed), findsOneWidget);
        await _refresh(tester, harness);
        expect(find.text(_strings.mailCacheSaveFailed), findsOneWidget);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(find.text(_strings.mailCacheSaveFailed), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} rejects a foreign cache owner before loading any draft',
      (tester) async {
        final harness = await _fixture(tester, kind);
        harness.stores.foreignCache = true;
        await _showHost(tester, harness);
        expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
        final owner = harness.stores.owners.single;
        expect(owner.loads, 0);
        expect(owner.closed, isTrue);
        expect(owner.foreign!.writes, 0);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(find.byType(MailMessageView), findsOneWidget);
        expect(owner.foreign!.writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
