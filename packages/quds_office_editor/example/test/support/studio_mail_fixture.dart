import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_strings.dart';

const mailStrings = StudioStrings(StudioLanguage.en);

mail.Mailbox mailboxFixture(String name) => mail.Mailbox(
  encodedName: name,
  encodedPath: name,
  flags: <mail.MailboxFlag>[],
  pathSeparator: '/',
);

mail.MimeMessage mailMessageFixture(String subject) =>
    mail.MimeMessage.parseFromText(
      'From: Writer <writer@example.invalid>\r\n'
      'To: Reader <reader@example.invalid>\r\n'
      'Subject: $subject\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      '\r\n'
      'Body of $subject.\r\n',
    );

final class MailClientFixture extends Fake implements mail.MailClient {
  final boxes = <mail.Mailbox>[
    mailboxFixture('INBOX'),
    mailboxFixture('Archive'),
  ];
  final messages = <mail.MimeMessage>[
    mailMessageFixture('First message'),
    mailMessageFixture('Second message'),
  ];
  Future<void> Function()? onConnect;
  Future<List<mail.Mailbox>> Function()? onList;
  Future<List<mail.MimeMessage>> Function()? onFetch;
  Future<mail.Mailbox> Function(mail.Mailbox)? onSelect;
  Future<mail.MimeMessage> Function(mail.MimeMessage)? onContents;
  Future<void> Function(mail.MimeMessage)? onSend;
  Object? disconnectFailure;
  int connects = 0;
  int disconnects = 0;
  int lists = 0;
  int fetches = 0;
  int selections = 0;
  final sent = <mail.MimeMessage>[];

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    connects++;
    await onConnect?.call();
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    if (disconnectFailure case final Object failure) throw failure;
  }

  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async {
    lists++;
    return await onList?.call() ?? boxes;
  }

  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async {
    fetches++;
    expect(count, 50);
    expect(fetchPreference, mail.FetchPreference.envelope);
    return await onFetch?.call() ?? messages;
  }

  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async {
    selections++;
    return await onSelect?.call(mailbox) ?? mailbox;
  }

  @override
  Future<mail.MimeMessage> fetchMessageContents(
    mail.MimeMessage message, {
    int? maxSize,
    bool markAsSeen = false,
    List<mail.MediaToptype>? includedInlineTypes,
    Duration? responseTimeout,
  }) async => await onContents?.call(message) ?? message;

  @override
  Future<void> sendMessage(
    mail.MimeMessage message, {
    mail.MailAddress? from,
    bool appendToSent = true,
    bool supportUnicode = false,
    mail.Mailbox? sentMailbox,
    bool use8BitEncoding = false,
    List<mail.MailAddress>? recipients,
  }) async {
    sent.add(message);
    await onSend?.call(message);
  }
}

Finder mailField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> pumpMail(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> openMail(
  WidgetTester tester,
  mail.MailClient Function(mail.MailAccount) clientFactory, {
  StudioStrings strings = mailStrings,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailDialog(
                strings: strings,
                clientFactory: clientFactory,
              ),
            ),
            child: const Text('Launch Mail'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launch Mail'));
  await pumpMail(tester);
  await tester.enterText(
    mailField(strings.emailAddress),
    'reader@example.invalid',
  );
  await tester.enterText(mailField(strings.password), 'session-password');
  await tester.tap(find.widgetWithText(SwitchListTile, strings.manualServers));
  await pumpMail(tester);
  await tester.enterText(mailField(strings.imapHost), 'imap.example.invalid');
  await tester.enterText(mailField(strings.smtpHost), 'smtp.example.invalid');
}

Future<void> connectMail(
  WidgetTester tester, {
  StudioStrings strings = mailStrings,
}) async {
  await tester.tap(find.widgetWithText(FilledButton, strings.connect));
  await pumpMail(tester);
}

Future<void> closeMail(
  WidgetTester tester, {
  StudioStrings strings = mailStrings,
}) async {
  await tester.tap(find.byTooltip(strings.close));
  await pumpMail(tester);
  expect(find.byType(StudioMailDialog), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> composeMail(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, mailStrings.compose));
  await pumpMail(tester);
  await tester.enterText(
    mailField(mailStrings.to),
    'recipient@example.invalid',
  );
  await tester.enterText(mailField(mailStrings.subject), 'Controlled draft');
  await tester.enterText(mailField(mailStrings.messageBody), 'A <safe> body.');
  await tester.tap(find.widgetWithText(FilledButton, mailStrings.send));
  await pumpMail(tester);
}

MailReaderController mailReader(WidgetTester tester) =>
    tester.widget<MailMessageView>(find.byType(MailMessageView)).controller;
