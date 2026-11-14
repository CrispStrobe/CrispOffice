// Prepared for Phase B; not included in the Phase A test command.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SheetEditorController _controller() {
  final first = SmlWorksheet(name: 'Original', sheetId: 1)
    ..cellA1('A1').value = 'Original';
  final second = SmlWorksheet(name: 'Neighbor', sheetId: 2)
    ..cellA1('A1').value = 'Neighbor';
  final controller = SheetEditorController(
    workbook: SmlWorkbook(sheets: [first, second]),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'grid history cannot replace a different worksheet after a tab change',
    () {
      final controller = _controller();
      final owner = controller.sheet;
      final neighbor = controller.workbook.sheets[1];
      controller.setSelectionFillRgb('FF0000');
      controller.setActiveSheet(1);
      controller.undo();
      expect(neighbor.cellA1('A1').value, 'Neighbor');
      expect(neighbor.cellA1('A1').fillRgb, isEmpty);
      expect(owner.cellA1('A1').fillRgb, isEmpty);
      controller.redo();
      expect(owner.cellA1('A1').fillRgb, 'FF0000');
      expect(neighbor.cellA1('A1').value, 'Neighbor');
      expect(neighbor.cellA1('A1').fillRgb, isEmpty);
    },
  );

  test('grid redo retains its original range after selection changes', () {
    final controller = _controller();
    controller.setSelectionFillRgb('FF0000');
    controller.undo();
    controller.selection.selectCell(const SmlCellRef(1, 0));
    controller.redo();
    expect(controller.sheet.cellA1('A1').fillRgb, 'FF0000');
    expect(controller.sheet.cellA1('B1').fillRgb, isEmpty);
  });

  test(
    'grid restoration leaves an earlier cell command attached to the grid',
    () {
      final controller = _controller();
      controller.beginCellEdit();
      controller.cellEditor.bridge.updateEditingValue(
        const TextEditingValue(
          text: 'Edited',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      controller.commitPendingEdits();
      controller.setSelectionFillRgb('FF0000');
      controller.undo();
      controller.undo();
      expect(controller.sheet.cellA1('A1').value, 'Original');
      controller.redo();
      controller.redo();
      expect(controller.sheet.cellA1('A1').value, 'Edited');
      expect(controller.sheet.cellA1('A1').fillRgb, 'FF0000');
    },
  );
}
