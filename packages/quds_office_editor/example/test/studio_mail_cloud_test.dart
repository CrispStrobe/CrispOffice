import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_cloud.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';
import 'package:quds_office_studio/studio_mail_archive_action.dart';
import 'package:quds_office_studio/studio_mail_archive_folder_action.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';

import 'support/mail_attachment_picker.dart';
import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);

final class _Tokens extends Fake implements MailCloudTokenSource {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

final class _Provider extends Fake implements MailCloudProvider {
  _Provider(this.configuration);
  final MailCloudConfiguration configuration;
  int disposals = 0;
  int reads = 0;
  bool disposalThrows = false;
  MailOperationLease? lastLease;
  MailProblem? connectionProblem;
  Completer<MailResult<MailMessage>>? messageGate;
  Completer<MailResult<MailHeaderPage>>? headerGate;
  MailHeaderPage Function(MailMailboxId, MailCursor?)? headerPage;
  final List<MailCursor?> cursors = [];
  final List<int> headerLimits = [];
  MailSubmissionOutcome outcome = MailSubmissionOutcome.accepted;
  MailProblem? submissionProblem;
  final submissions = <MailPreparedMessage>[];
  final commands = <MailOperation>[];
  MailAccountId? accountOverride;
  bool replyParticipants = false;
  MailEnvelope? envelopeOverride;
  void Function()? onSubmit;

  @override
  MailAccountId get account => accountOverride ?? configuration.account;
  MailMailboxId box(String name) => MailMailboxId(name, account: account);
  MailOpaqueIdentity identity(String value) => MailOpaqueIdentity(
    account: account,
    provider: configuration.service == MailCloudService.gmail
        ? MailProviderKind.gmail
        : MailProviderKind.graph,
    value: value,
  );

  MailHeaderRecord header(
    String id,
    String subject, {
    MailMessageFlags? flags = const MailMessageFlags(),
  }) => MailHeaderRecord(
    id: MailMessageId(id),
    remote: identity(id == 'cloud-message' ? 'remote-message' : id),
    envelope: MailEnvelope(
      subject: subject,
      from: [const MailAddress('writer@example.test')],
    ),
    flags: flags,
  );

  @override
  void dispose() {
    disposals++;
    if (disposalThrows) throw StateError('private-provider-cleanup');
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async {
    lastLease = lease;
    return connectionProblem == null
        ? MailSuccess(
            MailCapabilities(const [
              MailCapability.mail,
              MailCapability.folders,
              MailCapability.send,
              MailCapability.move,
            ]),
          )
        : MailFailure(connectionProblem!);
  }

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([
    MailMailbox(id: box('inbox'), displayName: 'Inbox'),
    MailMailbox(id: box('archive'), displayName: 'Archive'),
  ]);

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lastLease = lease;
    cursors.add(cursor);
    headerLimits.add(limit);
    expect(limit, inInclusiveRange(1, 50));
    if (headerGate case final gate?) return gate.future;
    if (headerPage case final page?) return MailSuccess(page(mailbox, cursor));
    return MailSuccess(
      MailHeaderPage(
        messages: [
          MailHeaderRecord(
            id: MailMessageId('cloud-message'),
            remote: identity('remote-message'),
            envelope: MailEnvelope(
              subject: 'Cloud message',
              from: [const MailAddress('writer@example.test')],
            ),
            flags: const MailMessageFlags(),
          ),
        ],
      ),
    );
  }

  MailMessage message() {
    final parsed = const QudsMimeCodec()
        .parse(
          utf8.encode(
            'From: Writer <writer@example.test>\r\n'
            'To: Reader <reader@example.test>${replyParticipants ? ', teammate@example.test' : ''}\r\n'
            '${replyParticipants ? 'Reply-To: author@example.test\r\nCc: copied@example.test\r\nMessage-ID: <parent@example.test>\r\nReferences: <root@example.test>\r\n' : ''}'
            'Subject: Cloud message\r\n'
            'Bcc: hidden@example.test\r\nX-Preserved:  original\r\n\tfolding\r\n'
            'MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=cloud-original\r\n\r\n'
            '--cloud-original\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n'
            'Body from cloud provider.\r\n'
            '--cloud-original\r\nContent-Type: application/octet-stream\r\n'
            'Content-Disposition: attachment; filename=cloud.bin\r\n'
            'Content-Transfer-Encoding: base64\r\n\r\nAAEC/w0K\r\n'
            '--cloud-original--\r\n',
          ),
        )
        .message!;
    return MailMessage(
      raw: parsed.raw,
      envelope: envelopeOverride ?? parsed.envelope,
      body: parsed.body,
      attachments: parsed.attachments,
      localId: MailMessageId('cloud-message'),
      remoteIdentity: identity('remote-message'),
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
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailSubmissionResult> submit(
    MailPreparedMessage message, {
    required String attemptId,
    required MailOperationLease lease,
  }) async {
    onSubmit?.call();
    submissions.add(message);
    lastLease = lease;
    return MailSubmissionResult(
      attemptId: attemptId,
      outcome: outcome,
      problem: submissionProblem,
    );
  }
}

final class _Harness {
  final tokens = _Tokens();
  int authorizations = 0;
  MailOAuthConfiguration? authorization;
  MailOperationLease? authLease;
  MailCloudLogSink? authLog;
  MailCloudLogSink? providerLog;
  Completer<MailResult<MailCloudTokenSource>>? authorizationGate;
  Object? authorizationError;
  MailProblem? authorizationProblem;
  MailProblem? connectionProblem;
  bool wrongAccount = false;
  bool factoryThrows = false;
  void Function(_Provider)? configureProvider;
  _Provider? provider;

  Future<MailResult<MailCloudTokenSource>> authorize({
    required MailOAuthConfiguration configuration,
    required MailAccountId account,
    required Future<bool> Function(Uri) openBrowser,
    required MailOperationLease lease,
    MailCloudLogSink? log,
  }) async {
    authorizations++;
    authorization = configuration;
    authLease = lease;
    authLog = log;
    expect(lease.account, account);
    if (authorizationError case final error?) throw error;
    if (authorizationProblem case final problem?) return MailFailure(problem);
    return authorizationGate == null
        ? MailSuccess(tokens)
        : await authorizationGate!.future;
  }

  MailCloudProvider create({
    required MailCloudConfiguration configuration,
    required MailCloudTokenSource tokenSource,
    MailCloudLogSink? log,
  }) {
    expect(tokenSource, same(tokens));
    if (factoryThrows) throw StateError('private-factory-credentials');
    providerLog = log;
    final result = _Provider(configuration)
      ..connectionProblem = connectionProblem;
    configureProvider?.call(result);
    if (wrongAccount) {
      result.accountOverride = MailAccountId(
        'wrong-account',
        profile: configuration.account.profile,
      );
    }
    provider = result;
    return result;
  }
}

Finder _field(String key) => find.byKey(ValueKey(key));
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester,
  _Harness harness, {
  MailCloudService service = MailCloudService.gmail,
  Size size = const Size(1280, 900),
  StudioMailArchiveWriter? archiveWriter,
  StudioMailArchiveFolderWriter? archiveFolderWriter,
  MemoryStudioMailDrafts? drafts,
}) async {
  final draftStorage = drafts ?? MemoryStudioMailDrafts();
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
              builder: (_) => StudioMailCloudDialog(
                draftStoreFactory: draftStorage.open,
                strings: _strings,
                service: service,
                authorizer: harness.authorize,
                providerFactory: harness.create,
                initialClientId: 'test-desktop-client',
                openBrowser: (_) async => true,
                archiveWriter: archiveWriter,
                archiveFolderWriter: archiveFolderWriter,
              ),
            ),
            child: const Text('Open cloud'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open cloud'));
  await _pump(tester);
}

Future<void> _connect(WidgetTester tester) async {
  await tester.enterText(_field('cloud-mailbox'), 'reader@example.test');
  await tester.ensureVisible(_field('cloud-connect'));
  await _pump(tester);
  await tester.tap(_field('cloud-connect'));
  await _pump(tester);
}

Finder _composeField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _send(
  WidgetTester tester, {
  String to = 'recipient@example.test',
  String cc = '',
  String bcc = '',
  Future<void> Function()? beforeSend,
}) async {
  await tester.tap(find.byTooltip(_strings.compose));
  await _pump(tester);
  await tester.enterText(_composeField(_strings.to), to);
  if (cc.isNotEmpty || bcc.isNotEmpty) {
    await tester.tap(find.text(_strings.mailCopyRecipients));
    await _pump(tester);
    await tester.enterText(_composeField(_strings.mailCc), cc);
    await tester.enterText(_composeField(_strings.mailBcc), bcc);
  }
  await tester.enterText(_composeField(_strings.subject), 'Cloud send');
  tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller
      .insertText('Sent from CrispOffice.');
  await tester.pump();
  await beforeSend?.call();
  final send = find.widgetWithText(FilledButton, _strings.send);
  await tester.ensureVisible(send);
  await tester.tap(send);
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
  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} confirmed flag leaves unknown read state untouched',
      (tester) async {
        final harness = _Harness()
          ..configureProvider = (provider) {
            provider.headerPage = (mailbox, cursor) => MailHeaderPage(
              messages: [
                provider.header('cloud-message', 'Cloud message', flags: null),
              ],
            );
          };
        await _show(tester, harness, service: service);
        await _connect(tester);
        await tester.tap(_field('ews-message-cloud-message'));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.ewsFlag));
        await _pump(tester);
        var row = tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .items
            .single;
        expect(row.isFlagged, isTrue);
        expect(row.isRead, isNull);
        expect(find.byTooltip(_strings.ewsUnflag), findsOneWidget);
        await tester.tap(_field('mail-list-flagged'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsOneWidget);
        await tester.tap(_field('mail-list-unread'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsNothing);
        await tester.tap(find.byTooltip(_strings.ewsUnflag));
        await _pump(tester);
        row = tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .items
            .single;
        expect(row.isFlagged, isFalse);
        expect(row.isRead, isNull);
        expect(
          harness.provider!.commands.map(
            (command) => (command as MailSetFlagged).flagged,
          ),
          [true, false],
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} unknown read commands stay independent and refresh replaces them',
      (tester) async {
        final harness = _Harness()
          ..configureProvider = (provider) {
            provider.headerPage = (mailbox, cursor) => MailHeaderPage(
              messages: [
                provider.header('cloud-message', 'Cloud message', flags: null),
              ],
            );
          };
        await _show(tester, harness, service: service);
        await _connect(tester);
        await tester.tap(_field('ews-message-cloud-message'));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.markRead));
        await _pump(tester);
        var row = tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .items
            .single;
        expect(row.isRead, isTrue);
        expect(row.isFlagged, isNull);
        await tester.tap(_field('mail-list-unread'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsNothing);
        await tester.tap(find.byTooltip(_strings.ewsMarkUnread));
        await _pump(tester);
        row = tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .items
            .single;
        expect(row.isRead, isFalse);
        expect(row.isFlagged, isNull);
        expect(_field('ews-message-cloud-message'), findsOneWidget);
        await tester.tap(_field('mail-list-flagged'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsNothing);
        final provider = harness.provider!;
        expect(
          provider.commands.map((command) => (command as MailSetRead).read),
          [true, false],
        );
        provider.headerPage = (mailbox, cursor) => MailHeaderPage(
          messages: [
            provider.header(
              'cloud-message',
              'Cloud message',
              flags: const MailMessageFlags(isRead: true),
            ),
          ],
        );
        await tester.tap(find.byTooltip(_strings.refresh));
        await _pump(tester);
        row = tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .items
            .single;
        expect(row.isRead, isTrue);
        expect(row.isFlagged, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} loaded filters permit explicit pagination with no matches',
      (tester) async {
        final harness = _Harness()
          ..configureProvider = (provider) {
            provider.headerPage = (mailbox, cursor) => MailHeaderPage(
              messages: [
                cursor == null
                    ? provider.header('cloud-message', 'Cloud message')
                    : provider.header('older', 'Later cloud message'),
              ],
              next: cursor == null
                  ? MailCursor(mailbox: mailbox, value: 'next-cloud-page')
                  : null,
            );
          };
        await _show(tester, harness, service: service);
        await _connect(tester);
        final provider = harness.provider!;
        await tester.enterText(_field('mail-list-search'), 'later');
        await tester.tap(_field('mail-list-unread'));
        await _pump(tester);
        expect(
          find.text(_strings.mailMessageListStrings.noMatches),
          findsOneWidget,
        );
        expect(provider.cursors, hasLength(1));
        expect(provider.reads, 0);
        await tester.tap(_field('ews-load-more'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsNothing);
        expect(_field('ews-message-older'), findsOneWidget);
        expect(
          find.text(
            '1 shown · 2 loaded\n${_strings.mailMessageListStrings.loadedScope}',
          ),
          findsOneWidget,
        );
        expect(provider.cursors.map((cursor) => cursor?.value), [
          null,
          'next-cloud-page',
        ]);
        expect(provider.reads, 0);
        expect(provider.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} compact Back preserves query filters selection and body',
      (tester) async {
        final harness = _Harness()
          ..configureProvider = (provider) {
            provider.headerPage = (mailbox, cursor) => MailHeaderPage(
              messages: [
                provider.header(
                  'cloud-message',
                  'Cloud message',
                  flags: const MailMessageFlags(isFlagged: true),
                ),
              ],
            );
          };
        await _show(
          tester,
          harness,
          service: service,
          size: const Size(400, 850),
        );
        await _connect(tester);
        await tester.enterText(_field('mail-list-search'), 'cloud');
        await tester.tap(_field('mail-list-unread'));
        await tester.tap(_field('mail-list-flagged'));
        await _pump(tester);
        await tester.tap(_field('ews-message-cloud-message'));
        await _pump(tester);
        final reader = tester
            .widget<MailMessageView>(find.byType(MailMessageView))
            .controller;
        expect(
          reader.result.message!.body.plainText,
          contains('Body from cloud provider.'),
        );
        await tester.tap(find.byTooltip(_strings.backToMessages));
        await _pump(tester);
        expect(
          tester.widget<TextField>(_field('mail-list-search')).controller!.text,
          'cloud',
        );
        expect(
          tester.widget<FilterChip>(_field('mail-list-unread')).selected,
          isTrue,
        );
        expect(
          tester.widget<FilterChip>(_field('mail-list-flagged')).selected,
          isTrue,
        );
        expect(
          tester
              .widget<Semantics>(_field('ews-message-cloud-message'))
              .properties
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<MailMessageView>(
                find.byType(MailMessageView, skipOffstage: false),
              )
              .controller,
          same(reader),
        );
        expect(harness.provider!.reads, 1);
        expect(harness.provider!.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} confirmed read and flag changes update filtered rows',
      (tester) async {
        final harness = _Harness();
        await _show(tester, harness, service: service);
        await _connect(tester);
        await tester.tap(_field('mail-list-unread'));
        await tester.tap(_field('ews-message-cloud-message'));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.markRead));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsNothing);
        expect(find.byType(MailMessageView), findsOneWidget);
        await tester.tap(find.byTooltip(_strings.ewsMarkUnread));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsOneWidget);
        await tester.tap(_field('mail-list-flagged'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsNothing);
        await tester.tap(find.byTooltip(_strings.ewsFlag));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsOneWidget);
        final commands = harness.provider!.commands;
        expect(commands, hasLength(3));
        expect(
          commands[0],
          isA<MailSetRead>().having((command) => command.read, 'read', true),
        );
        expect(
          commands[1],
          isA<MailSetRead>().having((command) => command.read, 'read', false),
        );
        expect(
          commands[2],
          isA<MailSetFlagged>().having(
            (command) => command.flagged,
            'flagged',
            true,
          ),
        );
        expect(
          commands.every(
            (command) =>
                command.message == harness.provider!.identity('remote-message'),
          ),
          isTrue,
        );
        expect(harness.provider!.reads, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} rejects a wrong-mailbox pagination cursor without losing rows',
      (tester) async {
        final harness = _Harness()
          ..configureProvider = (provider) {
            provider.headerPage = (mailbox, cursor) => MailHeaderPage(
              messages: [provider.header('cloud-message', 'Cloud message')],
              next: MailCursor(mailbox: mailbox, value: 'next-cloud-page'),
            );
          };
        await _show(tester, harness, service: service);
        await _connect(tester);
        final provider = harness.provider!;
        provider.headerPage = (mailbox, cursor) => MailHeaderPage(
          messages: [provider.header('rejected', 'Rejected private page')],
          next: MailCursor(
            mailbox: provider.box('archive'),
            value: 'wrong-scope',
          ),
        );
        await tester.tap(_field('ews-load-more'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsOneWidget);
        expect(find.text('Rejected private page'), findsNothing);
        expect(
          find.text(_strings.mailWorkspaceRefreshRequired),
          findsOneWidget,
        );
        expect(
          tester.widget<TextButton>(_field('ews-load-more')).onPressed,
          isNull,
        );
        expect(provider.cursors, hasLength(2));
        expect(provider.reads, 0);
        expect(provider.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} rejects a local row id collision with an earlier page',
      (tester) async {
        final harness = _Harness()
          ..configureProvider = (provider) {
            provider.headerPage = (mailbox, cursor) => MailHeaderPage(
              messages: [provider.header('cloud-message', 'Cloud message')],
              next: MailCursor(mailbox: mailbox, value: 'next-cloud-page'),
            );
          };
        await _show(tester, harness, service: service);
        await _connect(tester);
        final provider = harness.provider!;
        provider.headerPage = (mailbox, cursor) => MailHeaderPage(
          messages: [
            MailHeaderRecord(
              id: MailMessageId('cloud-message'),
              remote: provider.identity('foreign-remote'),
              envelope: MailEnvelope(subject: 'Colliding private page'),
            ),
          ],
        );
        await tester.tap(_field('ews-load-more'));
        await _pump(tester);
        expect(_field('ews-message-cloud-message'), findsOneWidget);
        expect(find.text('Cloud message'), findsOneWidget);
        expect(find.text('Colliding private page'), findsNothing);
        expect(
          find.text(_strings.mailWorkspaceRefreshRequired),
          findsOneWidget,
        );
        expect(
          tester.widget<TextButton>(_field('ews-load-more')).onPressed,
          isNull,
        );
        expect(provider.cursors, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} disconnect retires pending header page and credentials',
      (tester) async {
        final harness = _Harness()
          ..configureProvider = (provider) {
            provider.headerPage = (mailbox, cursor) => MailHeaderPage(
              messages: [provider.header('cloud-message', 'Cloud message')],
              next: MailCursor(mailbox: mailbox, value: 'next-cloud-page'),
            );
          };
        await _show(tester, harness, service: service);
        await _connect(tester);
        final provider = harness.provider!;
        final gate = Completer<MailResult<MailHeaderPage>>();
        provider.headerGate = gate;
        await tester.tap(_field('ews-load-more'));
        await _pump(tester);
        final lease = provider.lastLease!;
        await tester.tap(find.byTooltip(_strings.disconnect));
        await _pump(tester);
        gate.complete(
          MailSuccess(
            MailHeaderPage(
              messages: [provider.header('late', 'Late private page')],
            ),
          ),
        );
        await _pump(tester);
        expect(lease.isCurrent, isFalse);
        expect(provider.disposals, 1);
        expect(harness.tokens.disposals, 1);
        expect(find.text('Late private page'), findsNothing);
        expect(_field('cloud-connect'), findsOneWidget);
        expect(find.byType(MailMessageList), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final service in MailCloudService.values) {
    testWidgets('${service.name} reopens its saved draft after reconnect', (
      tester,
    ) async {
      final drafts = MemoryStudioMailDrafts();
      final harness = _Harness();
      await _show(tester, harness, service: service, drafts: drafts);
      await _connect(tester);
      final original = harness.provider!;
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
      await tester.enterText(_composeField(_strings.to), 'Draft recipient <');
      await tester.enterText(
        _composeField(_strings.subject),
        'Recovered cloud work',
      );
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller
          .insertText('Saved before closing cloud mail');
      await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
      await tester.tap(find.text(_strings.mailDraftSaveClose));
      await _pump(tester);
      expect(original.submissions, isEmpty);
      expect(drafts.records.values.single.draft.to, 'Draft recipient <');
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      expect(drafts.closes, 1);
      await tester.tap(find.text('Open cloud'));
      await _pump(tester);
      await _connect(tester);
      expect(find.text(_strings.mailDraftRestored), findsOneWidget);
      expect(
        drafts.identities.map((identity) => identity.account).toSet(),
        hasLength(1),
      );
      expect(
        drafts.identities.last.provider,
        service == MailCloudService.gmail
            ? MailProviderKind.gmail
            : MailProviderKind.graph,
      );
      expect(harness.provider!.submissions, isEmpty);
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
      expect(
        tester.widget<TextField>(_composeField(_strings.to)).controller!.text,
        'Draft recipient <',
      );
      expect(
        tester
            .widget<TextField>(_composeField(_strings.subject))
            .controller!
            .text,
        'Recovered cloud work',
      );
      expect(
        tester
            .widget<QudsWordEditor>(find.byType(QudsWordEditor))
            .controller
            .document
            .paragraphs
            .single
            .text,
        'Saved before closing cloud mail',
      );
      await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
      await tester.tap(find.text(_strings.mailDraftSaveClose));
      await _pump(tester);
      expect(harness.provider!.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Gmail submits only after durable uncertainty and clears accepted work',
    (tester) async {
      final drafts = MemoryStudioMailDrafts();
      final harness = _Harness();
      final markerGate = Completer<void>();
      bool? durableAtSubmission;
      await _show(tester, harness, drafts: drafts);
      await _connect(tester);
      harness.provider!.onSubmit = () => durableAtSubmission =
          drafts.records.values.single.submissionUncertain;
      await _send(
        tester,
        beforeSend: () async {
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
          expect(drafts.saved.last.submissionUncertain, isFalse);
          drafts.saveGate = markerGate;
        },
      );
      expect(harness.provider!.submissions, isEmpty);
      expect(drafts.records.values.single.submissionUncertain, isFalse);
      markerGate.complete();
      await _pump(tester);
      expect(harness.provider!.submissions, hasLength(1));
      expect(durableAtSubmission, isTrue);
      expect(drafts.saved.last.submissionUncertain, isTrue);
      expect(drafts.clears, 1);
      expect(drafts.records, isEmpty);
      expect(find.text(_strings.mailCloudSubmissionAccepted), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Gmail accepted cleanup failure restores guarded draft without resend',
    (tester) async {
      final drafts = MemoryStudioMailDrafts()..failClear = true;
      final harness = _Harness();
      await _show(tester, harness, drafts: drafts);
      await _connect(tester);
      final original = harness.provider!;
      await _send(tester);
      expect(original.submissions, hasLength(1));
      expect(
        find.text(_strings.mailDraftAcceptedCleanupFailed),
        findsOneWidget,
      );
      expect(drafts.records.values.single.submissionUncertain, isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(original.submissions, hasLength(1));
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      await tester.tap(find.text('Open cloud'));
      await _pump(tester);
      await _connect(tester);
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      expect(harness.provider!.submissions, isEmpty);
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
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
      expect(harness.provider!.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Gmail retries storage opening and blocks sends while saving fails',
    (tester) async {
      final drafts = MemoryStudioMailDrafts()..failOpen = true;
      final harness = _Harness();
      await _show(tester, harness, drafts: drafts);
      await _connect(tester);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      drafts.failOpen = false;
      drafts.failSave = true;
      await _send(tester);
      expect(harness.provider!.submissions, isEmpty);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
      drafts.failSave = false;
      await tester.ensureVisible(find.text(_strings.mailDraftRetrySave));
      await tester.tap(find.text(_strings.mailDraftRetrySave));
      await _pump(tester);
      await tester.ensureVisible(find.text(_strings.mailDraftSaveClose));
      await tester.tap(find.text(_strings.mailDraftSaveClose));
      await _pump(tester);
      expect(drafts.records.values.single.draft.subject, 'Cloud send');
      expect(harness.provider!.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Gmail closes late draft storage without adopting a retired session',
    (tester) async {
      final gate = Completer<void>();
      final drafts = MemoryStudioMailDrafts()..openGate = gate;
      final harness = _Harness();
      await _show(tester, harness, drafts: drafts);
      await _connect(tester);
      expect(drafts.identities, hasLength(1));
      final provider = harness.provider!;
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      gate.complete();
      await _pump(tester);
      expect(drafts.closes, 1);
      expect(drafts.records, isEmpty);
      expect(provider.disposals, 1);
      expect(provider.submissions, isEmpty);
      expect(find.byType(StudioMailCloudDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native setup offers Gmail, Microsoft 365 and Exchange', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: StudioMailDialog(strings: _strings)),
    );
    expect(_field('studio-mail-open-gmail'), findsOneWidget);
    expect(_field('studio-mail-open-microsoft365'), findsOneWidget);
    expect(_field('studio-mail-open-ews'), findsOneWidget);
    await tester.tap(_field('studio-mail-open-gmail'));
    await _pump(tester);
    expect(find.byType(StudioMailCloudDialog), findsOneWidget);
    expect(_field('cloud-mailbox'), findsOneWidget);
    expect(_field('ews-password'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} signs in and adopts the matching mailbox session',
      (tester) async {
        final harness = _Harness();
        await _show(tester, harness, service: service);
        if (service == MailCloudService.gmail) {
          await tester.enterText(
            _field('cloud-client-secret'),
            'desktop-metadata-secret',
          );
        } else {
          await tester.enterText(_field('cloud-tenant'), 'organizations');
        }
        final secret = service == MailCloudService.gmail
            ? tester.widget<TextField>(_field('cloud-client-secret')).controller
            : null;
        await _connect(tester);
        expect(harness.authorization!.service, service);
        expect(harness.authorization!.clientId, 'test-desktop-client');
        expect(
          harness.authorization!.tenant,
          service == MailCloudService.gmail ? 'common' : 'organizations',
        );
        expect(secret?.text ?? '', isEmpty);
        expect(
          harness.provider!.configuration.mailboxAddress,
          'reader@example.test',
        );
        expect(harness.authLog, isNull);
        expect(harness.providerLog, isNull);
        expect(find.text('Cloud message'), findsOneWidget);
        expect(harness.provider!.reads, 0);
        await tester.tap(find.text('Cloud message'));
        await _pump(tester);
        expect(find.byType(MailMessageView), findsOneWidget);
        expect(harness.provider!.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('invalid settings never authorize or construct a provider', (
    tester,
  ) async {
    final harness = _Harness();
    await _show(tester, harness);
    await tester.enterText(_field('cloud-client-id'), '');
    await _connect(tester);
    expect(harness.authorizations, 0);
    expect(harness.provider, isNull);
    expect(find.text(_strings.mailCloudInvalidSettings), findsOneWidget);
  });

  testWidgets(
    'authorization exceptions are redacted and leave retry available',
    (tester) async {
      final harness = _Harness()
        ..authorizationError = StateError(
          'secret-token private-address@example.test',
        );
      await _show(tester, harness);
      await _connect(tester);
      expect(find.text(_strings.mailCloudSignInFailed), findsOneWidget);
      expect(find.textContaining('secret-token'), findsNothing);
      expect(
        tester.widget<FilledButton>(_field('cloud-connect')).onPressed,
        isNotNull,
      );
      harness.authorizationError = null;
      await tester.tap(_field('cloud-connect'));
      await _pump(tester);
      expect(find.text('Cloud message'), findsOneWidget);
    },
  );

  testWidgets('denied OAuth permissions use localized actionable feedback', (
    tester,
  ) async {
    final harness = _Harness()
      ..authorizationProblem = const MailProblem(
        MailProblemCode.permissionDenied,
      );
    await _show(tester, harness);
    await _connect(tester);
    expect(find.text(_strings.mailCloudAccessFailed), findsOneWidget);
    expect(harness.provider, isNull);
  });

  testWidgets(
    'cancelled browser authorization rejects and disposes late tokens',
    (tester) async {
      final harness = _Harness()
        ..authorizationGate = Completer<MailResult<MailCloudTokenSource>>();
      await _show(tester, harness);
      await _connect(tester);
      expect(harness.authLease!.isCurrent, isTrue);
      await tester.ensureVisible(find.text(_strings.cancel));
      await tester.tap(find.text(_strings.cancel));
      await _pump(tester);
      expect(harness.authLease!.isCurrent, isFalse);
      harness.authorizationGate!.complete(MailSuccess(harness.tokens));
      await _pump(tester);
      expect(harness.tokens.disposals, 1);
      expect(harness.provider, isNull);
      expect(find.text('Cloud message'), findsNothing);
    },
  );

  testWidgets(
    'closing during authorization invalidates the lease and clears late tokens',
    (tester) async {
      final harness = _Harness()
        ..authorizationGate = Completer<MailResult<MailCloudTokenSource>>();
      await _show(tester, harness);
      await _connect(tester);
      await tester.tap(find.byTooltip(_strings.close));
      await _pump(tester);
      harness.authorizationGate!.complete(MailSuccess(harness.tokens));
      await _pump(tester);
      expect(harness.authLease!.isCurrent, isFalse);
      expect(harness.tokens.disposals, 1);
      expect(harness.provider, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mailbox rejection closes provider and tokens without exposing metadata secret',
    (tester) async {
      final harness = _Harness()
        ..connectionProblem = const MailProblem(
          MailProblemCode.authenticationRequired,
        );
      await _show(tester, harness);
      await tester.enterText(_field('cloud-client-secret'), 'secret-metadata');
      final secret = tester
          .widget<TextField>(_field('cloud-client-secret'))
          .controller!;
      await _connect(tester);
      expect(find.text(_strings.mailCloudAuthenticationFailed), findsOneWidget);
      expect(harness.provider!.disposals, 1);
      expect(harness.tokens.disposals, 1);
      expect(secret.text, isEmpty);
      expect(harness.authLease!.isCurrent, isFalse);
    },
  );

  testWidgets(
    'wrong-account provider is rejected and disposed before mailbox reads',
    (tester) async {
      final harness = _Harness()..wrongAccount = true;
      await _show(tester, harness);
      await _connect(tester);
      expect(find.text(_strings.mailCloudSignInFailed), findsOneWidget);
      expect(harness.provider!.disposals, 1);
      expect(harness.provider!.reads, 0);
      expect(harness.tokens.disposals, 1);
    },
  );

  testWidgets('provider construction errors retire the authorized tokens', (
    tester,
  ) async {
    final harness = _Harness()..factoryThrows = true;
    await _show(tester, harness);
    await _connect(tester);
    expect(harness.tokens.disposals, 1);
    expect(harness.authLease!.isCurrent, isFalse);
    expect(find.text(_strings.mailCloudSignInFailed), findsOneWidget);
    expect(find.textContaining('private-factory-credentials'), findsNothing);
  });

  testWidgets(
    'throttling displays the rounded delay without an automatic retry',
    (tester) async {
      final harness = _Harness()
        ..connectionProblem = const MailProblem(
          MailProblemCode.quotaExceeded,
          retryAfter: Duration(milliseconds: 12500),
        );
      await _show(tester, harness);
      await _connect(tester);
      expect(find.text(_strings.mailCloudRetryAfter(13)), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      expect(harness.authorizations, 1);
      expect(harness.provider!.submissions, isEmpty);
    },
  );

  testWidgets(
    'provider cleanup failure cannot prevent token cleanup or disconnect',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await _connect(tester);
      harness.provider!.disposalThrows = true;
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      expect(harness.tokens.disposals, 1);
      expect(_field('cloud-connect'), findsOneWidget);
      expect(find.textContaining('private-provider-cleanup'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disconnect ignores a pending message body and retires session resources',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await _connect(tester);
      final provider = harness.provider!
        ..messageGate = Completer<MailResult<MailMessage>>();
      await tester.tap(find.text('Cloud message'));
      await _pump(tester);
      await tester.tap(find.byTooltip(_strings.disconnect));
      await _pump(tester);
      provider.messageGate!.complete(MailSuccess(provider.message()));
      await _pump(tester);
      expect(provider.lastLease!.isCurrent, isFalse);
      expect(provider.disposals, 1);
      expect(harness.tokens.disposals, 1);
      expect(find.byType(MailMessageView), findsNothing);
      expect(_field('cloud-connect'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'verbose diagnostics opt in passes only structured safe events to the log',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await tester.ensureVisible(_field('cloud-diagnostics'));
      await tester.tap(_field('cloud-diagnostics'));
      await _pump(tester);
      await _connect(tester);
      expect(harness.authLog, isNotNull);
      expect(harness.providerLog, isNotNull);
      final captured = <String>[];
      final previous = debugPrint;
      debugPrint = (String? value, {int? wrapWidth}) {
        if (value != null) captured.add(value);
      };
      try {
        harness.providerLog!(
          const MailCloudLogEvent(
            service: MailCloudService.gmail,
            operation: MailCloudOperation.fetchHeaders,
            stage: MailCloudLogStage.completed,
            itemCount: 1,
            statusCode: 200,
          ),
        );
      } finally {
        debugPrint = previous;
      }
      expect(jsonDecode(captured.single), {
        'service': 'gmail',
        'operation': 'fetchHeaders',
        'stage': 'completed',
        'statusCode': 200,
        'itemCount': 1,
      });
    },
  );

  testWidgets(
    'cloud composition uses canonical MIME and does not overclaim delivery',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness, service: MailCloudService.microsoft365);
      await _connect(tester);
      await _send(tester);
      final submission = harness.provider!.submissions.single;
      expect(submission.envelope.sender, 'reader@example.test');
      expect(submission.envelope.recipients, ['recipient@example.test']);
      expect(
        utf8.decode(submission.wire.bytes),
        contains('Sent from CrispOffice.'),
      );
      expect(find.text(_strings.mailCloudSubmissionAccepted), findsOneWidget);
      expect(find.text(_strings.ewsSubmissionAccepted), findsNothing);
    },
  );

  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} host keeps hidden recipients out of canonical MIME',
      (tester) async {
        final harness = _Harness();
        await _show(tester, harness, service: service);
        await _connect(tester);
        await tester.tap(find.byTooltip(_strings.compose));
        await _pump(tester);
        await tester.enterText(
          _composeField(_strings.to),
          'primary@Example.test; second@example.test',
        );
        await tester.tap(find.text(_strings.mailCopyRecipients));
        await _pump(tester);
        await tester.enterText(
          _composeField(_strings.mailCc),
          'primary@example.test, copy@example.test',
        );
        await tester.enterText(
          _composeField(_strings.mailBcc),
          'copy@example.test; hidden@example.test',
        );
        await tester.enterText(
          _composeField(_strings.subject),
          'Recipient privacy',
        );
        final send = find.widgetWithText(FilledButton, _strings.send);
        await tester.ensureVisible(send);
        await tester.tap(send);
        await _pump(tester);
        final submission = harness.provider!.submissions.single;
        expect(submission.envelope.recipients, [
          'primary@Example.test',
          'second@example.test',
          'copy@example.test',
          'hidden@example.test',
        ]);
        final decoded = const QudsMimeCodec().parse(submission.wire.bytes);
        expect(decoded.status, MailParseStatus.complete);
        expect(decoded.message!.envelope.to.map((entry) => entry.address), [
          'primary@Example.test',
          'second@example.test',
        ]);
        expect(decoded.message!.envelope.cc.map((entry) => entry.address), [
          'copy@example.test',
        ]);
        expect(decoded.message!.envelope.bcc, isEmpty);
        expect(
          utf8.decode(submission.wire.bytes),
          isNot(contains('hidden@example.test')),
        );
        expect(find.text(_strings.mailCloudSubmissionAccepted), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} retains exact attachments through acknowledged retry',
      (tester) async {
        final source = Uint8List.fromList([0, 255, 128, 13, 10, 42]);
        final expected = Uint8List.fromList(source);
        final picker = MailAttachmentPickerFixture(
          () async => FilePickerResult([
            PlatformFile(
              name: 'Cloud snapshot.pptx',
              size: source.length,
              readStream: Stream<List<int>>.value(source),
            ),
          ]),
        );
        FilePicker.platform = picker;
        addTearDown(() => FilePicker.platform = FilePickerIO());
        final harness = _Harness();
        await _show(tester, harness, service: service);
        await _connect(tester);
        final provider = harness.provider!
          ..outcome = MailSubmissionOutcome.uncertain;
        await _send(
          tester,
          cc: 'copied@example.test',
          bcc: 'hidden@example.test',
          beforeSend: () async {
            final add = find.byKey(
              const ValueKey('studio-mail-add-attachments'),
            );
            await tester.ensureVisible(add);
            await tester.tap(add);
            await _pump(tester);
            expect(find.text('Cloud snapshot.pptx'), findsOneWidget);
            source.fillRange(0, source.length, 17);
          },
        );
        expect(provider.submissions, hasLength(1));
        expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
        await tester.pump(const Duration(minutes: 1));
        expect(provider.submissions, hasLength(1));
        await tester.tap(find.byTooltip(_strings.compose));
        await _pump(tester);
        expect(find.text('Cloud snapshot.pptx'), findsOneWidget);
        expect(picker.calls, 1);
        final send = find.widgetWithText(FilledButton, _strings.send);
        expect(tester.widget<FilledButton>(send).onPressed, isNull);
        provider.outcome = MailSubmissionOutcome.accepted;
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await _pump(tester);
        await tester.ensureVisible(send);
        await tester.tap(send);
        await _pump(tester);
        expect(provider.submissions, hasLength(2));
        for (final submission in provider.submissions) {
          expect(submission.envelope.recipients, [
            'recipient@example.test',
            'copied@example.test',
            'hidden@example.test',
          ]);
          final wire = ascii.decode(submission.wire.bytes);
          expect(wire, contains('multipart/mixed'));
          expect(wire, contains('multipart/alternative'));
          expect(wire, isNot(contains('hidden@example.test')));
          final decoded = const QudsMimeCodec().parse(submission.wire.bytes);
          expect(decoded.status, MailParseStatus.complete);
          expect(decoded.message!.body.plainText, 'Sent from CrispOffice.');
          expect(decoded.message!.attachments, hasLength(1));
          expect(
            decoded.message!.attachments.single.displayName,
            'Cloud snapshot.pptx',
          );
          expect(decoded.message!.attachments.single.content.bytes, expected);
          expect(decoded.message!.envelope.bcc, isEmpty);
        }
        expect(find.text(_strings.mailCloudSubmissionAccepted), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'uncertain cloud send retains draft and never automatically resubmits',
    (tester) async {
      final harness = _Harness();
      await _show(tester, harness);
      await _connect(tester);
      harness.provider!.outcome = MailSubmissionOutcome.uncertain;
      await _send(
        tester,
        to: 'first@example.test, second@example.test',
        cc: 'copied@example.test',
        bcc: 'private@example.test',
      );
      expect(find.text(_strings.mailSubmissionUncertain), findsOneWidget);
      expect(harness.provider!.submissions, hasLength(1));
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
      expect(find.text(_strings.mailRetryAcknowledgement), findsOneWidget);
      expect(
        tester.widget<TextField>(_composeField(_strings.to)).controller!.text,
        'first@example.test, second@example.test',
      );
      expect(
        tester
            .widget<TextField>(_composeField(_strings.mailCc))
            .controller!
            .text,
        'copied@example.test',
      );
      expect(
        tester
            .widget<TextField>(_composeField(_strings.mailBcc))
            .controller!
            .text,
        'private@example.test',
      );
      final send = find.widgetWithText(FilledButton, _strings.send);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(harness.provider!.submissions, hasLength(1));
      harness.provider!.outcome = MailSubmissionOutcome.accepted;
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await _pump(tester);
      await tester.ensureVisible(send);
      await tester.tap(send);
      await _pump(tester);
      expect(harness.provider!.submissions, hasLength(2));
      for (final submission in harness.provider!.submissions) {
        expect(submission.envelope.recipients, [
          'first@example.test',
          'second@example.test',
          'copied@example.test',
          'private@example.test',
        ]);
        expect(
          utf8.decode(submission.wire.bytes),
          isNot(contains('private@example.test')),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} Reply all submits visible groups and explicit Bcc with threading',
      (tester) async {
        final harness = _Harness();
        await _show(tester, harness, service: service);
        await _connect(tester);
        final provider = harness.provider!..replyParticipants = true;
        await tester.tap(find.text('Cloud message'));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.replyAll));
        await _pump(tester);
        expect(find.byType(StudioMailComposeDialog), findsOneWidget);
        expect(
          tester.widget<TextField>(_composeField(_strings.to)).controller!.text,
          'author@example.test, teammate@example.test',
        );
        expect(
          tester
              .widget<TextField>(_composeField(_strings.mailCc))
              .controller!
              .text,
          'copied@example.test',
        );
        expect(
          tester
              .widget<TextField>(_composeField(_strings.mailBcc))
              .controller!
              .text,
          isEmpty,
        );
        await tester.enterText(
          _composeField(_strings.mailBcc),
          'private-copy@example.test',
        );
        final send = find.widgetWithText(FilledButton, _strings.send);
        await tester.ensureVisible(send);
        await tester.tap(send);
        await _pump(tester);
        final submission = provider.submissions.single;
        expect(submission.envelope.recipients, [
          'author@example.test',
          'teammate@example.test',
          'copied@example.test',
          'private-copy@example.test',
        ]);
        final parsed = const QudsMimeCodec().parse(submission.wire.bytes);
        expect(parsed.status, MailParseStatus.complete);
        final message = parsed.message!;
        expect(message.envelope.to.map((address) => address.address), [
          'author@example.test',
          'teammate@example.test',
        ]);
        expect(message.envelope.cc.single.address, 'copied@example.test');
        expect(message.envelope.bcc, isEmpty);
        expect(message.envelope.inReplyTo, '<parent@example.test>');
        expect(message.envelope.references, [
          '<root@example.test>',
          '<parent@example.test>',
        ]);
        final wire = utf8.decode(submission.wire.bytes);
        expect(wire, isNot(contains('private-copy@example.test')));
        expect(wire, isNot(contains('hidden@example.test')));
        expect(find.text(_strings.mailCloudSubmissionAccepted), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${service.name} Reply all refuses an ambiguous source address',
      (tester) async {
        final harness = _Harness();
        await _show(tester, harness, service: service);
        await _connect(tester);
        harness.provider!.envelopeOverride = MailEnvelope(
          subject: 'Cloud message',
          from: const [MailAddress('writer@example.test')],
          to: const [MailAddress('first@example.test;second@example.test')],
        );
        await tester.tap(find.text('Cloud message'));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.replyAll));
        await _pump(tester);
        expect(find.byType(StudioMailComposeDialog), findsNothing);
        expect(
          find.text(_strings.mailReplyRecipientsUnavailable),
          findsOneWidget,
        );
        expect(harness.provider!.submissions, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'definite rejected sends retain drafts and show Retry-After without resending',
    (tester) async {
      final harness = _Harness();
      final drafts = MemoryStudioMailDrafts();
      await _show(tester, harness, drafts: drafts);
      await _connect(tester);
      harness.provider!
        ..outcome = MailSubmissionOutcome.rejected
        ..submissionProblem = const MailProblem(
          MailProblemCode.quotaExceeded,
          retryAfter: Duration(seconds: 45),
        );
      await _send(tester);
      expect(drafts.records.values.single.submissionUncertain, isFalse);
      expect(
        find.textContaining(_strings.mailCloudRetryAfter(45)),
        findsOneWidget,
      );
      expect(
        find.textContaining(_strings.ewsSubmissionRejected),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 60));
      expect(harness.provider!.submissions, hasLength(1));
      await tester.tap(find.byTooltip(_strings.compose));
      await _pump(tester);
      expect(
        tester
            .widget<TextField>(_composeField(_strings.subject))
            .controller!
            .text,
        'Cloud send',
      );
      expect(find.text(_strings.mailRetryAcknowledgement), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, _strings.send),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('narrow cloud setup and mailbox remain usable without overflow', (
    tester,
  ) async {
    final harness = _Harness();
    await _show(tester, harness, size: const Size(400, 850));
    await _connect(tester);
    await tester.tap(find.text('Cloud message'));
    await _pump(tester);
    expect(find.byType(MailMessageView), findsOneWidget);
    expect(find.byTooltip(_strings.mailCloudDelete), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} archive action preserves the exact fetched original and provider provenance',
      (tester) async {
        final harness = _Harness();
        MailMessage? archived;
        var archiveCalls = 0;
        MailArchiveOrigin? provenance;
        await _show(
          tester,
          harness,
          service: service,
          archiveWriter: (message, {required origin, cancellation}) async {
            archiveCalls++;
            archived = message;
            provenance = origin;
            return _archiveSuccess(message);
          },
        );
        await _connect(tester);
        final provider = harness.provider!;
        final original = provider.message();
        provider.messageGate = Completer<MailResult<MailMessage>>();
        await tester.tap(find.text('Cloud message'));
        await _pump(tester);
        expect(archived, isNull);
        provider.messageGate!.complete(MailSuccess(original));
        await _pump(tester);
        await tester.tap(find.byTooltip(_strings.archiveCurrentMessage));
        await _pump(tester);
        expect(archived, same(original));
        expect(archived!.raw.bytes, orderedEquals(original.raw.bytes));
        expect(archived!.envelope.bcc.single.address, 'hidden@example.test');
        expect(archived!.attachments.single.displayName, 'cloud.bin');
        expect(
          archived!.attachments.single.content.bytes,
          orderedEquals([0, 1, 2, 255, 13, 10]),
        );
        expect(provenance!.source, '${service.name} · reader@example.test');
        expect(provenance!.folder, 'Inbox');
        expect(provenance!.sourceMessageId, 'remote-message');
        expect(provider.reads, 1);
        expect(provider.commands, isEmpty);
        expect(provider.submissions, isEmpty);
        expect(archiveCalls, 1);
        expect(find.text(_strings.archiveMessageStored), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final service in MailCloudService.values) {
    testWidgets(
      '${service.name} folder archive receives the selected account and folder',
      (tester) async {
        final harness = _Harness();
        MailArchiveProfile? profile;
        await _show(
          tester,
          harness,
          service: service,
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
        expect(profile!.source, '${service.name} · reader@example.test');
        expect(profile!.folder, 'Inbox');
        expect(profile!.kind, MailArchiveProfileKind.mailbox);
        expect(profile!.includeSubfolders, isFalse);
        expect(profile!.id, startsWith('studio-mailbox:'));
        expect(harness.provider!.reads, 0);
        expect(harness.provider!.commands, isEmpty);
        expect(harness.provider!.submissions, isEmpty);
        expect(
          find.text(_strings.archiveFolderCounts(3, 1, 0, 2, 300)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
