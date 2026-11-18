import 'dart:convert';
import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  final document = WmlDocument.empty(text: 'Body');
  final session = WordZoteroCitingSession(
    document: document,
    documentId: 'review',
    insertionParagraph: document.paragraphs.first,
    insertionOffset: 0,
  );
  session.handle('Document.insertText', [
    'review', '<ol start="7"><li>Seven</li><li>Eight</li></ol>',
  ]);
  session.handle('Document.complete', ['review']);
  session.apply();
  final later = WmlParagraph(inlines: [WmlRun(text: 'Later ordinary list')]);
  document.sections.first.blocks.add(later);
  WordLists.applyLevel(later, numbered: true, document: document);
  final reopened = WordDeserializer().readBytes(WordSerializer().writeBytes(document));
  print(jsonEncode({
    'case': 'ordinary_list_created_after_independent_research_list',
    'source': [for (final p in document.paragraphs) {
      'text': p.text, 'numId': p.properties.numId, 'label': p.properties.listLabel,
    }],
    'reopened': [for (final p in reopened.paragraphs) {
      'text': p.text, 'numId': p.properties.numId, 'label': p.properties.listLabel,
    }],
  }));
  final imported = WmlDocument.empty(text: 'Existing');
  WordLists.applyLevel(imported.paragraphs.first, numbered: true, document: imported);
  final part = imported.package!.getPart('/word/numbering.xml')!;
  final xml = XmlDocument.parse(part.readText());
  xml.root!.addChild(XmlDocument.parse('<w:numIdMacAtCleanup xmlns:w="${OfficeNamespaces.w}" w:val="2"/>').root!);
  part.writeText(xml.toXmlString());
  WordLists.numberingId(imported, numbered: true, independent: true);
  print(jsonEncode({
    'case': 'independent_list_with_existing_numbering_cleanup',
    'children': XmlDocument.parse(part.readText()).root!.childElements.map((e) => e.localName).toList(),
  }));
}
