import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/studio_mail_fixture.dart';

void main() {
  testWidgets('manual setup connects with secure settings and disconnects', (
    tester,
  ) async {
    final client = MailClientFixture();
    mail.MailAccount? configured;
    await openMail(tester, (account) {
      configured = account;
      return client;
    });
    expect(client.connects, 0);
    expect(find.text(mailStrings.mailSessionNotice), findsOneWidget);
    await connectMail(tester);
    expect(configured!.email, 'reader@example.invalid');
    expect(configured!.incoming.serverConfig.hostname, 'imap.example.invalid');
    expect(configured!.outgoing.serverConfig.hostname, 'smtp.example.invalid');
    expect(configured!.incoming.serverConfig.socketType, mail.SocketType.ssl);
    expect(configured!.outgoing.serverConfig.socketType, mail.SocketType.ssl);
    expect(find.text('First message'), findsOneWidget);
    expect(find.text(mailStrings.noMessage), findsOneWidget);
    await tester.tap(find.byTooltip(mailStrings.disconnect));
    await pumpMail(tester);
    expect(client.disconnects, 1);
    expect(
      find.widgetWithText(FilledButton, mailStrings.connect),
      findsOneWidget,
    );
    expect(find.text('First message'), findsNothing);
    await closeMail(tester);
  });

  for (final phase in ['connect', 'list', 'fetch']) {
    for (final fail in [false, true]) {
      testWidgets(
        'closing during $phase ignores its late ${fail ? 'error' : 'success'} and closes the client',
        (tester) async {
          final client = MailClientFixture();
          final gate = Completer<void>();
          switch (phase) {
            case 'connect':
              client.onConnect = () => gate.future;
            case 'list':
              client.onList = () async {
                await gate.future;
                return client.boxes;
              };
            case 'fetch':
              client.onFetch = () async {
                await gate.future;
                return client.messages;
              };
          }
          await openMail(tester, (_) => client);
          await connectMail(tester);
          await closeMail(tester);
          if (fail) {
            gate.completeError(StateError('late $phase failure'));
          } else {
            gate.complete();
          }
          await pumpMail(tester);
          expect(client.disconnects, greaterThanOrEqualTo(1));
          if (phase == 'connect') expect(client.lists, 0);
          if (phase == 'list') expect(client.fetches, 0);
          expect(find.byType(StudioMailDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$phase failure releases the candidate and allows a fresh connection',
      (tester) async {
        final first = MailClientFixture();
        final second = MailClientFixture();
        final clients = [first, second];
        Future<Never> fail() async => throw StateError('$phase failed');
        switch (phase) {
          case 'connect':
            first.onConnect = fail;
          case 'list':
            first.onList = fail;
          case 'fetch':
            first.onFetch = fail;
        }
        await openMail(tester, (_) => clients.removeAt(0));
        await connectMail(tester);
        expect(find.textContaining('$phase failed'), findsOneWidget);
        expect(first.disconnects, 1);
        await connectMail(tester);
        expect(second.connects, 1);
        expect(find.text('First message'), findsOneWidget);
        expect(find.textContaining('$phase failed'), findsNothing);
        await closeMail(tester);
        expect(second.disconnects, 1);
      },
    );
  }

  testWidgets(
    'an account without a selectable mailbox is closed and reports its error',
    (tester) async {
      final client = MailClientFixture()..boxes.clear();
      await openMail(tester, (_) => client);
      await connectMail(tester);
      expect(find.textContaining('no selectable mailbox'), findsOneWidget);
      expect(client.disconnects, 1);
      expect(client.fetches, 0);
      await closeMail(tester);
    },
  );

  testWidgets(
    'opening messages replaces and disposes readers; a failed read preserves the current message',
    (tester) async {
      final client = MailClientFixture();
      await openMail(tester, (_) => client);
      await connectMail(tester);
      await tester.tap(find.text('First message'));
      await pumpMail(tester);
      final first = mailReader(tester);
      expect(first.decodedText, contains('Body of First message.'));
      await tester.tap(find.text('Second message').first);
      await pumpMail(tester);
      final second = mailReader(tester);
      expect(first.isDisposed, isTrue);
      expect(second.decodedText, contains('Body of Second message.'));
      client.onContents = (_) async => throw StateError('message read failed');
      await tester.tap(find.text('First message').first);
      await pumpMail(tester);
      expect(mailReader(tester), same(second));
      expect(second.isDisposed, isFalse);
      expect(find.textContaining('message read failed'), findsOneWidget);
      await closeMail(tester);
      expect(second.isDisposed, isTrue);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'a message read ${fail ? 'error' : 'success'} cannot alter a reconnected session',
      (tester) async {
        final first = MailClientFixture();
        final second = MailClientFixture();
        final clients = [first, second];
        final gate = Completer<mail.MimeMessage>();
        first.onContents = (_) => gate.future;
        await openMail(tester, (_) => clients.removeAt(0));
        await connectMail(tester);
        await tester.tap(find.text('First message'));
        await pumpMail(tester);
        await tester.tap(find.byTooltip(mailStrings.disconnect));
        await pumpMail(tester);
        await connectMail(tester);
        if (fail) {
          gate.completeError(StateError('stale read failure'));
        } else {
          gate.complete(mailMessageFixture('Stale message'));
        }
        await pumpMail(tester);
        expect(find.byType(MailMessageView), findsNothing);
        expect(find.textContaining('stale read failure'), findsNothing);
        expect(find.text('First message'), findsOneWidget);
        expect(second.disconnects, 0);
        expect(tester.takeException(), isNull);
        await closeMail(tester);
      },
    );
  }

  for (final phase in ['select', 'fetch']) {
    for (final fail in [false, true]) {
      testWidgets(
        'disconnect during mailbox $phase ignores a late ${fail ? 'error' : 'success'}',
        (tester) async {
          final client = MailClientFixture();
          await openMail(tester, (_) => client);
          await connectMail(tester);
          final gate = Completer<void>();
          if (phase == 'select') {
            client.onSelect = (box) async {
              await gate.future;
              return box;
            };
          } else {
            client.onFetch = () async {
              await gate.future;
              return client.messages;
            };
          }
          await tester.tap(find.text('Archive'));
          await pumpMail(tester);
          expect(find.text('First message'), findsNothing);
          await tester.tap(find.byTooltip(mailStrings.disconnect));
          await pumpMail(tester);
          if (fail) {
            gate.completeError(StateError('stale mailbox failure'));
          } else {
            gate.complete();
          }
          await pumpMail(tester);
          expect(
            find.widgetWithText(FilledButton, mailStrings.connect),
            findsOneWidget,
          );
          expect(find.text('First message'), findsNothing);
          expect(find.textContaining('stale mailbox failure'), findsNothing);
          if (phase == 'select') expect(client.fetches, 1);
          expect(tester.takeException(), isNull);
          await closeMail(tester);
        },
      );
    }
  }

  testWidgets(
    'mailbox failure does not leave another folder’s messages visible',
    (tester) async {
      final client = MailClientFixture();
      await openMail(tester, (_) => client);
      await connectMail(tester);
      client.onFetch = () async => throw StateError('mailbox load failed');
      await tester.tap(find.text('Archive'));
      await pumpMail(tester);
      expect(find.textContaining('mailbox load failed'), findsOneWidget);
      expect(find.text('First message'), findsNothing);
      await closeMail(tester);
    },
  );

  testWidgets('composing sends the draft and reports success or failure', (
    tester,
  ) async {
    final client = MailClientFixture();
    await openMail(tester, (_) => client);
    await connectMail(tester);
    await composeMail(tester);
    expect(client.sent.single.decodeSubject(), 'Controlled draft');
    expect(client.sent.single.to!.single.email, 'recipient@example.invalid');
    expect(client.sent.single.decodeTextPlainPart(), 'A <safe> body.');
    expect(find.text(mailStrings.messageSent), findsOneWidget);
    client.onSend = (_) async => throw StateError('send failed');
    await composeMail(tester);
    expect(find.textContaining('send failed'), findsOneWidget);
    expect(find.text(mailStrings.messageSent), findsNothing);
    expect(find.text(mailStrings.sending), findsNothing);
    expect(find.textContaining(mailStrings.sentCopyWarning), findsNothing);
    expect(find.textContaining(mailStrings.sentCleanupWarning), findsNothing);
    await closeMail(tester);
  });

  for (final (copy, cleanup) in [(true, false), (false, true), (true, true)]) {
    testWidgets(
      'confirmed submission shows sent with copy=$copy cleanup=$cleanup warnings',
      (tester) async {
        final client = MailClientFixture();
        client.onSend = (_) async => throw mail.MailSendPostSubmissionException(
          client,
          sentCopyError: copy ? StateError('controlled filing error') : null,
          cleanupError: cleanup ? StateError('controlled cleanup error') : null,
        );
        await openMail(tester, (_) => client);
        await connectMail(tester);
        await composeMail(tester);
        expect(client.sent, hasLength(1));
        expect(find.text(mailStrings.messageSent), findsOneWidget);
        expect(find.text(mailStrings.sending), findsNothing);
        expect(
          find.textContaining(mailStrings.sentCopyWarning),
          copy ? findsOneWidget : findsNothing,
        );
        expect(
          find.textContaining(mailStrings.sentCleanupWarning),
          cleanup ? findsOneWidget : findsNothing,
        );
        expect(find.textContaining('controlled filing error'), findsNothing);
        expect(find.textContaining('controlled cleanup error'), findsNothing);
        if (copy && cleanup) {
          client.onSend = null;
          await composeMail(tester);
          expect(client.sent, hasLength(2));
          expect(find.text(mailStrings.messageSent), findsOneWidget);
          expect(
            find.textContaining(mailStrings.sentCopyWarning),
            findsNothing,
          );
          expect(
            find.textContaining(mailStrings.sentCleanupWarning),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await closeMail(tester);
      },
    );
  }

  testWidgets('a late submitted-message warning cannot change a new session', (
    tester,
  ) async {
    final first = MailClientFixture();
    final second = MailClientFixture();
    final clients = [first, second];
    final gate = Completer<void>();
    first.onSend = (_) => gate.future;
    await openMail(tester, (_) => clients.removeAt(0));
    await connectMail(tester);
    await composeMail(tester);
    await tester.tap(find.byTooltip(mailStrings.disconnect));
    await pumpMail(tester);
    await connectMail(tester);
    gate.completeError(
      mail.MailSendPostSubmissionException(
        first,
        sentCopyError: StateError('late filing error'),
        cleanupError: StateError('late cleanup error'),
      ),
    );
    await pumpMail(tester);
    expect(find.text('First message'), findsOneWidget);
    expect(find.text(mailStrings.messageSent), findsNothing);
    expect(find.textContaining(mailStrings.sentCopyWarning), findsNothing);
    expect(find.textContaining(mailStrings.sentCleanupWarning), findsNothing);
    expect(second.disconnects, 0);
    expect(tester.takeException(), isNull);
    await closeMail(tester);
  });

  for (final fail in [false, true]) {
    testWidgets(
      'disconnect during send ignores its late ${fail ? 'error' : 'success'}',
      (tester) async {
        final client = MailClientFixture();
        final gate = Completer<void>();
        client.onSend = (_) => gate.future;
        await openMail(tester, (_) => client);
        await connectMail(tester);
        await composeMail(tester);
        expect(find.text(mailStrings.sending), findsOneWidget);
        await tester.tap(find.byTooltip(mailStrings.disconnect));
        await pumpMail(tester);
        if (fail) {
          gate.completeError(StateError('late send failure'));
        } else {
          gate.complete();
        }
        await pumpMail(tester);
        expect(
          find.widgetWithText(FilledButton, mailStrings.connect),
          findsOneWidget,
        );
        expect(find.text(mailStrings.messageSent), findsNothing);
        expect(find.textContaining('late send failure'), findsNothing);
        expect(tester.takeException(), isNull);
        await closeMail(tester);
      },
    );
  }

  testWidgets('search tolerates messages with an empty sender list', (
    tester,
  ) async {
    final client = MailClientFixture();
    client.messages.first.from = <mail.MailAddress>[];
    await openMail(tester, (_) => client);
    await connectMail(tester);
    await tester.enterText(find.byType(TextField), 'unmatched');
    await pumpMail(tester);
    expect(find.text(mailStrings.noMessages), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeMail(tester);
  });

  for (final dismiss in [false, true]) {
    testWidgets(
      '${dismiss ? 'closing' : 'disconnecting'} catches asynchronous cleanup errors',
      (tester) async {
        final client = MailClientFixture()
          ..disconnectFailure = StateError('cleanup failed');
        await openMail(tester, (_) => client);
        await connectMail(tester);
        if (dismiss) {
          await closeMail(tester);
        } else {
          await tester.tap(find.byTooltip(mailStrings.disconnect));
          await pumpMail(tester);
          expect(
            find.widgetWithText(FilledButton, mailStrings.connect),
            findsOneWidget,
          );
          await closeMail(tester);
        }
        expect(client.disconnects, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'German Mail retains localized account controls and reading prompt',
    (tester) async {
      const strings = StudioStrings(StudioLanguage.de);
      final client = MailClientFixture();
      await openMail(tester, (_) => client, strings: strings);
      expect(find.text(strings.mailSessionNotice), findsOneWidget);
      await connectMail(tester, strings: strings);
      expect(find.text(strings.noMessage), findsOneWidget);
      expect(find.byTooltip(strings.disconnect), findsOneWidget);
      await closeMail(tester, strings: strings);
    },
  );
}
