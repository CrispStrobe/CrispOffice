import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
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
}) => mail.MimeMessage.fromEnvelope(
  mail.Envelope(
    subject: subject,
    from: [mail.MailAddress('Writer', 'writer@example.test')],
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

final class _Browser
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
    await mutationGate?.future;
    if (failMutation) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.providerFailure,
      );
    }
  }

  @override
  void cancel() {}
  @override
  void dispose() {
    disposals++;
  }
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
}) async {
  final client = _Client();
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
        clientFactory: (_) => client,
        messageLoaderFactory: (_) => browser,
        draftStoreFactory: drafts.open,
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

void main() {
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
      expect(labels.count(3, 7), contains('3'));
      expect(labels.count(3, 7), contains('7'));
      expect(strings.mailWorkspaceLimit, isNotEmpty);
      expect(strings.mailWorkspaceRefreshRequired, isNotEmpty);
    }
  });
}
