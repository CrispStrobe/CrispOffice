import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_bulk_status.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);

mail.MimeMessage _header(
  int uid,
  String subject, {
  bool read = false,
  bool flagged = false,
  DateTime? date,
  List<mail.MailAddress> to = const [],
  List<mail.MailAddress> cc = const [],
}) => mail.MimeMessage.fromEnvelope(
  mail.Envelope(
    subject: subject,
    from: [mail.MailAddress('Writer', 'writer@example.test')],
    to: to,
    cc: cc,
    bcc: [mail.MailAddress('Hidden', 'hidden@example.test')],
    date: date,
  ),
  uid: uid,
  flags: [
    if (read) mail.MessageFlags.seen,
    if (flagged) mail.MessageFlags.flagged,
  ],
);

final class _Incoming extends mail.ImapClient {
  @override
  Future<void> abort() async {}
}

final class _Outgoing extends mail.SmtpClient {
  _Outgoing() : super('fixture.test');
  @override
  Future<void> abort() async {}
}

final class _Client extends Fake implements mail.MailClient {
  final boxes = [
    mail.Mailbox(
      encodedName: 'Inbox',
      encodedPath: 'Inbox',
      pathSeparator: '/',
      flags: [mail.MailboxFlag.inbox],
    )..uidValidity = 91,
    mail.Mailbox(
      encodedName: 'Archive',
      encodedPath: 'Archive',
      pathSeparator: '/',
      flags: [],
    )..uidValidity = 92,
  ];
  final _incoming = _Incoming();
  final _outgoing = _Outgoing();
  mail.Mailbox? _selected;
  int legacyFetches = 0;

  @override
  mail.Mailbox? get selectedMailbox => _selected;
  @override
  mail.ImapClient get lowLevelIncomingMailClient => _incoming;
  @override
  mail.SmtpClient get lowLevelOutgoingMailClient => _outgoing;
  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => boxes;
  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async {
    _selected = mailbox;
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
    legacyFetches++;
    throw StateError('The bounded browser must own the header list.');
  }
}

class _Browser
    implements
        StudioMailMessageLoader,
        StudioMailMailboxBrowser,
        StudioMailMessageActions {
  final account = MailAccountId(
    'fixture',
    profile: MailProfileId('fixture', hostId: 'tests'),
  );
  final requests = <(String, MailCursor?, int)>[];
  final changes = <(String, int?, bool)>[];
  int reads = 0;
  int disposals = 0;
  int cancellations = 0;
  Future<void> Function(int)? mutationHandler;
  Completer<void>? mutationGate;
  bool failMutation = false;
  Future<StudioMailHeaderPage> Function(mail.Mailbox, MailCursor?, int)? pages;

  MailCursor cursor(String token, [String folder = 'Inbox']) => MailCursor(
    mailbox: MailMailboxId(folder, account: account),
    value: token,
  );

  @override
  Future<StudioMailHeaderPage> fetchHeaders(
    mail.Mailbox mailbox, {
    MailCursor? cursor,
    int limit = 50,
  }) async {
    requests.add((mailbox.path, cursor, limit));
    if (pages case final handler?) return handler(mailbox, cursor, limit);
    if (mailbox.path == 'Archive') {
      return StudioMailHeaderPage(messages: [_header(50, 'Archived message')]);
    }
    return cursor == null
        ? StudioMailHeaderPage(
            messages: [
              _header(300, 'Newest message'),
              _header(200, 'Read message', read: true),
            ],
            next: this.cursor('next-page'),
          )
        : StudioMailHeaderPage(
            messages: [_header(100, 'Older flagged message', flagged: true)],
          );
  }

  @override
  Future<Uint8List> fetch(mail.Mailbox mailbox, mail.MimeMessage header) async {
    reads++;
    return Uint8List.fromList(
      utf8.encode(
        'From: Writer <writer@example.test>\r\nSubject: ${header.decodeSubject()}\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n\r\nBody for UID ${header.uid}.\r\n',
      ),
    );
  }

  @override
  Future<void> markRead(mail.Mailbox mailbox, mail.MimeMessage header) =>
      setRead(mailbox, header, read: true);
  @override
  Future<void> setRead(
    mail.Mailbox mailbox,
    mail.MimeMessage header, {
    required bool read,
  }) async {
    changes.add(('read', header.uid, read));
    await mutationHandler?.call(changes.length);
    await mutationGate?.future;
    if (failMutation) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.providerFailure,
      );
    }
  }

  @override
  Future<void> setFlagged(
    mail.Mailbox mailbox,
    mail.MimeMessage header, {
    required bool flagged,
  }) async {
    changes.add(('flagged', header.uid, flagged));
    await mutationHandler?.call(changes.length);
    await mutationGate?.future;
    if (failMutation) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.providerFailure,
      );
    }
  }

  @override
  void cancel() {
    cancellations++;
  }

  @override
  void dispose() {
    disposals++;
  }
}

final class _ImageBrowser extends _Browser {
  @override
  Future<Uint8List> fetch(mail.Mailbox mailbox, mail.MimeMessage header) async {
    reads++;
    return Uint8List.fromList(
      utf8.encode(
        'From: Writer <writer@example.test>\r\nSubject: ${header.decodeSubject()}\r\n'
        'Content-Type: text/html; charset=utf-8\r\n\r\n'
        '<p>Message ${header.uid}</p><img src="https://images.example.test/one.png" alt="Remote">',
      ),
    );
  }
}

final class _ImageClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  Completer<http.StreamedResponse>? pending;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return pending?.future ?? response();
  }

  http.StreamedResponse response() => http.StreamedResponse(
    Stream.value(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwaDjwHwAExAJwNooHGQAAAABJRU5ErkJggg==',
      ),
    ),
    200,
    headers: {'content-type': 'image/png'},
  );

  @override
  void close() => closed = true;
}

final class _BulkBrowser extends _Browser implements StudioMailMailboxRecords {
  final _observed = Map<mail.MimeMessage, MailHeaderRecord>.identity();
  mail.Mailbox? lastObservedMailbox;
  mail.Mailbox? lastMutationMailbox;
  MailAccountId? reportedAccount;

  @override
  MailAccountId get account => reportedAccount ?? super.account;

  @override
  Future<void> setRead(
    mail.Mailbox mailbox,
    mail.MimeMessage header, {
    required bool read,
  }) {
    lastMutationMailbox = mailbox;
    return super.setRead(mailbox, header, read: read);
  }

  @override
  Future<void> setFlagged(
    mail.Mailbox mailbox,
    mail.MimeMessage header, {
    required bool flagged,
  }) {
    lastMutationMailbox = mailbox;
    return super.setFlagged(mailbox, header, flagged: flagged);
  }

  @override
  Future<StudioMailHeaderPage> fetchHeaders(
    mail.Mailbox mailbox, {
    MailCursor? cursor,
    int limit = 50,
  }) async {
    final page = await super.fetchHeaders(
      mailbox,
      cursor: cursor,
      limit: limit,
    );
    lastObservedMailbox = mailbox;
    for (final message in page.messages) {
      _observed[message] = MailHeaderRecord(
        id: MailMessageId(
          '${mailbox.path}:${mailbox.uidValidity}:${message.uid}',
        ),
        remote: MailImapIdentity(
          mailbox: MailMailboxId(mailbox.path, account: account),
          uidValidity: mailbox.uidValidity!,
          uid: message.uid!,
        ),
        envelope: MailEnvelope(subject: message.decodeSubject() ?? ''),
        flags: message.flags == null
            ? null
            : MailMessageFlags(
                isRead: message.isSeen,
                isFlagged: message.isFlagged,
                isAnswered: message.isAnswered,
                isDraft: message.hasFlag(mail.MessageFlags.draft),
                isDeleted: message.isDeleted,
              ),
      );
    }
    return page;
  }

  @override
  MailHeaderRecord observedHeader(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) => _observed[header]!;

  @override
  Future<MailMessage> fetchMessage(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) async {
    final record = observedHeader(mailbox, header);
    return MailMessage(
      raw: MailBytes(await fetch(mailbox, header)),
      envelope: record.envelope,
      localId: record.id,
      remoteIdentity: record.remote,
    );
  }
}

MailMessageList _bulkList(WidgetTester tester) =>
    tester.widget<MailMessageList>(find.byType(MailMessageList));

List<mail.MimeMessage> _bulkHeaders() => [
  _header(300, 'First bulk message'),
  _header(200, 'Second bulk message'),
  _header(100, 'Third bulk message'),
];

final class _SessionCredentials extends Fake
    implements StudioMailCredentialStore {
  @override
  Future<StudioMailCredentials?> load() async => null;
  @override
  Future<bool> save(StudioMailCredentials credentials) async => true;
  @override
  Future<bool> clear() async => true;
}

Finder _key(String name) => find.byKey(ValueKey(name));
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Finder _button(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<_Client> _show(
  WidgetTester tester,
  _Browser browser, {
  bool compact = false,
  _Browser? reconnectBrowser,
  http.Client Function()? remoteImageClientFactory,
}) async {
  final client = _Client();
  var connections = 0;
  final drafts = MemoryStudioMailDrafts();
  tester.view
    ..physicalSize = compact ? const Size(600, 1000) : const Size(1300, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: _SessionCredentials(),
        clientFactory: (_) => client,
        messageLoaderFactory: (_) =>
            connections++ == 0 ? browser : reconnectBrowser ?? browser,
        draftStoreFactory: drafts.open,
        remoteImageClientFactory: remoteImageClientFactory,
      ),
    ),
  );
  await _pump(tester);
  await tester.enterText(_field(_strings.emailAddress), 'reader@example.test');
  await tester.enterText(_field(_strings.password), 'fixture-password');
  await tester.tap(find.widgetWithText(SwitchListTile, _strings.manualServers));
  await tester.pump();
  await tester.enterText(_field(_strings.imapHost), 'imap.example.test');
  await tester.enterText(_field(_strings.smtpHost), 'smtp.example.test');
  await tester.ensureVisible(find.text(_strings.connect));
  await tester.tap(find.text(_strings.connect));
  await _pump(tester);
  return client;
}

// The reconciled status exposes each outcome independently for accessibility.
void _expectBulkCounts(
  WidgetTester tester,
  int confirmed,
  int failed,
  int uncertain,
  int unattempted,
) {
  final status = _bulkList(tester).bulkStatus! as StudioMailBulkStatus;
  expect(status.report.confirmedCount, confirmed);
  expect(status.report.failedCount, failed);
  expect(status.report.uncertainCount, uncertain);
  expect(status.report.unattemptedCount, unattempted);
  expect(find.text('Confirmed: $confirmed'), findsOneWidget);
  expect(find.text('Failed: $failed'), findsOneWidget);
  expect(find.text('Uncertain: $uncertain'), findsOneWidget);
  expect(find.text('Not attempted: $unattempted'), findsOneWidget);
}

void main() {
  _peerBulkWorkspaceTests();
  testWidgets(
    'remote images require the explicit action and resume keeps the reader',
    (tester) async {
      final browser = _ImageBrowser();
      final images = _ImageClient();
      await _show(tester, browser, remoteImageClientFactory: () => images);
      _mailList(tester).onOpen(_mailList(tester).items.first.id);
      await _pump(tester);
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      expect(reader.presentation.images, isEmpty);
      expect(images.requests, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pump(tester);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(reader),
      );
      expect(browser.reads, 1);
      expect(browser.requests, hasLength(1));
      await tester.tap(_key('studio-mail-show-images'));
      await _pump(tester);
      expect(images.requests, hasLength(1));
      expect(images.closed, isTrue);
      expect(reader.presentation.images, hasLength(1));
      expect(
        reader.decodedText,
        isNot(contains('[External image blocked: Remote]')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing mailbox closes remote image work and ignores its late response',
    (tester) async {
      final browser = _ImageBrowser();
      final images = _ImageClient()
        ..pending = Completer<http.StreamedResponse>();
      await _show(tester, browser, remoteImageClientFactory: () => images);
      _mailList(tester).onOpen(_mailList(tester).items.first.id);
      await _pump(tester);
      await tester.tap(_key('studio-mail-show-images'));
      await tester.pump();
      expect(images.requests, hasLength(1));
      await tester.tap(find.widgetWithText(ListTile, 'Archive'));
      await _pump(tester);
      expect(images.closed, isTrue);
      _mailList(tester).onOpen(_mailList(tester).items.first.id);
      await _pump(tester);
      final current = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      var bodyCancelled = false;
      // An explicit test-zone cancellation future lets fake async observe the
      // stale response's cleanup, unlike Stream.value's root-zone future.
      final lateBody = StreamController<List<int>>(
        onCancel: () async {
          bodyCancelled = true;
        },
      );
      images.pending!.complete(
        http.StreamedResponse(
          lateBody.stream,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await _pump(tester);
      expect(bodyCancelled, isTrue);
      expect(current.presentation.images, isEmpty);
      expect(current.decodedText, contains('Message 50'));
      expect(current.decodedText, contains('[External image blocked: Remote]'));
      expect(images.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('IMAP bulk commands require immutable record capability', (
    tester,
  ) async {
    final browser = _Browser();
    await _show(tester, browser);
    expect(_bulkList(tester).onBulkAction, isNull);
    expect(browser.changes, isEmpty);
    expect(browser.reads, 0);
  });

  testWidgets(
    'IMAP bulk commands target checked identities and preserve the open message',
    (tester) async {
      final headers = _bulkHeaders();
      final browser = _BulkBrowser()
        ..pages = (mailbox, cursor, limit) async =>
            StudioMailHeaderPage(messages: headers);
      await _show(tester, browser);
      _bulkList(tester).onOpen('imap-message-91:300');
      await _pump(tester);
      expect(browser.reads, 1);
      final selection = ['imap-message-91:200', 'imap-message-91:100'];
      _bulkList(tester).onBulkAction!(MailBulkFlagAction.flag, selection);
      selection.clear();
      await _pump(tester);
      expect(browser.changes, [('flagged', 200, true), ('flagged', 100, true)]);
      expect(_bulkList(tester).selectedId, 'imap-message-91:300');
      expect(_bulkList(tester).items.map((item) => item.isFlagged), [
        false,
        true,
        true,
      ]);
      expect(browser.reads, 1);
      expect(browser.requests, hasLength(1));
      _expectBulkCounts(tester, 2, 0, 0, 0);
    },
  );

  testWidgets('IMAP bulk confirmations preserve unknown and unrelated flags', (
    tester,
  ) async {
    final unknown = _header(300, 'Unknown')..flags = null;
    final known = _header(200, 'Known', read: true)
      ..setFlag(mail.MessageFlags.answered, true)
      ..setFlag(mail.MessageFlags.draft, true)
      ..setFlag(mail.MessageFlags.deleted, true);
    final browser = _BulkBrowser()
      ..pages = (mailbox, cursor, limit) async =>
          StudioMailHeaderPage(messages: [unknown, known]);
    await _show(tester, browser);
    _bulkList(tester).onBulkAction!(MailBulkFlagAction.flag, [
      'imap-message-91:300',
      'imap-message-91:200',
    ]);
    await _pump(tester);
    expect(_bulkList(tester).items.map((item) => item.isRead), [null, true]);
    expect(_bulkList(tester).items.map((item) => item.isFlagged), [true, true]);
    expect(known.isAnswered, isTrue);
    expect(known.hasFlag(mail.MessageFlags.draft), isTrue);
    expect(known.isDeleted, isTrue);
    _bulkList(tester).onBulkAction!(MailBulkFlagAction.markUnread, [
      'imap-message-91:200',
    ]);
    await _pump(tester);
    _bulkList(tester).onBulkAction!(MailBulkFlagAction.unflag, [
      'imap-message-91:300',
    ]);
    await _pump(tester);
    expect(_bulkList(tester).items.map((item) => item.isRead), [null, false]);
    expect(_bulkList(tester).items.map((item) => item.isFlagged), [
      false,
      true,
    ]);
    expect(browser.reads, 0);
  });

  testWidgets(
    'IMAP bulk stops on uncertain confirmation and requires explicit refresh',
    (tester) async {
      final headers = _bulkHeaders();
      final browser = _BulkBrowser()
        ..mutationHandler = (index) async {
          if (index == 2) throw StateError('private-server-text');
        }
        ..pages = (mailbox, cursor, limit) async =>
            StudioMailHeaderPage(messages: headers);
      await _show(tester, browser);
      _bulkList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
        'imap-message-91:300',
        'imap-message-91:200',
        'imap-message-91:100',
      ]);
      await _pump(tester);
      expect(browser.changes, [('read', 300, true), ('read', 200, true)]);
      expect(_bulkList(tester).items.map((item) => item.isRead), [
        true,
        false,
        false,
      ]);
      expect(_bulkList(tester).bulkEnabled, isFalse);
      _expectBulkCounts(tester, 1, 0, 1, 1);
      expect(
        find.textContaining(_strings.mailWorkspaceRefreshRequired),
        findsOneWidget,
      );
      expect(find.textContaining('private-server-text'), findsNothing);
      _bulkList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
        'imap-message-91:100',
      ]);
      await _pump(tester);
      expect(browser.changes, hasLength(2));
      expect(browser.requests, hasLength(1));
      expect(browser.reads, 0);
      await tester.tap(_button(_strings.refresh));
      await _pump(tester);
      expect(_bulkList(tester).bulkEnabled, isTrue);
      expect(browser.requests, hasLength(2));
    },
  );

  for (final problem in [
    MailProblemCode.permissionDenied,
    MailProblemCode.cancelled,
    MailProblemCode.staleOperation,
  ]) {
    testWidgets(
      'IMAP bulk distinguishes explicit no-mutation $problem evidence',
      (tester) async {
        final stops = problem != MailProblemCode.permissionDenied;
        final refreshRequired = problem == MailProblemCode.staleOperation;
        final browser = _BulkBrowser()
          ..mutationHandler = (index) async {
            if (index == 1) {
              throw StudioMailMessageLoadException(
                problem,
                mutationMayHaveOccurred: false,
              );
            }
          }
          ..pages = (mailbox, cursor, limit) async =>
              StudioMailHeaderPage(messages: _bulkHeaders());
        await _show(tester, browser);
        _bulkList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
          'imap-message-91:300',
          'imap-message-91:200',
          'imap-message-91:100',
        ]);
        await _pump(tester);
        expect(browser.changes, hasLength(stops ? 1 : 3));
        expect(_bulkList(tester).items.map((item) => item.isRead), [
          false,
          !stops,
          !stops,
        ]);
        expect(_bulkList(tester).bulkActionsEnabled, !refreshRequired);
        expect(
          find.text(
            stops
                ? '0 confirmed · 1 failed · 0 uncertain · 2 not attempted'
                : '2 confirmed · 1 failed · 0 uncertain · 0 not attempted',
          ),
          findsOneWidget,
        );
        expect(
          find.text(_strings.mailWorkspaceRefreshRequired),
          refreshRequired ? findsOneWidget : findsNothing,
        );
        expect(browser.reads, 0);
        expect(browser.requests, hasLength(1));
        expect(_bulkList(tester).busy, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mayHaveOccurred in <bool?>[null, true]) {
    testWidgets(
      'IMAP typed failure with mutation certainty $mayHaveOccurred remains uncertain',
      (tester) async {
        final browser = _BulkBrowser()
          ..mutationHandler = (_) async {
            throw StudioMailMessageLoadException(
              MailProblemCode.permissionDenied,
              mutationMayHaveOccurred: mayHaveOccurred,
            );
          }
          ..pages = (mailbox, cursor, limit) async =>
              StudioMailHeaderPage(messages: _bulkHeaders());
        await _show(tester, browser);
        _bulkList(tester).onBulkAction!(MailBulkFlagAction.flag, [
          'imap-message-91:300',
          'imap-message-91:200',
          'imap-message-91:100',
        ]);
        await _pump(tester);
        expect(browser.changes, hasLength(1));
        expect(
          _bulkList(tester).items.every((item) => !item.isFlagged!),
          isTrue,
        );
        expect(_bulkList(tester).bulkActionsEnabled, isFalse);
        expect(
          find.text('0 confirmed · 0 failed · 1 uncertain · 2 not attempted'),
          findsOneWidget,
        );
        expect(
          find.text(_strings.mailWorkspaceRefreshRequired),
          findsOneWidget,
        );
        expect(browser.reads, 0);
        expect(browser.requests, hasLength(1));
      },
    );
  }

  testWidgets(
    'IMAP bulk cancellation waits for the in-flight confirmation without cancelling transport',
    (tester) async {
      final gate = Completer<void>();
      final browser = _BulkBrowser()
        ..mutationGate = gate
        ..pages = (mailbox, cursor, limit) async =>
            StudioMailHeaderPage(messages: _bulkHeaders());
      await _show(tester, browser);
      _bulkList(tester).onBulkAction!(MailBulkFlagAction.flag, [
        'imap-message-91:300',
        'imap-message-91:200',
        'imap-message-91:100',
      ]);
      await _pump(tester);
      expect(browser.changes, hasLength(1));
      (_bulkList(tester).bulkStatus! as StudioMailBulkStatus).onStop!();
      await _pump(tester);
      expect(_bulkList(tester).busy, isTrue);
      expect(browser.cancellations, 0);
      gate.complete();
      await _pump(tester);
      expect(browser.changes, hasLength(1));
      expect(_bulkList(tester).items.map((item) => item.isFlagged), [
        true,
        false,
        false,
      ]);
      expect(_bulkList(tester).bulkEnabled, isTrue);
      expect(
        (_bulkList(tester).bulkStatus! as StudioMailBulkStatus).onStop,
        isNull,
      );
      _expectBulkCounts(tester, 1, 0, 0, 2);
    },
  );

  for (final changed in ['uid', 'uidValidity', 'recordId']) {
    testWidgets(
      'IMAP bulk rejects a mutated $changed before the next dispatch and publication',
      (tester) async {
        final headers = _bulkHeaders();
        final gate = Completer<void>();
        final browser = _BulkBrowser()
          ..mutationGate = gate
          ..pages = (mailbox, cursor, limit) async =>
              StudioMailHeaderPage(messages: headers);
        await _show(tester, browser);
        _bulkList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
          'imap-message-91:300',
          'imap-message-91:200',
        ]);
        await _pump(tester);
        if (changed == 'uid') {
          headers[1].uid = 999;
        } else if (changed == 'uidValidity') {
          browser.lastObservedMailbox!.uidValidity = 999;
        } else {
          final observed = browser._observed[headers[1]]!;
          browser._observed[headers[1]] = MailHeaderRecord(
            id: MailMessageId('replacement-observation'),
            remote: observed.remote,
            envelope: observed.envelope,
            flags: observed.flags,
          );
        }
        expect(
          browser.lastMutationMailbox,
          isNot(same(browser.lastObservedMailbox)),
        );
        expect(browser.lastMutationMailbox!.uidValidity, 91);
        gate.complete();
        await _pump(tester);
        expect(browser.changes, [('read', 300, true)]);
        expect(
          _bulkList(tester).items.every((item) => item.isRead == false),
          isTrue,
        );
        expect(_bulkList(tester).bulkEnabled, isFalse);
        expect(_bulkList(tester).busy, isFalse);
        expect(
          find.textContaining(_strings.mailWorkspaceRefreshRequired),
          findsOneWidget,
        );
        expect(browser.reads, 0);
      },
    );
  }

  testWidgets('IMAP legacy records cannot substitute another account', (
    tester,
  ) async {
    final browser = _BulkBrowser();
    await _show(tester, browser);
    final header = browser._observed.keys.first;
    final record = browser._observed[header]!;
    final remote = record.remote as MailImapIdentity;
    browser._observed[header] = MailHeaderRecord(
      id: record.id,
      remote: MailImapIdentity(
        mailbox: MailMailboxId(
          remote.mailbox.value,
          account: MailAccountId(
            'other-account',
            profile: browser.account.profile,
          ),
        ),
        uidValidity: remote.uidValidity,
        uid: remote.uid,
      ),
      envelope: record.envelope,
      flags: record.flags,
    );
    _bulkList(tester).onBulkAction!(MailBulkFlagAction.flag, [
      'imap-message-91:300',
    ]);
    await _pump(tester);
    expect(browser.changes, isEmpty);
    expect(_bulkList(tester).bulkEnabled, isFalse);
    expect(_bulkList(tester).busy, isFalse);
    expect(browser.reads, 0);
  });

  testWidgets('IMAP legacy account retirement stops an acknowledged batch', (
    tester,
  ) async {
    final gate = Completer<void>();
    final browser = _BulkBrowser()
      ..mutationGate = gate
      ..pages = (mailbox, cursor, limit) async =>
          StudioMailHeaderPage(messages: _bulkHeaders());
    await _show(tester, browser);
    _bulkList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
      'imap-message-91:300',
      'imap-message-91:200',
    ]);
    await _pump(tester);
    browser.reportedAccount = MailAccountId(
      'replacement-account',
      profile: browser.account.profile,
    );
    gate.complete();
    await _pump(tester);
    expect(browser.changes, [('read', 300, true)]);
    expect(
      _bulkList(tester).items.every((item) => item.isRead == false),
      isTrue,
    );
    final report =
        (_bulkList(tester).bulkStatus! as StudioMailBulkStatus).report;
    expect(report.confirmedCount, 1);
    expect(report.unattemptedCount, 1);
    expect(_bulkList(tester).bulkEnabled, isFalse);
    expect(_bulkList(tester).busy, isFalse);
  });

  testWidgets(
    'IMAP stale bulk callback cannot mutate a later visit to the same folder',
    (tester) async {
      final browser = _BulkBrowser();
      await _show(tester, browser);
      final stale = _bulkList(tester).onBulkAction!;
      await tester.tap(find.widgetWithText(ListTile, 'Archive'));
      await _pump(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Inbox'));
      await _pump(tester);
      stale(MailBulkFlagAction.flag, ['imap-message-91:300']);
      await _pump(tester);
      expect(browser.changes, isEmpty);
      expect(_bulkList(tester).items.first.isFlagged, isFalse);
      expect(browser.reads, 0);
    },
  );

  testWidgets(
    'IMAP refresh retains discovery but rejects the old bulk selection scope',
    (tester) async {
      final browser = _BulkBrowser();
      await _show(tester, browser);
      await tester.enterText(_key('mail-list-search'), 'message');
      await _pump(tester);
      final old = _bulkList(tester);
      await tester.tap(_button(_strings.refresh));
      await _pump(tester);
      final refreshed = _bulkList(tester);
      expect(refreshed.scopeId, old.scopeId);
      expect(refreshed.selectionRevision, isNot(old.selectionRevision));
      expect(
        tester.widget<TextField>(_key('mail-list-search')).controller!.text,
        'message',
      );
      old.onBulkAction!(MailBulkFlagAction.markRead, ['imap-message-91:300']);
      await _pump(tester);
      expect(browser.changes, isEmpty);
      expect(browser.reads, 0);
    },
  );

  testWidgets(
    'IMAP stale bulk callback cannot reach a reconnected identical account adapter',
    (tester) async {
      final browser = _BulkBrowser();
      await _show(tester, browser);
      final stale = _bulkList(tester).onBulkAction!;
      await tester.tap(_button(_strings.disconnect));
      await _pump(tester);
      await tester.enterText(_field(_strings.password), 'fixture-password');
      await tester.ensureVisible(find.text(_strings.connect));
      await tester.tap(find.text(_strings.connect));
      await _pump(tester);
      expect(find.byType(MailMessageList), findsOneWidget);
      stale(MailBulkFlagAction.markRead, ['imap-message-91:300']);
      await _pump(tester);
      expect(browser.changes, isEmpty);
      expect(_bulkList(tester).items.first.isRead, isFalse);
      expect(browser.reads, 0);
    },
  );

  testWidgets('IMAP disposed bulk callback never dispatches or changes state', (
    tester,
  ) async {
    final browser = _BulkBrowser();
    await _show(tester, browser);
    final stale = _bulkList(tester).onBulkAction!;
    await tester.pumpWidget(const SizedBox.shrink());
    stale(MailBulkFlagAction.flag, ['imap-message-91:300']);
    await _pump(tester);
    expect(browser.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'IMAP late bulk confirmation after disposal has no view side effects',
    (tester) async {
      final gate = Completer<void>();
      final browser = _BulkBrowser()..mutationGate = gate;
      await _show(tester, browser);
      _bulkList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
        'imap-message-91:300',
        'imap-message-91:200',
      ]);
      await _pump(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await _pump(tester);
      expect(browser.changes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  _bulkWorkspaceTests();
  testWidgets('IMAP searches visible header fields without provider work', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 20, 12);
    final browser = _Browser()
      ..pages = (mailbox, cursor, limit) async => StudioMailHeaderPage(
        messages: [
          _header(
            300,
            'Quarterly report',
            flagged: true,
            date: date,
            to: [mail.MailAddress('Project Team', 'team@example.test')],
            cc: [mail.MailAddress('Reviewer', 'reviewer@example.test')],
          ),
          _header(200, 'Quarterly report', read: true),
        ],
      );
    await _show(tester, browser);
    final rows = tester
        .widget<MailMessageList>(find.byType(MailMessageList))
        .items;
    expect(rows.first.date, date);
    expect(rows.first.to, contains('Project Team <team@example.test>'));
    expect(rows.first.cc, contains('reviewer@example.test'));
    await tester.enterText(
      _key('mail-list-search'),
      'from:writer to:"Project Team" cc:reviewer subject:"Quarterly report" '
      'on:2026-11-20 is:unread is:flagged',
    );
    await _pump(tester);
    expect(_key('imap-message-91:300'), findsOneWidget);
    expect(_key('imap-message-91:200'), findsNothing);
    expect(find.textContaining('1 shown · 2 loaded'), findsOneWidget);
    await tester.enterText(_key('mail-list-search'), 'to:hidden@example.test');
    await _pump(tester);
    expect(
      find.text(_strings.mailMessageListStrings.noMatches),
      findsOneWidget,
    );
    await tester.enterText(_key('mail-list-search'), 'bcc:hidden@example.test');
    await _pump(tester);
    expect(
      find.text(
        _strings.mailMessageListStrings.searchError(
          MailHeaderSearchError.unknownField,
        ),
      ),
      findsOneWidget,
    );
    expect(browser.requests, hasLength(1));
    expect(browser.reads, 0);
    expect(browser.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IMAP uses bounded pages and keeps no-match pagination visible', (
    tester,
  ) async {
    final browser = _Browser();
    final client = await _show(tester, browser);
    expect(client.legacyFetches, 0);
    expect(browser.requests.single.$3, 50);
    await tester.enterText(_key('mail-list-search'), 'Older');
    await tester.tap(_key('mail-list-flagged'));
    await _pump(tester);
    expect(
      find.text(_strings.mailMessageListStrings.noMatches),
      findsOneWidget,
    );
    expect(browser.reads, 0);
    expect(browser.requests, hasLength(1));
    await tester.tap(_key('imap-load-more'));
    await _pump(tester);
    expect(_key('imap-message-91:100'), findsOneWidget);
    expect(browser.requests.last.$2!.value, 'next-page');
    expect(find.textContaining('1 shown · 3 loaded'), findsOneWidget);
    expect(_key('imap-load-more'), findsNothing);
    expect(browser.reads, 0);
  });

  testWidgets('IMAP keyboard movement never reads until Enter', (tester) async {
    final browser = _Browser();
    await _show(tester, browser);
    tester.widget<Focus>(_key('mail-list-focus')).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(browser.reads, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pump(tester);
    expect(browser.reads, 1);
    expect(browser.changes, isEmpty);
    expect(
      tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller
          .result
          .message!
          .body
          .plainText,
      contains('Body for UID 200'),
    );
  });

  testWidgets('IMAP compact Back preserves query filters and selected row', (
    tester,
  ) async {
    final browser = _Browser();
    await _show(tester, browser, compact: true);
    await tester.enterText(_key('mail-list-search'), 'Newest');
    await tester.tap(_key('mail-list-unread'));
    await _pump(tester);
    await tester.tap(_key('imap-message-91:300'));
    await _pump(tester);
    expect(_key('mail-list-search'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pump(tester);
    expect(
      browser.reads,
      1,
      reason: 'Hidden list must not retain keyboard activation',
    );
    await tester.tap(_button(_strings.backToMessages));
    await _pump(tester);
    expect(
      tester.widget<TextField>(_key('mail-list-search')).controller!.text,
      'Newest',
    );
    expect(
      tester.widget<FilterChip>(_key('mail-list-unread')).selected,
      isTrue,
    );
    expect(
      tester.widget<Semantics>(_key('imap-message-91:300')).properties.selected,
      isTrue,
    );
  });

  testWidgets('IMAP folder change resets filters and continuation scope', (
    tester,
  ) async {
    final browser = _Browser();
    await _show(tester, browser);
    await tester.enterText(_key('mail-list-search'), 'missing');
    await tester.tap(_key('mail-list-unread'));
    await _pump(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Archive'));
    await _pump(tester);
    expect(_key('imap-message-92:50'), findsOneWidget);
    expect(
      tester.widget<TextField>(_key('mail-list-search')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<FilterChip>(_key('mail-list-unread')).selected,
      isFalse,
    );
    expect(browser.requests.last.$1, 'Archive');
    expect(browser.requests.last.$2, isNull);
    expect(_key('imap-load-more'), findsNothing);
  });

  testWidgets('IMAP read and flag filters update only on confirmed actions', (
    tester,
  ) async {
    final browser = _Browser();
    await _show(tester, browser);
    await tester.tap(_key('mail-list-unread'));
    await tester.pump();
    await tester.tap(_key('imap-message-91:300'));
    await _pump(tester);
    browser.mutationGate = Completer<void>();
    await tester.tap(_button(_strings.markRead));
    await tester.pump();
    expect(_key('imap-message-91:300'), findsOneWidget);
    expect(browser.changes.single, ('read', 300, true));
    browser.mutationGate!.complete();
    await _pump(tester);
    expect(_key('imap-message-91:300'), findsNothing);
    browser.mutationGate = null;
    await tester.tap(_button(_strings.ewsMarkUnread));
    await _pump(tester);
    expect(_key('imap-message-91:300'), findsOneWidget);
    await tester.tap(_key('mail-list-flagged'));
    await _pump(tester);
    expect(_key('imap-message-91:300'), findsNothing);
    await tester.tap(_button(_strings.ewsFlag));
    await _pump(tester);
    expect(_key('imap-message-91:300'), findsOneWidget);
    await tester.tap(_button(_strings.ewsUnflag));
    await _pump(tester);
    expect(_key('imap-message-91:300'), findsNothing);
    expect(browser.changes, [
      ('read', 300, true),
      ('read', 300, false),
      ('flagged', 300, true),
      ('flagged', 300, false),
    ]);
  });

  testWidgets(
    'IMAP confirmed target flags never invent the other unknown flag',
    (tester) async {
      final browser = _Browser();
      browser.pages = (_, _, _) async => StudioMailHeaderPage(
        messages: [_header(300, 'Unknown flags')..flags = null],
      );
      await _show(tester, browser);
      await tester.tap(_key('imap-message-91:300'));
      await _pump(tester);
      await tester.tap(_button(_strings.ewsFlag));
      await _pump(tester);
      var row = tester
          .widget<MailMessageList>(find.byType(MailMessageList))
          .items
          .single;
      expect(row.isFlagged, isTrue);
      expect(row.isRead, isNull);
      await tester.tap(_key('mail-list-unread'));
      await _pump(tester);
      expect(_key('imap-message-91:300'), findsNothing);
      await tester.tap(_button(_strings.markRead));
      await _pump(tester);
      row = tester
          .widget<MailMessageList>(find.byType(MailMessageList))
          .items
          .single;
      expect(row.isRead, isTrue);
      expect(row.isFlagged, isTrue);
      await tester.tap(_button(_strings.ewsMarkUnread));
      await _pump(tester);
      expect(_key('imap-message-91:300'), findsOneWidget);
      browser.pages = (_, _, _) async => StudioMailHeaderPage(
        messages: [_header(300, 'Server snapshot', read: true)],
      );
      await tester.tap(_button(_strings.refresh));
      await _pump(tester);
      row = tester
          .widget<MailMessageList>(find.byType(MailMessageList))
          .items
          .single;
      expect(row.isRead, isTrue);
      expect(row.isFlagged, isFalse);
    },
  );

  testWidgets('IMAP read confirmation retains unknown flagged state', (
    tester,
  ) async {
    final browser = _Browser();
    browser.pages = (_, _, _) async => StudioMailHeaderPage(
      messages: [_header(300, 'Unknown flags')..flags = null],
    );
    await _show(tester, browser);
    await tester.tap(_key('imap-message-91:300'));
    await _pump(tester);
    await tester.tap(_button(_strings.markRead));
    await _pump(tester);
    final row = tester
        .widget<MailMessageList>(find.byType(MailMessageList))
        .items
        .single;
    expect(row.isRead, isTrue);
    expect(row.isFlagged, isNull);
  });

  testWidgets(
    'IMAP unconfirmed mutation requires refresh without retry or optimistic flags',
    (tester) async {
      final browser = _Browser()..failMutation = true;
      await _show(tester, browser);
      await tester.tap(_key('imap-message-91:300'));
      await _pump(tester);
      await tester.tap(_button(_strings.ewsFlag));
      await _pump(tester);
      expect(browser.changes, hasLength(1));
      expect(find.text(_strings.mailWorkspaceRefreshRequired), findsOneWidget);
      expect(
        tester.widget<IconButton>(_button(_strings.ewsFlag)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(_key('imap-load-more')).onPressed,
        isNull,
      );
      await tester.tap(_button(_strings.refresh));
      await _pump(tester);
      expect(browser.requests.last.$2, isNull);
      expect(browser.changes, hasLength(1));
      expect(
        tester.widget<TextButton>(_key('imap-load-more')).onPressed,
        isNotNull,
      );
    },
  );

  for (final failure in [
    'repeated',
    'cross-folder',
    'duplicate',
    'oversized',
  ]) {
    testWidgets(
      'IMAP rejects $failure continuation without losing loaded rows',
      (tester) async {
        final browser = _Browser();
        await _show(tester, browser);
        browser.pages = (mailbox, cursor, limit) async => switch (failure) {
          'repeated' => StudioMailHeaderPage(
            messages: [_header(100, 'Rejected row')],
            next: cursor,
          ),
          'cross-folder' => StudioMailHeaderPage(
            messages: [_header(100, 'Rejected row')],
            next: browser.cursor('elsewhere', 'Archive'),
          ),
          'duplicate' => StudioMailHeaderPage(
            messages: [
              _header(100, 'Rejected row'),
              _header(100, 'Rejected row'),
            ],
          ),
          _ => StudioMailHeaderPage(
            messages: [
              for (var i = 0; i <= limit; i++) _header(100 - i, 'Rejected row'),
            ],
          ),
        };
        await tester.tap(_key('imap-load-more'));
        await _pump(tester);
        expect(_key('imap-message-91:300'), findsOneWidget);
        expect(_key('imap-message-91:200'), findsOneWidget);
        expect(find.text('Rejected row'), findsNothing);
        expect(browser.requests, hasLength(2));
        expect(browser.reads, 0);
      },
    );
  }

  testWidgets('IMAP failed next page can be explicitly retried', (
    tester,
  ) async {
    final browser = _Browser();
    await _show(tester, browser);
    browser.pages = (_, _, _) async =>
        throw const StudioMailMessageLoadException(
          MailProblemCode.providerFailure,
        );
    await tester.tap(_key('imap-load-more'));
    await _pump(tester);
    expect(find.text(_strings.mailMailboxFailed), findsOneWidget);
    expect(_key('imap-message-91:300'), findsOneWidget);
    browser.pages = null;
    await tester.tap(_key('imap-load-more'));
    await _pump(tester);
    expect(_key('imap-message-91:100'), findsOneWidget);
    expect(browser.requests[1].$2, same(browser.requests[2].$2));
  });

  testWidgets('IMAP discards a late page after disconnect', (tester) async {
    final browser = _Browser();
    await _show(tester, browser);
    final gate = Completer<StudioMailHeaderPage>();
    browser.pages = (_, _, _) => gate.future;
    await tester.tap(_key('imap-load-more'));
    await tester.pump();
    await tester.tap(_button(_strings.disconnect));
    await _pump(tester);
    gate.complete(
      StudioMailHeaderPage(messages: [_header(100, 'Late private row')]),
    );
    await _pump(tester);
    expect(browser.disposals, 1);
    expect(find.text('Late private row'), findsNothing);
    expect(_key('mail-list-search'), findsNothing);
  });

  testWidgets('IMAP stops at 1000 loaded messages with an explicit limit', (
    tester,
  ) async {
    final browser = _Browser();
    browser.pages = (mailbox, cursor, limit) async {
      final offset = cursor == null ? 0 : int.parse(cursor.value);
      return StudioMailHeaderPage(
        messages: [
          for (var i = 0; i < limit; i++)
            _header(2000 - offset - i, 'Message ${offset + i}'),
        ],
        next: browser.cursor('${offset + limit}'),
      );
    };
    await _show(tester, browser);
    for (var i = 1; i < 20; i++) {
      await tester.tap(_key('imap-load-more'));
      await _pump(tester);
    }
    expect(browser.requests, hasLength(20));
    expect(browser.requests.every((request) => request.$3 == 50), isTrue);
    expect(find.textContaining('1000 shown · 1000 loaded'), findsOneWidget);
    expect(find.text(_strings.mailWorkspaceLimit), findsOneWidget);
    expect(_key('imap-load-more'), findsNothing);
    expect(browser.reads, 0);
  });

  test('mailbox workspace feedback is supplied for all Studio languages', () {
    for (final language in StudioLanguage.values) {
      final strings = StudioStrings(language);
      final labels = strings.mailMessageListStrings;
      expect(labels.searchLoaded, isNotEmpty);
      expect(labels.unread, isNotEmpty);
      expect(labels.flagged, isNotEmpty);
      expect(labels.noMatches, isNotEmpty);
      expect(labels.loadedScope, isNotEmpty);
      expect(labels.searchHelpText, contains('subject:'));
      expect(labels.searchHelpText, contains('before:'));
      expect(labels.searchHelp, isNotEmpty);
      expect(labels.clearSearch, isNotEmpty);
      expect(labels.sort, isNotEmpty);
      expect(labels.providerOrder, isNotEmpty);
      expect(labels.newestFirst, isNotEmpty);
      expect(labels.oldestFirst, isNotEmpty);
      expect(labels.senderAscending, isNotEmpty);
      expect(labels.subjectAscending, isNotEmpty);
      for (final error in MailHeaderSearchError.values) {
        expect(labels.searchError(error), isNotEmpty);
        if (language != StudioLanguage.en) {
          expect(
            labels.searchError(error),
            isNot(_strings.mailMessageListStrings.searchError(error)),
          );
        }
      }
      expect(labels.count(3, 7), contains('3'));
      expect(labels.count(3, 7), contains('7'));
      expect(strings.mailWorkspaceLimit, isNotEmpty);
      expect(strings.mailWorkspaceRefreshRequired, isNotEmpty);
    }
  });
}

final class _EvidenceBulkBrowser extends _Browser
    implements StudioMailBulkMessageActions {
  final bulkCommands = <MailOperation>[];
  Future<MailResult<MailUnit>> Function(MailOperation)? bulkAnswer;
  mail.Mailbox? capturedMailbox;

  @override
  MailImapIdentity bulkIdentity(mail.Mailbox mailbox, mail.MimeMessage header) {
    capturedMailbox = mailbox;
    return MailImapIdentity(
      mailbox: MailMailboxId(mailbox.path, account: account),
      uidValidity: mailbox.uidValidity!,
      uid: header.uid!,
    );
  }

  @override
  Future<MailResult<MailUnit>> applyBulkFlag(
    MailOperation command,
    MailOperationLease lease,
  ) {
    lease.checkCurrent();
    bulkCommands.add(command);
    return bulkAnswer?.call(command) ??
        Future.value(const MailSuccess(MailUnit.value));
  }
}

MailMessageList _mailList(WidgetTester tester) =>
    tester.widget<MailMessageList>(find.byType(MailMessageList));

StudioMailBulkStatus _bulkStatus(WidgetTester tester) =>
    _mailList(tester).bulkStatus! as StudioMailBulkStatus;

final class _TypedBulkBrowser extends _BulkBrowser
    implements StudioMailBulkMessageActions {
  final bulkCommands = <MailOperation>[];
  Future<MailResult<MailUnit>> Function(MailOperation)? bulkAnswer;
  mail.Mailbox? capturedMailbox;

  @override
  MailHeaderRecord observedHeader(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) {
    capturedMailbox = mailbox;
    return super.observedHeader(mailbox, header);
  }

  @override
  MailImapIdentity bulkIdentity(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) => observedHeader(mailbox, header).remote as MailImapIdentity;

  @override
  Future<MailResult<MailUnit>> applyBulkFlag(
    MailOperation command,
    MailOperationLease lease,
  ) {
    lease.checkCurrent();
    bulkCommands.add(command);
    return bulkAnswer?.call(command) ??
        Future.value(const MailSuccess(MailUnit.value));
  }
}

// Preserve distinct scenarios from work/mail-bulk-actions-20261120 at
// b60c0ec26f2a80c984076fb1d480eb2e641b542e, through the accepted typed bulk
// adapter/status API. Reconnect is an additional positive/negative control for
// the session-capture difference found during the concurrent source review.
void _peerBulkWorkspaceTests() {
  testWidgets(
    'certified native quota stops the tail and keeps retry guidance without refresh',
    (tester) async {
      final browser = _TypedBulkBrowser();
      browser.pages = (_, _, _) async => StudioMailHeaderPage(
        messages: [
          for (final uid in [300, 200, 100]) _header(uid, 'Message $uid'),
        ],
      );
      browser.bulkAnswer = (_) async => const MailFailure(
        MailProblem(
          MailProblemCode.quotaExceeded,
          retryAfter: Duration(milliseconds: 1250),
          mutationMayHaveOccurred: false,
        ),
      );
      await _show(tester, browser);
      _mailList(tester).onBulkAction!(MailBulkFlagAction.flag, [
        'imap-message-91:300',
        'imap-message-91:200',
        'imap-message-91:100',
      ]);
      await _pump(tester);
      expect(browser.bulkCommands, hasLength(1));
      expect(browser.changes, isEmpty);
      final report = _bulkStatus(tester).report;
      expect(report.stopReason, MailBulkFlagStopReason.rateLimited);
      expect(report.confirmedCount, 0);
      expect(report.failedCount, 1);
      expect(report.uncertainCount, 0);
      expect(report.unattemptedCount, 2);
      expect(report.requiresRefresh, isFalse);
      expect(_mailList(tester).bulkEnabled, isTrue);
      expect(_mailList(tester).busy, isFalse);
      expect(_mailList(tester).items.map((row) => row.isFlagged), [
        false,
        false,
        false,
      ]);
      expect(find.text(_strings.mailWorkspaceRefreshRequired), findsNothing);
      expect(find.textContaining('Request limit reached.'), findsOneWidget);
      expect(
        find.text('Wait at least 2 seconds before trying again.'),
        findsOneWidget,
      );
      await tester.ensureVisible(_key('studio-mail-bulk-details'));
      await tester.tap(_key('studio-mail-bulk-details'));
      await _pump(tester);
      expect(
        find.descendant(
          of: _key('studio-mail-bulk-result-0'),
          matching: find.text('Wait at least 2 seconds before trying again.'),
        ),
        findsOneWidget,
      );
      expect(browser.bulkCommands, hasLength(1));
      expect(browser.reads, 0);
      expect(browser.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  group('IMAP reconciled bulk scenarios', () {
    testWidgets('legacy action capability does not imply safe bulk identity', (
      tester,
    ) async {
      final browser = _Browser();
      await _show(tester, browser);
      expect(_mailList(tester).onBulkAction, isNull);
      expect(browser.reads, 0);
      expect(browser.changes, isEmpty);
    });

    for (final action in MailBulkFlagAction.values) {
      testWidgets(
        '$action freezes reverse subset and keeps the opened reader',
        (tester) async {
          final headers = [
            _header(300, 'Opened message'),
            _header(200, 'Known selected', read: true, flagged: true),
            _header(100, 'Unknown selected')..flags = null,
          ];
          final browser = _TypedBulkBrowser()
            ..pages = (_, _, _) async =>
                StudioMailHeaderPage(messages: headers);
          await _show(tester, browser);
          _mailList(tester).onOpen('imap-message-91:300');
          await _pump(tester);
          expect(browser.reads, 1);
          final reader = tester.widget<MailMessageView>(
            find.byType(MailMessageView),
          );
          final selection = ['imap-message-91:100', 'imap-message-91:200'];
          _mailList(tester).onBulkAction!(action, selection);
          selection
            ..clear()
            ..add('imap-message-91:300');
          await _pump(tester);
          expect(
            browser.bulkCommands.map(
              (command) => (command.message as MailImapIdentity).uid,
            ),
            [100, 200],
          );
          expect(_mailList(tester).selectedId, 'imap-message-91:300');
          expect(
            tester
                .widget<MailMessageView>(find.byType(MailMessageView))
                .controller,
            same(reader.controller),
          );
          expect(browser.reads, 1);
          expect(browser.requests, hasLength(1));
          expect(browser.changes, isEmpty);
          expect(_bulkStatus(tester).report.confirmedCount, 2);
          expect(_bulkStatus(tester).report.unattemptedCount, 0);
          final rows = _mailList(tester).items;
          expect(rows.first.isRead, isFalse);
          expect(rows.first.isFlagged, isFalse);
          if (action == MailBulkFlagAction.markRead ||
              action == MailBulkFlagAction.markUnread) {
            expect(rows.skip(1).map((row) => row.isRead), [
              action == MailBulkFlagAction.markRead,
              action == MailBulkFlagAction.markRead,
            ]);
            expect(rows.skip(1).map((row) => row.isFlagged), [true, null]);
          } else {
            expect(rows.skip(1).map((row) => row.isFlagged), [
              action == MailBulkFlagAction.flag,
              action == MailBulkFlagAction.flag,
            ]);
            expect(rows.skip(1).map((row) => row.isRead), [true, null]);
          }
        },
      );
    }

    testWidgets(
      'answered draft and deleted flags survive confirmed bulk edits',
      (tester) async {
        final unknown = _header(300, 'Unknown')..flags = null;
        final known = _header(200, 'Known', read: true)
          ..setFlag(mail.MessageFlags.answered, true)
          ..setFlag(mail.MessageFlags.draft, true)
          ..setFlag(mail.MessageFlags.deleted, true);
        final browser = _TypedBulkBrowser()
          ..pages = (_, _, _) async =>
              StudioMailHeaderPage(messages: [unknown, known]);
        await _show(tester, browser);
        _mailList(tester).onBulkAction!(MailBulkFlagAction.flag, [
          'imap-message-91:300',
          'imap-message-91:200',
        ]);
        await _pump(tester);
        _mailList(tester).onBulkAction!(MailBulkFlagAction.markUnread, [
          'imap-message-91:200',
        ]);
        await _pump(tester);
        _mailList(tester).onBulkAction!(MailBulkFlagAction.unflag, [
          'imap-message-91:300',
        ]);
        await _pump(tester);
        expect(_mailList(tester).items.map((row) => row.isRead), [null, false]);
        expect(_mailList(tester).items.map((row) => row.isFlagged), [
          false,
          true,
        ]);
        expect(known.isAnswered, isTrue);
        expect(known.hasFlag(mail.MessageFlags.draft), isTrue);
        expect(known.isDeleted, isTrue);
        expect(browser.reads, 0);
      },
    );

    testWidgets('a later selected UID change retires dispatch and projection', (
      tester,
    ) async {
      final headers = [
        _header(300, 'First selected'),
        _header(200, 'Later selected'),
      ];
      final gate = Completer<MailResult<MailUnit>>();
      final browser = _TypedBulkBrowser()
        ..pages = ((_, _, _) async => StudioMailHeaderPage(messages: headers))
        ..bulkAnswer = (_) => gate.future;
      await _show(tester, browser);
      _mailList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
        'imap-message-91:300',
        'imap-message-91:200',
      ]);
      await tester.pump();
      headers[1].uid = 999;
      gate.complete(const MailSuccess(MailUnit.value));
      await _pump(tester);
      expect(browser.bulkCommands, hasLength(1));
      expect(
        (browser.bulkCommands.single.message as MailImapIdentity).uid,
        300,
      );
      expect(
        _mailList(tester).items.every((row) => row.isRead == false),
        isTrue,
      );
      expect(_mailList(tester).bulkActionsEnabled, isFalse);
      expect(_mailList(tester).busy, isFalse);
      // Preserve the acknowledged receipt while refusing stale projection.
      expect(_bulkStatus(tester).report.confirmedCount, 1);
      expect(_bulkStatus(tester).report.unattemptedCount, 1);
      expect(_bulkStatus(tester).report.requiresRefresh, isTrue);
      expect(find.text(_strings.mailWorkspaceRefreshRequired), findsOneWidget);
      expect(browser.reads, 0);
    });

    testWidgets('folder A to B to A rejects an old host callback', (
      tester,
    ) async {
      final browser = _TypedBulkBrowser();
      await _show(tester, browser);
      final old = _mailList(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Archive'));
      await _pump(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Inbox'));
      await _pump(tester);
      old.onBulkAction!(MailBulkFlagAction.flag, [old.items.first.id]);
      await _pump(tester);
      expect(browser.bulkCommands, isEmpty);
      expect(_mailList(tester).items.first.isFlagged, isFalse);
      expect(browser.reads, 0);
      final current = _mailList(tester);
      current.onBulkAction!(MailBulkFlagAction.flag, [current.items.first.id]);
      await _pump(tester);
      expect(browser.bulkCommands, hasLength(1));
      expect(_mailList(tester).items.first.isFlagged, isTrue);
    });

    testWidgets('reconnect rejects old callback despite overlapping row IDs', (
      tester,
    ) async {
      final first = _TypedBulkBrowser();
      final second = _TypedBulkBrowser();
      await _show(tester, first, reconnectBrowser: second);
      final old = _mailList(tester);
      await tester.tap(_button(_strings.disconnect));
      await _pump(tester);
      await tester.enterText(
        _field(_strings.password),
        'second-fixture-password',
      );
      await tester.ensureVisible(find.text(_strings.connect));
      await tester.tap(find.text(_strings.connect));
      await _pump(tester);
      final current = _mailList(tester);
      expect(current.items.first.id, old.items.first.id);
      old.onBulkAction!(MailBulkFlagAction.flag, [old.items.first.id]);
      await _pump(tester);
      expect(first.bulkCommands, isEmpty);
      expect(second.bulkCommands, isEmpty);
      expect(first.disposals, 1);
      current.onBulkAction!(MailBulkFlagAction.flag, [current.items.first.id]);
      await _pump(tester);
      expect(second.bulkCommands, hasLength(1));
      expect(_mailList(tester).items.first.isFlagged, isTrue);
      expect(first.reads, 0);
      expect(second.reads, 0);
    });
    testWidgets('disposed bulk callback cannot dispatch or change state', (
      tester,
    ) async {
      final browser = _TypedBulkBrowser();
      await _show(tester, browser);
      final stale = _mailList(tester).onBulkAction!;
      await tester.pumpWidget(const SizedBox.shrink());
      stale(MailBulkFlagAction.flag, ['imap-message-91:300']);
      await _pump(tester);
      expect(browser.bulkCommands, isEmpty);
      expect(browser.changes, isEmpty);
      expect(browser.reads, 0);
      expect(tester.takeException(), isNull);
    });

    // The peer's final 639ea75 revision added certified provider outcomes.
    // Exercise them through the accepted typed adapter, with no legacy writes.
    for (final problem in [
      MailProblemCode.permissionDenied,
      MailProblemCode.cancelled,
      MailProblemCode.staleOperation,
    ]) {
      testWidgets('explicit no-mutation $problem evidence stays definite', (
        tester,
      ) async {
        final stops = problem != MailProblemCode.permissionDenied;
        final refreshRequired = problem == MailProblemCode.staleOperation;
        final browser = _TypedBulkBrowser()
          ..pages = ((_, _, _) async => StudioMailHeaderPage(
            messages: [
              for (final uid in [300, 200, 100]) _header(uid, 'Message $uid'),
            ],
          ))
          ..bulkAnswer = (command) async =>
              (command.message as MailImapIdentity).uid == 300
              ? MailFailure(
                  MailProblem(problem, mutationMayHaveOccurred: false),
                )
              : const MailSuccess(MailUnit.value);
        await _show(tester, browser);
        _mailList(tester).onBulkAction!(MailBulkFlagAction.markRead, [
          'imap-message-91:300',
          'imap-message-91:200',
          'imap-message-91:100',
        ]);
        await _pump(tester);
        expect(browser.bulkCommands, hasLength(stops ? 1 : 3));
        expect(_mailList(tester).items.map((row) => row.isRead), [
          false,
          !stops,
          !stops,
        ]);
        expect(_mailList(tester).bulkEnabled, !refreshRequired);
        final report = _bulkStatus(tester).report;
        expect(report.confirmedCount, stops ? 0 : 2);
        expect(report.failedCount, 1);
        expect(report.uncertainCount, 0);
        expect(report.unattemptedCount, stops ? 2 : 0);
        expect(
          find.text(_strings.mailWorkspaceRefreshRequired),
          refreshRequired ? findsOneWidget : findsNothing,
        );
        expect(browser.changes, isEmpty);
        expect(browser.reads, 0);
        expect(browser.requests, hasLength(1));
        expect(_mailList(tester).busy, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    for (final mayHaveOccurred in <bool?>[null, true]) {
      testWidgets('uncertified $mayHaveOccurred failure remains uncertain', (
        tester,
      ) async {
        final browser = _TypedBulkBrowser()
          ..pages = ((_, _, _) async => StudioMailHeaderPage(
            messages: [
              for (final uid in [300, 200, 100]) _header(uid, 'Message $uid'),
            ],
          ))
          ..bulkAnswer = (_) async => MailFailure(
            MailProblem(
              MailProblemCode.permissionDenied,
              mutationMayHaveOccurred: mayHaveOccurred,
            ),
          );
        await _show(tester, browser);
        _mailList(tester).onBulkAction!(MailBulkFlagAction.flag, [
          'imap-message-91:300',
          'imap-message-91:200',
          'imap-message-91:100',
        ]);
        await _pump(tester);
        expect(browser.bulkCommands, hasLength(1));
        expect(
          _mailList(tester).items.every((row) => row.isFlagged == false),
          isTrue,
        );
        expect(_mailList(tester).bulkEnabled, isFalse);
        final report = _bulkStatus(tester).report;
        expect(report.confirmedCount, 0);
        expect(report.failedCount, 0);
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 2);
        expect(
          find.text(_strings.mailWorkspaceRefreshRequired),
          findsOneWidget,
        );
        expect(browser.changes, isEmpty);
        expect(browser.reads, 0);
        expect(browser.requests, hasLength(1));
      });
    }
  });
}

void _bulkWorkspaceTests() {
  group('IMAP foreground bulk flags', () {
    for (final action in MailBulkFlagAction.values) {
      testWidgets('$action changes only the confirmed target flag', (
        tester,
      ) async {
        final browser = _EvidenceBulkBrowser()
          ..pages = (_, _, _) async => StudioMailHeaderPage(
            messages: [
              _header(300, 'First unknown')..flags = null,
              _header(200, 'Second unknown')..flags = null,
            ],
          );
        await _show(tester, browser);
        final list = _mailList(tester);
        list.onBulkAction!(action, list.items.map((item) => item.id).toList());
        await _pump(tester);
        final report = _bulkStatus(tester).report;
        expect(report.confirmedCount, 2);
        expect(report.failedCount, 0);
        expect(report.uncertainCount, 0);
        expect(report.unattemptedCount, 0);
        expect(
          browser.bulkCommands.map(
            (command) => (command.message as MailImapIdentity).uid,
          ),
          [300, 200],
        );
        for (final row in _mailList(tester).items) {
          if (action == MailBulkFlagAction.markRead ||
              action == MailBulkFlagAction.markUnread) {
            expect(row.isRead, action == MailBulkFlagAction.markRead);
            expect(row.isFlagged, isNull);
          } else {
            expect(row.isFlagged, action == MailBulkFlagAction.flag);
            expect(row.isRead, isNull);
          }
        }
        expect(browser.reads, 0);
        expect(browser.changes, isEmpty);
        expect(browser.requests, hasLength(1));
      });
    }

    testWidgets('mixed results stop uncertainty and require explicit refresh', (
      tester,
    ) async {
      final browser = _EvidenceBulkBrowser();
      browser.pages = (_, _, _) async => StudioMailHeaderPage(
        messages: [
          for (var uid = 1; uid <= 5; uid++) _header(uid, 'Message $uid'),
        ],
      );
      browser.bulkAnswer = (command) async {
        final uid = (command.message as MailImapIdentity).uid;
        if (uid == 2) {
          return const MailFailure(
            MailProblem(
              MailProblemCode.permissionDenied,
              mutationMayHaveOccurred: false,
            ),
          );
        }
        if (uid == 4) {
          return const MailFailure(
            MailProblem(
              MailProblemCode.conflict,
              mutationMayHaveOccurred: true,
            ),
          );
        }
        return const MailSuccess(MailUnit.value);
      };
      await _show(tester, browser);
      final list = _mailList(tester);
      list.onBulkAction!(
        MailBulkFlagAction.flag,
        list.items.map((item) => item.id).toList(),
      );
      await _pump(tester);
      final report = _bulkStatus(tester).report;
      expect(report.results.map((result) => result.outcome), [
        MailBulkFlagOutcome.confirmed,
        MailBulkFlagOutcome.failed,
        MailBulkFlagOutcome.confirmed,
        MailBulkFlagOutcome.uncertain,
        MailBulkFlagOutcome.unattempted,
      ]);
      expect(browser.bulkCommands, hasLength(4));
      expect(_mailList(tester).items.map((row) => row.isFlagged), [
        true,
        false,
        true,
        false,
        false,
      ]);
      expect(_mailList(tester).bulkEnabled, isFalse);
      _mailList(tester).onBulkAction!(MailBulkFlagAction.unflag, [
        'imap-message-91:1',
      ]);
      await _pump(tester);
      expect(browser.bulkCommands, hasLength(4));
      await tester.tap(_button(_strings.refresh));
      await _pump(tester);
      expect(_mailList(tester).bulkEnabled, isTrue);
      expect(_mailList(tester).bulkStatus, isNull);
      expect(browser.reads, 0);
    });

    testWidgets(
      'Stop waits for current confirmation and leaves the rest untouched',
      (tester) async {
        final gate = Completer<MailResult<MailUnit>>();
        final browser = _EvidenceBulkBrowser()..bulkAnswer = (_) => gate.future;
        await _show(tester, browser);
        final list = _mailList(tester);
        list.onBulkAction!(
          MailBulkFlagAction.flag,
          list.items.map((item) => item.id).toList(),
        );
        await tester.pump();
        expect(browser.bulkCommands, hasLength(1));
        _bulkStatus(tester).onStop!();
        gate.complete(const MailSuccess(MailUnit.value));
        await _pump(tester);
        final status = _bulkStatus(tester);
        expect(status.running, isFalse);
        expect(status.report.confirmedCount, 1);
        expect(status.report.unattemptedCount, 1);
        expect(status.report.stopProblem?.code, MailProblemCode.cancelled);
        expect(status.report.requiresRefresh, isFalse);
        expect(browser.bulkCommands, hasLength(1));
        expect(_mailList(tester).busy, isFalse);
        expect(_mailList(tester).items.first.isFlagged, isTrue);
        expect(_mailList(tester).items.last.isFlagged, isFalse);
      },
    );

    testWidgets(
      'refresh invalidates saved callbacks even with repeated row IDs',
      (tester) async {
        final browser = _EvidenceBulkBrowser();
        await _show(tester, browser);
        final old = _mailList(tester);
        await tester.tap(_button(_strings.refresh));
        await _pump(tester);
        expect(
          _mailList(tester).selectionRevision,
          isNot(old.selectionRevision),
        );
        old.onBulkAction!(MailBulkFlagAction.flag, [old.items.first.id]);
        await _pump(tester);
        expect(browser.bulkCommands, isEmpty);
        final current = _mailList(tester);
        current.onBulkAction!(MailBulkFlagAction.flag, [
          current.items.first.id,
          'unknown-row',
        ]);
        current.onBulkAction!(MailBulkFlagAction.flag, [
          current.items.first.id,
          current.items.first.id,
        ]);
        await _pump(tester);
        expect(browser.bulkCommands, isEmpty);
      },
    );

    testWidgets(
      'mutable UIDVALIDITY retires the batch without wrong-scope flags',
      (tester) async {
        final gate = Completer<MailResult<MailUnit>>();
        final browser = _EvidenceBulkBrowser()..bulkAnswer = (_) => gate.future;
        await _show(tester, browser);
        final list = _mailList(tester);
        list.onBulkAction!(
          MailBulkFlagAction.flag,
          list.items.map((item) => item.id).toList(),
        );
        await tester.pump();
        browser.capturedMailbox!.uidValidity = 999;
        gate.complete(const MailSuccess(MailUnit.value));
        await _pump(tester);
        expect(browser.bulkCommands, hasLength(1));
        expect(
          (browser.bulkCommands.single.message as MailImapIdentity).uidValidity,
          91,
        );
        expect(
          _mailList(tester).items.every((row) => row.isFlagged == false),
          isTrue,
        );
        expect(_mailList(tester).bulkEnabled, isFalse);
        expect(_mailList(tester).busy, isFalse);
        expect(_bulkStatus(tester).report.confirmedCount, 1);
        expect(_bulkStatus(tester).report.unattemptedCount, 1);
      },
    );

    testWidgets('old status callbacks cannot stop or hide a later batch', (
      tester,
    ) async {
      final firstGate = Completer<MailResult<MailUnit>>();
      final browser = _EvidenceBulkBrowser()
        ..bulkAnswer = (_) => firstGate.future;
      await _show(tester, browser);
      var list = _mailList(tester);
      list.onBulkAction!(
        MailBulkFlagAction.flag,
        list.items.map((item) => item.id).toList(),
      );
      await tester.pump();
      final oldStop = _bulkStatus(tester).onStop!;
      firstGate.complete(const MailSuccess(MailUnit.value));
      await _pump(tester);
      final oldDismiss = _bulkStatus(tester).onDismiss!;
      final secondGate = Completer<MailResult<MailUnit>>();
      browser.bulkAnswer = (_) => secondGate.future;
      list = _mailList(tester);
      list.onBulkAction!(
        MailBulkFlagAction.unflag,
        list.items.map((item) => item.id).toList(),
      );
      await tester.pump();
      final currentStop = _bulkStatus(tester).onStop!;
      oldStop();
      oldDismiss();
      await tester.pump();
      expect(_bulkStatus(tester).running, isTrue);
      expect(_bulkStatus(tester).onStop, isNotNull);
      secondGate.complete(const MailSuccess(MailUnit.value));
      await _pump(tester);
      expect(browser.bulkCommands, hasLength(4));
      expect(_bulkStatus(tester).report.confirmedCount, 2);
      expect(_bulkStatus(tester).report.unattemptedCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(oldStop, returnsNormally);
      expect(oldDismiss, returnsNormally);
      expect(currentStop, returnsNormally);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disconnect prevents later dispatch and late UI resurrection', (
      tester,
    ) async {
      final gate = Completer<MailResult<MailUnit>>();
      final browser = _EvidenceBulkBrowser()..bulkAnswer = (_) => gate.future;
      await _show(tester, browser);
      final list = _mailList(tester);
      list.onBulkAction!(
        MailBulkFlagAction.flag,
        list.items.map((item) => item.id).toList(),
      );
      await tester.pump();
      await tester.tap(_button(_strings.disconnect));
      await _pump(tester);
      gate.complete(const MailSuccess(MailUnit.value));
      await _pump(tester);
      expect(browser.bulkCommands, hasLength(1));
      expect(browser.disposals, 1);
      expect(find.byType(MailMessageList), findsNothing);
      expect(find.byType(StudioMailBulkStatus), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
