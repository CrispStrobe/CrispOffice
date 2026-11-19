#!/usr/bin/env python3
"""Read-only final portability delta and preservation review; no test execution."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import io
import json
from pathlib import Path
import tarfile

from audit_recovery import Audit, sha256
from audit_delta_47 import dart_tokens, events, static_constants

BASE = '47ce5f726f1a0b1f213b926162528533dc0a3aab'
HEAD = '0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9'
TREE = '37d9017ca00c5abe491819af3373e83b80a4da98'
MAIN = 'b070e228a749e22cc8ce2098029a76ab5fb8eccb'
FINAL = 'docs/validation/office-resume-main-20261119/final/'
CODE = 'packages/quds_arabic_morph/lib/src/morph_analysis.dart'
TEST = 'packages/quds_arabic_morph/test/arabic_morph_unit_test.dart'
ARABIC = 'packages/quds_office_engine/lib/src/proofing/arabic_extended_rules.dart'


def unpack(audit, name):
    stem = FINAL + name + '-evidence'
    data = audit.blob(HEAD, stem + '.tar.xz')
    index = json.loads(audit.blob(HEAD, stem + '.index.json'))
    audit.check(len(data) == index['bytes'] and sha256(data) == index['sha256'], name + ' archive identity')
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as tar:
        members = tar.getmembers()
        audit.check(all(m.isfile() for m in members), name + ' regular files')
        contents = {m.name: tar.extractfile(m).read() for m in members}
    expected = {m['path']: m for m in index['members']}
    audit.check(len(contents) == len(members) == len(expected) == index['member_count'], name + ' member counts')
    audit.check(set(contents) == set(expected), name + ' exact member coverage')
    for path, entry in expected.items():
        raw = contents[path]
        audit.check(len(raw) == entry['bytes'] and sha256(raw) == entry['sha256'], name + ' member hash: ' + path)
    return contents, {'name': name, 'bytes': len(data), 'sha256': sha256(data), 'members': len(members), 'status': index['status']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    audit = Audit(args.repo)
    audit.check(audit.text('rev-parse', HEAD + '^') == BASE, 'Expected source parent')
    audit.check(audit.text('rev-parse', HEAD + '^{tree}') == TREE, 'Expected source tree')
    paths = audit.text('diff', '--name-only', BASE, HEAD).splitlines()
    expected = {CODE, TEST, 'docs/PROOFING.md', FINAL + 'plan.json', FINAL + 'portability-attempt-47.md'}
    for name in ['portability-attempt-47', 'portability-development']:
        expected.update({FINAL + name + '-evidence.tar.xz', FINAL + name + '-evidence.index.json'})
    audit.check(set(paths) == expected, 'Exactly nine bounded changed paths')
    old_code, code = audit.blob(BASE, CODE), audit.blob(HEAD, CODE)
    old_test, test = audit.blob(BASE, TEST), audit.blob(HEAD, TEST)
    test_text = test.decode()
    start = test_text.index("    test('numeric feature text preserves fractions, signs and exponents'")
    end = test_text.index("    test('rejects malformed input'", start)
    audit.check(test_text[:start] + test_text[end:] == old_test.decode(), 'Original unit tests and -99.0 expectations retained verbatim')
    new_case = test_text[start:end]
    assertions = {
        'negative': '-99.0', 'positive': '7.0', 'zero': '0.0', 'negative_zero': '-0.0',
        'fraction': '-1.25', 'tiny': '1e-7', 'large_plain': '100000000000000000000.0',
        'exponent': '1e+21', 'text': '-99',
    }
    audit.check(all(f"'{k}': '{v}'" in new_case for k, v in assertions.items()), 'Numeric regression preserves exact expected representations')

    old_plan = json.loads(audit.blob(BASE, FINAL + 'plan.json'))
    plan = json.loads(audit.blob(HEAD, FINAL + 'plan.json'))
    audit.check(old_plan['groups'] == plan['groups'], 'Native suite selection unchanged')
    audit.check(audit.blob(BASE, FINAL + 'node-plan.json') == audit.blob(HEAD, FINAL + 'node-plan.json'), 'Node selection unchanged')
    for key in ['analysis', 'format']:
        audit.check(set(plan[key]) == set(old_plan[key]) | {CODE, TEST} and len(plan[key]) == len(set(plan[key])), 'Only decoder/unit added to static targets: ' + key)
    old_final = audit.tree(BASE, [FINAL])
    new_final = audit.tree(HEAD, [FINAL])
    changed_old_evidence = [p for p, value in old_final.items() if new_final.get(p) != value]
    audit.check(changed_old_evidence == [FINAL + 'plan.json'], 'All earlier evidence entries preserved apart from explicit plan update')

    stable_paths = [
        'packages/quds_office_engine/lib/src/proofing/arabic_grammar_rules.dart',
        'packages/quds_office_engine/lib/src/proofing/arabic_morphology.dart',
        'packages/quds_office_engine/lib/src/proofing/arabic_writing_rules.dart',
        'packages/quds_arabic_morph/',
    ]
    main_tree = audit.tree(MAIN, stable_paths)
    current_tree = audit.tree(HEAD, stable_paths)
    exceptions = sorted(p for p in set(main_tree) | set(current_tree) if main_tree.get(p) != current_tree.get(p))
    audit.check(exceptions == sorted([CODE, TEST]), 'Only two intentional morphology exceptions from captured main')
    arabic_before, arabic_after = audit.blob(BASE, ARABIC), audit.blob(HEAD, ARABIC)
    audit.check(arabic_before == arabic_after, 'Arabic rule implementation unchanged by portability repair')
    old_constants = static_constants(audit.blob(MAIN, ARABIC))
    current_constants = static_constants(arabic_after)
    audit.check(all(current_constants.get(k) == v for k, v in old_constants.items()), 'All 28 original Arabic constants/tables preserved')
    marker = b'  // ---------------------- word tables (S9 frozen, L3, L4, L7, S10)'
    main_arabic = audit.blob(MAIN, ARABIC)
    main_tables = main_arabic[main_arabic.index(marker):]
    tables = arabic_after[arabic_after.index(marker):]
    audit.check(main_tables == tables, 'Broad Arabic word tables byte-identical')

    rejected, rejected_archive = unpack(audit, 'portability-attempt-47')
    development, development_archive = unpack(audit, 'portability-development')
    proposal = json.loads(development['audit-final/morph-decimal-proposal/review.json'])
    snapshot_checks = []
    for path, before, after in [(CODE, old_code, code), (TEST, old_test, test)]:
        snap_before = development['audit-final/morph-decimal-proposal/before/' + path]
        snap_after = development['audit-final/morph-decimal-proposal/after/' + path]
        row = next(x for x in proposal['files'] if x['path'] == path)
        audit.check(snap_before == before and sha256(snap_before) == row['before_sha256'], 'Proposal before snapshot: ' + path)
        audit.check(sha256(snap_after) == row['after_sha256'] and dart_tokens(snap_after) == dart_tokens(after), 'Proposal after snapshot tokens: ' + path)
        snapshot_checks.append({'path': path, 'before_sha256': sha256(before), 'committed_sha256': sha256(after),
                                'reviewed_after_sha256': sha256(snap_after),
                                'reviewed_and_committed_tokens_identical': dart_tokens(snap_after) == dart_tokens(after)})
    doc_review = json.loads(development['audit-preservation/proofing-host-doc-review.json'])
    old_doc = audit.blob(BASE, 'docs/PROOFING.md').decode()
    new_doc = audit.blob(HEAD, 'docs/PROOFING.md').decode()
    replacement = ('Studio provides\nexplicit dictionary download/setup and registers spelling providers for\n'
                   'installed dictionaries; see **Studio wiring** below.')
    audit.check(' '.join(replacement.split()) == ' '.join(doc_review['new'].split()), 'Reviewed documentation sentence retained')
    audit.check(old_doc.count(doc_review['old']) == 1 and old_doc.replace(doc_review['old'], replacement, 1) == new_doc,
                'Documentation correction is exact and isolated')
    for row in doc_review['evidence']:
        audit.check(sha256(audit.blob(HEAD, row['path'])) == row['sha256'], 'Studio implementation supporting corrected docs: ' + row['path'])

    phase_reports, identities, frozen_manifest = [], {}, None
    for phase, plan_file in [('main', 'plan.json'), ('node', 'node-plan.json')]:
        prefix = 'qualification-final-' + phase + '/'
        receipt = json.loads(rejected[prefix + 'verification.json'])
        baseline_plan = json.loads(audit.blob(BASE, FINAL + plan_file))
        audit.check(receipt['source_commit'] == BASE, phase + ' original source attribution')
        audit.check(receipt['source_tree'] == audit.text('rev-parse', BASE + '^{tree}'), phase + ' original tree')
        audit.check(receipt['success'] is (phase == 'main'), phase + ' truthful success/rejection')
        audit.check(receipt['planned_groups'] == baseline_plan['groups'] and receipt['plan_sha256'] == sha256(audit.blob(BASE, FINAL + plan_file)), phase + ' original plan')
        for path, digest in receipt['manifest_sha256'].items():
            audit.check(sha256(rejected[prefix + path]) == digest, phase + ' preserved manifest: ' + path)
        source = json.loads(rejected[prefix + 'source-before.json'])
        environment = json.loads(rejected[prefix + 'environment-before.json'])
        audit.check(source == json.loads(rejected[prefix + 'source-after.json']), phase + ' source stable')
        audit.check(environment == json.loads(rejected[prefix + 'environment-after.json']), phase + ' runtime stable')
        audit.check(len(source) == receipt['source_input_count'] and len(environment) == receipt['runtime_input_count'], phase + ' inventory counts')
        if frozen_manifest is None:
            frozen_manifest = source
        else:
            audit.check(frozen_manifest == source, 'Both prior phases use the same source manifest')
        cases, group_reports = [], []
        for run in receipt['runs']:
            raw = rejected[prefix + run['log']]
            audit.check(sha256(raw) == run['log_sha256'], phase + ' log: ' + run['name'])
            compressed = rejected[prefix + run['compressed_log']]
            audit.check(sha256(compressed) == run['compressed_log_sha256'] and gzip.decompress(compressed) == raw, phase + ' compressed log: ' + run['name'])
            if 'cases_file' not in run:
                audit.check(run['exit_code'] == 0 and run['accepted'] is True, phase + ' static success: ' + run['name'])
                continue
            for field, digest_field in [('cases_file', 'cases_sha256'), ('errors_file', 'errors_sha256')]:
                audit.check(sha256(rejected[prefix + run[field]]) == run[digest_field], phase + ' ' + field + ': ' + run['name'])
            parsed = events(audit, raw, phase + ' ' + run['name'])
            failed = parsed['counts'].get('failure', 0) + parsed['counts'].get('error', 0)
            audit.check(parsed['counts'].get('success', 0) == run['passed'] and failed == run['failed'] and parsed['skipped'] == run['skipped'] == 0,
                        phase + ' raw/receipt totals: ' + run['name'])
            audit.check(parsed['terminal_success'] == (failed == 0) and (run['exit_code'] == 0) == (failed == 0), phase + ' termination: ' + run['name'])
            group = next(g for g in baseline_plan['groups'] if g['name'] == run['name'])
            def canonical(path):
                return path.split('/quds_office_suite/', 1)[1] if '/quds_office_suite/' in path else path if path.startswith('packages/') else group['cwd'] + '/' + path
            requested = {group['cwd'] + '/' + path for path in group['tests']}
            audit.check({canonical(p) for p in parsed['suites']} == requested == {canonical(c['suite']) for c in parsed['cases']}, phase + ' exact nonempty suites: ' + run['name'])
            for case in parsed['cases']:
                case['suite'] = canonical(case['suite'])
            cases.extend(parsed.pop('cases'))
            group_reports.append({'name': run['name'], **parsed})
        identities[phase] = {(c['suite'], c['name']) for c in cases}
        counts = dict(Counter(c['result'] for c in cases))
        audit.check(len(cases) == len(identities[phase]) and counts.get('success', 0) == receipt['passed'] and
                    counts.get('failure', 0) + counts.get('error', 0) == receipt['failed'], phase + ' full distinct totals')
        phase_reports.append({'phase': phase, 'success': receipt['success'], 'executions': len(cases), 'counts': counts,
                              'suites': len({p for p, _ in identities[phase]}), 'source_records': len(source),
                              'runtime_records': len(environment), 'analysis_paths': len(receipt['analysis_files']),
                              'format_paths': len(receipt['formatted_files']),
                              'failures': [c for c in cases if c['result'] != 'success'], 'groups': group_reports})
    audit.check(identities['node'] <= identities['main'], 'Node identities are repeats of native cases')
    source_check = audit.source_hashes(frozen_manifest, BASE)
    sdk_records = {key: value for key, value in environment.items()
                   if key.endswith('/lib/_internal/js_runtime/lib/js_number.dart')}
    audit.check(len(sdk_records) == 1 and next(iter(sdk_records.values())) == proposal['primary_sdk_evidence']['sha256'],
                'Primary JavaScript number evidence matches retained runtime')

    receipt_list = json.loads(development['diagnostics/morph-portability/receipts.json'])
    focus_reports = []
    for item in receipt_list:
        name = item.get('platform', item.get('name'))
        raw = development['diagnostics/morph-portability/' + name + '.jsonl']
        stderr = development['diagnostics/morph-portability/' + name + '.stderr.log']
        audit.check(item['base'] == BASE and item['exit_code'] == 0 and
                    sha256(raw) == item['log_sha256'] and sha256(stderr) == item['stderr_sha256'],
                    'Focused original receipt/log bindings: ' + name)
        audit.check(set(item['files']) == {CODE, TEST} and all(sha256(audit.blob(HEAD, p)) == digest for p, digest in item['files'].items()),
                    'Focused source bytes match new frozen source: ' + name)
        parsed = events(audit, raw, 'Focused portability ' + name)
        audit.check(parsed['terminal_success'] is True and parsed['counts'] == {'success': 9} and parsed['skipped'] == parsed['reporter_errors'] == 0,
                    'Focused nine-case preflight: ' + name)
        parsed.pop('cases')
        focus_reports.append({'platform': name, **parsed})

    report = {
        'schema': 1, 'audited_at_utc': datetime.now(timezone.utc).isoformat(),
        'source': HEAD, 'tree': TREE, 'parent': BASE, 'captured_main': MAIN,
        'auditor_sha256': sha256(Path(__file__).read_bytes()), 'exact_changed_paths': paths,
        'only_application_logic_change': CODE, 'original_unit_assertions_retained_verbatim': True,
        'numeric_expectations': assertions, 'reviewed_source_snapshots': snapshot_checks,
        'recorded_primary_javascript_number_source': sdk_records,
        'static_target_count': len(plan['analysis']), 'native_and_node_suite_selection_unchanged': True,
        'arabic_preservation': {'tracked_records_compared': len(main_tree),
                                'unchanged_from_captured_main': len(main_tree) - len(exceptions),
                                'intentional_morphology_exceptions': exceptions,
                                'extended_rules_identical_to_parent': arabic_before == arabic_after,
                                'original_static_constants_preserved': len(old_constants),
                                'word_table_section_bytes': len(tables), 'word_table_section_sha256': sha256(tables)},
        'prior_final_evidence_entries': len(old_final), 'prior_entries_changed': changed_old_evidence,
        'new_archives': [rejected_archive, development_archive],
        'retained_portability_attempt': {'source': BASE, 'accepted': False, 'phases': phase_reports,
                                         'total_executions': sum(p['executions'] for p in phase_reports),
                                         'distinct_case_identities': len(identities['main'] | identities['node']),
                                         'source_hash_verification': source_check,
                                         'contribution_to_current_accepted_totals': 0},
        'development_preflights': focus_reports, 'development_contribution_to_current_accepted_totals': 0,
        'documentation_correction': {'path': 'docs/PROOFING.md', 'sentence': ' '.join(replacement.split()),
                                     'implementation_hashes_match_review': True, 'acceptance_limits_unchanged': True},
        'review_findings': [
            'The numeric branch appends .0 only to finite text without decimal point or exponent; fractions and exponent notation retain the existing representation, and strings/null handling is untouched.',
            'The original -99.0 unit assertion remains unchanged. The new case covers signed integers, positive/negative zero, fractional values, exponent bounds and unchanged string values.',
            'Broad Arabic rule tables, T2 grammar and the morphology interface remain preserved. The intentional exceptions are the numeric decoder and its unit test, not dictionary data or linguistic tables.',
            'The Hunspell sentence now agrees with implemented Studio download/setup and installed-provider registration. The documentation correction is included in the frozen source.',
        ],
        'fresh_product_test_executions_by_auditor': 0, 'repository_mutations_by_auditor': 0,
        'github_actions_calls': 0, 'errors': audit.errors, 'passed': not audit.errors,
        'scope': 'Bounded source preservation and retained evidence audit. Fresh final qualification is a separate owning-session run.'}
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: report[k] for k in ['source','tree','static_target_count','arabic_preservation','errors','passed']}))
    print(json.dumps({'retained_phases': [{k: p[k] for k in ['phase','success','executions','counts','suites']} for p in phase_reports]}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
