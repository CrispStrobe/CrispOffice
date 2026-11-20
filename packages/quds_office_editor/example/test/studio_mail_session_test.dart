import 'support/mail_credentials.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_attachment_picker.dart';
import 'support/mail_draft_store.dart';

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
  void Function()? onSend;
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
    onSend?.call();
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
  MemoryStudioMailDrafts? drafts,
  String email = 'reader@example.invalid',
}) async {
  final draftStorage = drafts ?? MemoryStudioMailDrafts();
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
                credentialStore: SessionMailCredentials(),
                draftStoreFactory: draftStorage.open,
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
  await tester.enterText(_field(_strings.emailAddress), email);
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
  MemoryStudioMailDrafts? drafts,
  String email = 'reader@example.invalid',
}) async {
  await _show(
    tester,
    (_) => client,
    loader: loader,
    drafts: drafts,
    email: email,
  );
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

String _composeBody(WidgetTester tester) => tester
    .widget<QudsWordEditor>(find.byType(QudsWordEditor))
    .controller
    .document
    .paragraphs
    .map((paragraph) => paragraph.text)
    .join('\n');

Future<void> _saveAndCloseCompose(WidgetTester tester) async {
  final close = find.text(_strings.mailDraftSaveClose);
  await tester.ensureVisible(close);
  await tester.tap(close);
  await _pump(tester);
  expect(find.byType(StudioMailComposeDialog), findsNothing);
}

Future<void> _autosave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await _pump(tester);
}

Future<void> _send(WidgetTester tester) async {
  final send = find.widgetWithIcon(FilledButton, Icons.send);
  await tester.ensureVisible(send);
  await tester.tap(send);
  await _pump(tester);
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
  testWidgets(
    'reopened native session restores raw unfinished draft with stable identity',
    (tester) async {
      final drafts = MemoryStudioMailDrafts();
      final first = _Client();
      await _connected(tester, first, drafts: drafts);
      await _compose(tester);
      await tester.enterText(_field(_strings.to), '  unfinished recipient @  ');
      await tester.enterText(
        _field(_strings.subject),
        '  Unfinished subject  ',
      );
      await tester.tap(find.text(_strings.mailCopyRecipients));
      await _pump(tester);
      await tester.enterText(
        _field(_strings.mailCc),
        ' copied@example.invalid; ',
      );
      await tester.enterText(_field(_strings.mailBcc), ' hidden @ ');
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller
          .insertText('\nSecond line – العربية');
      final expectedBody = _composeBody(tester);
      await _saveAndCloseCompose(tester);
      final key = drafts.identities.single.account.value;
      final saved = drafts.records[key]!;
      expect(saved.draft.to, '  unfinished recipient @  ');
      expect(saved.draft.cc, ' copied@example.invalid; ');
      expect(saved.draft.bcc, ' hidden @ ');
      expect(saved.draft.subject, '  Unfinished subject  ');
      expect(saved.draft.body, expectedBody);
      expect(saved.submissionUncertain, isFalse);
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      expect(drafts.closes, 1);
      final reopened = _Client();
      await _show(tester, (_) => reopened, drafts: drafts);
      await tester.enterText(_field(_strings.password), 'a-new-test-password');
      await _manual(tester);
      await _connect(tester);
      await _pump(tester);
      expect(drafts.identities.last.account.value, key);
      expect(find.text(_strings.mailDraftRestored), findsOneWidget);
      expect(reopened.sends, 0);
      await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
      await _pump(tester);
      expect(
        tester.widget<TextField>(_field(_strings.to)).controller!.text,
        saved.draft.to,
      );
      expect(
        tester.widget<TextField>(_field(_strings.mailCc)).controller!.text,
        saved.draft.cc,
      );
      expect(
        tester.widget<TextField>(_field(_strings.mailBcc)).controller!.text,
        saved.draft.bcc,
      );
      expect(
        tester.widget<TextField>(_field(_strings.subject)).controller!.text,
        saved.draft.subject,
      );
      expect(_composeBody(tester), expectedBody);
      expect(first.sends, 0);
      await _saveAndCloseCompose(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native draft storage isolates a different connected account', (
    tester,
  ) async {
    final drafts = MemoryStudioMailDrafts();
    final first = _Client();
    await _connected(tester, first, drafts: drafts);
    await _compose(tester);
    await _saveAndCloseCompose(tester);
    final firstKey = drafts.identities.single.account.value;
    await tester.tap(find.byTooltip(_strings.close));
    await _pump(tester);
    final second = _Client();
    await _connected(
      tester,
      second,
      drafts: drafts,
      email: 'other@example.invalid',
    );
    final secondKey = drafts.identities.last.account.value;
    expect(secondKey, isNot(firstKey));
    expect(find.text(_strings.mailDraftRestored), findsNothing);
    await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
    await _pump(tester);
    expect(
      tester.widget<TextField>(_field(_strings.to)).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<TextField>(_field(_strings.subject)).controller!.text,
      isEmpty,
    );
    expect(_composeBody(tester), isEmpty);
    await tester.enterText(_field(_strings.subject), 'Other account draft');
    await _saveAndCloseCompose(tester);
    expect(drafts.records, hasLength(2));
    expect(drafts.records[firstKey]!.draft.subject, 'Session draft');
    expect(drafts.records[secondKey]!.draft.subject, 'Other account draft');
    expect(first.sends + second.sends, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native send waits for durable uncertainty and restart never resends',
    (tester) async {
      final drafts = MemoryStudioMailDrafts();
      StudioMailStoredDraft? atSend;
      final first = _Client()
        ..sendGate = Completer<void>()
        ..onSend = () => atSend = drafts.records.values.single;
      await _connected(tester, first, drafts: drafts);
      await _compose(tester);
      await _autosave(tester);
      expect(drafts.records.values.single.submissionUncertain, isFalse);
      final saveGate = Completer<void>();
      drafts.saveGate = saveGate;
      await _send(tester);
      expect(first.sends, 0);
      expect(atSend, isNull);
      expect(drafts.records.values.single.submissionUncertain, isFalse);
      saveGate.complete();
      await _pump(tester);
      expect(first.sends, 1);
      expect(atSend, isNotNull);
      expect(atSend!.submissionUncertain, isTrue);
      expect(atSend!.draft.to, 'recipient@example.invalid');
      expect(atSend!.draft.body, 'Draft body.');
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      final reopened = _Client();
      await _connected(tester, reopened, drafts: drafts);
      // The delivery warning takes precedence over the ordinary restore notice.
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(reopened.sends, 0);
      first.sendGate!.completeError(StateError('late transport failure'));
      await _pump(tester);
      expect(find.textContaining('late transport failure'), findsNothing);
      await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
      await _pump(tester);
      expect(_composeBody(tester), 'Draft body.');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithIcon(FilledButton, Icons.send))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(first.sends, 1);
      expect(reopened.sends, 0);
      await _saveAndCloseCompose(tester);
      expect(drafts.records.values.single.submissionUncertain, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disconnect during durable send checkpoint cannot submit or auto-retry',
    (tester) async {
      final drafts = MemoryStudioMailDrafts();
      final first = _Client();
      await _connected(tester, first, drafts: drafts);
      await _compose(tester);
      await _autosave(tester);
      final saveGate = Completer<void>();
      drafts.saveGate = saveGate;
      await _send(tester);
      expect(first.sends, 0);
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      saveGate.complete();
      await _pump(tester);
      expect(first.sends, 0);
      _expectClosed(first);
      final reopened = _Client();
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      await _connected(tester, reopened, drafts: drafts);
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(reopened.sends, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native storage open failure prevents composition and submission',
    (tester) async {
      final drafts = MemoryStudioMailDrafts()..failOpen = true;
      final client = _Client();
      await _connected(tester, client, drafts: drafts);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
      await _pump(tester);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      expect(drafts.records, isEmpty);
      expect(client.sends, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final bool preSubmission in [false, true]) {
    testWidgets(
      'native ${preSubmission ? 'submission checkpoint' : 'composer save'} failure cannot send',
      (tester) async {
        final drafts = MemoryStudioMailDrafts();
        final client = _Client();
        await _connected(tester, client, drafts: drafts);
        await _compose(tester);
        if (preSubmission) await _autosave(tester);
        drafts.failSave = true;
        await _send(tester);
        expect(client.sends, 0);
        if (preSubmission) {
          expect(find.byType(StudioMailComposeDialog), findsNothing);
          expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
          expect(drafts.records.values.single.submissionUncertain, isFalse);
          expect(drafts.records.values.single.draft.body, 'Draft body.');
        } else {
          expect(find.byType(StudioMailComposeDialog), findsOneWidget);
          expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
          expect(_composeBody(tester), 'Draft body.');
          drafts.failSave = false;
          await _saveAndCloseCompose(tester);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'native acceptance clears the durable draft before another session',
    (tester) async {
      final drafts = MemoryStudioMailDrafts();
      final first = _Client()..sendGate = Completer<void>();
      await _connected(tester, first, drafts: drafts);
      await _compose(tester);
      await _send(tester);
      expect(first.sends, 1);
      expect(drafts.records.values.single.submissionUncertain, isTrue);
      first.sendGate!.complete();
      await _pump(tester);
      expect(drafts.clears, 1);
      expect(drafts.records, isEmpty);
      expect(find.text(_strings.mailSubmissionAccepted), findsOneWidget);
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      final reopened = _Client();
      await _connected(tester, reopened, drafts: drafts);
      expect(find.text(_strings.mailDraftRestored), findsNothing);
      expect(find.text(_strings.mailSubmissionUncertain), findsNothing);
      expect(reopened.sends, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native accepted cleanup failure retains uncertain draft and do-not-resend notice',
    (tester) async {
      final drafts = MemoryStudioMailDrafts()..failClear = true;
      final first = _Client();
      await _connected(tester, first, drafts: drafts);
      await _compose(tester);
      await _send(tester);
      expect(first.sends, 1);
      expect(
        find.text(_strings.mailDraftAcceptedCleanupFailed),
        findsOneWidget,
      );
      expect(drafts.records.values.single.submissionUncertain, isTrue);
      expect(drafts.records.values.single.draft.body, 'Draft body.');
      expect(drafts.clears, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(first.sends, 1);
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      final reopened = _Client();
      await _connected(tester, reopened, drafts: drafts);
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      expect(reopened.sends, 0);
      await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
      await _pump(tester);
      expect(_composeBody(tester), 'Draft body.');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithIcon(FilledButton, Icons.send))
            .onPressed,
        isNull,
      );
      await _saveAndCloseCompose(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a delayed native draft open cannot install the previous account store',
    (tester) async {
      final openGate = Completer<void>();
      final drafts = MemoryStudioMailDrafts()..openGate = openGate;
      final first = _Client();
      final second = _Client()..messages = [_message('Second account message')];
      var attempts = 0;
      await _show(
        tester,
        (_) => attempts++ == 0 ? first : second,
        drafts: drafts,
      );
      await _manual(tester);
      await _connect(tester);
      await _pump(tester);
      final oldKey = drafts.identities.single.account.value;
      drafts.records[oldKey] = const StudioMailStoredDraft(
        draft: StudioMailDraft(
          to: 'old@example.invalid',
          subject: 'Old account draft',
          body: 'Old account body',
        ),
        submissionUncertain: true,
      );
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      drafts.openGate = null;
      await tester.enterText(
        _field(_strings.emailAddress),
        'other@example.invalid',
      );
      await tester.enterText(_field(_strings.password), 'other-test-password');
      await _connect(tester);
      await _pump(tester);
      expect(find.text('Second account message'), findsOneWidget);
      await _compose(tester);
      await tester.enterText(_field(_strings.subject), 'Current account draft');
      await _saveAndCloseCompose(tester);
      final newKey = drafts.identities.last.account.value;
      expect(newKey, isNot(oldKey));
      expect(drafts.records[newKey]!.draft.subject, 'Current account draft');
      openGate.complete();
      await _pump(tester);
      expect(drafts.closes, 1);
      expect(find.text('Second account message'), findsOneWidget);
      expect(find.text(_strings.mailSubmissionUncertain), findsNothing);
      await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
      await _pump(tester);
      expect(
        tester.widget<TextField>(_field(_strings.subject)).controller!.text,
        'Current account draft',
      );
      expect(_composeBody(tester), 'Draft body.');
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(first.sends + second.sends, 0);
      await _saveAndCloseCompose(tester);
      expect(drafts.records[oldKey]!.draft.body, 'Old account body');
      expect(tester.takeException(), isNull);
    },
  );

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
    'native attachment snapshots survive an uncertain send and acknowledged retry',
    (tester) async {
      final source = Uint8List.fromList([0, 255, 128, 13, 10, 42]);
      final expected = Uint8List.fromList(source);
      final picker = MailAttachmentPickerFixture(
        () async => FilePickerResult([
          PlatformFile(
            name: 'Snapshot.xlsx',
            size: source.length,
            readStream: Stream<List<int>>.value(source),
          ),
          PlatformFile(name: 'Empty.txt', size: 0, bytes: Uint8List(0)),
        ]),
      );
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = FilePickerIO());
      final client = _Client()..sendGate = Completer<void>();
      await _connected(tester, client);
      await _compose(tester);
      await tester.tap(find.text(_strings.mailCopyRecipients));
      await _pump(tester);
      await tester.enterText(
        _field(_strings.mailBcc),
        'hidden@example.invalid',
      );
      final add = find.byKey(const ValueKey('studio-mail-add-attachments'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await _pump(tester);
      expect(find.text('Snapshot.xlsx'), findsOneWidget);
      expect(find.text('Empty.txt'), findsOneWidget);
      source.fillRange(0, source.length, 17);

      final send = find.widgetWithIcon(FilledButton, Icons.send);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(client.sends, 1);
      client.sendGate!.completeError(StateError('connection lost after DATA'));
      await _pump(tester);
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(client.sends, 1);

      await tester.tap(find.widgetWithIcon(TextButton, Icons.edit_outlined));
      await _pump(tester);
      expect(find.text('Snapshot.xlsx'), findsOneWidget);
      expect(find.text('Empty.txt'), findsOneWidget);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(picker.calls, 1);
      client.sendGate = null;
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await _pump(tester);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(client.sends, 2);
      expect(client.sentAppendToSent, everyElement(isFalse));
      for (final recipients in client.sentRecipients) {
        expect(recipients, [
          'recipient@example.invalid',
          'hidden@example.invalid',
        ]);
      }
      for (final message in client.sentMessages) {
        expect(message.mediaType.text, 'multipart/mixed');
        expect(message.parts!.first.mediaType.text, 'multipart/alternative');
        final wire = message.renderMessage();
        expect(wire, isNot(contains('hidden@example.invalid')));
        final decoded = const QudsMimeCodec().parse(ascii.encode(wire));
        expect(decoded.status, MailParseStatus.complete);
        expect(decoded.message!.body.plainText, 'Draft body.');
        expect(decoded.message!.body.html, contains('Draft body.'));
        expect(decoded.message!.attachments, hasLength(2));
        expect(decoded.message!.attachments.first.displayName, 'Snapshot.xlsx');
        expect(decoded.message!.attachments.first.content.bytes, expected);
        expect(decoded.message!.attachments.last.displayName, 'Empty.txt');
        expect(decoded.message!.attachments.last.content.bytes, isEmpty);
        expect(decoded.message!.envelope.bcc, isEmpty);
      }
      expect(find.text(_strings.mailSubmissionAccepted), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
