import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:quds_office_studio/studio_mail_archive_native.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

Uint8List _eml(String subject) => Uint8List.fromList(
  utf8.encode(
    [
      'From: Reader <reader@example.test>',
      'To: recipient@example.test',
      'Subject: $subject',
      'Date: Thu, 19 Nov 2026 12:00:00 +0000',
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=utf-8',
      '',
      'Original body for $subject.',
      '',
    ].join('\r\n'),
  ),
);

MailArchiveEntry _entry(MailMessage message) => MailArchiveEntry(
  id: message.raw.sha256,
  envelope: message.envelope,
  archivedAt: DateTime.utc(2026, 11, 19),
  byteLength: message.raw.length,
  attachmentCount: message.attachments.length,
  indexTruncated: false,
  attachmentTextIndexed: 0,
  attachmentTextSkipped: 0,
);

final class _Store extends Fake implements StudioMailArchiveStore {
  @override
  final profile = MailProfileId('studio-archive', hostId: 'widget-tests');
  final exportRequests = <MailArchiveSearchRequest>[];
  Future<MailResult<MailArchiveExportPlan>> Function(MailArchiveSearchRequest)?
  onPlan;
  final entries = <MailArchiveSearchHit>[];
  final originals = <String, MailBytes>{};
  final searches = <MailArchiveSearchRequest>[];
  final saved = <MailArchiveSavedSearch>[];
  final imported = <MailMessage>[];
  final importedOrigins = <MailArchiveOrigin>[];
  final verifyCursors = <String?>[];
  final rebuildCursors = <String?>[];
  MailCodec? rebuildCodec;
  bool? rebuildAttachments;
  final origin = const MailArchiveOrigin(source: 'Account A', folder: '/Inbox');
  Future<MailResult<MailArchiveSearchPage>> Function(MailArchiveSearchRequest)?
  onSearch;
  Future<MailResult<MailBytes?>> Function(String)? onLoad;
  Future<MailResult<MailArchiveMaintenancePage>> Function(
    String?,
    MailCancellationToken?,
  )?
  onVerify;
  Future<MailResult<MailArchiveImportResult>> Function(MailMessage)? onArchive;
  MailProblemCode? saveSearchFailure;
  MailArchiveDiagnostics? logging;
  int closes = 0;

  MailArchiveSearchHit add(String subject) {
    final message = const QudsMimeCodec().parse(_eml(subject)).message!;
    final hit = MailArchiveSearchHit(
      entry: _entry(message),
      preview: message.body.plainText!,
    );
    entries.add(hit);
    originals[hit.entry.id] = message.raw;
    return hit;
  }

  @override
  set diagnostics(MailArchiveDiagnostics? value) => logging = value;
  @override
  Future<MailResult<MailArchiveExportPlan>> planExport(
    MailArchiveSearchRequest request, {
    MailArchiveExportLimits exportLimits = const MailArchiveExportLimits(),
    MailCancellationToken? cancellation,
  }) async {
    exportRequests.add(request);
    if (onPlan != null) return onPlan!(request);
    return MailSuccess(
      MailArchiveExportPlan(
        profile: profile,
        createdAt: DateTime.utc(2026, 11, 19),
        items: [
          for (final hit in entries)
            MailArchiveExportItem(
              id: hit.entry.id,
              byteLength: hit.entry.byteLength,
              origins: [origin],
            ),
        ],
      ),
    );
  }

  @override
  Future<MailResult<MailArchiveSearchPage>> search(
    MailArchiveSearchRequest request,
  ) async {
    searches.add(request);
    if (onSearch != null) return onSearch!(request);
    return MailSuccess(
      MailArchiveSearchPage(
        hits: entries.skip(request.offset).take(request.limit).toList(),
        total: entries.length,
        offset: request.offset,
      ),
    );
  }

  @override
  Future<MailResult<MailBytes?>> loadOriginal(String id) async =>
      onLoad == null ? MailSuccess(originals[id]) : onLoad!(id);
  @override
  Future<MailResult<List<MailArchiveOrigin>>> listOrigins(String id) async =>
      MailSuccess([origin]);
  @override
  Future<MailResult<MailArchiveStats>> statistics() async => MailSuccess(
    MailArchiveStats(
      messages: entries.length,
      rawBytes: originals.values.fold(0, (sum, bytes) => sum + bytes.length),
      indexedMessages: entries.length,
      origins: entries.length,
    ),
  );
  @override
  Future<MailResult<List<MailArchiveSavedSearch>>> listSearches() async =>
      MailSuccess(List.of(saved));
  @override
  Future<MailResult<MailUnit>> saveSearch(MailArchiveSavedSearch search) async {
    if (saveSearchFailure case final code?) {
      return MailFailure(MailProblem(code));
    }
    saved.removeWhere((item) => item.name == search.name);
    saved.add(search);
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> removeSearch(String name) async {
    saved.removeWhere((item) => item.name == name);
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailArchiveImportResult>> archiveMessage(
    MailMessage message, {
    required MailArchiveOrigin origin,
    bool indexAttachmentText = false,
    MailCancellationToken? cancellation,
  }) async {
    imported.add(message);
    importedOrigins.add(origin);
    if (onArchive != null) return onArchive!(message);
    final duplicate = originals.containsKey(message.raw.sha256);
    if (!duplicate) {
      entries.add(
        MailArchiveSearchHit(
          entry: _entry(message),
          preview: message.body.plainText ?? '',
        ),
      );
    }
    originals[message.raw.sha256] = message.raw;
    return MailSuccess(
      MailArchiveImportResult(
        entry: _entry(message),
        duplicate: duplicate,
        originAdded: !duplicate,
      ),
    );
  }

  @override
  Future<MailResult<MailArchiveMaintenancePage>> verifyIntegrity({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
  }) async {
    verifyCursors.add(afterId);
    return onVerify != null
        ? onVerify!(afterId, cancellation)
        : MailSuccess(
            MailArchiveMaintenancePage(
              processed: entries.length,
              nextAfterId: null,
              hasMore: false,
            ),
          );
  }

  @override
  Future<MailResult<MailArchiveMaintenancePage>> rebuildIndex({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
    MailCodec? codec,
    bool? indexAttachmentText,
  }) async {
    rebuildCursors.add(afterId);
    rebuildCodec = codec;
    rebuildAttachments = indexAttachmentText;
    return MailSuccess(
      MailArchiveMaintenancePage(
        processed: entries.length,
        nextAfterId: null,
        hasMore: false,
      ),
    );
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

final class _Files extends Fake implements StudioMailArchiveFiles {
  String? pickedDirectory = '/selected';
  final exportedPlans = <MailArchiveExportPlan>[];
  final directoryEntries = <MailArchiveDirectoryEntry>[];
  bool? scanRecursive;
  MailCancellationToken? exportCancellation;
  MailProfileId? resumedProfile;
  int resumeCalls = 0;
  Future<MailArchiveExportReport> Function(
    MailArchiveExportPlan,
    MailCancellationToken,
    MailArchiveExportProgressSink?,
  )?
  onBulkExport;
  List<StudioMailArchiveInput>? picked;
  final records = <String, List<MailResult<Uint8List>>>{};
  MailBytes? exported;
  String? exportName;
  int reads = 0;
  int? readLimit;
  MailMboxDialect? dialectRead;
  @override
  Future<List<StudioMailArchiveInput>?> pickFiles() async => picked;
  @override
  Future<String?> pickDirectory() async => pickedDirectory;
  @override
  Stream<MailArchiveDirectoryEntry> enumerateDirectory(
    String path, {
    required MailCancellationToken cancellation,
    MailArchiveDirectoryLimits limits = const MailArchiveDirectoryLimits(),
    bool recursive = true,
  }) {
    scanRecursive = recursive;
    return Stream.fromIterable(directoryEntries);
  }

  @override
  Future<MailArchiveExportReport> exportPlan(
    MailArchiveExportPlan plan,
    String parentPath, {
    required MailArchiveOriginalLoader loadOriginal,
    required MailCancellationToken cancellation,
    MailArchiveExportProgressSink? onProgress,
  }) async {
    exportedPlans.add(plan);
    exportCancellation = cancellation;
    if (onBulkExport != null) {
      return onBulkExport!(plan, cancellation, onProgress);
    }
    return _exportReport(
      planned: plan.items.length,
      written: plan.items.length,
    );
  }

  @override
  Future<MailArchiveExportReport> resumeExport(
    String directoryPath, {
    required MailProfileId profile,
    required MailArchiveOriginalLoader loadOriginal,
    required MailCancellationToken cancellation,
    MailArchiveExportProgressSink? onProgress,
  }) async {
    resumeCalls++;
    resumedProfile = profile;
    return _exportReport(planned: 1, existing: 1);
  }

  @override
  Stream<MailResult<Uint8List>> readMessages(
    StudioMailArchiveInput input, {
    required int maxMessageBytes,
    required MailCancellationToken cancellation,
    MailMboxDialect dialect = MailMboxDialect.mboxrd,
  }) async* {
    reads++;
    readLimit = maxMessageBytes;
    dialectRead = dialect;
    for (final record
        in records[input.name] ?? const <MailResult<Uint8List>>[]) {
      if (cancellation.isCancelled) break;
      yield record;
    }
  }

  @override
  Future<MailResult<bool>> exportOriginal(
    String suggestedName,
    MailBytes bytes, {
    required MailCancellationToken cancellation,
  }) async {
    exported = bytes;
    exportName = suggestedName;
    return const MailSuccess(true);
  }
}

MailArchiveExportReport _exportReport({
  MailArchiveExportStatus status = MailArchiveExportStatus.completed,
  int planned = 1,
  int written = 0,
  int existing = 0,
  int failed = 0,
}) => MailArchiveExportReport(
  status: status,
  planned: planned,
  written: written,
  existing: existing,
  failed: failed,
  bytes: 10 * (written + existing),
  elapsedMicroseconds: 100,
  observerErrors: 0,
  failures: const [],
  droppedFailures: 0,
  directoryPath: '/selected/crispoffice-mail-export-job',
);

Finder _key(String key) => find.byKey(ValueKey(key));
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _pump(tester);
  await tester.ensureVisible(_key(key));
  await tester.pump();
  await tester.tap(_key(key));
  await _pump(tester);
}

Future<void> _show(
  WidgetTester tester,
  _Store? store, {
  StudioStrings strings = _strings,
  _Files? files,
  StudioMailArchiveOpener? openArchive,
  Size size = const Size(1200, 1000),
  MailArchiveLogSink? diagnosticSink,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailArchiveDialog(
        strings: strings,
        store: store,
        files: files ?? _Files(),
        openArchive: openArchive,
        diagnosticSink: diagnosticSink,
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _filters(WidgetTester tester) async =>
    _tap(tester, 'archive-filter-panel');

void main() {
  testWidgets(
    'bulk export freezes all pages of the applied search and shows its destination',
    (tester) async {
      final store = _Store();
      for (var i = 0; i < 51; i++) {
        store.add('Invoice $i');
      }
      final files = _Files();
      await _show(tester, store, files: files);
      await tester.enterText(_key('archive-query'), 'subject:Invoice');
      await _tap(tester, 'archive-search');
      await _tap(tester, 'archive-next');
      expect(store.searches.last.offset, 50);
      await _tap(tester, 'archive-bulk-export');
      expect(
        find.textContaining('Export 51 original messages'),
        findsOneWidget,
      );
      await _tap(tester, 'archive-choose-export-directory');
      expect(store.exportRequests.single.query, 'subject:Invoice');
      expect(files.exportedPlans.single.items, hasLength(51));
      expect(
        find.text(
          _strings.archiveBulkSummary(
            MailArchiveExportStatus.completed,
            51,
            0,
            0,
            51,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('/selected/crispoffice-mail-export-job'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled export picker does not start file publication', (
    tester,
  ) async {
    final store = _Store()..add('One');
    final files = _Files()..pickedDirectory = null;
    await _show(tester, store, files: files);
    await _tap(tester, 'archive-bulk-export');
    await _tap(tester, 'archive-choose-export-directory');
    expect(files.exportedPlans, isEmpty);
    expect(_key('archive-error'), findsNothing);
  });

  testWidgets(
    'failed export plan reports its bound without starting a picker or export',
    (tester) async {
      final store = _Store()
        ..onPlan = (_) async =>
            const MailFailure(MailProblem(MailProblemCode.quotaExceeded));
      final files = _Files();
      await _show(tester, store, files: files);
      await _tap(tester, 'archive-bulk-export');
      expect(
        find.text(_strings.archiveProblem(MailProblemCode.quotaExceeded)),
        findsOneWidget,
      );
      expect(_key('archive-choose-export-directory'), findsNothing);
      expect(files.exportedPlans, isEmpty);
    },
  );

  testWidgets(
    'resume uses the saved export and archive profile without replanning current filters',
    (tester) async {
      final store = _Store()..add('One');
      final files = _Files();
      await _show(tester, store, files: files);
      await tester.enterText(_key('archive-query'), 'unsent query');
      await _tap(tester, 'archive-resume-export');
      expect(find.text(_strings.archiveResumeHelp), findsOneWidget);
      await _tap(tester, 'archive-choose-export-directory');
      expect(store.exportRequests, isEmpty);
      expect(files.resumeCalls, 1);
      expect(files.resumedProfile, store.profile);
      expect(
        find.text(
          _strings.archiveBulkSummary(
            MailArchiveExportStatus.completed,
            0,
            1,
            0,
            1,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'export cancellation waits for the final confirmed publication counts',
    (tester) async {
      final store = _Store()..add('One');
      final done = Completer<void>();
      final files = _Files()
        ..onBulkExport = (plan, cancellation, progress) async {
          progress?.call(
            const MailArchiveExportProgress(
              phase: MailArchiveExportPhase.message,
              planned: 2,
              written: 1,
              existing: 0,
              failed: 0,
              bytes: 10,
              elapsedMicroseconds: 1,
              observerErrors: 0,
            ),
          );
          await done.future;
          expect(cancellation.isCancelled, isTrue);
          return _exportReport(
            status: MailArchiveExportStatus.cancelled,
            planned: 2,
            written: 1,
          );
        };
      await _show(tester, store, files: files);
      await _tap(tester, 'archive-bulk-export');
      await _tap(tester, 'archive-choose-export-directory');
      await _tap(tester, 'archive-cancel');
      expect(files.exportCancellation!.isCancelled, isTrue);
      expect(
        tester.widget<OutlinedButton>(_key('archive-bulk-export')).onPressed,
        isNull,
      );
      done.complete();
      await _pump(tester);
      expect(
        find.text(
          _strings.archiveBulkSummary(
            MailArchiveExportStatus.cancelled,
            1,
            0,
            0,
            2,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('/selected/crispoffice-mail-export-job'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'disposed export planning cannot open a dialog or publish files',
    (tester) async {
      final plan = Completer<MailResult<MailArchiveExportPlan>>();
      final store = _Store()..onPlan = (_) => plan.future;
      final files = _Files();
      await _show(tester, store, files: files);
      await _tap(tester, 'archive-bulk-export');
      await tester.pumpWidget(const SizedBox.shrink());
      plan.complete(
        MailSuccess(
          MailArchiveExportPlan(
            profile: store.profile,
            createdAt: DateTime.utc(2026),
            items: const [],
          ),
        ),
      );
      await _pump(tester);
      expect(files.exportedPlans, isEmpty);
      expect(store.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'directory import exposes recursive choice and retains relative provenance',
    (tester) async {
      final store = _Store();
      final files = _Files();
      final raw = _eml('Nested original');
      const counts = MailArchiveDirectoryProgress(
        entriesInspected: 3,
        directoriesVisited: 2,
        filesAccepted: 1,
        acceptedBytes: 200,
        skippedEntries: 0,
        errorEntries: 0,
        limitedEntries: 0,
      );
      files.directoryEntries.addAll([
        MailArchiveDirectoryEntry(
          outcome: MailArchiveDirectoryOutcome.file,
          progress: counts,
          absolutePath: '/selected/Letters/item.eml',
          relativePath: 'Letters/item.eml',
          relativeFolder: 'Letters',
          kind: MailArchiveDirectoryFileKind.eml,
          byteLength: raw.length,
        ),
        const MailArchiveDirectoryEntry(
          outcome: MailArchiveDirectoryOutcome.completed,
          progress: counts,
          terminal: true,
        ),
      ]);
      files.records['item.eml'] = [MailSuccess(raw)];
      await _show(tester, store, files: files);
      await _tap(tester, 'archive-import-directory');
      expect(find.text(_strings.archiveDirectoryHelp), findsOneWidget);
      await tester.enterText(_key('archive-import-folder'), '/Imported');
      await _tap(tester, 'archive-choose-files');
      // Cancelling the synchronous fake scan awaits Dart's shared root-zone
      // completed future. Let its microtask run before settling the progress UI.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(files.scanRecursive, isTrue);
      expect(store.importedOrigins.single.folder, '/Imported/Letters');
      expect(store.imported.single.raw.bytes, raw);
      expect(
        find.textContaining('1 saved · 0 already archived'),
        findsOneWidget,
        reason: tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data)
            .join('\n'),
      );
    },
  );

  testWidgets('persistent search paginates with the complete query request', (
    tester,
  ) async {
    final store = _Store();
    for (var i = 0; i < 51; i++) {
      store.add('Invoice $i');
    }
    await _show(tester, store);
    expect(
      find.text(
        _strings.archiveStats(
          51,
          store.originals.values.fold(0, (sum, value) => sum + value.length),
          51,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('1–50 of 51'), findsOneWidget);
    await _tap(tester, 'archive-next');
    expect(store.searches.last.offset, 50);
    expect(find.text('51–51 of 51'), findsOneWidget);
    expect(find.text('Invoice 50'), findsOneWidget);
    await _tap(tester, 'archive-previous');
    expect(store.searches.last.offset, 0);
  });

  testWidgets(
    'filters reject invalid calendar dates and preserve inclusive UTC end days',
    (tester) async {
      final store = _Store();
      await _show(tester, store);
      await _filters(tester);
      await tester.ensureVisible(_key('archive-sent-since'));
      await tester.enterText(_key('archive-sent-since'), '2026-02-30');
      await _tap(tester, 'archive-search');
      expect(store.searches, hasLength(1));
      expect(find.text(_strings.archiveQueryInvalid), findsOneWidget);
      await tester.ensureVisible(_key('archive-sent-since'));
      await tester.enterText(_key('archive-sent-since'), '2026-02-01');
      await tester.enterText(_key('archive-sent-through'), '2026-02-28');
      await tester.ensureVisible(_key('archive-source'));
      await tester.enterText(_key('archive-source'), 'Account A');
      await tester.enterText(_key('archive-folder'), '/Inbox');
      await tester.ensureVisible(_key('archive-min-size'));
      await tester.enterText(_key('archive-min-size'), '1537');
      await tester.enterText(_key('archive-max-size'), '4096');
      await _tap(tester, 'archive-search');
      expect(store.searches.last.sentSince, DateTime.utc(2026, 2, 1));
      expect(store.searches.last.sentBefore, DateTime.utc(2026, 3, 1));
      expect(store.searches.last.minBytes, 1537);
      expect(store.searches.last.maxBytes, 4096);
      expect(store.searches.last.source, 'Account A');
      expect(store.searches.last.folder, '/Inbox');
    },
  );

  testWidgets(
    'malformed query is rejected before backend and exposes fixed feedback',
    (tester) async {
      final store = _Store();
      await _show(tester, store);
      await tester.enterText(_key('archive-query'), 'subject:"unfinished');
      await _tap(tester, 'archive-search');
      expect(store.searches, hasLength(1));
      expect(find.text(_strings.archiveQueryInvalid), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late search completion cannot replace newer results', (
    tester,
  ) async {
    final store = _Store();
    final old = Completer<MailResult<MailArchiveSearchPage>>();
    final newer = store.add('New result');
    store.onSearch = (request) async => request.query == 'old'
        ? old.future
        : MailSuccess(
            MailArchiveSearchPage(hits: [newer], total: 1, offset: 0),
          );
    await _show(tester, store);
    await tester.enterText(_key('archive-query'), 'old');
    await _tap(tester, 'archive-search');
    await tester.enterText(_key('archive-query'), 'new');
    await _tap(tester, 'archive-search');
    old.complete(
      MailSuccess(MailArchiveSearchPage(hits: [], total: 0, offset: 0)),
    );
    await _pump(tester);
    expect(find.text('New result'), findsOneWidget);
    expect(find.text('1–1 of 1'), findsOneWidget);
  });

  testWidgets('a store acquired after dialog disposal is closed exactly once', (
    tester,
  ) async {
    final opened = Completer<MailResult<StudioMailArchiveStore>>();
    final store = _Store();
    await _show(tester, null, openArchive: () => opened.future);
    await tester.pumpWidget(const SizedBox.shrink());
    opened.complete(MailSuccess(store));
    await _pump(tester);
    expect(store.closes, 1);
    expect(store.searches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during original loading ignores late completion', (
    tester,
  ) async {
    final store = _Store();
    final hit = store.add('Slow message');
    final loaded = Completer<MailResult<MailBytes?>>();
    store.onLoad = (_) => loaded.future;
    await _show(tester, store);
    await _tap(tester, 'archive-hit-${hit.entry.id}');
    await tester.pumpWidget(const SizedBox.shrink());
    loaded.complete(MailSuccess(store.originals[hit.entry.id]));
    await _pump(tester);
    expect(store.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview shows provenance and exports exact original bytes with a safe name',
    (tester) async {
      final store = _Store();
      final hit = store.add('../../unsafe subject');
      final files = _Files();
      await _show(tester, store, files: files);
      await _tap(tester, 'archive-hit-${hit.entry.id}');
      expect(find.text('Account A · /Inbox'), findsOneWidget);
      await _tap(tester, 'archive-export');
      expect(files.exportName, '${hit.entry.id}.eml');
      expect(
        files.exported!.bytes,
        orderedEquals(store.originals[hit.entry.id]!.bytes),
      );
      expect(find.text(_strings.archiveExported), findsOneWidget);
    },
  );

  testWidgets('saved search preserves filters and can be loaded and deleted', (
    tester,
  ) async {
    final store = _Store();
    await _show(tester, store);
    await tester.enterText(_key('archive-query'), 'subject:invoice -from:spam');
    await _filters(tester);
    await tester.ensureVisible(_key('archive-source'));
    await tester.enterText(_key('archive-source'), 'Invoices');
    await tester.ensureVisible(_key('archive-min-size'));
    await tester.enterText(_key('archive-min-size'), '1537');
    await _tap(tester, 'archive-save-search');
    await tester.enterText(_key('archive-search-name'), 'Accounting');
    await _tap(tester, 'archive-confirm-save-search');
    expect(store.saved.single.request.query, 'subject:invoice -from:spam');
    expect(store.saved.single.request.source, 'Invoices');
    expect(store.saved.single.request.minBytes, 1537);
    await tester.ensureVisible(_key('archive-query'));
    await tester.enterText(_key('archive-query'), 'changed');
    await _tap(tester, 'archive-saved-searches');
    await tester.tap(find.text('Accounting').last);
    await _pump(tester);
    expect(
      tester.widget<TextField>(_key('archive-query')).controller!.text,
      'subject:invoice -from:spam',
    );
    expect(store.searches.last.minBytes, 1537);
    await _tap(tester, 'archive-delete-search');
    expect(store.saved, isEmpty);
    expect(find.text(_strings.archiveSearchRemoved), findsOneWidget);
  });

  testWidgets(
    'partial import reports duplicates and typed per-file failures while retaining successes',
    (tester) async {
      final store = _Store();
      final bytes = _eml('Imported invoice');
      final files = _Files()
        ..picked = const [
          StudioMailArchiveInput(name: 'batch.mbox', path: '/not-read-by-test'),
        ]
        ..records['batch.mbox'] = [
          MailSuccess(bytes),
          MailSuccess(bytes),
          const MailFailure(MailProblem(MailProblemCode.permissionDenied)),
        ];
      await _show(tester, store, files: files);
      await _tap(tester, 'archive-import');
      await _tap(tester, 'archive-choose-files');
      await _pump(tester);
      expect(store.imported, hasLength(2));
      expect(store.entries, hasLength(1));
      expect(files.readLimit, const MailArchiveLimits().maxMessageBytes);
      expect(store.importedOrigins.first.sourceMessageId, 'batch.mbox:1');
      expect(store.importedOrigins.last.sourceMessageId, 'batch.mbox:2');
      expect(
        find.textContaining('1 imported · 1 duplicates · 1 failed'),
        findsOneWidget,
      );
      expect(
        find.text(_strings.archiveProblem(MailProblemCode.permissionDenied)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'oversized injected records are rejected before MIME parsing or writes',
    (tester) async {
      final store = _Store();
      final files = _Files()
        ..picked = const [
          StudioMailArchiveInput(name: 'huge.eml', path: '/unused'),
        ]
        ..records['huge.eml'] = [
          MailSuccess(Uint8List(const MailArchiveLimits().maxMessageBytes + 1)),
        ];
      await _show(tester, store, files: files);
      await _tap(tester, 'archive-import');
      await _tap(tester, 'archive-choose-files');
      await _pump(tester);
      expect(store.imported, isEmpty);
      expect(
        find.text(_strings.archiveProblem(MailProblemCode.quotaExceeded)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'maintenance advances its cursor and reports all observed issues',
    (tester) async {
      final store = _Store();
      store.onVerify = (cursor, _) async => MailSuccess(
        cursor == null
            ? MailArchiveMaintenancePage(
                processed: 25,
                nextAfterId: 'a',
                hasMore: true,
                issues: const [
                  MailArchiveIntegrityIssue(
                    id: 'item-a',
                    code: MailArchiveIntegrityCode.missingIndex,
                  ),
                ],
              )
            : MailArchiveMaintenancePage(
                processed: 2,
                nextAfterId: null,
                hasMore: false,
              ),
      );
      await _show(tester, store);
      await _tap(tester, 'archive-verify');
      await _pump(tester);
      expect(store.verifyCursors, [null, 'a']);
      expect(
        find.text(_strings.archiveMaintenanceSummary(27, 1, false)),
        findsOneWidget,
      );
    },
  );

  testWidgets('maintenance cancellation stops before the next page', (
    tester,
  ) async {
    final store = _Store();
    final page = Completer<MailResult<MailArchiveMaintenancePage>>();
    MailCancellationToken? token;
    store.onVerify = (_, cancellation) {
      token = cancellation;
      return page.future;
    };
    await _show(tester, store);
    await _tap(tester, 'archive-verify');
    await _tap(tester, 'archive-cancel');
    expect(token!.isCancelled, isTrue);
    page.complete(
      MailSuccess(
        MailArchiveMaintenancePage(
          processed: 5,
          nextAfterId: 'next',
          hasMore: true,
        ),
      ),
    );
    await _pump(tester);
    expect(store.verifyCursors, [null]);
    expect(
      find.text(_strings.archiveMaintenanceSummary(5, 0, true)),
      findsOneWidget,
    );
  });

  testWidgets('maintenance detects a nonadvancing cursor instead of looping', (
    tester,
  ) async {
    final store = _Store();
    store.onVerify = (_, _) async => MailSuccess(
      MailArchiveMaintenancePage(
        processed: 1,
        nextAfterId: 'same',
        hasMore: true,
      ),
    );
    await _show(tester, store);
    await _tap(tester, 'archive-verify');
    await _pump(tester);
    expect(store.verifyCursors, [null, 'same']);
    expect(
      find.text(_strings.archiveProblem(MailProblemCode.storageFailure)),
      findsOneWidget,
    );
  });

  testWidgets(
    'verbose diagnostics are opt-in and a failing sink cannot break the dialog',
    (tester) async {
      final store = _Store();
      await _show(
        tester,
        store,
        diagnosticSink: (_) => throw StateError('private diagnostic sink'),
      );
      expect(store.logging, isNull);
      final expander = find.widgetWithText(
        ExpansionTile,
        _strings.archiveDiagnostics,
      );
      await tester.ensureVisible(expander);
      await tester.tap(expander);
      await _pump(tester);
      await _tap(tester, 'archive-diagnostics');
      expect(store.logging!.verbose, isTrue);
      store.logging!.sink(
        const MailArchiveDiagnostic(
          operationId: 1,
          operation: MailArchiveOperation.search,
          phase: MailArchivePhase.completed,
          elapsedMicroseconds: 42,
          items: 1,
        ),
      );
      await _pump(tester);
      expect(find.textContaining('private diagnostic sink'), findsNothing);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'archive-diagnostics');
      expect(store.logging, isNull);
    },
  );

  for (final language in StudioLanguage.values) {
    testWidgets('archive and preview fit 320px in ${language.name}', (
      tester,
    ) async {
      final store = _Store();
      final hit = store.add(
        'A very long archive subject that still wraps safely',
      );
      await _show(
        tester,
        store,
        strings: StudioStrings(language),
        size: const Size(320, 740),
      );
      expect(tester.takeException(), isNull);
      await _tap(tester, 'archive-hit-${hit.entry.id}');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'archive-back');
      expect(_key('archive-hit-${hit.entry.id}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'backend exceptions produce typed feedback without exception text',
    (tester) async {
      final store = _Store()
        ..onSearch = (_) async => throw StateError('secret-path-and-message');
      await _show(tester, store);
      expect(
        find.text(_strings.archiveProblem(MailProblemCode.storageFailure)),
        findsOneWidget,
      );
      expect(find.textContaining('secret-path-and-message'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'rebuild reparses originals with the selected attachment indexing policy',
    (tester) async {
      final store = _Store();
      await _show(tester, store);
      final expander = find.widgetWithText(
        ExpansionTile,
        _strings.archiveIndexingOptions,
      );
      await tester.ensureVisible(expander);
      await tester.tap(expander);
      await _pump(tester);
      await _tap(tester, 'archive-index-attachments');
      await _tap(tester, 'archive-rebuild');
      expect(store.rebuildCursors, [null]);
      expect(store.rebuildCodec, isA<QudsMimeCodec>());
      expect(store.rebuildAttachments, isTrue);
    },
  );
  testWidgets('MBOX import forwards the explicitly chosen dialect', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files()
      ..picked = const [
        StudioMailArchiveInput(name: 'quoted.mbox', path: '/unused'),
      ];
    await _show(tester, store, files: files);
    await _tap(tester, 'archive-import');
    await _tap(tester, 'archive-mbox-dialect');
    await tester.tap(find.text('mboxo').last);
    await _pump(tester);
    await _tap(tester, 'archive-choose-files');
    expect(files.dialectRead, MailMboxDialect.mboxo);
  });
}
