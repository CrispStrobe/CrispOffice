// Workspace qualification helpers, not a separately published package.
// ignore_for_file: depend_on_referenced_packages

import 'package:quds_office_engine/src/proofing/office_proofing.dart';

const qualityLanes = <String>[
  'writing_only',
  'deterministic',
  'model_only',
  'combined',
];
const qualityProjectionPolicy =
    'Single pass over the original snapshot; first replacement only; '
    'provider/result order gives precedence; overlapping proposals and '
    'advisories without replacements are skipped explicitly. Insertions '
    'conflict at either endpoint. Expected text never selects a replacement. '
    'Incomplete reports have no projected correction.';

final class QualityCase {
  const QualityCase({
    required this.id,
    required this.kind,
    required this.input,
    required this.expected,
    required this.locale,
    this.category,
    this.pairId,
    this.declaredModelStatus,
  });
  final String id, kind, input, expected, locale;
  final String? category, pairId, declaredModelStatus;
  String get language => normalizeProofingLanguage(locale);
  String get expectedModelStatus =>
      declaredModelStatus ?? (language == 'de-DE' ? 'success' : 'unsupported');
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'input': input,
    'expected': expected,
    'locale': locale,
    'language': language,
    'expected_model_status': expectedModelStatus,
    if (category != null) 'category': category,
    if (pairId != null) 'pair_id': pairId,
  };
}

List<QualityCase> parseQualityCases(Object? value) {
  if (value is! List<Object?> || value.isEmpty || value.length > 2000) {
    throw const FormatException('Expected 1..2000 declared quality cases.');
  }
  final ids = <String>{};
  return [
    for (final raw in value)
      (() {
        if (raw is! Map<String, Object?> ||
            raw.keys.any(
              (key) => !const {
                'id',
                'kind',
                'input',
                'expected',
                'locale',
                'category',
                'pair_id',
                'expected_model_status',
              }.contains(key),
            )) {
          throw const FormatException('Invalid quality case fields.');
        }
        final id = _text(raw['id'], 'id');
        final kind = _text(raw['kind'], 'kind');
        final input = _text(raw['input'], 'input');
        if (!ids.add(id) || !const {'error', 'clean'}.contains(kind)) {
          throw const FormatException('Duplicate case ID or invalid kind.');
        }
        final expected = kind == 'error' || raw.containsKey('expected')
            ? _text(raw['expected'], 'expected')
            : input;
        if ((kind == 'error') == (expected == input)) {
          throw const FormatException(
            'Case kind disagrees with expected text.',
          );
        }
        final sample = QualityCase(
          id: id,
          kind: kind,
          input: input,
          expected: expected,
          locale: raw.containsKey('locale')
              ? _text(raw['locale'], 'locale')
              : 'de-DE',
          category: raw.containsKey('category')
              ? _text(raw['category'], 'category')
              : null,
          pairId: raw['pair_id'] != null
              ? _text(raw['pair_id'], 'pair_id')
              : null,
          declaredModelStatus: raw.containsKey('expected_model_status')
              ? _text(raw['expected_model_status'], 'expected_model_status')
              : null,
        );
        if (sample.expectedModelStatus !=
            (sample.language == 'de-DE' ? 'success' : 'unsupported')) {
          throw const FormatException(
            'Declared model status disagrees with locale policy.',
          );
        }
        return sample;
      })(),
  ];
}

String _text(Object? value, String field) {
  if (value is! String || value.trim().isEmpty || !_wellFormed(value)) {
    throw FormatException('$field must be nonempty well-formed text.');
  }
  return value;
}

bool _wellFormed(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i == text.length) return false;
      final next = text.codeUnitAt(i);
      if (next < 0xdc00 || next > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

Map<String, Object?> qualityFinding(OfficeProofingFinding finding) => {
  'provider_id': finding.providerId,
  'rule_id': finding.ruleId,
  'category': finding.category.name,
  'start': finding.start,
  'end': finding.end,
  'original': finding.originalText,
  'replacements': finding.replacements,
  'message': finding.message,
};

final class QualityProjection {
  QualityProjection._(this.report, this.corrected, this.accepted, this.skipped);
  final OfficeProofingReport report;
  final String? corrected;
  final List<OfficeProofingFinding> accepted;
  final List<({OfficeProofingFinding finding, String reason})> skipped;
  bool get changed => corrected != null && corrected != report.request.text;
  bool get flagged => report.findings.isNotEmpty;
  bool exact(String expected) => report.complete && corrected == expected;
  bool get unsupported =>
      report.results.isNotEmpty &&
      report.results.every(
        (result) => result.status == OfficeProofingStatus.unsupported,
      );
  bool get operationalFailure => report.results.any(
    (result) =>
        result.status == OfficeProofingStatus.failed ||
        result.status == OfficeProofingStatus.unavailable,
  );
  Map<String, Object?> toJson(String expected) => {
    'complete': report.complete,
    'clean_report': report.isClean,
    'flagged': flagged,
    'corrected': corrected,
    'changed': changed,
    'exact_expected': exact(expected),
    'results': [
      for (final result in report.results)
        {
          'provider_id': result.providerId,
          'status': result.status.name,
          'message': result.message,
          'findings': result.findings.map(qualityFinding).toList(),
        },
    ],
    'displayed_findings': report.findings.map(qualityFinding).toList(),
    'projected_findings': [
      for (final finding in accepted)
        {...qualityFinding(finding), 'replacement_index': 0},
    ],
    'skipped_findings': [
      for (final item in skipped)
        {...qualityFinding(item.finding), 'reason': item.reason},
    ],
  };
}

/// This diagnostic has no access to gold text or model confidence.
QualityProjection projectQualityReport(OfficeProofingReport report) {
  final accepted = <OfficeProofingFinding>[];
  final skipped = <({OfficeProofingFinding finding, String reason})>[];
  final request = report.request;
  for (final result in report.results) {
    if (!identical(result.request, request)) {
      throw const FormatException('Projection received a misbound result.');
    }
    if (result.status != OfficeProofingStatus.success) {
      if (result.findings.isNotEmpty) {
        throw const FormatException('Unsuccessful result contains findings.');
      }
      continue;
    }
    for (final finding in result.findings) {
      final start = finding.start - request.startOffset;
      final end = finding.end - request.startOffset;
      if (start < 0 ||
          end < start ||
          end > request.text.length ||
          request.text.substring(start, end) != finding.originalText ||
          finding.replacements.any((text) => !_wellFormed(text))) {
        throw const FormatException(
          'Projection received an invalid source edit.',
        );
      }
      final reason = !report.complete
          ? 'incomplete-report'
          : finding.replacements.isEmpty
          ? 'no-replacement-advisory'
          : accepted.any((previous) => _conflicts(previous, finding))
          ? 'overlap-with-earlier-projection'
          : null;
      if (reason == null) {
        accepted.add(finding);
      } else {
        skipped.add((finding: finding, reason: reason));
      }
    }
  }
  String? corrected;
  if (report.complete) {
    corrected = request.text;
    final ordered = accepted.toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    for (final finding in ordered) {
      corrected = corrected!.replaceRange(
        finding.start - request.startOffset,
        finding.end - request.startOffset,
        finding.replacements.first,
      );
    }
  }
  return QualityProjection._(
    report,
    corrected,
    List.unmodifiable(accepted),
    List.unmodifiable(skipped),
  );
}

bool _conflicts(OfficeProofingFinding a, OfficeProofingFinding b) {
  if (a.start == a.end) return a.start >= b.start && a.start <= b.end;
  if (b.start == b.end) return b.start >= a.start && b.start <= a.end;
  return a.start < b.end && b.start < a.end;
}

final class QualityObservation {
  QualityObservation(this.sample, Map<String, QualityProjection> outcomes)
    : outcomes = Map.unmodifiable(outcomes) {
    if (outcomes.length != qualityLanes.length ||
        !qualityLanes.every(outcomes.containsKey)) {
      throw const FormatException(
        'Every quality lane is required exactly once.',
      );
    }
    final request = outcomes.values.first.report.request;
    if (request.text != sample.input ||
        request.language != sample.language ||
        outcomes.values.any((o) => !identical(o.report.request, request))) {
      throw const FormatException(
        'Quality lanes do not share their case input.',
      );
    }
  }
  final QualityCase sample;
  final Map<String, QualityProjection> outcomes;
  QualityProjection operator [](String lane) => outcomes[lane]!;
  List<OfficeProofingFinding> get acceptedModel => [
    for (final result in this['combined'].report.results)
      if (this['model_only'].report.results.any(
        (modelResult) => modelResult.providerId == result.providerId,
      ))
        ...result.findings,
  ];
  List<OfficeProofingFinding> get suppressedModel => [
    for (final finding in this['model_only'].report.findings)
      if (!acceptedModel.contains(finding)) finding,
  ];
  Map<String, Object?> toJson() => {
    ...sample.toJson(),
    'start_offset': this['deterministic'].report.request.startOffset,
    'outcomes': {
      for (final entry in outcomes.entries)
        entry.key: entry.value.toJson(sample.expected),
    },
    'accepted_model_findings': acceptedModel.map(qualityFinding).toList(),
    'suppressed_model_findings': suppressedModel.map(qualityFinding).toList(),
  };
}

Map<String, Object?> summarizeQuality(
  List<QualityCase> cases,
  List<QualityObservation> observations, {
  bool includeLanguageCohorts = true,
}) {
  if (cases.isEmpty) throw const FormatException('Quality corpus is empty.');
  final expected = {for (final sample in cases) sample.id: sample};
  final observed = <String>{};
  for (final row in observations) {
    final original = expected[row.sample.id];
    if (!observed.add(row.sample.id) ||
        original == null ||
        original.input != row.sample.input ||
        original.expected != row.sample.expected ||
        original.kind != row.sample.kind ||
        original.locale != row.sample.locale ||
        original.expectedModelStatus != row.sample.expectedModelStatus) {
      throw const FormatException('Duplicate, foreign or altered quality row.');
    }
  }
  if (expected.length != cases.length || observed.length != expected.length) {
    throw const FormatException(
      'Quality coverage is incomplete or duplicated.',
    );
  }
  List<String> ids(bool Function(QualityObservation) matches) => [
    for (final row in observations)
      if (matches(row)) row.sample.id,
  ];
  bool comparable(QualityObservation row) =>
      row['model_only'].report.complete &&
      row['deterministic'].report.complete &&
      row['combined'].report.complete;
  final summary = <String, Object?>{
    'case_count': cases.length,
    'error_count': cases.where((sample) => sample.kind == 'error').length,
    'clean_count': cases.where((sample) => sample.kind == 'clean').length,
    'lanes': <String, Map<String, Object?>>{
      for (final lane in qualityLanes)
        lane: <String, Object?>{
          'completed_ids': ids((r) => r[lane].report.complete),
          'completed_error_ids': ids(
            (r) => r.sample.kind == 'error' && r[lane].report.complete,
          ),
          'completed_clean_ids': ids(
            (r) => r.sample.kind == 'clean' && r[lane].report.complete,
          ),
          'exact_error_ids': ids(
            (r) => r.sample.kind == 'error' && r[lane].exact(r.sample.expected),
          ),
          'changed_nonexact_error_ids': ids(
            (r) =>
                r.sample.kind == 'error' &&
                r[lane].changed &&
                !r[lane].exact(r.sample.expected),
          ),
          'changed_clean_ids': ids(
            (r) => r.sample.kind == 'clean' && r[lane].changed,
          ),
          'flagged_clean_ids': ids(
            (r) => r.sample.kind == 'clean' && r[lane].flagged,
          ),
          'unchanged_clean_ids': ids(
            (r) =>
                r.sample.kind == 'clean' &&
                r[lane].report.complete &&
                !r[lane].changed,
          ),
          'unflagged_clean_ids': ids(
            (r) => r.sample.kind == 'clean' && r[lane].report.isClean,
          ),
          'unsupported_only_ids': ids((r) => r[lane].unsupported),
          'incomplete_ids': ids((r) => !r[lane].report.complete),
          'operational_failure_ids': ids((r) => r[lane].operationalFailure),
        },
    },
    'incremental': {
      'comparable_ids': ids(comparable),
      'not_comparable_ids': ids((r) => !comparable(r)),
      'added_exact_error_ids': ids(
        (r) =>
            comparable(r) &&
            r.sample.kind == 'error' &&
            !r['deterministic'].exact(r.sample.expected) &&
            r['combined'].exact(r.sample.expected),
      ),
      'lost_exact_error_ids': ids(
        (r) =>
            comparable(r) &&
            r.sample.kind == 'error' &&
            r['deterministic'].exact(r.sample.expected) &&
            !r['combined'].exact(r.sample.expected),
      ),
      'model_unique_exact_error_ids': ids(
        (r) =>
            comparable(r) &&
            r.sample.kind == 'error' &&
            r['model_only'].exact(r.sample.expected) &&
            !r['deterministic'].exact(r.sample.expected),
      ),
      'new_changed_clean_ids': ids(
        (r) =>
            comparable(r) &&
            r.sample.kind == 'clean' &&
            !r['deterministic'].changed &&
            r['combined'].changed,
      ),
      'new_flagged_clean_ids': ids(
        (r) =>
            comparable(r) &&
            r.sample.kind == 'clean' &&
            !r['deterministic'].flagged &&
            r['combined'].flagged,
      ),
      'model_changed_clean_ids': ids(
        (r) => r.sample.kind == 'clean' && r['model_only'].changed,
      ),
      'accepted_model_finding_count': observations.fold<int>(
        0,
        (n, r) => n + r.acceptedModel.length,
      ),
      'suppressed_model_finding_count': observations.fold<int>(
        0,
        (n, r) => n + r.suppressedModel.length,
      ),
    },
    'operational_passed': observations.every(
      (row) => row.outcomes.values.every(
        (outcome) =>
            !outcome.operationalFailure &&
            (outcome.report.complete || outcome.unsupported),
      ),
    ),
  };
  final lanes = summary['lanes']! as Map<String, Map<String, Object?>>;
  for (final metrics in lanes.values) {
    for (final entry in metrics.entries.toList()) {
      if (entry.key.endsWith('_ids')) {
        metrics['${entry.key.substring(0, entry.key.length - 4)}_count'] =
            (entry.value! as List<String>).length;
      }
    }
  }
  if (includeLanguageCohorts) {
    summary['by_language'] = {
      for (final language in cases.map((sample) => sample.language).toSet())
        language: summarizeQuality(
          cases.where((sample) => sample.language == language).toList(),
          observations.where((row) => row.sample.language == language).toList(),
          includeLanguageCohorts: false,
        ),
    };
  }
  return summary;
}
