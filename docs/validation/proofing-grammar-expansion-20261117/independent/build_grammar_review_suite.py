#!/usr/bin/env python3
"""Embed independently authored cases in a VM/Node-compatible Dart probe."""
import json
from pathlib import Path

root=Path(__file__).resolve().parent
positive=json.loads((root/'positive_german_review_cases.json').read_text())
negative=[]
for name in ['valid_german_review_cases','adversarial-valid-german','adversarial-valid-german-2','adversarial-valid-german-3','adversarial-valid-german-4','adversarial-valid-german-5']:
    negative.extend(json.loads((root/(name+'.json')).read_text()))
template=r'''import 'dart:convert';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

const fixtures = r'__FIXTURES__';

Future<void> main() async {
  final data = jsonDecode(fixtures) as Map<String, dynamic>;
  final positive = (data['positive'] as List).cast<Map<String, dynamic>>();
  final negative = (data['negative'] as List).cast<String>();
  final provider = GermanWritingRulesProvider();
  final failures = <Map<String, Object?>>[];
  var requests = 0;
  var correctionRechecks = 0;
  var variants = 0;
  Future<OfficeProofingResult> check(String text, {int offset = 0, String language = 'de-DE', Set<String> ignored = const {}}) async {
    requests++;
    final result = await provider.check(OfficeProofingRequest(documentId: 'independent-grammar-review', blockId: 'case', revision: requests,
      text: text, startOffset: offset, language: language, ignoredRuleIds: ignored));
    if (result.status != OfficeProofingStatus.success) failures.add({'stage': 'provider-status', 'text': text, 'detail': result.status.name, 'message': result.message});
    return result;
  }
  void fail(String stage, String text, Object? detail) => failures.add({'stage': stage, 'text': text, 'detail': detail});
  for (final fixture in positive) {
    final text = fixture['text'] as String;
    final rule = fixture['rule'] as String;
    final original = fixture['original'] as String;
    final replacement = fixture['replacement'] as String;
    for (final variant in ['base', 'offset', 'soft-hyphen']) {
      variants++;
      var source = text;
      var expectedOriginal = original;
      if (variant == 'soft-hyphen') {
        final insertAt = original.isEmpty ? 1 : source.indexOf(original) + 1;
        source = source.replaceRange(insertAt, insertAt, '\u00ad');
        if (original.isNotEmpty) expectedOriginal = original.replaceRange(1, 1, '\u00ad');
      }
      final offset = variant == 'base' ? 0 : 37;
      if (offset != 0) source = '🙂 $source';
      final expectedReplacement = variant == 'soft-hyphen' ? replacement.replaceAll('ß', 'ss') : replacement;
      final variantLanguage = variant == 'base' ? 'de-DE' : variant == 'offset' ? 'de-AT' : 'de-CH';
      final result = await check(source, offset: offset, language: variantLanguage);
      final findings = result.findings;
      if (findings.length != 1) {
        fail(variant, source, {'expectedRule': rule, 'actualRules': findings.map((f) => f.ruleId).toList()});
        continue;
      }
      final finding = findings.single;
      if (finding.ruleId != rule || finding.originalText != expectedOriginal || finding.replacements.length != 1 || finding.replacements.single != expectedReplacement) {
        fail(variant, source, {'expectedRule': rule, 'expectedOriginal': expectedOriginal, 'expectedReplacement': expectedReplacement,
          'actualRule': finding.ruleId, 'actualOriginal': finding.originalText, 'actualReplacements': finding.replacements});
        continue;
      }
      final start = finding.start - offset;
      final end = finding.end - offset;
      if (start < 0 || end > source.length || source.substring(start, end) != expectedOriginal) {
        fail('source-range', source, {'start': start, 'end': end, 'expectedOriginal': expectedOriginal});
        continue;
      }
      final corrected = source.replaceRange(start, end, expectedReplacement);
      correctionRechecks++;
      final rechecked = await check(corrected, offset: offset, language: variantLanguage);
      if (rechecked.findings.isNotEmpty) fail('correction-recheck', corrected, rechecked.findings.map((f) => f.ruleId).toList());
    }
    variants++;
    final ignored = await check(text, ignored: {rule});
    if (ignored.findings.isNotEmpty) fail('ignore-rule', text, ignored.findings.map((f) => f.ruleId).toList());
    variants++;
    final protected = await check('🙂 `$text`', offset: 37);
    if (protected.findings.isNotEmpty) fail('protected-code', text, protected.findings.map((f) => f.ruleId).toList());
  }
  for (final text in negative) {
    final result = await check('🙂 $text', offset: 37);
    if (result.findings.isNotEmpty) fail('negative-control', text, [for (final f in result.findings) {'rule': f.ruleId, 'source': f.originalText, 'replacements': f.replacements}]);
  }
  await provider.dispose();
  print(const JsonEncoder.withIndent('  ').convert({'status': failures.isEmpty ? 'passed' : 'failed',
    'positive_sentences': positive.length, 'negative_sentences': negative.length, 'positive_variants': variants,
    'correction_rechecks': correctionRechecks, 'requests': requests, 'failures': failures,
    'scope': 'First-party independent behavioral cases; variants and rechecks are not separate language examples.'}));
  if (failures.isNotEmpty) throw StateError('Independent grammar review failed');
}
'''
# JSON is kept in a raw single-quoted Dart string; escape its literal apostrophes
# with Unicode escapes inside JSON to avoid changing fixture semantics.
fixtures=json.dumps({'positive':positive,'negative':negative},ensure_ascii=False,separators=(',',':')).replace("'",'\\u0027')
assert "'" not in fixtures
(root/'grammar_review_suite.dart').write_text(template.replace('__FIXTURES__',fixtures))
print({'positive_sentences':len(positive),'negative_sentences':len(negative)})
