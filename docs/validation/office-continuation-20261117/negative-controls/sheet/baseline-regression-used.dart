import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _sheetNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _worksheetUri = '/xl/worksheets/sheet2.xml';

void main() {
  group('edits to imported conditional rules persist', () {
    for (final entry in <String, SmlConditionalKind>{
      '': SmlConditionalKind.top,
      'bottom="1"': SmlConditionalKind.bottom,
      'percent="1"': SmlConditionalKind.topPercent,
      'bottom="1" percent="1"': SmlConditionalKind.bottomPercent,
    }.entries) {
      test('rank-only edit survives repeated ${entry.value.name} saves', () {
        var book = _native(
          '<cfRule type="top10" rank="3" priority="1" ${entry.key}/>',
        );
        final rule = book.sheets[1].conditionalFormats.single;
        expect(rule.kind, entry.value);
        expect(rule.rank, 3);
        rule.rank = 1;

        for (var cycle = 0; cycle < 2; cycle++) {
          final bytes = SheetSerializer().writeBytes(book, recalculate: false);
          final package = OpcPackage.openBytes(bytes);
          expect(_nativeRule(package).getAttribute('rank'), '1');
          book = SheetDeserializer().read(package);
          expect(book.sheets[1].conditionalFormats.single.kind, entry.value);
          expect(book.sheets[1].conditionalFormats.single.rank, 1);
        }
      });
    }

    for (final operator in ['between', 'notBetween']) {
      test('upper-bound-only $operator edit survives isolate save', () async {
        final book = _native(
          '<cfRule type="cellIs" operator="$operator" priority="1">'
          '<formula>1</formula><formula>3</formula></cfRule>',
        );
        final rule = book.sheets[1].conditionalFormats.single;
        expect(rule.formula, '1');
        expect(rule.formula2, '3');
        rule.formula2 = '2';

        final bytes = await OfficeIsolateSave.workbook(
          book,
          recalculate: false,
        );
        final package = OpcPackage.openBytes(bytes);
        expect(
          _nativeRule(
            package,
          ).childrenNamed('formula').map((node) => node.text),
          ['1', '2'],
        );
        final reopened = SheetDeserializer().read(package);
        expect(reopened.sheets[1].conditionalFormats.single.formula, '1');
        expect(reopened.sheets[1].conditionalFormats.single.formula2, '2');
      });
    }
  });

  group('SpreadsheetML boolean spellings', () {
    for (final entry in <String, SmlConditionalKind>{
      '': SmlConditionalKind.top,
      'bottom="0" percent="0"': SmlConditionalKind.top,
      'bottom="false" percent="false"': SmlConditionalKind.top,
      'bottom="1" percent="0"': SmlConditionalKind.bottom,
      'bottom="true" percent="false"': SmlConditionalKind.bottom,
      'bottom="0" percent="1"': SmlConditionalKind.topPercent,
      'bottom="false" percent="true"': SmlConditionalKind.topPercent,
      'bottom="1" percent="1"': SmlConditionalKind.bottomPercent,
      'bottom="true" percent="true"': SmlConditionalKind.bottomPercent,
    }.entries) {
      test('top10 ${entry.key.isEmpty ? 'defaults' : entry.key}', () {
        final book = _native(
          '<cfRule type="top10" rank="2" priority="1" ${entry.key}/>',
        );
        final rule = book.sheets[1].conditionalFormats.single;
        expect(rule.kind, entry.value);
        expect(rule.rank, 2);
      });
    }

    for (final entry in <String, SmlConditionalKind>{
      '': SmlConditionalKind.aboveAverage,
      'aboveAverage="1"': SmlConditionalKind.aboveAverage,
      'aboveAverage="true"': SmlConditionalKind.aboveAverage,
      'aboveAverage="0"': SmlConditionalKind.belowAverage,
      'aboveAverage="false"': SmlConditionalKind.belowAverage,
    }.entries) {
      test('aboveAverage ${entry.key.isEmpty ? 'default' : entry.key}', () {
        final book = _native(
          '<cfRule type="aboveAverage" priority="1" ${entry.key}/>',
        );
        expect(book.sheets[1].conditionalFormats.single.kind, entry.value);
      });
    }
  });

  group('conditional bounds follow reversible worksheet renames', () {
    for (final operator in ['between', 'notBetween']) {
      test('$operator keeps both modeled and native bounds through saves', () {
        final book = _native(
          '<cfRule type="cellIs" operator="$operator" priority="7" '
          'stopIfTrue="1"><formula>Data!A1</formula>'
          '<formula>Data!A2</formula></cfRule>',
        );
        final edit = SheetRename.prepare(book, book.firstSheet, "O'Brien");
        edit.apply();
        _expectRenamedBounds(book, "'O''Brien'!A1", "'O''Brien'!A2");
        edit.undo();
        _expectRenamedBounds(book, 'Data!A1', 'Data!A2');
        edit.apply();
        _expectRenamedBounds(book, "'O''Brien'!A1", "'O''Brien'!A2");
      });
    }

    test('a reference only in the upper bound follows the rename', () {
      final book = _native(
        '<cfRule type="cellIs" operator="between" priority="7" '
        'stopIfTrue="1"><formula>1</formula>'
        '<formula>Data!A2</formula></cfRule>',
      );
      SheetRename.rename(book, book.firstSheet, 'Next');
      _expectRenamedBounds(book, '1', "'Next'!A2");
    });

    for (final undo in [false, true]) {
      for (final property in ['rank', 'formula2']) {
        test('${undo ? 'undo' : 'apply'} rejects a newer $property edit', () {
          final book = _native(
            property == 'rank'
                ? '<cfRule type="top10" rank="3" priority="1"/>'
                : '<cfRule type="cellIs" operator="between" priority="1">'
                      '<formula>Data!A1</formula><formula>Data!A2</formula>'
                      '</cfRule>',
          );
          final edit = SheetRename.prepare(book, book.firstSheet, 'Next');
          if (undo) edit.apply();
          final rule = book.sheets[1].conditionalFormats.single;
          if (property == 'rank') {
            rule.rank = 1;
          } else {
            rule.formula2 = '99';
          }
          final before = _snapshot(book);

          expect(undo ? edit.undo : edit.apply, throwsStateError);
          expect(_snapshot(book), before);
        });
      }
    }
  });

  test('no-edit saves preserve native rule attributes and disjoint ranges', () {
    var book = _native(
      '<cfRule type="cellIs" operator="between" priority="7" '
      'stopIfTrue="1"><formula>Data!A1</formula>'
      '<formula>Data!A2</formula></cfRule>',
      sqref: 'A1:A3 C1:C3',
    );
    final original = _conditionalXml(book.package!);
    for (var cycle = 0; cycle < 2; cycle++) {
      final bytes = SheetSerializer().writeBytes(book, recalculate: false);
      final package = OpcPackage.openBytes(bytes);
      expect(_conditionalXml(package), original);
      book = SheetDeserializer().read(package);
    }
  });
}

SmlWorkbook _native(String ruleXml, {String sqref = 'A1:A3'}) {
  final book = SmlWorkbook(
    sheets: [
      SmlWorksheet(name: 'Data', sheetId: 1)
        ..cellA1('A1').value = 1
        ..cellA1('A2').value = 3,
      SmlWorksheet(name: 'Rules', sheetId: 2)..cellA1('A1').value = 2,
    ],
  );
  final package = SheetSerializer().write(book, recalculate: false);
  final part = package.getPart(_worksheetUri)!;
  final document = XmlDocument.parse(part.readText());
  document.root!.addChild(
    XmlDocument.parse(
      '<conditionalFormatting xmlns="$_sheetNamespace" sqref="$sqref">'
      '$ruleXml</conditionalFormatting>',
    ).root!,
  );
  part.writeText(document.toXmlString());
  return SheetDeserializer().read(package);
}

XmlElement _nativeRule(OpcPackage package) => XmlDocument.parse(
  package.getPart(_worksheetUri)!.readText(),
).root!.firstChild('conditionalFormatting')!.firstChild('cfRule')!;

String _conditionalXml(OpcPackage package) => XmlDocument(
  root: XmlDocument.parse(
    package.getPart(_worksheetUri)!.readText(),
  ).root!.firstChild('conditionalFormatting')!,
).toXmlString(declaration: false);

void _expectRenamedBounds(SmlWorkbook book, String lower, String upper) {
  final sheet = book.sheets[1];
  final rule = sheet.conditionalFormats.single;
  expect(rule.formula, lower);
  expect(rule.formula2, upper);
  expect(sheet.sourceConditionalFormatState, sheet.conditionalFormatState());

  final bytes = SheetSerializer().writeBytes(book, recalculate: false);
  final package = OpcPackage.openBytes(bytes);
  final nativeRule = _nativeRule(package);
  expect(nativeRule.getAttribute('priority'), '7');
  expect(nativeRule.getAttribute('stopIfTrue'), '1');
  expect(nativeRule.childrenNamed('formula').map((node) => node.text), [
    lower,
    upper,
  ]);
  final reopened = SheetDeserializer().read(package);
  expect(reopened.sheets[1].conditionalFormats.single.formula, lower);
  expect(reopened.sheets[1].conditionalFormats.single.formula2, upper);
}

Map<String, Object?> _snapshot(SmlWorkbook book) {
  final rule = book.sheets[1].conditionalFormats.single;
  return {
    'name': book.firstSheet.name,
    'formula': rule.formula,
    'formula2': rule.formula2,
    'rank': rule.rank,
    'source': book.sheets[1].sourceConditionalFormatState,
    'parts': {
      for (final part in book.package!.parts) part.uri: part.readBytes(),
    },
  };
}
