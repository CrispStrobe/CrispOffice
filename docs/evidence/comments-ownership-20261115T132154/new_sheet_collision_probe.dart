import 'dart:convert';
import 'package:quds_office_engine/quds_office_engine.dart';

Map<String, Object?> probe(bool malformed) {
  final sheet = SmlWorksheet(name: 'Original', sheetId: 1);
  sheet.cellA1('A1').value = 'original data';
  final source = SheetSerializer().write(SmlWorkbook(sheets: [sheet]));
  const orphanUri = '/xl/comments2.xml';
  final orphan = utf8.encode(malformed
      ? '<unrelated xmlns="${OfficeNamespaces.x}"/>'
      : '<comments xmlns="${OfficeNamespaces.x}"><authors><author>Unrelated author</author></authors>'
        '<commentList><comment ref="A1" authorId="0"><text><t>Retain this unrelated part</t></text></comment>'
        '</commentList></comments>');
  source.createPart(orphanUri, OfficeContentTypes.sheetComments, orphan);
  final book = SheetDeserializer().read(source);
  final added = SmlWorksheet(name: 'New worksheet', sheetId: 2);
  added.cellA1('A1').value = 'new value';
  book.sheets.add(added);
  final before = base64Encode(source.save());
  String? error;
  try {
    SheetSerializer().write(book, recalculate: false);
  } catch (failure) {
    error = failure.toString();
  }
  final retained = source.getPart(orphanUri);
  return {
    'malformedOrphanRoot': malformed,
    'error': error,
    'orphanPartRetained': retained != null,
    'orphanBytesUnchanged': retained != null && base64Encode(retained.readBytes()) == base64Encode(orphan),
    'packageChanged': before != base64Encode(source.save()),
    'newWorksheetPartCreated': source.getPart('/xl/worksheets/sheet2.xml') != null,
    'newWorksheetSourceUri': added.sourcePartUri,
  };
}
void main() {
  print(jsonEncode({'validOrphan': probe(false), 'malformedOrphan': probe(true)}));
}
