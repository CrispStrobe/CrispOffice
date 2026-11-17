// This workspace-level cross-checkout harness receives an explicit package
// configuration; it intentionally is not a new published Dart package.
// ignore_for_file: depend_on_referenced_packages

// Cross-runtime qualification: pass the same immutable JSON corpus via
// -DQUDS_MORPHOLOGY_CORPUS=... to the Dart VM or the JavaScript compiler.
// This file intentionally avoids dart:io so Node runs the actual provider.
import 'dart:convert';

import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

const String _corpusJson = String.fromEnvironment('QUDS_MORPHOLOGY_CORPUS');
const bool _variants = bool.fromEnvironment(
  'QUDS_MORPHOLOGY_VARIANTS',
  defaultValue: true,
);

String _withSoftHyphen(String text) {
  // The zero-width discretionary character stays in original-source space.
  // Inserting within the first sufficiently long word also probes target words
  // in sentence-initial examples; comparison removes only this authored mark.
  final Match? match = RegExp(r'\p{L}{3,}', unicode: true).firstMatch(text);
  if (match == null) return text;
  return text.replaceRange(match.start + 2, match.start + 2, '\u00ad');
}

Future<void> main() async {
  if (_corpusJson.isEmpty) {
    throw StateError(
      'QUDS_MORPHOLOGY_CORPUS must contain the reviewed JSON corpus.',
    );
  }
  final Map<String, Object?> corpus =
      (jsonDecode(_corpusJson) as Map<String, dynamic>).cast<String, Object?>();
  final List<Map<String, dynamic>> cases = (corpus['cases']! as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final OfficeProofingService service = OfficeProofingService(
    providers: <OfficeProofingProvider>[GermanWritingRulesProvider()],
    timeout: const Duration(seconds: 30),
  );
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  int revision = 0;
  Future<OfficeProofingReport> check(
    String text,
    String language, {
    int offset = 0,
    Set<String> ignored = const <String>{},
  }) => service.check(
    OfficeProofingRequest(
      documentId: 'independent-morphology-qualification',
      blockId: 'case',
      revision: revision++,
      text: text,
      language: language,
      startOffset: offset,
      ignoredRuleIds: ignored,
    ),
  );
  for (final Map<String, dynamic> sample in cases) {
    final String source = sample['text'] as String;
    final String expected = sample['expected'] as String;
    final String language = sample['language'] as String;
    final List<(String, String, String, String, int)> variants =
        <(String, String, String, String, int)>[
          ('base', source, expected, language, 0),
          if (_variants) ...<(String, String, String, String, int)>[
            (
              'source-offset',
              '👩🏽‍💻 $source',
              '👩🏽‍💻 $expected',
              language,
              37,
            ),
            ('soft-hyphen', _withSoftHyphen(source), expected, language, 19),
            (
              'locale-alias',
              source,
              expected,
              language == 'de-CH'
                  ? 'de-Latn-CH-1996-u-co-phonebk'
                  : 'de-Latn-AT-1996-u-co-phonebk',
              11,
            ),
          ],
        ];
    for (final (
          String name,
          String text,
          String wanted,
          String locale,
          int offset,
        )
        in variants) {
      final OfficeProofingReport report = await check(
        text,
        locale,
        offset: offset,
      );
      String applied = text;
      bool canApply = report.complete;
      int rightEdge = text.length + 1;
      for (final OfficeProofingFinding finding in report.findings.reversed) {
        final int start = finding.start - offset;
        final int end = finding.end - offset;
        if (finding.replacements.isEmpty || end > rightEdge) {
          canApply = false;
          break;
        }
        applied = applied.replaceRange(start, end, finding.replacements.first);
        rightEdge = start;
      }
      final String comparable = name == 'soft-hyphen'
          ? applied.replaceAll('\u00ad', '')
          : applied;
      final String wantedComparable = name == 'soft-hyphen'
          ? wanted.replaceAll('\u00ad', '')
          : wanted;
      final bool exact =
          report.complete && canApply && comparable == wantedComparable;
      final Map<String, Object?> item = <String, Object?>{
        'id': sample['id'],
        'kind': sample['kind'],
        'area': sample['area'],
        'scope': sample['scope'],
        'variant': name,
        'language': locale,
        'text': text,
        'expected': wanted,
        'start_offset': offset,
        'complete': report.complete,
        'statuses': <String>[
          for (final OfficeProofingResult result in report.results)
            result.status.name,
        ],
        'messages': <String?>[
          for (final OfficeProofingResult result in report.results)
            result.message,
        ],
        'clean': report.isClean,
        'applied': applied,
        'can_apply_nonoverlapping': canApply,
        'exact': exact,
        'findings': <Map<String, Object?>>[
          for (final OfficeProofingFinding finding in report.findings)
            <String, Object?>{
              'rule': finding.ruleId,
              'original': finding.originalText,
              'start': finding.start,
              'end': finding.end,
              'replacements': finding.replacements,
            },
        ],
      };
      if (canApply && report.findings.isNotEmpty) {
        final OfficeProofingReport recheck = await check(
          applied,
          locale,
          offset: offset,
        );
        item['recheck_clean'] = recheck.isClean;
        item['recheck_statuses'] = <String>[
          for (final OfficeProofingResult result in recheck.results)
            result.status.name,
        ];
      }
      if (report.findings.isNotEmpty) {
        final OfficeProofingReport ignored = await check(
          text,
          locale,
          offset: offset,
          ignored: <String>{
            for (final OfficeProofingFinding finding in report.findings)
              finding.ruleId,
          },
        );
        item['ignore_clean'] = ignored.isClean;
      }
      results.add(item);
    }
    // Whole-span literal code is a separate safety check, not a German
    // accuracy sample. Use four backticks so examples containing one/two
    // backticks remain enclosed by a matching delimiter.
    if (_variants) {
      final OfficeProofingReport code = await check(
        '````$source````',
        language,
        offset: 7,
      );
      results.add(<String, Object?>{
        'id': sample['id'],
        'kind': 'protection',
        'area': sample['area'],
        'scope': 'source-protection',
        'variant': 'code',
        'language': language,
        'complete': code.complete,
        'clean': code.isClean,
        'statuses': <String>[
          for (final OfficeProofingResult result in code.results)
            result.status.name,
        ],
        'findings': <Map<String, Object?>>[
          for (final OfficeProofingFinding finding in code.findings)
            <String, Object?>{
              'rule': finding.ruleId,
              'original': finding.originalText,
              'replacements': finding.replacements,
            },
        ],
      });
    }
  }
  await service.dispose();
  final List<Map<String, Object?>> base = results
      .where((Map<String, Object?> x) => x['variant'] == 'base')
      .toList();
  int count(bool Function(Map<String, Object?>) predicate) =>
      base.where(predicate).length;
  final Map<String, Object?> summary = <String, Object?>{
    'sentences': cases.length,
    'requests_recorded': results.length,
    'errors': count((Map<String, Object?> x) => x['kind'] == 'error'),
    'exact_errors': count(
      (Map<String, Object?> x) => x['kind'] == 'error' && x['exact'] == true,
    ),
    'expanded_errors': count(
      (Map<String, Object?> x) =>
          x['kind'] == 'error' && x['scope'] == 'expanded',
    ),
    'exact_expanded_errors': count(
      (Map<String, Object?> x) =>
          x['kind'] == 'error' &&
          x['scope'] == 'expanded' &&
          x['exact'] == true,
    ),
    'challenge_errors': count(
      (Map<String, Object?> x) =>
          x['kind'] == 'error' && x['scope'] == 'challenge',
    ),
    'exact_challenge_errors': count(
      (Map<String, Object?> x) =>
          x['kind'] == 'error' &&
          x['scope'] == 'challenge' &&
          x['exact'] == true,
    ),
    'valid_controls': count((Map<String, Object?> x) => x['kind'] == 'control'),
    'flagged_controls': count(
      (Map<String, Object?> x) =>
          x['kind'] == 'control' &&
          x['complete'] == true &&
          x['clean'] == false,
    ),
    'operational_failures': results
        .where((Map<String, Object?> x) => x['complete'] != true)
        .length,
    'protection_failures': results
        .where(
          (Map<String, Object?> x) =>
              x['kind'] == 'protection' && x['clean'] != true,
        )
        .length,
    'ignore_failures': results
        .where((Map<String, Object?> x) => x['ignore_clean'] == false)
        .length,
    'recheck_failures': results
        .where((Map<String, Object?> x) => x['recheck_clean'] == false)
        .length,
  };
  print(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'summary': summary, 'results': results}),
  );
}
