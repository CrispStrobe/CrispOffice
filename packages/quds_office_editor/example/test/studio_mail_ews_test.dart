import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/studio_mail_archive_action.dart';
import 'package:quds_office_studio/studio_mail_archive_folder_action.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

final class _Provider extends Fake implements MailEwsProvider {
  _Provider(this.configuration, this.credentials);
  final MailEwsConfiguration configuration;
  final MailCredentialStore credentials;
  Completer<MailResult<MailCapabilities>>? connectGate;
  Completer<MailResult<MailMessage>>? messageGate;
  Completer<MailSubmissionResult>? sendGate;
  MailSubmissionOutcome outcome = MailSubmissionOutcome.accepted;
  MailCapabilities supported = MailCapabilities(const [
    MailCapability.mail,
    MailCapability.folders,
    MailCapability.send,
    MailCapability.move,
  ]);
  MailProblem? mutationProblem;
  bool failConnection = false;
  int connects = 0;
  int lists = 0;
  int reads = 0;
  String firstMessageId = 'one';
  final List<MailCursor?> cursors = [];
  final List<MailOperation> commands = [];
  final List<MailPreparedMessage> submissions = [];
  final List<String> attempts = [];
  MailOperationLease? lastLease;

  @override
  MailAccountId get account => configuration.account;
  MailMailboxId box(String name) => MailMailboxId(name, account: account);
  MailOpaqueIdentity identity(String id) => MailOpaqueIdentity(
    account: account,
    provider: MailProviderKind.ews,
    value: id,
  );

  MailHeaderRecord header(String id, String subject) => MailHeaderRecord(
    id: MailMessageId(id),
    remote: identity(id),
    envelope: MailEnvelope(
      subject: subject,
      from: [const MailAddress('writer@example.test')],
    ),
    flags: const MailMessageFlags(),
  );

  MailMessage message() {
    final bytes = utf8.encode(
      'From: Writer <writer@example.test>\r\n'
      'To: Reader <reader@example.test>\r\nSubject: First Exchange message\r\n'
      'Bcc: hidden@example.test\r\nX-Preserved:  original\r\n\tfolding\r\n'
      'MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=fixture\r\n'
      '\r\n--fixture\r\nContent-Type: text/plain; charset=utf-8\r\n'
      '\r\nA message from Exchange.\r\n'
      '--fixture\r\nContent-Type: application/octet-stream\r\n'
      'Content-Disposition: attachment; filename=example.txt\r\n'
      'Content-Transfer-Encoding: base64\r\n\r\nZXhhbXBsZQ==\r\n'
      '--fixture--\r\n',
    );
    final parsed = const QudsMimeCodec().parse(bytes).message!;
    return MailMessage(
      raw: parsed.raw,
      envelope: parsed.envelope,
      body: parsed.body,
      attachments: parsed.attachments,
      remoteIdentity: identity(firstMessageId),
      localId: MailMessageId(firstMessageId),
    );
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async {
    connects++;
    lastLease = lease;
    if (failConnection) throw StateError('private-password-and-server-text');
    return connectGate == null
        ? MailSuccess(supported)
        : await connectGate!.future;
  }

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async {
    lists++;
    lastLease = lease;
    return MailSuccess([
      MailMailbox(id: box('inbox'), displayName: 'Inbox'),
      MailMailbox(id: box('archive'), displayName: 'Archive'),
    ]);
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    cursors.add(cursor);
    lastLease = lease;
    expect(limit, 50);
    if (mailbox.value == 'archive') {
      return MailSuccess(
        MailHeaderPage(
          messages: [header('archive-message', 'Archived message')],
        ),
      );
    }
    return MailSuccess(
      MailHeaderPage(
        messages: [
          cursor == null
              ? header(firstMessageId, 'First Exchange message')
              : header('two', 'Second Exchange message'),
        ],
        next: cursor == null
            ? MailCursor(mailbox: mailbox, value: 'next-page')
            : null,
      ),
    );
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    reads++;
    lastLease = lease;
    return messageGate == null
        ? MailSuccess(message())
        : await messageGate!.future;
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async {
    commands.add(operation);
    lastLease = lease;
    return mutationProblem == null
        ? const MailSuccess(MailUnit.value)
        : MailFailure(mutationProblem!);
  }

  @override
  Future<MailSubmissionResult> submit(
    MailPreparedMessage message, {
    required String attemptId,
    required MailOperationLease lease,
  }) async {
    submissions.add(message);
    attempts.add(attemptId);
    lastLease = lease;
    return sendGate == null
        ? MailSubmissionResult(attemptId: attemptId, outcome: outcome)
        : await sendGate!.future;
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Finder _field(String key) => find.byKey(ValueKey(key));
Finder _iconButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

Future<void> _show(
  WidgetTester tester,
  StudioEwsProviderFactory factory, {
  Size size = const Size(1280, 900),
  StudioMailArchiveWriter? archiveWriter,
  StudioMailArchiveFolderWriter? archiveFolderWriter,
}) async {
  tester.view
    ..physicalSize = size
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
              builder: (_) => StudioMailEwsDialog(
                strings: _strings,
                providerFactory: factory,
                archiveWriter: archiveWriter,
                archiveFolderWriter: archiveFolderWriter,
              ),
            ),
            child: const Text('Open Exchange'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Exchange'));
  await _pump(tester);
}

Future<void> _settings(
  WidgetTester tester, {
  String endpoint = 'https://mail.example.test/EWS/Exchange.asmx',
}) async {
  await tester.enterText(_field('ews-endpoint'), endpoint);
  await tester.enterText(_field('ews-mailbox'), 'reader@example.test');
  await tester.enterText(_field('ews-login'), r'EXAMPLE\reader');
  await tester.enterText(_field('ews-password'), 'ephemeral-test-password');
  await tester.ensureVisible(_field('ews-connect'));
  await _pump(tester);
}

Future<void> _connect(WidgetTester tester) async {
  await _settings(tester);
  await tester.tap(_field('ews-connect'));
  await _pump(tester);
}

Finder _composerField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _compose(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_strings.compose));
  await _pump(tester);
  await tester.enterText(_composerField(_strings.to), 'recipient@example.test');
  await tester.enterText(_composerField(_strings.subject), 'EWS send');
  tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller
      .insertText('Composed in the existing Word editor.');
  await tester.pump();
  await tester.ensureVisible(find.widgetWithText(FilledButton, _strings.send));
  await tester.tap(find.widgetWithText(FilledButton, _strings.send));
  await _pump(tester);
}

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
  testWidgets('native account setup exposes the Exchange Server entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: StudioMailDialog(strings: _strings)),
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-open-ews')));
    await _pump(tester);
    expect(find.byType(StudioMailEwsDialog), findsOneWidget);
    expect(_field('ews-endpoint'), findsOneWidget);
    expect(find.text(_strings.ewsNtlm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual NTLM connection loads bounded headers and clears the password field',
    (tester) async {
      late _Provider provider;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials),
      );
      await _settings(tester);
      final password = tester
          .widget<TextField>(_field('ews-password'))
          .controller!;
      await tester.tap(_field('ews-connect'));
      await _pump(tester);
      expect(provider.configuration.authentication, MailEwsAuthentication.ntlm);
      expect(provider.configuration.username, r'EXAMPLE\reader');
      expect(provider.configuration.mailboxAddress, 'reader@example.test');
      expect(provider.configuration.endpoint.host, 'mail.example.test');
      expect(password.text, isEmpty);
      expect(provider.connects, 1);
      expect(provider.lists, 1);
      expect(provider.reads, 0);
      expect(provider.commands, isEmpty);
      expect(find.text('First Exchange message'), findsOneWidget);
      await tester.tap(_field('ews-load-more'));
      await _pump(tester);
      expect(provider.cursors.last?.value, 'next-page');
      expect(find.text('Second Exchange message'), findsOneWidget);
      expect(_field('ews-load-more'), findsNothing);
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      expect(
        reader.result.message!.body.plainText,
        contains('A message from Exchange.'),
      );
      expect(
        reader.result.message!.attachments.single.displayName,
        'example.txt',
      );
      expect(find.textContaining('example.txt'), findsOneWidget);
      expect(
        provider.commands,
        isEmpty,
        reason: 'Opening a message must not mark it read implicitly.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit read, flag and move actions use the EWS provider', (
    tester,
  ) async {
    late _Provider provider;
    await _show(
      tester,
      (configuration, credentials) =>
          provider = _Provider(configuration, credentials),
    );
    await _connect(tester);
    await tester.tap(find.text('First Exchange message'));
    await _pump(tester);
    await tester.tap(find.byTooltip(_strings.markRead));
    await _pump(tester);
    expect(
      provider.commands.single,
      isA<MailSetRead>().having((c) => c.read, 'read', true),
    );
    expect(find.byTooltip(_strings.ewsMarkUnread), findsOneWidget);
    await tester.tap(find.byTooltip(_strings.ewsFlag));
    await _pump(tester);
    expect(
      provider.commands.last,
      isA<MailSetFlagged>().having((c) => c.flagged, 'flagged', true),
    );
    await tester.tap(find.byTooltip(_strings.ewsMove));
    await _pump(tester);
    await tester.tap(
      find.widgetWithText(PopupMenuItem<MailMailbox>, 'Archive'),
    );
    await _pump(tester);
    expect(
      provider.commands.last,
      isA<MailMove>().having(
        (c) => c.destination.value,
        'destination',
        'archive',
      ),
    );
    expect(find.byType(MailMessageView), findsNothing);
    expect(find.text('First Exchange message'), findsNothing);
    expect(_field('ews-load-more'), findsNothing);
    expect(find.text(_strings.ewsFolderChanged), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Basic authentication is available only by explicit selection', (
    tester,
  ) async {
    late _Provider provider;
    await _show(
      tester,
      (configuration, credentials) =>
          provider = _Provider(configuration, credentials),
    );
    await _settings(tester);
    await tester.tap(find.text(_strings.ewsNtlm));
    await _pump(tester);
    await tester.tap(find.text(_strings.ewsBasic).last);
    await _pump(tester);
    await tester.tap(_field('ews-connect'));
    await _pump(tester);
    expect(provider.configuration.authentication, MailEwsAuthentication.basic);
    expect(find.text('First Exchange message'), findsOneWidget);
  });

  testWidgets(
    'read-only capabilities disable submission, reply and move actions',
    (tester) async {
      late _Provider provider;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials)
              ..supported = MailCapabilities(const [
                MailCapability.mail,
                MailCapability.folders,
              ]),
      );
      await _connect(tester);
      expect(
        tester.widget<IconButton>(_iconButton(_strings.compose)).onPressed,
        isNull,
      );
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      expect(
        tester.widget<IconButton>(_iconButton(_strings.reply)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_iconButton(_strings.forward)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<PopupMenuButton<MailMailbox>>(
              find.byType(PopupMenuButton<MailMailbox>),
            )
            .enabled,
        isFalse,
      );
      expect(provider.submissions, isEmpty);
      expect(provider.commands, isEmpty);
    },
  );

  testWidgets(
    'delete requires explicit confirmation before moving to Deleted Items',
    (tester) async {
      late _Provider provider;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials),
      );
      await _connect(tester);
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.ewsDelete));
      await _pump(tester);
      expect(provider.commands, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
      await _pump(tester);
      expect(provider.commands, isEmpty);
      await tester.tap(find.byTooltip(_strings.ewsDelete));
      await _pump(tester);
      await tester.tap(find.widgetWithText(FilledButton, _strings.ewsDelete));
      await _pump(tester);
      expect(provider.commands.single, isA<MailDelete>());
      expect(find.byType(MailMessageView), findsNothing);
      expect(find.text('First Exchange message'), findsNothing);
    },
  );

  testWidgets(
    'failed write confirmation requires refresh before another change',
    (tester) async {
      late _Provider provider;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials),
      );
      await _connect(tester);
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      provider.mutationProblem = const MailProblem(MailProblemCode.conflict);
      await tester.tap(find.byTooltip(_strings.markRead));
      await _pump(tester);
      expect(find.text(_strings.ewsMutationFailed), findsOneWidget);
      final flag = tester.widget<IconButton>(_iconButton(_strings.ewsFlag));
      expect(flag.onPressed, isNull);
      expect(
        tester.widget<TextButton>(_field('ews-load-more')).onPressed,
        isNull,
      );
      final pagesBefore = provider.cursors.length;
      await tester.tap(_field('ews-load-more'));
      await _pump(tester);
      expect(provider.cursors, hasLength(pagesBefore));
      expect(
        tester.widget<IconButton>(_iconButton(_strings.ewsFlag)).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip(_strings.refresh));
      await _pump(tester);
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      expect(
        tester.widget<IconButton>(_iconButton(_strings.ewsFlag)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('insecure endpoints fail before provider creation', (
    tester,
  ) async {
    var calls = 0;
    await _show(tester, (configuration, credentials) {
      calls++;
      return _Provider(configuration, credentials);
    });
    await _settings(
      tester,
      endpoint: 'http://mail.example.test/EWS/Exchange.asmx',
    );
    await tester.tap(_field('ews-connect'));
    await _pump(tester);
    expect(calls, 0);
    expect(find.text(_strings.ewsInvalidSettings), findsOneWidget);
  });

  testWidgets(
    'closing a pending connection invalidates its lease and clears credentials',
    (tester) async {
      late _Provider provider;
      final gate = Completer<MailResult<MailCapabilities>>();
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials)
              ..connectGate = gate,
      );
      await _connect(tester);
      expect(provider.lastLease!.isCurrent, isTrue);
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      expect(provider.lastLease!.isCurrent, isFalse);
      final stored = await provider.credentials.load(
        provider.configuration.credential,
      );
      expect((stored as MailSuccess<MailCredentialRecord?>).value, isNull);
      gate.complete(MailSuccess(MailCapabilities([MailCapability.mail])));
      await _pump(tester);
      expect(provider.lists, 0);
      expect(find.byType(StudioMailEwsDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disconnect ignores late message bodies and returns to cleared setup',
    (tester) async {
      late _Provider provider;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials),
      );
      await _connect(tester);
      final gate = Completer<MailResult<MailMessage>>();
      provider.messageGate = gate;
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      expect(provider.lastLease!.isCurrent, isFalse);
      gate.complete(MailSuccess(provider.message()));
      await _pump(tester);
      expect(find.byType(MailMessageView), findsNothing);
      expect(
        tester.widget<TextField>(_field('ews-password')).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'composer sends canonical MIME with one explicit envelope through EWS',
    (tester) async {
      late _Provider provider;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials),
      );
      await _connect(tester);
      await _compose(tester);
      expect(provider.submissions, hasLength(1));
      final submitted = provider.submissions.single;
      expect(submitted.envelope.sender, 'reader@example.test');
      expect(submitted.envelope.recipients, ['recipient@example.test']);
      final decoded = const QudsMimeCodec().parse(submitted.wire.bytes);
      expect(decoded.status, MailParseStatus.complete);
      expect(decoded.message!.envelope.subject, 'EWS send');
      expect(
        decoded.message!.body.plainText,
        contains('Composed in the existing Word editor.'),
      );
      expect(find.text(_strings.ewsSubmissionAccepted), findsOneWidget);
      expect(find.byTooltip(_strings.mailDiscardDraft), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain submissions retain the draft and require acknowledged retry',
    (tester) async {
      late _Provider provider;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials)
              ..outcome = MailSubmissionOutcome.uncertain,
      );
      await _connect(tester);
      await _compose(tester);
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      expect(provider.submissions, hasLength(1));
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(
        tester
            .widget<TextField>(_composerField(_strings.subject))
            .controller!
            .text,
        'EWS send',
      );
      final send = find.widgetWithText(FilledButton, _strings.send);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(provider.submissions, hasLength(1));
      provider.outcome = MailSubmissionOutcome.accepted;
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await _pump(tester);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(provider.submissions, hasLength(2));
      expect(provider.attempts.toSet(), hasLength(2));
      expect(find.text(_strings.ewsSubmissionAccepted), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing during send ignores a late acceptance', (
    tester,
  ) async {
    late _Provider provider;
    final gate = Completer<MailSubmissionResult>();
    await _show(
      tester,
      (configuration, credentials) =>
          provider = _Provider(configuration, credentials)..sendGate = gate,
    );
    await _connect(tester);
    await _compose(tester);
    expect(provider.submissions, hasLength(1));
    final attempt = provider.attempts.single;
    await tester.tap(find.byTooltip(_strings.close));
    await _pump(tester);
    expect(provider.lastLease!.isCurrent, isFalse);
    gate.complete(
      MailSubmissionResult(
        attemptId: attempt,
        outcome: MailSubmissionOutcome.accepted,
      ),
    );
    await _pump(tester);
    expect(find.byType(StudioMailEwsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider exceptions stay redacted in connection feedback', (
    tester,
  ) async {
    await _show(
      tester,
      (configuration, credentials) =>
          _Provider(configuration, credentials)..failConnection = true,
    );
    await _connect(tester);
    expect(find.text(_strings.mailConnectionFailed), findsOneWidget);
    expect(
      find.textContaining('private-password-and-server-text'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow Exchange layout keeps setup, message and actions usable',
    (tester) async {
      await _show(
        tester,
        (configuration, credentials) => _Provider(configuration, credentials),
        size: const Size(390, 720),
      );
      await _connect(tester);
      expect(find.byType(DropdownButton<MailMailboxId>), findsOneWidget);
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      expect(find.byType(MailMessageView), findsOneWidget);
      expect(find.byTooltip(_strings.backToMessages), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'EWS archive action preserves the fetched original and provenance without sending or mutating',
    (tester) async {
      late _Provider provider;
      MailMessage? archived;
      var archiveCalls = 0;
      MailArchiveOrigin? provenance;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials),
        archiveWriter: (message, {required origin, cancellation}) async {
          archiveCalls++;
          archived = message;
          provenance = origin;
          return _archiveSuccess(message);
        },
      );
      await _connect(tester);
      final original = provider.message();
      provider.messageGate = Completer<MailResult<MailMessage>>();
      await tester.tap(find.text('First Exchange message'));
      await _pump(tester);
      expect(archived, isNull);
      provider.messageGate!.complete(MailSuccess(original));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.archiveCurrentMessage));
      await _pump(tester);
      expect(archived, same(original));
      expect(archived!.raw.bytes, orderedEquals(original.raw.bytes));
      expect(archived!.envelope.bcc.single.address, 'hidden@example.test');
      expect(archived!.attachments.single.displayName, 'example.txt');
      expect(
        archived!.attachments.single.content.bytes,
        orderedEquals(utf8.encode('example')),
      );
      expect(provenance!.source, 'Exchange · reader@example.test');
      expect(provenance!.folder, 'Inbox');
      expect(provenance!.sourceMessageId, 'one');
      expect(provider.reads, 1);
      expect(provider.commands, isEmpty);
      expect(provider.submissions, isEmpty);
      expect(archiveCalls, 1);
      expect(find.text(_strings.archiveMessageStored), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'EWS folder archive uses the selected mailbox and a stable profile',
    (tester) async {
      late _Provider provider;
      MailArchiveProfile? profile;
      await _show(
        tester,
        (configuration, credentials) =>
            provider = _Provider(configuration, credentials),
        archiveFolderWriter:
            (
              value, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) async {
              profile = value;
              return _folderReport();
            },
      );
      await _connect(tester);
      await tester.tap(find.byTooltip(_strings.archiveSelectedFolder));
      await _pump(tester);
      expect(profile, isNull);
      await tester.tap(find.byKey(const ValueKey('archive-folder-start')));
      await _pump(tester);
      expect(profile!.source, 'Exchange · reader@example.test');
      expect(profile!.folder, 'Inbox');
      expect(profile!.kind, MailArchiveProfileKind.mailbox);
      expect(profile!.includeSubfolders, isFalse);
      expect(profile!.id, startsWith('studio-mailbox:'));
      expect(provider.reads, 0);
      expect(provider.commands, isEmpty);
      expect(provider.submissions, isEmpty);
      expect(
        find.text(_strings.archiveFolderCounts(3, 1, 0, 2, 300)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('EWS selected message hashes an overlong opaque source ID', (
    tester,
  ) async {
    final originalId = 'opaque-EWS-value' * 160;
    MailArchiveOrigin? receivedOrigin;
    await _show(
      tester,
      (configuration, credentials) =>
          _Provider(configuration, credentials)..firstMessageId = originalId,
      archiveWriter: (message, {required origin, cancellation}) async {
        receivedOrigin = origin;
        return _archiveSuccess(message);
      },
    );
    await _connect(tester);
    await tester.tap(find.text('First Exchange message'));
    await _pump(tester);
    await tester.tap(find.byTooltip(_strings.archiveCurrentMessage));
    await _pump(tester);
    expect(
      receivedOrigin!.sourceMessageId,
      studioArchiveSourceMessageId(originalId),
    );
    expect(receivedOrigin!.sourceMessageId.length, 71);
    expect(tester.takeException(), isNull);
  });
}
