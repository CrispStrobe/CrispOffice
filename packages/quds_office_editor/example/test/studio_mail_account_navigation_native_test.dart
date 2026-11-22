import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_account_navigation_strings.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_local_accounts_dialog.dart';
import 'package:quds_office_studio/studio_mail_local_drafts.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _first = StudioMailCredentials(
  email: 'first@example.test',
  password: 'first-secret',
  imapHost: 'imap.first.test',
  smtpHost: 'smtp.first.test',
  manual: true,
  startTls: false,
);
const _second = StudioMailCredentials(
  email: 'second@example.test',
  password: 'second-secret',
  imapHost: 'imap.second.test',
  smtpHost: 'smtp.second.test',
  manual: true,
  startTls: true,
);

StudioMailDraftAccount _identity(StudioMailCredentials credentials) {
  final route = credentials.connectionIdentity;
  return StudioMailDraftAccount(
    provider: 'imap',
    endpoint: Uri(
      scheme: route.imapStartTls ? 'imap' : 'imaps',
      host: route.imapHost,
      port: route.imapPort,
    ).toString(),
    login: route.imapLogin,
    sender: route.sender,
  );
}

final class _Directory
    implements
        StudioMailLocalAccountStore,
        StudioMailLocalAccountReconnectStore {
  final records = <String, MailLocalAccountRecord>{};
  Completer<void>? rememberGate;
  // Attempts include blocked CAS operations; remembers counts committed writes.
  int rememberAttempts = 0;
  int remembers = 0;
  int selectedRemembers = 0;

  @override
  Future<List<MailLocalAccountRecord>> load() async =>
      List.unmodifiable(records.values);

  @override
  Future<void> remember(StudioMailDraftAccount identity) async {
    rememberAttempts++;
    _remember(identity);
  }

  @override
  Future<void> rememberSelected(
    StudioMailDraftAccount identity, {
    required MailLocalAccountRecord expectedRecord,
  }) async {
    rememberAttempts++;
    selectedRemembers++;
    await rememberGate?.future;
    final current = records[identity.account.value];
    if (current == null ||
        !current.hasSameIdentity(expectedRecord) ||
        current.revision != expectedRecord.revision ||
        current.lastConnectedAt.millisecondsSinceEpoch !=
            expectedRecord.lastConnectedAt.millisecondsSinceEpoch) {
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);
    }
    _remember(identity);
  }

  void _remember(StudioMailDraftAccount identity) {
    remembers++;
    final previous = records[identity.account.value];
    records[identity.account.value] = MailLocalAccountRecord(
      id: identity.account.value,
      provider: identity.provider,
      endpoint: identity.endpoint,
      login: identity.login,
      sender: identity.sender,
      revision: (previous?.revision ?? 0) + 1,
      lastConnectedAt: DateTime.utc(2026, 11, 22),
    );
  }

  @override
  Future<void> forget(MailLocalAccountRecord record) async {
    records.remove(record.id);
  }

  StudioMailAccountNavigationTarget target(StudioMailDraftAccount identity) =>
      StudioMailAccountNavigationTarget.fromRecord(
        records[identity.account.value]!,
      );
}

final class _Credentials extends Fake
    implements StudioMailCredentialStore, StudioMailAccountCatalogStore {
  _Credentials([List<StudioMailCredentials> values = const [_first, _second]])
    : catalog = StudioMailAccountCatalog(
        accounts: [
          for (final value in values)
            StudioMailSavedAccount(id: value.accountId, credentials: value),
        ],
        selectedAccountId: values.firstOrNull?.accountId,
      );

  StudioMailAccountCatalog catalog;

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() async =>
      StudioMailAccountCatalogResult.success(catalog);

  @override
  Future<StudioMailAccountCatalogResult> saveAccount(
    StudioMailCredentials credentials,
  ) async => StudioMailAccountCatalogResult.success(catalog);

  @override
  Future<StudioMailAccountCatalogResult> selectAccount(String id) async {
    catalog = StudioMailAccountCatalog(
      accounts: catalog.accounts,
      selectedAccountId: id,
    );
    return StudioMailAccountCatalogResult.success(catalog);
  }
}

final class _Loader extends Fake implements StudioMailMessageLoader {
  @override
  void dispose() {}
  @override
  void cancel() {}
}

final class _CatalogStore extends Fake
    implements StudioMailDraftStore, StudioMailDraftCatalog {
  _CatalogStore(this.account);
  @override
  final MailAccountId account;
  @override
  String get selectedDraftId => 'reconnect';
  @override
  int get selectionEpoch => 0;
  int closes = 0;

  @override
  Future<StudioMailStoredDraft?> load() async => null;

  @override
  Future<void> close() async {
    closes++;
  }
}

final class _Client extends Fake implements mail.MailClient {
  _Client({
    this.connectGate,
    this.folderGate,
    this.selectGate,
    this.headerGate,
  });

  Completer<void>? connectGate;
  Completer<void>? folderGate;
  final Completer<void>? selectGate;
  Completer<void>? headerGate;
  final inbox = mail.Mailbox(
    encodedName: 'INBOX',
    encodedPath: 'INBOX',
    flags: [mail.MailboxFlag.inbox],
    pathSeparator: '/',
    uidValidity: 7,
    uidNext: 1,
  );
  int connections = 0;
  int disconnections = 0;
  int folderReads = 0;
  int selections = 0;
  int headerReads = 0;

  @override
  mail.Mailbox get selectedMailbox => inbox;
  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    connections++;
    await connectGate?.future;
  }

  @override
  Future<void> disconnect() async {
    disconnections++;
  }

  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async {
    folderReads++;
    await folderGate?.future;
    return [inbox];
  }

  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async {
    selections++;
    await selectGate?.future;
    return mailbox;
  }

  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async {
    headerReads++;
    await headerGate?.future;
    return [];
  }
}

final class _Browser extends Fake
    implements
        StudioMailMessageLoader,
        StudioMailMailboxBrowser,
        StudioMailMembershipActions {
  _Browser({this.headerGate, this.capabilityGate});

  final Completer<void>? headerGate;
  final Completer<void>? capabilityGate;
  int headerReads = 0;
  int capabilityReads = 0;
  int disposals = 0;

  @override
  Future<StudioMailHeaderPage> fetchHeaders(
    mail.Mailbox selectedMailbox, {
    MailCursor? cursor,
    int limit = 50,
  }) async {
    headerReads++;
    await headerGate?.future;
    return StudioMailHeaderPage(messages: []);
  }

  @override
  Future<MailCapabilities> membershipCapabilities() async {
    capabilityReads++;
    await capabilityGate?.future;
    return const MailCapabilities.none();
  }

  @override
  void dispose() => disposals++;
  @override
  void cancel() {}
}

/// Adds observable owner/reader gates without weakening account identity.
final class _ObservedStore extends Fake
    implements StudioMailDraftStore, StudioMailDraftCatalog {
  _ObservedStore(this.delegate, this.account, {this.loadGate});

  final StudioMailDraftStore delegate;
  @override
  final MailAccountId account;
  final Completer<void>? loadGate;
  Completer<void>? closeGate;
  bool failClose = false;
  int loads = 0;
  int closeAttempts = 0;
  int closes = 0;

  @override
  String get selectedDraftId => 'selected';
  @override
  int get selectionEpoch => 0;

  @override
  Future<StudioMailDraftCatalogPage> listDrafts({String? afterId}) async =>
      StudioMailDraftCatalogPage(drafts: const []);

  @override
  Future<StudioMailStoredDraft?> load() async {
    loads++;
    await loadGate?.future;
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
  Future<void> close() async {
    closeAttempts++;
    await closeGate?.future;
    if (failClose) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    await delegate.close();
    closes++;
  }
}

final class _ClosingStore implements StudioMailDraftStore {
  _ClosingStore(this.delegate, this.gate, this.events);
  final StudioMailDraftStore delegate;
  final Completer<void>? gate;
  final List<String> events;
  int loads = 0;

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
  Future<void> close() async {
    events.add('closing');
    await gate?.future;
    await delegate.close();
    events.add('closed');
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
String _fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var turn = 0; turn < 100 && !ready(); turn++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(ready(), isTrue, reason: 'Native account ownership must settle.');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _show(
  WidgetTester tester, {
  required _Directory directory,
  required List<mail.MailAccount> created,
  required List<_Client> clients,
  MemoryStudioMailDrafts? drafts,
  _Credentials? credentials,
  StudioMailAccountNavigationTarget? initialAccount,
  StudioMailDraftStoreFactory? open,
  bool autoConnect = false,
  void Function(_Client)? configureClient,
  _Client Function()? clientBuilder,
  StudioMailMessageLoader? loader,
  VoidCallback? onClose,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1050));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        onClose: onClose,
        credentialStore: credentials ?? _Credentials(),
        localAccountStore: directory,
        initialAccount: initialAccount,
        autoConnectSavedAccount: autoConnect,
        draftStoreFactory: open ?? (drafts ?? MemoryStudioMailDrafts()).open,
        clientFactory: (account) {
          created.add(account);
          final client = clientBuilder?.call() ?? _Client();
          configureClient?.call(client);
          clients.add(client);
          return client;
        },
        messageLoaderFactory: (_) => loader ?? _Loader(),
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _connect(WidgetTester tester) =>
    _tap(tester, find.widgetWithText(FilledButton, _strings.connect));

Future<void> _choose(WidgetTester tester, StudioMailDraftAccount target) async {
  await _tap(tester, _key('studio-mail-navigate-account'));
  await _tap(
    tester,
    _key('studio-mail-navigation-account-${target.account.value}'),
  );
  await _tap(tester, _key('studio-mail-account-navigation-continue'));
}

void main() {
  testWidgets(
    'selected account uses only its saved route and requires explicit Connect',
    (tester) async {
      final directory = _Directory();
      await directory.remember(_identity(_first));
      await directory.remember(_identity(_second));
      final created = <mail.MailAccount>[];
      final clients = <_Client>[];
      final drafts = MemoryStudioMailDrafts();
      await _show(
        tester,
        directory: directory,
        created: created,
        clients: clients,
        drafts: drafts,
        initialAccount: directory.target(_identity(_second)),
        autoConnect: true,
      );
      expect(created, isEmpty);
      expect(drafts.identities, isEmpty);
      expect(_fieldText(tester, _strings.emailAddress), _second.email);
      expect(_fieldText(tester, _strings.password), _second.password);
      expect(_fieldText(tester, _strings.smtpHost), _second.smtpHost);
      await _connect(tester);
      expect(created.single.email, _second.email);
      expect(created.single.incoming.serverConfig.hostname, _second.imapHost);
      expect(drafts.identities.single.account, _identity(_second).account);
      expect(clients.single.folderReads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edited identity fails before client construction or local store access',
    (tester) async {
      final directory = _Directory();
      await directory.remember(_identity(_second));
      final created = <mail.MailAccount>[];
      final drafts = MemoryStudioMailDrafts();
      await _show(
        tester,
        directory: directory,
        created: created,
        clients: [],
        drafts: drafts,
        initialAccount: directory.target(_identity(_second)),
      );
      await tester.enterText(
        _field(_strings.emailAddress),
        'different@example.test',
      );
      await _connect(tester);
      expect(created, isEmpty);
      expect(drafts.identities, isEmpty);
      expect(
        find.text(_strings.mailAccountNavigationIdentityMismatch),
        findsOneWidget,
      );
    },
  );

  testWidgets('forgotten destination fails before client construction', (
    tester,
  ) async {
    final directory = _Directory();
    final identity = _identity(_second);
    await directory.remember(identity);
    final created = <mail.MailAccount>[];
    await _show(
      tester,
      directory: directory,
      created: created,
      clients: [],
      initialAccount: directory.target(identity),
    );
    directory.records.clear();
    await _connect(tester);
    expect(created, isEmpty);
    expect(find.text(_strings.mailAccountNavigationChanged), findsOneWidget);
  });

  for (final stage in [
    'connect',
    'folders',
    'select',
    'headers',
    'capabilities',
  ]) {
    for (final remove in [true, false]) {
      testWidgets(
        '${remove ? 'removed' : 'revised'} destination during $stage stops the next provider step',
        (tester) async {
          final directory = _Directory();
          final identity = _identity(_second);
          await directory.remember(identity);
          final gate = Completer<void>();
          final client = _Client(
            connectGate: stage == 'connect' ? gate : null,
            folderGate: stage == 'folders' ? gate : null,
            selectGate: stage == 'select' ? gate : null,
          );
          final browser = _Browser(
            headerGate: stage == 'headers' ? gate : null,
            capabilityGate: stage == 'capabilities' ? gate : null,
          );
          final drafts = MemoryStudioMailDrafts();
          await _show(
            tester,
            directory: directory,
            created: [],
            clients: [],
            drafts: drafts,
            initialAccount: directory.target(identity),
            clientBuilder: () => client,
            loader: browser,
          );
          await _connect(tester);
          expect(client.connections, 1);
          expect(drafts.identities, isEmpty);
          if (remove) {
            directory.records.remove(identity.account.value);
          } else {
            await directory.remember(identity);
          }
          gate.complete();
          await _pump(tester);
          expect(client.disconnections, 1);
          expect(browser.disposals, 1);
          expect(drafts.identities, isEmpty);
          expect(directory.selectedRemembers, 0);
          expect(
            find.text(_strings.mailAccountNavigationChanged),
            findsOneWidget,
          );
          if (stage == 'connect') expect(client.folderReads, 0);
          if (stage == 'folders') expect(client.selections, 0);
          if (stage == 'select') expect(browser.headerReads, 0);
          if (stage == 'headers') expect(browser.capabilityReads, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('legacy header adapter also rejects a removed pending target', (
    tester,
  ) async {
    final directory = _Directory();
    final identity = _identity(_second);
    await directory.remember(identity);
    final gate = Completer<void>();
    final client = _Client(headerGate: gate);
    final drafts = MemoryStudioMailDrafts();
    await _show(
      tester,
      directory: directory,
      created: [],
      clients: [],
      drafts: drafts,
      initialAccount: directory.target(identity),
      clientBuilder: () => client,
    );
    await _connect(tester);
    expect(client.headerReads, 1);
    directory.records.clear();
    gate.complete();
    await _pump(tester);
    expect(client.disconnections, 1);
    expect(drafts.identities, isEmpty);
    expect(find.text(_strings.mailAccountNavigationChanged), findsOneWidget);
  });

  for (final stage in ['open', 'load']) {
    for (final remove in [true, false]) {
      testWidgets(
        '${remove ? 'removed' : 'revised'} destination during draft $stage cannot publish local content',
        (tester) async {
          final directory = _Directory();
          final identity = _identity(_second);
          await directory.remember(identity);
          final gate = Completer<void>();
          final drafts = MemoryStudioMailDrafts();
          drafts.records[identity.account.value] = const StudioMailStoredDraft(
            draft: StudioMailDraft(
              to: '',
              subject: 'Private draft',
              body: 'Keep private',
            ),
            submissionUncertain: true,
          );
          if (stage == 'open') drafts.openGate = gate;
          final owners = <_ObservedStore>[];
          final clients = <_Client>[];
          await _show(
            tester,
            directory: directory,
            created: [],
            clients: clients,
            initialAccount: directory.target(identity),
            open: (account) async {
              final owner = _ObservedStore(
                await drafts.open(account),
                account.account,
                loadGate: stage == 'load' ? gate : null,
              );
              owners.add(owner);
              return owner;
            },
          );
          await _connect(tester);
          expect(drafts.identities, hasLength(1));
          if (remove) {
            directory.records.clear();
          } else {
            await directory.remember(identity);
          }
          gate.complete();
          await _pump(tester);
          expect(owners.single.loads, stage == 'open' ? 0 : 1);
          expect(owners.single.closes, 1);
          expect(clients.single.disconnections, 1);
          expect(directory.selectedRemembers, 0);
          expect(find.text(_strings.mailDraftRestored), findsNothing);
          expect(
            find.text(_strings.mailAccountNavigationChanged),
            findsOneWidget,
          );
          expect(
            drafts.records[identity.account.value]!.draft.body,
            'Keep private',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final replacement in ['target', 'directory', 'draft factory']) {
    testWidgets('replacing host $replacement retires a pending IMAP sign-in', (
      tester,
    ) async {
      final directory = _Directory();
      final identity = _identity(_second);
      await directory.remember(identity);
      await directory.remember(_identity(_first));
      final target = directory.target(identity);
      final gate = Completer<void>();
      final client = _Client(connectGate: gate);
      final drafts = MemoryStudioMailDrafts();
      final credentials = _Credentials();
      final StudioMailDraftStoreFactory open = drafts.open;
      final clients = <_Client>[];
      final created = <mail.MailAccount>[];
      await _show(
        tester,
        directory: directory,
        created: created,
        clients: clients,
        initialAccount: target,
        credentials: credentials,
        open: open,
        clientBuilder: () => client,
      );
      await _connect(tester);
      await _show(
        tester,
        directory: replacement == 'directory' ? _Directory() : directory,
        created: created,
        clients: clients,
        initialAccount: replacement == 'target'
            ? directory.target(_identity(_first))
            : target,
        credentials: credentials,
        open: replacement == 'draft factory'
            ? MemoryStudioMailDrafts().open
            : open,
        clientBuilder: () => client,
      );
      gate.complete();
      await _pump(tester);
      expect(created, hasLength(1));
      expect(client.disconnections, 1);
      expect(client.folderReads, 0);
      expect(drafts.identities, isEmpty);
      expect(find.text(_strings.mailAccountNavigationChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final remove in [true, false]) {
    testWidgets(
      '${remove ? 'removed' : 'revised'} destination during final remember is never recreated',
      (tester) async {
        final directory = _Directory();
        final identity = _identity(_second);
        await directory.remember(identity);
        final target = directory.target(identity);
        directory.rememberGate = Completer<void>();
        final drafts = MemoryStudioMailDrafts();
        final clients = <_Client>[];
        await _show(
          tester,
          directory: directory,
          created: [],
          clients: clients,
          initialAccount: target,
          open: (account) async =>
              _ObservedStore(await drafts.open(account), account.account),
        );
        await _connect(tester);
        expect(directory.selectedRemembers, 1);
        if (remove) {
          directory.records.clear();
        } else {
          await directory.remember(identity);
        }
        directory.rememberGate!.complete();
        await _pump(tester);
        expect(
          directory.records[identity.account.value]?.revision,
          remove ? null : 2,
        );
        expect(clients.single.disconnections, 1);
        expect(drafts.closes, 1);
        expect(
          find.text(_strings.mailAccountNavigationChanged),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ambiguous SMTP routes require a choice and preserve STARTTLS prefill',
    (tester) async {
      const alternate = StudioMailCredentials(
        email: 'second@example.test',
        password: 'alternate-secret',
        imapHost: 'imap.second.test',
        smtpHost: 'different.smtp.test',
        manual: true,
        startTls: true,
      );
      final directory = _Directory();
      await directory.remember(_identity(_second));
      final created = <mail.MailAccount>[];
      await _show(
        tester,
        directory: directory,
        created: created,
        clients: [],
        credentials: _Credentials([_second, alternate]),
        initialAccount: directory.target(_identity(_second)),
        autoConnect: true,
      );
      expect(_fieldText(tester, _strings.password), isEmpty);
      expect(_fieldText(tester, _strings.smtpHost), isEmpty);
      expect(_fieldText(tester, _strings.imapHost), _second.imapHost);
      await _connect(tester);
      expect(created, isEmpty);
      expect(
        find.text(_strings.mailAccountNavigationRouteUnavailable),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'switch saves uncertainty and drains the old store before showing another setup',
    (tester) async {
      final directory = _Directory();
      final first = _identity(_first);
      final second = _identity(_second);
      await directory.remember(first);
      await directory.remember(second);
      final drafts = MemoryStudioMailDrafts();
      drafts.records[first.account.value] = const StudioMailStoredDraft(
        draft: StudioMailDraft(
          to: '',
          subject: 'Keep first',
          body: 'Unsent first',
        ),
        submissionUncertain: true,
      );
      final closeGate = Completer<void>();
      final events = <String>[];
      final created = <mail.MailAccount>[];
      final clients = <_Client>[];
      await _show(
        tester,
        directory: directory,
        created: created,
        clients: clients,
        drafts: drafts,
        open: (identity) async {
          final store = await drafts.open(identity);
          return identity.account == first.account
              ? _ClosingStore(store, closeGate, events)
              : store;
        },
      );
      await _connect(tester);
      await _choose(tester, second);
      expect(events, ['closing']);
      expect(_key('studio-mail-navigation-target'), findsNothing);
      expect(created, hasLength(1));
      expect(drafts.saved.single.submissionUncertain, isTrue);
      expect(drafts.records[first.account.value]!.draft.body, 'Unsent first');
      closeGate.complete();
      await _pump(tester);
      expect(events, ['closing', 'closed']);
      expect(_fieldText(tester, _strings.emailAddress), _second.email);
      expect(created, hasLength(1));
      expect(clients.single.disconnections, 1);
      await _connect(tester);
      expect(created.map((value) => value.email), [
        _first.email,
        _second.email,
      ]);
      expect(drafts.identities.map((value) => value.account), [
        first.account,
        second.account,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed draft save retains the original connected account', (
    tester,
  ) async {
    final directory = _Directory();
    final first = _identity(_first);
    final second = _identity(_second);
    await directory.remember(first);
    await directory.remember(second);
    final drafts = MemoryStudioMailDrafts();
    drafts.records[first.account.value] = const StudioMailStoredDraft(
      draft: StudioMailDraft(to: '', subject: 'Keep me', body: 'Recovery work'),
      submissionUncertain: false,
    );
    final clients = <_Client>[];
    final created = <mail.MailAccount>[];
    await _show(
      tester,
      directory: directory,
      created: created,
      clients: clients,
      drafts: drafts,
    );
    await _connect(tester);
    drafts.failSave = true;
    await _choose(tester, second);
    expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
    expect(clients.single.disconnections, 0);
    expect(drafts.closes, 0);
    expect(_key('studio-mail-navigation-target'), findsNothing);
    expect(find.byTooltip(_strings.disconnect), findsOneWidget);
    expect(drafts.records[first.account.value]!.draft.body, 'Recovery work');
    drafts.failSave = false;
    await _choose(tester, second);
    expect(clients.single.disconnections, 1);
    expect(_fieldText(tester, _strings.emailAddress), _second.email);
  });

  testWidgets('removal during draft persistence keeps the old connection', (
    tester,
  ) async {
    final directory = _Directory();
    final first = _identity(_first);
    final second = _identity(_second);
    await directory.remember(first);
    await directory.remember(second);
    final drafts = MemoryStudioMailDrafts();
    drafts.records[first.account.value] = const StudioMailStoredDraft(
      draft: StudioMailDraft(to: '', subject: 'First', body: 'First body'),
      submissionUncertain: false,
    );
    final clients = <_Client>[];
    await _show(
      tester,
      directory: directory,
      created: [],
      clients: clients,
      drafts: drafts,
    );
    await _connect(tester);
    final gate = Completer<void>();
    drafts.saveGate = gate;
    await _choose(tester, second);
    directory.records.remove(second.account.value);
    gate.complete();
    await _pump(tester);
    expect(clients.single.disconnections, 0);
    expect(drafts.closes, 0);
    expect(find.text(_strings.mailAccountNavigationFailed), findsOneWidget);
  });

  testWidgets(
    'failed owner release retains source ownership until explicit release retry',
    (tester) async {
      final directory = _Directory();
      final first = _identity(_first);
      final second = _identity(_second);
      await directory.remember(first);
      await directory.remember(second);
      final drafts = MemoryStudioMailDrafts();
      final owners = <_ObservedStore>[];
      final clients = <_Client>[];
      await _show(
        tester,
        directory: directory,
        created: [],
        clients: clients,
        open: (account) async {
          final owner = _ObservedStore(
            await drafts.open(account),
            account.account,
          );
          owners.add(owner);
          return owner;
        },
      );
      await _connect(tester);
      owners.single.failClose = true;
      await _choose(tester, second);
      expect(owners.single.closeAttempts, 1);
      expect(owners.single.closes, 0);
      expect(clients.single.disconnections, 1);
      expect(_key('studio-mail-navigation-target'), findsNothing);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      expect(_key('studio-mail-navigation-release'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, _strings.connect),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, _key('studio-mail-navigation-release'));
      expect(owners.single.closeAttempts, 2);
      expect(owners.single.closes, 0);
      expect(_key('studio-mail-navigation-release'), findsOneWidget);
      owners.single.failClose = false;
      await _tap(tester, _key('studio-mail-navigation-release'));
      expect(owners.single.closeAttempts, 3);
      expect(owners.single.closes, 1);
      expect(_key('studio-mail-navigation-release'), findsNothing);
      await _choose(tester, second);
      expect(owners.single.closes, 1);
      expect(clients.single.disconnections, 1);
      expect(_fieldText(tester, _strings.emailAddress), _second.email);
      expect(tester.takeException(), isNull);
    },
  );

  for (final destination in ['connect', 'provider setup']) {
    testWidgets(
      'late unselected owner acquisition drains before a subsequent $destination',
      (tester) async {
        final directory = _Directory();
        final identity = _identity(_first);
        await directory.remember(identity);
        final drafts = MemoryStudioMailDrafts();
        final owners = <_ObservedStore>[];
        final clients = <_Client>[];
        final gate = Completer<void>();
        var acquisitions = 0;
        await _show(
          tester,
          directory: directory,
          created: [],
          clients: clients,
          open: (account) async {
            acquisitions++;
            if (acquisitions == 1) await gate.future;
            final owner = _ObservedStore(
              await drafts.open(account),
              account.account,
            );
            owners.add(owner);
            return owner;
          },
          clientBuilder: () {
            if (clients.isNotEmpty) expect(owners.first.closes, 1);
            return _Client();
          },
        );
        await _connect(tester);
        expect(acquisitions, 1);
        expect(owners, isEmpty);
        // Selected-account acquisition is fenced by native_release_test.
        // An ordinary connection may disconnect; its late owner must still
        // drain before another connection or provider setup can start.
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == _strings.disconnect,
                ),
              )
              .onPressed,
          isNotNull,
        );
        await _tap(tester, find.byTooltip(_strings.disconnect));
        if (destination == 'connect') {
          await tester.enterText(_field(_strings.password), _first.password);
          await _connect(tester);
        } else {
          await _tap(tester, _key('studio-mail-open-ews'));
        }
        expect(clients, hasLength(1));
        expect(_key('ews-connect'), findsNothing);
        expect(acquisitions, 1);
        gate.complete();
        await _pump(tester);
        expect(owners.first.closes, 1);
        expect(owners.first.loads, 0);
        if (destination == 'connect') {
          expect(clients, hasLength(2));
          expect(acquisitions, 2);
          expect(owners.last.loads, 1);
        } else {
          expect(_key('ews-connect'), findsOneWidget);
          expect(clients, hasLength(1));
          expect(acquisitions, 1);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a failed disconnected owner blocks $destination until explicit release retry',
      (tester) async {
        final directory = _Directory();
        await directory.remember(_identity(_first));
        final drafts = MemoryStudioMailDrafts();
        final owners = <_ObservedStore>[];
        final clients = <_Client>[];
        await _show(
          tester,
          directory: directory,
          created: [],
          clients: clients,
          open: (account) async {
            final owner = _ObservedStore(
              await drafts.open(account),
              account.account,
            );
            owners.add(owner);
            return owner;
          },
        );
        await _connect(tester);
        final oldOwner = owners.single;
        oldOwner.failClose = true;
        await _tap(tester, find.byTooltip(_strings.disconnect));
        expect(oldOwner.closeAttempts, 1);
        Future<void> attempt() async {
          if (destination == 'connect') {
            await tester.enterText(_field(_strings.password), _first.password);
            await _connect(tester);
          } else {
            await _tap(tester, _key('studio-mail-open-ews'));
          }
        }

        await attempt();
        expect(oldOwner.closeAttempts, 1);
        expect(oldOwner.closes, 0);
        expect(clients, hasLength(1));
        expect(owners, hasLength(1));
        expect(_key('ews-connect'), findsNothing);
        await _tap(tester, _key('studio-mail-navigation-release'));
        expect(oldOwner.closeAttempts, 2);
        expect(oldOwner.closes, 0);
        oldOwner.failClose = false;
        await _tap(tester, _key('studio-mail-navigation-release'));
        await _until(tester, () => oldOwner.closes == 1);
        await attempt();
        expect(oldOwner.closes, 1);
        if (destination == 'connect') {
          expect(clients, hasLength(2));
          expect(owners, hasLength(2));
        } else {
          expect(_key('ews-connect'), findsOneWidget);
          expect(clients, hasLength(1));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final stage in ['open', 'load']) {
    for (final localDrafts in [false, true]) {
      testWidgets(
        'pending ordinary $stage blocks Close and local ${localDrafts ? 'drafts' : 'accounts'} after Disconnect',
        (tester) async {
          final directory = _Directory();
          await directory.remember(_identity(_first));
          final drafts = MemoryStudioMailDrafts();
          final owners = <_ObservedStore>[];
          final clients = <_Client>[];
          final gate = Completer<void>();
          var acquisitions = 0;
          var closes = 0;
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          await _show(
            tester,
            directory: directory,
            created: [],
            clients: clients,
            onClose: () => closes++,
            open: (account) async {
              final first = ++acquisitions == 1;
              if (first && stage == 'open') await gate.future;
              final owner = _ObservedStore(
                await drafts.open(account),
                account.account,
                loadGate: first && stage == 'load' ? gate : null,
              );
              owners.add(owner);
              return owner;
            },
          );
          final entry = _key(
            localDrafts
                ? 'studio-mail-open-local-drafts'
                : 'studio-mail-known-drafts',
          );
          final staleEntry = tester.widget<OutlinedButton>(entry).onPressed!;
          final staleClose = tester
              .widget<IconButton>(_icon(_strings.close))
              .onPressed!;
          await _connect(tester);
          expect(acquisitions, 1);
          expect(
            tester.widget<IconButton>(_icon(_strings.close)).onPressed,
            isNull,
          );
          staleClose();
          expect(closes, 0);
          await _tap(tester, _icon(_strings.disconnect));
          expect(clients.single.disconnections, 1);
          staleEntry();
          staleClose();
          await _pump(tester);
          expect(tester.widget<OutlinedButton>(entry).onPressed, isNull);
          expect(find.byType(StudioMailLocalAccountsDialog), findsNothing);
          expect(find.byType(StudioMailLocalDraftsDialog), findsNothing);
          expect(acquisitions, 1);
          expect(closes, 0);

          gate.complete();
          await _until(
            tester,
            () => owners.isNotEmpty && owners.first.closes == 1,
          );
          await _pump(tester);
          expect(owners.first.loads, stage == 'open' ? 0 : 1);
          expect(acquisitions, 1);
          expect(tester.widget<OutlinedButton>(entry).onPressed, isNotNull);
          staleClose();
          expect(closes, 1);
          await _tap(tester, entry);
          if (localDrafts) {
            await _until(tester, () => acquisitions == 2);
            expect(find.byType(StudioMailLocalDraftsDialog), findsOneWidget);
          } else {
            expect(find.byType(StudioMailLocalAccountsDialog), findsOneWidget);
            expect(acquisitions, 1);
          }
          expect(owners.first.closes, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'ordinary close failure keeps Close and local entries blocked until explicit release',
    (tester) async {
      final directory = _Directory();
      await directory.remember(_identity(_first));
      final drafts = MemoryStudioMailDrafts();
      final owners = <_ObservedStore>[];
      var closes = 0;
      await _show(
        tester,
        directory: directory,
        created: [],
        clients: [],
        onClose: () => closes++,
        open: (account) async {
          final owner = _ObservedStore(
            await drafts.open(account),
            account.account,
          );
          owners.add(owner);
          return owner;
        },
      );
      final staleClose = tester
          .widget<IconButton>(_icon(_strings.close))
          .onPressed!;
      final staleAccounts = tester
          .widget<OutlinedButton>(_key('studio-mail-known-drafts'))
          .onPressed!;
      final staleDrafts = tester
          .widget<OutlinedButton>(_key('studio-mail-open-local-drafts'))
          .onPressed!;
      await _connect(tester);
      final owner = owners.single;
      final gate = Completer<void>();
      owner.closeGate = gate;
      owner.failClose = true;
      addTearDown(() {
        owner.failClose = false;
        if (!gate.isCompleted) gate.complete();
      });
      await _tap(tester, _icon(_strings.disconnect));
      expect(owner.closeAttempts, 1);
      expect(
        tester.widget<IconButton>(_icon(_strings.close)).onPressed,
        isNull,
      );
      staleClose();
      staleAccounts();
      staleDrafts();
      await _pump(tester);
      expect(closes, 0);
      expect(owners, hasLength(1));
      expect(find.byType(StudioMailLocalAccountsDialog), findsNothing);
      expect(find.byType(StudioMailLocalDraftsDialog), findsNothing);

      gate.complete();
      await _until(
        tester,
        () => _key('studio-mail-navigation-release').evaluate().isNotEmpty,
      );
      expect(owner.closeAttempts, 1);
      staleClose();
      staleAccounts();
      staleDrafts();
      await _pump(tester);
      expect(closes, 0);
      expect(owner.closeAttempts, 1);
      await _tap(tester, _key('studio-mail-navigation-release'));
      expect(owner.closeAttempts, 2);
      expect(owner.closes, 0);
      expect(
        tester.widget<IconButton>(_icon(_strings.close)).onPressed,
        isNull,
      );
      owner.failClose = false;
      await _tap(tester, _key('studio-mail-navigation-release'));
      await _until(tester, () => owner.closes == 1);
      await _pump(tester);
      expect(_key('studio-mail-navigation-release'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(_key('studio-mail-known-drafts'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(_key('studio-mail-open-local-drafts'))
            .onPressed,
        isNotNull,
      );
      staleClose();
      expect(closes, 1);
      expect(owner.closeAttempts, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful target can disconnect and reconnect after directory revision advances',
    (tester) async {
      final directory = _Directory();
      final identity = _identity(_second);
      await directory.remember(identity);
      final initial = directory.target(identity);
      final created = <mail.MailAccount>[];
      final clients = <_Client>[];
      final owners = <_CatalogStore>[];
      await _show(
        tester,
        directory: directory,
        created: created,
        clients: clients,
        initialAccount: initial,
        open: (account) async {
          final owner = _CatalogStore(account.account);
          owners.add(owner);
          return owner;
        },
      );
      await _connect(tester);
      expect(owners.single.account, identity.account);
      expect(
        directory.records[identity.account.value]!.revision,
        initial.record.revision + 1,
      );
      await _tap(tester, find.byTooltip(_strings.disconnect));
      await tester.enterText(_field(_strings.password), _second.password);
      await _connect(tester);
      expect(created, hasLength(2));
      expect(owners, hasLength(2));
      expect(owners.first.closes, 1);
      expect(clients.last.folderReads, 1);
      expect(
        directory.records[identity.account.value]!.revision,
        initial.record.revision + 2,
      );
      expect(find.text(_strings.mailAccountNavigationChanged), findsNothing);
    },
  );

  testWidgets('fresh catalog connection still registers its account', (
    tester,
  ) async {
    final directory = _Directory();
    final owners = <_CatalogStore>[];
    await _show(
      tester,
      directory: directory,
      created: [],
      clients: [],
      open: (account) async {
        final owner = _CatalogStore(account.account);
        owners.add(owner);
        return owner;
      },
    );
    await _connect(tester);
    final identity = _identity(_first);
    expect(owners.single.account, identity.account);
    expect(directory.records[identity.account.value]!.revision, 1);
    expect(directory.remembers, 1);
    expect(directory.selectedRemembers, 0);
    expect(tester.takeException(), isNull);
  });

  for (final removed in [true, false]) {
    testWidgets(
      'atomic selected refresh preserves a ${removed ? 'removed' : 'revised'} native shortcut',
      (tester) async {
        final directory = _Directory();
        final identity = _identity(_second);
        await directory.remember(identity);
        final selected = directory.target(identity);
        final gate = Completer<void>();
        directory.rememberGate = gate;
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final clients = <_Client>[];
        final owners = <_CatalogStore>[];
        await _show(
          tester,
          directory: directory,
          created: [],
          clients: clients,
          initialAccount: selected,
          open: (account) async {
            final owner = _CatalogStore(account.account);
            owners.add(owner);
            return owner;
          },
        );
        await _connect(tester);
        expect(directory.rememberAttempts, 2);
        if (removed) {
          directory.records.remove(identity.account.value);
        } else {
          directory._remember(identity);
        }
        final replacement = directory.records[identity.account.value];
        final committedWrites = directory.remembers;
        gate.complete();
        await _pump(tester);
        expect(directory.records[identity.account.value], same(replacement));
        expect(directory.remembers, committedWrites);
        expect(directory.selectedRemembers, 1);
        expect(owners.single.closes, 1);
        expect(clients.single.disconnections, 1);
        expect(
          find.text(_strings.mailAccountNavigationChanged),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final stage in ['connect', 'folders', 'headers']) {
    testWidgets('removed target after delayed $stage cannot admit later work', (
      tester,
    ) async {
      final directory = _Directory();
      final identity = _identity(_second);
      await directory.remember(identity);
      final gate = Completer<void>();
      final clients = <_Client>[];
      final drafts = MemoryStudioMailDrafts();
      await _show(
        tester,
        directory: directory,
        created: [],
        clients: clients,
        drafts: drafts,
        initialAccount: directory.target(identity),
        configureClient: (client) {
          switch (stage) {
            case 'connect':
              client.connectGate = gate;
            case 'folders':
              client.folderGate = gate;
            case 'headers':
              client.headerGate = gate;
          }
        },
      );
      await _connect(tester);
      directory.records.clear();
      gate.complete();
      await _pump(tester);
      expect(clients.single.disconnections, 1);
      expect(drafts.identities, isEmpty);
      if (stage == 'connect') expect(clients.single.folderReads, 0);
      if (stage != 'headers') expect(clients.single.headerReads, 0);
      expect(find.text(_strings.mailAccountNavigationChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'removed target during store open closes the candidate without adoption',
    (tester) async {
      final directory = _Directory();
      final identity = _identity(_second);
      await directory.remember(identity);
      final drafts = MemoryStudioMailDrafts();
      final gate = Completer<void>();
      drafts.openGate = gate;
      final clients = <_Client>[];
      _ClosingStore? candidate;
      await _show(
        tester,
        directory: directory,
        created: [],
        clients: clients,
        drafts: drafts,
        initialAccount: directory.target(identity),
        open: (account) async {
          candidate = _ClosingStore(await drafts.open(account), null, []);
          return candidate!;
        },
      );
      await _connect(tester);
      expect(drafts.identities, hasLength(1));
      directory.records.clear();
      gate.complete();
      await _pump(tester);
      expect(drafts.closes, 1);
      expect(candidate!.loads, 0);
      expect(clients.single.disconnections, 1);
      expect(find.text(_strings.mailAccountNavigationChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
