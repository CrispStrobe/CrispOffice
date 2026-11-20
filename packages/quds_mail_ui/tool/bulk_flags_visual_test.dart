import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
// This workspace-only visual harness uses the actual host translations.
// ignore: depend_on_referenced_packages
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
// ignore: depend_on_referenced_packages
import 'package:quds_office_studio/studio_strings.dart';

void main() {
  final output = Directory(
    Platform.environment['MAIL_BULK_UI_EVIDENCE'] ??
        '../../docs/validation/mail-bulk-flags-20261120/screenshots',
  );
  for (final (name, language, size, showMenu) in [
    ('bulk-en-selected', StudioLanguage.en, const Size(440, 850), false),
    ('bulk-de-selected', StudioLanguage.de, const Size(440, 850), false),
    ('bulk-ar-selected', StudioLanguage.ar, const Size(440, 850), false),
    ('bulk-de-compact-menu', StudioLanguage.de, const Size(320, 360), true),
    ('bulk-ar-compact-menu', StudioLanguage.ar, const Size(320, 360), true),
  ]) {
    testWidgets('render $name with real localized strings and fonts', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final sdk = Platform.environment['FLUTTER_ROOT']!;
        for (final (family, path) in [
          (
            'MailSans',
            '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
          ),
          (
            'MailArabic',
            '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
          ),
          (
            'MaterialIcons',
            '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ]) {
          final bytes = await File(path).readAsBytes();
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
      final strings = StudioStrings(language).mailMessageListStrings;
      final direction = language == StudioLanguage.ar
          ? TextDirection.rtl
          : TextDirection.ltr;
      final boundaryKey = GlobalKey();
      var opens = 0;
      var commands = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'MailSans',
              fontFamilyFallback: ['MailArabic'],
              colorSchemeSeed: const Color(0xff226363),
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
              child: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: MailMessageList(
                    scopeId: 'visual-fixture/inbox',
                    selectionRevision: 1,
                    strings: strings,
                    onOpen: (_) => opens++,
                    onBulkAction: (_, _) => commands++,
                    items: [
                      MailMessageListItem(
                        id: 'one',
                        subject: switch (language) {
                          StudioLanguage.en => 'Quarterly planning',
                          StudioLanguage.de => 'Quartalsplanung',
                          StudioLanguage.ar => 'التخطيط الفصلي',
                        },
                        sender: 'Alice <alice@example.test>',
                        dateLabel: '20.11.2026',
                        isRead: false,
                        isFlagged: true,
                      ),
                      MailMessageListItem(
                        id: 'two',
                        subject: switch (language) {
                          StudioLanguage.en => 'Meeting notes',
                          StudioLanguage.de => 'Besprechungsnotizen',
                          StudioLanguage.ar => 'ملاحظات الاجتماع',
                        },
                        sender: 'Sara <sara@example.test>',
                        dateLabel: '19.11.2026',
                        isRead: true,
                        isFlagged: false,
                      ),
                      MailMessageListItem(
                        id: 'three',
                        subject: switch (language) {
                          StudioLanguage.en => 'Office update',
                          StudioLanguage.de => 'Office-Aktualisierung',
                          StudioLanguage.ar => 'تحديث المكتب',
                        },
                        sender: 'Team <team@example.test>',
                        dateLabel: '18.11.2026',
                        isRead: false,
                        isFlagged: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final select = find.byKey(const ValueKey('mail-list-select-shown'));
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      expect(find.text(strings.selectedCount(3)), findsOneWidget);
      if (showMenu) {
        final menu = find.byKey(const ValueKey('mail-list-bulk-actions'));
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        for (final label in [
          strings.markRead,
          strings.markUnread,
          strings.flag,
          strings.unflag,
        ]) {
          expect(find.text(label), findsOneWidget);
        }
      }
      expect(opens, 0);
      expect(commands, 0);
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        await output.create(recursive: true);
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${output.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        await File('${output.path}/$name.json').writeAsString(
          jsonEncode({
            'scenario': name,
            'width': size.width,
            'height': size.height,
            'text_scale': 1.4,
            'language': language.name,
            'direction': direction.name,
            'selected_loaded_rows': 3,
            'menu_open': showMenu,
            'body_opens': opens,
            'mutation_callbacks': commands,
            'source': 'Synthetic headers; actual Studio translations',
            'runtime': 'Flutter widget test with bundled local fonts',
          }),
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
