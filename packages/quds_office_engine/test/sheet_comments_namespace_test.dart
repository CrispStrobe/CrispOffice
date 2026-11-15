import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// ISO/IEC 29500-1, 18.7.5 (comment text) and A.2 (CT_Rst): comment
// text is a rich-string container, with plain text in an x:t child.
// https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.commenttext
SmlWorkbook _workbook(String text) {
  final sheet = SmlWorksheet(name: 'Notes', sheetId: 1);
  sheet.cellA1('A1').value = 'reviewed';
  sheet.comments.addAll([
    SmlComment(ref: SmlCellRef.parse('A1'), text: text, author: 'Alice & Co'),
    SmlComment(ref: SmlCellRef.parse('B2'), text: 'second', author: 'Bob'),
    SmlComment(
      ref: SmlCellRef.parse('C3'),
      text: 'again',
      author: 'Alice & Co',
    ),
  ]);
  return SmlWorkbook(sheets: [sheet]);
}

Iterable<XmlElement> _elements(XmlElement element) sync* {
  yield element;
  for (final child in element.childElements) {
    yield* _elements(child);
  }
}

const _relocatedComments = '/xl/annotations/note42.xml';

OpcPackage _relocatedPackage({bool keepLegacyDecoy = false}) {
  final package = SheetSerializer().write(_workbook('legacy decoy'));
  // Independently authored valid source avoids relying on the serializer's
  // output shape for import and relationship coverage.
  package.createPart(
    _relocatedComments,
    OfficeContentTypes.sheetComments,
    utf8.encode(
      '<comments xmlns="${OfficeNamespaces.x}">'
      '<authors><author>Original</author></authors>'
      '<commentList><comment ref="A1" authorId="0">'
      '<text><t xml:space="preserve"> authored note </t></text>'
      '</comment></commentList></comments>',
    ),
  );
  final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
  final original = rels.firstByType(RelationshipTypes.comments)!;
  rels.removeById(original.id);
  rels.add(
    id: original.id,
    type: RelationshipTypes.comments,
    target: '../annotations/note42.xml',
  );
  if (!keepLegacyDecoy) package.deletePart('/xl/comments1.xml');
  return OpcPackage.openBytes(package.save());
}

void main() {
  test('import and edit follow the authored comments relationship', () {
    final source = _relocatedPackage();
    var book = SheetDeserializer().read(source);
    expect(book.firstSheet.comments, hasLength(1));
    expect(book.firstSheet.comments.single.text, ' authored note ');
    expect(book.firstSheet.comments.single.author, 'Original');
    book.firstSheet.comments.single
      ..text = ' changed & reviewed '
      ..author = 'Reviewer';

    for (var cycle = 1; cycle <= 3; cycle++) {
      final package = OpcPackage.openBytes(
        SheetSerializer().write(book).save(),
      );
      final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
      final commentsRel = rels.firstByType(RelationshipTypes.comments)!;
      expect(rels.resolve(commentsRel), _relocatedComments);
      expect(package.getPart('/xl/comments1.xml'), isNull);
      expect(package.getPart(_relocatedComments), isNotNull);
      book = SheetDeserializer().read(package);
      expect(book.firstSheet.comments, hasLength(1));
      expect(book.firstSheet.comments.single.text, ' changed & reviewed ');
      expect(book.firstSheet.comments.single.author, 'Reviewer');
    }
  });

  test('authored comments relationship takes priority over legacy naming', () {
    final book = SheetDeserializer().read(
      _relocatedPackage(keepLegacyDecoy: true),
    );
    expect(book.firstSheet.comments, hasLength(1));
    expect(book.firstSheet.comments.single.text, ' authored note ');
  });

  test('legacy fixed-name comments remain readable without a relationship', () {
    final package = SheetSerializer().write(_workbook('legacy fallback'));
    final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
    rels.removeById(rels.firstByType(RelationshipTypes.comments)!.id);
    final book = SheetDeserializer().readBytes(package.save());
    expect(book.firstSheet.comments.first.text, 'legacy fallback');
  });

  for (final relocated in [false, true]) {
    test(
      'clearing ${relocated ? 'relocated' : 'standard'} comments removes them',
      () {
        final package = relocated
            ? _relocatedPackage()
            : SheetSerializer().write(_workbook('remove me'));
        final sourceUri = relocated ? _relocatedComments : '/xl/comments1.xml';
        var book = SheetDeserializer().read(package);
        book.firstSheet.comments.clear();
        for (var cycle = 1; cycle <= 2; cycle++) {
          final saved = OpcPackage.openBytes(
            SheetSerializer().write(book).save(),
          );
          expect(
            saved
                .relationshipsFor('/xl/worksheets/sheet1.xml')
                .firstByType(RelationshipTypes.comments),
            isNull,
          );
          expect(saved.getPart(sourceUri), isNull);
          expect(saved.getPart('/xl/comments1.xml'), isNull);
          book = SheetDeserializer().read(saved);
          expect(book.firstSheet.comments, isEmpty);
        }
      },
    );
  }

  test('every comment element belongs to the SpreadsheetML namespace', () {
    final package = SheetSerializer().write(_workbook('reviewed'));
    final root = XmlDocument.parse(
      package.getPart('/xl/comments1.xml')!.readText(),
    ).root!;
    expect(root.localName, 'comments');
    for (final element in _elements(root)) {
      expect(
        element.namespaceUri,
        OfficeNamespaces.x,
        reason: 'namespace of ${element.localName}',
      );
    }
  });

  const cases = <String, String>{
    'ordinary text': 'plain comment',
    'leading whitespace': ' leading',
    'trailing whitespace': 'trailing ',
    'multiline and tabs': ' \tline one\nline two \t ',
    'empty text': '',
    'escaped XML and Unicode': 'A&B <tag> "quote" — café 🙂',
  };
  for (final entry in cases.entries) {
    test('CT_Rst preserves ${entry.key} through three XLSX saves', () {
      var book = _workbook(entry.value);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = SheetSerializer().write(book).save();
        final package = OpcPackage.openBytes(bytes);
        final root = XmlDocument.parse(
          package.getPart('/xl/comments1.xml')!.readText(),
        ).root!;
        final authors = root.firstChild('authors')!.childElements.toList();
        expect(authors.map((author) => author.text), ['Alice & Co', 'Bob']);
        final comments = root.firstChild('commentList')!.childElements.toList();
        expect(comments.map((comment) => comment.getAttribute('authorId')), [
          '0',
          '1',
          '0',
        ]);
        final text = comments.first.firstChild('text')!;
        expect(text.childElements.map((element) => element.localName), [
          't',
        ], reason: 'plain comment text uses CT_Rst/x:t on save $cycle');
        expect(text.children.whereType<XmlText>(), isEmpty);
        final runText = text.firstChild('t')!;
        expect(runText.namespaceUri, OfficeNamespaces.x);
        expect(runText.text, entry.value);
        if (entry.value.trim() != entry.value) {
          expect(
            runText.getAttribute('space', namespaceUri: OfficeNamespaces.xml),
            'preserve',
            reason: 'edge whitespace is significant in comment text',
          );
        }
        book = SheetDeserializer().read(package);
        expect(book.firstSheet.comments.map((comment) => comment.text), [
          entry.value,
          'second',
          'again',
        ]);
        expect(book.firstSheet.comments.map((comment) => comment.author), [
          'Alice & Co',
          'Bob',
          'Alice & Co',
        ]);
      }
    });
  }
}
