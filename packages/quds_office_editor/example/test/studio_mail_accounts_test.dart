import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_presets.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _a = StudioMailCredentials(
  email: 'first@example.test',
  password: 'first-password',
  imapHost: 'imap.first.test',
  smtpHost: 'smtp.first.test',
  manual: true,
  startTls: false,
);
const _b = StudioMailCredentials(
  email: 'second@example.test',
  password: 'second-password',
  imapHost: 'imap.second.test',
  smtpHost: 'smtp.second.test',
  manual: true,
  startTls: false,
);
const _c = StudioMailCredentials(
  email: 'third@example.test',
  password: 'third-password',
  imapHost: 'imap.third.test',
  smtpHost: 'smtp.third.test',
  manual: true,
  startTls: false,
);

final class _Accounts extends Fake
    implements StudioMailCredentialStore, StudioMailAccountCatalogStore {
  _Accounts({StudioMailCredentials selected = _a})
    : catalog = StudioMailAccountCatalog(
        accounts: [
          StudioMailSavedAccount(id: _a.accountId, credentials: _a),
          StudioMailSavedAccount(id: _b.accountId, credentials: _b),
        ],
        selectedAccountId: selected.accountId,
      );

  StudioMailAccountCatalog catalog;
  Completer<void>? loadGate;
  Completer<void>? selectGate;
  Completer<void>? saveGate;
  Completer<void>? forgetGate;
  StudioMailAccountCatalogProblem? loadProblem;
  StudioMailAccountCatalogProblem? selectProblem;
  StudioMailAccountCatalogProblem? saveProblem;
  StudioMailAccountCatalogProblem? forgetProblem;
  final selectedIds = <String>[];
  final forgottenIds = <String>[];
  final savedCredentials = <StudioMailCredentials>[];

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() async {
    await loadGate?.future;
    if (loadProblem case final problem?) {
      return StudioMailAccountCatalogResult.failure(problem);
    }
    return StudioMailAccountCatalogResult.success(catalog);
  }

  @override
  Future<StudioMailAccountCatalogResult> selectAccount(String id) async {
    selectedIds.add(id);
    await selectGate?.future;
    if (selectProblem case final problem?) {
      return StudioMailAccountCatalogResult.failure(problem);
    }
    catalog = StudioMailAccountCatalog(
      accounts: catalog.accounts,
      selectedAccountId: id,
    );
    return StudioMailAccountCatalogResult.success(catalog);
  }

  @override
  Future<StudioMailAccountCatalogResult> saveAccount(
    StudioMailCredentials credentials,
  ) async {
    savedCredentials.add(credentials);
    await saveGate?.future;
    if (saveProblem case final problem?) {
      return StudioMailAccountCatalogResult.failure(problem);
    }
    catalog = StudioMailAccountCatalog(
      accounts: [
        for (final entry in catalog.accounts)
          if (entry.id != credentials.accountId) entry,
        StudioMailSavedAccount(
          id: credentials.accountId,
          credentials: credentials,
        ),
      ],
      selectedAccountId: credentials.accountId,
    );
    return StudioMailAccountCatalogResult.success(catalog);
  }

  @override
  Future<StudioMailAccountCatalogResult> forgetAccount(String id) async {
    forgottenIds.add(id);
    await forgetGate?.future;
    if (forgetProblem case final problem?) {
      return StudioMailAccountCatalogResult.failure(problem);
    }
    final remaining = catalog.accounts
        .where((entry) => entry.id != id)
        .toList();
    catalog = StudioMailAccountCatalog(
      accounts: remaining,
      selectedAccountId: catalog.selectedAccountId == id
          ? remaining.firstOrNull?.id
          : catalog.selectedAccountId,
    );
    return StudioMailAccountCatalogResult.success(catalog);
  }
}

final class _Loader extends Fake implements StudioMailMessageLoader {
  int disposals = 0;
  @override
  void dispose() => disposals++;
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

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;
String _label(StudioMailCredentials credentials) =>
    '${credentials.email} · ${credentials.imapHost}';

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
  WidgetTester tester,
  _Accounts store, {
  mail.MailClient Function(mail.MailAccount)? clientFactory,
  MemoryStudioMailDrafts? drafts,
  Size surfaceSize = const Size(1280, 1500),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: store,
        clientFactory: clientFactory ?? (_) => _Client(),
        messageLoaderFactory: (_) => _Loader(),
        draftStoreFactory: (drafts ?? MemoryStudioMailDrafts()).open,
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _choose(WidgetTester tester, StudioMailCredentials account) async {
  await _tap(tester, _key('studio-mail-saved-account'));
  await _tap(tester, find.text(_label(account)).last);
}

Future<void> _connect(WidgetTester tester) =>
    _tap(tester, find.widgetWithText(FilledButton, _strings.connect));

Future<void> _enterNewAccount(WidgetTester tester) async {
  await _tap(tester, _key('studio-mail-new-account'));
  await tester.enterText(_field(_strings.emailAddress), _c.email);
  await tester.enterText(_field(_strings.password), _c.password);
  await _tap(
    tester,
    find.widgetWithText(SwitchListTile, _strings.manualServers),
  );
  await tester.enterText(_field(_strings.imapHost), _c.imapHost);
  await tester.enterText(_field(_strings.smtpHost), _c.smtpHost);
}

String _draftKey(StudioMailCredentials credentials) => StudioMailDraftAccount(
  provider: 'imap',
  endpoint: Uri(
    scheme: 'imaps',
    host: credentials.imapHost,
    port: 993,
  ).toString(),
  login: credentials.email,
  sender: credentials.email,
).account.value;

StudioMailCredentials _duplicateCredentials({
  StudioMailImapPreset? preset,
  String primaryLogin = '',
  String smtpHost = 'smtp.shared.test',
  bool startTls = false,
}) => StudioMailCredentials(
  email: 'shared@example.test',
  password: 'duplicate-fixture-password',
  imapHost: 'imap.shared.test',
  smtpHost: smtpHost,
  manual: preset == null,
  startTls: startTls,
  preset: preset,
  primaryLogin: primaryLogin,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'duplicate account labels expose exact routes and Forget targets at compact width',
    (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      final cases = [
        (
          name: 'Fastmail primary login',
          first: _duplicateCredentials(
            preset: StudioMailImapPreset.fastmail,
            primaryLogin: 'alpha@fastmail.test',
          ),
          second: _duplicateCredentials(
            preset: StudioMailImapPreset.fastmail,
            primaryLogin: 'beta@fastmail.test',
          ),
          firstQualifier: 'Login: alpha@fastmail.test',
          secondQualifier: 'Login: beta@fastmail.test',
          secondDetails:
              'Sender: shared@example.test\n'
              'IMAP login: beta@fastmail.test · imap.fastmail.com:993 TLS\n'
              'SMTP login: beta@fastmail.test · smtp.fastmail.com:465 TLS',
        ),
        (
          name: 'iCloud SMTP login with identical IMAP login',
          first: _duplicateCredentials(
            preset: StudioMailImapPreset.icloud,
            primaryLogin: 'person@icloud.com',
          ),
          second: _duplicateCredentials(
            preset: StudioMailImapPreset.icloud,
            primaryLogin: 'person@me.com',
          ),
          firstQualifier: 'SMTP login: person@icloud.com',
          secondQualifier: 'SMTP login: person@me.com',
          secondDetails:
              'Sender: shared@example.test\n'
              'IMAP login: person · imap.mail.me.com:993 TLS\n'
              'SMTP login: person@me.com · smtp.mail.me.com:587 STARTTLS',
        ),
        (
          name: 'manual SMTP route',
          first: _duplicateCredentials(smtpHost: 'relay.one.test'),
          second: _duplicateCredentials(smtpHost: 'relay.two.test'),
          firstQualifier: 'SMTP: relay.one.test:465 TLS',
          secondQualifier: 'SMTP: relay.two.test:465 TLS',
          secondDetails:
              'Sender: shared@example.test\n'
              'IMAP login: shared@example.test · imap.shared.test:993 TLS\n'
              'SMTP login: shared@example.test · relay.two.test:465 TLS',
        ),
        (
          name: 'manual TLS mode',
          first: _duplicateCredentials(),
          second: _duplicateCredentials(startTls: true),
          firstQualifier: 'IMAP: 993 TLS',
          secondQualifier: 'IMAP: 143 STARTTLS',
          secondDetails:
              'Sender: shared@example.test\n'
              'IMAP login: shared@example.test · imap.shared.test:143 STARTTLS\n'
              'SMTP login: shared@example.test · smtp.shared.test:587 STARTTLS',
        ),
      ];
      for (final scenario in cases) {
        final first = scenario.first;
        final second = scenario.second;
        final store = _Accounts()
          ..catalog = StudioMailAccountCatalog(
            accounts: [
              StudioMailSavedAccount(id: first.accountId, credentials: first),
              StudioMailSavedAccount(id: second.accountId, credentials: second),
            ],
            selectedAccountId: first.accountId,
          );
        var clientCreations = 0;
        await _show(
          tester,
          store,
          surfaceSize: const Size(560, 900),
          clientFactory: (_) {
            clientCreations++;
            return _Client();
          },
        );
        await _tap(tester, _key('studio-mail-saved-account'));
        final firstLabel = tester
            .widget<Text>(
              _key('studio-mail-account-label-${first.accountId}').last,
            )
            .data!;
        final secondLabelFinder = _key(
          'studio-mail-account-label-${second.accountId}',
        ).last;
        final secondLabel = tester.widget<Text>(secondLabelFinder).data!;
        expect(
          firstLabel,
          contains(scenario.firstQualifier),
          reason: scenario.name,
        );
        expect(
          secondLabel,
          contains(scenario.secondQualifier),
          reason: scenario.name,
        );
        expect(firstLabel, isNot(secondLabel), reason: scenario.name);
        final secondTooltip = tester
            .widget<Tooltip>(
              _key('studio-mail-account-tooltip-${second.accountId}').last,
            )
            .message!;
        expect(secondTooltip, scenario.secondDetails, reason: scenario.name);
        for (final presentation in [firstLabel, secondLabel, secondTooltip]) {
          expect(presentation, isNot(contains(first.password)));
          expect(presentation, isNot(contains(first.accountId)));
          expect(presentation, isNot(contains(second.accountId)));
        }
        expect(
          tester
              .getSemantics(
                _key(
                  'studio-mail-account-description-${second.accountId}',
                ).last,
              )
              .getSemanticsData()
              .label,
          contains(scenario.secondDetails),
          reason: scenario.name,
        );
        await tester.longPress(secondLabelFinder);
        await _pump(tester);
        expect(
          find.text(scenario.secondDetails),
          findsOneWidget,
          reason: scenario.name,
        );
        await _tap(tester, secondLabelFinder);
        expect(store.selectedIds, [second.accountId], reason: scenario.name);
        expect(clientCreations, 0);
        await tester.ensureVisible(_key('studio-mail-forget'));
        await _pump(tester);
        expect(
          tester.widget<Tooltip>(_key('studio-mail-forget-tooltip')).message,
          '${_strings.forgetAccount}\n${scenario.secondDetails}',
          reason: scenario.name,
        );
        expect(
          tester
              .getSemantics(_key('studio-mail-forget-description'))
              .getSemanticsData()
              .label,
          contains(scenario.secondDetails),
          reason: scenario.name,
        );
        await _tap(tester, _key('studio-mail-forget'));
        expect(store.forgottenIds, [second.accountId], reason: scenario.name);
        expect(
          store.catalog.accounts.single.id,
          first.accountId,
          reason: scenario.name,
        );
        expect(clientCreations, 0);
        expect(tester.takeException(), isNull, reason: scenario.name);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'restores the selected saved account without a network connection',
    (tester) async {
      final store = _Accounts(selected: _b);
      var createdClients = 0;
      await _show(
        tester,
        store,
        clientFactory: (_) {
          createdClients++;
          return _Client();
        },
      );
      expect(_text(tester, _strings.emailAddress), _b.email);
      expect(_text(tester, _strings.password), _b.password);
      expect(_text(tester, _strings.imapHost), _b.imapHost);
      expect(createdClients, 0);
      expect(store.selectedIds, isEmpty);
      expect(store.savedCredentials, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'choosing an account survives reopening and Connect stays explicit',
    (tester) async {
      final store = _Accounts();
      final connected = <String>[];
      mail.MailClient create(mail.MailAccount account) {
        connected.add(account.email);
        return _Client();
      }

      await _show(tester, store, clientFactory: create);
      await _choose(tester, _b);
      expect(store.selectedIds, [_b.accountId]);
      expect(_text(tester, _strings.emailAddress), _b.email);
      expect(connected, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await _show(tester, store, clientFactory: create);
      expect(_text(tester, _strings.emailAddress), _b.email);
      expect(connected, isEmpty);
      await _connect(tester);
      expect(connected, [_b.email]);
      expect(store.catalog.accounts, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'New account clears setup and saves a third profile without replacing either account',
    (tester) async {
      final store = _Accounts(selected: _b);
      await _show(tester, store);
      await _tap(tester, _key('studio-mail-new-account'));
      expect(_text(tester, _strings.emailAddress), isEmpty);
      expect(_text(tester, _strings.password), isEmpty);
      expect(store.catalog.accounts, hasLength(2));
      expect(store.catalog.selectedAccountId, _b.accountId);
      expect(store.savedCredentials, isEmpty);
      await _enterNewAccount(tester);
      await _connect(tester);
      expect(
        store.catalog.accounts.map((entry) => entry.credentials.email).toSet(),
        {_a.email, _b.email, _c.email},
      );
      expect(store.catalog.selectedAccount!.credentials.email, _c.email);
      expect(
        store.catalog.accounts
            .firstWhere((entry) => entry.id == _a.accountId)
            .credentials
            .password,
        _a.password,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remembered password updates retain the account identity and other profiles',
    (tester) async {
      final store = _Accounts();
      await _show(tester, store);
      await tester.enterText(_field(_strings.password), 'replacement-password');
      await _connect(tester);
      expect(store.catalog.accounts, hasLength(2));
      expect(store.catalog.selectedAccountId, _a.accountId);
      expect(
        store.catalog.selectedAccount!.credentials.password,
        'replacement-password',
      );
      expect(
        store.catalog.accounts
            .firstWhere((entry) => entry.id == _b.accountId)
            .credentials
            .password,
        _b.password,
      );
    },
  );

  testWidgets(
    'opting out for a new account does not forget an existing account',
    (tester) async {
      final store = _Accounts();
      await _show(tester, store);
      await _enterNewAccount(tester);
      await _tap(tester, _key('studio-mail-remember'));
      await _connect(tester);
      expect(store.forgottenIds, isEmpty);
      expect(store.savedCredentials, isEmpty);
      expect(store.catalog.accounts.map((entry) => entry.id).toSet(), {
        _a.accountId,
        _b.accountId,
      });
      expect(find.byTooltip(_strings.disconnect), findsOneWidget);
    },
  );

  testWidgets('opting out forgets only the account that connected', (
    tester,
  ) async {
    final store = _Accounts(selected: _b);
    await _show(tester, store);
    await _tap(tester, _key('studio-mail-remember'));
    await _connect(tester);
    expect(store.forgottenIds, [_b.accountId]);
    expect(store.catalog.accounts.single.id, _a.accountId);
    expect(find.byTooltip(_strings.disconnect), findsOneWidget);
  });

  testWidgets(
    'failed Forget retains settings and a retry removes only the selected account',
    (tester) async {
      final store = _Accounts()
        ..forgetProblem = StudioMailAccountCatalogProblem.unavailable;
      await _show(tester, store);
      await _tap(tester, _key('studio-mail-forget'));
      expect(_text(tester, _strings.emailAddress), _a.email);
      expect(_text(tester, _strings.password), _a.password);
      expect(store.catalog.accounts, hasLength(2));
      expect(find.text(_strings.mailKeychainClearFailed), findsOneWidget);
      store.forgetProblem = null;
      await _tap(tester, _key('studio-mail-forget'));
      expect(store.catalog.accounts.single.id, _b.accountId);
      expect(store.forgottenIds, [_a.accountId, _a.accountId]);
      expect(_text(tester, _strings.emailAddress), _b.email);
      expect(find.text(_strings.mailKeychainClearFailed), findsNothing);
      await _tap(tester, _key('studio-mail-forget'));
      expect(store.catalog.accounts, isEmpty);
      expect(_text(tester, _strings.emailAddress), isEmpty);
      expect(_text(tester, _strings.password), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late account loading preserves newly typed settings', (
    tester,
  ) async {
    final store = _Accounts()..loadGate = Completer<void>();
    await _show(tester, store);
    await tester.enterText(
      _field(_strings.emailAddress),
      'edited@example.test',
    );
    await tester.enterText(_field(_strings.password), 'edited-password');
    store.loadGate!.complete();
    await _pump(tester);
    expect(_text(tester, _strings.emailAddress), 'edited@example.test');
    expect(_text(tester, _strings.password), 'edited-password');
    expect(
      tester.widget<TextButton>(_key('studio-mail-forget')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('late saved-account selection cannot replace newer form edits', (
    tester,
  ) async {
    final store = _Accounts()..selectGate = Completer<void>();
    await _show(tester, store);
    await _choose(tester, _b);
    await tester.enterText(
      _field(_strings.emailAddress),
      'edited@example.test',
    );
    await tester.enterText(_field(_strings.password), 'edited-password');
    store.selectGate!.complete();
    await _pump(tester);
    expect(store.catalog.selectedAccountId, _b.accountId);
    expect(_text(tester, _strings.emailAddress), 'edited@example.test');
    expect(_text(tester, _strings.password), 'edited-password');
    expect(
      tester.widget<TextButton>(_key('studio-mail-forget')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed selection keeps the original account and provides a retry',
    (tester) async {
      final store = _Accounts()
        ..selectProblem = StudioMailAccountCatalogProblem.unavailable;
      await _show(tester, store);
      await _choose(tester, _b);
      expect(_text(tester, _strings.emailAddress), _a.email);
      expect(_text(tester, _strings.password), _a.password);
      expect(store.catalog.selectedAccountId, _a.accountId);
      expect(find.text(_strings.mailAccountSelectFailed), findsOneWidget);
      store.selectProblem = null;
      await _choose(tester, _b);
      expect(_text(tester, _strings.emailAddress), _b.email);
      expect(find.text(_strings.mailAccountSelectFailed), findsNothing);
    },
  );

  testWidgets(
    'pending selection blocks competing actions and safely completes after close',
    (tester) async {
      final store = _Accounts()..selectGate = Completer<void>();
      await _show(tester, store);
      await _choose(tester, _b);
      expect(
        tester.widget<TextButton>(_key('studio-mail-new-account')).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(_key('studio-mail-forget')).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, _strings.connect),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.selectGate!.complete();
      await _pump(tester);
      expect(store.catalog.selectedAccountId, _b.accountId);
      expect(store.forgottenIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed catalog loading leaves manual account setup available', (
    tester,
  ) async {
    final store = _Accounts()
      ..loadProblem = StudioMailAccountCatalogProblem.invalid;
    await _show(tester, store);
    expect(find.text(_strings.mailAccountsLoadFailed), findsOneWidget);
    expect(_text(tester, _strings.emailAddress), isEmpty);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, _strings.connect),
          )
          .onPressed,
      isNotNull,
    );
    expect(store.catalog.accounts, hasLength(2));
    expect(store.savedCredentials, isEmpty);
  });

  testWidgets(
    'catalog capacity failure keeps the connected account available',
    (tester) async {
      final store = _Accounts()
        ..saveProblem = StudioMailAccountCatalogProblem.limitReached;
      await _show(tester, store);
      await _enterNewAccount(tester);
      await _connect(tester);
      expect(find.byTooltip(_strings.disconnect), findsOneWidget);
      expect(find.text(_strings.mailAccountLimitReached), findsOneWidget);
      expect(store.catalog.accounts, hasLength(2));
      expect(store.forgottenIds, isEmpty);
    },
  );

  testWidgets(
    'a pending credential save survives disconnect without replacing subsequent edits',
    (tester) async {
      final store = _Accounts()..saveGate = Completer<void>();
      await _show(tester, store);
      await _enterNewAccount(tester);
      await _connect(tester);
      expect(
        tester.widget<IconButton>(_key('studio-mail-switch-account')).onPressed,
        isNull,
      );
      await _tap(tester, find.byTooltip(_strings.disconnect));
      expect(
        tester.widget<TextButton>(_key('studio-mail-new-account')).onPressed,
        isNull,
      );
      await tester.enterText(
        _field(_strings.emailAddress),
        'newer@example.test',
      );
      store.saveGate!.complete();
      await _pump(tester);
      expect(_text(tester, _strings.emailAddress), 'newer@example.test');
      expect(_text(tester, _strings.password), isEmpty);
      expect(store.catalog.accounts, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a retired save cannot leave an unrelated remembered account as the Forget target',
    (tester) async {
      final store = _Accounts()..saveGate = Completer<void>();
      await _show(tester, store);
      // Deliberately edit the selected account instead of using New account.
      // The displayed selection still names A when connection B is created.
      await tester.enterText(_field(_strings.emailAddress), _b.email);
      await tester.enterText(_field(_strings.password), _b.password);
      await tester.enterText(_field(_strings.imapHost), _b.imapHost);
      await tester.enterText(_field(_strings.smtpHost), _b.smtpHost);
      await _connect(tester);
      expect(store.savedCredentials.single.accountId, _b.accountId);
      await _tap(tester, find.byTooltip(_strings.disconnect));
      await tester.enterText(
        _field(_strings.emailAddress),
        'newer@example.test',
      );
      await tester.enterText(_field(_strings.password), 'newer-password');
      store.saveGate!.complete();
      await _pump(tester);
      expect(store.catalog.selectedAccountId, _b.accountId);
      expect(_text(tester, _strings.emailAddress), 'newer@example.test');
      expect(_text(tester, _strings.password), 'newer-password');
      expect(
        tester.widget<TextButton>(_key('studio-mail-forget')).onPressed,
        isNull,
      );
      final chooser = find.descendant(
        of: _key('studio-mail-saved-account'),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      expect(tester.state<FormFieldState<String>>(chooser).value, isNull);
      expect(store.catalog.accounts, hasLength(2));
      expect(store.forgottenIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching saves and restores each account draft independently', (
    tester,
  ) async {
    final store = _Accounts();
    final drafts = MemoryStudioMailDrafts();
    const firstDraft = StudioMailDraft(
      to: 'one@example.test',
      subject: 'First draft',
      body: 'First body',
    );
    const secondDraft = StudioMailDraft(
      to: 'two@example.test',
      subject: 'Second draft',
      body: 'Second body',
    );
    drafts.records[_draftKey(_a)] = const StudioMailStoredDraft(
      draft: firstDraft,
      submissionUncertain: true,
    );
    drafts.records[_draftKey(_b)] = const StudioMailStoredDraft(
      draft: secondDraft,
      submissionUncertain: false,
    );
    final clients = <_Client>[];
    await _show(
      tester,
      store,
      drafts: drafts,
      clientFactory: (_) {
        final client = _Client();
        clients.add(client);
        return client;
      },
    );
    await _connect(tester);
    expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
    await _tap(tester, _key('studio-mail-switch-account'));
    expect(clients.single.disconnections, 1);
    expect(drafts.closes, 1);
    expect(drafts.records[_draftKey(_a)]!.submissionUncertain, isTrue);
    await _choose(tester, _b);
    expect(clients, hasLength(1));
    await _connect(tester);
    await _tap(tester, find.widgetWithText(TextButton, _strings.compose));
    expect(_text(tester, _strings.subject), secondDraft.subject);
    await _tap(tester, find.text(_strings.mailDraftSaveClose));
    await _tap(tester, _key('studio-mail-switch-account'));
    await _choose(tester, _a);
    await _connect(tester);
    await _tap(tester, find.widgetWithText(TextButton, _strings.compose));
    expect(_text(tester, _strings.subject), firstDraft.subject);
    await _tap(tester, find.text(_strings.mailDraftSaveClose));
    expect(drafts.records[_draftKey(_b)]!.draft.body, secondDraft.body);
    expect(drafts.identities.map((entry) => entry.account.value).toList(), [
      _draftKey(_a),
      _draftKey(_b),
      _draftKey(_a),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switch refuses to leave an account when its retained draft cannot save',
    (tester) async {
      final store = _Accounts();
      final drafts = MemoryStudioMailDrafts();
      const retained = StudioMailDraft(
        to: '',
        subject: 'Keep me',
        body: 'Unsent work',
      );
      drafts.records[_draftKey(_a)] = const StudioMailStoredDraft(
        draft: retained,
        submissionUncertain: false,
      );
      final client = _Client();
      await _show(tester, store, drafts: drafts, clientFactory: (_) => client);
      await _connect(tester);
      drafts.failSave = true;
      await _tap(tester, _key('studio-mail-switch-account'));
      expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
      expect(find.byTooltip(_strings.disconnect), findsOneWidget);
      expect(client.disconnections, 0);
      expect(drafts.closes, 0);
      expect(store.selectedIds, isEmpty);
      drafts.failSave = false;
      await _tap(tester, _key('studio-mail-switch-account'));
      expect(client.disconnections, 1);
      expect(drafts.records[_draftKey(_a)]!.draft.body, retained.body);
      expect(_key('studio-mail-saved-account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
