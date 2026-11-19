// Reproducible Flutter-rendered Layout/theme previews, separate from behavior tests.
// Copy into example/test/_layout_theme_previews_test.dart and run from the example:
// CRISPOFFICE_GUI_SCREENSHOTS=/absolute/output flutter test --no-pub \
//   --concurrency=1 test/_layout_theme_previews_test.dart
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
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_window.dart';
import 'package:quds_office_studio/suite_workspace.dart';

import 'support/studio_test_settings.dart';

const _capture = ValueKey<String>('gui-preview-capture');
Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _fonts() async {
  await OfficeHostFonts.ensureRegistered();
  // Raw dart:ui text uses the Flutter test engine's default Ahem family.
  // Substitute our bundled face in this visual harness so ruler labels show
  // real glyphs without changing the production renderer's font policy.
  final defaultFont = FontLoader('Ahem')
    ..addFont(
      rootBundle.load(
        'packages/quds_office_editor/fonts/LiberationSans-Regular.ttf',
      ),
    );
  await defaultFont.load();
  final defaultProbe =
      (ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: 9),
        )..addText('1234')).build()
        ..layout(const ui.ParagraphConstraints(width: 100));
  expect(
    defaultProbe.longestLine,
    lessThan(30),
    reason: 'Raw ruler text must use readable glyphs rather than Ahem blocks.',
  );
  defaultProbe.dispose();
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk == null) throw StateError('FLUTTER_ROOT must identify the real SDK.');
  final icons = File(
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
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
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    _key('gui-preview-capture'),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) throw StateError('Cannot render preview.');
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    if (bytes == null) throw StateError('Cannot encode preview.');
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    });
  } finally {
    image.dispose();
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await _settle(tester);
}

Future<void> _look(WidgetTester tester, SuiteLook look) async {
  await tester.tap(find.byTooltip('Settings'));
  await _settle(tester);
  final field = find.byType(DropdownButtonFormField<SuiteLook>);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await _settle(tester);
  await tester.tap(find.text(look == SuiteLook.dark ? 'Dark' : 'Light').last);
  await _settle(tester);
}

Future<void> _pageDialog(WidgetTester tester) async {
  final button = find.byWidgetPredicate(
    (widget) => widget is StudioCmd && widget.label == 'Page Layout…',
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);
  testWidgets(
    'precise Layout, Paragraph, dark appearance and narrow translations',
    (tester) async {
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
      preferences.setShowCommandLabels(true);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'Liberation Sans',
              fontFamilyFallback: const <String>[
                'Noto Naskh Arabic',
                'Tajawal',
              ],
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2B579A),
              ),
            ),
            home: SuiteWorkspace(ribbonPreferences: preferences),
          ),
        ),
      );
      await _settle(tester);
      final word = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      word.proofing.enabled = false;
      word.proofing.configure(OfficeProofingService(providers: []));
      await _tapKey(tester, 'ribbon-tab-layout');
      await _save(tester, 'layout-light');
      await _tapKey(tester, 'ribbon-menu-word-layout-margins');
      await _save(tester, 'layout-margins-menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      await _pageDialog(tester);
      await _save(tester, 'page-layout-margins');
      await _tapKey(tester, 'page-layout-tab-paper');
      await _save(tester, 'page-layout-paper');
      await _tapKey(tester, 'page-layout-tab-columns');
      await _save(tester, 'page-layout-columns');
      await _tapKey(tester, 'page-layout-cancel');

      await _look(tester, SuiteLook.dark);
      await _save(tester, 'settings-dark');
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _settle(tester);
      await _save(tester, 'layout-dark');
      await _tapKey(tester, 'ribbon-menu-word-layout-size');
      await _save(tester, 'layout-dark-menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      await _pageDialog(tester);
      await _save(tester, 'page-layout-dark');
      await _tapKey(tester, 'page-layout-cancel');
      await _tapKey(tester, 'ribbon-menu-word-layout-paragraph');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Paragraph…'));
      await _settle(tester);
      expect(_key('studio-paragraph-dialog'), findsOneWidget);
      expect(
        Theme.of(tester.element(_key('studio-paragraph-dialog'))).brightness,
        Brightness.dark,
      );
      await _save(tester, 'paragraph-dark');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester);

      await _look(tester, SuiteLook.light);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _settle(tester);
      await configureStudioForTest(tester, language: StudioLanguage.de);
      tester.view.physicalSize = const Size(900, 760);
      await _save(tester, 'layout-narrow-german');
      await configureStudioForTest(tester, language: StudioLanguage.ar);
      await _save(tester, 'layout-narrow-arabic');

      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
