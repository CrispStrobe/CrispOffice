import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

/// Narrow acceptance probe for the URL and capital-sharp-s continuation fixes.
/// Compiled with the repository package config and executed in Node, not a
/// browser. The companion receipt binds source, dependencies and runtime.
Future<void> main() async {
  final spelling = OfficeProofingService(providers: [GermanSpellingProvider()]);
  final writing = OfficeProofingService(
    providers: [GermanWritingRulesProvider()],
  );
  var checks = 0;
  void verify(bool condition, String label) {
    if (!condition) throw StateError(label);
    checks++;
    print('PASS $checks $label');
  }

  OfficeProofingRequest input(
    String text, {
    String language = 'de-DE',
    int startOffset = 0,
  }) => OfficeProofingRequest(
    documentId: 'new-behavior-web-probe',
    blockId: 'paragraph',
    revision: 1,
    text: text,
    language: language,
    startOffset: startOffset,
  );

  const swissText = '🙂 STRAẞE GRÜẞE';
  final swiss = await spelling.check(input(swissText, language: 'de-CH'));
  verify(
    swiss.complete &&
        swiss.findings.length == 2 &&
        swiss.findings[0].originalText == 'STRAẞE' &&
        swiss.findings[1].originalText == 'GRÜẞE',
    'Swiss capital sharp-s produces two reviewable spelling findings',
  );
  verify(
    swiss.findings[0].replacements.contains('STRASSE') &&
        swiss.findings[0].replacements.every(
          (word) => word == word.toUpperCase(),
        ),
    'STRAẞE offers STRASSE and retains uppercase suggestion style',
  );
  verify(
    swiss.findings[1].replacements.contains('GRÜSSE'),
    'GRÜẞE offers GRÜSSE',
  );
  verify(
    swiss.findings.every(
          (finding) =>
              finding.message ==
              'Die Schweizer Schreibweise verwendet ss statt ß.',
        ) &&
        swiss.findings[0].start == swissText.indexOf('STRAẞE') &&
        swiss.findings[0].end ==
            swissText.indexOf('STRAẞE') + 'STRAẞE'.length &&
        swiss.findings[1].start == swissText.indexOf('GRÜẞE') &&
        swiss.findings[1].end == swissText.length,
    'Swiss explanations and UTF-16 ranges preserve the original source',
  );
  verify(
    (await spelling.check(input('STRAẞE GRÜẞE'))).isClean,
    'standard German still accepts the capital sharp-s forms',
  );

  const urlText =
      '🙂 HTTPS://example.invalid/Huas WWW.example.invalid/Huas Huas';
  final urlSpelling = await spelling.check(input(urlText));
  verify(
    urlSpelling.complete &&
        urlSpelling.findings.length == 1 &&
        urlSpelling.findings.single.originalText == 'Huas' &&
        urlSpelling.findings.single.start == urlText.lastIndexOf('Huas') &&
        urlSpelling.findings.single.end == urlText.length &&
        urlSpelling.findings.single.replacements.contains('Haus'),
    'uppercase URL prefixes are protected while the ordinary typo stays actionable',
  );

  for (final prefix in [
    'https://example.invalid/ich',
    'HTTPS://example.invalid/ich',
    'WWW.example.invalid/ich',
    'name@example.ich',
  ]) {
    final text = '🙂 $prefix bist. Ich bist hier.';
    final result = await writing.check(input(text));
    verify(
      result.complete &&
          result.findings.length == 1 &&
          result.findings.single.ruleId == 'de.grammar.pronoun-verb' &&
          result.findings.single.originalText == 'bist' &&
          result.findings.single.start == text.lastIndexOf('bist') &&
          result.findings.single.replacements.single == 'bin',
      'protected subject context cannot govern following prose: $prefix',
    );
  }

  for (final text in [
    '(https://example.invalid/path)',
    '(https://example.invalid/a(b))',
    '(http://[::1]/a(b)).',
    '„https://example.invalid/path“',
    '“https://example.invalid/path”',
    '‘https://example.invalid/path’',
    '«https://example.invalid/path»',
    '»https://example.invalid/path«',
    '(„HTTPS://example.invalid/a(b)“).',
  ]) {
    verify(
      (await writing.check(input(text))).isClean,
      'balanced URL punctuation stays clean: $text',
    );
  }

  const excessText = '🙂 (https://example.invalid/a(b)))';
  final excess = await writing.check(input(excessText, startOffset: 20));
  verify(
    excess.complete &&
        excess.findings.length == 1 &&
        excess.findings.single.ruleId == 'de.delimiter.balance' &&
        excess.findings.single.originalText == ')' &&
        excess.findings.single.start == 20 + excessText.length - 1 &&
        excess.findings.single.end == 20 + excessText.length &&
        excess.findings.single.replacements.isEmpty,
    'excess closing punctuation keeps exact block-relative UTF-16 offsets',
  );

  await spelling.dispose();
  await writing.dispose();
  if (checks != 20)
    throw StateError('Expected 20 targeted checks, got $checks');
  print('All $checks targeted compiled-JavaScript proofing checks passed.');
}
