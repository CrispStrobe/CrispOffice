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

const _strings = StudioStrings(StudioLanguage.en);
final _identity = StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://mail.example.test:993',
  login: 'retained-reader@example.test',
  sender: 'retained-reader@example.test',
);
final _savedAt = DateTime.utc(2026, 11, 22, 8, 15);

MailMailbox _folder(String name) => MailMailbox(
  id: MailMailboxId(name, account: _identity.account),
  displayName: name,
);

MailHeaderRecord _header(
  int number, {
  String folder = 'Inbox',
  String prefix = 'Synchronized',
  int generation = 17,
  bool isRead = false,
}) => MailHeaderRecord(
  id: MailMessageId('saved-$number'),
  remote: MailImapIdentity(
    mailbox: _folder(folder).id,
    uidValidity: generation,
    uid: number,
  ),
  envelope: MailEnvelope(
    subject: '$prefix message $number',
    from: const [MailAddress('author@example.test', displayName: 'Author')],
    sentAt: _savedAt,
  ),
  flags: MailMessageFlags(isRead: isRead),
);

MailMessage _body(MailHeaderRecord header) => MailMessage(
  raw: MailBytes(utf8.encode('Subject: Saved\r\n\r\nRetained local body')),
  localId: header.id,
  remoteIdentity: header.remote,
  envelope: header.envelope,
  body: const MailBody(plainText: 'Retained local body for offline reading.'),
);

final class _SyncWatch {
  _SyncWatch(this.mailbox, this.limit, this.offset, this.controller);
  final MailMailboxId mailbox;
  final int limit;
  final int offset;
  final StreamController<MailResult<MailMailboxSyncSnapshot?>> controller;
}

/// Both catalogs share one local owner. The fake has no provider or credential
/// port; all draft access and storage writes fail if navigation attempts them.
final class _Store
    implements
        StudioMailMailboxStore,
        StudioMailMailboxWatchStore,
        StudioMailSyncStore {
  @override
  MailAccountId get account => _identity.account;

  final browse = <MailMailboxId, MailCachedMailboxView>{};
  final sync = <MailMailboxId, MailMailboxSyncSummary>{};
  final syncedHeaders = <MailMailboxId, List<MailHeaderRecord>>{};
  final bodies = <MailMessageId, MailMessage>{};
  final bodyTargets = <MailHeaderRecord>[];
  final browseTargets = <MailMailboxId>[];
  final syncTargets = <(MailMailboxId, int, int)>[];
  final cancellationGates = <String, Completer<void>>{};
  final cancellationFailures = <String>{};
  final cancellations = <String, int>{};
  final _browseCatalogs =
      <StreamController<MailResult<List<MailCachedMailboxSummary>>>>[];
  final _syncCatalogs =
      <StreamController<MailResult<List<MailMailboxSyncSummary>>>>[];
  final _browseWatches =
      <
        MailMailboxId,
        List<StreamController<MailResult<MailCachedMailboxView?>>>
      >{};
  final _syncWatches = <_SyncWatch>[];
  Completer<void>? bodyGate;
  bool allowCleanup = false;
  bool failBrowseCatalogRead = false;
  bool failSyncCatalogRead = false;
  int clearCalls = 0;
  int browseCatalogReads = 0;
  int syncCatalogReads = 0;

  void saveBrowse(
    List<MailHeaderRecord> headers, {
    String folder = 'Inbox',
    int revision = 1,
    bool publish = true,
  }) {
    final mailbox = _folder(folder);
    browse[mailbox.id] = MailCachedMailboxView(
      mailbox: mailbox,
      revision: revision,
      capturedAt: _savedAt,
      headers: headers,
      hasMore: false,
    );
    if (publish) {
      publishBrowseCatalog();
      for (final controller in _browseWatches[mailbox.id] ?? const []) {
        if (controller.hasListener) {
          controller.add(MailSuccess(browse[mailbox.id]));
        }
      }
    }
  }

  void saveSync(
    List<MailHeaderRecord> headers, {
    String folder = 'Inbox',
    int revision = 1,
    bool hasMore = false,
    bool publish = true,
  }) {
    final mailbox = _folder(folder);
    sync[mailbox.id] = MailMailboxSyncSummary(
      mailbox: mailbox,
      revision: revision,
      updatedAt: _savedAt,
      hasMore: hasMore,
      headerCount: headers.length,
    );
    syncedHeaders[mailbox.id] = List.of(headers);
    if (publish) publishSync();
  }

  MailMailboxSyncSnapshot? _snapshot(
    MailMailboxId mailbox,
    int limit,
    int offset,
  ) {
    final summary = sync[mailbox];
    if (summary == null) return null;
    final headers = syncedHeaders[mailbox] ?? const <MailHeaderRecord>[];
    return MailMailboxSyncSnapshot(
      summary: summary,
      headers: headers.skip(offset).take(limit).toList(),
      offset: offset,
      hasMoreHeaders: headers.length > offset + limit,
    );
  }

  Future<void> _cancel(String source) async {
    cancellations.update(source, (count) => count + 1, ifAbsent: () => 1);
    await cancellationGates[source]?.future;
    if (cancellationFailures.contains(source)) {
      throw StateError('Local subscription cancellation failed');
    }
  }

  @override
  Future<List<MailCachedMailboxSummary>> listViews() async {
    browseCatalogReads++;
    if (failBrowseCatalogRead) throw StateError('Local catalog read failed');
    return [for (final view in browse.values) view.summary];
  }

  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) async {
    browseTargets.add(mailbox);
    return browse[mailbox];
  }

  @override
  Stream<MailResult<List<MailCachedMailboxSummary>>> watchViews() {
    late final StreamController<MailResult<List<MailCachedMailboxSummary>>>
    controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(
            failBrowseCatalogRead
                ? const MailFailure(_problem)
                : MailSuccess([for (final view in browse.values) view.summary]),
          );
        }
      }),
      onCancel: () => _cancel('browse catalog'),
    );
    _browseCatalogs.add(controller);
    return controller.stream;
  }

  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    browseTargets.add(mailbox);
    late final StreamController<MailResult<MailCachedMailboxView?>> controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(MailSuccess(browse[mailbox]));
        }
      }),
      onCancel: () => _cancel('browse view'),
    );
    _browseWatches.putIfAbsent(mailbox, () => []).add(controller);
    return controller.stream;
  }

  @override
  Future<MailResult<List<MailMailboxSyncSummary>>> listSyncMailboxes() async {
    syncCatalogReads++;
    if (failSyncCatalogRead) return const MailFailure(_problem);
    return MailSuccess(sync.values.toList());
  }

  @override
  Future<MailResult<MailMailboxSyncSnapshot?>> loadSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) async {
    syncTargets.add((mailbox, limit, offset));
    return MailSuccess(_snapshot(mailbox, limit, offset));
  }

  @override
  Stream<MailResult<List<MailMailboxSyncSummary>>> watchSyncMailboxes() {
    late final StreamController<MailResult<List<MailMailboxSyncSummary>>>
    controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(
            failSyncCatalogRead
                ? const MailFailure(_problem)
                : MailSuccess(sync.values.toList()),
          );
        }
      }),
      onCancel: () => _cancel('sync catalog'),
    );
    _syncCatalogs.add(controller);
    return controller.stream;
  }

  @override
  Stream<MailResult<MailMailboxSyncSnapshot?>> watchSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) {
    syncTargets.add((mailbox, limit, offset));
    late final StreamController<MailResult<MailMailboxSyncSnapshot?>>
    controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(MailSuccess(_snapshot(mailbox, limit, offset)));
        }
      }),
      onCancel: () => _cancel('sync view'),
    );
    _syncWatches.add(_SyncWatch(mailbox, limit, offset, controller));
    return controller.stream;
  }

  static const _problem = MailProblem(MailProblemCode.storageFailure);

  void publishBrowseCatalog({bool failed = false}) {
    for (final controller in _browseCatalogs) {
      if (controller.hasListener) {
        controller.add(
          failed
              ? const MailFailure(_problem)
              : MailSuccess([for (final view in browse.values) view.summary]),
        );
      }
    }
  }

  void publishSyncCatalog({bool failed = false}) {
    for (final controller in _syncCatalogs) {
      if (controller.hasListener) {
        controller.add(
          failed
              ? const MailFailure(_problem)
              : MailSuccess(sync.values.toList()),
        );
      }
    }
  }

  void publishSync({bool notifyCatalog = true, bool failed = false}) {
    if (notifyCatalog) publishSyncCatalog();
    for (final watch in List<_SyncWatch>.of(_syncWatches)) {
      if (watch.controller.hasListener) {
        watch.controller.add(
          failed
              ? const MailFailure(_problem)
              : MailSuccess(
                  _snapshot(watch.mailbox, watch.limit, watch.offset),
                ),
        );
      }
    }
  }

  void removeSync(String folder) {
    final mailbox = _folder(folder).id;
    sync.remove(mailbox);
    syncedHeaders.remove(mailbox);
    publishSync();
  }

  void publishOldSnapshot(MailMailboxSyncSnapshot snapshot) {
    for (final watch in List<_SyncWatch>.of(_syncWatches)) {
      if (watch.controller.hasListener &&
          watch.mailbox == snapshot.mailbox.id &&
          watch.offset == snapshot.offset) {
        watch.controller.add(MailSuccess(snapshot));
      }
    }
  }

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) async {
    bodyTargets.add(header);
    await bodyGate?.future;
    return bodies[header.id];
  }

  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => throw StateError('Offline navigation cannot save a browse window');

  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => throw StateError('Offline navigation cannot download a body');

  @override
  Future<MailCacheCleanupReport> clearCache() async {
    if (!allowCleanup) throw StateError('Navigation cannot clear local mail');
    clearCalls++;
    final report = MailCacheCleanupReport(
      removedViews: browse.length,
      evictedBodies: bodies.length,
      removedHeaders: syncedHeaders.values.fold(
        0,
        (count, rows) => count + rows.length,
      ),
      retainedBodies: 0,
      hasMore: false,
    );
    browse.clear();
    sync.clear();
    syncedHeaders.clear();
    bodies.clear();
    return report;
  }

  @override
  Future<MailResult<MailUnit>> saveSyncMailbox(MailMailbox mailbox) =>
      throw StateError('Navigation cannot start synchronization');

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) =>
      throw StateError('Navigation cannot read a provider cursor');

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) => throw StateError('Navigation cannot commit provider data');

  Future<void> closeStreams() async {
    if (bodyGate case final gate? when !gate.isCompleted) gate.complete();
    for (final gate in cancellationGates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    for (final controller in [
      ..._browseCatalogs,
      ..._syncCatalogs,
      for (final watches in _browseWatches.values) ...watches,
      for (final watch in _syncWatches) watch.controller,
    ]) {
      try {
        await controller.close();
      } on StateError catch (error) {
        // A deliberately failed onCancel also completes the controller's
        // done future with that error. The dialog assertions already inspect
        // its handling; fixture disposal must consume the same known failure.
        if (error.message != 'Local subscription cancellation failed') rethrow;
      }
    }
  }
}

final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.mailboxStore);
  @override
  final _Store mailboxStore;
  int closes = 0;

  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Offline navigation cannot load a draft');

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Offline navigation cannot save a draft');

  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Offline navigation cannot save a rejected draft');

  @override
  Future<void> clear() =>
      throw StateError('Offline navigation cannot clear a draft');

  @override
  Future<void> close() async => closes++;
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _pump(WidgetTester tester) async {
  for (var turn = 0; turn < 8; turn++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

Future<_Owner> _show(
  WidgetTester tester,
  _Store store, {
  StudioLanguage language = StudioLanguage.en,
  Size size = const Size(1200, 900),
  double scale = 1,
}) async {
  final owner = _Owner(store);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.closeStreams);
    await _pump(tester);
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => Directionality(
                textDirection: language == StudioLanguage.ar
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: StudioMailCachedMailDialog(
                  strings: StudioStrings(language),
                  identity: _identity,
                  isCurrent: () => true,
                  draftStoreFactory: (identity) async {
                    expect(identity.account, _identity.account);
                    return owner;
                  },
                ),
              ),
            ),
            child: const Text('Open retained mail'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open retained mail'));
  await _pump(tester);
  return owner;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _pump(tester);
}

MailMessageList _list(WidgetTester tester) =>
    tester.widget<MailMessageList>(find.byType(MailMessageList));

DropdownButton<MailMailboxId> _folders(WidgetTester tester) => tester
    .widget<DropdownButton<MailMailboxId>>(_key('studio-mail-cache-folders'));

Future<void> _openMessage(WidgetTester tester, String id) async {
  _list(tester).onOpen(id);
  await _pump(tester);
}

List<String> _ids(WidgetTester tester) =>
    _list(tester).items.map((item) => item.id).toList();

void main() {
  testWidgets(
    'sync-only retained folder is visible in the local mailbox reader',
    (tester) async {
      final store = _Store()..saveSync([_header(1), _header(2)]);
      await _show(tester, store);
      expect(_folders(tester).items!.map((item) => item.value), [
        _folder('Inbox').id,
      ]);
      expect(_ids(tester), ['saved-1', 'saved-2']);
      expect(_key('studio-mail-cache-source'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('studio-mail-cache-source')).data,
        isNotEmpty,
      );
      expect(store.syncTargets, [(_folder('Inbox').id, 100, 0)]);
      expect(store.browseTargets, isEmpty);
      expect(store.bodyTargets, isEmpty);
      expect(find.text(_strings.mailCacheEmpty), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'folder union contains one choice per folder across both catalogs',
    (tester) async {
      final store = _Store()
        ..saveBrowse([_header(801, prefix: 'Visited')])
        ..saveBrowse([_header(802, folder: 'Archive')], folder: 'Archive')
        ..saveSync([_header(1)])
        ..saveSync([_header(2, folder: 'Sent')], folder: 'Sent');
      await _show(tester, store);
      final choices = _folders(
        tester,
      ).items!.map((item) => item.value).toList();
      expect(
        choices,
        unorderedEquals([
          _folder('Inbox').id,
          _folder('Archive').id,
          _folder('Sent').id,
        ]),
      );
      expect(choices.toSet(), hasLength(choices.length));
      _folders(tester).onChanged!(_folder('Sent').id);
      await _pump(tester);
      expect(_ids(tester), ['saved-2']);
      expect(_folders(tester).value, _folder('Sent').id);
      expect(store.bodyTargets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overlap defaults to sync and explicit source switches never mix rows',
    (tester) async {
      final store = _Store()
        ..saveBrowse([_header(801, prefix: 'Visited')])
        ..saveSync([_header(1), _header(2)]);
      await _show(tester, store);
      expect(_ids(tester), ['saved-1', 'saved-2']);
      expect(
        tester
            .widget<ChoiceChip>(_key('studio-mail-cache-source-sync'))
            .selected,
        isTrue,
      );
      expect(store.browseTargets, isEmpty);
      await _tap(tester, 'studio-mail-cache-source-browse');
      expect(_ids(tester), ['saved-801']);
      expect(
        tester
            .widget<ChoiceChip>(_key('studio-mail-cache-source-browse'))
            .selected,
        isTrue,
      );
      store.saveSync([_header(3)], revision: 2);
      await _pump(tester);
      expect(_ids(tester), ['saved-801']);
      await _tap(tester, 'studio-mail-cache-source-sync');
      expect(_ids(tester), ['saved-3']);
      expect(store.bodyTargets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sync pages stay bounded and a shrinking last page repairs its offset',
    (tester) async {
      final records = [for (var i = 1; i <= 205; i++) _header(i)];
      final store = _Store()..saveSync(records);
      await _show(tester, store);
      expect(_ids(tester), [for (var i = 1; i <= 100; i++) 'saved-$i']);
      expect(_key('studio-mail-cache-page'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(_key('studio-mail-cache-previous'))
            .onPressed,
        isNull,
      );
      await _tap(tester, 'studio-mail-cache-next');
      expect(_ids(tester), [for (var i = 101; i <= 200; i++) 'saved-$i']);
      await _tap(tester, 'studio-mail-cache-next');
      expect(_ids(tester), [for (var i = 201; i <= 205; i++) 'saved-$i']);
      expect(
        tester
            .widget<ButtonStyleButton>(_key('studio-mail-cache-next'))
            .onPressed,
        isNull,
      );
      store.saveSync(records.take(101).toList(), revision: 2);
      await _pump(tester);
      expect(_ids(tester), ['saved-101']);
      expect(store.syncTargets.last, (_folder('Inbox').id, 100, 100));
      await _tap(tester, 'studio-mail-cache-previous');
      expect(_ids(tester), [for (var i = 1; i <= 100; i++) 'saved-$i']);
      expect(store.syncTargets.every((target) => target.$2 == 100), isTrue);
      expect(store.bodyTargets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit refresh preserves selected sync page and discovers local changes',
    (tester) async {
      final store = _Store()
        ..saveSync([for (var i = 1; i <= 150; i++) _header(i)]);
      await _show(tester, store);
      await _tap(tester, 'studio-mail-cache-next');
      store.saveSync(
        [for (var i = 1; i <= 150; i++) _header(i, prefix: 'Refreshed')],
        revision: 2,
        publish: false,
      );
      await _tap(tester, 'studio-mail-cache-refresh');
      expect(_ids(tester), [for (var i = 101; i <= 150; i++) 'saved-$i']);
      expect(_list(tester).items.first.subject, 'Refreshed message 101');
      expect(store.syncTargets.last, (_folder('Inbox').id, 100, 100));
      expect(store.browseTargets, isEmpty);
      expect(store.bodyTargets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live flags preserve exact loaded reader while removal clears it',
    (tester) async {
      final selected = _header(1);
      final store = _Store()
        ..saveSync([selected, _header(2)])
        ..bodies[selected.id] = _body(selected);
      await _show(tester, store);
      await _openMessage(tester, 'saved-1');
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      store.saveSync([_header(1, isRead: true), _header(2)], revision: 2);
      await _pump(tester);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(reader),
      );
      expect(reader.isDisposed, isFalse);
      expect(_list(tester).selectedId, 'saved-1');
      expect(_list(tester).items.first.isRead, isTrue);
      expect(store.bodyTargets.single.remote, selected.remote);
      store.saveSync([_header(2)], revision: 3);
      await _pump(tester);
      expect(reader.isDisposed, isTrue);
      expect(find.byType(MailMessageView), findsNothing);
      expect(_list(tester).selectedId, isNull);
      expect(_ids(tester), ['saved-2']);
      expect(store.bodyTargets, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late body read cannot revive a removed synchronized membership',
    (tester) async {
      final selected = _header(1);
      final store = _Store()
        ..saveSync([selected, _header(2)])
        ..bodies[selected.id] = _body(selected)
        ..bodyGate = Completer<void>();
      await _show(tester, store);
      await _openMessage(tester, 'saved-1');
      store.saveSync([_header(2)], revision: 2);
      await _pump(tester);
      store.bodyGate!.complete();
      await _pump(tester);
      expect(find.byType(MailMessageView), findsNothing);
      expect(_list(tester).selectedId, isNull);
      expect(_ids(tester), ['saved-2']);
      expect(store.bodyTargets, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same local id with changed IMAP generation retires the previous reader',
    (tester) async {
      final selected = _header(1);
      final store = _Store()
        ..saveSync([selected])
        ..bodies[selected.id] = _body(selected);
      await _show(tester, store);
      await _openMessage(tester, 'saved-1');
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      store.saveSync([_header(1, generation: 18)], revision: 2);
      await _pump(tester);
      expect(reader.isDisposed, isTrue);
      expect(find.byType(MailMessageView), findsNothing);
      expect(_list(tester).selectedId, isNull);
      expect(store.bodyTargets, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'both catalog failures retain the reader and recover independently',
    (tester) async {
      final selected = _header(1);
      final store = _Store()
        ..saveBrowse([_header(801, prefix: 'Visited')])
        ..saveSync([selected, _header(2)])
        ..bodies[selected.id] = _body(selected);
      await _show(tester, store);
      await _openMessage(tester, 'saved-1');
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      store.publishBrowseCatalog(failed: true);
      store.publishSyncCatalog(failed: true);
      await _pump(tester);
      expect(_key('studio-mail-cache-error'), findsOneWidget);
      expect(_ids(tester), ['saved-1', 'saved-2']);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(reader),
      );
      store.publishBrowseCatalog();
      await _pump(tester);
      expect(_key('studio-mail-cache-error'), findsOneWidget);
      store.publishSyncCatalog();
      await _pump(tester);
      expect(_key('studio-mail-cache-error'), findsNothing);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(reader),
      );
      expect(store.bodyTargets, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected page failure keeps prior rows until a successful page event',
    (tester) async {
      final store = _Store()..saveSync([_header(1), _header(2)]);
      await _show(tester, store);
      store.publishSync(notifyCatalog: false, failed: true);
      await _pump(tester);
      expect(_key('studio-mail-cache-error'), findsOneWidget);
      expect(_ids(tester), ['saved-1', 'saved-2']);
      store.publishSyncCatalog();
      await _pump(tester);
      expect(_key('studio-mail-cache-error'), findsOneWidget);
      store.saveSync([_header(1, isRead: true), _header(2)], revision: 2);
      await _pump(tester);
      expect(_key('studio-mail-cache-error'), findsNothing);
      expect(_list(tester).items.first.isRead, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removed sync source never silently falls back to an older browse window',
    (tester) async {
      final selected = _header(1);
      final store = _Store()
        ..saveBrowse([_header(801, prefix: 'Visited')])
        ..saveSync([selected])
        ..bodies[selected.id] = _body(selected);
      await _show(tester, store);
      await _openMessage(tester, 'saved-1');
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      store.removeSync('Inbox');
      await _pump(tester);
      expect(reader.isDisposed, isTrue);
      expect(find.byType(MailMessageView), findsNothing);
      expect(find.text('Visited message 801'), findsNothing);
      expect(store.browseTargets, isEmpty);
      if (find.byType(MailMessageList).evaluate().isNotEmpty) {
        expect(_ids(tester), isEmpty);
      }
      expect(_folders(tester).items!.map((item) => item.value), [
        _folder('Inbox').id,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing retained body explains offline availability without downloading',
    (tester) async {
      final store = _Store()..saveSync([_header(1)]);
      await _show(tester, store);
      await _openMessage(tester, 'saved-1');
      expect(find.text(_strings.mailCacheMissingBody), findsOneWidget);
      expect(find.byType(MailMessageView), findsNothing);
      expect(store.bodyTargets, hasLength(1));
      expect(store.browseTargets, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in StudioLanguage.values) {
    testWidgets(
      '${language.name} retained sources and paging fit a narrow dialog',
      (tester) async {
        final store = _Store()
          ..saveBrowse([_header(801, prefix: 'Visited')])
          ..saveSync([for (var i = 1; i <= 101; i++) _header(i)]);
        await _show(
          tester,
          store,
          language: language,
          size: const Size(460, 760),
          scale: 1.1,
        );
        expect(_ids(tester), hasLength(100));
        expect(tester.takeException(), isNull);
        await _tap(tester, 'studio-mail-cache-next');
        expect(_ids(tester), ['saved-101']);
        await _openMessage(tester, 'saved-101');
        expect(
          find.text(StudioStrings(language).mailCacheMissingBody),
          findsOneWidget,
        );
        await _tap(tester, 'studio-mail-cache-back');
        await _tap(tester, 'studio-mail-cache-source-browse');
        expect(_ids(tester), ['saved-801']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final cancellation in ['browse catalog', 'sync catalog', 'sync view']) {
    testWidgets(
      'close waits for $cancellation cancellation before closing owner',
      (tester) async {
        final store = _Store()..saveSync([_header(1)]);
        final gate = Completer<void>();
        store.cancellationGates[cancellation] = gate;
        final owner = await _show(tester, store);
        await _tap(tester, 'studio-mail-cache-close');
        expect(store.cancellations[cancellation], 1);
        expect(owner.closes, 0);
        expect(find.byType(StudioMailCachedMailDialog), findsOneWidget);
        store.saveSync([_header(2)], revision: 2);
        await _pump(tester);
        expect(find.text('Synchronized message 2'), findsNothing);
        gate.complete();
        await _pump(tester);
        expect(owner.closes, 1);
        expect(store.cancellations['browse catalog'], 1);
        expect(store.cancellations['sync catalog'], 1);
        expect(store.cancellations['sync view'], 1);
        expect(find.byType(StudioMailCachedMailDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'successful cleanup revokes stale page delivery before catalog cancellation and failed reloads',
    (tester) async {
      final selected = _header(1);
      final store = _Store()
        ..saveBrowse([_header(801, prefix: 'Visited')])
        ..saveSync([selected])
        ..bodies[selected.id] = _body(selected)
        ..allowCleanup = true;
      await _show(tester, store);
      await _openMessage(tester, 'saved-1');
      final reader = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      final stale = store._snapshot(_folder('Inbox').id, 100, 0)!;
      final catalogGate = Completer<void>();
      store.cancellationGates['sync catalog'] = catalogGate;
      store.failBrowseCatalogRead = true;
      store.failSyncCatalogRead = true;
      await _tap(tester, 'studio-mail-cache-clear');
      await _tap(tester, 'studio-mail-cache-clear-confirm');
      expect(store.clearCalls, 1);
      expect(reader.isDisposed, isTrue);
      expect(find.byType(MailMessageView), findsNothing);
      store.publishOldSnapshot(stale);
      await _pump(tester);
      expect(find.text('Synchronized message 1'), findsNothing);
      expect(find.byType(MailMessageView), findsNothing);
      catalogGate.complete();
      await _pump(tester);
      expect(_key('studio-mail-cache-error'), findsOneWidget);
      expect(find.text('Synchronized message 1'), findsNothing);
      expect(find.text('Visited message 801'), findsNothing);
      expect(find.byType(MailMessageView), findsNothing);
      expect(store.bodyTargets, hasLength(1));
      expect(store.clearCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed catalog cancellation still drains the selected view and retains its owner',
    (tester) async {
      final store = _Store()
        ..saveSync([_header(1)])
        ..cancellationFailures.add('sync catalog');
      final owner = await _show(tester, store);
      await _tap(tester, 'studio-mail-cache-close');
      expect(store.cancellations['browse catalog'], 1);
      expect(store.cancellations['sync catalog'], 1);
      expect(store.cancellations['sync view'], 1);
      expect(owner.closes, 0);
      expect(
        tester.widget<Text>(_key('studio-mail-cache-error')).data,
        _strings.mailCacheCloseFailed,
      );
      expect(find.byType(StudioMailCachedMailDialog), findsOneWidget);
      store.saveSync([_header(2)], revision: 2);
      await _pump(tester);
      expect(find.text('Synchronized message 2'), findsNothing);
      // StreamSubscription may keep returning its first failed cancellation
      // future. Retrying must retain ownership rather than treating that
      // missing successful drain as permission to close the repository.
      await _tap(tester, 'studio-mail-cache-close');
      expect(owner.closes, 0);
      expect(store.cancellations['sync view'], 1);
      expect(
        tester.widget<Text>(_key('studio-mail-cache-error')).data,
        _strings.mailCacheCloseFailed,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
