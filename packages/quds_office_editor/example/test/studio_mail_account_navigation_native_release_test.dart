import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_local_accounts_dialog.dart';
import 'package:quds_office_studio/studio_mail_local_drafts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_credential_store.dart';
import 'support/mail_local_accounts.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _credentials = StudioMailCredentials(
  email: 'source@example.test',
  password: 'fixture-password',
  imapHost: 'imap.example.test',
  smtpHost: 'smtp.example.test',
  manual: true,
  startTls: false,
);
final _source = StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://imap.example.test:993',
  login: _credentials.email,
  sender: _credentials.email,
);
final _destination = StudioMailDraftAccount(
  provider: 'ews',
  endpoint: 'https://exchange.example.test/EWS/Exchange.asmx',
  login: '["DOMAIN","operator"]',
  sender: 'destination@example.test',
);
const _snapshot = StudioMailStoredDraft(
  draft: StudioMailDraft(
    to: 'recipient@example.test',
    subject: 'Retained source work',
    body: 'Keep the draft and submission uncertainty until release succeeds.',
  ),
  submissionUncertain: true,
);

final class _GuardedDirectory
    implements
        StudioMailLocalAccountStore,
        StudioMailLocalAccountReconnectStore {
  _GuardedDirectory(this.delegate);
  final MemoryMailLocalAccounts delegate;
  Completer<void>? refreshGate;
  int refreshAttempts = 0;

  @override
  Future<List<MailLocalAccountRecord>> load() => delegate.load();

  @override
  Future<void> remember(StudioMailDraftAccount identity) =>
      delegate.remember(identity);

  @override
  Future<void> forget(MailLocalAccountRecord record) => delegate.forget(record);

  @override
  Future<void> rememberSelected(
    StudioMailDraftAccount identity, {
    required MailLocalAccountRecord expectedRecord,
  }) async {
    refreshAttempts++;
    await refreshGate?.future;
    final current = delegate.records[identity.account.value];
    if (current == null ||
        !current.hasSameIdentity(expectedRecord) ||
        current.revision != expectedRecord.revision ||
        current.lastConnectedAt.millisecondsSinceEpoch !=
            expectedRecord.lastConnectedAt.millisecondsSinceEpoch) {
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);
    }
    delegate.records[identity.account.value] = MailLocalAccountRecord(
      id: current.id,
      provider: current.provider,
      endpoint: current.endpoint,
      login: current.login,
      sender: current.sender,
      lastConnectedAt: current.lastConnectedAt,
      revision: current.revision + 1,
    );
  }
}

/// A host observer can fail before it has released its underlying resource.
/// Its subsequent cancellation must retry that resource, not report success
/// merely because the first cancellation was attempted.
final class _Observation extends Stream<MailResult<MailCachedMailboxView?>> {
  _Observation(this.owner, this.delegate);
  final _Mailbox owner;
  final Stream<MailResult<MailCachedMailboxView?>> delegate;

  @override
  StreamSubscription<MailResult<MailCachedMailboxView?>> listen(
    void Function(MailResult<MailCachedMailboxView?>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _Subscription(
    owner,
    delegate.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

final class _Subscription extends Fake
    implements StreamSubscription<MailResult<MailCachedMailboxView?>> {
  _Subscription(this.owner, this.delegate);
  final _Mailbox owner;
  final StreamSubscription<MailResult<MailCachedMailboxView?>> delegate;

  @override
  Future<void> cancel() async {
    owner.cancelCalls++;
    owner.events.add('observer:cancel');
    if (owner.cancelFailures > 0) {
      owner.cancelFailures--;
      await owner.cancelFailureGate?.future;
      owner.events.add('observer:failed');
      throw const StudioMailMailboxStoreException(
        MailProblemCode.storageFailure,
      );
    }
    await owner.cancelGate?.future;
    await delegate.cancel();
    owner.cancelled++;
    owner.events.add('observer:closed');
  }
}

final class _Mailbox extends Fake
    implements StudioMailMailboxStore, StudioMailMailboxWatchStore {
  _Mailbox(this.events);
  final List<String> events;
  @override
  MailAccountId get account => _source.account;
  MailCachedMailboxView? view;
  final controllers = <StreamController<MailResult<MailCachedMailboxView?>>>[];
  Completer<void>? firstViewGate;
  Completer<void>? cancelFailureGate;
  Completer<void>? cancelGate;
  int cancelFailures = 0;
  int cancelCalls = 0;
  int cancelled = 0;
  bool emitInitial = true;

  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) async => view = MailCachedMailboxView(
    mailbox: mailbox,
    revision: (view?.revision ?? 0) + 1,
    capturedAt: DateTime.utc(2026, 11, 22),
    headers: headers,
    hasMore: hasMore,
  );

  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    late final StreamController<MailResult<MailCachedMailboxView?>> controller;
    controller = StreamController<MailResult<MailCachedMailboxView?>>(
      onListen: () {
        if (!emitInitial) return;
        final gate = firstViewGate;
        if (gate == null) {
          controller.add(MailSuccess(view));
        } else {
          unawaited(
            gate.future.then((_) {
              if (!controller.isClosed) controller.add(MailSuccess(view));
            }),
          );
        }
      },
    );
    controllers.add(controller);
    return _Observation(this, controller.stream);
  }
}

final class _Owner extends Fake
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.events) : mailboxStore = _Mailbox(events);
  final List<String> events;
  @override
  final _Mailbox mailboxStore;
  StudioMailStoredDraft snapshot = _snapshot;
  Completer<void>? loadGate;
  Completer<void>? closeGate;
  bool failClose = false;
  int loads = 0;
  int closeCalls = 0;
  int closed = 0;
  final savedUncertainty = <bool>[];

  @override
  Future<StudioMailStoredDraft?> load() async {
    loads++;
    await loadGate?.future;
    return snapshot;
  }

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) async {
    savedUncertainty.add(submissionUncertain);
    snapshot = StudioMailStoredDraft(
      draft: draft,
      submissionUncertain: submissionUncertain || snapshot.submissionUncertain,
    );
    events.add('draft:saved');
  }

  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => save(draft, submissionUncertain: wasPreviouslyUncertain);

  @override
  Future<void> clear() async => throw StateError('No draft may be discarded');

  @override
  Future<void> close() async {
    closeCalls++;
    events.add('owner:close');
    await closeGate?.future;
    if (failClose) {
      events.add('owner:failed');
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    closed++;
    events.add('owner:closed');
  }
}

final class _CatalogOwner extends _Owner implements StudioMailDraftCatalog {
  _CatalogOwner(super.events);

  @override
  MailAccountId get account => _source.account;
  @override
  String get selectedDraftId => 'retained';
  @override
  int get selectionEpoch => 0;
}

final class _Loader extends Fake
    implements StudioMailMessageLoader, StudioMailMailboxRecords {
  @override
  MailAccountId get account => _source.account;
  @override
  void cancel() {}
  @override
  void dispose() {}
}

final class _Client extends Fake implements mail.MailClient {
  final inbox = mail.Mailbox(
    encodedName: 'INBOX',
    encodedPath: 'INBOX',
    flags: [mail.MailboxFlag.inbox],
    pathSeparator: '/',
    uidValidity: 7,
    uidNext: 1,
  );
  int disconnections = 0;

  @override
  mail.Mailbox get selectedMailbox => inbox;
  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {}
  @override
  Future<void> disconnect() async => disconnections++;
  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => [inbox];
  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async => [];
}

final class _Harness {
  _Harness({this.catalogOwner = false}) {
    directory.seed(_source);
    directory.seed(_destination);
  }
  final directory = MemoryMailLocalAccounts();
  final credentials = memoryStudioMailCredentialStore();
  final events = <String>[];
  final bool catalogOwner;
  late final _Owner owner = catalogOwner
      ? _CatalogOwner(events)
      : _Owner(events);
  final clients = <_Client>[];
  final routed = <StudioMailAccountNavigationTarget>[];
  Completer<void>? openGate;
  int opens = 0;

  StudioMailAccountNavigationTarget get initial =>
      StudioMailAccountNavigationTarget.fromRecord(
        directory.records[_source.account.value]!,
      );

  Future<StudioMailDraftStore> open(StudioMailDraftAccount identity) async {
    expect(identity.account, _source.account);
    opens++;
    await openGate?.future;
    return owner;
  }

  Widget destination(
    BuildContext context,
    MailProviderKind provider,
    StudioMailAccountNavigationTarget? target,
    ValueChanged<StudioMailAccountNavigationTarget> navigate,
  ) {
    expect(provider, MailProviderKind.ews);
    expect(target?.identity.account, _destination.account);
    routed.add(target!);
    events.add('target:routed');
    return const AlertDialog(content: Text('Destination sign in'));
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);
Finder get _connect => find.widgetWithText(FilledButton, _strings.connect);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(ready(), isTrue, reason: 'The observable release stage must settle.');
}

Future<void> _show(
  WidgetTester tester,
  _Harness harness, {
  bool selectedAccount = true,
  StudioMailLocalAccountStore? directory,
  VoidCallback? onClose,
}) async {
  await (harness.credentials as StudioMailAccountCatalogStore).saveAccount(
    _credentials,
  );
  await tester.binding.setSurfaceSize(const Size(1440, 1200));
  addTearDown(() async {
    for (final gate in [
      harness.openGate,
      harness.owner.loadGate,
      harness.owner.closeGate,
      harness.owner.mailboxStore.firstViewGate,
      harness.owner.mailboxStore.cancelFailureGate,
      harness.owner.mailboxStore.cancelGate,
      if (directory is _GuardedDirectory) directory.refreshGate,
    ]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    harness.owner.failClose = false;
    harness.owner.mailboxStore.cancelFailures = 0;
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
    for (final controller in harness.owner.mailboxStore.controllers) {
      await controller.close();
    }
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        onClose: onClose,
        credentialStore: harness.credentials,
        localAccountStore: directory ?? harness.directory,
        initialAccount: selectedAccount ? harness.initial : null,
        autoConnectSavedAccount: false,
        draftStoreFactory: harness.open,
        accountDestinationBuilder: harness.destination,
        clientFactory: (_) {
          final client = _Client();
          harness.clients.add(client);
          return client;
        },
        messageLoaderFactory: (_) => _Loader(),
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _choose(WidgetTester tester) async {
  await _press(tester, _key('studio-mail-navigate-account'));
  await _press(
    tester,
    _key('studio-mail-navigation-account-${_destination.account.value}'),
  );
  await _press(tester, _key('studio-mail-account-navigation-continue'));
}

void main() {
  testWidgets('native switch drains observer then owner before routing', (
    tester,
  ) async {
    final harness = _Harness();
    await _show(tester, harness);
    await _press(tester, _connect);
    final mailbox = harness.owner.mailboxStore;
    expect(mailbox.controllers, hasLength(1));
    final previousSwitch = tester
        .widget<IconButton>(_key('studio-mail-navigate-account'))
        .onPressed!;
    mailbox.cancelGate = Completer<void>();
    harness.owner.closeGate = Completer<void>();
    await _choose(tester);
    await _until(tester, () => mailbox.cancelCalls == 1);
    expect(harness.owner.savedUncertainty, [true]);
    expect(mailbox.cancelled, 0);
    expect(harness.owner.closeCalls, 0);
    expect(harness.clients.single.disconnections, 0);
    expect(harness.routed, isEmpty);
    previousSwitch();
    await _pump(tester);
    expect(mailbox.cancelCalls, 1);
    expect(harness.owner.savedUncertainty, [true]);
    mailbox.cancelGate!.complete();
    await _until(tester, () => harness.owner.closeCalls == 1);
    expect(mailbox.cancelled, 1);
    expect(harness.routed, isEmpty);
    expect(harness.clients.single.disconnections, 0);
    harness.owner.closeGate!.complete();
    await _until(tester, () => harness.routed.isNotEmpty);
    expect(harness.owner.closed, 1);
    expect(harness.clients.single.disconnections, 1);
    expect(harness.events, [
      'draft:saved',
      'observer:cancel',
      'observer:closed',
      'owner:close',
      'owner:closed',
      'target:routed',
    ]);
    expect(harness.owner.snapshot.submissionUncertain, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed native observer drain blocks stale disconnect and refresh until release',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      final previousLocalDrafts = tester
          .widget<OutlinedButton>(_key('studio-mail-open-local-drafts'))
          .onPressed!;
      final previousAccounts = tester
          .widget<OutlinedButton>(_key('studio-mail-known-drafts'))
          .onPressed!;
      await _press(tester, _connect);
      final previousDisconnect = tester
          .widget<IconButton>(_icon(_strings.disconnect))
          .onPressed!;
      final previousRefresh = tester
          .widget<IconButton>(_icon(_strings.refresh))
          .onPressed!;
      final previousSwitch = tester
          .widget<IconButton>(_key('studio-mail-navigate-account'))
          .onPressed!;
      final mailbox = harness.owner.mailboxStore;
      mailbox.cancelFailures = 1;
      await _choose(tester);
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isNotEmpty,
      );
      expect(mailbox.cancelCalls, 1);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      expect(harness.clients.single.disconnections, 1);
      expect(harness.routed, isEmpty);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
      expect(harness.owner.snapshot.submissionUncertain, isTrue);
      previousDisconnect();
      previousRefresh();
      previousSwitch();
      previousLocalDrafts();
      previousAccounts();
      await _pump(tester);
      expect(mailbox.cancelCalls, 1);
      expect(harness.owner.closeCalls, 0);
      expect(harness.clients.single.disconnections, 1);
      expect(harness.opens, 1);
      expect(harness.routed, isEmpty);
      expect(find.byType(StudioMailLocalDraftsDialog), findsNothing);
      expect(find.byType(StudioMailLocalAccountsDialog), findsNothing);

      mailbox.cancelGate = Completer<void>();
      harness.owner.closeGate = Completer<void>();
      await _press(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => mailbox.cancelCalls == 2);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      expect(harness.routed, isEmpty);
      expect(harness.opens, 1);
      previousDisconnect();
      previousRefresh();
      previousSwitch();
      await _pump(tester);
      expect(mailbox.cancelCalls, 2);
      expect(harness.owner.closeCalls, 0);
      mailbox.cancelGate!.complete();
      await _until(tester, () => harness.owner.closeCalls == 1);
      expect(mailbox.cancelled, 1);
      expect(harness.routed, isEmpty);
      harness.owner.closeGate!.complete();
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isEmpty,
      );
      expect(harness.routed, isEmpty);
      await _choose(tester);
      await _until(tester, () => harness.routed.isNotEmpty);
      expect(harness.routed, hasLength(1));
      expect(harness.owner.closed, 1);
      expect(harness.owner.savedUncertainty, [true]);
      expect(harness.events, [
        'draft:saved',
        'observer:cancel',
        'observer:failed',
        'observer:cancel',
        'observer:closed',
        'owner:close',
        'owner:closed',
        'target:routed',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['Disconnect', 'Refresh']) {
    testWidgets(
      'ordinary native $action retains failed observers until explicit release',
      (tester) async {
        final harness = _Harness();
        await _show(tester, harness);
        final previousConnect = tester
            .widget<FilledButton>(_connect)
            .onPressed!;
        await _press(tester, _connect);
        final mailbox = harness.owner.mailboxStore;
        expect(mailbox.controllers, hasLength(1));
        final previousDisconnect = tester
            .widget<IconButton>(_icon(_strings.disconnect))
            .onPressed!;
        final previousRefresh = tester
            .widget<IconButton>(_icon(_strings.refresh))
            .onPressed!;
        final previousSwitch = tester
            .widget<IconButton>(_key('studio-mail-navigate-account'))
            .onPressed!;
        mailbox.cancelFailures = 1;
        await _press(
          tester,
          _icon(
            action == 'Disconnect' ? _strings.disconnect : _strings.refresh,
          ),
        );
        await _until(
          tester,
          () =>
              find.text(_strings.mailDraftStorageFailed).evaluate().isNotEmpty,
        );
        expect(mailbox.cancelCalls, 1);
        expect(mailbox.cancelled, 0);
        expect(harness.owner.closeCalls, 0);
        expect(harness.clients.single.disconnections, 1);
        expect(harness.routed, isEmpty);
        expect(_key('studio-mail-navigation-release'), findsOneWidget);
        previousConnect();
        previousDisconnect();
        previousRefresh();
        previousSwitch();
        await _pump(tester);
        expect(mailbox.cancelCalls, 1);
        expect(harness.owner.closeCalls, 0);
        expect(harness.clients, hasLength(1));
        expect(harness.opens, 1);
        expect(harness.routed, isEmpty);

        mailbox.cancelGate = Completer<void>();
        harness.owner.closeGate = Completer<void>();
        await _press(tester, _key('studio-mail-navigation-release'));
        await _until(tester, () => mailbox.cancelCalls == 2);
        expect(mailbox.cancelled, 0);
        expect(harness.owner.closeCalls, 0);
        mailbox.cancelGate!.complete();
        await _until(tester, () => harness.owner.closeCalls == 1);
        expect(mailbox.cancelled, 1);
        expect(harness.owner.closed, 0);
        expect(harness.routed, isEmpty);
        harness.owner.closeGate!.complete();
        await _until(
          tester,
          () => _key('studio-mail-navigation-release').evaluate().isEmpty,
        );
        expect(harness.owner.closed, 1);
        expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
        expect(harness.owner.snapshot.submissionUncertain, isTrue);
        expect(harness.routed, isEmpty);
        await _choose(tester);
        await _until(tester, () => harness.routed.isNotEmpty);
        expect(harness.routed, hasLength(1));
        expect(harness.owner.closed, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ordinary native Disconnect does not retry a failing in-flight Refresh drain',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      final previousConnect = tester.widget<FilledButton>(_connect).onPressed!;
      await _press(tester, _connect);
      final mailbox = harness.owner.mailboxStore;
      final previousRefresh = tester
          .widget<IconButton>(_icon(_strings.refresh))
          .onPressed!;
      mailbox.cancelFailures = 1;
      mailbox.cancelFailureGate = Completer<void>();
      await _press(tester, _icon(_strings.refresh));
      await _until(tester, () => mailbox.cancelCalls == 1);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);

      await _press(tester, _icon(_strings.disconnect));
      expect(harness.clients.single.disconnections, 1);
      expect(mailbox.cancelCalls, 1);
      expect(harness.owner.closeCalls, 0);
      expect(harness.routed, isEmpty);
      mailbox.cancelFailureGate!.complete();
      await _until(
        tester,
        () => find.text(_strings.mailDraftStorageFailed).evaluate().isNotEmpty,
      );
      expect(mailbox.cancelCalls, 1);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      expect(_key('studio-mail-navigation-release'), findsOneWidget);
      previousConnect();
      previousRefresh();
      await _pump(tester);
      expect(harness.clients, hasLength(1));
      expect(harness.opens, 1);
      expect(mailbox.cancelCalls, 1);

      mailbox.cancelGate = Completer<void>();
      harness.owner.closeGate = Completer<void>();
      await _press(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => mailbox.cancelCalls == 2);
      expect(harness.owner.closeCalls, 0);
      mailbox.cancelGate!.complete();
      await _until(tester, () => harness.owner.closeCalls == 1);
      expect(mailbox.cancelled, 1);
      expect(harness.owner.closed, 0);
      harness.owner.closeGate!.complete();
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isEmpty,
      );
      expect(harness.owner.closed, 1);
      expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
      expect(harness.owner.snapshot.submissionUncertain, isTrue);
      await _choose(tester);
      await _until(tester, () => harness.routed.isNotEmpty);
      expect(harness.routed, hasLength(1));
      expect(harness.events, [
        'observer:cancel',
        'observer:failed',
        'observer:cancel',
        'observer:closed',
        'owner:close',
        'owner:closed',
        'target:routed',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary native Disconnect releases a pending first snapshot before its owner',
    (tester) async {
      final harness = _Harness();
      final mailbox = harness.owner.mailboxStore;
      mailbox.firstViewGate = Completer<void>();
      mailbox.cancelFailures = 1;
      await _show(tester, harness, selectedAccount: false);
      await _press(tester, _connect);
      await _until(tester, () => mailbox.controllers.isNotEmpty);
      expect(mailbox.view, isNotNull);
      expect(mailbox.firstViewGate!.isCompleted, isFalse);
      expect(harness.owner.loads, 1);
      await _press(tester, _icon(_strings.disconnect));
      await _until(
        tester,
        () => find.text(_strings.mailDraftStorageFailed).evaluate().isNotEmpty,
      );
      expect(mailbox.firstViewGate!.isCompleted, isFalse);
      expect(mailbox.cancelCalls, 1);
      expect(mailbox.cancelled, 0);
      expect(harness.clients.single.disconnections, 1);
      expect(harness.owner.closeCalls, 0);
      expect(harness.routed, isEmpty);
      expect(_key('studio-mail-navigation-release'), findsOneWidget);
      await _pump(tester);
      expect(mailbox.cancelCalls, 1);
      expect(harness.owner.closeCalls, 0);

      mailbox.cancelGate = Completer<void>();
      harness.owner.closeGate = Completer<void>();
      await _press(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => mailbox.cancelCalls == 2);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      mailbox.cancelGate!.complete();
      await _until(tester, () => harness.owner.closeCalls == 1);
      expect(mailbox.cancelled, 1);
      expect(harness.owner.closed, 0);
      expect(mailbox.firstViewGate!.isCompleted, isFalse);
      harness.owner.closeGate!.complete();
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isEmpty,
      );
      expect(harness.owner.closed, 1);
      expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
      expect(harness.owner.snapshot.submissionUncertain, isTrue);
      expect(harness.routed, isEmpty);
      await _choose(tester);
      await _until(tester, () => harness.routed.isNotEmpty);
      expect(harness.routed, hasLength(1));
      expect(harness.opens, 1);
      expect(mailbox.firstViewGate!.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final stage in ['factory', 'load']) {
    testWidgets(
      'ordinary native Disconnect retains a failed late $stage owner',
      (tester) async {
        final harness = _Harness();
        final gate = Completer<void>();
        if (stage == 'factory') {
          harness.openGate = gate;
        } else {
          harness.owner.loadGate = gate;
        }
        harness.owner.failClose = true;
        await _show(tester, harness, selectedAccount: false);
        final previousConnect = tester
            .widget<FilledButton>(_connect)
            .onPressed!;
        final previousSwitch = tester
            .widget<IconButton>(_key('studio-mail-navigate-account'))
            .onPressed!;
        await _press(tester, _connect);
        expect(harness.opens, 1);
        expect(harness.owner.loads, stage == 'factory' ? 0 : 1);
        await _press(tester, _icon(_strings.disconnect));
        expect(harness.clients.single.disconnections, 1);
        expect(harness.owner.closeCalls, 0);
        previousConnect();
        previousSwitch();
        await _pump(tester);
        expect(harness.clients, hasLength(1));
        expect(harness.opens, 1);
        expect(harness.routed, isEmpty);
        gate.complete();
        await _until(
          tester,
          () =>
              find.text(_strings.mailDraftStorageFailed).evaluate().isNotEmpty,
        );
        expect(harness.owner.closeCalls, 1);
        expect(harness.owner.closed, 0);
        expect(harness.owner.mailboxStore.controllers, isEmpty);
        expect(_key('studio-mail-navigation-release'), findsOneWidget);
        previousConnect();
        previousSwitch();
        await _pump(tester);
        expect(harness.clients, hasLength(1));
        expect(harness.owner.closeCalls, 1);
        expect(harness.routed, isEmpty);
        harness.owner.failClose = false;
        harness.owner.closeGate = Completer<void>();
        await _press(tester, _key('studio-mail-navigation-release'));
        await _until(tester, () => harness.owner.closeCalls == 2);
        expect(harness.owner.closed, 0);
        expect(harness.routed, isEmpty);
        harness.owner.closeGate!.complete();
        await _until(
          tester,
          () => _key('studio-mail-navigation-release').evaluate().isEmpty,
        );
        expect(harness.owner.closed, 1);
        expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
        expect(harness.owner.snapshot.submissionUncertain, isTrue);
        await _choose(tester);
        await _until(tester, () => harness.routed.isNotEmpty);
        expect(harness.routed, hasLength(1));
        expect(harness.opens, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'revoked native selection after cache save retains a failed observer until release',
    (tester) async {
      final harness = _Harness();
      final mailbox = harness.owner.mailboxStore;
      mailbox.firstViewGate = Completer<void>();
      await _show(tester, harness);
      final previousConnect = tester.widget<FilledButton>(_connect).onPressed!;
      final previousSwitch = tester
          .widget<IconButton>(_key('studio-mail-navigate-account'))
          .onPressed!;
      await _press(tester, _connect);
      await _until(tester, () => mailbox.controllers.isNotEmpty);
      expect(mailbox.view, isNotNull);
      expect(harness.owner.loads, 1);
      expect(harness.owner.closeCalls, 0);

      harness.directory.records.remove(_source.account.value);
      mailbox.cancelFailures = 1;
      mailbox.firstViewGate!.complete();
      await _until(
        tester,
        () =>
            mailbox.cancelCalls == 1 &&
            find.text(_strings.mailDraftStorageFailed).evaluate().isNotEmpty,
      );
      expect(mailbox.cancelCalls, 1);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      expect(harness.clients.single.disconnections, 1);
      expect(harness.routed, isEmpty);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      expect(find.text(_strings.mailDraftRestored), findsNothing);
      expect(
        harness.directory.records.containsKey(_source.account.value),
        isFalse,
      );
      expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
      expect(harness.owner.snapshot.submissionUncertain, isTrue);

      previousConnect();
      previousSwitch();
      await _pump(tester);
      expect(harness.clients, hasLength(1));
      expect(harness.opens, 1);
      expect(harness.owner.closeCalls, 0);
      expect(harness.routed, isEmpty);

      mailbox.cancelGate = Completer<void>();
      harness.owner.closeGate = Completer<void>();
      await _press(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => mailbox.cancelCalls == 2);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      mailbox.cancelGate!.complete();
      await _until(tester, () => harness.owner.closeCalls == 1);
      expect(mailbox.cancelled, 1);
      expect(harness.owner.closed, 0);
      expect(harness.routed, isEmpty);
      harness.owner.closeGate!.complete();
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isEmpty,
      );
      expect(harness.owner.closed, 1);
      expect(harness.owner.savedUncertainty, isEmpty);
      expect(harness.owner.snapshot.submissionUncertain, isTrue);
      expect(harness.routed, isEmpty);
      await _choose(tester);
      await _until(tester, () => harness.routed.isNotEmpty);
      expect(harness.routed, hasLength(1));
      expect(harness.opens, 1);
      expect(
        harness.directory.records.containsKey(_source.account.value),
        isFalse,
      );
      expect(harness.events, [
        'observer:cancel',
        'observer:failed',
        'observer:cancel',
        'observer:closed',
        'owner:close',
        'owner:closed',
        'target:routed',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed stale candidate close blocks account ownership until explicit release',
    (tester) async {
      final harness = _Harness();
      harness.openGate = Completer<void>();
      await _show(tester, harness);
      final previousConnect = tester.widget<FilledButton>(_connect).onPressed!;
      final previousSwitch = tester
          .widget<IconButton>(_key('studio-mail-navigate-account'))
          .onPressed!;
      final previousLocalDrafts = tester
          .widget<OutlinedButton>(_key('studio-mail-open-local-drafts'))
          .onPressed!;
      final previousAccounts = tester
          .widget<OutlinedButton>(_key('studio-mail-known-drafts'))
          .onPressed!;
      await _press(tester, _connect);
      expect(harness.opens, 1);
      harness.owner.failClose = true;
      harness.directory.records.remove(_source.account.value);
      harness.openGate!.complete();
      await _until(tester, () => harness.clients.single.disconnections == 1);
      await _pump(tester);
      expect(harness.owner.loads, 0);
      expect(harness.owner.closeCalls, 1);
      expect(harness.owner.closed, 0);
      expect(harness.routed, isEmpty);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      previousConnect();
      previousSwitch();
      previousLocalDrafts();
      previousAccounts();
      await _pump(tester);
      expect(harness.clients, hasLength(1));
      expect(harness.opens, 1);
      expect(harness.routed, isEmpty);
      expect(find.byType(StudioMailLocalDraftsDialog), findsNothing);
      expect(find.byType(StudioMailLocalAccountsDialog), findsNothing);

      await _press(tester, _key('studio-mail-navigation-release'));
      expect(harness.owner.closeCalls, 2);
      expect(harness.owner.closed, 0);
      expect(_key('studio-mail-navigation-release'), findsOneWidget);
      harness.owner.failClose = false;
      harness.owner.closeGate = Completer<void>();
      await _press(tester, _key('studio-mail-navigation-release'));
      expect(harness.owner.closeCalls, 3);
      expect(harness.owner.closed, 0);
      previousConnect();
      previousSwitch();
      previousLocalDrafts();
      previousAccounts();
      await _pump(tester);
      expect(harness.clients, hasLength(1));
      expect(harness.opens, 1);
      expect(harness.routed, isEmpty);
      harness.owner.closeGate!.complete();
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isEmpty,
      );
      expect(harness.owner.closed, 1);
      expect(harness.routed, isEmpty);
      await _choose(tester);
      await _until(tester, () => harness.routed.isNotEmpty);
      expect(harness.routed, hasLength(1));
      expect(harness.opens, 1);
      expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native disconnect cannot retire pending target factory or load ownership',
    (tester) async {
      final harness = _Harness();
      harness.openGate = Completer<void>();
      harness.owner.loadGate = Completer<void>();
      await _show(tester, harness);
      await _press(tester, _connect);
      expect(harness.opens, 1);
      expect(harness.owner.loads, 0);
      final disconnect = _icon(_strings.disconnect);
      expect(tester.widget<IconButton>(disconnect).onPressed, isNull);
      await _press(tester, disconnect);
      expect(harness.clients.single.disconnections, 0);
      expect(harness.owner.closeCalls, 0);

      harness.openGate!.complete();
      await _until(tester, () => harness.owner.loads == 1);
      await _pump(tester);
      expect(tester.widget<IconButton>(disconnect).onPressed, isNull);
      await _press(tester, disconnect);
      expect(harness.clients.single.disconnections, 0);
      expect(harness.owner.closeCalls, 0);
      harness.owner.failClose = true;
      harness.directory.records.remove(_source.account.value);
      harness.owner.loadGate!.complete();
      await _until(tester, () => harness.clients.single.disconnections == 1);
      await _pump(tester);
      expect(harness.owner.closeCalls, 1);
      expect(harness.owner.closed, 0);
      expect(harness.routed, isEmpty);
      expect(harness.owner.mailboxStore.controllers, isEmpty);
      expect(_key('studio-mail-navigation-release'), findsOneWidget);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      harness.owner.failClose = false;
      await _press(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => harness.owner.closed == 1);
      expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
      expect(harness.owner.snapshot.submissionUncertain, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected cache remains unadopted until CAS and retains failed observer cleanup',
    (tester) async {
      final harness = _Harness(catalogOwner: true);
      final directory = _GuardedDirectory(harness.directory)
        ..refreshGate = Completer<void>();
      var closes = 0;
      await _show(
        tester,
        harness,
        directory: directory,
        onClose: () => closes++,
      );
      final staleClose = tester
          .widget<IconButton>(_icon(_strings.close))
          .onPressed!;
      await _press(tester, _connect);
      await _until(tester, () => directory.refreshAttempts == 1);
      final mailbox = harness.owner.mailboxStore;
      expect(mailbox.controllers, hasLength(1));
      expect(harness.owner.loads, 1);
      expect(find.text(_strings.mailDraftRestored), findsNothing);
      expect(
        tester.widget<IconButton>(_icon(_strings.close)).onPressed,
        isNull,
      );
      staleClose();
      expect(closes, 0);
      mailbox.cancelFailures = 1;
      harness.directory.records.remove(_source.account.value);
      directory.refreshGate!.complete();
      await _until(tester, () => mailbox.cancelCalls == 1);
      await _until(
        tester,
        () =>
            _key('studio-mail-navigation-release').evaluate().isNotEmpty &&
            tester
                    .widget<OutlinedButton>(
                      _key('studio-mail-navigation-release'),
                    )
                    .onPressed !=
                null,
      );
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      expect(harness.clients.single.disconnections, 1);
      expect(
        harness.directory.records.containsKey(_source.account.value),
        isFalse,
      );
      expect(find.text(_strings.mailDraftRestored), findsNothing);
      expect(harness.owner.snapshot.submissionUncertain, isTrue);
      staleClose();
      expect(closes, 0);

      mailbox.cancelGate = Completer<void>();
      harness.owner.closeGate = Completer<void>();
      await _press(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => mailbox.cancelCalls == 2);
      expect(harness.owner.closeCalls, 0);
      mailbox.cancelGate!.complete();
      await _until(tester, () => harness.owner.closeCalls == 1);
      expect(mailbox.cancelled, 1);
      staleClose();
      expect(closes, 0);
      harness.owner.closeGate!.complete();
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isEmpty,
      );
      expect(harness.owner.closed, 1);
      expect(harness.owner.snapshot.draft.body, _snapshot.draft.body);
      staleClose();
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary Disconnect retires a non-emitting staged observer once before explicit retry',
    (tester) async {
      final harness = _Harness();
      final mailbox = harness.owner.mailboxStore
        ..emitInitial = false
        ..cancelFailures = 1;
      var closes = 0;
      await _show(
        tester,
        harness,
        selectedAccount: false,
        onClose: () => closes++,
      );
      final staleClose = tester
          .widget<IconButton>(_icon(_strings.close))
          .onPressed!;
      await _press(tester, _connect);
      await _until(tester, () => mailbox.controllers.isNotEmpty);
      expect(find.text(_strings.mailDraftRestored), findsNothing);
      expect(
        tester.widget<IconButton>(_icon(_strings.close)).onPressed,
        isNull,
      );
      await _press(tester, _icon(_strings.disconnect));
      await _until(
        tester,
        () =>
            _key('studio-mail-navigation-release').evaluate().isNotEmpty &&
            tester
                    .widget<OutlinedButton>(
                      _key('studio-mail-navigation-release'),
                    )
                    .onPressed !=
                null,
      );
      expect(mailbox.cancelCalls, 1);
      expect(mailbox.cancelled, 0);
      expect(harness.owner.closeCalls, 0);
      expect(harness.clients.single.disconnections, 1);
      expect(harness.opens, 1);
      staleClose();
      expect(closes, 0);

      mailbox.cancelGate = Completer<void>();
      await _press(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => mailbox.cancelCalls == 2);
      expect(harness.owner.closeCalls, 0);
      mailbox.cancelGate!.complete();
      await _until(tester, () => harness.owner.closed == 1);
      await _pump(tester);
      expect(mailbox.cancelled, 1);
      expect(harness.owner.closeCalls, 1);
      expect(find.text(_strings.mailDraftRestored), findsNothing);
      staleClose();
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing a staged observer drains its candidate only once', (
    tester,
  ) async {
    final harness = _Harness();
    final mailbox = harness.owner.mailboxStore
      ..emitInitial = false
      ..cancelGate = Completer<void>();
    await _show(tester, harness, selectedAccount: false);
    await _press(tester, _connect);
    await _until(tester, () => mailbox.controllers.isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await _until(tester, () => mailbox.cancelCalls == 1);
    expect(harness.owner.closeCalls, 0);
    mailbox.cancelGate!.complete();
    await _until(tester, () => harness.owner.closed == 1);
    await _pump(tester);
    expect(mailbox.cancelCalls, 1);
    expect(harness.owner.closeCalls, 1);
    expect(harness.clients.single.disconnections, 1);
    expect(tester.takeException(), isNull);
  });
}
