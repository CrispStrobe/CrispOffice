import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// A header whose content control wraps a table or a drawing (letterhead
// templates) cannot be represented by the paragraph-only header model. The
// document used to be refused; the header part is now kept verbatim.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

OpcPackage _package() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart('/word/media/logo.png', 'image/png', _png);
  package
      .createPart('/word/header1.xml', OfficeContentTypes.wordHeader)
      .writeText(
        '<w:hdr xmlns:w="$_w" xmlns:r="$_r" xmlns:v="urn:schemas-microsoft-com:vml">'
        '<w:sdt><w:sdtPr><w:id w:val="42"/><w:tag w:val="Letterhead"/></w:sdtPr><w:sdtContent>'
        '<w:tbl><w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid><w:tr><w:tc>'
        '<w:p><w:r><w:t>Example GmbH</w:t></w:r></w:p>'
        '<w:p><w:r><w:pict><v:shape style="width:20pt;height:20pt"><v:imagedata r:id="rIdLogo"/></v:shape></w:pict></w:r></w:p>'
        '</w:tc></w:tr></w:tbl></w:sdtContent></w:sdt><w:p/></w:hdr>',
      );
  package
      .relationshipsFor('/word/header1.xml')
      .add(id: 'rIdLogo', type: RelationshipTypes.image, target: 'media/logo.png');
  package
      .relationshipsFor('/word/document.xml')
      .add(id: 'rIdH', type: RelationshipTypes.header, target: 'header1.xml');
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:r="$_r"><w:body>'
        '<w:p><w:r><w:t>Body text</w:t></w:r></w:p>'
        '<w:sectPr><w:headerReference w:type="default" r:id="rIdH"/></w:sectPr>'
        '</w:body></w:document>',
      );
  return package;
}

(String, OpcPackage) _savedHeader(Uint8List bytes) {
  final saved = OpcPackage.openBytes(bytes);
  final rels = saved.relationshipsFor('/word/document.xml');
  final rel = rels.items.singleWhere((r) => r.type == RelationshipTypes.header);
  final uri = rels.resolve(rel);
  return (saved.getPart(uri)!.readText(), saved);
}

void main() {
  test('a header with a control around a table and logo is kept verbatim', () async {
    var doc = WordDeserializer().read(_package());
    expect(doc.paragraphs.single.text, 'Body text');
    expect(doc.sections.single.preservedStories.keys, ['header']);
    for (var cycle = 0; cycle < 3; cycle++) {
      final bytes = await OfficeIsolateSave.word(doc);
      final (xml, saved) = _savedHeader(bytes);
      expect(xml, contains('<w:tag w:val="Letterhead"/>'), reason: '$cycle');
      expect(xml, contains('Example GmbH'));
      expect(xml, contains('<w:tbl>'));
      final headerUri = saved
          .relationshipsFor('/word/document.xml')
          .items
          .singleWhere((r) => r.type == RelationshipTypes.header);
      final partUri = saved.relationshipsFor('/word/document.xml').resolve(headerUri);
      final rid = RegExp(r'r:id="([^"]+)"').firstMatch(xml)!.group(1)!;
      final rels = saved.relationshipsFor(partUri);
      expect(rels.resolve(rels.byId(rid)!), '/word/media/logo.png');
      doc = WordDeserializer().readBytes(bytes);
      expect(doc.sections.single.preservedStories.keys, ['header']);
    }
  });

  test('new header content replaces a preserved header', () async {
    final doc = WordDeserializer().read(_package());
    doc.sections.single.header.add(
      WmlParagraph(inlines: [WmlRun(text: 'New header')]),
    );
    final (xml, _) = _savedHeader(await OfficeIsolateSave.word(doc));
    expect(xml, contains('New header'));
    expect(xml, isNot(contains('Letterhead')));
  });
}
