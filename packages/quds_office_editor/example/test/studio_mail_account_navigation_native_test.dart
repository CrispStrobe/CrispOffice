import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_account_navigation_strings.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
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

final class _Directory implements StudioMailLocalAccountStore {
  final records = <String, MailLocalAccountRecord>{};

  @override
  Future<List<MailLocalAccountRecord>> load() async =>
      List.unmodifiable(records.values);

  @override
  Future<void> remember(StudioMailDraftAccount identity) async {
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

final class _Client extends Fake implements mail.MailClient {
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
  }) async {
    folderReads++;
    return [inbox];
  }

  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async => [];
}

final class _ClosingStore implements StudioMailDraftStore {
  _ClosingStore(this.delegate, this.gate, this.events);
  final StudioMailDraftStore delegate;
  final Completer<void> gate;
  final List<String> events;

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
  Future<void> close() async {
    events.add('closing');
    await gate.future;
    await delegate.close();
    events.add('closed');
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
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
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1050));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: credentials ?? _Credentials(),
        localAccountStore: directory,
        initialAccount: initialAccount,
        autoConnectSavedAccount: autoConnect,
        draftStoreFactory: open ?? (drafts ?? MemoryStudioMailDrafts()).open,
        clientFactory: (account) {
          created.add(account);
          final client = _Client();
          clients.add(client);
          return client;
        },
        messageLoaderFactory: (_) => _Loader(),
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
    'successful target can disconnect and reconnect after directory revision advances',
    (tester) async {
      final directory = _Directory();
      final identity = _identity(_second);
      await directory.remember(identity);
      final initial = directory.target(identity);
      final created = <mail.MailAccount>[];
      final clients = <_Client>[];
      await _show(
        tester,
        directory: directory,
        created: created,
        clients: clients,
        initialAccount: initial,
      );
      await _connect(tester);
      expect(
        directory.records[identity.account.value]!.revision,
        greaterThan(initial.record.revision),
      );
      await _tap(tester, find.byTooltip(_strings.disconnect));
      await tester.enterText(_field(_strings.password), _second.password);
      await _connect(tester);
      expect(created, hasLength(2));
      expect(clients.last.folderReads, 1);
      expect(find.text(_strings.mailAccountNavigationChanged), findsNothing);
    },
  );
}
