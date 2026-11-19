import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

class _Incoming extends mail.ImapClient {
  int aborts = 0;
  bool failAbort = false;

  @override
  Future<void> abort() async {
    aborts++;
    if (failAbort) throw StateError('incoming cleanup failed');
  }
}

class _Outgoing extends mail.SmtpClient {
  _Outgoing() : super('example.invalid');

  int aborts = 0;
  bool failAbort = false;

  @override
  Future<void> abort() async {
    aborts++;
    if (failAbort) throw StateError('outgoing cleanup failed');
  }
}

mail.Mailbox _box(String name, {bool selectable = true}) => mail.Mailbox(
  encodedName: name,
  encodedPath: name,
  pathSeparator: '/',
  flags: <mail.MailboxFlag>[
    if (name == 'Inbox') mail.MailboxFlag.inbox,
    if (!selectable) mail.MailboxFlag.noSelect,
  ],
);

mail.MimeMessage _message(String subject) => mail.MimeMessage.parseFromText(
  'From: Writer <writer@example.invalid>\r\n'
  'To: Reader <reader@example.invalid>\r\n'
  'Subject: $subject\r\n'
  'Content-Type: text/plain; charset=utf-8\r\n'
  '\r\nBody of $subject.\r\n',
);

class _Client extends Fake implements mail.MailClient {
  final incoming = _Incoming();
  final outgoing = _Outgoing();
  Completer<void>? connectGate;
  Completer<List<mail.MimeMessage>>? fetchGate;
  Completer<void>? sendGate;
  bool failDisconnect = false;
  List<mail.Mailbox> boxes = <mail.Mailbox>[_box('Inbox'), _box('Archive')];
  List<mail.MimeMessage> messages = <mail.MimeMessage>[
    _message('First message'),
  ];
  int connects = 0;
  int lists = 0;
  int selections = 0;
  int fetches = 0;
  int sends = 0;
  int disconnects = 0;
  final sentMessages = <mail.MimeMessage>[];
  final sentRecipients = <List<String>>[];
  final sentAppendToSent = <bool>[];

  @override
  mail.Mailbox get selectedMailbox => boxes.first;

  @override
  mail.ImapClient get lowLevelIncomingMailClient => incoming;

  @override
  mail.SmtpClient get lowLevelOutgoingMailClient => outgoing;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    connects++;
    await connectGate?.future;
  }

  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async {
    lists++;
    return boxes;
  }

  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async {
    selections++;
    return mailbox;
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
    return fetchGate == null ? messages : await fetchGate!.future;
  }

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
    sends++;
    sentMessages.add(mail.MimeMessage.parseFromText(message.renderMessage()));
    sentRecipients.add([
      for (final recipient in recipients ?? const <mail.MailAddress>[])
        recipient.email,
    ]);
    sentAppendToSent.add(appendToSent);
    await sendGate?.future;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    if (failDisconnect) throw StateError('disconnect failed');
  }
}

final class _Loader implements StudioMailMessageLoader {
  _Loader({this.raw});

  final Uint8List? raw;

  @override
  Future<void> markRead(mail.Mailbox mailbox, mail.MimeMessage header) async {
    throw StateError('This session fixture must not write message flags.');
  }

  @override
  Future<Uint8List> fetch(mail.Mailbox mailbox, mail.MimeMessage header) async {
    if (raw case final bytes?) return Uint8List.fromList(bytes);
    throw StateError('This session fixture must not fetch message bodies.');
  }

  @override
  void cancel() {}

  @override
  void dispose() {}
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _show(
  WidgetTester tester,
  mail.MailClient Function(mail.MailAccount) factory, {
  Future<mail.ClientConfig?> Function(String)? discover,
  _Loader? loader,
}) async {
  tester.view
    ..physicalSize = const Size(1300, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailDialog(
                strings: _strings,
                clientFactory: factory,
                accountDiscovery: discover,
                messageLoaderFactory: (_) => loader ?? _Loader(),
              ),
            ),
            child: const Text('Open session'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open session'));
  await _pump(tester);
  await tester.enterText(
    _field(_strings.emailAddress),
    'reader@example.invalid',
  );
  await tester.enterText(_field(_strings.password), 'original-test-password');
}

Future<void> _manual(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(SwitchListTile, _strings.manualServers));
  await tester.pump();
  await tester.enterText(_field(_strings.imapHost), 'imap.example.invalid');
  await tester.enterText(_field(_strings.smtpHost), 'smtp.example.invalid');
}

Future<void> _connect(WidgetTester tester) async {
  await tester.ensureVisible(find.text(_strings.connect));
  await tester.tap(find.text(_strings.connect));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _connected(
  WidgetTester tester,
  _Client client, {
  _Loader? loader,
}) async {
  await _show(tester, (_) => client, loader: loader);
  await _manual(tester);
  await _connect(tester);
  await _pump(tester);
  expect(find.text('First message'), findsOneWidget);
}

void _expectClosed(_Client client) {
  expect(client.incoming.aborts, greaterThan(0));
  expect(client.outgoing.aborts, greaterThan(0));
  expect(client.disconnects, greaterThan(0));
}

Future<void> _compose(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
  await _pump(tester);
  await tester.enterText(_field(_strings.to), 'recipient@example.invalid');
  await tester.enterText(_field(_strings.subject), 'Session draft');
  tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller
      .insertText('Draft body.');
  await tester.pump();
}

mail.ClientConfig _configuration() {
  final provider = mail.ConfigEmailProvider()
    ..addIncomingServer(
      const mail.ServerConfig(
        type: mail.ServerType.imap,
        hostname: 'imap.example.invalid',
        port: 993,
        socketType: mail.SocketType.ssl,
        authentication: mail.Authentication.plain,
        usernameType: mail.UsernameType.emailAddress,
      ),
    )
    ..addOutgoingServer(
      const mail.ServerConfig(
        type: mail.ServerType.smtp,
        hostname: 'smtp.example.invalid',
        port: 465,
        socketType: mail.SocketType.ssl,
        authentication: mail.Authentication.plain,
        usernameType: mail.UsernameType.emailAddress,
      ),
    );
  return mail.ClientConfig(emailProviders: [provider]);
}

void main() {
  testWidgets('closing during connect aborts pending owned clients', (
    tester,
  ) async {
    final client = _Client()..connectGate = Completer<void>();
    await _show(tester, (_) => client);
    await _manual(tester);
    await _connect(tester);
    expect(client.connects, 1);
    await tester.tap(find.byTooltip(_strings.close));
    await _pump(tester);
    _expectClosed(client);
    client.connectGate!.complete();
    await _pump(tester);
    expect(client.lists, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery uses the credentials captured when connect starts', (
    tester,
  ) async {
    final discovery = Completer<mail.ClientConfig?>();
    mail.MailAccount? captured;
    final client = _Client();
    await _show(tester, (account) {
      captured = account;
      return client;
    }, discover: (_) => discovery.future);
    await _connect(tester);
    await tester.enterText(_field(_strings.password), 'changed-test-password');
    discovery.complete(_configuration());
    await _pump(tester);
    final authentication =
        captured!.incoming.authentication as mail.PlainAuthentication;
    expect(authentication.password, 'original-test-password');
  });

  testWidgets('only nonselectable folders release both owned transports', (
    tester,
  ) async {
    final client = _Client()
      ..boxes = [
        _box('Inbox', selectable: false),
        _box('Archive', selectable: false),
      ];
    await _show(tester, (_) => client);
    await _manual(tester);
    await _connect(tester);
    await _pump(tester);
    _expectClosed(client);
    expect(client.fetches, 0);
    expect(find.text(_strings.mailConnectionFailed), findsOneWidget);
    expect(find.text(_strings.connect), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fail in <bool>[false, true]) {
    testWidgets(
      'old mailbox ${fail ? 'failure' : 'results'} cannot replace a new session',
      (tester) async {
        final oldClient = _Client();
        final newClient = _Client()
          ..messages = <mail.MimeMessage>[_message('New session message')];
        var attempts = 0;
        await _show(tester, (_) => attempts++ == 0 ? oldClient : newClient);
        await _manual(tester);
        await _connect(tester);
        await _pump(tester);
        oldClient.fetchGate = Completer<List<mail.MimeMessage>>();
        await tester.tap(find.text('Archive'));
        await tester.pump();
        expect(oldClient.fetches, 2);
        await tester.tap(find.byTooltip(_strings.disconnect));
        await _pump(tester);
        await _connect(tester);
        await _pump(tester);
        if (fail) {
          oldClient.fetchGate!.completeError(StateError('old mailbox failed'));
        } else {
          oldClient.fetchGate!.complete(<mail.MimeMessage>[
            _message('Stale message'),
          ]);
        }
        await _pump(tester);
        expect(find.text('New session message'), findsOneWidget);
        expect(find.text('Stale message'), findsNothing);
        expect(find.textContaining('old mailbox failed'), findsNothing);
        expect(tester.takeException(), isNull);
        _expectClosed(oldClient);
      },
    );
  }

  testWidgets('a draft from a disconnected session is not sent', (
    tester,
  ) async {
    final client = _Client();
    await _connected(tester, client);
    await _compose(tester);
    final disconnect = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == _strings.disconnect,
            skipOffstage: false,
          ),
        )
        .onPressed!;
    disconnect();
    await tester.pump();
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.send));
    await _pump(tester);
    expect(client.sends, 0);
    _expectClosed(client);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late send failure cannot alter a replacement session', (
    tester,
  ) async {
    final oldClient = _Client();
    final newClient = _Client()
      ..messages = <mail.MimeMessage>[_message('New session message')];
    var attempts = 0;
    await _show(tester, (_) => attempts++ == 0 ? oldClient : newClient);
    await _manual(tester);
    await _connect(tester);
    await _pump(tester);
    oldClient.sendGate = Completer<void>();
    await _compose(tester);
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.send));
    await tester.pump(const Duration(seconds: 1));
    expect(oldClient.sends, 1);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await _pump(tester);
    await _connect(tester);
    await _pump(tester);
    oldClient.sendGate!.completeError(StateError('old send failed'));
    await _pump(tester);
    expect(find.text('New session message'), findsOneWidget);
    expect(find.textContaining('old send failed'), findsNothing);
    _expectClosed(oldClient);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native composition submits To Cc and Bcc only in the explicit envelope',
    (tester) async {
      final client = _Client();
      await _connected(tester, client);
      await _compose(tester);
      await tester.enterText(
        _field(_strings.to),
        'first@example.invalid; second@example.invalid',
      );
      await tester.tap(find.text(_strings.mailCopyRecipients));
      await _pump(tester);
      await tester.enterText(_field(_strings.mailCc), 'copied@example.invalid');
      await tester.enterText(
        _field(_strings.mailBcc),
        'hidden@example.invalid',
      );
      final send = find.widgetWithIcon(FilledButton, Icons.send);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(client.sends, 1);
      expect(client.sentRecipients.single, [
        'first@example.invalid',
        'second@example.invalid',
        'copied@example.invalid',
        'hidden@example.invalid',
      ]);
      final message = client.sentMessages.single;
      expect(message.to!.map((address) => address.email), [
        'first@example.invalid',
        'second@example.invalid',
      ]);
      expect(message.cc!.single.email, 'copied@example.invalid');
      expect(message.getHeaderValue('bcc'), isNull);
      expect(
        message.renderMessage(),
        isNot(contains('hidden@example.invalid')),
      );
      expect(client.sentAppendToSent.single, isFalse);
      expect(find.text(_strings.mailSubmissionAccepted), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native Reply all retains every recipient and thread through an uncertain retry',
    (tester) async {
      final client = _Client()..sendGate = Completer<void>();
      final loader = _Loader(
        raw: Uint8List.fromList(
          utf8.encode(
            'From: writer@example.invalid\r\n'
            'Reply-To: author@example.invalid\r\n'
            'To: reader@example.invalid, teammate@example.invalid\r\n'
            'Cc: copied@example.invalid\r\n'
            'Bcc: source-hidden@example.invalid\r\n'
            'Message-ID: <parent@example.invalid>\r\n'
            'References: <root@example.invalid>\r\n'
            'Subject: First message\r\n'
            'Content-Type: text/plain; charset=utf-8\r\n\r\nSource body.\r\n',
          ),
        ),
      );
      await _connected(tester, client, loader: loader);
      await tester.tap(find.text('First message'));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.replyAll));
      await _pump(tester);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(_field(_strings.to)).controller!.text,
        'author@example.invalid, teammate@example.invalid',
      );
      expect(
        tester.widget<TextField>(_field(_strings.mailCc)).controller!.text,
        'copied@example.invalid',
      );
      expect(
        tester.widget<TextField>(_field(_strings.mailBcc)).controller!.text,
        isEmpty,
      );
      await tester.enterText(
        _field(_strings.mailBcc),
        'new-hidden@example.invalid',
      );
      final send = find.widgetWithIcon(FilledButton, Icons.send);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(client.sends, 1);
      client.sendGate!.completeError(StateError('submission disconnected'));
      await _pump(tester);
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
      await _pump(tester);
      expect(
        tester.widget<TextField>(_field(_strings.to)).controller!.text,
        'author@example.invalid, teammate@example.invalid',
      );
      expect(
        tester.widget<TextField>(_field(_strings.mailCc)).controller!.text,
        'copied@example.invalid',
      );
      expect(
        tester.widget<TextField>(_field(_strings.mailBcc)).controller!.text,
        'new-hidden@example.invalid',
      );
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(client.sends, 1);
      client.sendGate = null;
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await _pump(tester);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(client.sends, 2);
      for (final recipients in client.sentRecipients) {
        expect(recipients, [
          'author@example.invalid',
          'teammate@example.invalid',
          'copied@example.invalid',
          'new-hidden@example.invalid',
        ]);
      }
      for (final message in client.sentMessages) {
        expect(
          message.getHeaderValue('in-reply-to'),
          '<parent@example.invalid>',
        );
        expect(
          message.getHeaderValue('references'),
          '<root@example.invalid> <parent@example.invalid>',
        );
        expect(message.getHeaderValue('bcc'), isNull);
        expect(
          message.renderMessage(),
          isNot(contains('new-hidden@example.invalid')),
        );
        expect(
          message.renderMessage(),
          isNot(contains('source-hidden@example.invalid')),
        );
      }
      expect(find.text(_strings.mailSubmissionAccepted), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disconnect contains cleanup errors and aborts both transports', (
    tester,
  ) async {
    final client = _Client()..failDisconnect = true;
    client.incoming.failAbort = true;
    client.outgoing.failAbort = true;
    await _connected(tester, client);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await _pump(tester);
    _expectClosed(client);
    expect(tester.takeException(), isNull);
    expect(find.text(_strings.connect), findsOneWidget);
  });
}
