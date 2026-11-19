import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_ribbon_preferences.dart';
import 'package:quds_office_studio/suite_workspace.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _menuKey(String id) => _key('ribbon-menu-$id');

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _studio(WidgetTester tester) async {
  final preferences = StudioRibbonPreferences(persist: false);
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    preferences.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Liberation Sans'),
      home: SuiteWorkspace(ribbonPreferences: preferences),
    ),
  );
  await tester.pump();
  final word = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  word.proofing.enabled = false;
  word.proofing.configure(OfficeProofingService(providers: []));
  await _frames(tester);
}

Future<void> _tab(WidgetTester tester, String tab) async {
  final finder = _key('ribbon-tab-$tab');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _frames(tester);
}

Future<void> _openMenu(WidgetTester tester, String id) async {
  final finder = _menuKey(id);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _frames(tester);
}

Future<void> _choose(WidgetTester tester, String id, String label) async {
  await _openMenu(tester, id);
  final item = find.widgetWithText(MenuItemButton, label);
  await tester.ensureVisible(item);
  await tester.tap(item);
  await _frames(tester);
}

void _expectSelected(WidgetTester tester, String label) {
  final item = tester.widget<MenuItemButton>(
    find.widgetWithText(MenuItemButton, label),
  );
  expect(item.trailingIcon, isA<Icon>());
  expect((item.trailingIcon! as Icon).icon, Icons.check);
}

Future<void> _expectDisabled(WidgetTester tester, String id) async {
  final finder = _menuKey(id);
  final menu = tester.widget<StudioCommandMenu>(finder);
  expect(menu.commands, isNotEmpty);
  expect(menu.commands.every((command) => command.onPressed == null), isTrue);
  final trigger = find.descendant(of: finder, matching: find.byType(StudioCmd));
  expect(tester.widget<StudioCmd>(trigger).onPressed, isNull);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _frames(tester);
  expect(find.byType(MenuItemButton), findsNothing);
}

void main() {
  testWidgets('the Function menu inserts SUM in the selected worksheet cell', (
    tester,
  ) async {
    await _studio(tester);
    final word = tester
        .widget<QudsWordEditor>(find.byType(QudsWordEditor))
        .controller;
    final wordText = word.document.paragraphs
        .map((paragraph) => paragraph.text)
        .toList();
    await tester.tap(find.byTooltip('Spreadsheets'));
    await _frames(tester);
    final sheet = tester
        .widget<QudsSheetEditor>(find.byType(QudsSheetEditor))
        .controller;
    sheet.sheet.cellA1('A1')
      ..formula = null
      ..type = SmlCellType.number
      ..value = 2;
    sheet.sheet.cellA1('B1')
      ..formula = null
      ..type = SmlCellType.number
      ..value = 3;
    final original = sheet.sheet.cellA1('C1').value;
    sheet.selection.selectCell(const SmlCellRef(2, 0));
    sheet.refresh();
    await _tab(tester, 'formulas');
    await _openMenu(tester, 'excel-formulas-function');
    expect(find.widgetWithText(MenuItemButton, 'SUM'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(sheet.sheet.cellA1('C1').value, original);

    await _choose(tester, 'excel-formulas-function', 'SUM');
    expect(sheet.sheet.cellA1('C1').formula, '=SUM(A1:B1)');
    expect(sheet.sheet.cellA1('C1').value, 5);
    expect(sheet.isDirty, isTrue);
    expect(
      word.document.paragraphs.map((paragraph) => paragraph.text).toList(),
      wordText,
    );
    sheet.undo();
    await _frames(tester);
    expect(sheet.sheet.cellA1('C1').formula, isNull);
    expect(sheet.sheet.cellA1('C1').value, original);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('slide menus select exact effects, durations and advance times', (
    tester,
  ) async {
    await _studio(tester);
    await tester.tap(find.byTooltip('Presentations'));
    await _frames(tester);
    final slides = tester
        .widget<QudsSlideEditor>(find.byType(QudsSlideEditor))
        .controller;
    await _tab(tester, 'transitions');
    final original = slides.slide.transition.kind;
    await _openMenu(tester, 'powerpoint-transitions-effect');
    _expectSelected(
      tester,
      PmlMotionCatalog.transitionLabel(original, arabic: false),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(slides.slide.transition.kind, original);
    await _choose(tester, 'powerpoint-transitions-effect', 'Push');
    expect(slides.slide.transition.kind, PmlTransitionKind.push);
    // Effect selection previews the transition; Escape returns to editing.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    expect(slides.isPlayingMotion, isFalse);

    for (final choice in <(String, int)>[
      ('0.35 s', 350),
      ('0.7 s', 700),
      ('1.2 s', 1200),
    ]) {
      await _choose(tester, 'slides-transition-duration', choice.$1);
      expect(slides.slide.transition.durationMs, choice.$2);
      expect(find.byTooltip('Duration: ${choice.$1}'), findsOneWidget);
      await _openMenu(tester, 'slides-transition-duration');
      _expectSelected(tester, choice.$1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _frames(tester);
      expect(slides.slide.transition.durationMs, choice.$2);
    }
    await _choose(tester, 'slides-transition-advance', 'After 2 s');
    expect(slides.slide.transition.advanceAfterMs, 2000);
    expect(find.byTooltip('Advance slide: After 2 s'), findsOneWidget);
    await _choose(tester, 'slides-transition-advance', 'Manually');
    expect(slides.slide.transition.advanceAfterMs, isNull);
    expect(find.byTooltip('Advance slide: Manually'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('File Document mode disables sheet and slide editing menus', (
    tester,
  ) async {
    await _studio(tester);
    await tester.tap(find.byTooltip('Spreadsheets'));
    await _frames(tester);
    final sheet = tester
        .widget<QudsSheetEditor>(find.byType(QudsSheetEditor))
        .controller;
    final cell = sheet.sheet.cellA1('A1');
    final originalValue = cell.value;
    await _tab(tester, 'file');
    await _choose(tester, 'document-mode', 'Read and copy');
    expect(sheet.config.allowsMutation, isFalse);
    await _tab(tester, 'formulas');
    await _expectDisabled(tester, 'excel-formulas-function');
    expect(cell.value, originalValue);

    await tester.tap(find.byTooltip('Presentations'));
    await _frames(tester);
    final slides = tester
        .widget<QudsSlideEditor>(find.byType(QudsSlideEditor))
        .controller;
    final transition = slides.slide.transition;
    await _tab(tester, 'file');
    await _choose(tester, 'document-mode', 'Preview only');
    expect(slides.config.allowsMutation, isFalse);
    await _tab(tester, 'transitions');
    for (final id in <String>[
      'powerpoint-transitions-effect',
      'slides-transition-duration',
      'slides-transition-advance',
    ]) {
      await _expectDisabled(tester, id);
    }
    expect(slides.slide.transition, same(transition));

    await _tab(tester, 'file');
    await _choose(tester, 'document-mode', 'Edit document');
    await _tab(tester, 'transitions');
    expect(slides.config.allowsMutation, isTrue);
    final duration = tester.widget<StudioCommandMenu>(
      _menuKey('slides-transition-duration'),
    );
    expect(
      duration.commands.every((command) => command.onPressed != null),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
