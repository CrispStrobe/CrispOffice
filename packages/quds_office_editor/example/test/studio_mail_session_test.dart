import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail.dart';
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
  Completer<mail.Mailbox>? selectGate;
  Completer<List<mail.MimeMessage>>? fetchGate;
  Completer<mail.MimeMessage>? contentsGate;
  Completer<void>? sendGate;
  Object? listError;
  Object? fetchError;
  bool failDisconnect = false;
  List<mail.Mailbox> boxes = <mail.Mailbox>[_box('Inbox'), _box('Archive')];
  List<mail.MimeMessage> messages = <mail.MimeMessage>[
    _message('First message'),
  ];
  int connects = 0;
  int lists = 0;
  int selections = 0;
  int fetches = 0;
  int contents = 0;
  int sends = 0;
  int disconnects = 0;

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
    if (listError case final error?) throw error;
    return boxes;
  }

  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async {
    selections++;
    return selectGate == null ? mailbox : await selectGate!.future;
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
    if (fetchError case final error?) throw error;
    return fetchGate == null ? messages : await fetchGate!.future;
  }

  @override
  Future<mail.MimeMessage> fetchMessageContents(
    mail.MimeMessage message, {
    int? maxSize,
    bool markAsSeen = false,
    List<mail.MediaToptype>? includedInlineTypes,
    Duration? responseTimeout,
  }) async {
    contents++;
    return contentsGate == null ? message : await contentsGate!.future;
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
    await sendGate?.future;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    if (failDisconnect) throw StateError('disconnect failed');
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _show(
  WidgetTester tester,
  mail.MailClient Function(mail.MailAccount) factory, {
  Future<mail.ClientConfig?> Function(String)? discover,
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
                discoverAccount: discover,
              ),
            ),
            child: const Text('Open session'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open session'));
  await tester.pumpAndSettle();
  await tester.enterText(
    _field(_strings.emailAddress),
    'reader@example.invalid',
  );
  await tester.enterText(_field(_strings.password), 'original-test-password');
}

Future<void> _manual(WidgetTester tester) async {
  await tester.tap(find.byType(SwitchListTile));
  await tester.pump();
  await tester.enterText(_field(_strings.imapHost), 'imap.example.invalid');
  await tester.enterText(_field(_strings.smtpHost), 'smtp.example.invalid');
}

Future<void> _connect(WidgetTester tester) async {
  await tester.tap(find.text(_strings.connect));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _connected(WidgetTester tester, _Client client) async {
  await _show(tester, (_) => client);
  await _manual(tester);
  await _connect(tester);
  await tester.pumpAndSettle();
  expect(find.text('First message'), findsOneWidget);
}

void _expectClosed(_Client client) {
  expect(client.incoming.aborts, greaterThan(0));
  expect(client.outgoing.aborts, greaterThan(0));
  expect(client.disconnects, greaterThan(0));
}

Future<void> _compose(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(_field(_strings.to), 'recipient@example.invalid');
  await tester.enterText(_field(_strings.subject), 'Session draft');
  await tester.enterText(_field(_strings.messageBody), 'Draft body.');
}

mail.ClientConfig _configuration() => mail.ClientConfig(
  emailProviders: <mail.ConfigEmailProvider>[
    mail.ConfigEmailProvider(
      incomingServers: const <mail.ServerConfig>[
        mail.ServerConfig(
          type: mail.ServerType.imap,
          hostname: 'imap.example.invalid',
          port: 993,
          socketType: mail.SocketType.ssl,
          authentication: mail.Authentication.plain,
          usernameType: mail.UsernameType.emailAddress,
        ),
      ],
      outgoingServers: const <mail.ServerConfig>[
        mail.ServerConfig(
          type: mail.ServerType.smtp,
          hostname: 'smtp.example.invalid',
          port: 465,
          socketType: mail.SocketType.ssl,
          authentication: mail.Authentication.plain,
          usernameType: mail.UsernameType.emailAddress,
        ),
      ],
    ),
  ],
);

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
    await tester.pumpAndSettle();
    _expectClosed(client);
    client.connectGate!.complete();
    await tester.pumpAndSettle();
    expect(client.lists, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late discovery cannot create a client after closing', (
    tester,
  ) async {
    final discovery = Completer<mail.ClientConfig?>();
    var clientsCreated = 0;
    await _show(tester, (_) {
      clientsCreated++;
      return _Client();
    }, discover: (_) => discovery.future);
    await _connect(tester);
    await tester.tap(find.byTooltip(_strings.close));
    await tester.pumpAndSettle();
    discovery.complete(_configuration());
    await tester.pumpAndSettle();
    expect(clientsCreated, 0);
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
    await tester.pumpAndSettle();
    final authentication =
        captured!.incoming.authentication as mail.PlainAuthentication;
    expect(authentication.password, 'original-test-password');
  });

  for (final stage in <String>['list', 'fetch', 'no selectable mailbox']) {
    testWidgets('setup $stage failure releases the pending client', (
      tester,
    ) async {
      final client = _Client();
      if (stage == 'list') client.listError = StateError('setup failed');
      if (stage == 'fetch') client.fetchError = StateError('setup failed');
      if (stage == 'no selectable mailbox')
        client.boxes = <mail.Mailbox>[_box('Archive', selectable: false)];
      await _show(tester, (_) => client);
      await _manual(tester);
      await _connect(tester);
      await tester.pumpAndSettle();
      _expectClosed(client);
      expect(find.text(_strings.connect), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disconnected mailbox selection cannot start a late fetch', (
    tester,
  ) async {
    final client = _Client();
    await _connected(tester, client);
    client.selectGate = Completer<mail.Mailbox>();
    await tester.tap(find.text('Archive'));
    await tester.pump();
    expect(client.selections, 1);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await tester.pumpAndSettle();
    client.selectGate!.complete(client.boxes.last);
    await tester.pumpAndSettle();
    expect(client.fetches, 1);
    _expectClosed(client);
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
        await tester.pumpAndSettle();
        oldClient.fetchGate = Completer<List<mail.MimeMessage>>();
        await tester.tap(find.text('Archive'));
        await tester.pump();
        expect(oldClient.fetches, 2);
        await tester.tap(find.byTooltip(_strings.disconnect));
        await tester.pumpAndSettle();
        await _connect(tester);
        await tester.pumpAndSettle();
        if (fail) {
          oldClient.fetchGate!.completeError(StateError('old mailbox failed'));
        } else {
          oldClient.fetchGate!.complete(<mail.MimeMessage>[
            _message('Stale message'),
          ]);
        }
        await tester.pumpAndSettle();
        expect(find.text('New session message'), findsOneWidget);
        expect(find.text('Stale message'), findsNothing);
        expect(find.textContaining('old mailbox failed'), findsNothing);
        expect(tester.takeException(), isNull);
        _expectClosed(oldClient);
      },
    );
  }

  testWidgets('old message contents cannot open in a reconnected session', (
    tester,
  ) async {
    final oldClient = _Client();
    final newClient = _Client()
      ..messages = <mail.MimeMessage>[_message('New session message')];
    var attempts = 0;
    await _show(tester, (_) => attempts++ == 0 ? oldClient : newClient);
    await _manual(tester);
    await _connect(tester);
    await tester.pumpAndSettle();
    oldClient.contentsGate = Completer<mail.MimeMessage>();
    await tester.tap(find.text('First message'));
    await tester.pump();
    await tester.tap(find.byTooltip(_strings.disconnect));
    await tester.pumpAndSettle();
    await _connect(tester);
    await tester.pumpAndSettle();
    oldClient.contentsGate!.complete(_message('Old full message'));
    await tester.pumpAndSettle();
    expect(find.byType(MailMessageView), findsNothing);
    expect(find.text('New session message'), findsOneWidget);
    _expectClosed(oldClient);
  });

  testWidgets('a draft from a disconnected session is not sent', (
    tester,
  ) async {
    final client = _Client();
    await _connected(tester, client);
    await _compose(tester);
    final disconnect = tester
        .widget<IconButton>(
          find.byTooltip(_strings.disconnect, skipOffstage: false),
        )
        .onPressed!;
    disconnect();
    await tester.pump();
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.send));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    oldClient.sendGate = Completer<void>();
    await _compose(tester);
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.send));
    await tester.pump(const Duration(seconds: 1));
    expect(oldClient.sends, 1);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await tester.pumpAndSettle();
    await _connect(tester);
    await tester.pumpAndSettle();
    oldClient.sendGate!.completeError(StateError('old send failed'));
    await tester.pumpAndSettle();
    expect(find.text('New session message'), findsOneWidget);
    expect(find.textContaining('old send failed'), findsNothing);
    _expectClosed(oldClient);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnect contains cleanup errors and aborts both transports', (
    tester,
  ) async {
    final client = _Client()..failDisconnect = true;
    client.incoming.failAbort = true;
    client.outgoing.failAbort = true;
    await _connected(tester, client);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await tester.pumpAndSettle();
    _expectClosed(client);
    expect(tester.takeException(), isNull);
    expect(find.text(_strings.connect), findsOneWidget);
  });

  testWidgets('search handles a message with an empty sender list', (
    tester,
  ) async {
    final message = _message('First message')..from = <mail.MailAddress>[];
    final client = _Client()..messages = <mail.MimeMessage>[message];
    await _connected(tester, client);
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == _strings.searchMail,
    );
    await tester.enterText(search, 'unknown sender');
    await tester.pumpAndSettle();
    expect(find.text(_strings.noMessages), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
