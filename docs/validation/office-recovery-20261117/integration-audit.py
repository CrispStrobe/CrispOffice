#!/usr/bin/env python3
"""Read-only scoped ancestry/preservation audit of a published Git commit."""
from pathlib import Path
import collections
import datetime
import gzip
import hashlib
import json
import subprocess

REPO = Path('/workspace/scratch/f911bf3b5689/quds_office_suite')
BASE = Path('/workspace/scratch/f911bf3b5689/runtime-recovery')
TARGET = 'f29373cf29048a6a6b133e2e75628d58c4b2b23f'
REPORT = 'docs/validation/office-recovery-20261117/'

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])

def full(ref):
    return git('rev-parse', ref).decode().strip()

def content(ref, path):
    return git('show', ref + ':' + path)

def text(ref, path):
    return content(ref, path).decode()

def digest(data):
    return hashlib.sha256(data).hexdigest()

def tree(ref, *paths):
    rows = {}
    for row in git('ls-tree', '-r', '-l', '-z', ref, '--', *paths).split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        mode, kind, blob, size = meta.decode().split()
        assert kind == 'blob', (name, kind)
        rows[name.decode()] = {'mode': mode, 'git_blob': blob, 'bytes': int(size)}
    return rows

all_target = tree(TARGET)

def comparison(name, donor, scopes, exclusions=()):
    donor = full(donor)
    expected = tree(donor, *scopes)
    actual = tree(TARGET, *scopes)
    excluded = set(exclusions)
    paths = sorted((set(expected) | set(actual)) - excluded)
    mismatches = {p: {'donor': expected.get(p), 'target': actual.get(p)}
                  for p in paths if expected.get(p) != actual.get(p)}
    equal = {p: actual[p] for p in paths if p in actual and p in expected and actual[p] == expected[p]}
    return {'name': name, 'donor_commit': donor, 'scopes': scopes,
            'explicitly_excluded_paths': sorted(excluded),
            'scope_meaning': 'Exact path-set, Git blob bytes, and mode equality only; no whole-repository or historical import-closure equivalence is claimed.',
            'compared_paths': len(paths), 'equal_files': len(equal),
            'equal_bytes': sum(row['bytes'] for row in equal.values()),
            'files': equal, 'mismatches': mismatches, 'passed': not mismatches and bool(paths)}

snapshot_data = content(TARGET, REPORT + 'incoming-snapshot.json')
snapshot = json.loads(snapshot_data)
refs = [ref for observation in snapshot['observations'] for ref in observation['refs']]
ancestors = set(git('rev-list', TARGET).decode().splitlines())
ref_rows = [dict(ref, is_ancestor=ref['sha'] in ancestors) for ref in refs]
counts = collections.Counter((r['remote'], 'branches' if r['ref'].startswith('refs/heads/') else 'pull_heads') for r in refs)
ancestry = {'method': 'Each captured SHA is checked against the complete ancestor set from git rev-list of the explicit audited commit.',
            'snapshot_sha256': digest(snapshot_data), 'snapshot_observations': [
                {k: item[k] for k in ('remote', 'started_at', 'completed_at')} for item in snapshot['observations']],
            'named_references': len(refs), 'distinct_heads': len({r['sha'] for r in refs}),
            'counts': {remote + '_' + kind: count for (remote, kind), count in sorted(counts.items())},
            'refs': ref_rows, 'passed': len(refs) == 258 and all(row['is_ancestor'] for row in ref_rows)}

morph = '121f3be504a89e56bde40bda8f93f4e81d8c2503'
gector = '78cd772c35f46ebe6d0e2a63bafcd87e767593f3'
fidelity = 'd1738017afd3696adbd2e895678b1fa7d26065ec'
comparisons = [
    comparison('Completed fidelity evidence', fidelity, ['docs/validation/office-fidelity-lists-sections-20261117/']),
    comparison('Preserved prior resume evidence', '8eb01db0', ['docs/validation/office-fidelity-resume-20261117/']),
    comparison('Engine proofing production, generated data, manifests, generators and tests', morph, [
        'packages/quds_office_engine/lib/src/proofing/',
        'packages/quds_office_engine/third_party/proofing/',
        'packages/quds_office_engine/tool/proofing/',
        'packages/quds_office_engine/test/proofing/',
    ]),
    comparison('Complete optional GECToR package', gector, ['packages/quds_proofing_gector/']),
]
gector_tool_exceptions = [
    'tools/proofing/german_model/INCREMENTAL_QUALITY.md',
    'tools/proofing/german_model/README.md',
    'tools/proofing/german_model/evaluate_guarded_onnx.dart',
    'tools/proofing/german_model/onnx_probe_backend.py',
]
comparisons.append(comparison('Inherited GECToR tooling with explicit newer morphology additions', gector,
                              ['tools/proofing/german_model/'], gector_tool_exceptions))
comparisons.append(comparison('Four newer morphology tooling/doc paths', morph, gector_tool_exceptions))

manifest_checks = []
for path in ('packages/quds_office_engine/third_party/proofing/manifest.json',
             'packages/quds_office_engine/third_party/proofing/morphology_manifest.json'):
    manifest_bytes = content(TARGET, path)
    manifest = json.loads(manifest_bytes)
    files = {}
    for relative, expected in manifest['generated_files'].items():
        resolved = 'packages/quds_office_engine/' + relative
        actual = digest(content(TARGET, resolved))
        files[resolved] = {'expected_sha256': expected, 'actual_sha256': actual, 'passed': expected == actual}
    manifest_checks.append({'path': path, 'sha256': digest(manifest_bytes), 'generated_files': files,
                            'passed': bool(files) and all(row['passed'] for row in files.values())})

reconciliation_bytes = content(TARGET, REPORT + 'source-reconciliation.json')
reconciliation = json.loads(reconciliation_bytes)
shading = []
for row in reconciliation['shading_heads']:
    differing = git('diff', '--name-only', row['head'], reconciliation['main']).decode().splitlines()
    equals = full(row['head'] + '^{tree}') == full(reconciliation['main'] + '^{tree}')
    shading.append({'head': row['head'], 'whole_tree_equals_captured_main': equals,
                    'actual_differing_paths': differing,
                    'reported_differences_exact': differing == row['differing_paths'],
                    'no_production_or_test_difference': not any(p.startswith('packages/') for p in differing),
                    'passed': equals == row['whole_tree_equals_main'] and differing == row['differing_paths']
                              and not any(p.startswith('packages/') for p in differing)})
mirror_paths = reconciliation['shading_heads'][1]['differing_paths']
comparisons.append(comparison('Latest German evidence retained across shading vendor merge', morph, mirror_paths))
odp_path = reconciliation['odp_conflict']['path']
odp_donor, odp_actual = text(morph, odp_path), text(TARGET, odp_path)
assertion = '    expect(content, contains(\'<text:a xlink:href="https://example.com/deck">\'));\n'
odp = {'path': odp_path, 'donor_commit': morph,
       'assertion_occurrences_donor': odp_donor.count(assertion),
       'assertion_occurrences_target': odp_actual.count(assertion),
       'removal_inverse_exact': odp_donor.replace(assertion, '') == odp_actual.replace(assertion, ''),
       'meaning': 'The entire file differs solely by the location of one unchanged hyperlink assertion; all other bytes are identical.'}
odp['passed'] = odp['assertion_occurrences_donor'] == odp['assertion_occurrences_target'] == 1 and odp['removal_inverse_exact']

# Reverse only the documented deliberate test decisions, proving the old fixture
# and all other original source remain intact. No Dart code is executed.
frame_path = 'packages/quds_office_engine/test/odf_frame_extraction_test.dart'
frame_donor, frame_actual = text(gector, frame_path), text(TARGET, frame_path)
start = frame_actual.index('  for (final empty in [false, true]) {')
end = frame_actual.index("  test(\n    'hidden inline stories cannot expose frames or spend the text budget',", start)
added_frame_controls = frame_actual[start:end]
reconstructed = frame_actual[:start] + frame_actual[end:]
reconstructed = reconstructed.replace("'authored blanks survive while empty text-box anchors add no paragraph'", "'ordinary blanks empty frames and explicit whitespace remain distinct'", 1)
marker = "      expect(OfficeTextExtractor.extract(bytes, name: 'blank.odt').paragraphs, [\n"
assert reconstructed.count(marker) == 1
reconstructed = reconstructed.replace(marker, marker + "        '',\n", 1)
new_search = r"      expect(await officeSearchText(bytes, 'blank.odt', 65536), '\n\n \t\nX\n');"
old_search = "      expect(\n        await officeSearchText(bytes, 'blank.odt', 65536),\n" + r"        '\n\n\n \t\nX\n'," + "\n      );"
assert reconstructed.count(new_search) == 1
reconstructed = reconstructed.replace(new_search, old_search, 1)
frame_inverse = reconstructed == frame_donor

box_path = 'packages/quds_office_engine/test/odf_text_box_extraction_test.dart'
box_donor, box_actual = text(fidelity, box_path), text(TARGET, box_path)
helper_start = box_actual.index('Future<void> _expectBody(')
helper_end = box_actual.index('\nvoid main()', helper_start)
donor_helper_start = box_donor.index('Future<void> _expectBody(')
donor_helper_end = box_donor.index('\nvoid main()', donor_helper_start)
box_reconstructed = box_actual[:helper_start] + box_donor[donor_helper_start:donor_helper_end] + box_actual[helper_end:]
box_addition = '''      // Structured extraction retains the frame's table; text/search keep the
      // same visible paragraph sequence as the original regression.
      expectedParagraphs: ['AB'],
      expectedTables: [
        [
          ['Visible'],
        ],
      ],
'''
assert box_reconstructed.count(box_addition) == 1
box_reconstructed = box_reconstructed.replace(box_addition, '', 1)
box_inverse = box_reconstructed == box_donor

frame_review = {
    'reviewed_commit_only': TARGET,
    'uncommitted_writer_source_read': False,
    'document_path': REPORT + 'frame-reconciliation.md',
    'document_sha256': digest(content(TARGET, REPORT + 'frame-reconciliation.md')),
    'frame_test': {'path': frame_path, 'donor_commit': gector, 'donor_sha256': digest(frame_donor.encode()),
                   'target_sha256': digest(frame_actual.encode()), 'inverse_reconstruction_equals_donor': frame_inverse,
                   'exact_intentional_changes': ['Three added linked-frame controls (two table states and one hidden-wrapper case).',
                       'Rename mixed-blank case and remove only the synthetic empty text-box anchor from its expected paragraph/search sequence.'],
                   'added_controls_sha256': digest(added_frame_controls.encode())},
    'text_box_test': {'path': box_path, 'donor_commit': fidelity, 'donor_sha256': digest(box_donor.encode()),
                     'target_sha256': digest(box_actual.encode()), 'inverse_reconstruction_equals_donor': box_inverse,
                     'exact_intentional_changes': ['Extend helper to assert paragraphs and tables separately while retaining original read/search expectation.',
                         "For the one covered-cell fixture, assert paragraphs ['AB'] and table [[['Visible']]] while retaining text sequence AB\\nVisible."]},
    'production_reconciliation_scope': {
        'unchanged_from_gector': ['packages/quds_office_engine/lib/src/extract/office_search_text.dart'],
        'explicitly_reconciled': ['packages/quds_office_engine/lib/src/extract/office_text_extractor.dart',
                                  'packages/quds_office_engine/lib/src/odf/odf_text.dart'],
        'whole_odf_branch_equality_claimed': False,
    },
    'contract_assessment': 'The exact fixture inverses support the report: original fixture XML and visible nonempty text were retained. Structured table ownership and the synthetic-empty-anchor behavior are deliberate contract decisions, not unchanged expectations. This audit does not establish runtime correctness.',
    'passed': frame_inverse and box_inverse and content(TARGET, 'packages/quds_office_engine/lib/src/extract/office_search_text.dart') == content(gector, 'packages/quds_office_engine/lib/src/extract/office_search_text.dart'),
}

index = json.loads(content(TARGET, REPORT + 'integration-checks/index.json'))
log_checks = []
logs = {}
for row in index['files']:
    packed = content(TARGET, REPORT + 'integration-checks/' + row['archive'])
    raw = gzip.decompress(packed)
    logs[row['source_name']] = raw
    log_checks.append({'name': row['source_name'], 'compressed_sha256': digest(packed),
                       'bytes': len(raw), 'sha256': digest(raw),
                       'passed': len(raw) == row['size'] and digest(raw) == row['sha256']})
events = [json.loads(line) for line in logs['focused-final.jsonl'].decode().splitlines() if line.strip().startswith('{')]
starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
suites = {e['suite']['id']: e['suite'] for e in events if e.get('type') == 'suite'}
visible = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
by_suite = collections.Counter(Path(suites[starts[e['testID']]['suiteID']]['path']).name for e in visible if e.get('result') == 'success' and not e.get('skipped'))
errors = [e for e in events if e.get('type') == 'error']
done = [e for e in events if e.get('type') == 'done']
merge_logs = {'kind': 'Reconstruction of retained development logs only; this is not a new test execution or frozen-source qualification.',
              'log_integrity': log_checks, 'successful_case_executions_by_file': dict(sorted(by_suite.items())),
              'visible_completed_tests': len(visible), 'errors': len(errors),
              'skips': sum(bool(e.get('skipped')) for e in visible),
              'failures': sum(e.get('result') != 'success' for e in visible),
              'terminal_success': bool(done and done[-1].get('success')),
              'initial_analysis_failure_retained': b'187 issues found' in logs['analyze-final.log'],
              'corrected_analysis_success_retained': b'No issues found' in logs['analyze-packages.log'],
              'source_bound_qualification_claimed': False}
merge_logs['passed'] = all(row['passed'] for row in log_checks) and len(visible) == 99 and len(suites) == 6 and not errors and not merge_logs['skips'] and not merge_logs['failures'] and merge_logs['terminal_success'] and merge_logs['initial_analysis_failure_retained'] and merge_logs['corrected_analysis_success_retained']

clarifications = [
    {'severity': 'scope clarification', 'subject': 'GECToR tooling donor',
     'detail': 'The optional GECToR package is exactly 78cd772c. The tools/proofing/german_model directory combines its unchanged inherited files with four explicitly listed newer morphology121 files; it is not wholly equal to 78cd772c.'},
    {'severity': 'documentation precision', 'subject': 'Namespace statement in frame-reconciliation.md',
     'detail': 'Frame and inline-story traversal checks namespace identity. The inherited top-level OfficeTextExtractor table/table-row/table-cell streaming dispatch still tests local names, so the unqualified sentence "Namespace identity is required" should be scoped to the frame/inline paths reviewed here.'},
    {'severity': 'documentation precision', 'subject': 'UTF-8 separator budget statement in frame-reconciliation.md',
     'detail': 'Search/readOdfText charges emitted paragraph separators. Generic structured extraction charges decoded content and separators inside cells, while wrappers and block separators later added by OfficeTextExtract.plainString remain outside that budget, as OdfTextBudget already documents. Keep that distinction if describing the contract broadly.'},
]
passed = ancestry['passed'] and all(row['passed'] for row in comparisons) and all(row['passed'] for row in manifest_checks) and all(row['passed'] for row in shading) and odp['passed'] and frame_review['passed'] and merge_logs['passed']
audit = {
    'schema': 1, 'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'audited_commit': TARGET, 'audited_tree': full(TARGET + '^{tree}'),
    'method': 'Independent read-only Git-object comparison at an explicit published checkpoint. Working-tree and uncommitted writer bytes were not used.',
    'runtime_tests_executed': False, 'github_actions_queried_or_awaited': False,
    'whole_repository_or_historical_import_closure_equivalence_claimed': False,
    'ancestry': ancestry, 'scoped_equalities': comparisons,
    'generated_manifest_checks': manifest_checks,
    'source_reconciliation': {'document_sha256': digest(reconciliation_bytes), 'shading_mirrors': shading, 'odp_assertion': odp},
    'frame_expectations': frame_review, 'retained_development_log_review': merge_logs,
    'clarifications': clarifications, 'all_requested_structural_checks_passed': passed,
    'status': 'passed_with_scope_clarifications' if passed else 'failed',
    'audit_script_sha256': digest(Path(__file__).read_bytes()),
}
(BASE / 'integration-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
print(json.dumps({'status': audit['status'], 'references': ancestry['named_references'], 'distinct_heads': ancestry['distinct_heads'],
                  'equalities': [{k: row[k] for k in ('name','equal_files','equal_bytes','passed')} for row in comparisons],
                  'manifest_generated_files': sum(len(row['generated_files']) for row in manifest_checks),
                  'frame_inverse_checks_passed': frame_review['passed'], 'retained_merge_logs_passed': merge_logs['passed']}))
