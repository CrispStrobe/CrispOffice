// Always checks the actual localized controls with real bundled fonts.
// Optional PNG evidence:
// flutter test test/studio_mail_bulk_visual_test.dart \
//   --dart-define=MAIL_BULK_SCREENSHOT_DIR=<absolute output directory>
// Ordinary test runs never write files.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
import 'package:quds_office_studio/studio_mail_bulk_status.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _output = String.fromEnvironment('MAIL_BULK_SCREENSHOT_DIR');
const _captureKey = ValueKey('mail-bulk-visual-capture');

String _text(StudioLanguage language, String en, String de, String ar) =>
    switch (language) {
      StudioLanguage.en => en,
      StudioLanguage.de => de,
      StudioLanguage.ar => ar,
    };

List<MailMessageListItem> _rows(StudioLanguage language) => [
  MailMessageListItem(
    id: 'planning',
    subject: _text(
      language,
      'Quarterly planning review',
      'Besprechung der Quartalsplanung',
      'مراجعة خطة الربع القادم',
    ),
    sender: 'Nadia Hassan <nadia@example.test>',
    to: 'Project Team <team@example.test>',
    date: DateTime(2026, 11, 20, 10, 24),
    dateLabel: _text(language, 'Today, 10:24', 'Heute, 10:24', 'اليوم، 10:24'),
    isRead: false,
    isFlagged: true,
  ),
  MailMessageListItem(
    id: 'design',
    subject: _text(
      language,
      'Design notes and next steps',
      'Designnotizen und nächste Schritte',
      'ملاحظات التصميم والخطوات التالية',
    ),
    sender: 'Jonas Weber <jonas@example.test>',
    date: DateTime(2026, 11, 19, 15, 40),
    dateLabel: _text(
      language,
      'Yesterday, 15:40',
      'Gestern, 15:40',
      'أمس، 15:40',
    ),
    isRead: true,
    isFlagged: false,
  ),
  MailMessageListItem(
    id: 'release',
    subject: _text(
      language,
      'Updated release checklist',
      'Aktualisierte Veröffentlichungsliste',
      'قائمة التحقق المحدّثة للإصدار',
    ),
    sender: 'Amal Saleh <amal@example.test>',
  ),
];

Future<void> _loadFonts() async {
  await (FontLoader('MailBulkLatin')
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
  await (FontLoader('MailBulkArabic')
        ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _showControl(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void _expectRowsUsable(WidgetTester tester) {
  final rows = _key('mail-list-rows');
  expect(rows, findsOneWidget);
  expect(tester.getSize(rows).height, greaterThanOrEqualTo(48));
  expect(_key('mail-list-check-planning').hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  if (_output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final directory = await Directory(_output).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1.5);
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  for (final variant in [
    (language: StudioLanguage.en, size: const Size(440, 850), compact: false),
    (language: StudioLanguage.de, size: const Size(440, 850), compact: false),
    (language: StudioLanguage.ar, size: const Size(440, 850), compact: false),
    (language: StudioLanguage.de, size: const Size(320, 260), compact: true),
    (language: StudioLanguage.ar, size: const Size(320, 260), compact: true),
  ]) {
    final language = variant.language;
    final name = '${language.name}-${variant.compact ? 'compact' : 'portrait'}';
    testWidgets('$name bulk controls remain usable at 1.4 text scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final strings = StudioStrings(language).mailMessageListStrings;
      final direction = language == StudioLanguage.ar
          ? TextDirection.rtl
          : TextDirection.ltr;
      var busy = false;
      var commands = 0;
      var stops = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff256356),
              ),
              fontFamily: language == StudioLanguage.ar
                  ? 'MailBulkArabic'
                  : 'MailBulkLatin',
              fontFamilyFallback: const ['MailBulkArabic', 'MailBulkLatin'],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: Directionality(textDirection: direction, child: child!),
            ),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                appBar: variant.compact
                    ? null
                    : AppBar(
                        title: Text(
                          _text(
                            language,
                            'Mail · Inbox',
                            'E-Mail · Posteingang',
                            'البريد · الوارد',
                          ),
                        ),
                      ),
                body: MailMessageList(
                  key: const ValueKey('localized-bulk-list'),
                  scopeId: 'visual/${language.name}',
                  selectionScopeId: '1',
                  strings: strings,
                  items: _rows(language),
                  busy: busy,
                  onOpen: (_) =>
                      fail('Selecting a checkbox must not open mail.'),
                  onBulkAction: (action, ids) {
                    expect(action, MailBulkFlagAction.markRead);
                    expect(ids, ['planning']);
                    expect(() => ids.clear(), throwsUnsupportedError);
                    setState(() {
                      commands++;
                      busy = true;
                    });
                  },
                  onCancelBulk: busy ? () => stops++ : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(MailMessageList);
      expect(Directionality.of(tester.element(list)), direction);
      expect(MediaQuery.textScalerOf(tester.element(list)).scale(10), 14);
      _expectRowsUsable(tester);
      if (variant.compact) {
        final header = tester.widget<SingleChildScrollView>(
          _key('mail-list-header-scroll'),
        );
        expect(header.controller!.position.maxScrollExtent, greaterThan(0));
      }

      final checkbox = _key('mail-list-check-planning');
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(
        tester.widget<Checkbox>(checkbox).semanticLabel,
        contains(_rows(language).first.subject),
      );
      expect(commands, 0);
      await _showControl(tester, _key('mail-list-selected-count'));
      expect(find.text(strings.selectedCount(1)), findsOneWidget);
      _expectRowsUsable(tester);
      await _capture(tester, '$name-selected');

      await _showControl(tester, _key('mail-list-bulk-actions'));
      await tester.tap(_key('mail-list-bulk-actions'));
      await tester.pumpAndSettle();
      for (final action in MailBulkFlagAction.values) {
        final item = _key('mail-list-bulk-${action.name}');
        expect(item.hitTestable(), findsOneWidget);
        final label = find.descendant(of: item, matching: find.byType(Text));
        expect(label, findsOneWidget);
        expect(Directionality.of(tester.element(label)), direction);
        expect(tester.widget<Text>(label).textScaler!.scale(10), 14);
      }
      await _capture(tester, '$name-actions');
      await tester.tap(_key('mail-list-bulk-markRead'));
      await tester.pumpAndSettle();
      expect(commands, 1);
      expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
      expect(
        tester
            .widget<PopupMenuButton<Object>>(_key('mail-list-bulk-actions'))
            .enabled,
        isFalse,
      );
      await _showControl(tester, _key('mail-list-stop-bulk'));
      _expectRowsUsable(tester);
      await _capture(tester, '$name-working');
      await tester.tap(_key('mail-list-stop-bulk'));
      await tester.pumpAndSettle();
      expect(stops, 1);
      expect(commands, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in StudioLanguage.values) {
    testWidgets(
      '${language.name} per-message receipt and details at 1.4 scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(440, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final account = MailAccountId(
          'visual-receipt',
          profile: MailProfileId('visual', hostId: 'test'),
        );
        final session = MailAccountSession(account);
        addTearDown(session.dispose);
        final identities = [
          for (var index = 0; index < 4; index++)
            MailOpaqueIdentity(
              account: account,
              provider: MailProviderKind.ews,
              value: 'visual-$index',
            ),
        ];
        var calls = 0;
        final report = await MailBulkFlagCoordinator().run(
          plan: MailBulkFlagPlan(
            id: 'visual-receipt',
            mailbox: MailMailboxId('inbox', account: account),
            provider: MailProviderKind.ews,
            messages: identities,
            action: MailBulkFlagAction.markRead,
          ),
          lease: session.begin(),
          isScopeCurrent: () => true,
          apply: (_, _) async => switch (++calls) {
            1 => const MailBulkFlagAttempt.confirmed(),
            2 => const MailBulkFlagAttempt.failed(
              MailProblem(
                MailProblemCode.permissionDenied,
                mutationMayHaveOccurred: false,
              ),
            ),
            _ => const MailBulkFlagAttempt.uncertain(
              MailProblem(MailProblemCode.unavailable),
            ),
          },
        );
        final subjects = [
          for (final row in _rows(language)) row.subject,
          _text(
            language,
            'Follow-up notes',
            'Weitere Notizen',
            'ملاحظات المتابعة',
          ),
        ];
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
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff256356),
                ),
                fontFamily: language == StudioLanguage.ar
                    ? 'MailBulkArabic'
                    : 'MailBulkLatin',
                fontFamilyFallback: const ['MailBulkArabic', 'MailBulkLatin'],
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: Directionality(textDirection: direction, child: child!),
              ),
              home: Scaffold(
                appBar: AppBar(
                  title: Text(
                    _text(
                      language,
                      'Mail action results',
                      'Ergebnisse der E-Mail-Aktion',
                      'نتائج إجراء البريد',
                    ),
                  ),
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: StudioMailBulkStatus(
                    strings: StudioStrings(language),
                    report: report,
                    running: false,
                    subjects: Map.unmodifiable({
                      for (var i = 0; i < identities.length; i++)
                        identities[i]: subjects[i],
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final outcome in MailBulkFlagOutcome.values) {
          expect(
            tester
                .widget<Text>(_key('studio-mail-bulk-count-${outcome.name}'))
                .data,
            endsWith(': 1'),
          );
        }
        await _capture(tester, '${language.name}-receipt');
        await _showControl(tester, _key('studio-mail-bulk-details'));
        await tester.tap(_key('studio-mail-bulk-details'));
        await tester.pumpAndSettle();
        expect(_key('studio-mail-bulk-details-dialog'), findsOneWidget);
        expect(
          Directionality.of(tester.element(_key('studio-mail-bulk-result-0'))),
          direction,
        );
        expect(find.text(subjects.first), findsOneWidget);
        await _capture(tester, '${language.name}-receipt-details');
        await tester.tap(_key('studio-mail-bulk-details-close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
