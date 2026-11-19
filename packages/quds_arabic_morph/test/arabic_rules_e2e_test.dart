@TestOn('vm')
library;

import 'dart:io';

import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// End to end: the real native analyzer and noprob database feeding the
/// morphology-based Arabic rules (ArabicWritingRulesProvider(morphology:)).
final _library = Platform.environment['QUDS_ARABIC_MORPH_TEST_LIBRARY'];
final _bundle = Platform.environment['QUDS_ARABIC_MORPH_TEST_BUNDLE'];
final Object _skip = _library == null || _bundle == null
    ? 'Set QUDS_ARABIC_MORPH_TEST_LIBRARY and QUDS_ARABIC_MORPH_TEST_BUNDLE.'
    : false;

void main() {
  late CamelArabicMorphology morphology;
  late ArabicWritingRulesProvider provider;

  setUpAll(() async {
    if (_skip != false) return;
    morphology = CamelArabicMorphology(
      database: MorphDatabaseFiles(
        camelMorphMsaNoprob,
        manifestPath: '$_bundle/manifest.json',
      ),
      nativeLibraryPath: _library,
    );
    await morphology.load();
    provider = ArabicWritingRulesProvider(morphology: morphology);
  });
  tearDownAll(() async {
    if (_skip != false) return;
    await provider.dispose();
    await morphology.dispose();
  });

  Future<Set<String>> ruleIds(String text) async {
    final result = await provider.check(
      OfficeProofingRequest(
        documentId: 'e2e',
        blockId: 'p',
        revision: 1,
        text: text,
        language: 'ar',
      ),
    );
    return {for (final f in result.findings) f.ruleId};
  }

  test('errors are found with the real analyzer', () async {
    expect(morphology.isAvailable, isTrue);
    expect(
      await ruleIds('لم يبقى أحد في القاعة.'),
      contains('ar.grammar.jussive'),
    );
    expect(
      await ruleIds('يجب أن يرتدون الزي الرسمي.'),
      contains('ar.grammar.subjunctive'),
    );
    expect(
      await ruleIds('نزلنا في ثلاث فنادق.'),
      contains('ar.numeral.gender'),
    );
  }, skip: _skip);

  test('the corrected sentences stay silent', () async {
    const grammar = {
      'ar.grammar.jussive',
      'ar.grammar.subjunctive',
      'ar.numeral.gender',
    };
    for (final text in [
      'لم يبق أحد في القاعة.',
      'يجب أن يرتدوا الزي الرسمي.',
      'نزلنا في ثلاثة فنادق.',
    ]) {
      expect(
        (await ruleIds(text)).intersection(grammar),
        isEmpty,
        reason: text,
      );
    }
  }, skip: _skip);
}
