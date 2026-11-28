import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// A cell xf may introduce a custom number format id. The serializer must
/// write that id's `<numFmt>` entry, otherwise strict readers (openpyxl,
/// Open XML SDK) index past the end of `<numFmts>` and reject the package.
void main() {
  test('localizes a canonical XLSX format without changing its pattern', () {
    final styles = SmlStyleSheet(
      numFmts: {164: r'#,##0.00\ "€"'},
      cellXfsNumFmt: [164],
    );
    expect(styles.format(1234.5, 0), '1,234.50 €');
    expect(styles.format(1234.5, 0, locale: 'de_DE'), '1.234,50 €');
    expect(styles.format(-1234.5, 0, locale: 'de_DE'), '-1.234,50 €');
  });

  test(
    'localizes the built-in short date while preserving authored patterns',
    () {
      final styles = SmlStyleSheet(cellXfsNumFmt: [14, 164, 165]);
      styles.numFmts[164] = 'yyyy-mm-dd';
      styles.numFmts[165] = 'mm-dd-yy';
      expect(styles.format(45084, 0, locale: 'de_DE'), '07.06.23');
      expect(styles.format(45084.75, 0, locale: 'de_DE'), '07.06.23');
      expect(styles.format(45084, 0, locale: 'en_US'), '6/7/23');
      expect(styles.format(45084, 0, locale: 'fr_FR'), '07/06/2023');
      expect(styles.format(45084, 0), '06-07-23');
      expect(styles.format(45084, 1, locale: 'de_DE'), '2023-06-07');
      expect(styles.format(45084, 2, locale: 'de_DE'), '06-07-23');
      expect(styles.format('45084', 0, locale: 'de_DE'), '45084');
    },
  );

  test('cell formats use the workbook date system and Excel early dates', () {
    final styles = SmlStyleSheet(cellXfsNumFmt: [14, 164]);
    styles.numFmts[164] = 'yyyy-mm-dd hh:mm';
    expect(styles.format(0, 0, locale: 'de_DE'), '00.01.00');
    expect(styles.format(0.75, 0, locale: 'en_US'), '1/0/00');
    expect(styles.format(1, 0, locale: 'de_DE'), '01.01.00');
    expect(styles.format(59, 0, locale: 'de_DE'), '28.02.00');
    expect(styles.format(60, 0, locale: 'de_DE'), '29.02.00');
    expect(styles.format(61, 0, locale: 'de_DE'), '01.03.00');
    expect(styles.format(0.75, 1), '1900-01-00 18:00');
    expect(styles.format(60, 1), '1900-02-29 00:00');
    expect(
      styles.format(0, 0, locale: 'de_DE', uses1904Dates: true),
      '01.01.04',
    );
    expect(styles.format(0.75, 1, uses1904Dates: true), '1904-01-01 18:00');
    expect(applyNumberFormat(1.5, '[h]:mm', uses1904Dates: true), '36:00');
  });

  test('localizes General numbers without formatting text as numbers', () {
    final styles = SmlStyleSheet();
    expect(styles.format(3489.75, 0, locale: 'de_DE'), '3489,75');
    expect(styles.format(3489.75, 0, locale: 'en_US'), '3489.75');
    expect(styles.format(1.23e-7, 0, locale: 'de_DE'), '1,23e-7');
    expect(styles.format(3489, 0, locale: 'de_DE'), '3489');
    expect(styles.format('3489.75', 0, locale: 'de_DE'), '3489.75');
  });

  test('General display suppresses floating-point artifacts', () {
    final styles = SmlStyleSheet();
    final total = 3898.19 + 357;
    expect(styles.format(total, 0, locale: 'de_DE'), '4255,19');
    expect(styles.format(total, 0, locale: 'en_US'), '4255.19');
    expect(styles.format(1.234567890123456, 0), '1.23456789012346');
    expect(styles.format(123456789012345.0, 0), '123456789012345');
    expect(styles.format(-0.0, 0), '0');
  });

  test('an authored custom number format is written and reloads', () async {
    final book = SmlWorkbook(
      sheets: [SmlWorksheet(name: 'Sheet1', sheetId: 1)],
    );
    final sheet = book.firstSheet;
    final cell = sheet.cellA1('A1')..value = 1234.5;
    final styles = book.styles ??= SmlStyleSheet();
    while (styles.cellXfsAlign.length < 2) {
      styles.cellXfsNumFmt.add(0);
      styles.cellXfsAlign.add(SmlHAlign.general);
      styles.cellXfsFillId.add(0);
      styles.cellXfsFontId.add(0);
    }
    styles.numFmts[170] = '#,##0.00 "EUR"';
    styles.cellXfsNumFmt.add(170);
    styles.cellXfsAlign.add(SmlHAlign.general);
    styles.cellXfsFillId.add(0);
    styles.cellXfsFontId.add(0);
    cell
      ..styleIndex = styles.cellXfsNumFmt.length - 1
      ..hasExplicitStyleIndex = true;

    final bytes = await OfficeIsolateSave.workbook(book, recalculate: false);
    final text = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/styles.xml')!.readText();
    expect(text, contains('numFmtId="170"'));
    expect(text, contains('#,##0.00'));
    expect(text, contains(r'&quot;EUR&quot;'));
    expect(text.indexOf('<numFmts'), lessThan(text.indexOf('<fonts')));

    final reopened = SheetDeserializer().readBytes(bytes);
    expect(reopened.styles!.numFmts[170], '#,##0.00 "EUR"');
    expect(reopened.firstSheet.cellA1('A1').styleIndex, 2);
  });

  test('authored formats merge with a native numFmts collection', () async {
    final book = SheetDeserializer().readBytes(
      File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
    );
    final styles = book.styles ??= SmlStyleSheet();
    styles.numFmts[200] = '0.0000';
    styles.cellXfsNumFmt.add(200);
    styles.cellXfsAlign.add(SmlHAlign.general);
    styles.cellXfsFillId.add(0);
    styles.cellXfsFontId.add(0);

    final bytes = await OfficeIsolateSave.workbook(book, recalculate: false);
    final text = OpcPackage.openBytes(
      bytes,
    ).getPart('/xl/styles.xml')!.readText();
    expect(text, contains('numFmtId="200"'));
    final reopened = SheetDeserializer().readBytes(bytes);
    expect(reopened.styles!.numFmts[200], '0.0000');
    expect(reopened.styles!.numFmts.length, greaterThan(1));
  });
}
