import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_cached_search_dialog.dart';
import 'package:quds_office_studio/studio_mail_cached_search_strings.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_material_theme.dart';
import 'package:quds_office_studio/studio_strings.dart';

import '../test/support/mail_outbox_store.dart';

const _captureKey = ValueKey('mail-live-search-visual-capture');
const _destination = String.fromEnvironment('MAIL_LIVE_SEARCH_SCREENSHOT_DIR');
const _accent = Color(0xFF2B579A);
final _query = find.byKey(const ValueKey('studio-mail-cached-search-query'));
final _start = find.byKey(const ValueKey('studio-mail-cached-search-start'));
final _refresh = find.byKey(
  const ValueKey('studio-mail-cached-search-refresh'),
);
final _automatic = find.byKey(
  const ValueKey('studio-mail-cached-search-auto-refresh'),
);
final _close = find.byKey(const ValueKey('studio-mail-cached-search-close'));
var _fontsLoaded = false;

Future<void> _fonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    await OfficeHostFonts.ensureRegistered();
    await (FontLoader('Tajawal')
          ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
          ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  _fontsLoaded = true;
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final elapsed = Stopwatch()..start();
  while (!done() && elapsed.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 1));
    if (!done()) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
  }
  expect(done(), isTrue, reason: 'Local visual fixture did not settle.');
  await tester.pump();
}

Future<void> _idle(WidgetTester tester) => _until(
  tester,
  () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
);

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _capture(WidgetTester tester, String name) async {
  // Let the switch finish moving after an asynchronous refresh changes it.
  // Capturing its first frame would visually contradict the asserted value.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  if (_destination.isNotEmpty) {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    await tester.runAsync(() async {
      final directory = await Directory(_destination).create(recursive: true);
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/$name.png').writeAsBytes(
          bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
  }
  expect(tester.takeException(), isNull, reason: '$name must not overflow.');
}

Future<void> _showReadableBody(WidgetTester tester) async {
  final viewport = find.byKey(const ValueKey('mail-reader-scroll'));
  final viewportBounds = tester.getRect(viewport);
  expect(
    viewportBounds.height,
    greaterThanOrEqualTo(180),
    reason: 'Refresh controls must leave space for reading the message.',
  );

  final surface = tester.renderObject<RenderMailSelectionSurface>(
    find.byType(MailSelectionSurface),
  );
  final controller = surface.controller;
  final paragraph = controller.presentation.bodyText.split('\n').first;
  expect(paragraph, isNotEmpty);
  final start = controller.decodedText.indexOf(paragraph);
  expect(start, greaterThanOrEqualTo(0));
  final previousSelection = controller.selection;
  controller.select(
    TextSelection(baseOffset: start, extentOffset: start + paragraph.length),
  );
  await tester.pump();

  // Exercise the reader's normal scrolling; no header or control is hidden to
  // make the message fit. The short fixture reaches its body at the lower end.
  await tester.drag(viewport, const Offset(0, -500));
  await tester.pumpAndSettle();
  final localBounds = surface.selectionRect;
  expect(localBounds, isNotNull);
  final paintedBounds = localBounds!.shift(surface.localToGlobal(Offset.zero));
  expect(
    viewportBounds.inflate(1).contains(paintedBounds.topLeft) &&
        viewportBounds.inflate(1).contains(paintedBounds.bottomRight),
    isTrue,
    reason: 'The first message paragraph must be readable inside the viewport.',
  );
  controller.select(previousSelection);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousWarnings = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting();
  });
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarnings,
  );

  for (final configuration in const [
    (language: StudioLanguage.en, size: Size(1100, 900), scale: 1.0),
    (language: StudioLanguage.en, size: Size(360, 640), scale: 1.3),
    (language: StudioLanguage.de, size: Size(360, 640), scale: 1.3),
    (language: StudioLanguage.ar, size: Size(360, 640), scale: 1.3),
  ]) {
    final language = configuration.language;
    final compact = configuration.size.width < 600;
    final name = '${language.name}-${compact ? 'compact' : 'desktop'}';
    testWidgets('live saved search controls remain usable in $name', (
      tester,
    ) async {
      await _fonts(tester);
      final strings = StudioStrings(language);
      final subject = switch (language) {
        StudioLanguage.en => 'Updated project plan',
        StudioLanguage.de => 'Aktualisierter Projektplan',
        StudioLanguage.ar => 'خطة المشروع المحدثة',
      };
      final identity = StudioMailDraftAccount(
        provider: 'imap',
        endpoint: 'imaps://mail.example.test:993',
        login: 'alex@example.test',
        sender: 'alex@example.test',
      );
      final fixture = await awaitOutboxOperation(
        tester,
        SqliteOutboxFixture.create(identity),
      );
      final files = await awaitOutboxOperation(
        tester,
        Directory.systemTemp.createTemp('mail-live-search-visual-'),
      );
      final directory = NativeStudioMailLocalAccountStore(appDirectory: files);
      await awaitOutboxOperation(tester, directory.remember(identity));
      var failOpen = false;

      addTearDown(() async {
        if (_close.evaluate().isNotEmpty) {
          tester.widget<IconButton>(_close).onPressed?.call();
          await _until(
            tester,
            () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await awaitOutboxOperation(tester, fixture.close());
        await awaitOutboxOperation(tester, files.delete(recursive: true));
      });

      final owner = await awaitOutboxOperation(tester, fixture.open(identity));
      final mailbox = (owner as StudioMailMailboxStoreOwner).mailboxStore;
      final accountSession = MailAccountSession(identity.account);
      final lease = accountSession.begin();
      final header = MailHeaderRecord(
        id: MailMessageId('visual-message'),
        remote: MailImapIdentity(
          mailbox: MailMailboxId('Inbox', account: identity.account),
          uidValidity: 23,
          uid: 1,
        ),
        envelope: MailEnvelope(
          subject: subject,
          from: const [MailAddress('maria@example.test', displayName: 'Maria')],
          to: [MailAddress(identity.sender)],
          sentAt: DateTime.utc(2026, 11, 21, 9),
        ),
        flags: const MailMessageFlags(isRead: false, isFlagged: true),
      );
      await awaitOutboxOperation(
        tester,
        mailbox.saveView(
          MailMailbox(
            id: MailMailboxId('Inbox', account: identity.account),
            displayName: 'Inbox',
          ),
          [header],
          hasMore: false,
          lease: lease,
        ),
      );
      await awaitOutboxOperation(
        tester,
        mailbox.cacheMessage(
          header,
          MailMessage(
            raw: MailBytes(
              utf8.encode('Subject: Project plan\r\n\r\nSaved mail'),
            ),
            envelope: header.envelope,
            body: MailBody(
              plainText: switch (language) {
                StudioLanguage.en =>
                  'The revised plan is ready for review.\n\nThis message is saved on this device.',
                StudioLanguage.de =>
                  'Der überarbeitete Plan ist zur Prüfung bereit.\n\nDiese Nachricht ist auf diesem Gerät gespeichert.',
                StudioLanguage.ar =>
                  'الخطة المنقحة جاهزة للمراجعة.\n\nهذه الرسالة محفوظة على هذا الجهاز.',
              },
            ),
            localId: header.id,
            remoteIdentity: header.remote,
          ),
          lease: lease,
        ),
      );
      await awaitOutboxOperation(tester, owner.close());
      accountSession.dispose();

      await tester.binding.setSurfaceSize(configuration.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: studioMaterialTheme(
              ThemeData(
                useMaterial3: true,
                fontFamily: 'Liberation Sans',
                fontFamilyFallback: const ['Noto Naskh Arabic', 'Tajawal'],
                colorScheme: ColorScheme.fromSeed(seedColor: _accent),
              ),
              office: OfficeTheme.light.copyWith(
                focusRing: _accent,
                fontFamily: 'Tajawal',
              ),
              accent: _accent,
              dark: false,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(configuration.scale)),
              child: Directionality(
                textDirection: language == StudioLanguage.ar
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => StudioMailCachedSearchDialog(
                        strings: strings,
                        store: directory,
                        isCurrent: () => true,
                        draftStoreFactory: (account) async {
                          if (failOpen) {
                            throw const StudioMailDraftStoreException(
                              MailProblemCode.storageFailure,
                            );
                          }
                          return fixture.open(account);
                        },
                      ),
                    ),
                    child: Text(strings.mailCachedSearch),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _press(tester, find.text(strings.mailCachedSearch));
      await _idle(tester);
      await tester.ensureVisible(_query);
      await tester.enterText(_query, 'is:unread');
      await _press(tester, _start);
      await _idle(tester);
      expect(tester.widget<SwitchListTile>(_automatic).onChanged, isNotNull);
      await _press(tester, _refresh);
      await _idle(tester);
      await _press(tester, _automatic);
      expect(tester.widget<SwitchListTile>(_automatic).value, isTrue);
      await tester.scrollUntilVisible(
        find.text(subject),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey('studio-mail-cached-search-results'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await _capture(tester, '$name-results');

      await _press(tester, find.text(subject));
      await _idle(tester);
      expect(find.byType(MailMessageView), findsOneWidget);
      await _showReadableBody(tester);
      await _capture(tester, '$name-reader');

      failOpen = true;
      await _press(tester, _refresh);
      await _idle(tester);
      expect(find.text(strings.mailCachedSearchRefreshPartial), findsOneWidget);
      expect(tester.widget<SwitchListTile>(_automatic).value, isFalse);
      expect(find.byType(MailMessageView), findsNothing);
      await _capture(tester, '$name-partial');
    });
  }
}
