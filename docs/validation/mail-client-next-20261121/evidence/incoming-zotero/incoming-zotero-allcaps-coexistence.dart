import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const fixture =
    '/workspace/scratch/9b6ad165714c/quds_office_suite/packages/quds_office_engine/test/fixtures/zotero/odt/native-prose.odt';

void require(bool result, String detail) {
  if (!result) throw StateError(detail);
}

WmlRun arabic(WmlDocument document) => document.paragraphs
    .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
    .singleWhere((run) => run.text.contains('العربية'));

String? native(WmlRun run, String property) => XmlDocument.parse(
  run.properties.sourcePropertiesXml!,
).root!.firstChild(property, namespaceUri: word)?.getAttribute(
  'val',
  namespaceUri: word,
);

Future<void> main() async {
  final source = File(fixture).readAsBytesSync();
  final sourceHash = sha256.convert(source).toString();
  require(
    sourceHash ==
        '9fd4e0d23bf9cd2be0248bd5e9cfb496dfe512ec1226c456f324f2171705e1bd',
    'Unexpected real LibreOffice fixture',
  );
  var document = await OdtDocumentReader.readBytes(source);
  final originalText = document.paragraphs.map((p) => p.text).join('\n');
  arabic(document).properties
    ..allCaps = true
    ..smallCaps = false
    ..fontSizeHalfPoints = 32
    ..bold = false
    ..italic = true
    ..csFont = 'Noto Naskh Arabic';
  for (var cycle = 0; cycle < 4; cycle++) {
    final caps = cycle < 2;
    if (cycle == 2) arabic(document).properties.allCaps = false;
    document = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    final run = arabic(document);
    require(run.properties.allCaps == caps, 'AllCaps at cycle $cycle');
    require(!run.properties.smallCaps, 'SmallCaps at cycle $cycle');
    require(run.properties.fontSizeHalfPoints == 32, 'Size at cycle $cycle');
    require(!run.properties.bold, 'Weight at cycle $cycle');
    require(run.properties.italic, 'Italic at cycle $cycle');
    require(
      run.properties.csFont == 'Noto Naskh Arabic',
      'Complex font at cycle $cycle',
    );
    require(
      run.properties.complexScriptLanguage == 'hi-IN',
      'Authored complex language at cycle $cycle',
    );
    for (final expectation in {
      'caps': caps ? '1' : '0',
      'sz': '32',
      'szCs': '32',
      'bCs': '0',
      'iCs': '1',
    }.entries) {
      require(
        native(run, expectation.key) == expectation.value,
        'Native ${expectation.key} at cycle $cycle',
      );
    }
    require(
      document.paragraphs.map((p) => p.text).join('\n') == originalText,
      'Authored text at cycle $cycle',
    );
  }
  require(
    sha256.convert(File(fixture).readAsBytesSync()).toString() == sourceHash,
    'Fixture remains untouched',
  );
  stdout.writeln(jsonEncode({
    'success': true,
    'fixture_sha256': sourceHash,
    'docx_roundtrips': 4,
    'all_caps_transitions': [true, true, false, false],
    'verified': [
      'typed AllCaps and native caps retained together',
      'script font size, weight and italic synchronized',
      'complex font and authored language preserved',
      'UTF-16 source text and fixture bytes unchanged',
    ],
  }));
}
