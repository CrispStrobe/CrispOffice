import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

mail.MimeMessage _message(String subject) => mail.MimeMessage.parseFromText(
  'From: Writer <writer@example.invalid>\r\n'
  'To: Reader <reader@example.invalid>\r\n'
  'Subject: $subject\r\n'
  'Content-Type: text/plain; charset=utf-8\r\n'
  '\r\n'
  'Body of $subject.\r\n',
);

final class _DeferredMailClient extends Fake implements mail.MailClient {
  final result = Completer<mail.MimeMessage>();
  final messages = <mail.MimeMessage>[
    _message('Current message'),
    _message('Deferred message'),
  ];
  int contentRequests = 0;
  int disconnects = 0;

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {}

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => <mail.Mailbox>[
    mail.Mailbox(
      encodedName: 'INBOX',
      encodedPath: 'INBOX',
      flags: <mail.MailboxFlag>[],
      pathSeparator: '/',
    ),
  ];

  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async => messages;

  @override
  Future<mail.MimeMessage> fetchMessageContents(
    mail.MimeMessage message, {
    int? maxSize,
    bool markAsSeen = false,
    List<mail.MediaToptype>? includedInlineTypes,
    Duration? responseTimeout,
  }) async {
    contentRequests++;
    return identical(message, messages.first) ? message : result.future;
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets(
    'closing Mail disposes its reader and ignores pending message content',
    (WidgetTester tester) async {
      final client = _DeferredMailClient();
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (BuildContext context) => StudioMailDialog(
                    strings: _strings,
                    clientFactory: (_) => client,
                  ),
                ),
                child: const Text('Show mail'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show mail'));
      await _pump(tester);
      await tester.enterText(
        _field(_strings.emailAddress),
        'reader@example.invalid',
      );
      await tester.enterText(_field(_strings.password), 'session-password');
      await tester.tap(
        find.widgetWithText(SwitchListTile, _strings.manualServers),
      );
      await _pump(tester);
      await tester.enterText(_field(_strings.imapHost), 'imap.example.invalid');
      await tester.enterText(_field(_strings.smtpHost), 'smtp.example.invalid');
      await tester.tap(find.widgetWithText(FilledButton, _strings.connect));
      await _pump(tester);

      await tester.tap(find.text('Current message'));
      await _pump(tester);
      final controller = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      expect(controller.decodedText, contains('Body of Current message.'));
      await tester.tap(find.text('Deferred message'));
      await _pump(tester);
      expect(client.contentRequests, 2);
      expect(client.result.isCompleted, isFalse);
      expect(controller.isDisposed, isFalse);

      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      expect(find.byType(StudioMailDialog), findsNothing);
      expect(controller.isDisposed, isTrue);
      expect(client.disconnects, 1);

      client.result.complete(_message('Late server response'));
      await _pump(tester);
      expect(find.byType(StudioMailDialog), findsNothing);
      expect(find.byType(MailMessageView), findsNothing);
      expect(client.disconnects, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
