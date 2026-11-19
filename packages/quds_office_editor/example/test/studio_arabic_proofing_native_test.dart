// End-to-end Arabic proofing with the real engine and dictionary:
//   QUDS_HUNSPELL_TEST_LIBRARY=<.../libquds_proofing_hunspell.dylib> \
//   QUDS_HUNSPELL_TEST_DICTIONARY=<directory with ar.aff/ar.dic> \
//   flutter test test/studio_arabic_proofing_native_test.dart
// Skipped (with the reason) when either variable is missing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

WmlDocument _wordAuthoredArabic() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:pPr><w:bidi/></w:pPr>
<w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space="preserve">ذهب الولد الى المدرسه وكتب الدرس، هاذا خطأ. </w:t></w:r>
<w:r><w:rPr><w:lang w:val="de-DE" w:bidi="ar-SA"/></w:rPr><w:t>Das ist gut.</w:t></w:r>
</w:p><w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault></w:docDefaults>
</w:styles>''');
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['QUDS_HUNSPELL_TEST_LIBRARY'];
  final dictionary = Platform.environment['QUDS_HUNSPELL_TEST_DICTIONARY'];
  final skip = library == null || dictionary == null
      ? 'Set QUDS_HUNSPELL_TEST_LIBRARY and QUDS_HUNSPELL_TEST_DICTIONARY.'
      : null;

  test(
    'Word document with w:bidi: Arabic rules and AyaSpell, one merged item',
    () async {
      final controller = WordEditorController(document: _wordAuthoredArabic());
      addTearDown(controller.dispose);
      controller.proofing.configure(
        OfficeProofingService(
          providers: [
            GermanSpellingProvider(vocabulary: controller.proofing.vocabulary),
            GermanWritingRulesProvider(),
            ArabicWritingRulesProvider(),
            HunspellProofingProvider(
              bundle: ayaspellArabic,
              dictionary: HunspellDictionaryFiles(
                affPath: '$dictionary/ar.aff',
                dicPath: '$dictionary/ar.dic',
              ),
              vocabulary: controller.proofing.vocabulary,
              nativeLibraryPath: library,
            ),
          ],
          timeout: const Duration(seconds: 60),
        ),
      );
      final summary = await controller.checkDocumentProofing();
      expect(summary.complete, isTrue, reason: summary.statusMessage);
      final items = [
        for (final issue in summary.issues)
          (
            issue.finding.providerId,
            issue.finding.ruleId,
            issue.finding.originalText,
            issue.finding.replacements.first,
            issue.language,
          ),
      ];
      expect(items, [
        // Rule and dictionary agree on الى → إلى: one item, the rule's.
        ('arabic-writing', 'ar.hamza.initial', 'الى', 'إلى', 'ar-SA'),
        ('arabic-writing', 'ar.ta-marbuta.final', 'المدرسه', 'المدرسة', 'ar-SA'),
        ('hunspell-ayaspell-ar', 'hunspell.spelling', 'هاذا', 'هادا', 'ar-SA'),
      ]);
      final merged = summary.issues.first.finding;
      expect(merged.replacements.first, 'إلى');
      expect(merged.replacements.length, greaterThan(1));
    },
    skip: skip,
  );
}
