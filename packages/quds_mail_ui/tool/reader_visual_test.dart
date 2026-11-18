import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_reader_example/main.dart' show exampleMessage;
import 'package:quds_mail_ui/quds_mail_ui.dart';

void main() {
  final output = Directory(
    Platform.environment['MAIL_READER_EVIDENCE'] ??
        '../../docs/validation/mail-reader-20261118/ui/screenshots',
  );
  for (final scenario
      in <
        ({
          String name,
          Size size,
          TextDirection direction,
          double scale,
          MailReaderMode mode,
        })
      >[
        (
          name: 'reader-desktop',
          size: const Size(1100, 850),
          direction: TextDirection.ltr,
          scale: 1,
          mode: MailReaderMode.full,
        ),
        (
          name: 'reader-rtl-narrow',
          size: const Size(390, 844),
          direction: TextDirection.rtl,
          scale: 1.5,
          mode: MailReaderMode.preview,
        ),
      ]) {
    testWidgets('render ${scenario.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final sdk = Platform.environment['FLUTTER_ROOT']!;
        final fonts = <String, String>{
          'ReaderSans':
              '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
          'ReaderArabic':
              '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
          'MaterialIcons':
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        };
        for (final entry in fonts.entries) {
          final bytes = await File(entry.value).readAsBytes();
          await (FontLoader(
            entry.key,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
      final controller = MailReaderController.fromBytes(
        exampleMessage(),
        codec: const QudsMimeCodec(),
        mode: scenario.mode,
      );
      controller.search('agenda');
      controller.nextSearchMatch();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'ReaderSans',
              fontFamilyFallback: ['ReaderArabic'],
              colorSchemeSeed: const Color(0xff226363),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scenario.scale),
              ),
              child: Directionality(
                textDirection: scenario.direction,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Quds saved-message reader'),
                  ),
                  body: MailMessageView(
                    controller: controller,
                    compact: scenario.mode == MailReaderMode.preview,
                    onOpenSource: (bytes, view) async {},
                    onOpenAttachmentReadOnly: (attachment) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.result.status, MailParseStatus.complete);
      expect(find.byType(MailSelectionSurface), findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await output.create(recursive: true);
        await File(
          '${output.path}/${scenario.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        await File('${output.path}/${scenario.name}.json').writeAsString(
          jsonEncode({
            'width': scenario.size.width,
            'height': scenario.size.height,
            'text_scale': scenario.scale,
            'direction': scenario.direction.name,
            'mode': scenario.mode.name,
            'source_sha256': controller.result.original!.sha256,
            'parse_status': controller.result.status.name,
            'runtime':
                'Flutter widget test with real local fonts and RepaintBoundary capture',
          }),
        );
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
