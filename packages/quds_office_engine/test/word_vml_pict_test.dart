import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Legacy VML content (w:pict: horizontal rules, Word 2003 shapes, old
// pictures) was not read at all, so it vanished on the first save.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _ns =
    'xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

OpcPackage _package() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart('/word/media/legacy.png', 'image/png', _png);
  package
      .relationshipsFor('/word/document.xml')
      .add(id: 'rId7', type: RelationshipTypes.image, target: 'media/legacy.png');
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" $_ns><w:body>'
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">Before </w:t>'
        '<w:pict><v:rect id="_x0000_i1025" style="width:0;height:1.5pt" '
        'o:hralign="center" o:hrstd="t" o:hr="t" fillcolor="#a0a0a0" stroked="f"/></w:pict>'
        '<w:t xml:space="preserve"> after</w:t></w:r></w:p>'
        '<w:p><w:r><w:pict><v:shape id="_x0000_i1026" style="width:12pt;height:12pt">'
        '<v:imagedata r:id="rId7" o:title="legacy"/></v:shape></w:pict></w:r></w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  return package;
}

void main() {
  test('VML pictures and rules survive repeated saves', () async {
    var doc = WordDeserializer().read(_package());
    expect(doc.paragraphs.first.text, 'Before  after');
    for (var cycle = 0; cycle < 3; cycle++) {
      final bytes = await OfficeIsolateSave.word(doc);
      final saved = OpcPackage.openBytes(bytes);
      final xml = saved.getPart('/word/document.xml')!.readText();
      expect(xml, contains('o:hr="t"'), reason: '$cycle');
      final rid = RegExp(r'<v:imagedata r:id="([^"]+)"').firstMatch(xml)!.group(1);
      final rels = saved.relationshipsFor('/word/document.xml');
      expect(rels.resolve(rels.byId(rid!)!), '/word/media/legacy.png');
      expect(saved.getPart('/word/media/legacy.png')!.readBytes(), _png);
      // The rule stays between the two text runs, in a bold run.
      expect(
        xml.indexOf('Before'),
        lessThan(xml.indexOf('o:hr="t"')),
      );
      expect(xml.indexOf('o:hr="t"'), lessThan(xml.indexOf(' after')));
      doc = WordDeserializer().readBytes(bytes);
      expect(doc.paragraphs.first.text, 'Before  after');
    }
  });
}
