import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail.dart';

import 'support/studio_mail_fixture.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'closing Mail disposes its reader and ignores a pending message ${fail ? 'error' : 'success'}',
      (tester) async {
        final client = MailClientFixture();
        await openMail(tester, (_) => client);
        await connectMail(tester);
        await tester.tap(find.text('First message'));
        await pumpMail(tester);
        final reader = mailReader(tester);
        expect(reader.isDisposed, isFalse);
        expect(reader.decodedText, contains('Body of First message.'));

        final pending = Completer<mail.MimeMessage>();
        client.onContents = (_) => pending.future;
        await tester.tap(find.text('Second message'));
        await pumpMail(tester);
        expect(mailReader(tester), same(reader));
        expect(pending.isCompleted, isFalse);

        await closeMail(tester);
        expect(reader.isDisposed, isTrue);
        expect(client.disconnects, 1);
        if (fail) {
          pending.completeError(StateError('late contents failure'));
        } else {
          pending.complete(mailMessageFixture('Late message'));
        }
        await pumpMail(tester);
        expect(find.byType(StudioMailDialog), findsNothing);
        expect(find.byType(MailMessageView), findsNothing);
        expect(find.textContaining('late contents failure'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
