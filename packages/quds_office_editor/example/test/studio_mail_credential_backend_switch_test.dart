import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
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

StudioMailAccountCatalog _catalog(StudioMailCredentials account) =>
    StudioMailAccountCatalog(
      accounts: [
        StudioMailSavedAccount(id: account.accountId, credentials: account),
      ],
      selectedAccountId: account.accountId,
    );

final class _Accounts extends Fake
    implements StudioMailCredentialStore, StudioMailAccountCatalogStore {
  StudioMailAccountCatalog catalog = _catalog(_a);
  Completer<void>? loadGate;
  Completer<void>? saveGate;
  bool loadFails = false;
  int saves = 0;
  String selectedBackend = 'original';
  final savedBackends = <String>[];
  final forgottenIds = <String>[];

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() async {
    final selectedCatalog = catalog;
    await loadGate?.future;
    if (loadFails) {
      return const StudioMailAccountCatalogResult.failure(
        StudioMailAccountCatalogProblem.unavailable,
      );
    }
    return StudioMailAccountCatalogResult.success(selectedCatalog);
  }

  @override
  Future<StudioMailAccountCatalogResult> selectAccount(String id) async {
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
    saves++;
    savedBackends.add(selectedBackend);
    await saveGate?.future;
    catalog = _catalog(credentials);
    return StudioMailAccountCatalogResult.success(catalog);
  }

  @override
  Future<StudioMailAccountCatalogResult> forgetAccount(String id) async {
    forgottenIds.add(id);
    final remaining = catalog.accounts
        .where((account) => account.id != id)
        .toList();
    catalog = StudioMailAccountCatalog(
      accounts: remaining,
      selectedAccountId: remaining.firstOrNull?.id,
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

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;
String? _selection(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<String>>(
      find.descendant(
        of: _key('studio-mail-saved-account'),
        matching: find.byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField<String>,
        ),
      ),
    )
    .initialValue;
bool _canForget(WidgetTester tester) =>
    tester.widget<TextButton>(_key('studio-mail-forget')).onPressed != null;

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
  _Accounts accounts,
  _Client client,
  Future<bool> Function(BuildContext context) settings, {
  StudioMailDraftStoreFactory? draftStoreFactory,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: accounts,
        credentialSettingsOpener: settings,
        clientFactory: (_) => client,
        messageLoaderFactory: (_) => _Loader(),
        draftStoreFactory: draftStoreFactory ?? MemoryStudioMailDrafts().open,
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _connect(WidgetTester tester) =>
    _tap(tester, find.widgetWithText(FilledButton, _strings.connect));

Future<void> _openStorage(WidgetTester tester) =>
    _tap(tester, _key('studio-mail-credential-storage'));

void main() {
  testWidgets(
    'connected backend switch clears the old chooser and Forget target',
    (tester) async {
      final accounts = _Accounts();
      final client = _Client();
      await _show(tester, accounts, client, (_) async {
        accounts.catalog = _catalog(_b);
        return true;
      });
      expect(_selection(tester), _a.accountId);
      await _connect(tester);
      expect(client.connections, 1);

      await _openStorage(tester);
      expect(client.connections, 1);
      expect(client.disconnections, 0);
      await _tap(tester, find.byTooltip(_strings.disconnect));

      expect(tester.takeException(), isNull);
      expect(_selection(tester), isNull);
      expect(_canForget(tester), isFalse);
      expect(_text(tester, _strings.emailAddress), _a.email);
      expect(_text(tester, _strings.password), isEmpty);
      expect(accounts.forgottenIds, isEmpty);

      await _tap(tester, _key('studio-mail-saved-account'));
      await _tap(
        tester,
        find.text('second@example.test · imap.second.test').last,
      );
      expect(_selection(tester), _b.accountId);
      expect(_text(tester, _strings.emailAddress), _b.email);
      expect(_text(tester, _strings.password), _b.password);
      expect(client.connections, 1);
      await _tap(tester, _key('studio-mail-forget'));
      expect(accounts.forgottenIds, [_b.accountId]);
    },
  );

  for (final unavailable in [false, true]) {
    testWidgets(
      unavailable
          ? 'unavailable backend cannot retain the previous Forget target'
          : 'empty backend cannot retain the previous Forget target',
      (tester) async {
        final accounts = _Accounts();
        final client = _Client();
        await _show(tester, accounts, client, (_) async {
          accounts.catalog = StudioMailAccountCatalog(accounts: const []);
          accounts.loadFails = unavailable;
          return true;
        });
        expect(_selection(tester), _a.accountId);
        expect(_canForget(tester), isTrue);

        await _openStorage(tester);

        expect(tester.takeException(), isNull);
        expect(_selection(tester), isNull);
        expect(_canForget(tester), isFalse);
        expect(_text(tester, _strings.emailAddress), isEmpty);
        expect(_text(tester, _strings.password), isEmpty);
        expect(accounts.forgottenIds, isEmpty);
        expect(client.connections, 0);
        if (unavailable) {
          expect(find.text(_strings.mailAccountsLoadFailed), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'late backend load preserves newer settings without restoring ownership',
    (tester) async {
      final accounts = _Accounts();
      final client = _Client();
      final gate = Completer<void>();
      await _show(tester, accounts, client, (_) async {
        accounts.catalog = _catalog(_b);
        accounts.loadGate = gate;
        return true;
      });

      await _openStorage(tester);
      expect(_selection(tester), isNull);
      expect(_canForget(tester), isFalse);
      await tester.enterText(
        _field(_strings.emailAddress),
        'newer@example.test',
      );
      await tester.enterText(_field(_strings.password), 'newer-password');
      gate.complete();
      await _pump(tester);

      expect(tester.takeException(), isNull);
      expect(_selection(tester), isNull);
      expect(_canForget(tester), isFalse);
      expect(_text(tester, _strings.emailAddress), 'newer@example.test');
      expect(_text(tester, _strings.password), 'newer-password');
      expect(accounts.forgottenIds, isEmpty);
      expect(client.connections, 0);
    },
  );

  testWidgets('cancelled settings retain the current account association', (
    tester,
  ) async {
    final accounts = _Accounts();
    final client = _Client();
    await _show(tester, accounts, client, (_) async => false);

    await _openStorage(tester);

    expect(_selection(tester), _a.accountId);
    expect(_canForget(tester), isTrue);
    expect(_text(tester, _strings.emailAddress), _a.email);
    expect(_text(tester, _strings.password), _a.password);
    expect(client.connections, 0);
  });

  testWidgets('pending account save also disables storage in the File menu', (
    tester,
  ) async {
    final accounts = _Accounts();
    final client = _Client();
    final gate = Completer<void>();
    var opened = 0;
    await _show(tester, accounts, client, (_) async {
      opened++;
      return true;
    });
    accounts.saveGate = gate;
    await _connect(tester);
    expect(accounts.saves, 1);
    expect(
      tester
          .widget<IconButton>(_key('studio-mail-credential-storage'))
          .onPressed,
      isNull,
    );

    await _tap(tester, find.widgetWithText(SubmenuButton, 'File'));
    expect(
      tester
          .widget<MenuItemButton>(
            find.widgetWithText(MenuItemButton, 'Credential storage…'),
          )
          .onPressed,
      isNull,
    );
    expect(opened, 0);
    await _tap(tester, find.widgetWithText(SubmenuButton, 'File'));
    gate.complete();
    await _pump(tester);
    expect(
      tester
          .widget<IconButton>(_key('studio-mail-credential-storage'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'initial draft restore keeps storage owned until the first account save',
    (tester) async {
      final accounts = _Accounts();
      final client = _Client();
      final drafts = MemoryStudioMailDrafts();
      final opening = Completer<void>();
      final release = Completer<void>();
      var openedSettings = 0;
      await _show(
        tester,
        accounts,
        client,
        (_) async {
          openedSettings++;
          accounts.selectedBackend = 'other';
          accounts.catalog = _catalog(_b);
          return true;
        },
        draftStoreFactory: (account) async {
          opening.complete();
          await release.future;
          return drafts.open(account);
        },
      );
      final earlierSettingsAction = tester
          .widget<IconButton>(_key('studio-mail-credential-storage'))
          .onPressed!;

      try {
        await _connect(tester);
        expect(opening.isCompleted, isTrue);
        expect(client.connections, 1);
        expect(accounts.saves, 0);
        expect(
          tester
              .widget<IconButton>(_key('studio-mail-credential-storage'))
              .onPressed,
          isNull,
        );
        await _tap(tester, find.widgetWithText(SubmenuButton, 'File'));
        expect(
          tester
              .widget<MenuItemButton>(
                find.widgetWithText(MenuItemButton, 'Credential storage…'),
              )
              .onPressed,
          isNull,
        );
        await _tap(tester, find.widgetWithText(SubmenuButton, 'File'));

        // A callback captured before connection must obey the same guard as
        // the newly disabled controls.
        earlierSettingsAction();
        await _pump(tester);
        expect(openedSettings, 0);
        expect(accounts.selectedBackend, 'original');
        expect(accounts.saves, 0);
      } finally {
        release.complete();
      }
      await _pump(tester);

      expect(accounts.saves, 1);
      expect(accounts.savedBackends, ['original']);
      expect(accounts.catalog.selectedAccount!.credentials.email, _a.email);
      expect(client.connections, 1);
      expect(client.disconnections, 0);
      expect(
        tester
            .widget<IconButton>(_key('studio-mail-credential-storage'))
            .onPressed,
        isNotNull,
      );
    },
  );
}
