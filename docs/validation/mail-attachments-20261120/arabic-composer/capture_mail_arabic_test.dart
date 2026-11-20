import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_strings.dart';

Future<void> pumpComposer(WidgetTester tester) async {
  // Match the production composer regression harness: the Word canvas can
  // continue requesting frames, so wait through the dialog transition rather
  // than requiring all editor animation to cease.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets('capture current narrow Arabic mail composer', (tester) async {
    final path = Platform.environment['QUDS_MAIL_CAPTURE_PATH'];
    expect(path, isNotNull);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(OfficeHostFonts.ensureRegistered);
    await tester.runAsync(() async {
      final iconFile = File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/'
        'material_fonts/MaterialIcons-Regular.otf',
      );
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(ByteData.sublistView(await iconFile.readAsBytes())),
        );
      await loader.load();
    });
    const boundaryKey = ValueKey('mail-capture-boundary');
    final draft = StudioMailDraft(
      to: 'reader@example.invalid',
      subject: 'مراجعة التقرير والميزانية',
      body:
          'مرحبًا بكم في مراجعة التقرير والميزانية.\n'
          'أرفقت المستندات للاطلاع عليها. شكرًا لكم.',
      attachments: StudioMailAttachments.from([
        StudioMailAttachment(
          name: 'مراجعة 2026.pdf',
          bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
        ),
        StudioMailAttachment(
          name: 'Budget.xlsx',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Liberation Sans',
            fontFamilyFallback: const ['Noto Naskh Arabic', 'Tajawal'],
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2B579A),
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<StudioMailDraft>(
                  context: context,
                  builder: (_) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: StudioMailComposeDialog(
                      strings: const StudioStrings(StudioLanguage.ar),
                      from: 'writer@example.invalid',
                      initialDraft: draft,
                    ),
                  ),
                ),
                child: const Text('Open composer'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open composer'));
    await pumpComposer(tester);
    await tester.ensureVisible(find.byType(QudsWordEditor));
    await pumpComposer(tester);
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(path!).writeAsBytes(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  });
}
