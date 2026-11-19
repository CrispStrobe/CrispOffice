import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

mail.Mailbox _box(String name) => mail.Mailbox(
  encodedName: name,
  encodedPath: name,
  flags: <mail.MailboxFlag>[],
  pathSeparator: '/',
);

mail.MimeMessage _message(String subject) => mail.MimeMessage.parseFromText(
  'From: Writer <writer@example.invalid>\r\n'
  'To: Reader <reader@example.invalid>\r\n'
  'Subject: $subject\r\n'
  'Content-Type: text/plain; charset=utf-8\r\n'
  '\r\n'
  'Body of $subject.\r\n',
);

final class _Client extends Fake implements mail.MailClient {
  final boxes = <mail.Mailbox>[_box('INBOX'), _box('Archive')];
  final messages = <mail.MimeMessage>[
    _message('First message'),
    _message('Second message'),
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
  final appendRequests = <bool>[];
  final recipientLists = <List<mail.MailAddress>?>[];
  mail.Mailbox? _selectedMailbox;

  @override
  mail.Mailbox? get selectedMailbox => _selectedMailbox ?? boxes.first;

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
    _selectedMailbox = mailbox ?? _selectedMailbox;
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
    appendRequests.add(appendToSent);
    recipientLists.add(recipients);
    await onSend?.call(message);
  }
}

final class _Loader implements StudioMailMessageLoader {
  _Loader(this.client);
  final mail.MailClient client;
  @override
  Future<Uint8List> fetch(mail.Mailbox mailbox, mail.MimeMessage header) async {
    final full = await client.fetchMessageContents(header);
    // Controlled test fixture bytes; production uses the bounded raw provider.
    return Uint8List.fromList(utf8.encode(full.renderMessage()));
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
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
  WidgetTester tester,
  mail.MailClient Function(mail.MailAccount) clientFactory, {
  StudioStrings strings = _strings,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  mail.MailClient? createdClient;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailDialog(
                strings: strings,
                clientFactory: (account) =>
                    createdClient = clientFactory(account),
                messageLoaderFactory: (_) => _Loader(createdClient!),
              ),
            ),
            child: const Text('Launch Mail'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launch Mail'));
  await _pump(tester);
  await tester.enterText(
    _field(strings.emailAddress),
    'reader@example.invalid',
  );
  await tester.enterText(_field(strings.password), 'session-password');
  await tester.tap(find.widgetWithText(SwitchListTile, strings.manualServers));
  await _pump(tester);
  await tester.enterText(_field(strings.imapHost), 'imap.example.invalid');
  await tester.enterText(_field(strings.smtpHost), 'smtp.example.invalid');
}

Future<void> _connect(
  WidgetTester tester, {
  StudioStrings strings = _strings,
}) async {
  await tester.tap(find.widgetWithText(FilledButton, strings.connect));
  await _pump(tester);
}

Future<void> _close(
  WidgetTester tester, {
  StudioStrings strings = _strings,
}) async {
  await tester.tap(find.byTooltip(strings.close));
  await _pump(tester);
  expect(find.byType(StudioMailDialog), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _compose(
  WidgetTester tester, {
  StudioStrings strings = _strings,
}) async {
  await tester.tap(find.widgetWithText(TextButton, strings.compose));
  await _pump(tester);
  await tester.enterText(_field(strings.to), 'recipient@example.invalid');
  await tester.enterText(_field(strings.subject), 'Controlled draft');
  tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller
      .insertText('A <safe> body.');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, strings.send));
  await _pump(tester);
}

MailReaderController _reader(WidgetTester tester) =>
    tester.widget<MailMessageView>(find.byType(MailMessageView)).controller;

void main() {
  testWidgets('manual setup connects with secure settings and disconnects', (
    tester,
  ) async {
    final client = _Client();
    mail.MailAccount? configured;
    await _open(tester, (account) {
      configured = account;
      return client;
    });
    expect(client.connects, 0);
    expect(find.text(_strings.mailSessionNotice), findsOneWidget);
    await _connect(tester);
    expect(configured!.email, 'reader@example.invalid');
    expect(configured!.incoming.serverConfig.hostname, 'imap.example.invalid');
    expect(configured!.outgoing.serverConfig.hostname, 'smtp.example.invalid');
    expect(configured!.incoming.serverConfig.socketType, mail.SocketType.ssl);
    expect(configured!.outgoing.serverConfig.socketType, mail.SocketType.ssl);
    expect(find.text('First message'), findsOneWidget);
    expect(find.text(_strings.noMessage), findsOneWidget);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await _pump(tester);
    expect(client.disconnects, 1);
    expect(find.widgetWithText(FilledButton, _strings.connect), findsOneWidget);
    expect(find.text('First message'), findsNothing);
    await _close(tester);
  });

  for (final phase in ['connect', 'list', 'fetch']) {
    for (final fail in [false, true]) {
      testWidgets(
        'closing during $phase ignores its late ${fail ? 'error' : 'success'} and closes the client',
        (tester) async {
          final client = _Client();
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
          await _open(tester, (_) => client);
          await _connect(tester);
          await _close(tester);
          if (fail) {
            gate.completeError(StateError('late $phase failure'));
          } else {
            gate.complete();
          }
          await _pump(tester);
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
        final first = _Client();
        final second = _Client();
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
        await _open(tester, (_) => clients.removeAt(0));
        await _connect(tester);
        expect(find.text(_strings.mailConnectionFailed), findsOneWidget);
        expect(find.textContaining('$phase failed'), findsNothing);
        expect(first.disconnects, 1);
        await _connect(tester);
        expect(second.connects, 1);
        expect(find.text('First message'), findsOneWidget);
        expect(find.textContaining('$phase failed'), findsNothing);
        await _close(tester);
        expect(second.disconnects, 1);
      },
    );
  }

  testWidgets(
    'an account without a selectable mailbox is closed and reports its error',
    (tester) async {
      final client = _Client()..boxes.clear();
      await _open(tester, (_) => client);
      await _connect(tester);
      expect(find.text(_strings.mailConnectionFailed), findsOneWidget);
      expect(client.disconnects, 1);
      expect(client.fetches, 0);
      await _close(tester);
    },
  );

  testWidgets(
    'opening messages replaces and disposes readers; a failed read preserves the current message',
    (tester) async {
      final client = _Client();
      await _open(tester, (_) => client);
      await _connect(tester);
      await tester.tap(find.text('First message'));
      await _pump(tester);
      final first = _reader(tester);
      expect(first.decodedText, contains('Body of First message.'));
      await tester.tap(find.text('Second message').first);
      await _pump(tester);
      final second = _reader(tester);
      expect(first.isDisposed, isTrue);
      expect(second.decodedText, contains('Body of Second message.'));
      client.onContents = (_) async => throw StateError('message read failed');
      await tester.tap(find.text('First message').first);
      await _pump(tester);
      expect(_reader(tester), same(second));
      expect(second.isDisposed, isFalse);
      expect(find.text(_strings.mailMessageFailed), findsOneWidget);
      await _close(tester);
      expect(second.isDisposed, isTrue);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'a message read ${fail ? 'error' : 'success'} cannot alter a reconnected session',
      (tester) async {
        final first = _Client();
        final second = _Client();
        final clients = [first, second];
        final gate = Completer<mail.MimeMessage>();
        first.onContents = (_) => gate.future;
        await _open(tester, (_) => clients.removeAt(0));
        await _connect(tester);
        await tester.tap(find.text('First message'));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.disconnect));
        await _pump(tester);
        await _connect(tester);
        if (fail) {
          gate.completeError(StateError('stale read failure'));
        } else {
          gate.complete(_message('Stale message'));
        }
        await _pump(tester);
        expect(find.byType(MailMessageView), findsNothing);
        expect(find.textContaining('stale read failure'), findsNothing);
        expect(find.text('First message'), findsOneWidget);
        expect(second.disconnects, 0);
        expect(tester.takeException(), isNull);
        await _close(tester);
      },
    );
  }

  for (final phase in ['select', 'fetch']) {
    for (final fail in [false, true]) {
      testWidgets(
        'disconnect during mailbox $phase ignores a late ${fail ? 'error' : 'success'}',
        (tester) async {
          final client = _Client();
          await _open(tester, (_) => client);
          await _connect(tester);
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
          await _pump(tester);
          expect(find.text('First message'), findsNothing);
          await tester.tap(find.byTooltip(_strings.disconnect));
          await _pump(tester);
          if (fail) {
            gate.completeError(StateError('stale mailbox failure'));
          } else {
            gate.complete();
          }
          await _pump(tester);
          expect(
            find.widgetWithText(FilledButton, _strings.connect),
            findsOneWidget,
          );
          expect(find.text('First message'), findsNothing);
          expect(find.textContaining('stale mailbox failure'), findsNothing);
          if (phase == 'select') expect(client.fetches, 1);
          expect(tester.takeException(), isNull);
          await _close(tester);
        },
      );
    }
  }

  testWidgets(
    'mailbox failure does not leave another folder’s messages visible',
    (tester) async {
      final client = _Client();
      await _open(tester, (_) => client);
      await _connect(tester);
      client.onFetch = () async => throw StateError('mailbox load failed');
      await tester.tap(find.text('Archive'));
      await _pump(tester);
      expect(find.text(_strings.mailMailboxFailed), findsOneWidget);
      expect(find.textContaining('mailbox load failed'), findsNothing);
      expect(find.text('First message'), findsNothing);
      await _close(tester);
    },
  );

  testWidgets('composing sends the draft and reports success or failure', (
    tester,
  ) async {
    final client = _Client();
    await _open(tester, (_) => client);
    await _connect(tester);
    await _compose(tester);
    expect(client.sent.single.decodeSubject(), 'Controlled draft');
    expect(client.sent.single.to!.single.email, 'recipient@example.invalid');
    expect(client.sent.single.decodeTextPlainPart(), 'A <safe> body.');
    expect(find.text(_strings.mailSubmissionAccepted), findsOneWidget);
    client.onSend = (_) async => throw StateError('send failed');
    await _compose(tester);
    expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
    expect(find.textContaining('send failed'), findsNothing);
    expect(client.appendRequests, <bool>[false, false]);
    expect(
      client.recipientLists.every(
        (items) => items?.single.email == 'recipient@example.invalid',
      ),
      isTrue,
    );
    await tester.tap(find.widgetWithText(TextButton, _strings.compose));
    await _pump(tester);
    expect(find.byType(StudioMailComposeDialog), findsOneWidget);
    expect(
      tester.widget<TextField>(_field(_strings.subject)).controller!.text,
      'Controlled draft',
    );
    expect(
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller
          .document
          .paragraphs
          .single
          .text,
      'A <safe> body.',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, _strings.send),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text(_strings.cancel));
    await _pump(tester);
    expect(find.text(_strings.mailSubmissionAccepted), findsNothing);
    await _close(tester);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      'confirmed submission with failed cleanup clears draft in ${language.name}',
      (tester) async {
        final strings = StudioStrings(language);
        final client = _Client();
        client.onSend = (_) async => throw mail.MailSendPostSubmissionException(
          client,
          cleanupError: StateError('private server response session-password'),
        );
        await _open(tester, (_) => client, strings: strings);
        await _connect(tester, strings: strings);
        await _compose(tester, strings: strings);
        expect(find.text(strings.mailSubmissionFollowUpFailed), findsOneWidget);
        expect(find.text(strings.mailSubmissionUncertain), findsNothing);
        expect(find.textContaining('private server response'), findsNothing);
        expect(find.textContaining('session-password'), findsNothing);
        expect(client.sent, hasLength(1));
        expect(client.appendRequests, <bool>[false]);
        await tester.tap(find.widgetWithText(TextButton, strings.compose));
        await _pump(tester);
        expect(
          tester.widget<TextField>(_field(strings.to)).controller!.text,
          '',
        );
        expect(
          tester.widget<TextField>(_field(strings.subject)).controller!.text,
          '',
        );
        expect(
          tester
              .widget<QudsWordEditor>(find.byType(QudsWordEditor))
              .controller
              .document
              .paragraphs
              .single
              .text,
          '',
        );
        expect(find.text(strings.mailRetryAcknowledgement), findsNothing);
        await tester.tap(find.text(strings.cancel));
        await _pump(tester);
        expect(client.sent, hasLength(1));
        await _close(tester, strings: strings);
      },
    );
  }

  testWidgets('foreign client outcome cannot confirm the active submission', (
    tester,
  ) async {
    final client = _Client();
    client.onSend = (_) async => throw mail.MailSendPostSubmissionException(
      _Client(),
      cleanupError: StateError('foreign client cleanup'),
    );
    await _open(tester, (_) => client);
    await _connect(tester);
    await _compose(tester);
    expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
    expect(find.text(_strings.mailSubmissionFollowUpFailed), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, _strings.compose));
    await _pump(tester);
    expect(
      tester.widget<TextField>(_field(_strings.subject)).controller!.text,
      'Controlled draft',
    );
    expect(find.text(_strings.mailRetryAcknowledgement), findsOneWidget);
    await tester.tap(find.text(_strings.cancel));
    await _pump(tester);
    await _close(tester);
  });

  for (final outcome in ['success', 'error', 'accepted follow-up error']) {
    testWidgets('disconnect during send ignores its late $outcome', (
      tester,
    ) async {
      final client = _Client();
      final gate = Completer<void>();
      client.onSend = (_) => gate.future;
      await _open(tester, (_) => client);
      await _connect(tester);
      await _compose(tester);
      expect(find.text(_strings.sending), findsOneWidget);
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      if (outcome == 'accepted follow-up error') {
        gate.completeError(
          mail.MailSendPostSubmissionException(
            client,
            cleanupError: StateError('late cleanup failure'),
          ),
        );
      } else if (outcome == 'error') {
        gate.completeError(StateError('late send failure'));
      } else {
        gate.complete();
      }
      await _pump(tester);
      expect(
        find.widgetWithText(FilledButton, _strings.connect),
        findsOneWidget,
      );
      expect(find.text(_strings.mailSubmissionAccepted), findsNothing);
      expect(find.text(_strings.mailSubmissionFollowUpFailed), findsNothing);
      expect(find.textContaining('late send failure'), findsNothing);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }

  testWidgets('search tolerates messages with an empty sender list', (
    tester,
  ) async {
    final client = _Client();
    client.messages.first.from = <mail.MailAddress>[];
    await _open(tester, (_) => client);
    await _connect(tester);
    await tester.enterText(find.byType(TextField), 'unmatched');
    await _pump(tester);
    expect(find.text(_strings.noMessages), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  for (final dismiss in [false, true]) {
    testWidgets(
      '${dismiss ? 'closing' : 'disconnecting'} catches asynchronous cleanup errors',
      (tester) async {
        final client = _Client()
          ..disconnectFailure = StateError('cleanup failed');
        await _open(tester, (_) => client);
        await _connect(tester);
        if (dismiss) {
          await _close(tester);
        } else {
          await tester.tap(find.byTooltip(_strings.disconnect));
          await _pump(tester);
          expect(
            find.widgetWithText(FilledButton, _strings.connect),
            findsOneWidget,
          );
          await _close(tester);
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
      final client = _Client();
      await _open(tester, (_) => client, strings: strings);
      expect(find.text(strings.mailSessionNotice), findsOneWidget);
      await _connect(tester, strings: strings);
      expect(find.text(strings.noMessage), findsOneWidget);
      expect(find.byTooltip(strings.disconnect), findsOneWidget);
      await _close(tester, strings: strings);
    },
  );

  testWidgets('narrow inbox supports folders, reading and back navigation', (
    tester,
  ) async {
    final client = _Client();
    await _open(tester, (_) => client);
    await _connect(tester);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('First message'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('First message'));
    await _pump(tester);
    final reader = _reader(tester);
    expect(reader.decodedText, contains('Body of First message.'));
    expect(find.byTooltip(_strings.backToMessages), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip(_strings.backToMessages));
    await _pump(tester);
    expect(find.byType(MailMessageView), findsNothing);
    expect(reader.isDisposed, isFalse);
    await tester.tap(find.byType(DropdownButton<String>));
    await _pump(tester);
    await tester.tap(find.text('Archive').last);
    await _pump(tester);
    expect(client.selections, 1);
    expect(reader.isDisposed, isTrue);
    expect(find.text('First message'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('saved-message navigation retains the connected account', (
    tester,
  ) async {
    final client = _Client();
    await _open(tester, (_) => client);
    await _connect(tester);
    await tester.tap(find.byTooltip(_strings.savedMessages));
    await _pump(tester);
    final saved = _reader(tester);
    expect(saved.decodedText, contains('local, read-only message'));
    await tester.tap(find.byTooltip(_strings.mailAccounts));
    await _pump(tester);
    expect(find.text('First message'), findsOneWidget);
    expect(client.connects, 1);
    expect(client.disconnects, 0);
    expect(saved.isDisposed, isFalse);
    await _close(tester);
    expect(saved.isDisposed, isTrue);
    expect(client.disconnects, 1);
  });
}
