// Opt-in screenshots of the Language downloads dialog with real fonts:
//
//   flutter test test/studio_downloads_capture_test.dart --update-goldens \
//     --dart-define=STUDIO_CAPTURE_DOWNLOADS=<absolute output directory>
//
// Without the define the test only checks that each variant renders without
// an exception, so the suite never writes files by default.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_downloads_manager.dart';
import 'package:quds_office_studio/studio_material_theme.dart';

import 'support/studio_download_fakes.dart';

const _captureDir = String.fromEnvironment('STUDIO_CAPTURE_DOWNLOADS');

void main() {
  setUpAll(() async {
    if (_captureDir.isEmpty) return;
    await OfficeHostFonts.ensureRegistered();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final variant in captureVariants) {
    testWidgets('downloads dialog renders: ${variant.name}', (tester) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      final base = ThemeData(
        fontFamily: 'Liberation Sans',
        fontFamilyFallback: const <String>['Noto Naskh Arabic'],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: studioMaterialTheme(
              base,
              office: variant.dark ? OfficeTheme.dark : OfficeTheme.light,
              accent: const Color(0xFF2B579A),
              dark: variant.dark,
            ),
            home: Directionality(
              textDirection: variant.rtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => Directionality(
                          textDirection: variant.rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: buildCaptureManager(variant),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(StudioDownloadsManager), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (_captureDir.isNotEmpty) {
        await expectLater(
          find.byKey(key),
          matchesGoldenFile(Uri.file('$_captureDir/${variant.name}.png')),
        );
      }
      // Scroll to the package rows (Arabic on phones, German on wide
      // screens) for a second shot of the list itself.
      final section = find.byKey(
        ValueKey(
          variant.size.width < 600
              ? 'downloads-section-ar'
              : 'downloads-section-de',
        ),
      );
      if (section.evaluate().isNotEmpty) {
        await tester.ensureVisible(section);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (_captureDir.isNotEmpty) {
          await expectLater(
            find.byKey(key),
            matchesGoldenFile(
              Uri.file('$_captureDir/${variant.name}-rows.png'),
            ),
          );
        }
      }
    });
  }
}
