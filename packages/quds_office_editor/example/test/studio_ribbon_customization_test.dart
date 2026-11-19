import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/suite_workspace.dart';

import 'support/studio_test_settings.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<WordEditorController> _studio(
  WidgetTester tester,
  StudioRibbonPreferences preferences, {
  Size size = const Size(1280, 900),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    preferences.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Liberation Sans'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SuiteWorkspace(ribbonPreferences: preferences),
    ),
  );
  await _frames(tester);
  final word = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  word.proofing.enabled = false;
  word.proofing.configure(OfficeProofingService(providers: []));
  word.document = WmlDocument.empty(text: 'Insert here.');
  word.refresh();
  await _frames(tester);
  return word;
}

Future<void> _selectInsert(WidgetTester tester) async {
  await tester.ensureVisible(_key('ribbon-tab-insert'));
  await tester.tap(_key('ribbon-tab-insert'));
  await _frames(tester);
}

Future<void> _menu(WidgetTester tester, String id, String command) async {
  final menu = _key('ribbon-menu-word-insert-$id');
  final scrollable = find.descendant(
    of: find.byType(StudioRibbonStrip),
    matching: find.byType(Scrollable),
  );
  if (menu.evaluate().isEmpty) {
    await tester.scrollUntilVisible(menu, 180, scrollable: scrollable);
  }
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await _frames(tester);
  final item = find.widgetWithText(MenuItemButton, command);
  await tester.ensureVisible(item);
  await tester.tap(item);
  await _frames(tester);
}

List<String> _groupIds(WidgetTester tester) => tester
    .widget<StudioRibbonStrip>(find.byType(StudioRibbonStrip))
    .groups
    .map((group) => group.id)
    .toList();

void main() {
  testWidgets(
    'compact Insert menus execute table and footnote commands with undo',
    (tester) async {
      final preferences = StudioRibbonPreferences(persist: false);
      final word = await _studio(tester, preferences);
      await _selectInsert(tester);
      expect(_groupIds(tester), [
        'insert',
        'illustrations',
        'text',
        'references',
        'zotero',
        'equations',
        'mailings',
      ]);
      expect(find.text('Add/Edit citation'), findsNothing);
      expect(find.byTooltip('Add/Edit citation (Ctrl+Alt+C)'), findsOneWidget);
      expect(find.text('Spreadsheets'), findsNothing);
      expect(find.byTooltip('Spreadsheets'), findsOneWidget);

      await _menu(tester, 'table', '2×2');
      expect(
        word.document.sections
            .expand((section) => section.blocks)
            .whereType<WmlTable>(),
        hasLength(1),
      );
      expect(word.isDirty, isTrue);
      await tester.tap(_key('ribbon-tab-home'));
      await _frames(tester);
      expect(_groupIds(tester), contains('table'));
      await _selectInsert(tester);
      await tester.tap(find.byTooltip('Undo'));
      await _frames(tester);
      expect(
        word.document.sections
            .expand((section) => section.blocks)
            .whereType<WmlTable>(),
        isEmpty,
      );

      await _menu(tester, 'notes', 'Footnote');
      expect(word.document.footnotes, hasLength(1));
      expect(word.isDirty, isTrue);
      await tester.tap(find.byTooltip('Undo'));
      await _frames(tester);
      expect(word.document.footnotes, isEmpty);

      await _menu(tester, 'charts', 'Column');
      expect(word.document.visuals, hasLength(1));
      expect(word.selectedVisual?.visual.kind, OfficeVisualKind.chartColumn);
      await tester.tap(_key('ribbon-tab-home'));
      await _frames(tester);
      expect(_groupIds(tester), contains('chart-design'));
      await tester.tap(find.byTooltip('Undo'));
      await _frames(tester);
      expect(word.document.visuals, isEmpty);
      preferences.setVisible('tabs.word', 'design', false);
      await _selectInsert(tester);
      final equation = find.byTooltip('Equation');
      await tester.ensureVisible(equation);
      await tester.tap(equation);
      await _frames(tester);
      expect(word.selectedEquation, isNotNull);
      expect(_key('ribbon-tab-design'), findsNothing);
      expect(
        tester.widget<StudioTabChip>(_key('ribbon-tab-home')).selected,
        isTrue,
      );
      expect(
        _groupIds(tester),
        containsAll(['tools', 'symbols', 'structures']),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'customization hides and orders groups, switches labels, and restores defaults',
    (tester) async {
      final preferences = StudioRibbonPreferences(persist: false);
      await _studio(tester, preferences);
      await _selectInsert(tester);
      await tester.tap(_key('studio-customize-ribbon'));
      await _frames(tester);
      expect(_key('studio-ribbon-customization'), findsOneWidget);
      await tester.tap(_key('ribbon-visible-groups.word.insert-illustrations'));
      await tester.tap(_key('ribbon-up-groups.word.insert-text'));
      await tester.tap(_key('ribbon-setting-command-labels'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await _frames(tester);
      expect(_groupIds(tester).take(3), ['insert', 'text', 'references']);
      expect(_groupIds(tester), isNot(contains('illustrations')));
      expect(find.text('Picture'), findsOneWidget);
      expect(preferences.showCommandLabels, isTrue);

      await tester.tap(find.byTooltip('Spreadsheets'));
      await _frames(tester);
      await _selectInsert(tester);
      expect(_groupIds(tester), contains('illustrations'));
      await tester.tap(find.byTooltip('Documents'));
      await _frames(tester);
      await _selectInsert(tester);
      expect(_groupIds(tester), isNot(contains('illustrations')));

      await tester.tap(_key('studio-customize-ribbon'));
      await _frames(tester);
      await tester.tap(_key('ribbon-reset'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await _frames(tester);
      expect(_groupIds(tester), [
        'insert',
        'illustrations',
        'text',
        'references',
        'zotero',
        'equations',
        'mailings',
      ]);
      expect(preferences.showCommandLabels, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden tabs recover selection and collapsed ribbon can always be expanded',
    (tester) async {
      final preferences = StudioRibbonPreferences(persist: false);
      await _studio(tester, preferences);
      await _selectInsert(tester);
      await tester.tap(_key('studio-customize-ribbon'));
      await _frames(tester);
      await tester.tap(_key('ribbon-visible-tabs.word-insert'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await _frames(tester);
      expect(_key('ribbon-tab-insert'), findsNothing);
      expect(
        tester.widget<StudioTabChip>(_key('ribbon-tab-home')).selected,
        isTrue,
      );
      await tester.tap(_key('studio-collapse-ribbon'));
      await _frames(tester);
      expect(find.byType(StudioRibbonStrip), findsNothing);
      expect(_key('studio-customize-ribbon'), findsOneWidget);
      await tester.tap(_key('ribbon-tab-home'));
      await _frames(tester);
      expect(find.byType(StudioRibbonStrip), findsOneWidget);
      expect(preferences.collapsed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact commands and customization work in narrow Arabic at large text scale',
    (tester) async {
      final preferences = StudioRibbonPreferences(persist: false);
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        previousErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      await _studio(
        tester,
        preferences,
        size: const Size(500, 1000),
        textScale: 1.6,
      );
      await configureStudioForTest(tester, language: StudioLanguage.ar);
      await _selectInsert(tester);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('المزيد من الأوامر'), findsOneWidget);
      await _menu(tester, 'table', '٢×٢');
      expect(tester.takeException(), isNull);
      await tester.tap(_key('studio-customize-ribbon'));
      await _frames(tester);
      expect(_key('studio-ribbon-customization'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'تم'));
      await _frames(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('all application tabs retain unique reachable groups', (
    tester,
  ) async {
    final preferences = StudioRibbonPreferences(persist: false);
    await _studio(tester, preferences);
    for (final app in ['Documents', 'Spreadsheets', 'Presentations', 'PDF']) {
      await tester.tap(find.byTooltip(app));
      await _frames(tester);
      final tabs = tester
          .widgetList<StudioTabChip>(find.byType(StudioTabChip))
          .toList();
      for (final tab in tabs) {
        await tester.ensureVisible(find.byKey(tab.key!));
        await tester.tap(find.byKey(tab.key!));
        await _frames(tester);
        final groups = _groupIds(tester);
        expect(groups, isNotEmpty, reason: '$app / ${tab.label}');
        expect(
          groups.toSet(),
          hasLength(groups.length),
          reason: '$app / ${tab.label}',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });
}
