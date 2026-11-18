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
