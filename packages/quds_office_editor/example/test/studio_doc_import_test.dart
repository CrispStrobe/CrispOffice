@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_files.dart';

void main() {
  test('Word 97 .doc files are offered and converted to editable DOCX', () async {
    expect(StudioFiles.extensions, contains('doc'));
    expect(StudioFiles.extensions, contains('dot'));
    final file = File(
      '../../legacy_doc_parser/test/fixtures/external/poi-20261114/poi/doc/47304.doc',
    );
    expect(file.existsSync(), isTrue, reason: 'legacy DOC fixture is missing');
    final bytes = await file.readAsBytes();
    expect(StudioFiles.kindOf('47304.doc', Uint8List(0)), OpcPackageKind.word);
    expect(StudioFiles.kindOf('47304.doc', bytes), OpcPackageKind.word);
    expect(StudioFiles.isLegacyWordDoc('47304.doc', bytes), isTrue);
    expect(StudioFiles.legacyDocxName('47304.doc'), endsWith('.docx'));

    final converted = await StudioFiles.convertLegacyWordDoc(bytes);
    final package = OpcPackage.openBytes(converted);
    expect(package.kind, OpcPackageKind.word);
    final document = WordDeserializer().read(package);
    expect(document.paragraphs, isNotEmpty);
  });

  test('ordinary DOCX is not treated as a legacy conversion', () {
    final bytes = WordSerializer().writeBytes(
      WmlDocument.empty(text: 'Native DOCX'),
    );
    expect(StudioFiles.kindOf('word.docx', bytes), OpcPackageKind.word);
    expect(StudioFiles.isLegacyWordDoc('word.docx', bytes), isFalse);
  });
}
