@TestOn('vm')
library;

import 'dart:io';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_server_search.dart';

void main() {
  final login = Platform.environment['MBOX_LOGIN'];
  final password = Platform.environment['MBOX_PW'];
  test(
    'live IMAP folder search returns bounded envelope rows and body matches',
    () async {
      final account = mail.MailAccount.fromManualSettings(
        name: login!,
        email: login,
        incomingHost: 'imap.mailbox.org',
        outgoingHost: 'smtp.mailbox.org',
        password: password!,
        incomingPort: 993,
        outgoingPort: 465,
        incomingSocketType: mail.SocketType.ssl,
        outgoingSocketType: mail.SocketType.ssl,
      );
      final client = mail.MailClient(account, isLogEnabled: false);
      await client.connect();
      try {
        final boxes = await client.listMailboxes();
        final inbox = boxes.firstWhere(
          (box) => box.isInbox && !box.isNotSelectable,
        );
        final messages = await client.fetchMessages(
          mailbox: inbox,
          count: 20,
          fetchPreference: mail.FetchPreference.envelope,
        );
        expect(messages, isNotEmpty);
        final target = messages.firstWhere(
          (message) => message.from?.isNotEmpty == true,
        );
        final address = target.from!.first.email;
        final from = await studioMailServerSearch(
          client: client,
          mailbox: inbox,
          field: StudioMailServerSearchField.from,
          query: address,
          limit: 20,
        );
        expect(from.mailboxName, inbox.name);
        expect(from.totalMatches, greaterThanOrEqualTo(1));
        expect(from.messages, isNotEmpty);
        expect(from.messages.every((message) => message.uid != null), isTrue);
        expect(from.truncated, from.totalMatches > from.messages.length);

        final full = await client.fetchMessageContents(
          target,
          markAsSeen: false,
        );
        final body = full.decodeTextPlainPart() ?? '';
        final token = RegExp(
          r'[A-Za-zÄÖÜäöüß]{6,}',
        ).allMatches(body).map((match) => match.group(0)!).firstOrNull;
        if (token != null) {
          final bodyResult = await studioMailServerSearch(
            client: client,
            mailbox: inbox,
            field: StudioMailServerSearchField.body,
            query: token,
            limit: 20,
          );
          expect(bodyResult.totalMatches, greaterThanOrEqualTo(1));
        }

        final cancellation = MailCancellationSource();
        cancellation.cancel();
        await expectLater(
          studioMailServerSearch(
            client: client,
            mailbox: inbox,
            field: StudioMailServerSearchField.subject,
            query: target.decodeSubject() ?? 'test',
            cancellation: cancellation.token,
          ),
          throwsA(isA<MailCancelled>()),
        );
      } finally {
        await client.disconnect();
      }
    },
    skip:
        login == null || login.isEmpty || password == null || password.isEmpty,
  );
}
