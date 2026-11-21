import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_cached_mail.dart';
import 'package:quds_office_studio/studio_mail_cached_strings.dart';
import 'package:quds_office_studio/studio_mail_cloud.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_drafts_dialog.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_local_drafts.dart';
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
  final fetchedIdentities = <MailRemoteIdentity>[];
  final commands = <MailOperation>[];
  bool paginate = false;
  int disposals = 0;
  int bodyVersion = 1;
  String bodyFiller = '';
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
            '$bodyFiller\r\n'
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
          if (!paginate || cursor == null) header(2, folder: mailbox.value),
          if (!paginate || cursor != null) header(1, folder: mailbox.value),
        ],
        next: paginate && cursor != null
            ? null
            : MailCursor(mailbox: mailbox, value: 'more-headers'),
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
    fetchedIdentities.add(identity);
    return bodyGate == null ? MailSuccess(message(identity)) : bodyGate!.future;
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation command,
    MailOperationLease lease,
  ) async {
    lease.checkCurrent();
    commands.add(command);
    return const MailSuccess(MailUnit.value);
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
  _Owner(this.delegate, {this.foreign, this.watchProbe});
  final SqliteStudioMailDraftStore delegate;
  final _ForeignCache? foreign;
  final _WatchProbe? watchProbe;
  final _closeCompleted = Completer<void>();
  Future<void> get whenClosed => _closeCompleted.future;
  bool closed = false;
  int loads = 0;
  final saveFailures = <MailProblemCode>[];
  @override
  MailAccountId get account => delegate.account;
  @override
  String get selectedDraftId => delegate.selectedDraftId;
  @override
  int get selectionEpoch => delegate.selectionEpoch;
  @override
  StudioMailMailboxStore get mailboxStore =>
      foreign ?? watchProbe ?? delegate.mailboxStore;
  @override
  Future<StudioMailStoredDraft?> load() {
    loads++;
    return delegate.load();
  }

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) async {
    try {
      await delegate.save(draft, submissionUncertain: submissionUncertain);
    } on StudioMailDraftStoreException catch (error) {
      saveFailures.add(error.code);
      rethrow;
    }
  }

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
  Future<void> close() {
    if (!_closeCompleted.isCompleted) {
      _closeCompleted.complete(() async {
        await delegate.close();
        closed = true;
      }());
    }
    return whenClosed;
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

/// Real persistence and events, with cancellation held at the host boundary.
final class _WatchProbe extends Fake
    implements StudioMailMailboxStore, StudioMailMailboxWatchStore {
  _WatchProbe(this.delegate);
  final StudioMailMailboxStore delegate;
  Completer<void>? cancelGate;
  int watches = 0;
  int emissions = 0;
  int cancellations = 0;
  int completedCancellations = 0;
  final streams = <StreamController<MailResult<MailCachedMailboxView?>>>[];
  @override
  MailAccountId get account => delegate.account;
  @override
  Future<List<MailCachedMailboxSummary>> listViews() => delegate.listViews();
  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) =>
      delegate.loadView(mailbox);
  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => delegate.saveView(mailbox, headers, hasMore: hasMore, lease: lease);
  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => delegate.cacheMessage(header, message, lease: lease);
  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) =>
      delegate.loadMessage(header);
  @override
  Future<MailCacheCleanupReport> clearCache() => delegate.clearCache();
  @override
  Stream<MailResult<List<MailCachedMailboxSummary>>> watchViews() =>
      (delegate as StudioMailMailboxWatchStore).watchViews();
  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    watches++;
    late StreamSubscription<MailResult<MailCachedMailboxView?>> subscription;
    late StreamController<MailResult<MailCachedMailboxView?>> controller;
    controller = StreamController<MailResult<MailCachedMailboxView?>>(
      sync: true,
      onListen: () {
        subscription = (delegate as StudioMailMailboxWatchStore)
            .watchView(mailbox)
            .listen(
              (value) {
                emissions++;
                controller.add(value);
              },
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () async {
        cancellations++;
        await cancelGate?.future;
        await subscription.cancel();
        completedCancellations++;
      },
    );
    streams.add(controller);
    return controller.stream;
  }
}

final class _Stores {
  _Stores(this.directory);
  final Directory directory;
  final owners = <_Owner>[];
  StudioMailDraftAccount? identity;
  bool seedUncertain = false;
  bool seedAttachment = false;
  MailStoreLimits limits = const MailStoreLimits();
  bool failFirstView = false;
  bool failNextCommit = false;
  bool foreignCache = false;
  bool observeWatches = false;
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
              limits: limits,
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
      watchProbe: observeWatches ? _WatchProbe(delegate.mailboxStore) : null,
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
          attachments: seedAttachment
              ? StudioMailAttachments.from([
                  StudioMailAttachment(
                    name: 'draft-original.bin',
                    bytes: Uint8List.fromList([0, 1, 2, 255, 13, 10]),
                  ),
                ])
              : const StudioMailAttachments.empty(),
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
  bool paginate = false;
  final client = _Client();

  _Provider create(MailAccountId account) {
    if (provider?.account != account) {
      provider = _Provider(account, kind)..paginate = paginate;
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
    for (final owner in stores.owners.reversed) {
      final gate = owner.watchProbe?.cancelGate;
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    for (final owner in stores.owners.reversed) {
      // The host drains live repository reads before closing its owner. A
      // competing fixture close can tear down SQLite during that drain.
      await awaitOutboxOperation(tester, owner.whenClosed);
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

Future<void> _prepareQuotaRecovery(
  WidgetTester tester,
  _Harness harness,
) async {
  harness.stores
    ..limits = const MailStoreLimits(maxAccountBytes: 32768)
    ..seedUncertain = true
    ..seedAttachment = true;
  await _showHost(tester, harness);
  harness.provider!.bodyFiller = 'cache bytes ' * 700;
  await _tapMessage(tester, 'Message two');
  await _until(tester, () => _listReady(tester));
  expect(find.text(_strings.mailCacheSaveFailed), findsNothing);
  final cache = harness.stores.owners.last.mailboxStore;
  final views = await awaitOutboxOperation(tester, cache.listViews());
  final view = await awaitOutboxOperation(
    tester,
    cache.loadView(views.single.mailbox.id),
  );
  expect(
    await awaitOutboxOperation(tester, cache.loadMessage(view!.headers.first)),
    isNotNull,
    reason: 'The real automatic cache must occupy quota before editing.',
  );
}

Future<void> _openComposer(WidgetTester tester) async {
  final tooltip = find.byTooltip(_strings.compose);
  final trigger = tooltip.evaluate().isNotEmpty
      ? tooltip.first
      : find.text(_strings.compose).first;
  await tester.ensureVisible(trigger);
  await tester.tap(trigger);
  await tester.pump();
  await _until(
    tester,
    () => find.byType(StudioMailComposeDialog).evaluate().isNotEmpty,
  );
}

Future<void> _showLocalComposer(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final identity = harness.stores.identity!;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailLocalDraftsDialog(
                strings: _strings,
                identity: identity,
                sender: identity.sender,
                isCurrent: () => true,
                draftStoreFactory: harness.stores.open,
              ),
            ),
            child: const Text('Open local drafts fixture'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open local drafts fixture'));
  await _until(
    tester,
    () => find
        .descendant(
          of: find.byType(StudioMailDraftsDialog),
          matching: find.text('Uncertain draft'),
        )
        .evaluate()
        .isNotEmpty,
  );
  final row = find.descendant(
    of: find.byType(StudioMailDraftsDialog),
    matching: find.text('Uncertain draft'),
  );
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pump();
  await _until(
    tester,
    () => find.byType(StudioMailComposeDialog).evaluate().isNotEmpty,
  );
}

Future<void> _recoverUnsavedEditor(
  WidgetTester tester,
  _Harness harness,
) async {
  final owner = harness.stores.owners.last;
  final composer = tester.widget<StudioMailComposeDialog>(
    find.byType(StudioMailComposeDialog),
  );
  expect(composer.onClearMailCache, isNotNull);
  expect(composer.previousSubmissionUncertain, isTrue);
  final originalAttachment = composer.initialDraft!.attachments.items.single;
  final editor = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  await tester.enterText(_field(_strings.to), 'unfinished@');
  await tester.tap(find.text(_strings.mailCopyRecipients));
  await tester.pump();
  await tester.enterText(_field(_strings.mailCc), 'copy@example.test');
  await tester.enterText(_field(_strings.mailBcc), 'hidden@example.test');
  await tester.enterText(
    _field(_strings.subject),
    'Live unsaved quota recovery',
  );
  editor.insertText('Recovered unsaved text ' * 650);
  final body = editor.document.paragraphs
      .map((paragraph) => paragraph.text)
      .join('\n');
  await tester.pump(const Duration(milliseconds: 600));
  await _until(
    tester,
    () => find.text(_strings.mailDraftSaveFailed).evaluate().isNotEmpty,
  );
  expect(owner.saveFailures.last, MailProblemCode.quotaExceeded);
  final retained = await awaitOutboxOperation(tester, owner.load());
  expect(retained!.draft.subject, 'Uncertain draft');
  expect(retained.submissionUncertain, isTrue);
  final beforeNetwork = (
    harness.provider!.bodyReads,
    harness.provider!.headerReads,
    harness.providerCreations,
    harness.authorizations,
  );
  final clear = _key('studio-mail-compose-clear-cache');
  await tester.ensureVisible(clear);
  await tester.tap(clear);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(_key('studio-mail-compose-clear-cache-confirm'));
  await tester.pump();
  await _until(
    tester,
    () =>
        find.byType(StudioMailComposeDialog).evaluate().isNotEmpty &&
        tester.widget<Text>(_key('studio-mail-draft-status')).data ==
            _strings.mailDraftSaved,
  );
  expect(_key('studio-mail-compose-cache-cleared'), findsOneWidget);
  expect(_key('studio-mail-compose-cache-error'), findsNothing);
  expect(find.byType(StudioMailComposeDialog), findsOneWidget);
  expect(
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller,
    same(editor),
  );
  expect(editor.isDisposed, isFalse);
  expect(
    editor.document.paragraphs.map((paragraph) => paragraph.text).join('\n'),
    body,
  );
  for (final (label, expected) in [
    (_strings.to, 'unfinished@'),
    (_strings.mailCc, 'copy@example.test'),
    (_strings.mailBcc, 'hidden@example.test'),
    (_strings.subject, 'Live unsaved quota recovery'),
  ]) {
    expect(tester.widget<TextField>(_field(label)).controller!.text, expected);
  }
  final saved = await awaitOutboxOperation(tester, owner.load());
  expect(saved!.draft.to, 'unfinished@');
  expect(saved.draft.cc, 'copy@example.test');
  expect(saved.draft.bcc, 'hidden@example.test');
  expect(saved.draft.subject, 'Live unsaved quota recovery');
  expect(saved.draft.body, body);
  expect(saved.submissionUncertain, isTrue);
  expect(
    saved.draft.attachments.items.single.content.copyBytes(),
    originalAttachment.content.copyBytes(),
  );
  expect(
    await awaitOutboxOperation(tester, owner.mailboxStore.listViews()),
    isEmpty,
  );
  expect((
    harness.provider!.bodyReads,
    harness.provider!.headerReads,
    harness.providerCreations,
    harness.authorizations,
  ), beforeNetwork);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final kind in _providers) {
    testWidgets(
      '${kind.name} repository observations supersede only changed confirmed bits',
      (tester) async {
        final harness = await _fixture(tester, kind);
        harness.stores.observeWatches = true;
        await _showHost(tester, harness);
        final owner = harness.stores.owners.single;
        final probe = owner.watchProbe!;
        MailMessageList list() =>
            tester.widget<MailMessageList>(find.byType(MailMessageList));
        for (final action in [
          MailBulkFlagAction.flag,
          MailBulkFlagAction.markUnread,
        ]) {
          final before = harness.provider!.commands.length;
          list().onBulkAction!(action, [list().items.first.id]);
          await _until(
            tester,
            () =>
                harness.provider!.commands.length > before &&
                _listReady(tester),
          );
        }
        expect(list().items.first.isRead, isFalse);
        expect(list().items.first.isFlagged, isTrue);
        final before = probe.emissions;
        await awaitOutboxOperation(
          tester,
          owner.save(
            StudioMailDraft(to: '', subject: 'Same view revision', body: ''),
            submissionUncertain: false,
          ),
        );
        await _until(tester, () => probe.emissions > before);
        expect(list().items.first.isRead, isFalse);
        expect(list().items.first.isFlagged, isTrue);
        final folders = await awaitOutboxOperation(tester, probe.listViews());
        final saved = (await awaitOutboxOperation(
          tester,
          probe.loadView(folders.single.mailbox.id),
        ))!;
        Future<void> observe(MailMessageFlags flags) async {
          final first = saved.headers.first;
          probe.streams.single.add(
            MailSuccess(
              MailCachedMailboxView(
                mailbox: saved.mailbox,
                revision: saved.revision,
                capturedAt: saved.capturedAt,
                headers: [
                  MailHeaderRecord(
                    id: first.id,
                    remote: first.remote,
                    envelope: first.envelope,
                    flags: flags,
                  ),
                  ...saved.headers.skip(1),
                ],
                hasMore: saved.hasMore,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1));
        }

        // A changed read observation must not erase the independent flag
        // confirmation. All snapshots deliberately retain the same revision.
        await observe(const MailMessageFlags(isRead: false));
        expect(list().items.first.isRead, isFalse);
        expect(list().items.first.isFlagged, isTrue);
        await observe(const MailMessageFlags(isRead: true));
        expect(list().items.first.isRead, isTrue);
        expect(list().items.first.isFlagged, isTrue);
        await observe(const MailMessageFlags(isRead: true, isFlagged: true));
        await observe(const MailMessageFlags(isRead: true, isFlagged: false));
        expect(list().items.first.isFlagged, isFalse);
        expect(harness.provider!.headerReads, 1);
        expect(harness.provider!.commands, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );

    if (kind != MailProviderKind.imap) {
      testWidgets(
        '${kind.name} delete survives metadata updates and cannot resurrect cached rows',
        (tester) async {
          final harness = await _fixture(tester, kind);
          harness.stores.observeWatches = true;
          await _showHost(tester, harness);
          await _tapMessage(tester, 'Message two');
          await _until(tester, () => _listReady(tester));
          final owner = harness.stores.owners.single;
          final cache = owner.watchProbe!;
          final folders = await awaitOutboxOperation(tester, cache.listViews());
          final saved = (await awaitOutboxOperation(
            tester,
            cache.loadView(folders.single.mailbox.id),
          ))!;
          final label = kind == MailProviderKind.ews
              ? _strings.ewsDelete
              : _strings.mailCloudDelete;
          await tester.tap(find.byTooltip(label));
          await tester.pumpAndSettle();
          final session = MailAccountSession(cache.account);
          addTearDown(session.dispose);
          final before = cache.emissions;
          await awaitOutboxOperation(
            tester,
            cache.saveView(
              saved.mailbox,
              [
                for (final header in saved.headers)
                  MailHeaderRecord(
                    id: header.id,
                    remote: header.remote,
                    envelope: header.envelope,
                    flags: header.flags == null
                        ? null
                        : const MailMessageFlags(isRead: true, isFlagged: true),
                  ),
              ],
              hasMore: saved.hasMore,
              lease: session.begin(),
            ),
          );
          await _until(tester, () => cache.emissions > before);
          await tester.tap(find.widgetWithText(FilledButton, label));
          await _until(
            tester,
            () => harness.provider!.commands.isNotEmpty && _listReady(tester),
          );
          expect(harness.provider!.commands.single, isA<MailDelete>());
          expect(cache.completedCancellations, 1);
          expect(
            tester
                .widget<MailMessageList>(find.byType(MailMessageList))
                .items
                .map((item) => item.subject),
            ['Message one'],
          );
          expect(find.byType(MailMessageView), findsNothing);
          // This unrelated native draft commit needs the real isolate/I/O
          // event loop, independently of the host's fake widget clock.
          await tester.runAsync(
            () => owner.save(
              StudioMailDraft(to: '', subject: 'After delete', body: ''),
              submissionUncertain: false,
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            tester
                .widget<MailMessageList>(find.byType(MailMessageList))
                .items
                .map((item) => item.subject),
            ['Message one'],
          );
          expect(harness.provider!.headerReads, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${kind.name} pagination retains repository flags and selected reader',
      (tester) async {
        final harness = await _fixture(tester, kind);
        harness.paginate = true;
        await _showHost(tester, harness);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        final reader = tester
            .widget<MailMessageView>(find.byType(MailMessageView))
            .controller;
        final listBefore = tester.widget<MailMessageList>(
          find.byType(MailMessageList),
        );
        final cache = harness.stores.owners.single.mailboxStore;
        final views = await awaitOutboxOperation(tester, cache.listViews());
        final saved = (await awaitOutboxOperation(
          tester,
          cache.loadView(views.single.mailbox.id),
        ))!;
        expect(saved.headers, hasLength(1));
        final header = saved.headers.single;
        final session = MailAccountSession(cache.account);
        addTearDown(session.dispose);
        await awaitOutboxOperation(
          tester,
          cache.saveView(
            saved.mailbox,
            [
              MailHeaderRecord(
                id: header.id,
                remote: header.remote,
                envelope: header.envelope,
                flags: const MailMessageFlags(
                  isFlagged: true,
                  isAnswered: true,
                ),
              ),
            ],
            hasMore: true,
            lease: session.begin(),
          ),
        );
        await _until(
          tester,
          () =>
              tester
                  .widget<MailMessageList>(find.byType(MailMessageList))
                  .items
                  .single
                  .isFlagged ==
              true,
        );
        tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .onLoadMore!();
        await _until(
          tester,
          () => harness.provider!.headerReads == 2 && _listReady(tester),
        );
        final list = tester.widget<MailMessageList>(
          find.byType(MailMessageList),
        );
        expect(list.items, hasLength(2));
        expect(list.items.first.isFlagged, isTrue);
        expect(list.items.first.isRead, isFalse);
        expect(list.selectedId, listBefore.selectedId);
        expect(
          tester
              .widget<MailMessageView>(find.byType(MailMessageView))
              .controller,
          same(reader),
        );
        final retained = (await awaitOutboxOperation(
          tester,
          cache.loadView(saved.mailbox.id),
        ))!;
        expect(
          retained.headers.first.flags,
          const MailMessageFlags(isFlagged: true, isAnswered: true),
        );
        expect(retained.headers.last.flags, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} unchanged repository revision preserves newer foreground flag',
      (tester) async {
        final harness = await _fixture(tester, kind);
        harness.paginate = true;
        await _showHost(tester, harness);
        final list = tester.widget<MailMessageList>(
          find.byType(MailMessageList),
        );
        list.onBulkAction!(MailBulkFlagAction.flag, [list.items.first.id]);
        await _until(
          tester,
          () => harness.provider!.commands.isNotEmpty && _listReady(tester),
        );
        expect(
          tester
              .widget<MailMessageList>(find.byType(MailMessageList))
              .items
              .first
              .isFlagged,
          isTrue,
        );
        final sourceRemote = harness.provider!
            .header(2, folder: kind == MailProviderKind.imap ? 'INBOX' : null)
            .remote;
        expect(harness.provider!.commands.single.message, sourceRemote);
        // This custom owner has no journal; an unrelated draft commit must not
        // overwrite the newer confirmed flag with the unchanged cached value.
        await awaitOutboxOperation(
          tester,
          harness.stores.owners.single.save(
            StudioMailDraft(
              to: '',
              subject: 'Unrelated draft',
              body: 'Keep flag',
            ),
            submissionUncertain: false,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widget<MailMessageList>(find.byType(MailMessageList))
              .items
              .first
              .isFlagged,
          isTrue,
        );
        tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .onLoadMore!();
        await _until(
          tester,
          () => harness.provider!.headerReads == 2 && _listReady(tester),
        );
        expect(
          tester
              .widget<MailMessageList>(find.byType(MailMessageList))
              .items
              .first
              .isFlagged,
          isTrue,
        );
        final cache = harness.stores.owners.single.mailboxStore;
        final folders = await awaitOutboxOperation(tester, cache.listViews());
        final retained = (await awaitOutboxOperation(
          tester,
          cache.loadView(folders.single.mailbox.id),
        ))!;
        expect(retained.headers.first.flags!.isFlagged, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} repository flags preserve live reader and provider identities',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _showHost(tester, harness);
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        final before = tester.widget<MailMessageList>(
          find.byType(MailMessageList),
        );
        final originalIds = before.items.map((item) => item.id).toList();
        final selectedId = before.selectedId;
        final reader = tester
            .widget<MailMessageView>(find.byType(MailMessageView))
            .controller;
        final cache = harness.stores.owners.single.mailboxStore;
        final summaries = await awaitOutboxOperation(tester, cache.listViews());
        final saved = (await awaitOutboxOperation(
          tester,
          cache.loadView(summaries.single.mailbox.id),
        ))!;
        final session = MailAccountSession(cache.account);
        addTearDown(session.dispose);
        await awaitOutboxOperation(
          tester,
          cache.saveView(
            saved.mailbox,
            [
              for (final header in saved.headers)
                MailHeaderRecord(
                  id: header.id,
                  remote: header.remote,
                  envelope: header.envelope,
                  flags: header.envelope.subject == 'Message two'
                      ? const MailMessageFlags(isRead: false, isFlagged: true)
                      : header.flags,
                ),
            ],
            hasMore: saved.hasMore,
            lease: session.begin(),
          ),
        );
        await _until(tester, () {
          final list = tester.widget<MailMessageList>(
            find.byType(MailMessageList),
          );
          return list.items.first.isFlagged == true &&
              list.items.first.isRead == false;
        });
        final projected = tester.widget<MailMessageList>(
          find.byType(MailMessageList),
        );
        expect(projected.items.map((item) => item.id), originalIds);
        expect(projected.selectedId, selectedId);
        expect(
          tester
              .widget<MailMessageView>(find.byType(MailMessageView))
              .controller,
          same(reader),
        );
        expect(harness.provider!.headerReads, 1);
        expect(harness.provider!.bodyReads, 1);
        final sourceRemote = harness.provider!
            .header(2, folder: kind == MailProviderKind.imap ? 'INBOX' : null)
            .remote;
        expect(harness.provider!.fetchedIdentities.single, sourceRemote);

        // Losing the cache keeps the verified online window and reader usable.
        await awaitOutboxOperation(tester, cache.clearCache());
        await _until(
          tester,
          () => find.text(_strings.mailCacheSaveFailed).evaluate().isNotEmpty,
        );
        expect(
          tester.widget<MailMessageList>(find.byType(MailMessageList)).items,
          hasLength(2),
        );
        expect(
          tester
              .widget<MailMessageView>(find.byType(MailMessageView))
              .controller,
          same(reader),
        );
        await _tapMessage(tester, 'Message two');
        await _until(tester, () => _listReady(tester));
        expect(harness.provider!.bodyReads, 2);
        expect(harness.provider!.fetchedIdentities, [
          sourceRemote,
          sourceRemote,
        ]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} awaits repository cancellation before refresh and owner close',
      (tester) async {
        final harness = await _fixture(tester, kind);
        harness.stores.observeWatches = true;
        await _showHost(tester, harness);
        final owner = harness.stores.owners.single;
        final probe = owner.watchProbe!;
        expect(probe.watches, 1);
        final gate = probe.cancelGate = Completer<void>();
        final before = harness.provider!.headerReads;
        await tester.tap(find.byTooltip(_strings.refresh));
        await _until(tester, () => probe.cancellations == 1);
        expect(harness.provider!.headerReads, before);
        expect(probe.completedCancellations, 0);
        expect(owner.closed, isFalse);
        gate.complete();
        await _until(
          tester,
          () => harness.provider!.headerReads > before && _listReady(tester),
        );
        expect(probe.watches, 2);
        expect(probe.completedCancellations, 1);

        final closeGate = probe.cancelGate = Completer<void>();
        await tester.tap(find.byTooltip(_strings.disconnect));
        await _until(tester, () => probe.cancellations == 2);
        expect(owner.closed, isFalse);
        expect(probe.completedCancellations, 1);
        closeGate.complete();
        await _until(tester, () => owner.closed);
        expect(probe.completedCancellations, 2);
        expect(find.byType(MailMessageView), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} widget disposal drains repository cancellation before owner close',
      (tester) async {
        final harness = await _fixture(tester, kind);
        harness.stores.observeWatches = true;
        await _showHost(tester, harness);
        final owner = harness.stores.owners.single;
        final probe = owner.watchProbe!;
        final gate = probe.cancelGate = Completer<void>();

        await tester.pumpWidget(const SizedBox.shrink());
        await _until(tester, () => probe.cancellations == 1);
        expect(probe.completedCancellations, 0);
        expect(owner.closed, isFalse);
        gate.complete();
        await awaitOutboxOperation(tester, owner.whenClosed);
        expect(probe.completedCancellations, 1);
        expect(owner.closed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

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
      '${kind.name} connected composer recovers actual quota without losing live edits',
      (tester) async {
        final harness = await _fixture(tester, kind);
        await _prepareQuotaRecovery(tester, harness);
        await _openComposer(tester);
        await _recoverUnsavedEditor(tester, harness);
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

  testWidgets(
    'offline local composer recovers actual quota without reconnecting or losing edits',
    (tester) async {
      final harness = await _fixture(tester, MailProviderKind.imap);
      await _prepareQuotaRecovery(tester, harness);
      await _disconnect(tester, harness);
      final beforeNetwork = (
        harness.provider!.bodyReads,
        harness.provider!.headerReads,
        harness.providerCreations,
        harness.authorizations,
      );
      await _showLocalComposer(tester, harness);
      expect(
        tester
            .widget<StudioMailComposeDialog>(
              find.byType(StudioMailComposeDialog),
            )
            .canSend,
        isFalse,
      );
      await _recoverUnsavedEditor(tester, harness);
      expect((
        harness.provider!.bodyReads,
        harness.provider!.headerReads,
        harness.providerCreations,
        harness.authorizations,
      ), beforeNetwork);
    },
  );
}
