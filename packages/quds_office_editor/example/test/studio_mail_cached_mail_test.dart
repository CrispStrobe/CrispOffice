import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_cached_mail.dart';
import 'package:quds_office_studio/studio_mail_cached_strings.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
final _captured = DateTime.utc(2026, 11, 20, 12, 34, 56);

StudioMailDraftAccount _identity([String provider = 'imap']) =>
    StudioMailDraftAccount(
      provider: provider,
      endpoint: provider == 'imap'
          ? 'imaps://mail.example.test:993'
          : 'https://mail.example.test/v1',
      login: 'reader@example.test',
      sender: 'reader@example.test',
    );

MailHeaderRecord _header(
  StudioMailDraftAccount identity,
  int id, {
  String folder = 'Inbox',
}) => MailHeaderRecord(
  id: MailMessageId('message-$id'),
  remote: identity.provider == MailProviderKind.imap
      ? MailImapIdentity(
          mailbox: MailMailboxId(folder, account: identity.account),
          uidValidity: 23,
          uid: id,
        )
      : MailOpaqueIdentity(
          account: identity.account,
          provider: identity.provider,
          value: 'remote-$id',
        ),
  envelope: MailEnvelope(
    subject: 'Saved message $id',
    from: const [MailAddress('author@example.test', displayName: 'Author')],
    sentAt: _captured,
  ),
  flags: id == 1 ? const MailMessageFlags(isFlagged: true) : null,
);

MailMessage _message(MailHeaderRecord header) => MailMessage(
  raw: MailBytes(
    utf8.encode('Subject: ${header.envelope.subject}\r\n\r\nSaved body'),
  ),
  envelope: header.envelope,
  body: const MailBody(plainText: 'Local content, available offline.'),
  localId: header.id,
  remoteIdentity: header.remote,
);

MailCachedMailboxView _view(
  StudioMailDraftAccount identity, {
  String folder = 'Inbox',
  List<MailHeaderRecord>? headers,
  bool hasMore = true,
}) => MailCachedMailboxView(
  mailbox: MailMailbox(
    id: MailMailboxId(folder, account: identity.account),
    displayName: folder,
  ),
  revision: 7,
  capturedAt: _captured,
  headers: headers ?? [_header(identity, 1), _header(identity, 2)],
  hasMore: hasMore,
);

/// Fakes expose only the local storage contracts. Any write or draft access is
/// a test failure; there is no transport, OAuth or credential dependency here.
class _Mailbox implements StudioMailMailboxStore {
  _Mailbox(this.account);
  @override
  final MailAccountId account;
  final views = <MailMailboxId, MailCachedMailboxView>{};
  final bodies = <MailMessageId, MailMessage>{};
  Completer<void>? listGate;
  Completer<void>? bodyGate;
  bool failList = false;
  bool failBody = false;
  int listReads = 0;
  int bodyReads = 0;

  @override
  Future<List<MailCachedMailboxSummary>> listViews() async {
    listReads++;
    await listGate?.future;
    if (failList) throw StateError('storage unavailable');
    return [for (final view in views.values) view.summary];
  }

  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) async =>
      views[mailbox];

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) async {
    bodyReads++;
    await bodyGate?.future;
    if (failBody) throw StateError('storage unavailable');
    return bodies[header.id];
  }

  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => throw StateError('Offline UI must never save a mailbox view');

  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => throw StateError('Offline UI must never save a message');
}

class _Owner implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.mailboxStore);
  @override
  final _Mailbox mailboxStore;
  int closes = 0;
  int closeFailures = 0;
  Completer<void>? closeGate;

  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Offline mailbox must not load or create a draft');
  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Offline mailbox must not edit a draft');
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Offline mailbox must not edit a draft');
  @override
  Future<void> clear() =>
      throw StateError('Offline mailbox must not clear a draft');
  @override
  Future<void> close() async {
    closes++;
    await closeGate?.future;
    if (closeFailures > 0) {
      closeFailures--;
      throw StateError('close unavailable');
    }
  }
}

(_Owner, _Mailbox) _fixture(StudioMailDraftAccount identity) {
  final mailbox = _Mailbox(identity.account);
  final view = _view(identity);
  mailbox.views[view.mailbox.id] = view;
  mailbox.bodies[view.headers.first.id] = _message(view.headers.first);
  return (_Owner(mailbox), mailbox);
}

Future<void> _show(
  WidgetTester tester,
  StudioMailDraftAccount identity,
  StudioMailDraftStoreFactory factory, {
  bool Function()? isCurrent,
  StudioStrings strings = _strings,
  Size size = const Size(1200, 850),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpOutboxWidgets(tester);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => Directionality(
                textDirection: strings.language == StudioLanguage.ar
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: StudioMailCachedMailDialog(
                  strings: strings,
                  identity: identity,
                  isCurrent: isCurrent ?? () => true,
                  draftStoreFactory: factory,
                ),
              ),
            ),
            child: const Text('Open offline'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open offline'));
  await pumpOutboxWidgets(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await pumpOutboxWidgets(tester);
}

Finder get _close => find.byKey(const ValueKey('studio-mail-cache-close'));
Finder get _back => find.byKey(const ValueKey('studio-mail-cache-back'));

void main() {
  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    testWidgets('$provider reads saved headers and body without draft access', (
      tester,
    ) async {
      final identity = _identity(provider);
      final (owner, mailbox) = _fixture(identity);
      await _show(tester, identity, (_) async => owner);
      expect(find.text(_strings.mailCachePartial), findsOneWidget);
      expect(
        find.text(_strings.mailCacheSnapshot(_captured, 2)),
        findsOneWidget,
      );
      final list = tester.widget<MailMessageList>(find.byType(MailMessageList));
      expect(list.hasMore, isFalse);
      expect(list.onLoadMore, isNull);
      expect(list.items.last.isRead, isNull);
      expect(list.items.last.isFlagged, isNull);
      expect(mailbox.bodyReads, 0);
      await _tap(tester, find.text('Saved message 1'));
      final reader = tester.widget<MailMessageView>(
        find.byType(MailMessageView),
      );
      expect(
        reader.controller.result.message!.localId,
        MailMessageId('message-1'),
      );
      expect(reader.controller.decodedText, contains('Local content'));
      expect(reader.externalResources, isA<MailDenyExternalResources>());
      expect(reader.onOpenApprovedLink, isNull);
      expect(reader.onOpenAttachmentReadOnly, isNull);
      expect(mailbox.bodyReads, 1);
      await _tap(tester, _close);
      expect(owner.closes, 1);
      expect(find.byType(StudioMailCachedMailDialog), findsNothing);
    });
  }

  testWidgets('missing body keeps compact selection and search through Back', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    await _show(
      tester,
      identity,
      (_) async => owner,
      size: const Size(500, 850),
    );
    await tester.enterText(find.byType(TextField), 'message 2');
    await pumpOutboxWidgets(tester);
    expect(find.text('Saved message 1'), findsNothing);
    await _tap(tester, find.text('Saved message 2'));
    expect(find.text(_strings.mailCacheMissingBody), findsOneWidget);
    expect(find.byType(MailMessageView), findsNothing);
    await _tap(tester, _back);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'message 2',
    );
    final list = tester.widget<MailMessageList>(find.byType(MailMessageList));
    expect(list.selectedId, 'message-2');
    expect(mailbox.bodyReads, 1);
  });

  testWidgets('resize preserves the loaded list filter and selected reader', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    await _show(tester, identity, (_) async => owner);
    await tester.enterText(find.byType(TextField), 'message 1');
    await pumpOutboxWidgets(tester);
    await _tap(tester, find.text('Saved message 1'));
    await tester.binding.setSurfaceSize(const Size(500, 850));
    await pumpOutboxWidgets(tester);
    expect(find.byType(MailMessageView), findsOneWidget);
    await _tap(tester, _back);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'message 1',
    );
    expect(mailbox.bodyReads, 1);
  });

  testWidgets('switching saved folders resets reader and filter scope', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    final other = _view(
      identity,
      folder: 'Archive',
      headers: [_header(identity, 3, folder: 'Archive')],
      hasMore: false,
    );
    mailbox.views[other.mailbox.id] = other;
    await _show(tester, identity, (_) async => owner);
    await tester.enterText(find.byType(TextField), 'message 1');
    await pumpOutboxWidgets(tester);
    await _tap(tester, find.byKey(const ValueKey('studio-mail-cache-folders')));
    await _tap(tester, find.text('Archive').last);
    expect(find.text('Saved message 3'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text(_strings.mailCachePartial), findsNothing);
  });

  testWidgets('empty saved catalog is explicit and does not open drafts', (
    tester,
  ) async {
    final identity = _identity();
    final owner = _Owner(_Mailbox(identity.account));
    await _show(tester, identity, (_) async => owner);
    expect(find.text(_strings.mailCacheEmpty), findsOneWidget);
    expect(find.byType(MailMessageList), findsNothing);
    expect(find.byKey(const ValueKey('studio-mail-cache-error')), findsNothing);
  });

  testWidgets('close waits for pending open and releases a late owner once', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    final open = Completer<StudioMailDraftStore>();
    await _show(tester, identity, (_) => open.future);
    await _tap(tester, _close);
    expect(find.byType(StudioMailCachedMailDialog), findsOneWidget);
    expect(owner.closes, 0);
    open.complete(owner);
    await pumpOutboxWidgets(tester);
    expect(owner.closes, 1);
    expect(mailbox.listReads, 0);
    expect(find.byType(StudioMailCachedMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal before open completion releases the late owner', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    final open = Completer<StudioMailDraftStore>();
    await _show(tester, identity, (_) => open.future);
    await tester.pumpWidget(const SizedBox.shrink());
    open.complete(owner);
    await pumpOutboxWidgets(tester);
    expect(owner.closes, 1);
    expect(mailbox.listReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close waits for pending message read before releasing owner', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.bodyGate = Completer<void>();
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, find.text('Saved message 1'));
    await _tap(tester, _close);
    expect(owner.closes, 0);
    expect(find.byType(StudioMailCachedMailDialog), findsOneWidget);
    mailbox.bodyGate!.complete();
    await pumpOutboxWidgets(tester);
    expect(owner.closes, 1);
    expect(find.byType(StudioMailCachedMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account invalidation refuses a delayed body', (tester) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.bodyGate = Completer<void>();
    var current = true;
    await _show(tester, identity, (_) async => owner, isCurrent: () => current);
    await _tap(tester, find.text('Saved message 1'));
    current = false;
    mailbox.bodyGate!.complete();
    await pumpOutboxWidgets(tester);
    expect(find.byType(MailMessageView), findsNothing);
    await _tap(tester, _close);
    expect(owner.closes, 1);
  });

  testWidgets('wrong-account storage owner is rejected and released', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(_identity('ews'));
    await _show(tester, identity, (_) async => owner);
    expect(owner.closes, 1);
    expect(mailbox.listReads, 0);
    expect(
      find.byKey(const ValueKey('studio-mail-cache-error')),
      findsOneWidget,
    );
    expect(find.byType(MailMessageList), findsNothing);
  });

  testWidgets('mismatching saved body identity is refused before rendering', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.bodies[MailMessageId('message-1')] = _message(_header(identity, 9));
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, find.text('Saved message 1'));
    expect(find.byType(MailMessageView), findsNothing);
    expect(
      find.byKey(const ValueKey('studio-mail-cache-error')),
      findsOneWidget,
    );
  });

  testWidgets('read failure remains an error and keeps saved headers', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.failBody = true;
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, find.text('Saved message 1'));
    expect(find.text('Saved message 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('studio-mail-cache-error')),
      findsOneWidget,
    );
    expect(find.text(_strings.mailCacheMissingBody), findsNothing);
    expect(find.byType(MailMessageView), findsNothing);
  });

  testWidgets('failed catalog read is not reported as an empty catalog', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.failList = true;
    await _show(tester, identity, (_) async => owner);
    expect(find.text(_strings.mailCacheEmpty), findsNothing);
    expect(
      find.byKey(const ValueKey('studio-mail-cache-error')),
      findsOneWidget,
    );
    expect(owner.closes, 1);
  });

  testWidgets('failed close keeps ownership visible and offers close retry', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, _) = _fixture(identity);
    owner.closeFailures = 1;
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, _close);
    expect(find.byType(StudioMailCachedMailDialog), findsOneWidget);
    expect(find.text(_strings.mailCacheCloseFailed), findsWidgets);
    expect(owner.closes, 1);
    await _tap(tester, _close);
    expect(owner.closes, 2);
    expect(find.byType(StudioMailCachedMailDialog), findsNothing);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      'narrow ${language.name} saved workspace has no layout overflow',
      (tester) async {
        final identity = _identity();
        final (owner, _) = _fixture(identity);
        await _show(
          tester,
          identity,
          (_) async => owner,
          strings: StudioStrings(language),
          size: const Size(420, 660),
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Saved message 2'));
        expect(
          find.text(StudioStrings(language).mailCacheMissingBody),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, _back);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real SQLite snapshot and cached body reopen through same owner',
    (tester) async {
      final identity = _identity();
      final fixture = await awaitOutboxOperation(
        tester,
        SqliteOutboxFixture.create(identity),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await awaitOutboxOperation(tester, fixture.close());
      });
      final seed = await awaitOutboxOperation(tester, fixture.open(identity));
      final store = (seed as StudioMailMailboxStoreOwner).mailboxStore;
      final view = _view(identity);
      final lease = MailAccountSession(identity.account).begin();
      await awaitOutboxOperation(
        tester,
        store.saveView(view.mailbox, view.headers, hasMore: true, lease: lease),
      );
      await awaitOutboxOperation(
        tester,
        store.cacheMessage(
          view.headers.first,
          _message(view.headers.first),
          lease: lease,
        ),
      );
      await awaitOutboxOperation(tester, seed.close());
      await _show(tester, identity, fixture.open);
      for (
        var i = 0;
        i < 100 && find.text('Saved message 1').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await _tap(tester, find.text('Saved message 1'));
      for (
        var i = 0;
        i < 100 && find.byType(MailMessageView).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final reader = tester.widget<MailMessageView>(
        find.byType(MailMessageView),
      );
      expect(reader.controller.decodedText, contains('Local content'));
      await _tap(tester, _close);
      final check = await awaitOutboxOperation(tester, fixture.openLoaded());
      expect(await awaitOutboxOperation(tester, check.load()), isNull);
      expect(await awaitOutboxOperation(tester, check.loadOutbox()), isEmpty);
    },
  );
}
