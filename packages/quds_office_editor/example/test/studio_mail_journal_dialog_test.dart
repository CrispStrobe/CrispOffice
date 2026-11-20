@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_bulk_status.dart';
import 'package:quds_office_studio/studio_mail_flag_journal.dart';
import 'package:quds_office_studio/studio_mail_journal_dialog.dart';
import 'package:quds_office_studio/studio_mail_journal_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_flag_journal.dart';

const _output = String.fromEnvironment('MAIL_JOURNAL_SCREENSHOT_DIR');
const _captureKey = ValueKey('journal-visual-capture');
Finder _key(String value) => find.byKey(ValueKey(value));

final class _RecordingStore implements StudioMailFlagJournalStore {
  _RecordingStore(this.delegate);
  final StudioMailFlagJournalStore delegate;
  final pages = <(int, int)>[];
  final loads = <String>[];
  int clears = 0;
  int binds = 0;
  Future<MailStoredFlagBatchPage> Function()? listOverride;
  Future<MailStoredFlagBatch?> Function(String)? loadOverride;
  @override
  MailAccountId get account => delegate.account;
  @override
  MailBulkFlagJournal bind({
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required List<String> subjects,
    required bool Function() isCurrent,
  }) {
    binds++;
    return delegate.bind(
      sourceAccount: sourceAccount,
      provider: provider,
      subjects: subjects,
      isCurrent: isCurrent,
    );
  }

  @override
  Future<MailStoredFlagBatchPage> list({int limit = 20, int offset = 0}) {
    pages.add((limit, offset));
    return listOverride?.call() ?? delegate.list(limit: limit, offset: offset);
  }

  @override
  Future<MailStoredFlagBatch?> load(String id) {
    loads.add(id);
    return loadOverride?.call(id) ?? delegate.load(id);
  }

  @override
  Future<int> clearCompleted() {
    clears++;
    return delegate.clearCompleted();
  }
}

Future<void> _fonts() async {
  await (FontLoader('JournalLatin')
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
  await (FontLoader('JournalArabic')
        ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _show(
  WidgetTester tester,
  StudioMailFlagJournalStore store, {
  StudioLanguage language = StudioLanguage.en,
  Size size = const Size(900, 720),
  double scale = 1,
  bool Function()? isCurrent,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final strings = StudioStrings(language);
  final direction = language == StudioLanguage.ar
      ? TextDirection.rtl
      : TextDirection.ltr;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff256356)),
          fontFamily: language == StudioLanguage.ar
              ? 'JournalArabic'
              : 'JournalLatin',
          fontFamilyFallback: const ['JournalLatin', 'JournalArabic'],
        ),
        builder: (context, child) => Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const ValueKey('open-journal'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => StudioMailJournalDialog(
                    strings: strings,
                    store: store,
                    isCurrent: isCurrent ?? () => true,
                  ),
                ),
                child: Text(strings.mailActivity),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_key('open-journal'));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(_key(key));
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    await Directory(_output).create(recursive: true);
    final picture = await boundary.toImage(pixelRatio: 1.5);
    try {
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$_output/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

Future<void> _mixed(
  TestMailFlagJournal fixture,
  StudioLanguage language,
) async {
  final subjects = switch (language) {
    StudioLanguage.en => [
      'Quarterly planning review',
      'Design notes',
      'Release checklist',
      'Next meeting',
    ],
    StudioLanguage.de => [
      'Besprechung der Quartalsplanung',
      'Designnotizen',
      'Veröffentlichungsliste',
      'Nächstes Treffen',
    ],
    StudioLanguage.ar => [
      'مراجعة خطة الربع القادم',
      'ملاحظات التصميم',
      'قائمة التحقق للإصدار',
      'الاجتماع القادم',
    ],
  };
  var attempted = 0;
  await fixture.run(
    'mixed-receipt',
    count: 4,
    subjects: subjects,
    action: MailBulkFlagAction.markRead,
    apply: (_) async => switch (++attempted) {
      1 => const MailBulkFlagAttempt.confirmed(),
      2 => const MailBulkFlagAttempt.failed(
        MailProblem(
          MailProblemCode.permissionDenied,
          mutationMayHaveOccurred: false,
        ),
      ),
      _ => const MailBulkFlagAttempt.uncertain(
        MailProblem(
          MailProblemCode.providerFailure,
          mutationMayHaveOccurred: true,
        ),
      ),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);

  testWidgets(
    'history pages and details read real durable receipts without a dispatch port',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final fixture = await TestMailFlagJournal.create();
        for (var i = 0; i < 25; i++) {
          await fixture.run(
            'batch-${i.toString().padLeft(2, '0')}',
            count: 1,
            subjects: ['Saved subject $i'],
          );
        }
        await fixture.reopen();
        return fixture;
      }))!;
      addTearDown(() => settleMailJournal(tester, fixture.dispose));
      final store = _RecordingStore(fixture.store);
      final dispatched = fixture.dispatched.length;
      await _show(tester, store);
      expect(store.pages, [(20, 0)]);
      expect(find.byType(ListTile), findsNWidgets(20));
      expect(_key('studio-mail-activity-batch-00'), findsNothing);
      await _tap(tester, 'studio-mail-activity-more');
      expect(store.pages, [(20, 0), (20, 20)]);
      expect(find.byType(ListTile), findsNWidgets(25));
      expect(_key('studio-mail-activity-more'), findsNothing);
      await _tap(tester, 'studio-mail-activity-batch-00');
      expect(store.loads, ['batch-00']);
      expect(
        tester
            .widget<StudioMailBulkStatus>(find.byType(StudioMailBulkStatus))
            .report
            .confirmedCount,
        1,
      );
      await _tap(tester, 'studio-mail-bulk-details');
      expect(find.text('Saved subject 0'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(_key('studio-mail-bulk-stop'), findsNothing);
      expect(store.binds, 0);
      expect(fixture.dispatched, hasLength(dispatched));
      await _tap(tester, 'studio-mail-bulk-details-close');
      await _tap(tester, 'studio-mail-activity-back');
      expect(find.byType(ListTile), findsNWidgets(25));
    },
  );

  testWidgets(
    'explicit clear retains active and uncertain receipts across restart',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final fixture = await TestMailFlagJournal.create();
        await fixture.run('completed', count: 1);
        await fixture.prepare('prepared-only');
        await fixture.prepare('interrupted', begin: true);
        await fixture.reopen();
        await fixture.prepare('still-running', begin: true);
        return fixture;
      }))!;
      addTearDown(() => settleMailJournal(tester, fixture.dispose));
      final store = _RecordingStore(fixture.store);
      await _show(tester, store);
      await tester.tap(_key('studio-mail-activity-clear'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.widgetWithText(
          TextButton,
          const StudioStrings(StudioLanguage.en).cancel,
        ),
      );
      await _settle(tester);
      expect(store.clears, 0);
      expect(find.byType(ListTile), findsNWidgets(4));
      await tester.tap(_key('studio-mail-activity-clear'));
      await tester.pump(const Duration(milliseconds: 300));
      await _tap(tester, 'studio-mail-activity-confirm-clear');
      expect(store.clears, 1);
      expect(_key('studio-mail-activity-completed'), findsNothing);
      expect(_key('studio-mail-activity-prepared-only'), findsNothing);
      expect(_key('studio-mail-activity-interrupted'), findsOneWidget);
      expect(_key('studio-mail-activity-still-running'), findsOneWidget);
      await _tap(tester, 'studio-mail-activity-interrupted');
      expect(
        find.text(
          const StudioStrings(StudioLanguage.en).mailActivityInterrupted,
        ),
        findsOneWidget,
      );
      final status = tester.widget<StudioMailBulkStatus>(
        find.byType(StudioMailBulkStatus),
      );
      expect(status.report.uncertainCount, 1);
      expect(status.report.unattemptedCount, 2);
      expect(fixture.dispatched, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await settleMailJournal(tester, fixture.reopen);
      final remaining = (await tester.runAsync(() => fixture.store.list()))!;
      expect(remaining.batches.map((batch) => batch.id).toSet(), {
        'interrupted',
        'still-running',
      });
    },
  );

  testWidgets('a different account returned by an adapter is never displayed', (
    tester,
  ) async {
    final fixtures = (await tester.runAsync(() async {
      final first = await TestMailFlagJournal.create(accountName: 'first');
      final other = await TestMailFlagJournal.create(accountName: 'other');
      await first.run('same-id', count: 1);
      await other.run('same-id', count: 1);
      return [first, other];
    }))!;
    for (final fixture in fixtures) {
      addTearDown(() => settleMailJournal(tester, fixture.dispose));
    }
    final store = _RecordingStore(fixtures.first.store)
      ..listOverride = () => fixtures.last.store.list();
    await _show(tester, store);
    expect(_key('studio-mail-activity-error'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    store.listOverride = null;
    await _tap(tester, 'studio-mail-activity-refresh');
    store.loadOverride = (id) => fixtures.last.store.load(id);
    await _tap(tester, 'studio-mail-activity-same-id');
    expect(_key('studio-mail-activity-error'), findsOneWidget);
    expect(find.byType(StudioMailBulkStatus), findsNothing);
    expect(store.binds, 0);
  });

  testWidgets(
    'a late detail read cannot publish after account view retirement',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final fixture = await TestMailFlagJournal.create();
        await fixture.run('late', count: 1);
        return fixture;
      }))!;
      addTearDown(() => settleMailJournal(tester, fixture.dispose));
      final receipt = (await tester.runAsync(
        () => fixture.store.load('late'),
      ))!;
      final pending = Completer<MailStoredFlagBatch?>();
      final store = _RecordingStore(fixture.store)
        ..loadOverride = (_) => pending.future;
      var current = true;
      await _show(tester, store, isCurrent: () => current);
      await tester.tap(_key('studio-mail-activity-late'));
      await tester.pump();
      current = false;
      pending.complete(receipt);
      await tester.pump();
      expect(find.byType(StudioMailBulkStatus), findsNothing);
      expect(store.loads, ['late']);
      await tester.tap(_key('studio-mail-activity-close'));
      await tester.pumpAndSettle();
      expect(_key('studio-mail-activity-dialog'), findsNothing);
      expect(store.clears, 0);
      expect(store.binds, 0);
    },
  );

  testWidgets(
    'storage errors show a fixed localized message and no private exception text',
    (tester) async {
      final fixture = (await tester.runAsync(TestMailFlagJournal.create))!;
      addTearDown(() => settleMailJournal(tester, fixture.dispose));
      final store = _RecordingStore(fixture.store)
        ..listOverride = () async =>
            throw StateError('private-path password=synthetic-private-value');
      await _show(tester, store, language: StudioLanguage.de);
      expect(
        find.text(const StudioStrings(StudioLanguage.de).mailActivityFailed),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic-private-value'), findsNothing);
      expect(find.textContaining('private-path'), findsNothing);
      expect(store.clears, 0);
    },
  );

  for (final variant in [
    (
      language: StudioLanguage.en,
      size: const Size(900, 720),
      scale: 1.0,
      name: 'en-desktop',
    ),
    (
      language: StudioLanguage.de,
      size: const Size(360, 640),
      scale: 1.4,
      name: 'de-compact',
    ),
    (
      language: StudioLanguage.ar,
      size: const Size(360, 640),
      scale: 1.4,
      name: 'ar-compact',
    ),
  ]) {
    testWidgets(
      '${variant.name} durable history and outcome details remain readable',
      (tester) async {
        final fixture = (await tester.runAsync(() async {
          final fixture = await TestMailFlagJournal.create();
          await _mixed(fixture, variant.language);
          await fixture.reopen();
          return fixture;
        }))!;
        addTearDown(() => settleMailJournal(tester, fixture.dispose));
        final store = _RecordingStore(fixture.store);
        await _show(
          tester,
          store,
          language: variant.language,
          size: variant.size,
          scale: variant.scale,
        );
        final dialog = _key('studio-mail-activity-dialog');
        expect(
          Directionality.of(tester.element(dialog)),
          variant.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
        );
        expect(
          _key('studio-mail-activity-close').hitTestable(),
          findsOneWidget,
        );
        await _capture(tester, '${variant.name}-history');
        await _tap(tester, 'studio-mail-activity-mixed-receipt');
        final report = tester
            .widget<StudioMailBulkStatus>(find.byType(StudioMailBulkStatus))
            .report;
        for (final outcome in MailBulkFlagOutcome.values) {
          expect(report.count(outcome), 1);
        }
        await _capture(tester, '${variant.name}-receipt');
        await _tap(tester, 'studio-mail-bulk-details');
        expect(
          _key('studio-mail-bulk-details-close').hitTestable(),
          findsOneWidget,
        );
        expect(_key('studio-mail-bulk-result-0'), findsOneWidget);
        await _capture(tester, '${variant.name}-details');
        await _tap(tester, 'studio-mail-bulk-details-close');
        await _tap(tester, 'studio-mail-activity-back');
        expect(store.binds, 0);
        expect(fixture.dispatched, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
