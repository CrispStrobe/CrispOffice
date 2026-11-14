import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rejected pending input blocks sorting and retains its owning cell', () {
    final book = SmlWorkbook();
    final sheet = book.firstSheet;
    sheet.cellA1('A1').value = 'Header';
    sheet.cellA1('A2').value = 2;
    sheet.cellA1('A3').value = 1;
    sheet.validations.add(
      SmlDataValidation(
        range: SmlRange.parse('A2'),
        kind: SmlValidationKind.whole,
        formula1: '0',
        formula2: '10',
      ),
    );
    final controller = SheetEditorController(workbook: book);
    addTearDown(controller.dispose);
    controller.selection.selectCell(const SmlCellRef(0, 1));
    controller.beginCellEdit(initial: '99', replace: true);
    controller.selection
      ..anchor = const SmlCellRef(0, 0)
      ..focus = const SmlCellRef(0, 2);
    final revision = controller.contentRevision;
    expect(controller.commands.canUndo, isFalse);

    expect(controller.sortSelection, throwsStateError);
    expect(controller.contentRevision, revision);
    expect(controller.commands.canUndo, isFalse);
    expect(controller.cellEditor.editing, isTrue);
    expect(controller.cellEditor.formulaBar, '99');
    expect(controller.isDirty, isTrue);
    expect(controller.lastValidationError, isNotNull);
    expect(sheet.cellA1('A1').value, 'Header');
    expect(sheet.cellA1('A2').value, 2);
    expect(sheet.cellA1('A3').value, 1);

    controller.cellEditor.bridge.updateEditingValue(
      const TextEditingValue(
        text: '5',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    controller.commitPendingEdits();
    expect(sheet.cellA1('A1').value, 'Header');
    expect(sheet.cellA1('A2').value, 5);
    expect(sheet.cellA1('A3').value, 1);
  });
}
