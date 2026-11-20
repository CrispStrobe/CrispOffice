import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _saved = StudioMailCredentials(
  email: 'saved@example.test',
  password: 'remembered-password',
  imapHost: 'imap.example.test',
  smtpHost: 'smtp.example.test',
  manual: true,
  startTls: false,
);

class _Credentials extends Fake implements StudioMailCredentialStore {
  final ready = Completer<void>();
  bool failed = false;

  @override
  Future<StudioMailCredentials?> load() async {
    await ready.future;
    if (failed) throw StateError('Credential store unavailable');
    return _saved;
  }

  @override
  Future<bool> save(StudioMailCredentials value) async => true;
}

final class _Catalog extends _Credentials
    implements StudioMailAccountCatalogStore {
  final catalog = StudioMailAccountCatalog(
    accounts: [
      StudioMailSavedAccount(id: _saved.accountId, credentials: _saved),
    ],
    selectedAccountId: _saved.accountId,
  );

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() async {
    await ready.future;
    return failed
        ? const StudioMailAccountCatalogResult.failure(
            StudioMailAccountCatalogProblem.unavailable,
          )
        : StudioMailAccountCatalogResult.success(catalog);
  }

  @override
  Future<StudioMailAccountCatalogResult> saveAccount(
    StudioMailCredentials value,
  ) async => StudioMailAccountCatalogResult.success(catalog);
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
  int reads = 0;
  final createdAccounts = <mail.MailAccount>[];

  @override
  mail.Mailbox get selectedMailbox => inbox;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    connections++;
  }

  @override
  Future<void> disconnect() async {}

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
  }) async {
    reads++;
    return [];
  }
}

TextEditingController _input(WidgetTester tester, String label) => tester
    .widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    )
    .controller!;

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester,
  _Credentials store,
  _Client client, {
  bool? autoConnect = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: store,
        clientFactory: (account) {
          client.createdAccounts.add(account);
          return client;
        },
        messageLoaderFactory: (_) => _Loader(),
        draftStoreFactory: MemoryStudioMailDrafts().open,
        autoConnectSavedAccount: autoConnect,
      ),
    ),
  );
  await _pump(tester);
}

void main() {
  for (final catalog in [false, true]) {
    final source = catalog ? 'account catalog' : 'legacy credentials';

    testWidgets('$source connects once only after adopting saved credentials', (
      tester,
    ) async {
      final store = catalog ? _Catalog() : _Credentials();
      final client = _Client();
      await _show(tester, store, client);
      expect(client.connections, 0);
      store.ready.complete();
      await _pump(tester);
      expect(client.connections, 1);
      expect(client.createdAccounts.single.email, _saved.email);
      expect(
        client.createdAccounts.single.incoming.serverConfig.hostname,
        _saved.imapHost,
      );
      expect(client.reads, 1);
      expect(find.byType(MailMessageList), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pump(tester);
      expect(client.connections, 1);
      expect(client.reads, 1);
      expect(find.byType(MailMessageList), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$source cannot connect a form edited while loading', (
      tester,
    ) async {
      final store = catalog ? _Catalog() : _Credentials();
      final client = _Client();
      await _show(tester, store, client);
      _input(tester, _strings.emailAddress).text = 'edited@example.test';
      _input(tester, _strings.password).text = 'edited-password';
      store.ready.complete();
      await _pump(tester);
      expect(client.connections, 0);
      expect(_input(tester, _strings.emailAddress).text, 'edited@example.test');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$source failed load cannot authorize automatic connection', (
      tester,
    ) async {
      final store = (catalog ? _Catalog() : _Credentials())..failed = true;
      final client = _Client();
      await _show(tester, store, client);
      _input(tester, _strings.emailAddress).text = 'edited@example.test';
      _input(tester, _strings.password).text = 'edited-password';
      store.ready.complete();
      await _pump(tester);
      expect(client.connections, 0);
      expect(tester.takeException(), isNull);
    });

    for (final password in [false, true]) {
      testWidgets(
        '$source ${password ? 'password' : 'account'} edit cancels the queued callback',
        (tester) async {
          final store = catalog ? _Catalog() : _Credentials();
          final client = _Client();
          await _show(tester, store, client);
          store.ready.complete();
          await tester.idle();
          expect(_input(tester, _strings.emailAddress).text, _saved.email);
          expect(client.connections, 0);
          _input(
            tester,
            password ? _strings.password : _strings.emailAddress,
          ).text = password
              ? 'edited-password'
              : 'edited@example.test';
          await _pump(tester);
          expect(client.connections, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final setting in <bool?>[null, false]) {
    testWidgets(
      'custom factory remains manual with automatic setting $setting',
      (tester) async {
        final store = _Credentials();
        final client = _Client();
        await _show(tester, store, client, autoConnect: setting);
        store.ready.complete();
        await _pump(tester);
        expect(_input(tester, _strings.emailAddress).text, _saved.email);
        expect(client.connections, 0);
        await tester.tap(find.widgetWithText(FilledButton, _strings.connect));
        await _pump(tester);
        expect(client.connections, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('manual connection supersedes an already queued automatic one', (
    tester,
  ) async {
    final store = _Credentials();
    final client = _Client();
    await _show(tester, store, client);
    store.ready.complete();
    await tester.idle();
    expect(_input(tester, _strings.emailAddress).text, _saved.email);
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, _strings.connect),
        )
        .onPressed!();
    await _pump(tester);
    expect(client.connections, 1);
    expect(client.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal cancels an already queued automatic connection', (
    tester,
  ) async {
    final store = _Credentials();
    final client = _Client();
    await _show(tester, store, client);
    store.ready.complete();
    await tester.idle();
    expect(_input(tester, _strings.emailAddress).text, _saved.email);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
    expect(client.connections, 0);
    expect(tester.takeException(), isNull);
  });
}
