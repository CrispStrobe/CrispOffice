import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../../../tools/proofing/german_model/incremental_quality.dart';

typedef _Edit = (int, int, List<String>);

OfficeProofingResult _result(
  OfficeProofingRequest request,
  String id,
  List<_Edit> edits, {
  OfficeProofingStatus status = OfficeProofingStatus.success,
}) => OfficeProofingResult(
  request: request,
  providerId: id,
  status: status,
  message: status == OfficeProofingStatus.success ? null : 'Explicit status.',
  findings: [
    for (final edit in edits)
      OfficeProofingFinding.forRequest(
        request,
        providerId: id,
        start: edit.$1,
        end: edit.$2,
        ruleId: '$id.rule',
        message: 'Review.',
        category: OfficeProofingCategory.grammar,
        replacements: edit.$3,
      ),
  ],
);

QualityObservation _observe(
  QualityCase sample, {
  List<_Edit> spelling = const [],
  List<_Edit> writing = const [],
  List<_Edit> model = const [],
  OfficeProofingStatus modelStatus = OfficeProofingStatus.success,
}) {
  final request = OfficeProofingRequest(
    documentId: 'quality',
    blockId: sample.id,
    revision: 1,
    text: sample.input,
    language: sample.locale,
    startOffset: 37,
  );
  final writingResult = _result(request, 'german-writing', writing);
  final deterministic = OfficeProofingReport(
    request: request,
    results: [_result(request, 'german-spelling', spelling), writingResult],
  );
  final modelReport = OfficeProofingReport(
    request: request,
    results: [_result(request, 'gector-de', model, status: modelStatus)],
  );
  return QualityObservation(sample, {
    'writing_only': projectQualityReport(
      OfficeProofingReport(request: request, results: [writingResult]),
    ),
    'deterministic': projectQualityReport(deterministic),
    'model_only': projectQualityReport(modelReport),
    'combined': projectQualityReport(
      mergeOfficeProofingReports(
        primary: deterministic,
        secondary: modelReport,
      ),
    ),
  });
}

QualityCase _case({
  String id = 'case',
  String expected = 'abXd',
  String kind = 'error',
  String input = 'abcd',
  String locale = 'de-DE',
}) => QualityCase(
  id: id,
  kind: kind,
  input: input,
  expected: expected,
  locale: locale,
);

Map<String, Object?> _lane(Map<String, Object?> summary, String name) =>
    (summary['lanes']! as Map<String, Map<String, Object?>>)[name]!;

Map<String, Object?> _incremental(Map<String, Object?> summary) =>
    summary['incremental']! as Map<String, Object?>;

File _corpus(String name) {
  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 4; depth++) {
    final file = File('${directory.path}/tools/proofing/german_model/$name');
    if (file.existsSync()) return file;
    directory = directory.parent;
  }
  throw StateError('Run this test within the repository.');
}

void main() {
  test(
    'both frozen real corpora parse without changing their declarations',
    () {
      final frozen = parseQualityCases(
        jsonDecode(_corpus('cases.json').readAsStringSync()),
      );
      final prospective = parseQualityCases(
        jsonDecode(
          _corpus('prospective_cases_20261117.json').readAsStringSync(),
        ),
      );
      expect(frozen, hasLength(30));
      expect(prospective, hasLength(76));
      expect(
        frozen.where((sample) => sample.expectedModelStatus == 'unsupported'),
        hasLength(2),
      );
      expect(
        prospective.where(
          (sample) => sample.expectedModelStatus == 'unsupported',
        ),
        hasLength(4),
      );
      expect(prospective.any((sample) => sample.pairId == null), isTrue);
      expect(
        prospective
            .where((sample) => sample.declaredModelStatus != null)
            .every(
              (sample) =>
                  sample.toJson()['expected_model_status'] == 'unsupported',
            ),
        isTrue,
      );
    },
  );

  test(
    'clean expected text defaults to source and locale aliases stay explicit',
    () {
      final cases = parseQualityCases([
        {
          'id': 'clean',
          'kind': 'clean',
          'input': 'Gut.',
          'locale': 'de_CH',
          'expected_model_status': 'unsupported',
          'pair_id': null,
        },
      ]);
      expect(cases.single.expected, 'Gut.');
      expect(cases.single.locale, 'de_CH');
      expect(cases.single.language, 'de-CH');
      expect(cases.single.expectedModelStatus, 'unsupported');
    },
  );

  test('malformed, duplicate and contradictory corpus rows are rejected', () {
    const clean = {'id': 'one', 'kind': 'clean', 'input': 'Gut.'};
    for (final invalid in <Object?>[
      {},
      [],
      [clean, clean],
      [
        {'kind': 'clean', 'input': 'Gut.'},
      ],
      [
        {'id': 'one', 'kind': 'error', 'input': 'Gut.'},
      ],
      [
        {...clean, 'kind': 'unknown'},
      ],
      [
        {...clean, 'expected': 'Anders.'},
      ],
      [
        {...clean, 'kind': 'error', 'expected': 'Gut.'},
      ],
      [
        {...clean, 'input': '\ud800'},
      ],
      [
        {...clean, 'unrecognized': true},
      ],
      [
        {...clean, 'expected_model_status': 'unsupported'},
      ],
      [
        {...clean, 'locale': 'de-CH', 'expected_model_status': 'success'},
      ],
    ]) {
      expect(() => parseQualityCases(invalid), throwsFormatException);
    }
  });

  test('first replacement is chosen even when a later alternative is gold', () {
    final sample = _case();
    final row = _observe(
      sample,
      spelling: [
        (2, 3, ['wrong', 'X']),
      ],
    );
    expect(row['deterministic'].corrected, 'abwrongd');
    expect(row['deterministic'].exact(sample.expected), isFalse);
    expect(row['deterministic'].accepted.single.replacements, ['wrong', 'X']);
    expect(row['writing_only'].corrected, sample.input);
  });

  test('projection preserves source UTF16 offsets and an empty deletion', () {
    final sample = _case(input: '🙂abcd', expected: '🙂aXd');
    final row = _observe(
      sample,
      writing: [
        (3, 4, ['X']),
        (4, 5, ['']),
      ],
    );
    expect(row['combined'].corrected, sample.expected);
    expect(row['combined'].accepted.first.start, 40);
    expect(row['combined'].accepted.first.originalText, 'b');
  });

  test(
    'primary overlaps are retained for display but projection skips them',
    () {
      final row = _observe(
        _case(),
        spelling: [
          (1, 3, ['X']),
        ],
        writing: [
          (2, 4, ['Y']),
        ],
      );
      expect(row['deterministic'].report.findings, hasLength(2));
      expect(row['deterministic'].corrected, 'aXd');
      expect(
        row['deterministic'].skipped.single.reason,
        'overlap-with-earlier-projection',
      );
      expect(row['writing_only'].corrected, 'abY');
    },
  );

  test(
    'insertion endpoints conflict but adjacent nonempty ranges can apply',
    () {
      final row = _observe(
        _case(),
        writing: [
          (1, 2, ['B']),
          (2, 2, ['!']),
          (2, 3, ['C']),
          (4, 4, ['.']),
        ],
      );
      expect(row['writing_only'].corrected, 'aBCd.');
      expect(row['writing_only'].skipped, hasLength(1));
      expect(row['writing_only'].skipped.single.finding.originalText, '');
    },
  );

  test('advisory flags are distinct from changed clean controls', () {
    final sample = _case(kind: 'clean', expected: 'abcd');
    final row = _observe(sample, writing: [(1, 2, [])]);
    final summary = summarizeQuality([sample], [row]);
    expect(row['combined'].corrected, sample.input);
    expect(row['combined'].skipped.single.reason, 'no-replacement-advisory');
    expect(_lane(summary, 'combined')['flagged_clean_count'], 1);
    expect(_lane(summary, 'combined')['changed_clean_count'], 0);
    expect(_lane(summary, 'combined')['unchanged_clean_count'], 1);
    expect(_lane(summary, 'combined')['unflagged_clean_count'], 0);
  });

  test('incomplete reports never count as corrected or clean', () {
    final sample = _case();
    final row = _observe(
      sample,
      writing: [
        (2, 3, ['X']),
      ],
      modelStatus: OfficeProofingStatus.unavailable,
    );
    final summary = summarizeQuality([sample], [row]);
    expect(row['deterministic'].exact(sample.expected), isTrue);
    expect(row['combined'].corrected, isNull);
    expect(row['combined'].exact(sample.expected), isFalse);
    expect(row['combined'].report.isClean, isFalse);
    expect(row['combined'].skipped.single.reason, 'incomplete-report');
    expect(_lane(summary, 'combined')['exact_error_count'], 0);
    expect(_incremental(summary)['lost_exact_error_ids'], isEmpty);
    expect(_incremental(summary)['not_comparable_ids'], [sample.id]);
    expect(summary['operational_passed'], isFalse);
  });

  test(
    'unsupported model locales retain deterministic coverage separately',
    () {
      final sample = _case(kind: 'clean', expected: 'abcd', locale: 'de-CH');
      final row = _observe(
        sample,
        modelStatus: OfficeProofingStatus.unsupported,
      );
      final summary = summarizeQuality([sample], [row]);
      expect(row['model_only'].corrected, isNull);
      expect(row['combined'].report.isClean, isTrue);
      expect(_lane(summary, 'model_only')['unsupported_only_ids'], [sample.id]);
      expect(_lane(summary, 'model_only')['unchanged_clean_count'], 0);
      expect(_lane(summary, 'combined')['unchanged_clean_count'], 1);
      expect(_incremental(summary)['comparable_ids'], isEmpty);
      expect(summary['operational_passed'], isTrue);
    },
  );

  test('independent model fixes are counted only after production merging', () {
    final sample = _case();
    final row = _observe(
      sample,
      model: [
        (2, 3, ['X']),
      ],
    );
    final summary = summarizeQuality([sample], [row]);
    expect(_lane(summary, 'deterministic')['exact_error_count'], 0);
    expect(_lane(summary, 'combined')['exact_error_count'], 1);
    expect(_incremental(summary)['added_exact_error_ids'], [sample.id]);
    expect(_incremental(summary)['model_unique_exact_error_ids'], [sample.id]);
    expect(row.acceptedModel, hasLength(1));
    expect(row.suppressedModel, isEmpty);
  });

  test('overlapping model fixes stay visible as suppressed proposals', () {
    final sample = _case();
    final row = _observe(
      sample,
      writing: [
        (2, 3, ['X']),
      ],
      model: [
        (2, 3, ['X']),
      ],
    );
    final summary = summarizeQuality([sample], [row]);
    expect(_incremental(summary)['added_exact_error_ids'], isEmpty);
    expect(_incremental(summary)['suppressed_model_finding_count'], 1);
    expect(row.acceptedModel, isEmpty);
    expect(row.suppressedModel.single.providerId, 'gector-de');
  });

  test('independent model damage loses a deterministic exact correction', () {
    final sample = _case();
    final row = _observe(
      sample,
      writing: [
        (2, 3, ['X']),
      ],
      model: [
        (0, 1, ['Z']),
      ],
    );
    final summary = summarizeQuality([sample], [row]);
    expect(_incremental(summary)['lost_exact_error_ids'], [sample.id]);
    expect(_lane(summary, 'combined')['changed_nonexact_error_ids'], [
      sample.id,
    ]);
  });

  test(
    'model false changes and new combined flags are measured on controls',
    () {
      final sample = _case(kind: 'clean', expected: 'abcd');
      final row = _observe(
        sample,
        model: [
          (2, 3, ['X']),
        ],
      );
      final summary = summarizeQuality([sample], [row]);
      expect(_incremental(summary)['model_changed_clean_ids'], [sample.id]);
      expect(_incremental(summary)['new_changed_clean_ids'], [sample.id]);
      expect(_incremental(summary)['new_flagged_clean_ids'], [sample.id]);
    },
  );

  test('summary rejects missing, duplicate, foreign and changed outcomes', () {
    final sample = _case();
    final row = _observe(sample);
    for (final rows in <List<QualityObservation>>[
      [],
      [row, row],
      [_observe(_case(id: 'foreign'))],
      [_observe(_case(input: 'different'))],
      [_observe(_case(expected: 'other expected'))],
    ]) {
      expect(() => summarizeQuality([sample], rows), throwsFormatException);
    }
    expect(() => summarizeQuality([], []), throwsFormatException);
    expect(
      () => summarizeQuality([sample, sample], [row]),
      throwsFormatException,
    );
  });

  test('observation rejects absent lanes or a different source snapshot', () {
    final sample = _case();
    final row = _observe(sample);
    expect(
      () => QualityObservation(sample, {'combined': row['combined']}),
      throwsFormatException,
    );
    final other = _observe(sample);
    expect(
      () => QualityObservation(sample, {
        ...row.outcomes,
        'model_only': other['model_only'],
      }),
      throwsFormatException,
    );
  });

  test('empty provider reports are incomplete operational evidence', () {
    final sample = _case(kind: 'clean', expected: 'abcd');
    final request = _observe(sample)['writing_only'].report.request;
    final empty = projectQualityReport(
      OfficeProofingReport(request: request, results: []),
    );
    final row = QualityObservation(sample, {
      for (final lane in qualityLanes) lane: empty,
    });
    final summary = summarizeQuality([sample], [row]);
    expect(empty.corrected, isNull);
    expect(empty.unsupported, isFalse);
    expect(summary['operational_passed'], isFalse);
    expect(_lane(summary, 'model_only')['unchanged_clean_count'], 0);
  });

  test('language cohorts keep supported control denominators explicit', () {
    final de = _case(id: 'de', kind: 'clean', expected: 'abcd');
    final ch = _case(
      id: 'ch',
      kind: 'clean',
      expected: 'abcd',
      locale: 'de-CH',
    );
    final summary = summarizeQuality(
      [de, ch],
      [
        _observe(de),
        _observe(ch, modelStatus: OfficeProofingStatus.unsupported),
      ],
    );
    final cohorts =
        summary['by_language']! as Map<String, Map<String, Object?>>;
    expect(summary['clean_count'], 2);
    expect(_lane(summary, 'model_only')['completed_clean_count'], 1);
    expect(cohorts['de-DE']!['clean_count'], 1);
    expect(cohorts['de-CH']!['clean_count'], 1);
    expect(_lane(cohorts['de-CH']!, 'model_only')['completed_clean_count'], 0);
    expect(_lane(cohorts['de-CH']!, 'model_only')['unsupported_only_count'], 1);
  });

  test('projection rejects invalid source edits instead of scoring them', () {
    final sample = _case();
    final request = _observe(sample)['writing_only'].report.request;
    final report = OfficeProofingReport(
      request: request,
      results: [
        OfficeProofingResult(
          request: request,
          providerId: 'bad',
          status: OfficeProofingStatus.success,
          findings: [
            OfficeProofingFinding(
              documentId: request.documentId,
              blockId: request.blockId,
              revision: request.revision,
              providerId: 'bad',
              start: 37,
              end: 38,
              originalText: 'wrong',
              ruleId: 'bad',
              message: 'Bad source.',
              category: OfficeProofingCategory.grammar,
              replacements: ['x'],
            ),
          ],
        ),
      ],
    );
    expect(() => projectQualityReport(report), throwsFormatException);
  });
}
