import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/suite_workspace.dart';

import 'support/studio_document_mode.dart';
import 'support/studio_test_settings.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Finder _command(String label) => find.byWidgetPredicate(
  (widget) => widget is StudioCmd && widget.label == label,
);

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<WordEditorController> _studio(
  WidgetTester tester, {
  Size size = const Size(1440, 1000),
  double textScale = 1,
}) async {
  final preferences = StudioRibbonPreferences(persist: false);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    preferences.dispose();
    await tester.binding.setSurfaceSize(null);
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
  word.document = WmlDocument.empty(text: 'Keep this paragraph.');
  word.commands.clear();
  word.markClean();
  word.refresh();
  await _frames(tester);
  return word;
}

Future<void> _tab(WidgetTester tester, String tab) async {
  final finder = _key('ribbon-tab-$tab');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _frames(tester);
}

Future<void> _exposeRibbon(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find.descendant(
      of: find.byType(StudioRibbonStrip),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester, String id) async {
  final finder = _key('ribbon-menu-word-layout-$id');
  await _exposeRibbon(tester, finder);
  await tester.tap(finder);
  await _frames(tester);
}

Future<void> _menu(WidgetTester tester, String id, String label) async {
  await _openMenu(tester, id);
  final choice = find.widgetWithText(MenuItemButton, label);
  expect(choice, findsOneWidget);
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await _frames(tester);
}

Future<void> _pageLayout(
  WidgetTester tester, {
  String label = 'Page Layout…',
}) async {
  final finder = _command(label);
  await _exposeRibbon(tester, finder);
  await tester.tap(finder);
  await _frames(tester);
  expect(_key('studio-page-layout-dialog'), findsOneWidget);
}

Future<void> _undo(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Undo'));
  await _frames(tester);
}

Future<void> _closeSettings(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await _frames(tester);
}

void _expectDark(WidgetTester tester, Finder finder) {
  final theme = Theme.of(tester.element(finder));
  expect(theme.brightness, Brightness.dark);
  expect(theme.colorScheme.surface.computeLuminance(), lessThan(0.15));
  expect(theme.colorScheme.onSurface.computeLuminance(), greaterThan(0.6));
}

void main() {
  testWidgets('Layout dropdown commands apply and Undo restores each setting', (
    tester,
  ) async {
    final word = await _studio(tester);
    final originalWidth = word.pageSize.width;
    final originalHeight = word.pageSize.height;
    await _tab(tester, 'layout');
    expect(find.widgetWithText(MenuItemButton, 'Narrow'), findsNothing);

    await _menu(tester, 'margins', 'Narrow');
    expect(word.pageMargins.matches(WmlPageMargins.narrow), isTrue);
    expect(
      tester
          .widget<StudioCommandMenu>(_key('ribbon-menu-word-layout-margins'))
          .currentValue,
      'Narrow',
    );
    await _undo(tester);
    expect(word.pageMargins.matches(WmlPageMargins.normal), isTrue);

    await _menu(tester, 'orientation', 'Landscape');
    expect(word.pageSize.isLandscape, isTrue);
    await _undo(tester);
    expect(word.pageSize.width, originalWidth);
    expect(word.pageSize.height, originalHeight);

    await _menu(tester, 'size', 'Legal');
    expect(word.pageSize.portrait.matches(WmlPageSize.legal()), isTrue);
    await _undo(tester);
    expect(word.pageSize.width, originalWidth);
    expect(word.pageSize.height, originalHeight);

    await _menu(tester, 'columns', 'Four');
    expect(word.sectionAtCaret.columnCount, 4);
    await _undo(tester);
    expect(word.sectionAtCaret.columnCount, 1);
    expect(word.document.paragraphs.single.text, 'Keep this paragraph.');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'Page Layout and Paragraph dialogs are reachable from the ribbon',
    (tester) async {
      final word = await _studio(tester);
      await _tab(tester, 'layout');
      await _pageLayout(tester);
      expect(_key('page-layout-left'), findsOneWidget);
      await tester.tap(_key('page-layout-cancel'));
      await _frames(tester);

      await _tab(tester, 'home');
      final paragraph = find.byTooltip('Paragraph…');
      await _exposeRibbon(tester, paragraph);
      await tester.tap(paragraph);
      await _frames(tester);
      expect(_key('studio-paragraph-dialog'), findsOneWidget);
      await tester.tap(_key('paragraph-cancel'));
      await _frames(tester);

      await _tab(tester, 'layout');
      await _menu(tester, 'paragraph', 'Paragraph…');
      expect(_key('studio-paragraph-dialog'), findsOneWidget);
      await tester.tap(_key('paragraph-cancel'));
      await _frames(tester);
      expect(word.canUndo, isFalse);
      expect(word.document.paragraphs.single.text, 'Keep this paragraph.');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'Document mode explains restrictions and disables layout editing',
    (tester) async {
      final word = await _studio(tester);
      for (final mode in <OfficeInteractionMode>[
        OfficeInteractionMode.selecting,
        OfficeInteractionMode.viewing,
      ]) {
        await selectStudioDocumentMode(tester, mode);
        expect(word.config.mode, mode);
        expect(word.config.allowsMutation, isFalse);
        expect(
          word.config.allowsSelection,
          mode == OfficeInteractionMode.selecting,
        );
        await _tab(tester, 'layout');
        final margins = _key('ribbon-menu-word-layout-margins');
        await _exposeRibbon(tester, margins);
        expect(
          tester
              .widget<StudioCommandMenu>(margins)
              .commands
              .every((command) => command.onPressed == null),
          isTrue,
        );
        expect(
          tester.widget<StudioCmd>(_command('Page Layout…')).onPressed,
          isNull,
        );
        await tester.tap(margins);
        await _frames(tester);
        expect(find.widgetWithText(MenuItemButton, 'Narrow'), findsNothing);
        expect(_key('studio-page-layout-dialog'), findsNothing);
      }
      await selectStudioDocumentMode(tester, OfficeInteractionMode.editing);
      expect(word.config.allowsMutation, isTrue);
      await _tab(tester, 'layout');
      expect(
        tester.widget<StudioCmd>(_command('Page Layout…')).onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Settings'));
      await _frames(tester);
      expect(
        find.byType(DropdownButtonFormField<OfficeInteractionMode>),
        findsNothing,
      );
      expect(find.byType(DropdownButtonFormField<SuiteLook>), findsOneWidget);
      await _closeSettings(tester);
      expect(word.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'Dark appearance updates the open Settings dialog and later routes',
    (tester) async {
      final word = await _studio(tester);
      await tester.tap(find.byTooltip('Settings'));
      await _frames(tester);
      final appearance = find.byType(DropdownButtonFormField<SuiteLook>);
      await tester.ensureVisible(appearance);
      await tester.tap(appearance);
      await _frames(tester);
      await tester.tap(find.text('Dark').last);
      await _frames(tester);
      _expectDark(tester, find.byType(AlertDialog));
      expect(word.config.theme.adaptDocumentColors, isTrue);
      await _closeSettings(tester);

      await _tab(tester, 'layout');
      await _pageLayout(tester);
      _expectDark(tester, _key('studio-page-layout-dialog'));
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: _key('page-layout-left'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.style.color!.computeLuminance(), greaterThan(0.6));
      await tester.tap(_key('page-layout-cancel'));
      await _frames(tester);

      await _openMenu(tester, 'margins');
      final normal = find.widgetWithText(MenuItemButton, 'Normal');
      _expectDark(tester, normal);
      final label = find.descendant(of: normal, matching: find.text('Normal'));
      final rich = tester.widget<RichText>(
        find.descendant(of: label, matching: find.byType(RichText)),
      );
      expect(rich.text.style!.color!.computeLuminance(), greaterThan(0.6));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);
      expect(find.widgetWithText(MenuItemButton, 'Normal'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'narrow Arabic Layout menus and dialog stay reachable at 160 percent',
    (tester) async {
      final word = await _studio(
        tester,
        size: const Size(520, 900),
        textScale: 1.6,
      );
      await configureStudioForTest(tester, language: StudioLanguage.ar);
      await _tab(tester, 'layout');
      await _menu(tester, 'margins', 'ضيق');
      expect(word.pageMargins.matches(WmlPageMargins.narrow), isTrue);
      await _pageLayout(tester, label: 'تخطيط الصفحة…');
      expect(
        Directionality.of(tester.element(_key('studio-page-layout-dialog'))),
        TextDirection.rtl,
      );
      await tester.tap(_key('page-layout-cancel'));
      await _frames(tester);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
