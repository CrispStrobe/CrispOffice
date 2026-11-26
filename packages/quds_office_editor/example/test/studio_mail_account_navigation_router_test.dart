import 'dart:async';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_credential_storage.dart';
import 'package:quds_office_studio/studio_productivity_accounts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_credential_store.dart';
import 'support/mail_credentials.dart';
import 'support/mail_draft_store.dart';
import 'support/mail_local_accounts.dart';

const _strings = StudioStrings(StudioLanguage.en);

StudioMailDraftAccount _identity(String provider) => StudioMailDraftAccount(
  provider: provider,
  endpoint: switch (provider) {
    'imap' => 'imaps://imap.example.test:993',
    'ews' => 'https://exchange.example.test/EWS/Exchange.asmx',
    'gmail' => 'https://gmail.googleapis.com/gmail/v1',
    'graph' => 'https://graph.microsoft.com/v1.0',
    _ => throw StateError('Unknown fixture provider'),
  },
  login: switch (provider) {
    'ews' => jsonEncode(['DOMAIN', 'ExchangeLogin']),
    'graph' => jsonEncode(['common', '$provider@example.test']),
    _ => '$provider@example.test',
  },
  sender: '$provider@example.test',
);

final class _RouteEntry {
  const _RouteEntry(this.route, this.provider, this.target, this.navigate);

  final ModalRoute<Object?> route;
  final MailProviderKind provider;
  final StudioMailAccountNavigationTarget? target;
  final ValueChanged<StudioMailAccountNavigationTarget> navigate;
}

final class _RouterFixture {
  _RouterFixture() {
    for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
      directory.seed(_identity(provider));
    }
  }

  final directory = MemoryMailLocalAccounts();
  final routes = <_RouteEntry>[];
  int clientCreations = 0;
  int storeOpens = 0;

  StudioMailAccountNavigationTarget target(String provider) =>
      StudioMailAccountNavigationTarget.fromRecord(
        directory.records.values.singleWhere(
          (record) => record.provider.name == provider,
        ),
      );

  Widget destination(
    BuildContext context,
    MailProviderKind provider,
    StudioMailAccountNavigationTarget? target,
    ValueChanged<StudioMailAccountNavigationTarget> navigate,
  ) {
    final route = ModalRoute.of<Object?>(context)!;
    if (!routes.any((entry) => identical(entry.route, route))) {
      routes.add(_RouteEntry(route, provider, target, navigate));
    }
    return Dialog.fullscreen(
      child: Scaffold(
        body: Column(
          children: [
            Text('Provider setup: ${provider.name}'),
            TextButton(
              key: const ValueKey('fixture-close-provider'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close provider setup'),
            ),
          ],
        ),
      ),
    );
  }
}

const _imapCredentials = StudioMailCredentials(
  email: 'imap@example.test',
  password: 'fixture-imap-secret',
  imapHost: 'imap.example.test',
  smtpHost: 'smtp.example.test',
  manual: true,
  startTls: false,
);

final class _DelayedAccountCatalog extends Fake
    implements StudioMailCredentialStore, StudioMailAccountCatalogStore {
  final result = Completer<StudioMailAccountCatalogResult>();
  int loads = 0;
  bool completed = false;

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() async {
    loads++;
    final catalog = await result.future;
    completed = true;
    return catalog;
  }
}

final class _NativeClient extends Fake implements mail.MailClient {
  _NativeClient(this.account);
  @override
  final mail.MailAccount account;
  int connections = 0;
  int disconnections = 0;
  final inbox = mail.Mailbox(
    encodedName: 'INBOX',
    encodedPath: 'INBOX',
    flags: [mail.MailboxFlag.inbox],
    pathSeparator: '/',
    uidValidity: 7,
    uidNext: 1,
  );

  @override
  mail.Mailbox get selectedMailbox => inbox;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    connections++;
  }

  @override
  Future<void> disconnect() async {
    disconnections++;
  }

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

final class _NativeLoader extends Fake implements StudioMailMessageLoader {
  @override
  void dispose() {}
  @override
  void cancel() {}
}

final class _EwsProvider extends Fake implements MailEwsProvider {
  _EwsProvider(this.account);
  @override
  final MailAccountId account;
  MailOperationLease? lastLease;
  int calls = 0;

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async {
    lastLease = lease;
    calls++;
    return MailSuccess(
      MailCapabilities(const [MailCapability.mail, MailCapability.folders]),
    );
  }

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async {
    lastLease = lease;
    calls++;
    return MailSuccess([
      MailMailbox(
        id: MailMailboxId('inbox', account: account),
        displayName: 'Inbox',
      ),
    ]);
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lastLease = lease;
    calls++;
    return MailSuccess(MailHeaderPage(messages: const []));
  }
}

final class _TracedStore implements StudioMailDraftStore {
  _TracedStore(this.delegate, this.kind, this.events, this.onClose);
  final StudioMailDraftStore delegate;
  final String kind;
  final List<String> events;
  final Future<void> Function() onClose;
  bool _closed = false;

  @override
  Future<StudioMailStoredDraft?> load() => delegate.load();

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) async {
    await delegate.save(draft, submissionUncertain: submissionUncertain);
    events.add('save:$kind');
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
  Future<void> close() async {
    if (_closed) return;
    await onClose();
    await delegate.close();
    _closed = true;
    events.add('close:$kind');
  }
}

final class _ConnectedFixture {
  _ConnectedFixture() {
    directory
      ..seed(_identity('imap'))
      ..seed(_identity('ews'));
    for (final provider in ['imap', 'ews']) {
      drafts.records[_identity(provider).account.value] = StudioMailStoredDraft(
        draft: StudioMailDraft(
          to: 'recipient@example.test',
          subject: '$provider retained draft',
          body: '$provider private working copy',
        ),
        submissionUncertain: provider == 'imap',
      );
    }
  }

  final directory = MemoryMailLocalAccounts();
  final credentials = memoryStudioMailCredentialStore();
  final drafts = MemoryStudioMailDrafts();
  final nativeClients = <_NativeClient>[];
  final ewsProviders = <_EwsProvider>[];
  final storeEvents = <String>[];
  String? activeOwner;
  Completer<void>? ewsCloseGate;

  Future<StudioMailDraftStore> open(StudioMailDraftAccount account) async {
    expect(
      activeOwner,
      isNull,
      reason: 'Previous account must release its owner',
    );
    final kind = account.provider.name;
    activeOwner = kind;
    storeEvents.add('open:$kind');
    return _TracedStore(
      await drafts.open(account),
      kind,
      storeEvents,
      () async {
        if (kind == 'ews') await ewsCloseGate?.future;
        expect(activeOwner, kind);
        activeOwner = null;
      },
    );
  }

  Widget destination(
    BuildContext context,
    MailProviderKind provider,
    StudioMailAccountNavigationTarget? target,
    ValueChanged<StudioMailAccountNavigationTarget> navigate,
  ) {
    expect(provider, MailProviderKind.ews);
    return StudioMailEwsDialog(
      strings: _strings,
      initialAccount: target,
      onAccountNavigation: navigate,
      localAccountStore: directory,
      draftStoreFactory: open,
      providerFactory: (configuration, _) {
        expect(configuration.account, _identity('ews').account);
        final ews = _EwsProvider(configuration.account);
        ewsProviders.add(ews);
        return ews;
      },
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _email => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == _strings.emailAddress,
);

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

Future<void> _show(
  WidgetTester tester,
  _RouterFixture fixture, {
  StudioMailCredentialStore? credentials,
  StudioCredentialStorage? sharedStorage,
  VoidCallback? openConnections,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: credentials ?? SessionMailCredentials(),
        sharedCredentialStorage: sharedStorage,
        openConnections: openConnections,
        localAccountStore: fixture.directory,
        autoConnectSavedAccount: false,
        accountDestinationBuilder: fixture.destination,
        clientFactory: (_) {
          fixture.clientCreations++;
          throw StateError('Account navigation cannot connect a provider');
        },
        draftStoreFactory: (_) async {
          fixture.storeOpens++;
          throw StateError('Disconnected routing cannot acquire an account');
        },
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _showConnected(
  WidgetTester tester,
  _ConnectedFixture fixture, {
  StudioMailAccountNavigationTarget? initialAccount,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: fixture.credentials,
        localAccountStore: fixture.directory,
        initialAccount: initialAccount,
        autoConnectSavedAccount: false,
        accountDestinationBuilder: fixture.destination,
        draftStoreFactory: fixture.open,
        clientFactory: (account) {
          final client = _NativeClient(account);
          fixture.nativeClients.add(client);
          return client;
        },
        messageLoaderFactory: (_) => _NativeLoader(),
      ),
    ),
  );
  await _pump(tester);
}

Future<StudioCredentialStorage> _sharedExchange(SecureStorage vault) async {
  SharedPreferences.setMockInitialValues({});
  await vault.write(
    studioTasksLegacyKey,
    jsonEncode({
      'id': 'shared-ews',
      'provider': 'ews',
      'label': 'AKRS',
      'url': _identity('ews').endpoint,
      'login': 'ExchangeLogin',
      'domain': 'DOMAIN',
      'mailbox': _identity('ews').sender,
      'secret': 'fixture-exchange-secret',
      'services': ['mail', 'tasks', 'calendar'],
    }),
  );
  final storage = StudioCredentialStorage(
    systemStorageFactory: () async => vault,
  );
  addTearDown(storage.dispose);
  return storage;
}

void main() {
  testWidgets(
    'saved Exchange can be selected in either Mail chooser before its first Mail connection',
    (tester) async {
      final fixture = _RouterFixture();
      fixture.directory.records.remove(_identity('ews').account.value);
      final storage = await _sharedExchange(InMemorySecureStorage());
      final credentials = _DelayedAccountCatalog();
      credentials.result.complete(
        StudioMailAccountCatalogResult.success(
          StudioMailAccountCatalog(
            accounts: [
              StudioMailSavedAccount(
                id: _imapCredentials.accountId,
                credentials: _imapCredentials,
              ),
            ],
            selectedAccountId: _imapCredentials.accountId,
          ),
        ),
      );
      var managerOpens = 0;
      await _show(
        tester,
        fixture,
        credentials: credentials,
        sharedStorage: storage,
        openConnections: () => managerOpens++,
      );
      await _press(tester, _key('studio-mail-connections'));
      expect(managerOpens, 1);
      await _press(tester, _key('studio-mail-saved-account'));
      await _press(tester, find.textContaining('AKRS'));
      expect(fixture.routes.single.provider, MailProviderKind.ews);
      expect(fixture.routes.single.target?.choiceLabel, 'AKRS');
      await _press(tester, _key('fixture-close-provider'));
      expect(fixture.clientCreations, 0);
      expect(fixture.storeOpens, 0);

      await _press(tester, _key('studio-mail-navigate-account'));
      final selectedAccount = _identity('ews').account.value;
      await _press(
        tester,
        _key('studio-mail-navigation-account-$selectedAccount'),
      );
      await _press(tester, _key('studio-mail-account-navigation-continue'));
      expect(fixture.routes, hasLength(2));
      expect(
        fixture.routes.last.target?.identity.account,
        _identity('ews').account,
      );
      expect(fixture.clientCreations, 0);
      expect(fixture.storeOpens, 0);
    },
  );

  testWidgets(
    'a shared Exchange selection rechecks Mail permission before provider sign-in',
    (tester) async {
      final vault = InMemorySecureStorage();
      final storage = await _sharedExchange(vault);
      final target = (await StudioMailAccountNavigationTarget.savedExchange(
        storage,
      )).single;
      final directory = MemoryMailLocalAccounts();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StudioMailEwsDialog(
            strings: _strings,
            initialAccount: target,
            sharedCredentialStorage: storage,
            localAccountStore: directory,
            providerFactory: (configuration, credentials) {
              opened++;
              return _EwsProvider(configuration.account);
            },
          ),
        ),
      );
      expect(find.byKey(const ValueKey('ews-password')), findsNothing);
      await saveStudioAccountServices(vault, target.sharedExchangeId!, {
        StudioProductivityService.tasks,
      });
      await _pump(tester);
      await _press(tester, _key('ews-connect'));
      expect(opened, 0);
      expect(directory.records, isEmpty);
    },
  );

  testWidgets('selected Exchange uses the stored password only after Connect', (
    tester,
  ) async {
    final storage = await _sharedExchange(InMemorySecureStorage());
    final target = (await StudioMailAccountNavigationTarget.savedExchange(
      storage,
    )).single;
    final directory = MemoryMailLocalAccounts();
    final drafts = MemoryStudioMailDrafts();
    MailEwsConfiguration? configuration;
    MailCredentialStore? credentials;
    await tester.pumpWidget(
      MaterialApp(
        home: StudioMailEwsDialog(
          strings: _strings,
          initialAccount: target,
          sharedCredentialStorage: storage,
          localAccountStore: directory,
          draftStoreFactory: drafts.open,
          providerFactory: (selected, store) {
            configuration = selected;
            credentials = store;
            return _EwsProvider(selected.account);
          },
        ),
      ),
    );
    expect(configuration, isNull);
    expect(find.byKey(const ValueKey('ews-password')), findsNothing);
    await _press(tester, _key('ews-connect'));
    expect(configuration?.authentication, MailEwsAuthentication.ntlm);
    expect(configuration?.account, target.identity.account);
    final result = await credentials!.load(configuration!.credential);
    expect(
      utf8.decode(
        (result as MailSuccess<MailCredentialRecord?>).value!.opaqueData.bytes,
      ),
      'fixture-exchange-secret',
    );
  });

  for (final (button, provider) in [
    ('studio-mail-open-gmail', MailProviderKind.gmail),
    ('studio-mail-open-microsoft365', MailProviderKind.graph),
    ('studio-mail-open-ews', MailProviderKind.ews),
  ]) {
    testWidgets(
      '${provider.name} setup opens while the IMAP credential catalog is pending',
      (tester) async {
        final fixture = _RouterFixture();
        final credentials = _DelayedAccountCatalog();
        await _show(tester, fixture, credentials: credentials);
        expect(credentials.loads, 1);
        expect(credentials.completed, isFalse);
        final email = tester.widget<TextField>(_email).controller!;
        expect(email.text, isEmpty);

        await _press(tester, _key(button));
        expect(fixture.routes.single.provider, provider);
        expect(fixture.routes.single.target, isNull);
        expect(credentials.completed, isFalse);

        credentials.result.complete(
          StudioMailAccountCatalogResult.success(
            StudioMailAccountCatalog(
              accounts: [
                StudioMailSavedAccount(
                  id: _imapCredentials.accountId,
                  credentials: _imapCredentials,
                ),
              ],
              selectedAccountId: _imapCredentials.accountId,
            ),
          ),
        );
        await _pump(tester);
        expect(credentials.completed, isTrue);
        expect(fixture.routes.single.route.isCurrent, isTrue);
        expect(email.text, isEmpty);
        expect(fixture.clientCreations, 0);
        expect(fixture.storeOpens, 0);

        await _press(tester, _key('fixture-close-provider'));
        expect(email.text, isEmpty);
        expect(fixture.clientCreations, 0);
        expect(fixture.storeOpens, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('connected IMAP to EWS to IMAP retains each draft and owner', (
    tester,
  ) async {
    final fixture = _ConnectedFixture();
    await (fixture.credentials as StudioMailAccountCatalogStore).saveAccount(
      _imapCredentials,
    );
    await _showConnected(tester, fixture);
    await _press(tester, find.widgetWithText(FilledButton, _strings.connect));
    expect(fixture.nativeClients.single.connections, 1);
    expect(fixture.activeOwner, 'imap');

    await _press(tester, _key('studio-mail-navigate-account'));
    await _press(
      tester,
      _key('studio-mail-navigation-account-${_identity('ews').account.value}'),
    );
    await _press(tester, _key('studio-mail-account-navigation-continue'));
    expect(fixture.nativeClients.single.disconnections, 1);
    expect(fixture.storeEvents, ['open:imap', 'save:imap', 'close:imap']);
    expect(fixture.ewsProviders, isEmpty);
    expect(find.byType(StudioMailEwsDialog), findsOneWidget);
    expect(
      tester.widget<TextField>(_key('ews-mailbox')).controller!.text,
      'ews@example.test',
    );
    await tester.enterText(_key('ews-password'), 'fixture-ews-secret');
    await _press(tester, _key('ews-connect'));
    final ews = fixture.ewsProviders.single;
    expect(ews.calls, 3);
    expect(fixture.activeOwner, 'ews');
    expect(fixture.drafts.identities.map((value) => value.provider.name), [
      'imap',
      'ews',
    ]);

    fixture.ewsCloseGate = Completer<void>();
    await _press(
      tester,
      find.descendant(
        of: find.byType(StudioMailEwsDialog),
        matching: _key('studio-mail-switch-account'),
      ),
    );
    await _press(
      tester,
      _key('studio-mail-navigation-account-${_identity('imap').account.value}'),
    );
    await _press(tester, _key('studio-mail-account-navigation-continue'));
    expect(fixture.activeOwner, 'ews');
    expect(find.byType(StudioMailEwsDialog), findsOneWidget);
    expect(_key('studio-mail-navigation-target'), findsNothing);
    expect(fixture.nativeClients, hasLength(1));

    fixture.ewsCloseGate!.complete();
    await _pump(tester);
    expect(ews.lastLease!.isCurrent, isFalse);
    expect(find.byType(StudioMailEwsDialog), findsNothing);
    expect(fixture.activeOwner, isNull);
    expect(
      tester.widget<Text>(_key('studio-mail-navigation-target')).data,
      'imap@example.test',
    );
    expect(fixture.nativeClients, hasLength(1));
    await _press(tester, find.widgetWithText(FilledButton, _strings.connect));
    expect(fixture.nativeClients, hasLength(2));
    expect(fixture.nativeClients.last.account.email, 'imap@example.test');
    expect(fixture.storeEvents, [
      'open:imap',
      'save:imap',
      'close:imap',
      'open:ews',
      'save:ews',
      'close:ews',
      'open:imap',
    ]);
    for (final kind in ['imap', 'ews']) {
      final saved = fixture.drafts.records[_identity(kind).account.value]!;
      expect(saved.draft.body, '$kind private working copy');
      expect(saved.submissionUncertain, kind == 'imap');
    }
    expect(ews.calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
    expect(fixture.activeOwner, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ambiguous SMTP routes can be selected explicitly and connected',
    (tester) async {
      const alternate = StudioMailCredentials(
        email: 'imap@example.test',
        password: 'fixture-alternate-secret',
        imapHost: 'imap.example.test',
        smtpHost: 'alternate.smtp.example.test',
        manual: true,
        startTls: false,
      );
      final fixture = _ConnectedFixture();
      final catalog = fixture.credentials as StudioMailAccountCatalogStore;
      await catalog.saveAccount(_imapCredentials);
      await catalog.saveAccount(alternate);
      final target = StudioMailAccountNavigationTarget.fromRecord(
        fixture.directory.records[_identity('imap').account.value]!,
      );
      await _showConnected(tester, fixture, initialAccount: target);
      expect(fixture.nativeClients, isEmpty);
      await _press(tester, _key('studio-mail-saved-account'));
      await _press(
        tester,
        _key('studio-mail-account-label-${alternate.accountId}').last,
      );
      await _press(tester, find.widgetWithText(FilledButton, _strings.connect));
      expect(fixture.nativeClients.single.account.email, 'imap@example.test');
      expect(
        fixture.nativeClients.single.account.outgoing.serverConfig.hostname,
        'alternate.smtp.example.test',
      );
      expect(fixture.drafts.identities.single.account, target.identity.account);
      expect(fixture.ewsProviders, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
      expect(fixture.activeOwner, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duplicate and delayed callbacks cannot pop a newer provider', (
    tester,
  ) async {
    final fixture = _RouterFixture();
    await _show(tester, fixture);
    await _press(tester, _key('studio-mail-open-ews'));
    expect(fixture.routes, hasLength(1));
    final first = fixture.routes.single;
    expect(first.provider, MailProviderKind.ews);

    first.navigate(fixture.target('gmail'));
    // A duplicate arrives before the first route finishes its exit animation.
    first.navigate(fixture.target('graph'));
    await _pump(tester);
    expect(fixture.routes, hasLength(2));
    final second = fixture.routes.last;
    expect(second.provider, MailProviderKind.gmail);
    expect(second.target!.identity.account, _identity('gmail').account);
    expect(second.route.isCurrent, isTrue);

    // The old callback is retained by a host operation that finishes later.
    first.navigate(fixture.target('graph'));
    await _pump(tester);
    expect(fixture.routes, hasLength(2));
    expect(second.route.isCurrent, isTrue);
    expect(find.text('Provider setup: gmail'), findsOneWidget);

    second.navigate(fixture.target('imap'));
    await _pump(tester);
    expect(find.text('Provider setup: gmail'), findsNothing);
    expect(
      tester.widget<Text>(_key('studio-mail-navigation-target')).data,
      'imap@example.test',
    );
    // Neither completed provider route may navigate the restored native host.
    first.navigate(fixture.target('graph'));
    second.navigate(fixture.target('ews'));
    await _pump(tester);
    expect(fixture.routes, hasLength(2));
    expect(
      tester.widget<Text>(_key('studio-mail-navigation-target')).data,
      'imap@example.test',
    );
    expect(fixture.clientCreations, 0);
    expect(fixture.storeOpens, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('callback from a normally closed provider route stays retired', (
    tester,
  ) async {
    final fixture = _RouterFixture();
    await _show(tester, fixture);
    await _press(tester, _key('studio-mail-open-ews'));
    final previous = fixture.routes.single;
    await _press(tester, _key('fixture-close-provider'));
    await _press(tester, _key('studio-mail-open-gmail'));
    final current = fixture.routes.last;
    expect(current.provider, MailProviderKind.gmail);
    previous.navigate(fixture.target('graph'));
    await _pump(tester);
    expect(current.route.isCurrent, isTrue);
    expect(fixture.routes, hasLength(2));
    expect(find.text('Provider setup: gmail'), findsOneWidget);
    await _press(tester, _key('fixture-close-provider'));
    expect(tester.takeException(), isNull);
    expect(fixture.clientCreations, 0);
    expect(fixture.storeOpens, 0);
  });

  testWidgets(
    'setup keyboard input is retired during an async account change',
    (tester) async {
      final fixture = _RouterFixture();
      final validated = Completer<void>();
      // The chooser reads once, then rereads on Continue. Hold the root's
      // independent third read after the chooser route has closed.
      fixture.directory.onLoad = (count) {
        if (count == 3) fixture.directory.loadGate = validated;
      };
      await _show(tester, fixture);
      await tester.enterText(_email, 'unfinished@example.test');
      final editable = tester.widget<EditableText>(
        find.descendant(of: _email, matching: find.byType(EditableText)),
      );
      final focus = editable.focusNode;
      expect(focus.hasFocus, isTrue);
      await _press(tester, _key('studio-mail-navigate-account'));
      final target = fixture.target('imap');
      await _press(
        tester,
        _key('studio-mail-navigation-account-${target.record.id}'),
      );
      await _press(tester, _key('studio-mail-account-navigation-continue'));
      expect(fixture.directory.loads, 3);
      expect(focus.canRequestFocus, isFalse);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(editable.controller.text, 'unfinished@example.test');

      validated.complete();
      await _pump(tester);
      expect(
        tester.widget<Text>(_key('studio-mail-navigation-target')).data,
        'imap@example.test',
      );
      expect(
        tester.widget<TextField>(_email).controller!.text,
        'imap@example.test',
      );
      expect(fixture.clientCreations, 0);
      expect(fixture.storeOpens, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
