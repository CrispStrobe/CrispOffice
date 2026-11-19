import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
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
  expect(find.byTooltip('Language'), findsOneWidget);
  await tester.pump();
  await tester.tap(find.text('Spreadsheets').first);
  await tester.pump();
  final editor = tester.widget<QudsSheetEditor>(find.byType(QudsSheetEditor));
  // Embedded input rejects synthetic updates until its editor owns focus.
  editor.focusNode!.requestFocus();
  await tester.pump();
  expect(editor.focusNode!.hasPrimaryFocus, isTrue);
  return editor.controller;
}

void main() {
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
      await tester.tap(find.text('File').first);
      await tester.pump();
      await tester.tap(find.text(command));
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
