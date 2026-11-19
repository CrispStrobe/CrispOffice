// Reproducible Flutter-rendered GUI previews, separate from behavior tests.
// Copy into example/test/_gui_previews_test.dart and run from the example:
// CRISPOFFICE_GUI_SCREENSHOTS=/absolute/output flutter test --no-pub \
//   --concurrency=1 test/_gui_previews_test.dart
// Native AppKit controls require a separate check on a macOS host.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/suite_workspace.dart';

import 'support/studio_test_settings.dart';

const _capture = ValueKey<String>('gui-preview-capture');
Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _fonts() async {
  await OfficeHostFonts.ensureRegistered();
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk == null) throw StateError('FLUTTER_ROOT must identify the real SDK.');
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final loader = FontLoader('MaterialIcons')
    ..addFont(icons.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _save(WidgetTester tester, String name) async {
  await _settle(tester);
  final output = Platform.environment['CRISPOFFICE_GUI_SCREENSHOTS'];
  if (output == null) throw StateError('Set CRISPOFFICE_GUI_SCREENSHOTS.');
  final boundary = tester.renderObject<RenderRepaintBoundary>(_key('gui-preview-capture'));
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) throw StateError('Cannot render preview.');
  try {
    final bytes = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
    if (bytes == null) throw StateError('Cannot encode preview.');
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    });
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);
  testWidgets('desktop Insert, menus, customization and translated narrow layout', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    StudioWindow.supported = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 960);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final preferences = StudioRibbonPreferences(persist: false);
    await tester.pumpWidget(RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Liberation Sans',
          fontFamilyFallback: const <String>['Noto Naskh Arabic', 'Tajawal'],
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B579A)),
        ),
        home: SuiteWorkspace(ribbonPreferences: preferences),
      ),
    ));
    await _settle(tester);
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller.proofing
        .configure(OfficeProofingService(providers: []));
    await tester.tap(_key('ribbon-tab-insert'));
    await _save(tester, 'insert-desktop');

    await tester.tap(_key('ribbon-menu-word-insert-text'));
    await _save(tester, 'insert-text-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);

    await tester.tap(_key('studio-customize-ribbon'));
    await _save(tester, 'customize-ribbon');
    await tester.tap(find.text('Done'));
    await _settle(tester);

    preferences.setShowCommandLabels(true);
    await _save(tester, 'insert-labels');
    preferences.setShowCommandLabels(false);

    await configureStudioForTest(tester, language: StudioLanguage.de);
    tester.view.physicalSize = const Size(900, 760);
    await _save(tester, 'insert-narrow-german');

    await configureStudioForTest(tester, language: StudioLanguage.ar);
    await _save(tester, 'insert-narrow-arabic');

    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
