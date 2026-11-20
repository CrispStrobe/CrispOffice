import 'support/mail_credentials.dart';
import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_presets.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
Finder _input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  test('Yahoo uses authenticated implicit TLS and full-address login', () {
    final account = createStudioMailPresetAccount(
      preset: StudioMailImapPreset.yahoo,
      email: 'reader@yahoo.com',
      password: 'app-password',
    );
    expect(account.incoming.serverConfig.hostname, 'imap.mail.yahoo.com');
    expect(account.incoming.serverConfig.port, 993);
    expect(account.incoming.serverConfig.socketType, mail.SocketType.ssl);
    expect(account.outgoing.serverConfig.hostname, 'smtp.mail.yahoo.com');
    expect(account.outgoing.serverConfig.port, 465);
    expect(account.outgoing.serverConfig.socketType, mail.SocketType.ssl);
    expect(
      (account.incoming.authentication as mail.PlainAuthentication).userName,
      'reader@yahoo.com',
    );
    expect(
      (account.outgoing.authentication as mail.PlainAuthentication).userName,
      'reader@yahoo.com',
    );
  });

  test(
    'iCloud uses TLS IMAP, mandatory SMTP STARTTLS and separate login forms',
    () {
      final account = createStudioMailPresetAccount(
        preset: StudioMailImapPreset.icloud,
        email: 'alias@custom.example',
        primaryLogin: 'primary@icloud.com',
        password: 'app-specific-password',
      );
      expect(account.email, 'alias@custom.example');
      expect(account.incoming.serverConfig.hostname, 'imap.mail.me.com');
      expect(account.incoming.serverConfig.port, 993);
      expect(account.incoming.serverConfig.socketType, mail.SocketType.ssl);
      expect(account.outgoing.serverConfig.hostname, 'smtp.mail.me.com');
      expect(account.outgoing.serverConfig.port, 587);
      expect(
        account.outgoing.serverConfig.socketType,
        mail.SocketType.starttls,
      );
      expect(
        (account.incoming.authentication as mail.PlainAuthentication).userName,
        'primary',
      );
      expect(
        (account.outgoing.authentication as mail.PlainAuthentication).userName,
        'primary@icloud.com',
      );
    },
  );

  test('Fastmail preserves a primary login distinct from a custom sender', () {
    final account = createStudioMailPresetAccount(
      preset: StudioMailImapPreset.fastmail,
      email: 'alias@custom.example',
      primaryLogin: 'original@fastmail.com',
      password: 'app-password',
    );
    expect(account.email, 'alias@custom.example');
    expect(account.incoming.serverConfig.hostname, 'imap.fastmail.com');
    expect(account.incoming.serverConfig.port, 993);
    expect(account.incoming.serverConfig.socketType, mail.SocketType.ssl);
    expect(account.outgoing.serverConfig.hostname, 'smtp.fastmail.com');
    expect(account.outgoing.serverConfig.port, 465);
    expect(account.outgoing.serverConfig.socketType, mail.SocketType.ssl);
    expect(
      (account.incoming.authentication as mail.PlainAuthentication).userName,
      'original@fastmail.com',
    );
    expect(
      (account.outgoing.authentication as mail.PlainAuthentication).userName,
      'original@fastmail.com',
    );
  });

  test('iCloud offers Apple’s full-address IMAP login fallback explicitly', () {
    final account = createStudioMailPresetAccount(
      preset: StudioMailImapPreset.icloud,
      email: 'alias@custom.example',
      primaryLogin: 'primary@icloud.com',
      password: 'app-specific-password',
      icloudFullAddressLogin: true,
    );
    expect(
      (account.incoming.authentication as mail.PlainAuthentication).userName,
      'primary@icloud.com',
    );
    expect(account.outgoing.serverConfig.socketType, mail.SocketType.starttls);
  });

  test(
    'presets reject malformed identity and credential settings before connection',
    () {
      for (final entry in <(String, String, String)>[
        ('invalid', '', 'password'),
        ('reader@example.test\r\n', '', 'password'),
        ('reader@example.test', 'invalid', 'password'),
        ('reader@example.test', '', ''),
        ('reader@example.test', '', 'password\r\nINJECT'),
      ]) {
        expect(
          () => createStudioMailPresetAccount(
            preset: StudioMailImapPreset.yahoo,
            email: entry.$1,
            primaryLogin: entry.$2,
            password: entry.$3,
          ),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets(
    'choosing a preset clears old credentials and exposes app-password guidance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1050));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StudioMailDialog(
            strings: _strings,
            credentialStore: SessionMailCredentials(),
          ),
        ),
      );
      await tester.enterText(
        _input(_strings.password),
        'password-for-another-provider',
      );
      await tester.tap(
        find.byKey(const ValueKey('studio-mail-provider-preset')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('iCloud Mail').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(_input(_strings.mailAppPassword))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text(_strings.mailPresetPasswordHelp), findsOneWidget);
      expect(
        find.textContaining('smtp.mail.me.com:587 STARTTLS'),
        findsOneWidget,
      );
      expect(find.text(_strings.manualServers), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preset connection uses explicit settings without discovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1050));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    mail.MailAccount? captured;
    var discoveries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StudioMailDialog(
          credentialStore: SessionMailCredentials(),
          draftStoreFactory: MemoryStudioMailDrafts().open,
          strings: _strings,
          accountDiscovery: (_) async {
            discoveries++;
            return null;
          },
          clientFactory: (account) {
            captured = account;
            throw StateError('controlled-constructor-failure');
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-provider-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fastmail').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      _input(_strings.emailAddress),
      'alias@custom.example',
    );
    await tester.enterText(_input(_strings.mailAppPassword), 'app-password');
    await tester.enterText(
      _input(_strings.mailPrimaryLogin),
      'primary@fastmail.com',
    );
    final connect = find.widgetWithText(FilledButton, _strings.connect);
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(discoveries, 0);
    expect(captured!.incoming.serverConfig.hostname, 'imap.fastmail.com');
    expect(
      (captured!.outgoing.authentication as mail.PlainAuthentication).userName,
      'primary@fastmail.com',
    );
    expect(find.text(_strings.mailConnectionFailed), findsOneWidget);
    expect(find.textContaining('controlled-constructor-failure'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
