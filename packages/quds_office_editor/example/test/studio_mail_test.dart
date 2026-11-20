import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/studio_mail_archive_action.dart';
import 'package:quds_office_studio/studio_mail_archive_folder_action.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);

const _savedCredentials = StudioMailCredentials(
  email: 'saved@example.invalid',
  password: 'saved-fixture-password',
  imapHost: 'imap.saved.example.invalid',
  smtpHost: 'smtp.saved.example.invalid',
  manual: true,
  startTls: true,
);

final class _CredentialStore extends Fake implements StudioMailCredentialStore {
  StudioMailCredentials? saved;
  Future<StudioMailCredentials?> Function()? onLoad;
  Future<bool> Function(StudioMailCredentials)? onSave;
  Future<bool> Function()? onClear;
  final writes = <StudioMailCredentials>[];
  int clears = 0;

  @override
  Future<StudioMailCredentials?> load() async =>
      onLoad == null ? saved : await onLoad!();

  @override
  Future<bool> save(StudioMailCredentials credentials) async {
    writes.add(credentials);
    final succeeded = await onSave?.call(credentials) ?? true;
    if (succeeded) saved = credentials;
    return succeeded;
  }

  @override
  Future<bool> clear() async {
    clears++;
    final succeeded = await onClear?.call() ?? true;
    if (succeeded) saved = null;
    return succeeded;
  }
}

mail.Mailbox _box(String name) => mail.Mailbox(
  encodedName: name,
  encodedPath: name,
  flags: <mail.MailboxFlag>[],
  pathSeparator: '/',
  uidValidity: 41,
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
    _message('First message')..uid = 7,
    _message('Second message')..uid = 8,
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
  Future<Uint8List> Function(mail.Mailbox, mail.MimeMessage)? onFetch;
  Future<void> Function(mail.Mailbox, mail.MimeMessage)? onMarkRead;
  final marked = <(mail.Mailbox, mail.MimeMessage)>[];
  bool disposed = false;
  @override
  Future<Uint8List> fetch(mail.Mailbox mailbox, mail.MimeMessage header) async {
    if (onFetch case final callback?) return callback(mailbox, header);
    final full = await client.fetchMessageContents(header);
    // Controlled test fixture bytes; production uses the bounded raw provider.
    return Uint8List.fromList(utf8.encode(full.renderMessage()));
  }

  @override
  Future<void> markRead(mail.Mailbox mailbox, mail.MimeMessage header) async {
    marked.add((mailbox, header));
    await onMarkRead?.call(mailbox, header);
  }

  @override
  void cancel() {}
  @override
  void dispose() => disposed = true;
}

final class _ArchivingLoader extends _Loader
    implements StudioMailMailboxArchiver {
  _ArchivingLoader(super.client);

  @override
  Future<MailArchiveRunReport> archiveMailbox(
    mail.Mailbox selectedMailbox, {
    required SqliteMailArchive archive,
    required MailArchiveProfile profile,
    MailCancellationToken? cancellation,
    void Function(MailArchiveRunProgress)? onProgress,
  }) => throw StateError('Injected folder writer should own the operation.');
}

Finder _iconButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

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
  StudioMailMessageLoader Function(mail.MailClient)? loaderFactory,
  StudioMailCredentialStore? credentialStore,
  Future<mail.ClientConfig?> Function(String)? accountDiscovery,
  bool fillForm = true,
  bool nativeLoader = false,
  StudioMailArchiveWriter? archiveWriter,
  StudioMailArchiveFolderWriter? archiveFolderWriter,
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
                draftStoreFactory: MemoryStudioMailDrafts().open,
                strings: strings,
                clientFactory: (account) =>
                    createdClient = clientFactory(account),
                messageLoaderFactory: nativeLoader
                    ? null
                    : (_) =>
                          loaderFactory?.call(createdClient!) ??
                          _Loader(createdClient!),
                credentialStore: credentialStore ?? _CredentialStore(),
                accountDiscovery: accountDiscovery,
                archiveWriter: archiveWriter,
                archiveFolderWriter: archiveFolderWriter,
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
  if (!fillForm) return;
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
  await tester.ensureVisible(
    find.widgetWithText(FilledButton, strings.connect),
  );
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

MailResult<MailArchiveImportResult> _archiveSuccess(MailMessage message) =>
    MailSuccess(
      MailArchiveImportResult(
        entry: MailArchiveEntry(
          id: message.raw.sha256,
          envelope: message.envelope,
          archivedAt: DateTime.utc(2026, 11, 19),
          byteLength: message.raw.length,
          attachmentCount: message.attachments.length,
          indexTruncated: false,
          attachmentTextIndexed: 0,
          attachmentTextSkipped: 0,
        ),
        duplicate: false,
        originAdded: true,
      ),
    );

MailArchiveRunReport _folderReport() => MailArchiveRunReport(
  status: MailArchiveRunStatus.completed,
  pages: 2,
  processed: 4,
  saved: 3,
  duplicates: 1,
  failed: 0,
  bytes: 300,
  elapsedMicroseconds: 1000,
  observerErrors: 0,
  failures: const [],
  droppedFailures: 0,
);

void main() {
  for (final forward in [false, true]) {
    testWidgets(
      '${forward ? 'forward' : 'reply'} uses the exact loaded body and envelope, not the list header',
      (tester) async {
        final client = _Client();
        client.messages[0] = mail.MimeMessage.parseFromText(
          'From: List sender <list@example.invalid>\r\n'
          'Subject: First message\r\n\r\n',
        )..uid = 7;
        final raw = Uint8List.fromList([
          ...ascii.encode(
            'From: Raw sender <raw@example.invalid>\r\n'
            'Reply-To: reply@example.invalid\r\n'
            'To: reader@example.invalid\r\n'
            'Bcc: hidden@example.invalid\r\n'
            'Subject: Raw subject\r\n'
            'Content-Type: text/plain; charset=iso-8859-1\r\n'
            'Content-Transfer-Encoding: 8bit\r\n\r\n'
            'Exact caf',
          ),
          0xe9,
          ...ascii.encode(' body.\r\n'),
        ]);
        final loader = _Loader(client)..onFetch = (_, _) async => raw;
        await _open(tester, (_) => client, loaderFactory: (_) => loader);
        await _connect(tester);
        await tester.tap(find.text('First message'));
        await _pump(tester);
        expect(_reader(tester).decodedText, contains('Exact café body.'));
        await tester.tap(
          find.byTooltip(forward ? _strings.forward : _strings.reply),
        );
        await _pump(tester);

        expect(find.byType(StudioMailComposeDialog), findsOneWidget);
        expect(
          tester.widget<TextField>(_field(_strings.to)).controller!.text,
          forward ? '' : 'reply@example.invalid',
        );
        expect(
          tester.widget<TextField>(_field(_strings.subject)).controller!.text,
          '${forward ? 'Fwd' : 'Re'}: Raw subject',
        );
        final body = tester
            .widget<QudsWordEditor>(find.byType(QudsWordEditor))
            .controller
            .document
            .paragraphs
            .map((paragraph) => paragraph.text)
            .join('\n');
        expect(body, contains('> Exact café body.'));
        expect(body, contains('raw@example.invalid'));
        expect(body, isNot(contains('list@example.invalid')));
        expect(body, isNot(contains('hidden@example.invalid')));
        expect(body, isNot(contains('Body of First message')));
        if (forward) expect(body, contains(_strings.mailTextOnlyForward));
        expect(client.sent, isEmpty);
        await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
        await tester.tap(find.text(_strings.mailDraftSaveClose));
        await _pump(tester);
        await _close(tester);
      },
    );

    testWidgets(
      '${forward ? 'forward' : 'reply'} reports an HTML-only body without quoting presentation headers',
      (tester) async {
        final client = _Client();
        final loader = _Loader(client)
          ..onFetch = (_, _) async => Uint8List.fromList(
            utf8.encode(
              'From: writer@example.invalid\r\n'
              'Subject: HTML message\r\n'
              'Bcc: hidden@example.invalid\r\n'
              'Content-Type: text/html; charset=utf-8\r\n\r\n'
              '<p>HTML-only body.</p>',
            ),
          );
        await _open(tester, (_) => client, loaderFactory: (_) => loader);
        await _connect(tester);
        await tester.tap(find.text('First message'));
        await _pump(tester);
        await tester.tap(
          find.byTooltip(forward ? _strings.forward : _strings.reply),
        );
        await _pump(tester);
        expect(find.text(_strings.mailPlainTextUnavailable), findsOneWidget);
        expect(find.byType(StudioMailComposeDialog), findsNothing);
        expect(client.sent, isEmpty);
        await _close(tester);
      },
    );

    testWidgets(
      '${forward ? 'forward' : 'reply'} cannot replace an uncertain draft; only confirmed discard releases it',
      (tester) async {
        final client = _Client()
          ..onSend = (_) async => throw StateError('uncertain submission');
        await _open(tester, (_) => client);
        await _connect(tester);
        await _compose(tester);
        await tester.tap(find.text('First message'));
        await _pump(tester);
        final action = find.byTooltip(
          forward ? _strings.forward : _strings.reply,
        );
        await tester.tap(action);
        await _pump(tester);
        expect(find.text(_strings.mailRetainedDraft), findsOneWidget);
        expect(find.byType(StudioMailComposeDialog), findsNothing);

        await tester.tap(find.widgetWithText(TextButton, _strings.compose));
        await _pump(tester);
        expect(
          tester.widget<TextField>(_field(_strings.subject)).controller!.text,
          'Controlled draft',
        );
        expect(find.text(_strings.mailRetryAcknowledgement), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, _strings.send),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
        await tester.tap(find.text(_strings.mailDraftSaveClose));
        await _pump(tester);

        await tester.tap(find.byTooltip(_strings.mailDiscardDraft));
        await _pump(tester);
        expect(find.text(_strings.mailDiscardDraftExplanation), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
        await _pump(tester);
        await tester.tap(action);
        await _pump(tester);
        expect(find.text(_strings.mailRetainedDraft), findsOneWidget);
        expect(find.byType(StudioMailComposeDialog), findsNothing);

        await tester.tap(find.byTooltip(_strings.mailDiscardDraft));
        await _pump(tester);
        await tester.tap(
          find.widgetWithText(FilledButton, _strings.mailDiscardDraft),
        );
        await _pump(tester);
        expect(find.byTooltip(_strings.mailDiscardDraft), findsNothing);
        await tester.tap(action);
        await _pump(tester);
        expect(find.byType(StudioMailComposeDialog), findsOneWidget);
        expect(find.text(_strings.mailRetryAcknowledgement), findsNothing);
        expect(
          tester.widget<TextField>(_field(_strings.subject)).controller!.text,
          '${forward ? 'Fwd' : 'Re'}: First message',
        );
        expect(client.sent, hasLength(1));
        await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
        await tester.tap(find.text(_strings.mailDraftSaveClose));
        await _pump(tester);
        await _close(tester);
      },
    );
  }

  testWidgets(
    'mark-read holds the UI busy and updates only after confirmation',
    (tester) async {
      final client = _Client();
      final gate = Completer<void>();
      final loader = _Loader(client)..onMarkRead = (_, _) => gate.future;
      await _open(tester, (_) => client, loaderFactory: (_) => loader);
      await _connect(tester);
      await tester.tap(find.text('First message'));
      await _pump(tester);
      final action = tester
          .widget<IconButton>(_iconButton(_strings.markRead))
          .onPressed!;
      action();
      action();
      await _pump(tester);
      expect(loader.marked, hasLength(1));
      expect(loader.marked.single.$1, isNot(same(client.selectedMailbox)));
      expect(loader.marked.single.$1.uidValidity, 41);
      expect(loader.marked.single.$2.uid, 7);
      expect(client.messages.first.isSeen, isFalse);
      expect(
        tester.widget<IconButton>(_iconButton(_strings.markRead)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Archive'));
      await _pump(tester);
      expect(client.selections, 0);

      gate.complete();
      await _pump(tester);
      expect(client.messages.first.isSeen, isTrue);
      expect(
        tester.widget<IconButton>(_iconButton(_strings.markRead)).onPressed,
        isNull,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(_strings.mailMarkReadFailed), findsNothing);
      await _close(tester);
    },
  );

  testWidgets('failed mark-read preserves unread status with fixed feedback', (
    tester,
  ) async {
    final client = _Client();
    final loader = _Loader(client)
      ..onMarkRead = (_, _) async =>
          throw StateError('private response session-password');
    await _open(tester, (_) => client, loaderFactory: (_) => loader);
    await _connect(tester);
    await tester.tap(find.text('First message'));
    await _pump(tester);
    await tester.tap(find.byTooltip(_strings.markRead));
    await _pump(tester);
    expect(client.messages.first.isSeen, isFalse);
    expect(loader.marked, hasLength(1));
    expect(find.text(_strings.mailMarkReadFailed), findsOneWidget);
    expect(find.textContaining('private response'), findsNothing);
    expect(
      tester.widget<IconButton>(_iconButton(_strings.markRead)).onPressed,
      isNotNull,
    );
    await _close(tester);
  });

  testWidgets('failed mark-read allows an explicit successful retry', (
    tester,
  ) async {
    final client = _Client();
    final firstGate = Completer<void>();
    final retryGate = Completer<void>();
    var attempts = 0;
    final loader = _Loader(client)
      ..onMarkRead = (_, _) =>
          ++attempts == 1 ? firstGate.future : retryGate.future;
    await _open(tester, (_) => client, loaderFactory: (_) => loader);
    await _connect(tester);
    await tester.tap(find.text('First message'));
    await _pump(tester);
    final reader = _reader(tester);
    await tester.tap(find.byTooltip(_strings.markRead));
    await _pump(tester);
    expect(loader.marked, hasLength(1));
    expect(client.messages.first.isSeen, isFalse);

    firstGate.completeError(StateError('private first-write response'));
    await _pump(tester);
    expect(client.messages.first.isSeen, isFalse);
    expect(loader.marked, hasLength(1));
    expect(find.text(_strings.mailMarkReadFailed), findsOneWidget);
    expect(find.textContaining('private first-write response'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.widget<IconButton>(_iconButton(_strings.markRead)).onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip(_strings.markRead));
    await _pump(tester);
    expect(loader.marked, hasLength(2));
    expect(attempts, 2);
    expect(client.messages.first.isSeen, isFalse);
    expect(find.text(_strings.mailMarkReadFailed), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<IconButton>(_iconButton(_strings.markRead)).onPressed,
      isNull,
    );
    for (final (mailbox, header) in loader.marked) {
      expect(mailbox.path, 'INBOX');
      expect(mailbox.uidValidity, 41);
      expect(header.uid, 7);
    }

    retryGate.complete();
    await _pump(tester);
    expect(client.messages.first.isSeen, isTrue);
    expect(client.messages[1].isSeen, isFalse);
    expect(loader.marked, hasLength(2));
    expect(_reader(tester), same(reader));
    expect(reader.isDisposed, isFalse);
    expect(find.text(_strings.mailMarkReadFailed), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('mark-read completion cannot mark a header whose UID changed', (
    tester,
  ) async {
    final client = _Client();
    final gate = Completer<void>();
    final loader = _Loader(client)..onMarkRead = (_, _) => gate.future;
    await _open(tester, (_) => client, loaderFactory: (_) => loader);
    await _connect(tester);
    await tester.tap(find.text('First message'));
    await _pump(tester);
    await tester.tap(find.byTooltip(_strings.markRead));
    await _pump(tester);
    client.messages.first.uid = 800;
    gate.complete();
    await _pump(tester);
    expect(client.messages.first.isSeen, isFalse);
    expect(find.text(_strings.mailMarkReadFailed), findsOneWidget);
    await _close(tester);
  });

  for (final fail in [false, true]) {
    testWidgets(
      'mark-read late ${fail ? 'failure' : 'success'} cannot mutate a disconnected session',
      (tester) async {
        final first = _Client();
        final second = _Client();
        final clients = [first, second];
        final gate = Completer<void>();
        final loader = _Loader(first)..onMarkRead = (_, _) => gate.future;
        await _open(
          tester,
          (_) => clients.removeAt(0),
          loaderFactory: (client) =>
              identical(client, first) ? loader : _Loader(client),
        );
        await _connect(tester);
        await tester.tap(find.text('First message'));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.markRead));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.disconnect));
        await _pump(tester);
        await _connect(tester);
        if (fail) {
          gate.completeError(StateError('late mark-read failure'));
        } else {
          gate.complete();
        }
        await _pump(tester);
        expect(loader.disposed, isTrue);
        expect(first.messages.first.isSeen, isFalse);
        expect(second.messages.first.isSeen, isFalse);
        expect(find.text(_strings.mailMarkReadFailed), findsNothing);
        expect(find.textContaining('late mark-read failure'), findsNothing);
        expect(find.byType(MailMessageView), findsNothing);
        expect(find.text('First message'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _close(tester);
      },
    );

    testWidgets(
      'mark-read late ${fail ? 'failure' : 'success'} preserves a replacement pending request',
      (tester) async {
        final first = _Client();
        final second = _Client();
        second.messages[0] = _message('Replacement message')..uid = 17;
        final clients = [first, second];
        final firstGate = Completer<void>();
        final secondGate = Completer<void>();
        final firstLoader = _Loader(first)
          ..onMarkRead = (_, _) => firstGate.future;
        final secondLoader = _Loader(second)
          ..onMarkRead = (_, _) => secondGate.future;
        await _open(
          tester,
          (_) => clients.removeAt(0),
          loaderFactory: (client) =>
              identical(client, first) ? firstLoader : secondLoader,
        );
        await _connect(tester);
        await tester.tap(find.text('First message'));
        await _pump(tester);
        final firstReader = _reader(tester);
        await tester.tap(find.byTooltip(_strings.markRead));
        await _pump(tester);
        expect(firstLoader.marked, hasLength(1));

        await tester.tap(find.byTooltip(_strings.disconnect));
        await _pump(tester);
        await _connect(tester);
        await tester.tap(find.text('Replacement message'));
        await _pump(tester);
        final secondReader = _reader(tester);
        final secondAction = tester
            .widget<IconButton>(_iconButton(_strings.markRead))
            .onPressed!;
        secondAction();
        await _pump(tester);
        expect(secondLoader.marked, hasLength(1));
        expect(secondLoader.marked.single.$2.uid, 17);
        expect(secondGate.isCompleted, isFalse);

        if (fail) {
          firstGate.completeError(StateError('private stale-write response'));
        } else {
          firstGate.complete();
        }
        await _pump(tester);
        expect(firstLoader.disposed, isTrue);
        expect(firstReader.isDisposed, isTrue);
        expect(secondLoader.disposed, isFalse);
        expect(_reader(tester), same(secondReader));
        expect(secondReader.isDisposed, isFalse);
        expect(first.messages.first.isSeen, isFalse);
        expect(second.messages.first.isSeen, isFalse);
        expect(find.text(_strings.mailMarkReadFailed), findsNothing);
        expect(
          find.textContaining('private stale-write response'),
          findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          tester.widget<IconButton>(_iconButton(_strings.markRead)).onPressed,
          isNull,
        );

        // A stale completion must not release the replacement operation's busy
        // ownership, even to an activation captured before the new request.
        secondAction();
        await tester.tap(find.text('Archive'));
        await _pump(tester);
        expect(secondLoader.marked, hasLength(1));
        expect(second.selections, 0);
        expect(secondGate.isCompleted, isFalse);
        expect(second.messages.first.isSeen, isFalse);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        secondGate.complete();
        await _pump(tester);
        expect(first.messages.first.isSeen, isFalse);
        expect(second.messages.first.isSeen, isTrue);
        expect(firstLoader.marked, hasLength(1));
        expect(secondLoader.marked, hasLength(1));
        expect(_reader(tester), same(secondReader));
        expect(find.text(_strings.mailMarkReadFailed), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await _close(tester);
      },
    );
  }

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
    expect(find.text(_strings.mailAccountStorageNotice), findsOneWidget);
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

  testWidgets('an untouched form loads the saved account and TLS choice', (
    tester,
  ) async {
    final store = _CredentialStore()..saved = _savedCredentials;
    await _open(
      tester,
      (_) => _Client(),
      credentialStore: store,
      fillForm: false,
    );
    expect(
      tester.widget<TextField>(_field(_strings.emailAddress)).controller!.text,
      _savedCredentials.email,
    );
    expect(
      tester.widget<TextField>(_field(_strings.password)).controller!.text,
      _savedCredentials.password,
    );
    expect(
      tester.widget<TextField>(_field(_strings.imapHost)).controller!.text,
      _savedCredentials.imapHost,
    );
    expect(
      tester.widget<TextField>(_field(_strings.smtpHost)).controller!.text,
      _savedCredentials.smtpHost,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, _strings.useStartTls),
          )
          .value,
      isTrue,
    );
    expect(find.text(_strings.forgetAccount), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a delayed saved account never overwrites edited fields', (
    tester,
  ) async {
    final loaded = Completer<StudioMailCredentials?>();
    final store = _CredentialStore()..onLoad = () => loaded.future;
    mail.MailAccount? connected;
    await _open(tester, (account) {
      connected = account;
      return _Client();
    }, credentialStore: store);
    loaded.complete(_savedCredentials);
    await _pump(tester);
    expect(
      tester.widget<TextField>(_field(_strings.emailAddress)).controller!.text,
      'reader@example.invalid',
    );
    expect(
      tester.widget<TextField>(_field(_strings.password)).controller!.text,
      'session-password',
    );
    expect(
      tester.widget<TextField>(_field(_strings.imapHost)).controller!.text,
      'imap.example.invalid',
    );
    expect(
      tester.widget<TextField>(_field(_strings.smtpHost)).controller!.text,
      'smtp.example.invalid',
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, _strings.useStartTls),
          )
          .value,
      isFalse,
    );
    await _connect(tester);
    expect(connected!.email, 'reader@example.invalid');
    expect(connected!.incoming.serverConfig.port, 993);
    expect(store.writes.single.password, 'session-password');
    await _close(tester);
  });

  testWidgets('a delayed saved account cannot enter a started session', (
    tester,
  ) async {
    final loaded = Completer<StudioMailCredentials?>();
    final store = _CredentialStore()..onLoad = () => loaded.future;
    final client = _Client();
    await _open(tester, (_) => client, credentialStore: store);
    await _connect(tester);
    loaded.complete(_savedCredentials);
    await _pump(tester);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await _pump(tester);
    expect(
      tester.widget<TextField>(_field(_strings.emailAddress)).controller!.text,
      'reader@example.invalid',
    );
    expect(
      tester.widget<TextField>(_field(_strings.password)).controller!.text,
      isEmpty,
    );
    expect(client.connects, 1);
    await _close(tester);
  });

  testWidgets('a failed keychain save keeps Mail connected with fixed feedback', (
    tester,
  ) async {
    final store = _CredentialStore()
      ..onSave = (_) async =>
          throw StateError('private-keychain-reply saved-fixture-password');
    final client = _Client();
    await _open(tester, (_) => client, credentialStore: store);
    await _connect(tester);
    expect(find.text('First message'), findsOneWidget);
    expect(find.text(_strings.mailAccountSaveFailed), findsOneWidget);
    expect(find.textContaining('private-keychain-reply'), findsNothing);
    expect(find.text(_strings.mailConnectionFailed), findsNothing);
    expect(client.disconnects, 0);
    await tester.tap(find.byTooltip(_strings.disconnect));
    await _pump(tester);
    // Forget remains available for unreadable or still-pending keychain records.
    expect(find.text(_strings.forgetAccount), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a failed keychain deletion remains visible and can be retried', (
    tester,
  ) async {
    final store = _CredentialStore()
      ..saved = _savedCredentials
      ..onClear = () async => false;
    await _open(
      tester,
      (_) => _Client(),
      credentialStore: store,
      fillForm: false,
    );
    await tester.ensureVisible(find.text(_strings.forgetAccount));
    await tester.tap(find.text(_strings.forgetAccount));
    await _pump(tester);
    expect(find.text(_strings.mailAccountForgetFailed), findsOneWidget);
    expect(find.text(_strings.forgetAccount), findsOneWidget);
    expect(store.saved, same(_savedCredentials));
    store.onClear = () async => true;
    await tester.ensureVisible(find.text(_strings.forgetAccount));
    await tester.tap(find.text(_strings.forgetAccount));
    await _pump(tester);
    expect(store.clears, 2);
    expect(store.saved, isNull);
    // Forget remains available for unreadable or still-pending keychain records.
    expect(find.text(_strings.forgetAccount), findsOneWidget);
    expect(find.text(_strings.mailAccountForgetFailed), findsNothing);
    await _close(tester);
  });

  testWidgets('remember-off reports a failed deletion without losing Mail', (
    tester,
  ) async {
    final store = _CredentialStore()
      ..saved = _savedCredentials
      ..onClear = () async => false;
    final client = _Client();
    await _open(tester, (_) => client, credentialStore: store, fillForm: false);
    await tester.ensureVisible(find.text(_strings.rememberAccount));
    await tester.tap(find.text(_strings.rememberAccount));
    await _pump(tester);
    await _connect(tester);
    expect(store.writes, isEmpty);
    expect(store.clears, 1);
    expect(store.saved, same(_savedCredentials));
    expect(find.text(_strings.mailAccountForgetFailed), findsOneWidget);
    expect(find.text('First message'), findsOneWidget);
    expect(client.disconnects, 0);
    await _close(tester);
  });

  testWidgets(
    'an old keychain save cannot publish into a replacement session',
    (tester) async {
      final saved = Completer<bool>();
      final store = _CredentialStore()
        ..onSave = (credentials) =>
            credentials.email == 'reader@example.invalid'
            ? saved.future
            : Future<bool>.value(true);
      final first = _Client();
      final second = _Client();
      final clients = [first, second];
      await _open(tester, (_) => clients.removeAt(0), credentialStore: store);
      await _connect(tester);
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      await tester.enterText(
        _field(_strings.emailAddress),
        'replacement@example.invalid',
      );
      await _connect(tester);
      saved.complete(false);
      await _pump(tester);
      expect(find.text(_strings.mailAccountSaveFailed), findsNothing);
      expect(find.text('First message'), findsOneWidget);
      expect(store.saved!.email, 'replacement@example.invalid');
      expect(first.disconnects, 1);
      expect(second.disconnects, 0);
      await _close(tester);
    },
  );

  testWidgets('late keychain failure preserves the SMTP acceptance receipt', (
    tester,
  ) async {
    final saved = Completer<bool>();
    final store = _CredentialStore()..onSave = (_) => saved.future;
    await _open(tester, (_) => _Client(), credentialStore: store);
    await _connect(tester);
    await _compose(tester);
    expect(find.text(_strings.mailSubmissionAccepted), findsOneWidget);
    saved.complete(false);
    await _pump(tester);
    expect(find.text(_strings.mailSubmissionAccepted), findsOneWidget);
    expect(find.text(_strings.mailAccountSaveFailed), findsOneWidget);
    expect(find.byTooltip(_strings.mailDiscardDraft), findsNothing);
    await _close(tester);
  });

  testWidgets(
    'manual STARTTLS is selected before the only connection attempt',
    (tester) async {
      mail.MailAccount? connected;
      final client = _Client();
      await _open(tester, (account) {
        connected = account;
        return client;
      });
      await tester.ensureVisible(find.text(_strings.useStartTls));
      await tester.tap(find.text(_strings.useStartTls));
      await _pump(tester);
      await _connect(tester);
      expect(connected!.incoming.serverConfig.port, 143);
      expect(
        connected!.incoming.serverConfig.socketType,
        mail.SocketType.starttls,
      );
      expect(connected!.outgoing.serverConfig.port, 587);
      expect(
        connected!.outgoing.serverConfig.socketType,
        mail.SocketType.starttls,
      );
      expect(client.connects, 1);
      await _close(tester);
    },
  );

  testWidgets('mailbox.org uses verified STARTTLS settings without discovery', (
    tester,
  ) async {
    mail.MailAccount? connected;
    final client = _Client();
    await _open(tester, (account) {
      connected = account;
      return client;
    }, accountDiscovery: (_) async => throw StateError('Unexpected discovery'));
    await tester.enterText(_field(_strings.emailAddress), 'reader@MAILBOX.ORG');
    await tester.tap(find.text(_strings.manualServers));
    await _pump(tester);
    await _connect(tester);
    expect(connected!.incoming.serverConfig.hostname, 'imap.mailbox.org');
    expect(connected!.incoming.serverConfig.port, 143);
    expect(
      connected!.incoming.serverConfig.socketType,
      mail.SocketType.starttls,
    );
    expect(connected!.outgoing.serverConfig.hostname, 'smtp.mailbox.org');
    expect(connected!.outgoing.serverConfig.port, 587);
    expect(
      connected!.outgoing.serverConfig.socketType,
      mail.SocketType.starttls,
    );
    expect(client.connects, 1);
    expect(find.text('First message'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('native credential preflight rejects before authentication', (
    tester,
  ) async {
    final client = _Client();
    final store = _CredentialStore();
    await _open(
      tester,
      (_) => client,
      credentialStore: store,
      nativeLoader: true,
    );
    await tester.enterText(_field(_strings.password), '');
    await _connect(tester);
    expect(client.connects, 0);
    expect(client.lists, 0);
    expect(store.writes, isEmpty);
    expect(find.text(_strings.mailConnectionFailed), findsOneWidget);
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
          if (phase == 'connect') {
            expect(client.connects, 1);
            expect(client.lists, 0);
          }
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

  testWidgets('a nonselectable INBOX falls back to a selectable mailbox', (
    tester,
  ) async {
    final client = _Client();
    client.boxes[0] = mail.Mailbox(
      encodedName: 'INBOX',
      encodedPath: 'INBOX',
      flags: <mail.MailboxFlag>[
        mail.MailboxFlag.inbox,
        mail.MailboxFlag.noSelect,
      ],
      pathSeparator: '/',
    );
    await _open(tester, (_) => client);
    await _connect(tester);
    expect(client.selectedMailbox!.path, 'Archive');
    expect(find.text('First message'), findsOneWidget);
    await _close(tester);
  });

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

  testWidgets(
    'SMTP recipient groups stay in the envelope and survive acknowledged retry',
    (tester) async {
      final client = _Client()
        ..onSend = (_) async => throw StateError('controlled send uncertainty');
      await _open(tester, (_) => client);
      await _connect(tester);
      await tester.tap(find.widgetWithText(TextButton, _strings.compose));
      await _pump(tester);
      await tester.enterText(
        _field(_strings.to),
        'primary@Example.invalid; second@example.invalid',
      );
      await tester.tap(find.text(_strings.mailCopyRecipients));
      await _pump(tester);
      await tester.enterText(
        _field(_strings.mailCc),
        'primary@example.invalid, copy@example.invalid',
      );
      await tester.enterText(
        _field(_strings.mailBcc),
        'copy@example.invalid; hidden@example.invalid',
      );
      await tester.enterText(_field(_strings.subject), 'Recipient privacy');
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller
          .insertText('A controlled local host fixture.');
      final send = find.widgetWithText(FilledButton, _strings.send);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(client.sent, hasLength(1));
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, _strings.compose));
      await _pump(tester);
      expect(
        tester.widget<TextField>(_field(_strings.mailCc)).controller!.text,
        'primary@example.invalid, copy@example.invalid',
      );
      expect(
        tester.widget<TextField>(_field(_strings.mailBcc)).controller!.text,
        'copy@example.invalid; hidden@example.invalid',
      );
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(client.sent, hasLength(1));
      client.onSend = null;
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await _pump(tester);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(client.sent, hasLength(2));
      expect(client.appendRequests, <bool>[false, false]);
      for (var index = 0; index < client.sent.length; index++) {
        final message = client.sent[index];
        expect(client.recipientLists[index]!.map((entry) => entry.email), [
          'primary@Example.invalid',
          'second@example.invalid',
          'copy@example.invalid',
          'hidden@example.invalid',
        ]);
        expect(message.to!.map((entry) => entry.email), [
          'primary@Example.invalid',
          'second@example.invalid',
        ]);
        expect(message.cc!.map((entry) => entry.email), [
          'copy@example.invalid',
        ]);
        expect(message.bcc, isEmpty);
        expect(
          message.renderMessage(),
          isNot(contains('hidden@example.invalid')),
        );
      }
      expect(tester.takeException(), isNull);
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
    await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
    await tester.tap(find.text(_strings.mailDraftSaveClose));
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
        await tester.ensureVisible(find.text(strings.mailDraftSaveClose));
        await tester.tap(find.text(strings.mailDraftSaveClose));
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
    await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
    await tester.tap(find.text(_strings.mailDraftSaveClose));
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
      expect(find.text(strings.mailAccountStorageNotice), findsOneWidget);
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

  testWidgets(
    'IMAP archive action stores the loaded original with Bcc and attachments without touching the mailbox',
    (tester) async {
      final client = _Client();
      final raw = Uint8List.fromList(
        utf8.encode(
          [
            'From: Original <original@example.invalid>',
            'To: Reader <reader@example.invalid>',
            'Bcc: Hidden <hidden@example.invalid>',
            'Subject: Full MIME original, not the fetched header',
            'X-Preserved:  unusual',
            '\tspacing',
            'MIME-Version: 1.0',
            'Content-Type: multipart/mixed; boundary=archive-fixture',
            '',
            '--archive-fixture',
            'Content-Type: text/plain; charset=utf-8',
            '',
            'Exact original body.',
            '--archive-fixture',
            'Content-Type: application/octet-stream',
            'Content-Disposition: attachment; filename=original.bin',
            'Content-Transfer-Encoding: base64',
            '',
            'AAEC/w0K',
            '--archive-fixture--',
            '',
          ].join('\r\n'),
        ),
      );
      late _Loader loader;
      MailMessage? archived;
      var archiveCalls = 0;
      MailArchiveOrigin? provenance;
      await _open(
        tester,
        (_) => client,
        loaderFactory: (value) =>
            loader = _Loader(value)..onFetch = (_, _) async => raw,
        archiveWriter: (message, {required origin, cancellation}) async {
          archiveCalls++;
          archived = message;
          provenance = origin;
          return _archiveSuccess(message);
        },
      );
      await _connect(tester);
      expect(archived, isNull);
      await tester.tap(find.text('First message'));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.archiveCurrentMessage));
      await _pump(tester);
      expect(archived!.raw.bytes, orderedEquals(raw));
      expect(
        archived!.envelope.subject,
        'Full MIME original, not the fetched header',
      );
      expect(archived!.envelope.bcc.single.address, 'hidden@example.invalid');
      expect(archived!.attachments.single.displayName, 'original.bin');
      expect(
        archived!.attachments.single.content.bytes,
        orderedEquals([0, 1, 2, 255, 13, 10]),
      );
      expect(provenance!.source, 'reader@example.invalid');
      expect(provenance!.folder, 'INBOX');
      expect(provenance!.sourceMessageId, 'imap:41:7');
      expect(loader.marked, isEmpty);
      expect(client.sent, isEmpty);
      expect(client.selections, 0);
      expect(client.fetches, 1);
      expect(archiveCalls, 1);
      expect(find.text(_strings.archiveMessageStored), findsWidgets);
      await _close(tester);
    },
  );

  testWidgets(
    'disconnecting IMAP cancels a pending archive and suppresses its late feedback',
    (tester) async {
      final client = _Client();
      final saved = Completer<MailResult<MailArchiveImportResult>>();
      MailCancellationToken? token;
      await _open(
        tester,
        (_) => client,
        archiveWriter: (message, {required origin, cancellation}) {
          token = cancellation;
          return saved.future;
        },
      );
      await _connect(tester);
      await tester.tap(find.text('First message'));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.archiveCurrentMessage));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      expect(token!.isCancelled, isTrue);
      saved.complete(
        const MailFailure(MailProblem(MailProblemCode.permissionDenied)),
      );
      await _pump(tester);
      expect(
        find.text(_strings.archiveProblem(MailProblemCode.permissionDenied)),
        findsNothing,
      );
      expect(find.byType(StudioArchiveMessageButton), findsNothing);
      expect(client.sent, isEmpty);
      expect(client.disconnects, 1);
      await _close(tester);
    },
  );

  testWidgets('IMAP folder archiving requires an explicit loader capability', (
    tester,
  ) async {
    await _open(tester, (_) => _Client());
    await _connect(tester);
    expect(find.byType(StudioArchiveFolderButton), findsNothing);
    await _close(tester);
  });

  testWidgets(
    'IMAP selected-folder action freezes source and folder without changing the mailbox',
    (tester) async {
      final client = _Client();
      late _ArchivingLoader loader;
      MailArchiveProfile? profile;
      var runs = 0;
      await _open(
        tester,
        (_) => client,
        loaderFactory: (client) => loader = _ArchivingLoader(client),
        archiveFolderWriter:
            (
              value, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) async {
              runs++;
              profile = value;
              return _folderReport();
            },
      );
      await _connect(tester);
      await tester.tap(find.byTooltip(_strings.archiveSelectedFolder));
      await _pump(tester);
      expect(runs, 0);
      await tester.tap(find.byKey(const ValueKey('archive-folder-start')));
      await _pump(tester);
      expect(runs, 1);
      expect(profile!.source, 'reader@example.invalid');
      expect(profile!.folder, 'INBOX');
      expect(profile!.kind, MailArchiveProfileKind.mailbox);
      expect(profile!.includeSubfolders, isFalse);
      expect(profile!.indexAttachmentText, isFalse);
      expect(profile!.id, startsWith('studio-mailbox:'));
      expect(loader.marked, isEmpty);
      expect(client.sent, isEmpty);
      expect(client.selections, 0);
      expect(client.fetches, 1);
      expect(
        find.text(_strings.archiveFolderCounts(3, 1, 0, 2, 300)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('archive-folder-close')));
      await _pump(tester);
      await _close(tester);
    },
  );
}
