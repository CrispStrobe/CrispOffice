import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_outbox_dialog.dart';
import 'package:quds_office_studio/studio_mail_schedule_dialog.dart';
import 'package:quds_office_studio/studio_mail_schedule_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import '../test/support/mail_outbox_store.dart';

const _captureKey = ValueKey('mail-schedule-visual-capture');
var _fontsLoaded = false;

Future<void> _fonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    final text = FontLoader('MailSchedulePreview')
      ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await text.load();
    await icons.load();
  });
  _fontsLoaded = true;
}

Future<void> _capture(WidgetTester tester, String name) async {
  final destination = Platform.environment['MAIL_SCHEDULE_SCREENSHOT_DIR'];
  if (destination == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final directory = await Directory(destination).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(initializeDateFormatting);

  for (final language in StudioLanguage.values) {
    testWidgets('capture scheduled Outbox and picker in ${language.name}', (
      tester,
    ) async {
      final strings = StudioStrings(language);
      final narrow = language == StudioLanguage.ar;
      final now = DateTime.utc(2026, 11, 21, 12, 30);
      final identity = StudioMailDraftAccount(
        provider: 'imap',
        endpoint: 'imaps://mail.example.test:993',
        login: 'alex@example.test',
        sender: 'alex@example.test',
      );
      final database = await awaitOutboxOperation(
        tester,
        SqliteOutboxFixture.create(identity),
      );
      final store = SqliteStudioMailDraftStore(
        repository: database.repository,
        account: identity.account,
        clock: () => now,
      );
      database.adapters.add(store);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await awaitOutboxOperation(tester, database.close());
      });
      await awaitOutboxOperation(tester, store.load());
      final entry = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(
          StudioMailDraft(
            to: 'team@example.test',
            subject: switch (language) {
              StudioLanguage.en => 'Weekly project update',
              StudioLanguage.de => 'Wöchentlicher Projektbericht',
              StudioLanguage.ar => 'تحديث المشروع الأسبوعي',
            },
            body: 'The weekly update is ready for review.',
          ),
          identity.sender,
        ),
      );
      await awaitOutboxOperation(
        tester,
        store.scheduleOutbox(
          entry,
          sendNotBefore: now.add(const Duration(hours: 1)),
        ),
      );
      await _fonts(tester);
      await tester.binding.setSurfaceSize(
        narrow ? const Size(390, 844) : const Size(1100, 850),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'MailSchedulePreview'),
            builder: (context, child) => Directionality(
              textDirection: narrow ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => StudioMailOutboxDialog(
                        strings: strings,
                        store: store,
                        clock: () => now,
                        elapsed: () => Duration.zero,
                        isCurrent: () => true,
                        submit: (_, {required attemptId}) =>
                            throw StateError('Visual fixtures never send.'),
                      ),
                    ),
                    child: const Text('Open Outbox'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Outbox'));
      await pumpOutboxWidgets(tester);
      expect(find.text(strings.mailSchedulePaused), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'outbox-${language.name}');

      final schedule = find.byKey(
        ValueKey('studio-mail-outbox-schedule-${entry.id}'),
      );
      await tester.ensureVisible(schedule);
      await pumpOutboxWidgets(tester);
      if (narrow) await _capture(tester, 'outbox-ar-controls');
      await tester.tap(schedule);
      await pumpOutboxWidgets(tester);
      expect(find.byType(StudioMailScheduleDialog), findsOneWidget);
      expect(find.text(strings.mailScheduleExplanation), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'picker-${language.name}');
      await tester.tap(find.text(strings.cancel));
      await pumpOutboxWidgets(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
