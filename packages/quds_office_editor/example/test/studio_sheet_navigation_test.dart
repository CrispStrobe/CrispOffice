import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_find_pane.dart';

const _error = 'Correct the current cell before continuing.';

SheetEditorController _controller() {
  final controller = SheetEditorController(
    workbook: SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Budget', sheetId: 1)
          ..cellA1('A1').value = 5
          ..cellA1('B2').value = 'Needle first',
        SmlWorksheet(name: 'Summary', sheetId: 2)
          ..cellA1('B2').value = 'Needle second',
      ],
    ),
    config: const OfficeSurfaceConfig(autofocus: false),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _type(SheetEditorController controller, String text) {
  controller.cellEditor.bridge.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
}

void _rejectDraft(SheetEditorController controller) {
  controller.selection.selectCell(const SmlCellRef(0, 0));
  controller.sheet.cellA1('A1')
    ..formula = null
    ..value = 5
    ..type = SmlCellType.number;
  controller.sheet.validations.add(
    SmlDataValidation(
      range: SmlRange.parse('A1'),
      kind: SmlValidationKind.whole,
      formula1: '1',
      formula2: '10',
    ),
  );
  controller.beginCellEdit();
  _type(controller, 'invalid');
}

Future<void> _pane(
  WidgetTester tester,
  SheetEditorController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StudioFindPane(
          controller: controller,
          arabic: false,
          accent: Colors.green,
          replaceMode: false,
          onReplaceMode: (_) {},
          onClose: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<SheetEditorController> _studio(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const QudsOfficeStudioApp());
  await tester.pump();
  // Worksheet navigation does not exercise the background Word proofreader.
  // Keep its asynchronous provider timeouts out of these focused UI tests.
  final word = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
  word.controller.proofing.enabled = false;
  word.controller.proofing.configure(OfficeProofingService(providers: []));
  expect(find.byTooltip('Language'), findsOneWidget);
  await tester.pump();
  await tester.tap(find.byTooltip('Spreadsheets').first);
  await tester.pump();
  final editor = tester.widget<QudsSheetEditor>(find.byType(QudsSheetEditor));
  // Embedded input rejects synthetic updates until its editor owns focus.
  editor.focusNode!.requestFocus();
  await tester.pump();
  expect(editor.focusNode!.hasPrimaryFocus, isTrue);
  return editor.controller;
}

void main() {
  group('the font ribbon', () {
    const extraFamily = 'A Demo Typeface';
    const nativeFamily = 'American Typewriter';

    setUpAll(() async {
      final font = await rootBundle.load(
        'packages/quds_office_editor/fonts/LiberationMono-Regular.ttf',
      );
      await OfficeHostFonts.registerFamily(
        family: extraFamily,
        faces: [font],
        aliases: ['Demo Typeface Alias'],
      );
      OfficeHostFonts.addPlatformFamilies([nativeFamily]);
    });

    testWidgets('offers registered faces in Documents and Spreadsheets', (
      tester,
    ) async {
      final sheet = await _studio(tester);
      final combo = find.byWidgetPredicate(
        (widget) =>
            widget is StudioCombo<String> &&
            widget.items.contains('Liberation Mono'),
      );
      final sheetFonts = tester.widget<StudioCombo<String>>(combo);
      expect(sheetFonts.items, containsAll([extraFamily, nativeFamily]));
      expect(sheetFonts.items, isNot(contains('Demo Typeface Alias')));
      await tester.tap(combo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final search = find.widgetWithText(TextField, 'Search fonts');
      await tester.enterText(search, 'unavailable typeface');
      await tester.pump();
      expect(find.text('No matching fonts'), findsOneWidget);
      await tester.enterText(search, 'typewriter');
      await tester.pump();
      expect(find.text(extraFamily), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(sheet.sheet.cell(sheet.activeCell).fontFamily, nativeFamily);
      expect(
        PaintRunText.familyFor(text: 'Example', runFamily: nativeFamily),
        nativeFamily,
      );

      await tester.tap(find.byTooltip('Documents').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final wordFonts = tester.widget<StudioCombo<String>>(combo);
      expect(
        wordFonts.items,
        containsAll(['Aptos', extraFamily, nativeFamily]),
      );
      await tester.tap(combo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text(extraFamily));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final word = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
      expect(word.controller.activeRunProps.asciiFont, extraFamily);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('Cmd+W closes only the active file after the save guard', (
    tester,
  ) async {
    final controller = await _studio(tester);
    final cell = controller.activeCell;
    controller.beginCellEdit();
    _type(controller, 'test draft');

    Future<void> closeWithKeyboard() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    final closed = find.byKey(const ValueKey<String>('studio-closed-file'));
    await closeWithKeyboard();
    expect(find.text('Save changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.sheet.cell(cell).asString, 'test draft');
    expect(closed, findsNothing);

    await closeWithKeyboard();
    await tester.tap(find.text('Don’t Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(closed, findsOneWidget);
    expect(find.byType(QudsSheetEditor), findsNothing);

    await tester.tap(find.byTooltip('Documents').first);
    await tester.pump();
    expect(find.byType(QudsWordEditor), findsOneWidget);
    await tester.tap(find.byTooltip('Spreadsheets').first);
    await tester.pump();
    expect(closed, findsOneWidget);

    await tester.tap(find.descendant(of: closed, matching: find.text('New')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QudsSheetEditor), findsOneWidget);
    expect(controller.sheet.cell(cell).asString, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('the spreadsheet fx bar edits the active cell as a text field', (
    tester,
  ) async {
    final controller = await _studio(tester);
    final bar = find.byKey(const ValueKey<String>('sheet-formula-input'));
    expect(bar, findsOneWidget);
    expect(find.text('fx'), findsOneWidget);
    final cell = controller.activeCell;

    await tester.tap(bar);
    await tester.pump();
    final field = tester.widget<EditableText>(bar);
    expect(field.focusNode.hasPrimaryFocus, isTrue);
    tester.testTextInput.enterText('42');
    await tester.pump();
    expect(controller.formulaBarText, '42');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.sheet.cell(cell).asString, '42');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'find pane retains a rejected first search and shows correction',
    (tester) async {
      final controller = _controller();
      await _pane(tester, controller);
      _rejectDraft(controller);
      await tester.enterText(find.byType(TextField).first, 'Needle');
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.text(_error), findsOneWidget);
      expect(controller.findSession.hits, isEmpty);
      expect(controller.findSession.index, -1);
      expect(controller.activeSheetIndex, 0);
      expect(controller.formulaBarText, 'invalid');
      controller.cancelCellEdit();
      await tester.pump();
      expect(find.text(_error), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('result click changes its cursor only after draft acceptance', (
    tester,
  ) async {
    final controller = _controller();
    controller.find(const OfficeFindOptions(query: 'Needle'));
    await _pane(tester, controller);
    _rejectDraft(controller);
    final revision = controller.contentRevision;
    await tester.tap(find.text('Summary!B2'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(_error), findsOneWidget);
    expect(controller.findSession.index, 0);
    expect(controller.activeSheetIndex, 0);
    expect(controller.selection.focus.a1, 'A1');
    expect(controller.formulaBarText, 'invalid');
    expect(controller.contentRevision, revision);
    _type(controller, '8');
    await tester.tap(find.text('Summary!B2'));
    await tester.pump();
    expect(controller.activeSheetIndex, 1);
    expect(controller.selection.focus.a1, 'B2');
    expect(controller.findSession.index, 1);
    expect(controller.workbook.firstSheet.cellA1('A1').value, 8);
    expect(find.text(_error), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final action in ['Next', 'Previous', 'F3']) {
    testWidgets('find pane $action handles rejected navigation', (
      tester,
    ) async {
      final controller = _controller();
      controller.find(const OfficeFindOptions(query: 'Needle'));
      await _pane(tester, controller);
      _rejectDraft(controller);
      if (action == 'F3') {
        await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      } else {
        await tester.tap(find.text(action));
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(_error), findsOneWidget);
      expect(controller.findSession.index, 0);
      expect(controller.activeSheetIndex, 0);
      expect(controller.cellEditor.editing, isTrue);
      expect(controller.formulaBarText, 'invalid');
      if (action == 'Next') {
        await tester.enterText(find.byType(TextField).first, 'second');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('More >>'));
        await tester.pump();
        await tester.tap(find.text('Match case'));
        await tester.pump();
        expect(controller.findSession.options!.query, 'Needle');
        expect(controller.findSession.options!.matchCase, isFalse);
        _type(controller, '8');
        await tester.tap(find.text('Next'));
        await tester.pump();
        expect(controller.findSession.options!.query, 'second');
        expect(controller.findSession.options!.matchCase, isTrue);
        expect(controller.findSession.hits, hasLength(1));
        expect(controller.findSession.index, 0);
        expect(controller.activeSheetIndex, 1);
        expect(find.text(_error), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('studio worksheet tab keeps a rejected draft available', (
    tester,
  ) async {
    final controller = await _studio(tester);
    _rejectDraft(controller);
    expect(controller.formulaBarText, 'invalid');
    final before = controller.contentRevision;
    await tester.tap(find.text('Roster').last);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(_error), findsOneWidget);
    expect(controller.activeSheetIndex, 0);
    expect(controller.cellEditor.editing, isTrue);
    expect(controller.formulaBarText, 'invalid');
    expect(controller.contentRevision, before);
    _type(controller, '7');
    await tester.tap(find.text('Roster').last);
    await tester.pump();
    expect(controller.sheet.name, 'Roster');
    expect(controller.workbook.firstSheet.cellA1('A1').value, 7);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final command in ['New', 'Reload sample']) {
    testWidgets('studio $command explicitly resets a same-index worksheet', (
      tester,
    ) async {
      final controller = await _studio(tester);
      final previous = controller.workbook;
      controller.selection.selectCell(const SmlCellRef(2, 3));
      controller.beginCellEdit();
      _type(controller, 'draft to discard');
      controller.viewport.origin = const Offset(70, 80);
      await tester.tap(find.byKey(const ValueKey('ribbon-tab-file')));
      await tester.pump();
      await tester.tap(find.byTooltip(command));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Save changes?'), findsOneWidget);
      expect(controller.workbook, same(previous));
      await tester.tap(find.widgetWithText(TextButton, 'Don’t Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.workbook, isNot(same(previous)));
      expect(controller.activeSheetIndex, 0);
      expect(controller.selection.focus.a1, 'A1');
      expect(controller.cellEditor.editing, isFalse);
      expect(controller.viewport.origin, Offset.zero);
      expect(controller.selectedDrawingIndex, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
