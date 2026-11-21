import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_cached_mail.dart';
import 'package:quds_office_studio/studio_mail_cached_strings.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
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
  MailEnvelope? envelope,
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
  envelope:
      envelope ??
      MailEnvelope(
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

/// Fakes expose only local storage. Any save or draft access is a test failure;
/// explicit confirmed cleanup is separately counted. No transport is present.
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
  bool failClear = false;
  Completer<void>? clearGate;
  MailCacheCleanupReport? cleanupReport;
  int listReads = 0;
  int bodyReads = 0;
  int clearCalls = 0;

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

  @override
  Future<MailCacheCleanupReport> clearCache() async {
    clearCalls++;
    await clearGate?.future;
    if (failClear) throw StateError('cleanup unavailable');
    final report =
        cleanupReport ??
        MailCacheCleanupReport(
          removedViews: views.length,
          evictedBodies: bodies.length,
          removedHeaders: views.values.fold(
            0,
            (count, view) => count + view.headers.length,
          ),
          hasMore: false,
          retainedBodies: 0,
        );
    views.clear();
    bodies.clear();
    return report;
  }
}

/// A repository-only live adapter. Events never invoke a provider or a body
/// load, and cancellation can be held independently of owner shutdown.
class _LiveMailbox extends _Mailbox implements StudioMailMailboxWatchStore {
  _LiveMailbox(super.account);

  final _catalogs =
      <StreamController<MailResult<List<MailCachedMailboxSummary>>>>[];
  final _folders =
      <
        MailMailboxId,
        List<StreamController<MailResult<MailCachedMailboxView?>>>
      >{};
  Completer<void>? cancellationGate;
  int folderCancellations = 0;
  int catalogCancellations = 0;

  @override
  Stream<MailResult<List<MailCachedMailboxSummary>>> watchViews() {
    late final StreamController<MailResult<List<MailCachedMailboxSummary>>>
    controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(
            MailSuccess([for (final view in views.values) view.summary]),
          );
        }
      }),
      onCancel: () async {
        catalogCancellations++;
        await cancellationGate?.future;
      },
    );
    _catalogs.add(controller);
    return controller.stream;
  }

  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    late final StreamController<MailResult<MailCachedMailboxView?>> controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(MailSuccess(views[mailbox]));
        }
      }),
      onCancel: () async {
        folderCancellations++;
        await cancellationGate?.future;
      },
    );
    _folders.putIfAbsent(mailbox, () => []).add(controller);
    return controller.stream;
  }

  void publish(MailCachedMailboxView view, {bool notifyCatalog = true}) {
    views[view.mailbox.id] = view;
    _emitView(view.mailbox.id, MailSuccess(view));
    if (notifyCatalog) _emitCatalog();
  }

  void refreshCatalog() => _emitCatalog();

  void failCatalog() {
    for (final controller in _catalogs) {
      if (controller.hasListener) {
        controller.add(
          const MailFailure(MailProblem(MailProblemCode.storageFailure)),
        );
      }
    }
  }

  void remove(MailMailboxId mailbox) {
    views.remove(mailbox);
    _emitView(mailbox, const MailSuccess(null));
    _emitCatalog();
  }

  void fail(MailMailboxId mailbox) => _emitView(
    mailbox,
    const MailFailure(MailProblem(MailProblemCode.storageFailure)),
  );

  void _emitView(
    MailMailboxId mailbox,
    MailResult<MailCachedMailboxView?> event,
  ) {
    for (final controller in _folders[mailbox] ?? const []) {
      if (controller.hasListener) controller.add(event);
    }
  }

  void _emitCatalog() {
    for (final controller in _catalogs) {
      if (controller.hasListener) {
        controller.add(
          MailSuccess([for (final view in views.values) view.summary]),
        );
      }
    }
  }

  Future<void> closeStreams() async {
    if (cancellationGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    for (final controller in [
      ..._catalogs,
      for (final controllers in _folders.values) ...controllers,
    ]) {
      await controller.close();
    }
  }
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

(_Owner, _LiveMailbox) _liveFixture(StudioMailDraftAccount identity) {
  final mailbox = _LiveMailbox(identity.account);
  final view = _view(identity);
  mailbox.views[view.mailbox.id] = view;
  mailbox.bodies[view.headers.first.id] = _message(view.headers.first);
  return (_Owner(mailbox), mailbox);
}

MailCachedMailboxView _updatedView(StudioMailDraftAccount identity) {
  final header = _header(identity, 1);
  return _view(
    identity,
    headers: [
      MailHeaderRecord(
        id: header.id,
        remote: header.remote,
        envelope: MailEnvelope(subject: 'Saved message 1 updated'),
        flags: const MailMessageFlags(isRead: true),
      ),
      _header(identity, 2),
    ],
  );
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
    await _pumpCachedWidgets(tester);
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
  await _pumpCachedWidgets(tester);
}

/// Stream cancellation can complete in the SDK's outer zone. Drain that queue
/// as well as widget microtasks; fake-clock pumping alone cannot retire an
/// already-completed source subscription. Pending fixture gates remain pending.
Future<void> _pumpCachedWidgets(WidgetTester tester) async {
  await pumpOutboxWidgets(tester);
  for (var turn = 0; turn < 6; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await pumpOutboxWidgets(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _pumpCachedWidgets(tester);
}

Finder get _close => find.byKey(const ValueKey('studio-mail-cache-close'));
Finder get _back => find.byKey(const ValueKey('studio-mail-cache-back'));
Finder get _clear => find.byKey(const ValueKey('studio-mail-cache-clear'));
Finder get _confirmClear =>
    find.byKey(const ValueKey('studio-mail-cache-clear-confirm'));

void main() {
  testWidgets(
    'live metadata updates preserve the selected reader and loaded query',
    (tester) async {
      final identity = _identity();
      final (owner, mailbox) = _liveFixture(identity);
      addTearDown(() => awaitOutboxOperation(tester, mailbox.closeStreams()));
      await _show(tester, identity, (_) async => owner);
      expect(find.text(_strings.mailCacheUnread(1, 1)), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'message 1');
      await _pumpCachedWidgets(tester);
      await _tap(tester, find.text('Saved message 1'));
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      mailbox.publish(_updatedView(identity));
      await _pumpCachedWidgets(tester);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(reader),
      );
      expect(reader.isDisposed, isFalse);
      final list = tester.widget<MailMessageList>(find.byType(MailMessageList));
      expect(list.selectedId, 'message-1');
      expect(list.items.first.subject, 'Saved message 1 updated');
      expect(list.items.first.isRead, isTrue);
      expect(list.items.first.isFlagged, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'message 1',
      );
      expect(find.text(_strings.mailCacheUnread(0, 1)), findsOneWidget);
      expect(mailbox.bodyReads, 1);
      expect(mailbox.clearCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live flag update during a delayed body load keeps the exact reader target',
    (tester) async {
      final identity = _identity();
      final (owner, mailbox) = _liveFixture(identity);
      addTearDown(() => awaitOutboxOperation(tester, mailbox.closeStreams()));
      mailbox.bodyGate = Completer<void>();
      await _show(tester, identity, (_) async => owner);
      await _tap(tester, find.text('Saved message 1'));
      mailbox.publish(_updatedView(identity));
      await _pumpCachedWidgets(tester);
      expect(find.byType(MailMessageView), findsNothing);
      mailbox.bodyGate!.complete();
      await _pumpCachedWidgets(tester);
      final reader = tester.widget<MailMessageView>(
        find.byType(MailMessageView),
      );
      expect(
        reader.controller.result.message!.localId,
        MailMessageId('message-1'),
      );
      expect(
        reader.controller.result.message!.remoteIdentity,
        _header(identity, 1).remote,
      );
      expect(mailbox.bodyReads, 1);
      expect(
        tester
            .widget<MailMessageList>(find.byType(MailMessageList))
            .items
            .first
            .isRead,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removed live view clears the reader, selection and counts', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _liveFixture(identity);
    addTearDown(() => awaitOutboxOperation(tester, mailbox.closeStreams()));
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, find.text('Saved message 1'));
    final reader = tester
        .widget<MailMessageView>(find.byType(MailMessageView))
        .controller;
    mailbox.remove(_view(identity).mailbox.id);
    await _pumpCachedWidgets(tester);
    expect(reader.isDisposed, isTrue);
    expect(find.byType(MailMessageView), findsNothing);
    expect(find.byType(MailMessageList), findsNothing);
    expect(
      find.byKey(const ValueKey('studio-mail-cache-unread')),
      findsNothing,
    );
    expect(find.text(_strings.mailCacheEmpty), findsOneWidget);
    expect(mailbox.bodyReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'live failures recover independently and preserve operation errors',
    (tester) async {
      final identity = _identity();
      final (owner, mailbox) = _liveFixture(identity);
      addTearDown(() => awaitOutboxOperation(tester, mailbox.closeStreams()));
      await _show(tester, identity, (_) async => owner);
      await _tap(tester, find.text('Saved message 1'));
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      mailbox.failCatalog();
      await _pumpCachedWidgets(tester);
      expect(find.text(_strings.mailCacheReadFailed), findsOneWidget);
      mailbox.refreshCatalog();
      await _pumpCachedWidgets(tester);
      expect(
        find.byKey(const ValueKey('studio-mail-cache-error')),
        findsNothing,
      );
      mailbox.fail(_view(identity).mailbox.id);
      await _pumpCachedWidgets(tester);
      expect(find.text(_strings.mailCacheReadFailed), findsOneWidget);
      expect(find.text('Saved message 2'), findsOneWidget);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(reader),
      );
      // A fresh catalog cannot establish that the selected view recovered.
      mailbox.refreshCatalog();
      await _pumpCachedWidgets(tester);
      expect(find.text(_strings.mailCacheReadFailed), findsOneWidget);
      mailbox.failCatalog();
      // A fresh selected view cannot establish that the catalog recovered.
      mailbox.publish(_updatedView(identity), notifyCatalog: false);
      await _pumpCachedWidgets(tester);
      expect(find.text(_strings.mailCacheReadFailed), findsOneWidget);
      mailbox.refreshCatalog();
      await _pumpCachedWidgets(tester);
      expect(
        find.byKey(const ValueKey('studio-mail-cache-error')),
        findsNothing,
      );

      mailbox.failClear = true;
      await _tap(tester, _clear);
      await _tap(tester, _confirmClear);
      expect(find.text(_strings.mailCacheClearFailed), findsOneWidget);
      mailbox.failCatalog();
      await _pumpCachedWidgets(tester);
      final combined = tester.widget<Text>(
        find.byKey(const ValueKey('studio-mail-cache-error')),
      );
      expect(combined.data, contains(_strings.mailCacheClearFailed));
      expect(combined.data, contains(_strings.mailCacheReadFailed));
      mailbox.publish(_updatedView(identity));
      await _pumpCachedWidgets(tester);
      expect(find.text(_strings.mailCacheClearFailed), findsOneWidget);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(reader),
      );
      expect(mailbox.bodyReads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('close drains live subscriptions before closing their owner', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _liveFixture(identity);
    addTearDown(() => awaitOutboxOperation(tester, mailbox.closeStreams()));
    mailbox.cancellationGate = Completer<void>();
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, _close);
    expect(owner.closes, 0);
    expect(find.byType(StudioMailCachedMailDialog), findsOneWidget);
    mailbox.publish(_updatedView(identity));
    await _pumpCachedWidgets(tester);
    expect(find.text('Saved message 1 updated'), findsNothing);
    expect(owner.closes, 0);
    mailbox.cancellationGate!.complete();
    await _pumpCachedWidgets(tester);
    expect(mailbox.catalogCancellations, 1);
    expect(mailbox.folderCancellations, 1);
    expect(owner.closes, 1);
    expect(find.byType(StudioMailCachedMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    testWidgets('$provider cached search needs no body or draft access', (
      tester,
    ) async {
      final identity = _identity(provider);
      final (owner, mailbox) = _fixture(identity);
      final date = DateTime(2026, 11, 20, 12);
      final view = _view(
        identity,
        headers: [
          _header(
            identity,
            1,
            envelope: MailEnvelope(
              subject: 'Quarterly report',
              from: const [
                MailAddress('writer@example.test', displayName: 'Writer'),
              ],
              to: const [
                MailAddress('team@example.test', displayName: 'Project Team'),
              ],
              cc: const [
                MailAddress('reviewer@example.test', displayName: 'Reviewer'),
              ],
              bcc: const [MailAddress('hidden@example.test')],
              sentAt: date,
            ),
          ),
          _header(identity, 2),
        ],
      );
      mailbox.views[view.mailbox.id] = view;
      await _show(tester, identity, (_) async => owner);
      final list = tester.widget<MailMessageList>(find.byType(MailMessageList));
      final rows = list.items;
      expect(list.onBulkAction, isNull);
      expect(list.onCancelBulk, isNull);
      expect(list.bulkStatus, isNull);
      expect(
        find.byKey(const ValueKey('mail-list-bulk-actions')),
        findsNothing,
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(rows.first.date, date);
      expect(rows.first.to, contains('Project Team <team@example.test>'));
      expect(rows.first.cc, contains('reviewer@example.test'));
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'from:writer to:"Project Team" cc:reviewer subject:"Quarterly report" '
        'on:2026-11-20 is:unread is:flagged',
      );
      await _pumpCachedWidgets(tester);
      expect(find.text('Quarterly report'), findsOneWidget);
      expect(find.text('Saved message 2'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('mail-list-search')),
        'to:hidden@example.test',
      );
      await _pumpCachedWidgets(tester);
      expect(
        find.text(_strings.mailMessageListStrings.noMatches),
        findsOneWidget,
      );
      expect(mailbox.listReads, 1);
      expect(mailbox.bodyReads, 0);
      expect(mailbox.clearCalls, 0);
      expect(tester.takeException(), isNull);
    });

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
    await _pumpCachedWidgets(tester);
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
    await _pumpCachedWidgets(tester);
    await _tap(tester, find.text('Saved message 1'));
    await tester.binding.setSurfaceSize(const Size(500, 850));
    await _pumpCachedWidgets(tester);
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
    await _pumpCachedWidgets(tester);
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
    await _pumpCachedWidgets(tester);
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
    await _pumpCachedWidgets(tester);
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
    await _pumpCachedWidgets(tester);
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
    await _pumpCachedWidgets(tester);
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
    expect(owner.closes, 0);
    expect(
      find.byKey(const ValueKey('studio-mail-cache-clear')),
      findsOneWidget,
    );
    await _tap(tester, _close);
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
        await tester.scrollUntilVisible(
          find.text('Saved message 2'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(MailMessageList),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await _tap(tester, find.text('Saved message 2'));
        expect(
          find.text(StudioStrings(language).mailCacheMissingBody),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, _back);
        expect(tester.takeException(), isNull);
        await _tap(tester, _clear);
        expect(
          find.text(StudioStrings(language).mailCacheClearHelp),
          findsOneWidget,
        );
        expect(
          Directionality.of(tester.element(find.byType(AlertDialog))),
          language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text(StudioStrings(language).cancel));
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

  testWidgets(
    'cache cleanup requires confirmation and cancel preserves the view',
    (tester) async {
      final identity = _identity();
      final (owner, mailbox) = _fixture(identity);
      await _show(tester, identity, (_) async => owner);
      await _tap(tester, _clear);
      expect(find.text(_strings.mailCacheClearHelp), findsOneWidget);
      expect(mailbox.clearCalls, 0);
      await _tap(tester, find.text(_strings.cancel));
      expect(mailbox.clearCalls, 0);
      expect(find.text('Saved message 1'), findsOneWidget);
      expect(mailbox.bodies, hasLength(1));
    },
  );

  testWidgets('confirmed cleanup clears loaded state and releases reader', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, find.text('Saved message 1'));
    final reader = tester
        .widget<MailMessageView>(find.byType(MailMessageView))
        .controller;
    await _tap(tester, _clear);
    await _tap(tester, _confirmClear);
    expect(mailbox.clearCalls, 1);
    expect(mailbox.listReads, 2);
    expect(mailbox.views, isEmpty);
    expect(mailbox.bodies, isEmpty);
    expect(reader.isDisposed, isTrue);
    expect(find.byType(MailMessageView), findsNothing);
    expect(find.byType(MailMessageList), findsNothing);
    expect(find.text(_strings.mailCacheEmpty), findsOneWidget);
    expect(find.text(_strings.mailCacheCleared(1, 1, 2)), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, _strings.mailCacheClear),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'one confirmed cleanup reports more work without an automatic loop',
    (tester) async {
      final identity = _identity();
      final (owner, mailbox) = _fixture(identity);
      mailbox.cleanupReport = const MailCacheCleanupReport(
        removedViews: 1,
        evictedBodies: 1,
        removedHeaders: 1,
        hasMore: true,
        retainedBodies: 3,
      );
      await _show(tester, identity, (_) async => owner);
      await _tap(tester, _clear);
      await _tap(tester, _confirmClear);
      await _pumpCachedWidgets(tester);
      expect(mailbox.clearCalls, 1);
      expect(find.text(_strings.mailCacheClearMore), findsOneWidget);
      expect(find.text(_strings.mailCacheProtected(3)), findsOneWidget);
    },
  );

  testWidgets('cleanup failure retains the current view and reader', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.failClear = true;
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, find.text('Saved message 1'));
    final reader = tester
        .widget<MailMessageView>(find.byType(MailMessageView))
        .controller;
    await _tap(tester, _clear);
    await _tap(tester, _confirmClear);
    expect(mailbox.clearCalls, 1);
    expect(reader.isDisposed, isFalse);
    expect(find.byType(MailMessageView), findsOneWidget);
    expect(find.text('Saved message 2'), findsOneWidget);
    expect(find.text(_strings.mailCacheClearFailed), findsOneWidget);
  });

  testWidgets('valid owner offers cleanup after a failed catalog read', (
    tester,
  ) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.failList = true;
    await _show(tester, identity, (_) async => owner);
    expect(owner.closes, 0);
    mailbox.failList = false;
    await _tap(tester, _clear);
    await _tap(tester, _confirmClear);
    expect(mailbox.clearCalls, 1);
    expect(find.text(_strings.mailCacheEmpty), findsOneWidget);
    expect(find.byKey(const ValueKey('studio-mail-cache-error')), findsNothing);
  });

  testWidgets('close waits for a pending confirmed cleanup', (tester) async {
    final identity = _identity();
    final (owner, mailbox) = _fixture(identity);
    mailbox.clearGate = Completer<void>();
    await _show(tester, identity, (_) async => owner);
    await _tap(tester, _clear);
    await _tap(tester, _confirmClear);
    await _tap(tester, _close);
    expect(owner.closes, 0);
    mailbox.clearGate!.complete();
    await _pumpCachedWidgets(tester);
    expect(owner.closes, 1);
    expect(find.byType(StudioMailCachedMailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed native cleanup restores quota-blocked draft admission after reopen',
    (tester) async {
      final identity = _identity();
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('cached-mail-quota-'),
      ))!;
      final owners = <StudioMailDraftStore>[];
      Future<StudioMailDraftStore> open(StudioMailDraftAccount account) async {
        final owner = await openStudioMailDraftStore(
          account,
          appDirectory: directory,
          limits: const MailStoreLimits(maxAccountBytes: 16384),
        );
        owners.add(owner);
        return owner;
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await awaitOutboxOperation(tester, () async {
          for (final owner in owners) {
            await owner.close();
          }
          await directory.delete(recursive: true);
        }());
      });
      final draft = StudioMailDraft(
        to: '',
        subject: 'Preserve new work',
        body: 'x' * 5000,
      );
      final quotaFailure = await awaitOutboxOperation(tester, () async {
        final seed = await open(identity);
        final store = (seed as StudioMailMailboxStoreOwner).mailboxStore;
        final view = _view(identity, headers: [_header(identity, 1)]);
        final lease = MailAccountSession(identity.account).begin();
        await store.saveView(
          view.mailbox,
          view.headers,
          hasMore: false,
          lease: lease,
        );
        final header = view.headers.single;
        await store.cacheMessage(
          header,
          MailMessage(
            raw: MailBytes(Uint8List.fromList(List<int>.filled(8000, 65))),
            envelope: header.envelope,
            body: MailBody(plainText: 'b' * 1000),
            localId: header.id,
            remoteIdentity: header.remote,
          ),
          lease: lease,
        );
        await seed.load();
        MailProblemCode? failure;
        try {
          await seed.save(draft, submissionUncertain: false);
        } on StudioMailDraftStoreException catch (error) {
          failure = error.code;
        }
        await seed.close();
        return failure;
      }());
      expect(quotaFailure, MailProblemCode.quotaExceeded);
      await _show(tester, identity, open);
      for (
        var i = 0;
        i < 200 && find.text('Saved message 1').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      expect(find.text('Saved message 1'), findsOneWidget);
      await _tap(tester, _clear);
      await _tap(tester, _confirmClear);
      for (
        var i = 0;
        i < 200 &&
            find
                .byKey(const ValueKey('studio-mail-cache-cleared'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      expect(
        find.byKey(const ValueKey('studio-mail-cache-cleared')),
        findsOneWidget,
      );
      await _tap(tester, _close);
      for (
        var i = 0;
        i < 200 &&
            find.byType(StudioMailCachedMailDialog).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byType(StudioMailCachedMailDialog), findsNothing);
      final reopenedBody = await awaitOutboxOperation(tester, () async {
        final reopened = await open(identity);
        await reopened.load();
        await reopened.save(draft, submissionUncertain: false);
        final body = (await reopened.load())!.draft.body;
        await reopened.close();
        return body;
      }());
      expect(reopenedBody, draft.body);
    },
  );
}
