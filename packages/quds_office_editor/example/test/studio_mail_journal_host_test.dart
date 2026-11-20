@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_bulk_status.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_flag_journal.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _success = MailSuccess<MailUnit>(MailUnit.value);
Finder _key(String value) => find.byKey(ValueKey(value));
MailMessageList _list(WidgetTester tester) =>
    tester.widget(find.byType(MailMessageList));
StudioMailBulkStatus _status(WidgetTester tester) =>
    tester.widget(find.byType(StudioMailBulkStatus));
Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

final class _Incoming extends mail.ImapClient {
  @override
  Future<void> abort() async {}
}

final class _Outgoing extends mail.SmtpClient {
  _Outgoing() : super('test.invalid');
  @override
  Future<void> abort() async {}
}

final class _ImapClient extends Fake implements mail.MailClient {
  final _incoming = _Incoming();
  final _outgoing = _Outgoing();
  mail.Mailbox? selected;
  @override
  mail.Mailbox? get selectedMailbox => selected;
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
  }) async => [
    mail.Mailbox(
      encodedName: 'INBOX',
      encodedPath: 'INBOX',
      pathSeparator: '/',
      flags: [mail.MailboxFlag.inbox],
    )..uidValidity = 71,
  ];
  @override
  Future<mail.Mailbox> selectMailbox(
    mail.Mailbox mailbox, {
    bool enableCondStore = false,
    mail.QResyncParameters? qresync,
  }) async => selected = mailbox;
}

final class _Credentials extends Fake implements StudioMailCredentialStore {
  @override
  Future<StudioMailCredentials?> load() async => null;
  @override
  Future<bool> save(StudioMailCredentials credentials) async => true;
  @override
  Future<bool> clear() async => true;
}

final class _ImapBrowser
    implements
        StudioMailMessageLoader,
        StudioMailMailboxBrowser,
        StudioMailMailboxRecords,
        StudioMailMessageActions,
        StudioMailBulkMessageActions {
  _ImapBrowser(this.harness);
  final _Harness harness;
  @override
  final account = MailAccountId(
    'imap-live-connection',
    profile: MailProfileId('ephemeral', hostId: 'native-test'),
  );
  final observations = Map<mail.MimeMessage, MailHeaderRecord>.identity();
  @override
  Future<StudioMailHeaderPage> fetchHeaders(
    mail.Mailbox mailbox, {
    MailCursor? cursor,
    int limit = 50,
  }) async {
    final messages = [
      for (var uid = 1; uid <= 3; uid++)
        mail.MimeMessage.fromEnvelope(
          mail.Envelope(
            subject: 'Frozen subject $uid',
            from: [mail.MailAddress('Writer', 'writer@example.test')],
          ),
          uid: uid,
          flags: [mail.MessageFlags.seen],
        ),
    ];
    for (final message in messages) {
      observations[message] = MailHeaderRecord(
        id: MailMessageId('message-${message.uid}'),
        remote: MailImapIdentity(
          mailbox: MailMailboxId(mailbox.path, account: account),
          uidValidity: mailbox.uidValidity!,
          uid: message.uid!,
        ),
        envelope: MailEnvelope(subject: message.decodeSubject()!),
        flags: const MailMessageFlags(isRead: true),
      );
    }
    return StudioMailHeaderPage(messages: messages);
  }

  @override
  MailHeaderRecord observedHeader(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) => observations[header]!;
  @override
  MailImapIdentity bulkIdentity(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) => observedHeader(mailbox, header).remote as MailImapIdentity;
  @override
  Future<MailResult<MailUnit>> applyBulkFlag(
    MailOperation operation,
    MailOperationLease lease,
  ) => harness.record(operation);
  @override
  Future<Uint8List> fetch(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) async => Uint8List.fromList(
    utf8.encode('Subject: Frozen subject ${header.uid}\r\n\r\nSynthetic body.'),
  );
  @override
  Future<MailMessage> fetchMessage(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) async {
    final record = observedHeader(mailbox, header);
    return MailMessage(
      raw: MailBytes(await fetch(mailbox, header)),
      envelope: record.envelope,
      body: const MailBody(plainText: 'Synthetic body.'),
      localId: record.id,
      remoteIdentity: record.remote,
    );
  }

  @override
  Future<void> markRead(mail.Mailbox mailbox, mail.MimeMessage header) async {}
  @override
  Future<void> setRead(
    mail.Mailbox mailbox,
    mail.MimeMessage header, {
    required bool read,
  }) async =>
      throw StateError('Explicit flags must use the durable bulk path.');
  @override
  Future<void> setFlagged(
    mail.Mailbox mailbox,
    mail.MimeMessage header, {
    required bool flagged,
  }) async =>
      throw StateError('Explicit flags must use the durable bulk path.');
  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _Provider extends Fake implements MailProvider {
  _Provider(this.harness, this.account);
  final _Harness harness;
  @override
  final MailAccountId account;
  List<MailHeaderRecord> get headers => [
    for (var i = 1; i <= 3; i++)
      MailHeaderRecord(
        id: MailMessageId('message-$i'),
        remote: MailOpaqueIdentity(
          account: account,
          provider: harness.kind,
          value: 'remote-$i',
        ),
        envelope: MailEnvelope(subject: 'Frozen subject $i'),
        flags: const MailMessageFlags(isRead: true),
      ),
  ];
  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => MailSuccess(
    MailCapabilities(const [MailCapability.mail, MailCapability.folders]),
  );
  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([
    MailMailbox(
      id: MailMailboxId('inbox', account: account),
      displayName: 'Inbox',
    ),
  ]);
  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => MailSuccess(MailHeaderPage(messages: headers));
  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    final record = headers.firstWhere((header) => header.remote == identity);
    return MailSuccess(
      MailMessage(
        raw: MailBytes(
          Uint8List.fromList(
            utf8.encode(
              'Subject: ${record.envelope.subject}\r\n\r\nSynthetic body.',
            ),
          ),
        ),
        envelope: record.envelope,
        body: const MailBody(plainText: 'Synthetic body.'),
        localId: record.id,
        remoteIdentity: record.remote,
      ),
    );
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) => harness.record(operation);
}

final class _EwsProvider extends _Provider implements MailEwsProvider {
  _EwsProvider(_Harness harness, MailEwsConfiguration configuration)
    : super(harness, configuration.account);
}

final class _CloudProvider extends _Provider implements MailCloudProvider {
  _CloudProvider(_Harness harness, MailCloudConfiguration configuration)
    : super(harness, configuration.account);
  @override
  void dispose() {}
}

final class _Tokens extends Fake implements MailCloudTokenSource {
  @override
  void dispose() {}
}

final class _Harness {
  _Harness(this.kind);
  final MailProviderKind kind;
  TestMailFlagJournal? _fixture;
  TestMailFlagJournal get fixture => _fixture!;
  final commands = <MailOperation>[];
  final atDispatch = <MailStoredFlagBatch>[];
  Future<MailResult<MailUnit>> Function(MailOperation)? respond;
  Future<StudioMailDraftStore> openStore(
    StudioMailDraftAccount identity,
  ) async {
    _fixture = await TestMailFlagJournal.create(identity: identity);
    return fixture.owner;
  }

  Future<MailResult<MailUnit>> record(MailOperation operation) async {
    commands.add(operation);
    final id = operation.id.substring(0, operation.id.lastIndexOf(':'));
    final snapshot = await fixture.store.load(id);
    if (snapshot == null)
      throw StateError('Provider reached before durable intent.');
    atDispatch.add(snapshot);
    return respond == null ? _success : await respond!(operation);
  }

  Widget dialog() {
    if (kind == MailProviderKind.imap) {
      final client = _ImapClient();
      final browser = _ImapBrowser(this);
      return StudioMailDialog(
        strings: _strings,
        credentialStore: _Credentials(),
        clientFactory: (_) => client,
        messageLoaderFactory: (_) => browser,
        draftStoreFactory: openStore,
      );
    }
    if (kind == MailProviderKind.ews) {
      return StudioMailEwsDialog(
        strings: _strings,
        draftStoreFactory: openStore,
        providerFactory: (configuration, credentials) =>
            _EwsProvider(this, configuration),
      );
    }
    return StudioMailEwsDialog.cloud(
      strings: _strings,
      service: kind == MailProviderKind.gmail
          ? MailCloudService.gmail
          : MailCloudService.microsoft365,
      initialClientId: 'synthetic-desktop-client',
      draftStoreFactory: openStore,
      cloudAuthorizer:
          ({
            required configuration,
            required account,
            required openBrowser,
            required lease,
            log,
          }) async => MailSuccess(_Tokens()),
      cloudProviderFactory:
          ({required configuration, required tokenSource, log}) =>
              _CloudProvider(this, configuration),
    );
  }

  Future<void> dispose() async => _fixture?.dispose();
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (predicate()) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('The synthetic host did not settle.');
}

Future<void> _show(WidgetTester tester, _Harness harness) async {
  tester.view
    ..physicalSize = const Size(1400, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.runAsync(harness.dispose));
  await tester.pumpWidget(MaterialApp(home: harness.dialog()));
  await tester.pump(const Duration(milliseconds: 350));
  if (harness.kind == MailProviderKind.imap) {
    await tester.enterText(
      _field(_strings.emailAddress),
      'reader@example.test',
    );
    await tester.enterText(_field(_strings.password), 'synthetic-password');
    await tester.tap(
      find.widgetWithText(SwitchListTile, _strings.manualServers),
    );
    await tester.pump();
    await tester.enterText(_field(_strings.imapHost), 'imap.example.test');
    await tester.enterText(_field(_strings.smtpHost), 'smtp.example.test');
    await tester.ensureVisible(find.text(_strings.connect));
    await tester.tap(find.text(_strings.connect));
  } else if (harness.kind == MailProviderKind.ews) {
    await tester.enterText(
      _key('ews-endpoint'),
      'https://mail.example.test/EWS/Exchange.asmx',
    );
    await tester.enterText(_key('ews-mailbox'), 'reader@example.test');
    await tester.enterText(_key('ews-login'), 'reader');
    await tester.enterText(_key('ews-password'), 'synthetic-password');
    await tester.tap(_key('ews-connect'));
  } else {
    await tester.enterText(_key('cloud-mailbox'), 'reader@example.test');
    await tester.tap(_key('cloud-connect'));
  }
  await _until(
    tester,
    () =>
        harness._fixture != null &&
        find.byType(MailMessageList).evaluate().length == 1 &&
        !_list(tester).busy,
  );
  expect(_key('studio-mail-open-activity'), findsOneWidget);
}

void _bulk(WidgetTester tester) {
  final list = _list(tester);
  list.onBulkAction!(
    MailBulkFlagAction.flag,
    list.items.map((item) => item.id).toList(),
  );
}

void main() {
  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    testWidgets(
      '${kind.name} actual host journals bulk and single flags before provider dispatch',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        _bulk(tester);
        await _until(
          tester,
          () => harness.commands.length == 3 && !_list(tester).busy,
        );
        expect(_status(tester).report.confirmedCount, 3);
        expect(harness.atDispatch, hasLength(3));
        for (var i = 0; i < 3; i++) {
          final saved = harness.atDispatch[i];
          expect(saved.summary.complete, isFalse);
          expect(saved.summary.mailbox.account, harness.fixture.account);
          expect(saved.summary.uncertainCount, 1);
          expect(saved.summary.confirmedCount, i);
          expect(saved.summary.unattemptedCount, 2 - i);
        }
        final firstId = _list(tester).items.first.id;
        _list(tester).onOpen(firstId);
        await _until(
          tester,
          () =>
              find.byType(MailMessageView).evaluate().length == 1 &&
              !_list(tester).busy,
        );
        final unflag = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == _strings.ewsUnflag,
        );
        await tester.ensureVisible(unflag);
        await tester.tap(unflag);
        await _until(
          tester,
          () => harness.commands.length == 4 && !_list(tester).busy,
        );
        expect(harness.commands.last, isA<MailSetFlagged>());
        expect((harness.commands.last as MailSetFlagged).flagged, isFalse);
        expect(harness.atDispatch.last.summary.totalCount, 1);
        expect(harness.atDispatch.last.summary.uncertainCount, 1);
        await tester.tap(_key('studio-mail-open-activity'));
        await _until(
          tester,
          () =>
              _key('studio-mail-activity-dialog').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(find.byType(ListTile), findsNWidgets(2));
        expect(harness.commands, hasLength(4));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(harness.fixture.reopen);
        final page = (await tester.runAsync(
          () => harness.fixture.store.list(),
        ))!;
        expect(page.batches, hasLength(2));
        expect(page.batches.map((batch) => batch.confirmedCount).toSet(), {
          1,
          3,
        });
        expect(harness.commands, hasLength(4));
      },
    );

    testWidgets(
      '${kind.name} actual host stops before dispatch when intent cannot commit',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        harness.fixture.failWrites = true;
        _bulk(tester);
        await _until(
          tester,
          () =>
              find.byType(StudioMailBulkStatus).evaluate().isNotEmpty &&
              _status(tester).report.persistenceProblem != null &&
              !_list(tester).busy,
        );
        expect(harness.commands, isEmpty);
        expect(_status(tester).report.unattemptedCount, 3);
        expect(_list(tester).bulkActionsEnabled, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(harness.fixture.reopen);
        expect(
          (await tester.runAsync(() => harness.fixture.store.list()))!.batches,
          isEmpty,
        );
      },
    );

    testWidgets(
      '${kind.name} retiring the actual host waits for its durable late acknowledgement',
      (tester) async {
        final harness = _Harness(kind);
        final response = Completer<MailResult<MailUnit>>();
        harness.respond = (_) => response.future;
        await _show(tester, harness);
        _bulk(tester);
        await _until(tester, () => harness.atDispatch.length == 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        response.complete(_success);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        await tester.runAsync(harness.fixture.reopen);
        final page = (await tester.runAsync(
          () => harness.fixture.store.list(),
        ))!;
        expect(page.batches, hasLength(1));
        final saved = (await tester.runAsync(
          () => harness.fixture.store.load(page.batches.single.id),
        ))!;
        expect(saved!.report.confirmedCount, 1);
        expect(saved.report.uncertainCount, 0);
        expect(saved.report.unattemptedCount, 2);
        expect(harness.commands, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
