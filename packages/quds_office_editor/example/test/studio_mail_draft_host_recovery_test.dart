import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_drafts_dialog.dart';
import 'package:quds_office_studio/studio_mail_drafts_strings.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _sender = 'reader@example.test';
const _ewsEndpoint = 'https://mail.example.test/EWS/Exchange.asmx';
const _legacy = StudioMailDraft(
  to: 'first@example.test',
  bcc: 'hidden@example.test',
  subject: 'Retained A',
  body: 'Keep the original draft A.',
);
const _sibling = StudioMailDraft(
  to: 'second@example.test',
  subject: 'Independent B',
  body: 'Keep the independent draft B.',
);
const _wire =
    'From: Author <author@example.test>\r\n'
    'To: Reader <reader@example.test>\r\n'
    'Subject: Incoming message\r\n'
    'Message-ID: <source@example.test>\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: multipart/mixed; boundary=source\r\n\r\n'
    '--source\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n'
    'A received body.\r\n'
    '--source\r\nContent-Type: application/octet-stream\r\n'
    'Content-Disposition: attachment; filename=received.bin\r\n'
    'Content-Transfer-Encoding: base64\r\n\r\nAAH/gA==\r\n'
    '--source--\r\n';

StudioMailDraftAccount _identity(bool ews) => StudioMailDraftAccount(
  provider: ews ? 'ews' : 'imap',
  endpoint: ews ? _ewsEndpoint : 'imaps://imap.example.test:993',
  login: ews ? jsonEncode(['', _sender]) : _sender,
  sender: _sender,
);

/// Deliberately implements catalog without Outbox: the capabilities have
/// independent ownership contracts. All durable data still uses real SQLite.
final class _CatalogProxy
    implements StudioMailDraftStore, StudioMailDraftCatalog {
  _CatalogProxy(this.delegate, {this.reportedAccount});
  final SqliteStudioMailDraftStore delegate;
  final MailAccountId? reportedAccount;
  bool failNextLoad = false;
  int loads = 0;
  int closes = 0;

  @override
  MailAccountId get account => reportedAccount ?? delegate.account;
  @override
  String get selectedDraftId => delegate.selectedDraftId;
  @override
  int get selectionEpoch => delegate.selectionEpoch;
  @override
  Future<StudioMailStoredDraft?> load() async {
    loads++;
    if (failNextLoad) {
      failNextLoad = false;
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    return delegate.load();
  }

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => delegate.save(draft, submissionUncertain: submissionUncertain);
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => delegate.saveRejectedDraft(
    draft,
    wasPreviouslyUncertain: wasPreviouslyUncertain,
  );
  @override
  Future<void> clear() => delegate.clear();
  @override
  Future<void> close() async {
    closes++;
    await delegate.close();
  }

  @override
  Future<StudioMailDraftCatalogPage> listDrafts({String? afterId}) =>
      delegate.listDrafts(afterId: afterId);
  @override
  Future<StudioMailStoredDraft> selectDraft(StudioMailDraftSummary summary) =>
      delegate.selectDraft(summary);
  @override
  Future<StudioMailStoredDraft> createDraft(StudioMailDraft initial) =>
      delegate.createDraft(initial);
  @override
  Future<void> discardDraft(StudioMailDraftSummary summary) =>
      delegate.discardDraft(summary);
}

final class _Credentials implements StudioMailCredentialStore {
  @override
  Future<StudioMailCredentials?> load() async => null;
  @override
  Future<bool> save(StudioMailCredentials credentials) async => true;
  @override
  Future<bool> clear() async => true;
}

final class _Loader implements StudioMailMessageLoader {
  @override
  Future<Uint8List> fetch(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) async => Uint8List.fromList(utf8.encode(_wire));
  @override
  Future<void> markRead(mail.Mailbox mailbox, mail.MimeMessage header) async {}
  @override
  void cancel() {}
  @override
  void dispose() {}
}

final class _Client extends Fake implements mail.MailClient {
  final inbox = mail.Mailbox(
    encodedName: 'INBOX',
    encodedPath: 'INBOX',
    flags: <mail.MailboxFlag>[],
    pathSeparator: '/',
    uidValidity: 41,
  );
  @override
  mail.Mailbox get selectedMailbox => inbox;
  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<mail.Mailbox>> listMailboxes({
    List<mail.MailboxFlag>? order,
  }) async => [inbox];
  @override
  Future<List<mail.MimeMessage>> fetchMessages({
    mail.Mailbox? mailbox,
    int count = 20,
    int page = 1,
    mail.FetchPreference fetchPreference =
        mail.FetchPreference.fullWhenWithinSize,
  }) async => [mail.MimeMessage.parseFromText(_wire)..uid = 7];
}

final class _Provider extends Fake implements MailEwsProvider {
  _Provider(this.configuration, {this.canSend = true});
  final MailEwsConfiguration configuration;
  final bool canSend;
  @override
  MailAccountId get account => configuration.account;
  MailMailboxId get inbox => MailMailboxId('inbox', account: account);
  MailOpaqueIdentity get remote => MailOpaqueIdentity(
    account: account,
    provider: MailProviderKind.ews,
    value: 'one',
  );
  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => MailSuccess(
    MailCapabilities([
      MailCapability.mail,
      MailCapability.folders,
      if (canSend) MailCapability.send,
    ]),
  );
  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([MailMailbox(id: inbox, displayName: 'Inbox')]);
  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => MailSuccess(
    MailHeaderPage(
      messages: [
        MailHeaderRecord(
          id: MailMessageId('one'),
          remote: remote,
          envelope: MailEnvelope(
            subject: 'Incoming message',
            from: [const MailAddress('author@example.test')],
          ),
        ),
      ],
    ),
  );
  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    final parsed = const QudsMimeCodec()
        .parse(Uint8List.fromList(utf8.encode(_wire)))
        .message!;
    return MailSuccess(
      MailMessage(
        raw: parsed.raw,
        envelope: parsed.envelope,
        body: parsed.body,
        attachments: parsed.attachments,
        remoteIdentity: remote,
      ),
    );
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Finder _dialogClose(Type type) => find.descendant(
  of: find.byType(type),
  matching: find.byTooltip(_strings.close),
);
Finder get _openDrafts => find.byKey(const ValueKey('studio-mail-open-drafts'));

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpOutboxWidgets(tester);
}

Future<SqliteOutboxFixture> _fixture(WidgetTester tester, bool ews) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1050));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fixture = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(_identity(ews)),
  );
  addTearDown(() => awaitOutboxOperation(tester, fixture.close()));
  final seed = await awaitOutboxOperation(tester, fixture.openLoaded());
  await awaitOutboxOperation(
    tester,
    seed.save(_legacy, submissionUncertain: true),
  );
  await awaitOutboxOperation(tester, seed.createDraft(_sibling));
  await awaitOutboxOperation(tester, seed.close());
  return fixture;
}

Future<List<_CatalogProxy>> _mount(
  WidgetTester tester,
  SqliteOutboxFixture fixture,
  bool ews, {
  bool foreign = false,
  bool canSend = true,
}) async {
  final proxies = <_CatalogProxy>[];
  Future<StudioMailDraftStore> open(StudioMailDraftAccount identity) async {
    final delegate = await fixture.open(identity) as SqliteStudioMailDraftStore;
    final proxy = _CatalogProxy(
      delegate,
      reportedAccount: foreign
          ? MailAccountId('other', profile: identity.profile)
          : null,
    );
    proxies.add(proxy);
    return proxy;
  }

  final Widget host = ews
      ? StudioMailEwsDialog(
          strings: _strings,
          providerFactory: (configuration, _) =>
              _Provider(configuration, canSend: canSend),
          draftStoreFactory: open,
        )
      : StudioMailDialog(
          strings: _strings,
          clientFactory: (_) => _Client(),
          messageLoaderFactory: (_) => _Loader(),
          credentialStore: _Credentials(),
          draftStoreFactory: open,
        );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => host),
            child: const Text('Open host'),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Open host'));
  if (ews) {
    await tester.enterText(
      find.byKey(const ValueKey('ews-endpoint')),
      _ewsEndpoint,
    );
    await tester.enterText(find.byKey(const ValueKey('ews-mailbox')), _sender);
    await tester.enterText(find.byKey(const ValueKey('ews-login')), _sender);
    await tester.enterText(
      find.byKey(const ValueKey('ews-password')),
      'fixture',
    );
    await _press(tester, find.byKey(const ValueKey('ews-connect')));
  } else {
    await tester.enterText(_field(_strings.emailAddress), _sender);
    await tester.enterText(_field(_strings.password), 'fixture');
    await _press(
      tester,
      find.widgetWithText(SwitchListTile, _strings.manualServers),
    );
    await tester.enterText(_field(_strings.imapHost), 'imap.example.test');
    await tester.enterText(_field(_strings.smtpHost), 'smtp.example.test');
    await _press(tester, find.widgetWithText(FilledButton, _strings.connect));
  }
  expect(_openDrafts, findsOneWidget);
  expect(proxies, hasLength(1));
  return proxies;
}

Future<void> _compose(WidgetTester tester, bool ews) => _press(
  tester,
  ews
      ? find.byTooltip(_strings.compose)
      : find.widgetWithText(TextButton, _strings.compose),
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void main() {
  testWidgets(
    'read-only EWS account can resume and save local drafts without sending',
    (tester) async {
      final fixture = await _fixture(tester, true);
      final proxies = await _mount(tester, fixture, true, canSend: false);
      await _press(tester, _openDrafts);
      await _press(tester, find.text('Independent B'));
      final composer = tester.widget<StudioMailComposeDialog>(
        find.byType(StudioMailComposeDialog),
      );
      expect(composer.canSend, isFalse);
      expect(composer.onQueueDraft, isNull);
      expect(composer.previousSubmissionUncertain, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, _strings.send),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        _field(_strings.subject),
        'Edited without send access',
      );
      await _press(tester, find.text(_strings.mailDraftSaveClose));
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(
        (await awaitOutboxOperation(
          tester,
          proxies.single.load(),
        ))!.draft.subject,
        'Edited without send access',
      );
      expect(
        (await awaitOutboxOperation(
          tester,
          proxies.single.listDrafts(),
        )).drafts,
        hasLength(2),
      );
      await _compose(tester, true);
      expect(
        tester
            .widget<StudioMailComposeDialog>(
              find.byType(StudioMailComposeDialog),
            )
            .canSend,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpOutboxWidgets(tester);
    },
  );

  for (final ews in [false, true]) {
    final host = ews ? 'EWS' : 'IMAP';

    testWidgets(
      '$host rejects a foreign catalog-only owner before loading its content',
      (tester) async {
        final fixture = await _fixture(tester, ews);
        final proxies = await _mount(tester, fixture, ews, foreign: true);
        expect(proxies.single.loads, 0);
        expect(proxies.single.closes, 1);
        expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
        await _compose(tester, ews);
        expect(proxies, hasLength(2));
        expect(proxies.every((proxy) => proxy.loads == 0), isTrue);
        expect(find.byType(StudioMailComposeDialog), findsNothing);
        final page = _value(
          await awaitOutboxOperation(
            tester,
            fixture.repository.listDrafts(fixture.identity.account),
          ),
        );
        expect(page.drafts, hasLength(2));
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpOutboxWidgets(tester);
      },
    );

    testWidgets(
      '$host selected snapshot opens without a fallible redundant reload',
      (tester) async {
        final fixture = await _fixture(tester, ews);
        final proxies = await _mount(tester, fixture, ews);
        final proxy = proxies.single;
        await _press(tester, _openDrafts);
        proxy.failNextLoad = true;
        await _press(tester, find.text('Independent B'));
        expect(find.byType(StudioMailComposeDialog), findsOneWidget);
        expect(
          tester.widget<TextField>(_field(_strings.subject)).controller!.text,
          'Independent B',
        );
        expect(proxy.loads, 1);
        expect(proxy.failNextLoad, isTrue);
        final composer = tester.widget<StudioMailComposeDialog>(
          find.byType(StudioMailComposeDialog),
        );
        expect(composer.previousSubmissionUncertain, isFalse);
        final page = await awaitOutboxOperation(tester, proxy.listDrafts());
        expect(
          page.drafts
              .singleWhere((item) => item.subject == 'Retained A')
              .submissionUncertain,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpOutboxWidgets(tester);
      },
    );

    testWidgets(
      '$host failed reload after selected deletion cannot resurrect the old draft',
      (tester) async {
        final fixture = await _fixture(tester, ews);
        final proxies = await _mount(tester, fixture, ews);
        final proxy = proxies.single;
        await _press(tester, _openDrafts);
        await _press(
          tester,
          find.byKey(
            const ValueKey(
              'studio-mail-delete-draft-studio-foreground-compose',
            ),
          ),
        );
        await _press(
          tester,
          find.byKey(const ValueKey('studio-mail-confirm-delete-draft')),
        );
        proxy.failNextLoad = true;
        await _press(tester, _dialogClose(StudioMailDraftsDialog));
        expect(proxy.closes, 1);
        expect(find.text(_strings.mailDraftListFailed), findsOneWidget);
        final retained = _value(
          await awaitOutboxOperation(
            tester,
            fixture.repository.listDrafts(fixture.identity.account),
          ),
        );
        expect(retained.drafts.single.envelope.subject, 'Independent B');
        await _compose(tester, ews);
        expect(proxies, hasLength(2));
        expect(find.byType(StudioMailComposeDialog), findsOneWidget);
        expect(
          tester.widget<TextField>(_field(_strings.subject)).controller!.text,
          isEmpty,
        );
        final composer = tester.widget<StudioMailComposeDialog>(
          find.byType(StudioMailComposeDialog),
        );
        expect(composer.previousSubmissionUncertain, isFalse);
        final after = _value(
          await awaitOutboxOperation(
            tester,
            fixture.repository.listDrafts(fixture.identity.account),
          ),
        );
        expect(after.drafts.single.envelope.subject, 'Independent B');
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpOutboxWidgets(tester);
      },
    );

    testWidgets(
      '$host retained composer callback rejects A to B to A selection changes',
      (tester) async {
        final fixture = await _fixture(tester, ews);
        final proxies = await _mount(tester, fixture, ews);
        final proxy = proxies.single;
        await _compose(tester, ews);
        final callback = tester
            .widget<StudioMailComposeDialog>(
              find.byType(StudioMailComposeDialog),
            )
            .onSaveDraft!;
        final rows = (await awaitOutboxOperation(
          tester,
          proxy.listDrafts(),
        )).drafts;
        final a = rows.singleWhere((item) => item.subject == 'Retained A');
        final b = rows.singleWhere((item) => item.subject == 'Independent B');
        await awaitOutboxOperation(tester, proxy.selectDraft(b));
        await awaitOutboxOperation(tester, proxy.selectDraft(a));
        await expectLater(
          callback(
            const StudioMailDraft(
              to: '',
              subject: 'Stale overwrite',
              body: 'late',
            ),
          ),
          throwsA(isA<StudioMailDraftStoreException>()),
        );
        final stored = await awaitOutboxOperation(tester, proxy.load());
        expect(stored!.draft.subject, 'Retained A');
        expect(stored.submissionUncertain, isTrue);
        expect(
          (await awaitOutboxOperation(tester, proxy.listDrafts())).drafts,
          hasLength(2),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpOutboxWidgets(tester);
      },
    );

    for (final forward in [false, true]) {
      testWidgets(
        '$host ${forward ? 'complete forward' : 'reply'} preserves the retained uncertain draft',
        (tester) async {
          final fixture = await _fixture(tester, ews);
          final proxies = await _mount(tester, fixture, ews);
          final proxy = proxies.single;
          await _press(tester, find.text('Incoming message').first);
          await _press(
            tester,
            find.byTooltip(
              forward ? _strings.mailForwardWithAttachments : _strings.reply,
            ),
          );
          expect(find.byType(StudioMailComposeDialog), findsOneWidget);
          final composer = tester.widget<StudioMailComposeDialog>(
            find.byType(StudioMailComposeDialog),
          );
          expect(composer.previousSubmissionUncertain, isFalse);
          expect(composer.initialDraft!.body, contains('A received body.'));
          expect(
            composer.initialDraft!.thread.inReplyTo,
            forward ? isNull : '<source@example.test>',
          );
          expect(
            composer.initialDraft!.attachments.items.length,
            forward ? 1 : 0,
          );
          if (forward) {
            expect(
              composer.initialDraft!.attachments.items.single.content
                  .copyBytes(),
              [0, 1, 255, 128],
            );
            expect(composer.initialDraft!.to, isEmpty);
          } else {
            expect(composer.initialDraft!.to, 'author@example.test');
          }
          final page = await awaitOutboxOperation(tester, proxy.listDrafts());
          expect(page.drafts, hasLength(3));
          final retained = page.drafts.singleWhere(
            (item) => item.subject == 'Retained A',
          );
          expect(retained.submissionUncertain, isTrue);
          expect(retained.bcc, 'hidden@example.test');
          expect(retained.id, isNot(proxy.selectedDraftId));
          final stored = _value(
            await awaitOutboxOperation(
              tester,
              fixture.repository.loadDraft(proxy.account, retained.id),
            ),
          )!;
          expect(stored.body.plainText, _legacy.body);
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpOutboxWidgets(tester);
        },
      );
    }
  }
}
