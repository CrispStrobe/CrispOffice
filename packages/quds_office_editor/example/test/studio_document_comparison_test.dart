import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_files.dart';

void main() {
  test(
    'two real DOCX inputs retain tracking and compare final text safely',
    () {
      final original = WmlDocument.empty(text: 'Draft old new');
      WordRevisions.record(
        original,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 0,
        start: 6,
        end: 10,
        text: 'old ',
        author: 'Reviewer',
      );
      final leftBytes = WordSerializer().writeBytes(original);
      final rightBytes = WordSerializer().writeBytes(
        WmlDocument.empty(text: 'Draft new'),
      );
      final leftCopy = Uint8List.fromList(leftBytes);
      final rightCopy = Uint8List.fromList(rightBytes);
      final left = StudioFiles.decodeComparisonDocument(leftBytes);
      final right = StudioFiles.decodeComparisonDocument(rightBytes);

      final result = WordDocumentComparison.compare(left, right);
      expect(result.hasChanges, isFalse);
      expect(left.revisions.single.author, 'Reviewer');
      expect(left.revisions.single.accepted, isNull);
      expect(left.paragraphs.single.text, 'Draft old new');
      expect(right.paragraphs.single.text, 'Draft new');
      expect(leftBytes, leftCopy);
      expect(rightBytes, rightCopy);
    },
  );

  test(
    'spreadsheet bytes cannot masquerade as an empty comparison document',
    () {
      final bytes = OpcPackage.create(OpcPackageKind.sheet).save();
      expect(
        () => StudioFiles.decodeComparisonDocument(bytes),
        throwsFormatException,
      );
    },
  );

  test('missing main content is rejected before comparison', () {
    final package = OpcPackage.create(OpcPackageKind.word);
    package.deletePart('/word/document.xml');
    expect(
      () => StudioFiles.decodeComparisonDocument(package.save()),
      throwsFormatException,
    );
  });

  test('wrong XML root, foreign namespace and missing body are rejected', () {
    for (final xml in <String>[
      '<workbook/>',
      '<document xmlns="urn:not-word"><body/></document>',
      '<w:document xmlns:w="${OfficeNamespaces.w}"/>',
    ]) {
      final package = OpcPackage.create(OpcPackageKind.word);
      package.getPart('/word/document.xml')!.writeText(xml);
      expect(
        () => StudioFiles.decodeComparisonDocument(package.save()),
        throwsFormatException,
        reason: xml,
      );
    }
  });

  test('comparison requires exactly one direct Word body', () {
    for (final content in <String>[
      '<body/>',
      '<foreign:body xmlns:foreign="urn:not-word"/>',
      '<w:body xmlns:w="http://purl.oclc.org/ooxml/wordprocessingml/main"/>',
      '<w:body/><w:body/>',
      '<w:customXml><w:body/></w:customXml>',
    ]) {
      final xml =
          '<w:document xmlns:w="${OfficeNamespaces.w}">'
          '$content</w:document>';
      final package = OpcPackage.create(OpcPackageKind.word);
      package.getPart('/word/document.xml')!.writeText(xml);
      expect(
        () => StudioFiles.decodeComparisonDocument(package.save()),
        throwsFormatException,
        reason: xml,
      );
    }
  });

  test('truncated and malformed XML cannot become an empty comparison', () {
    final root = '<w:document xmlns:w="${OfficeNamespaces.w}">';
    for (final xml in <String>[
      '$root<w:body>',
      '$root<w:body/>',
      '$root<w:body><w:p><w:r><w:t>Unclosed text',
      '$root<w:body></w:document>',
      '$root<w:body/></w:document>$root<w:body/></w:document>',
      'Unexpected text$root<w:body/></w:document>',
      '$root<w:body/></w:document>Unexpected text',
      '$root<w:body><![CDATA[outside]]></w:body></w:document><![CDATA[outside]]>',
      '$root<w:body><undeclared:p/></w:body></w:document>',
      '$root<w:body><w:p><w:r><w:t>&missing;</w:t></w:r></w:p></w:body></w:document>',
      '$root<w:body/><?xml version="1.0"?></w:document>',
      '<!DOCTYPE document>$root<w:body/></w:document>',
    ]) {
      final package = OpcPackage.create(OpcPackageKind.word);
      package.getPart('/word/document.xml')!.writeText(xml);
      expect(
        () => StudioFiles.decodeComparisonDocument(package.save()),
        throwsFormatException,
        reason: xml,
      );
    }
  });

  test(
    'valid namespace prefixes and default namespace retain document text',
    () {
      for (final xml in <String>[
        '<?xml version="1.0"?><!--before-->'
            '<word:document xmlns:word="${OfficeNamespaces.w}">'
            '<word:body><word:p><word:r><word:t>Alpha &amp; beta</word:t>'
            '</word:r></word:p></word:body></word:document><!--after-->',
        '<document xmlns="${OfficeNamespaces.w}">'
            '<body><p><r><t>Alpha &amp; beta</t></r></p></body></document>',
        '<w:document xmlns:w="${OfficeNamespaces.w}">'
            '<body xmlns="${OfficeNamespaces.w}">'
            '<p><r><t>Alpha &amp; beta</t></r></p></body></w:document>',
      ]) {
        final package = OpcPackage.create(OpcPackageKind.word);
        package.getPart('/word/document.xml')!.writeText(xml);
        final document = StudioFiles.decodeComparisonDocument(package.save());
        expect(document.paragraphs.single.text, 'Alpha & beta', reason: xml);
      }
    },
  );

  test(
    'a valid empty Word document remains a legitimate comparison source',
    () {
      final bytes = WordSerializer().writeBytes(WmlDocument.empty());
      final document = StudioFiles.decodeComparisonDocument(bytes);
      expect(
        document.paragraphs.map((paragraph) => paragraph.text).join(),
        isEmpty,
      );
    },
  );
}
