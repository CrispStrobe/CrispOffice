import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:quds_office_editor/quds_office_editor.dart'
    show OfficeHostFonts;
import 'package:quds_office_studio/studio_mail_archive_native.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

// These cases always run layout assertions. Set QUDS_MAIL_PORTABILITY_SHOTS to
// an absolute output directory to also retain deterministic fixture captures.
final _output = Platform.environment['QUDS_MAIL_PORTABILITY_SHOTS'];
const _destination =
    '/home/alex/Documents/Mail exports/Customer correspondence/2026/'
    'Project archives/November migration/crispoffice-mail-export-'
    '20261119-final-verified-original-messages-7fa9b13e';

final class _VisualStore extends Fake implements StudioMailArchiveStore {
  _VisualStore() {
    for (final subject in [
      'Project Atlas — approved contract and next steps',
      'November invoice · Rechnung für November',
      'تأكيد موعد الاجتماع ومراجعة مستندات المشروع',
      'Support case 1042: original correspondence',
      'Meeting minutes and final project report',
    ]) {
      final raw = MailBytes(
        Uint8List.fromList(
          utf8.encode(
            'From: Morgan Reed <morgan@example.test>\r\n'
            'To: Alex <alex@example.test>\r\n'
            'Subject: $subject\r\n'
            'Content-Type: text/plain; charset=utf-8\r\n\r\n'
            'This original message is retained in the archive.\r\n',
          ),
        ),
      );
      originals[raw.sha256] = raw;
      entries.add(
        MailArchiveSearchHit(
          entry: MailArchiveEntry(
            id: raw.sha256,
            envelope: MailEnvelope(
              subject: subject,
              from: const [
                MailAddress('morgan@example.test', displayName: 'Morgan Reed'),
              ],
              to: const [MailAddress('alex@example.test')],
              sentAt: DateTime.utc(2026, 11, 18, 14, 30),
            ),
            archivedAt: DateTime.utc(2026, 11, 19, 12),
            byteLength: raw.length,
            attachmentCount: 0,
            indexTruncated: false,
            attachmentTextIndexed: 0,
            attachmentTextSkipped: 0,
          ),
          preview: 'This original message is retained in the archive.',
        ),
      );
    }
  }

  @override
  final profile = MailProfileId('visual-fixture', hostId: 'studio-tests');
  final entries = <MailArchiveSearchHit>[];
  final originals = <String, MailBytes>{};

  @override
  set diagnostics(MailArchiveDiagnostics? value) {}
  @override
  Future<MailResult<MailArchiveSearchPage>> search(
    MailArchiveSearchRequest request,
  ) async => MailSuccess(
    MailArchiveSearchPage(hits: entries, total: entries.length, offset: 0),
  );
  @override
  Future<MailResult<MailArchiveStats>> statistics() async => MailSuccess(
    MailArchiveStats(
      messages: entries.length,
      rawBytes: totalBytes,
      indexedMessages: entries.length,
      origins: entries.length,
    ),
  );
  int get totalBytes =>
      originals.values.fold(0, (total, value) => total + value.length);
  @override
  Future<MailResult<List<MailArchiveSavedSearch>>> listSearches() async =>
      const MailSuccess([]);
  @override
  Future<MailResult<MailBytes?>> loadOriginal(String id) async =>
      MailSuccess(originals[id]);
  @override
  Future<MailResult<List<MailArchiveOrigin>>> listOrigins(String id) async =>
      const MailSuccess([
        MailArchiveOrigin(
          source: 'Office mailbox',
          folder: '/Imported/Projects',
        ),
      ]);
  @override
  Future<MailResult<MailArchiveExportPlan>> planExport(
    MailArchiveSearchRequest request, {
    MailArchiveExportLimits exportLimits = const MailArchiveExportLimits(),
    MailCancellationToken? cancellation,
  }) async => MailSuccess(
    MailArchiveExportPlan(
      profile: profile,
      createdAt: DateTime.utc(2026, 11, 19),
      items: [
        for (final entry in entries)
          MailArchiveExportItem(
            id: entry.entry.id,
            byteLength: entry.entry.byteLength,
            origins: const [
              MailArchiveOrigin(
                source: 'Office mailbox',
                folder: '/Imported/Projects',
              ),
            ],
          ),
      ],
    ),
  );
  @override
  Future<void> close() async {}
}

final class _VisualFiles extends Fake implements StudioMailArchiveFiles {
  @override
  Future<String?> pickDirectory() async => '/home/alex/Documents/Mail exports';

  @override
  Future<MailArchiveExportReport> exportPlan(
    MailArchiveExportPlan plan,
    String parentPath, {
    required MailArchiveOriginalLoader loadOriginal,
    required MailCancellationToken cancellation,
    MailArchiveExportProgressSink? onProgress,
  }) async => MailArchiveExportReport(
    status: MailArchiveExportStatus.completed,
    planned: plan.items.length,
    written: plan.items.length,
    existing: 0,
    failed: 0,
    bytes: plan.totalBytes,
    elapsedMicroseconds: 15000,
    observerErrors: 0,
    failures: const [],
    droppedFailures: 0,
    directoryPath: _destination,
  );
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _loadFonts() async {
  await OfficeHostFonts.ensureRegistered();
  await (FontLoader('Tajawal')
        ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  expect(tester.takeException(), isNull);
  if (_output == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_output!)..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<GlobalKey> _show(
  WidgetTester tester,
  StudioLanguage language,
  Size size,
) async {
  await tester.runAsync(_loadFonts);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Liberation Sans',
          fontFamilyFallback: const ['Noto Naskh Arabic', 'Tajawal'],
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B579A)),
        ),
        home: StudioMailArchiveDialog(
          strings: StudioStrings(language),
          store: _VisualStore(),
          files: _VisualFiles(),
        ),
      ),
    ),
  );
  await _pump(tester);
  return key;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final control = _key(key);
  await tester.ensureVisible(control);
  await tester.pump();
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await _pump(tester);
}

void main() {
  testWidgets(
    'desktop portability controls, export confirmation and long destination',
    (tester) async {
      final capture = await _show(
        tester,
        StudioLanguage.en,
        const Size(1280, 900),
      );
      for (final name in [
        'archive-import-directory',
        'archive-bulk-export',
        'archive-resume-export',
      ]) {
        expect(_key(name).hitTestable(), findsOneWidget);
      }
      await _capture(tester, capture, 'archive-portability-desktop-en');
      await _tap(tester, 'archive-bulk-export');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('including every page'), findsOneWidget);
      await _capture(tester, capture, 'archive-export-confirmation-en');
      await _tap(tester, 'archive-choose-export-directory');
      expect(find.textContaining('5 written'), findsOneWidget);
      await tester.ensureVisible(_key('archive-export-directory'));
      await _pump(tester);
      expect(find.textContaining(_destination), findsOneWidget);
      await _capture(tester, capture, 'archive-export-report-en');
    },
  );

  testWidgets(
    'narrow Arabic portability controls and export report remain usable',
    (tester) async {
      final capture = await _show(
        tester,
        StudioLanguage.ar,
        const Size(390, 844),
      );
      const strings = StudioStrings(StudioLanguage.ar);
      expect(find.text(strings.archiveImportDirectory), findsOneWidget);
      expect(find.text(strings.archiveBulkExport), findsOneWidget);
      expect(
        Directionality.of(tester.element(_key('archive-bulk-export'))),
        TextDirection.rtl,
      );
      await _capture(tester, capture, 'archive-portability-mobile-ar');
      await _tap(tester, 'archive-bulk-export');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(_key('archive-choose-export-directory')),
        ),
        TextDirection.rtl,
      );
      await _capture(tester, capture, 'archive-export-confirmation-ar');
      await _tap(tester, 'archive-choose-export-directory');
      await tester.ensureVisible(_key('archive-export-directory'));
      await _pump(tester);
      expect(find.textContaining(_destination), findsOneWidget);
      final destination = tester.widget<SelectableText>(
        _key('archive-export-directory'),
      );
      expect(destination.data, _destination);
      expect(destination.textDirection, TextDirection.ltr);
      await _capture(tester, capture, 'archive-export-report-ar');
    },
  );
}
