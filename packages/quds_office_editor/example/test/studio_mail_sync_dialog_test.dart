@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_sync_dialog.dart';
import 'package:quds_office_studio/studio_mail_sync_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _screenshotDirectory = String.fromEnvironment('MAIL_SYNC_SCREENSHOT_DIR');
const _captureKey = ValueKey('sync-dialog-capture');
final _profile = MailProfileId('sync-dialog-profile', hostId: 'sync-tests');
final _account = MailAccountId('sync-reader', profile: _profile);
final _inbox = MailMailbox(
  id: MailMailboxId('Inbox', account: _account),
  displayName: 'Inbox',
);
final _savedAt = DateTime.utc(2026, 11, 21, 9, 15);

MailHeaderRecord _header(int id, {MailMailbox? mailbox}) => MailHeaderRecord(
  id: MailMessageId('saved-$id'),
  remote: MailImapIdentity(
    mailbox: (mailbox ?? _inbox).id,
    uidValidity: 7,
    uid: id,
  ),
  envelope: MailEnvelope(
    subject: 'Saved message $id',
    from: const [MailAddress('author@example.test', displayName: 'Author')],
    sentAt: _savedAt,
  ),
  flags: const MailMessageFlags(isRead: false),
);

MailMessage _message(MailHeaderRecord header) => MailMessage(
  raw: MailBytes(utf8.encode('Subject: Saved\r\n\r\nOffline body')),
  localId: header.id,
  remoteIdentity: header.remote,
  envelope: header.envelope,
  body: const MailBody(plainText: 'This body was saved earlier.'),
);

MailSyncRunProgress _progress({
  int pages = 1,
  bool hasMore = true,
  MailMailbox? mailbox,
}) => MailSyncRunProgress(
  mailbox: (mailbox ?? _inbox).id,
  committedPages: pages,
  upsertCount: pages * 100,
  tombstoneCount: 0,
  resetCount: 0,
  lastCommittedCursor: MailCursor(
    mailbox: (mailbox ?? _inbox).id,
    value: 'opaque-$pages',
  ),
  hasMore: hasMore,
);

MailSyncRunReport _report(MailSyncRunStatus status, {MailProblem? problem}) =>
    MailSyncRunReport(
      status: status,
      progress: _progress(hasMore: status != MailSyncRunStatus.completed),
      problem: problem,
    );

final class _ViewWatch {
  _ViewWatch(this.mailbox, this.limit, this.offset, this.controller);
  final MailMailboxId mailbox;
  final int limit;
  final int offset;
  final StreamController<MailResult<MailMailboxSyncSnapshot?>> controller;
}

/// Only local reads are available. Provider work is an explicit separate run
/// callback, and accidental writes or foreground browse-cache reads fail.
final class _Store implements StudioMailMailboxStore, StudioMailSyncStore {
  _Store({MailAccountId? account}) : account = account ?? _account;
  @override
  final MailAccountId account;
  final summaries = <MailMailboxId, MailMailboxSyncSummary>{};
  final headers = <MailMailboxId, List<MailHeaderRecord>>{};
  final bodies = <MailMessageId, MailMessage>{};
  final reads = <(MailMailboxId, int, int)>[];
  final _catalogs =
      <StreamController<MailResult<List<MailMailboxSyncSummary>>>>[];
  final _watches = <_ViewWatch>[];
  Completer<void>? readGate;
  Completer<void>? bodyGate;
  Completer<void>? cancelGate;
  bool readFails = false;
  bool bodyFails = false;
  int bodyReads = 0;
  int watchCalls = 0;
  int cancellations = 0;

  void save(
    List<MailHeaderRecord> records, {
    MailMailbox? mailbox,
    bool hasMore = true,
    int revision = 1,
  }) {
    final folder = mailbox ?? _inbox;
    summaries[folder.id] = MailMailboxSyncSummary(
      mailbox: folder,
      revision: revision,
      updatedAt: _savedAt,
      hasMore: hasMore,
      headerCount: records.length,
    );
    headers[folder.id] = records;
    publish();
  }

  MailMailboxSyncSnapshot? _snapshot(
    MailMailboxId mailbox,
    int limit,
    int offset,
  ) {
    final summary = summaries[mailbox];
    if (summary == null) return null;
    final all = headers[mailbox] ?? const <MailHeaderRecord>[];
    return MailMailboxSyncSnapshot(
      summary: summary,
      headers: all.skip(offset).take(limit).toList(),
      offset: offset,
      hasMoreHeaders: all.length > offset + limit,
    );
  }

  @override
  Future<MailResult<MailMailboxSyncSnapshot?>> loadSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) async {
    reads.add((mailbox, limit, offset));
    await readGate?.future;
    if (readFails) {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
    return MailSuccess(_snapshot(mailbox, limit, offset));
  }

  @override
  Future<MailResult<List<MailMailboxSyncSummary>>> listSyncMailboxes() async =>
      MailSuccess(summaries.values.toList());

  @override
  Stream<MailResult<List<MailMailboxSyncSummary>>> watchSyncMailboxes() {
    watchCalls++;
    late final StreamController<MailResult<List<MailMailboxSyncSummary>>>
    controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(MailSuccess(summaries.values.toList()));
        }
      }),
      onCancel: () async {
        cancellations++;
        await cancelGate?.future;
      },
    );
    _catalogs.add(controller);
    return controller.stream;
  }

  @override
  Stream<MailResult<MailMailboxSyncSnapshot?>> watchSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) {
    late final StreamController<MailResult<MailMailboxSyncSnapshot?>>
    controller;
    controller = StreamController(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (controller.hasListener) {
          controller.add(MailSuccess(_snapshot(mailbox, limit, offset)));
        }
      }),
      onCancel: () async {
        cancellations++;
        await cancelGate?.future;
      },
    );
    _watches.add(_ViewWatch(mailbox, limit, offset, controller));
    return controller.stream;
  }

  void publish() {
    for (final controller in _catalogs) {
      if (controller.hasListener) {
        controller.add(MailSuccess(summaries.values.toList()));
      }
    }
    for (final watch in List<_ViewWatch>.of(_watches)) {
      if (watch.controller.hasListener) {
        watch.controller.add(
          MailSuccess(_snapshot(watch.mailbox, watch.limit, watch.offset)),
        );
      }
    }
  }

  void failViews() {
    for (final watch in _watches) {
      if (watch.controller.hasListener) {
        watch.controller.add(
          const MailFailure(MailProblem(MailProblemCode.storageFailure)),
        );
      }
    }
  }

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) async {
    bodyReads++;
    await bodyGate?.future;
    if (bodyFails) throw StateError('private provider content must not leak');
    return bodies[header.id];
  }

  @override
  Future<List<MailCachedMailboxSummary>> listViews() =>
      throw StateError('Saved browse windows are a separate feature');
  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) =>
      throw StateError('Saved browse windows are a separate feature');
  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => throw StateError('The dialog cannot save browse windows');
  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => throw StateError('The dialog cannot download message bodies');
  @override
  Future<MailCacheCleanupReport> clearCache() =>
      throw StateError('The dialog cannot delete cached mail');
  @override
  Future<MailResult<MailUnit>> saveSyncMailbox(MailMailbox mailbox) =>
      throw StateError('Only the explicit runner may save metadata');
  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) =>
      throw StateError('Only the explicit runner may read cursors');
  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) => throw StateError('Only the explicit runner may commit pages');
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

Future<void> _fonts() async {
  await (FontLoader('SyncLatin')
        ..addFont(
          rootBundle.load(
            'packages/quds_office_editor/fonts/LiberationSans-Regular.ttf',
          ),
        )
        ..addFont(
          rootBundle.load(
            'packages/quds_office_editor/fonts/LiberationSans-Bold.ttf',
          ),
        ))
      .load();
  await (FontLoader('SyncArabic')
        ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_screenshotDirectory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Screenshot encoding failed');
      await Directory(_screenshotDirectory).create(recursive: true);
      await File('$_screenshotDirectory/$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> _show(
  WidgetTester tester,
  _Store store, {
  StudioMailSyncRun? run,
  StudioMailBodyDownloadRun? download,
  StudioMailSyncStore? syncStore,
  bool Function()? isCurrent,
  VoidCallback? onClosed,
  StudioLanguage language = StudioLanguage.en,
  Size size = const Size(1200, 900),
  double scale = 1,
}) async {
  if (_screenshotDirectory.isNotEmpty) await _fonts();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff256356)),
          fontFamily: _screenshotDirectory.isEmpty
              ? null
              : language == StudioLanguage.ar
              ? 'SyncArabic'
              : 'SyncLatin',
          fontFamilyFallback: _screenshotDirectory.isEmpty
              ? null
              : const ['SyncLatin', 'SyncArabic'],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => Directionality(
                    textDirection: language == StudioLanguage.ar
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: StudioMailSyncDialog(
                      strings: StudioStrings(language),
                      mailboxStore: store,
                      syncStore: syncStore ?? store,
                      isCurrent: isCurrent ?? () => true,
                      mailbox: run == null ? null : _inbox,
                      run: run,
                      download: download,
                    ),
                  ),
                );
                onClosed?.call();
              },
              child: const Text('Open sync'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open sync'));
  await _pump(tester);
}

void _openFirst(WidgetTester tester) {
  final list = tester.widget<MailMessageList>(find.byType(MailMessageList));
  list.onOpen(list.items.first.id);
}

void main() {
  MailBodyDownloadReport downloaded(
    int total, {
    int? saved,
    int cached = 0,
    MailBodyDownloadStatus status = MailBodyDownloadStatus.completed,
    MailProblem? problem,
  }) => MailBodyDownloadReport(
    status: status,
    progress: MailBodyDownloadProgress(
      mailbox: _inbox.id,
      total: total,
      downloaded: saved ?? total - cached,
      alreadyCached: cached,
      retainedBytes: (saved ?? total - cached) * 100,
    ),
    problem: problem,
  );

  Future<MailSyncRunReport> idleSync({
    required MailCancellationToken cancellation,
    required void Function(MailSyncRunProgress) onProgress,
  }) async => _report(MailSyncRunStatus.completed);

  testWidgets('connected reader downloads only after explicit message action', (
    tester,
  ) async {
    final header = _header(1);
    final store = _Store()..save([header, _header(2)]);
    var downloads = 0;
    await _show(
      tester,
      store,
      run: idleSync,
      download:
          ({
            required headers,
            required cancellation,
            required onProgress,
          }) async {
            downloads++;
            expect(headers, hasLength(1));
            expect(headers.single.remote, header.remote);
            store.bodies[header.id] = _message(header);
            final report = downloaded(1);
            onProgress(report.progress);
            return report;
          },
    );
    expect(downloads, 0);
    expect(store.bodyReads, 0);
    _openFirst(tester);
    await _pump(tester);
    expect(downloads, 0);
    expect(find.text(_strings.mailSyncMissingBody), findsOneWidget);
    await tester.tap(_key('studio-mail-download-message'));
    await _pump(tester);
    expect(downloads, 1);
    expect(find.byType(MailMessageView), findsOneWidget);
    expect(find.text(_strings.mailDownloadProgress(1, 0, 0)), findsOneWidget);
    expect(find.text(_strings.mailDownloadFinished), findsOneWidget);
    expect(store.bodies, hasLength(1));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'offline-download-message-en');
  });

  testWidgets('page download freezes 100 rows and Stop waits for completion', (
    tester,
  ) async {
    final store = _Store()
      ..save(List.generate(101, (index) => _header(index + 1)));
    final completion = Completer<MailBodyDownloadReport>();
    MailCancellationToken? token;
    List<MailHeaderRecord>? captured;
    await _show(
      tester,
      store,
      run: idleSync,
      download:
          ({required headers, required cancellation, required onProgress}) {
            captured = headers;
            token = cancellation;
            onProgress(downloaded(100, saved: 2, cached: 3).progress);
            return completion.future;
          },
    );
    await tester.tap(_key('studio-mail-download-page'));
    await _pump(tester);
    expect(captured, hasLength(100));
    expect(captured!.first.id, _header(1).id);
    expect(captured!.last.id, _header(100).id);
    expect(
      tester.widget<IconButton>(_key('studio-mail-sync-next')).onPressed,
      isNull,
    );
    expect(_key('studio-mail-sync-start'), findsNothing);
    expect(find.text(_strings.mailDownloadProgress(2, 3, 95)), findsOneWidget);
    await tester.tap(_key('studio-mail-sync-stop'));
    await _pump(tester);
    expect(token!.isCancelled, isTrue);
    expect(find.text(_strings.mailSyncStopping), findsOneWidget);
    completion.complete(
      downloaded(
        100,
        saved: 2,
        cached: 3,
        status: MailBodyDownloadStatus.cancelled,
      ),
    );
    await _pump(tester);
    expect(find.text(_strings.mailDownloadCancelled), findsOneWidget);
    expect(
      tester.widget<IconButton>(_key('studio-mail-sync-next')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing cancels body downloads and drains them before owner release',
    (tester) async {
      final store = _Store()..save([_header(1)]);
      final completion = Completer<MailBodyDownloadReport>();
      MailCancellationToken? token;
      var closed = false;
      await _show(
        tester,
        store,
        run: idleSync,
        onClosed: () => closed = true,
        download:
            ({required headers, required cancellation, required onProgress}) {
              token = cancellation;
              return completion.future;
            },
      );
      await tester.tap(_key('studio-mail-download-page'));
      await _pump(tester);
      await tester.tap(_key('studio-mail-sync-close'));
      await _pump(tester);
      expect(token!.isCancelled, isTrue);
      expect(closed, isFalse);
      completion.complete(
        downloaded(1, saved: 0, status: MailBodyDownloadStatus.cancelled),
      );
      await _pump(tester);
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('membership replacement cancels a frozen body download', (
    tester,
  ) async {
    final store = _Store()..save([_header(1)]);
    final completion = Completer<MailBodyDownloadReport>();
    MailCancellationToken? token;
    await _show(
      tester,
      store,
      run: idleSync,
      download:
          ({required headers, required cancellation, required onProgress}) {
            token = cancellation;
            return completion.future;
          },
    );
    await tester.tap(_key('studio-mail-download-page'));
    await _pump(tester);
    store.save([_header(2)], revision: 2);
    await _pump(tester);
    expect(token!.reason, MailCancellationReason.accountChanged);
    completion.complete(
      downloaded(
        1,
        saved: 0,
        status: MailBodyDownloadStatus.failed,
        problem: const MailProblem(MailProblemCode.staleOperation),
      ),
    );
    await _pump(tester);
    expect(find.text(_strings.mailDownloadConflict), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      'download limits and recovery remain usable in ${language.name}',
      (tester) async {
        final strings = StudioStrings(language);
        final store = _Store()..save([_header(1)]);
        await _show(
          tester,
          store,
          run: idleSync,
          language: language,
          size: const Size(480, 800),
          scale: 1.3,
          download:
              ({
                required headers,
                required cancellation,
                required onProgress,
              }) async => downloaded(
                1,
                saved: 0,
                status: MailBodyDownloadStatus.failed,
                problem: const MailProblem(MailProblemCode.quotaExceeded),
              ),
        );
        await tester.ensureVisible(_key('studio-mail-download-page'));
        await tester.tap(_key('studio-mail-download-page'));
        await _pump(tester);
        expect(find.text(strings.mailDownloadQuota), findsOneWidget);
        expect(
          find.text(strings.mailDownloadProgress(0, 0, 1)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, 'offline-download-limit-${language.name}');
      },
    );
  }

  testWidgets('offline catalog reads only saved headers and reports scope', (
    tester,
  ) async {
    final store = _Store()..save([_header(1), _header(2)]);
    await _show(tester, store);
    expect(find.text(_strings.mailSyncOffline), findsOneWidget);
    expect(find.text(_strings.mailSyncScope), findsOneWidget);
    expect(find.text(_strings.mailSyncSaved(_savedAt, 2)), findsOneWidget);
    expect(find.text(_strings.mailSyncPartial), findsOneWidget);
    expect(_key('studio-mail-sync-start'), findsNothing);
    expect(_key('studio-mail-download-page'), findsNothing);
    expect(_key('studio-mail-download-message'), findsNothing);
    expect(store.reads, [(_inbox.id, 100, 0)]);
    expect(store.bodyReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected folder starts only explicitly and shows saved state', (
    tester,
  ) async {
    final store = _Store();
    var calls = 0;
    await _show(
      tester,
      store,
      run: ({required cancellation, required onProgress}) async {
        calls++;
        onProgress(_progress(hasMore: false));
        store.save([_header(1)], hasMore: false);
        return _report(MailSyncRunStatus.completed);
      },
    );
    expect(calls, 0);
    expect(find.text(_strings.mailSyncStart), findsOneWidget);
    await tester.tap(_key('studio-mail-sync-start'));
    await _pump(tester);
    expect(calls, 1);
    expect(find.text(_strings.mailSyncFinished), findsOneWidget);
    expect(find.text(_strings.mailSyncCheckChanges), findsOneWidget);
    expect(find.text(_strings.mailSyncComplete), findsOneWidget);
    expect(store.bodyReads, 0);
    await _capture(tester, 'desktop-en');
  });

  testWidgets('partial checkpoint offers continue and bounded pause', (
    tester,
  ) async {
    final store = _Store()..save([_header(1)]);
    await _show(
      tester,
      store,
      run: ({required cancellation, required onProgress}) async =>
          _report(MailSyncRunStatus.paused),
    );
    expect(find.text(_strings.mailSyncContinue), findsOneWidget);
    await tester.tap(_key('studio-mail-sync-start'));
    await _pump(tester);
    expect(find.text(_strings.mailSyncPaused), findsOneWidget);
    expect(find.text(_strings.mailSyncContinue), findsOneWidget);
  });

  testWidgets('stop cancels once and waits for running work before resuming', (
    tester,
  ) async {
    final store = _Store()..save([_header(1)]);
    final completion = Completer<MailSyncRunReport>();
    MailCancellationToken? token;
    var calls = 0;
    await _show(
      tester,
      store,
      run: ({required cancellation, required onProgress}) {
        token = cancellation;
        calls++;
        onProgress(_progress());
        return completion.future;
      },
    );
    await tester.tap(_key('studio-mail-sync-start'));
    await _pump(tester);
    expect(find.text(_strings.mailSyncProgress(1, 100)), findsOneWidget);
    await tester.tap(_key('studio-mail-sync-stop'));
    await _pump(tester);
    expect(token!.isCancelled, isTrue);
    expect(find.text(_strings.mailSyncStopping), findsOneWidget);
    expect(_key('studio-mail-sync-start'), findsNothing);
    expect(calls, 1);
    completion.complete(_report(MailSyncRunStatus.cancelled));
    await _pump(tester);
    expect(find.text(_strings.mailSyncCancelled), findsOneWidget);
    expect(find.text(_strings.mailSyncContinue), findsOneWidget);
  });

  testWidgets('close cancels and drains run before releasing the caller', (
    tester,
  ) async {
    final store = _Store()..save([_header(1)]);
    final completion = Completer<MailSyncRunReport>();
    MailCancellationToken? token;
    var closed = false;
    await _show(
      tester,
      store,
      onClosed: () => closed = true,
      run: ({required cancellation, required onProgress}) {
        token = cancellation;
        return completion.future;
      },
    );
    await tester.tap(_key('studio-mail-sync-start'));
    await _pump(tester);
    await tester.tap(_key('studio-mail-sync-close'));
    await _pump(tester);
    expect(token!.isCancelled, isTrue);
    expect(closed, isFalse);
    expect(find.byType(StudioMailSyncDialog), findsOneWidget);
    completion.complete(_report(MailSyncRunStatus.cancelled));
    await _pump(tester);
    expect(closed, isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(StudioMailSyncDialog), findsNothing);
    expect(store.cancellations, 2);
  });

  testWidgets('close drains initial read and repository stream cancellation', (
    tester,
  ) async {
    final store = _Store()
      ..save([_header(1)])
      ..readGate = Completer<void>()
      ..cancelGate = Completer<void>();
    var closed = false;
    await _show(tester, store, onClosed: () => closed = true);
    expect(store.reads, hasLength(1));
    await tester.tap(_key('studio-mail-sync-close'));
    await _pump(tester);
    expect(closed, isFalse);
    store.cancelGate!.complete();
    await _pump(tester);
    expect(closed, isFalse);
    store.readGate!.complete();
    await _pump(tester);
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing body explains headers-only scope without downloading', (
    tester,
  ) async {
    final store = _Store()..save([_header(1)]);
    await _show(tester, store);
    _openFirst(tester);
    await _pump(tester);
    expect(store.bodyReads, 1);
    expect(find.text(_strings.mailSyncMissingBody), findsOneWidget);
    expect(find.byType(MailMessageView), findsNothing);
  });

  testWidgets('saved message body uses reader and survives metadata updates', (
    tester,
  ) async {
    final header = _header(1);
    final store = _Store()
      ..save([header])
      ..bodies[header.id] = _message(header);
    await _show(tester, store);
    _openFirst(tester);
    await _pump(tester);
    final reader = tester
        .widget<MailMessageView>(find.byType(MailMessageView))
        .controller;
    store.save([header, _header(2)], revision: 2);
    await _pump(tester);
    expect(
      tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
      same(reader),
    );
    expect(store.bodyReads, 1);
    store.save([_header(2)], revision: 3);
    await _pump(tester);
    expect(find.byType(MailMessageView), findsNothing);
  });

  testWidgets('close drains a body read and suppresses its late reader', (
    tester,
  ) async {
    final header = _header(1);
    final store = _Store()
      ..save([header])
      ..bodies[header.id] = _message(header)
      ..bodyGate = Completer<void>();
    var closed = false;
    await _show(tester, store, onClosed: () => closed = true);
    _openFirst(tester);
    await _pump(tester);
    await tester.tap(_key('studio-mail-sync-close'));
    await _pump(tester);
    expect(closed, isFalse);
    store.bodyGate!.complete();
    await _pump(tester);
    expect(closed, isTrue);
    expect(find.byType(MailMessageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forced disposal cancels work and never calls stale host again', (
    tester,
  ) async {
    final store = _Store()..save([_header(1)]);
    final completion = Completer<MailSyncRunReport>();
    MailCancellationToken? token;
    void Function(MailSyncRunProgress)? progress;
    var disposed = false;
    await _show(
      tester,
      store,
      isCurrent: () {
        if (disposed) throw StateError('Host callback after disposal');
        return true;
      },
      run: ({required cancellation, required onProgress}) {
        token = cancellation;
        progress = onProgress;
        return completion.future;
      },
    );
    await tester.tap(_key('studio-mail-sync-start'));
    await _pump(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    disposed = true;
    expect(token!.reason, MailCancellationReason.disposed);
    progress!(_progress(pages: 2));
    completion.complete(_report(MailSyncRunStatus.cancelled));
    store.publish();
    await _pump(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved headers page in bounded windows without accumulating', (
    tester,
  ) async {
    final store = _Store()
      ..save(List.generate(205, (index) => _header(index + 1)));
    await _show(tester, store);
    expect(
      tester.widget<MailMessageList>(find.byType(MailMessageList)).items,
      hasLength(100),
    );
    expect(find.text(_strings.mailSyncPage(1, 100, 205)), findsOneWidget);
    await tester.tap(_key('studio-mail-sync-next'));
    await _pump(tester);
    final second = tester.widget<MailMessageList>(find.byType(MailMessageList));
    expect(second.items, hasLength(100));
    expect(second.items.first.id, 'saved-101');
    await tester.tap(_key('studio-mail-sync-next'));
    await _pump(tester);
    expect(
      tester.widget<MailMessageList>(find.byType(MailMessageList)).items,
      hasLength(5),
    );
    expect(find.text(_strings.mailSyncPage(201, 205, 205)), findsOneWidget);
    expect(store.reads, [
      (_inbox.id, 100, 0),
      (_inbox.id, 100, 100),
      (_inbox.id, 100, 200),
    ]);
    expect(store.bodyReads, 0);
  });

  testWidgets('shrinking mailbox returns an out-of-range page to saved start', (
    tester,
  ) async {
    final store = _Store()
      ..save(List.generate(101, (index) => _header(index + 1)));
    await _show(tester, store);
    await tester.tap(_key('studio-mail-sync-next'));
    await _pump(tester);
    store.save([_header(1)], revision: 2);
    await _pump(tester);
    expect(store.reads.last, (_inbox.id, 100, 0));
    expect(find.text(_strings.mailSyncPage(1, 1, 1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repository failure retains view and successful update recovers',
    (tester) async {
      final store = _Store()..save([_header(1)]);
      await _show(tester, store);
      store.failViews();
      await _pump(tester);
      expect(_key('studio-mail-sync-error'), findsOneWidget);
      expect(
        tester.widget<MailMessageList>(find.byType(MailMessageList)).items,
        hasLength(1),
      );
      store.save([_header(1), _header(2)], revision: 2);
      await _pump(tester);
      expect(_key('studio-mail-sync-error'), findsNothing);
      expect(
        tester.widget<MailMessageList>(find.byType(MailMessageList)).items,
        hasLength(2),
      );
    },
  );

  testWidgets('cross-account stores are rejected before subscribing', (
    tester,
  ) async {
    final other = _Store(
      account: MailAccountId('other-account', profile: _profile),
    );
    await _show(tester, _Store(), syncStore: other);
    expect(other.watchCalls, 0);
    expect(_key('studio-mail-sync-error'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('mismatched cached body is not displayed', (tester) async {
    final header = _header(1);
    final store = _Store()
      ..save([header])
      ..bodies[header.id] = _message(_header(2));
    await _show(tester, store);
    _openFirst(tester);
    await _pump(tester);
    expect(find.byType(MailMessageView), findsNothing);
    expect(_key('studio-mail-sync-error'), findsOneWidget);
    expect(find.textContaining('private provider content'), findsNothing);
  });

  for (final code in [
    MailProblemCode.authenticationRequired,
    MailProblemCode.quotaExceeded,
    MailProblemCode.conflict,
    MailProblemCode.unsupported,
  ]) {
    testWidgets('typed ${code.name} failure preserves resumable saved view', (
      tester,
    ) async {
      final store = _Store()..save([_header(1)]);
      await _show(
        tester,
        store,
        run: ({required cancellation, required onProgress}) async =>
            _report(MailSyncRunStatus.failed, problem: MailProblem(code)),
      );
      await tester.tap(_key('studio-mail-sync-start'));
      await _pump(tester);
      expect(_key('studio-mail-sync-result'), findsOneWidget);
      expect(find.text(_strings.mailSyncContinue), findsOneWidget);
      expect(find.text(_strings.mailSyncSaved(_savedAt, 1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in StudioLanguage.values) {
    testWidgets('compact ${language.name} layout keeps controls and reader', (
      tester,
    ) async {
      final store = _Store()..save([_header(1)], hasMore: false);
      await _show(
        tester,
        store,
        language: language,
        size: const Size(390, 844),
        scale: 1.2,
      );
      expect(tester.takeException(), isNull);
      expect(_key('studio-mail-sync-close'), findsOneWidget);
      await _capture(tester, 'compact-${language.name}');
      _openFirst(tester);
      await _pump(tester);
      expect(_key('studio-mail-sync-back'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(_key('studio-mail-sync-back'));
      await _pump(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
