import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('relative expression rules follow the range anchor', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A2').value = 2;
    sheet.cellA1('A3').value = 9;
    final rule = SmlConditionalRule(
      range: SmlRange.parse('B2:B3'),
      kind: SmlConditionalKind.expression,
      formula: 'A2>5',
    );
    expect(rule.matches(sheet.cellA1('B2'), sheet), isFalse);
    expect(rule.matches(sheet.cellA1('B3'), sheet), isTrue);
  });

  test('numeric bounds can reference an absolute source cell', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1').value = 8;
    sheet.cellA1('D1').value = 5;
    final rule = SmlConditionalRule(
      range: SmlRange.parse('A1:A2'),
      kind: SmlConditionalKind.greaterThan,
      formula: r'$D$1',
    );
    expect(rule.matches(sheet.cellA1('A1'), sheet), isTrue);
  });

  test('worksheet PDF uses conditional fill and font colors', () {
    final book = SmlWorkbook();
    final sheet = book.sheets.single;
    sheet.cellA1('A1').value = 8;
    sheet.conditionalFormats.add(SmlConditionalRule(
      range: SmlRange.parse('A1'),
      kind: SmlConditionalKind.greaterThan,
      formula: '5',
      fillRgb: '123456',
      fontRgb: 'ABCDEF',
    ));
    final display = PdfFile.open(OfficePdfExport.workbook(book)).displayList(0);
    expect(display.ops.whereType<PdfFillPath>().map((op) => op.color),
        contains(0xff123456));
    expect(display.ops.whereType<PdfDrawText>()
        .where((op) => op.text == '8').map((op) => op.color),
        everyElement(0xffabcdef));
  });

  test('worksheet PDF colors blank cells in the selected print area', () {
    final book = SmlWorkbook();
    final sheet = book.sheets.single;
    sheet.printArea = SmlRange.parse('A1:B2');
    sheet.cellA1('A1').value = 'anchor';
    sheet.conditionalFormats.add(SmlConditionalRule(
      range: SmlRange.parse('B2'),
      kind: SmlConditionalKind.expression,
      formula: 'TRUE',
      fillRgb: '12AB34',
    ));
    final display = PdfFile.open(OfficePdfExport.workbook(book)).displayList(0);
    expect(display.ops.whereType<PdfFillPath>().map((op) => op.color),
        contains(0xff12ab34));
    expect(sheet.cellOrNull(SmlCellRef.parse('B2')), isNull);
  });
}
