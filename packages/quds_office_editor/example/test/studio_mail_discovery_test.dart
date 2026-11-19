import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

mail.ClientConfig _config({
  bool insecureSource = false,
  mail.ServerType incoming = mail.ServerType.imap,
  mail.ServerType outgoing = mail.ServerType.smtp,
}) {
  final provider = mail.ConfigEmailProvider();
  provider.addIncomingServer(
    mail.ServerConfig(
      type: incoming,
      hostname: 'imap.example.invalid',
      port: 143,
      socketType: mail.SocketType.starttls,
      authentication: mail.Authentication.passwordClearText,
      usernameType: mail.UsernameType.emailAddress,
    ),
  );
  provider.addOutgoingServer(
    mail.ServerConfig(
      type: outgoing,
      hostname: 'smtp.example.invalid',
      port: 587,
      socketType: mail.SocketType.starttls,
      authentication: mail.Authentication.passwordClearText,
      usernameType: mail.UsernameType.emailAddress,
    ),
  );
  return mail.ClientConfig(emailProviders: <mail.ConfigEmailProvider>[provider])
    ..isFromInsecureSource = insecureSource;
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
    flags: <mail.MailboxFlag>[mail.MailboxFlag.inbox],
    pathSeparator: '/',
    uidValidity: 7,
    uidNext: 1,
  );
  int connects = 0;
  int disconnects = 0;

  @override
  mail.Mailbox get selectedMailbox => inbox;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    connects++;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => <mail.Mailbox>[inbox];

  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async => <mail.MimeMessage>[];
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _open(
  WidgetTester tester, {
  required Future<mail.ClientConfig?> Function(String) discovery,
  required mail.MailClient Function(mail.MailAccount) client,
  required StudioMailMessageLoader Function(mail.MailAccount) loader,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailDialog(
                strings: _strings,
                accountDiscovery: discovery,
                clientFactory: client,
                messageLoaderFactory: loader,
              ),
            ),
            child: const Text('Open account'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open account'));
  await _pump(tester);
  await tester.enterText(
    _field(_strings.emailAddress),
    'reader@example.invalid',
  );
  await tester.enterText(_field(_strings.password), 'private-fixture-password');
  await tester.tap(find.widgetWithText(FilledButton, _strings.connect));
  await _pump(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_strings.close));
  await _pump(tester);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final (name, configuration) in <(String, mail.ClientConfig?)>[
    ('HTTP discovery', _config(insecureSource: true)),
    ('POP-only discovery', _config(incoming: mail.ServerType.pop)),
    ('non-SMTP outgoing discovery', _config(outgoing: mail.ServerType.imap)),
    ('missing server discovery', mail.ClientConfig()),
    ('no discovery result', null),
  ]) {
    testWidgets('$name is rejected before credentials reach a client', (
      tester,
    ) async {
      var clients = 0;
      var loaders = 0;
      await _open(
        tester,
        discovery: (email) async {
          expect(email, 'reader@example.invalid');
          return configuration;
        },
        client: (_) {
          clients++;
          return _Client();
        },
        loader: (_) {
          loaders++;
          return _Loader();
        },
      );
      expect(clients, 0);
      expect(loaders, 0);
      expect(find.text(_strings.mailConnectionFailed), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.data?.contains('private-fixture-password') ?? false),
        ),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(_field(_strings.password)).obscureText,
        isTrue,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(_field(_strings.imapHost), findsOneWidget);
      expect(_field(_strings.smtpHost), findsOneWidget);
      await _close(tester);
    });
  }

  testWidgets('trusted IMAP discovery creates SSL-only account endpoints', (
    tester,
  ) async {
    final client = _Client();
    final loader = _Loader();
    mail.MailAccount? account;
    await _open(
      tester,
      discovery: (_) async => _config(),
      client: (value) {
        account = value;
        return client;
      },
      loader: (_) => loader,
    );
    expect(client.connects, 1);
    expect(account!.incoming.serverConfig.type, mail.ServerType.imap);
    expect(account!.outgoing.serverConfig.type, mail.ServerType.smtp);
    expect(account!.incoming.serverConfig.socketType, mail.SocketType.ssl);
    expect(account!.outgoing.serverConfig.socketType, mail.SocketType.ssl);
    expect(account!.incoming.serverConfig.port, 993);
    expect(account!.outgoing.serverConfig.port, 465);
    expect(find.text(_strings.mailConnectionFailed), findsNothing);
    await _close(tester);
    expect(client.disconnects, 1);
    expect(loader.disposals, 1);
  });

  testWidgets(
    'discovery uses the credentials captured when connection begins',
    (tester) async {
      final pending = Completer<mail.ClientConfig?>();
      final client = _Client();
      final loader = _Loader();
      mail.MailAccount? captured;
      await _open(
        tester,
        discovery: (_) => pending.future,
        client: (account) {
          captured = account;
          return client;
        },
        loader: (_) => loader,
      );
      await tester.enterText(_field(_strings.password), 'changed-password');
      pending.complete(_config());
      await _pump(tester);
      final authentication =
          captured!.incoming.authentication as mail.PlainAuthentication;
      expect(authentication.password, 'private-fixture-password');
      await _close(tester);
      expect(loader.disposals, 1);
    },
  );

  for (final failure in <bool>[false, true]) {
    testWidgets(
      'closing during discovery ignores its late ${failure ? 'failure' : 'success'}',
      (tester) async {
        final pending = Completer<mail.ClientConfig?>();
        var clients = 0;
        var loaders = 0;
        await _open(
          tester,
          discovery: (_) => pending.future,
          client: (_) {
            clients++;
            return _Client();
          },
          loader: (_) {
            loaders++;
            return _Loader();
          },
        );
        await _close(tester);
        if (failure) {
          pending.completeError(StateError('late private discovery error'));
        } else {
          pending.complete(_config());
        }
        await _pump(tester);
        expect(clients, 0);
        expect(loaders, 0);
        expect(find.byType(StudioMailDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
