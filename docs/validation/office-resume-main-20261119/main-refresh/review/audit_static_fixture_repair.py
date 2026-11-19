#!/usr/bin/env python3
"""Read-only exact repair and evidence audit; never launches product tests."""
import argparse
import hashlib
import io
import json
import pathlib
import re
import subprocess
import tarfile

BASE = '08336f71b273eb81a4f2652328ad1c91c08e048c'
TARGET = '0f16754c278aa83cc79d5777e5b45d3f739e5469'
TREE = '83d24b0ef7a82f9dfb65dc4e0b2015ee743f237c'
MAIN = '76fe761f1c97c31ca8d8add405aa54c436a336aa'
ROOT = 'docs/validation/office-resume-main-20261119/'
REFRESH = ROOT + 'main-refresh/'
EXAMPLE = 'packages/quds_office_editor/example/'
FIXTURE = EXAMPLE + 'test/support/studio_mail_fixture.dart'
OPERATION = EXAMPLE + 'test/studio_mail_operation_test.dart'
REPAIRS = {FIXTURE, OPERATION}
OLD_EXCEPTIONS = {
    'packages/quds_arabic_morph/lib/src/morph_analysis.dart',
    'packages/quds_arabic_morph/test/arabic_morph_unit_test.dart',
    EXAMPLE + 'lib/studio_mail_native.dart',
    EXAMPLE + 'lib/studio_strings.dart',
    EXAMPLE + 'test/studio_mail_test.dart',
    EXAMPLE + 'test/studio_review_status_test.dart',
    'packages/quds_office_editor/lib/src/embed/office_controller.dart',
    'packages/quds_office_editor/test/word_text_proofing_controls_test.dart',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    def git(*values):
        return subprocess.check_output(['git', '--no-lazy-fetch', '-C', args.repo, *values])

    def tree(rev):
        result = {}
        for row in git('ls-tree', '-r', '-z', rev).split(b'\0'):
            if not row:
                continue
            info, path = row.split(b'\t', 1)
            result[path.decode()] = info.decode().split()
        return result

    def body(mapping, path):
        return git('cat-file', 'blob', mapping[path][2])

    def product(path):
        return path.startswith(('packages/', 'third_party/'))

    def evidence(path):
        return path.startswith(('docs/validation/', 'docs/evidence/'))

    def differences(before, after, predicate=lambda p: True):
        return [{'path': p, 'before': before.get(p), 'after': after.get(p)}
                for p in sorted(set(before) | set(after))
                if predicate(p) and before.get(p) != after.get(p)]

    base, current, incoming = tree(BASE), tree(TARGET), tree(MAIN)
    checks = []

    def check(name, passed, **detail):
        checks.append({'name': name, 'passed': bool(passed), **detail})

    actual_tree = git('rev-parse', TARGET + '^{tree}').decode().strip()
    parents = git('show', '-s', '--format=%P', TARGET).decode().strip().split()
    check('exact_frozen_tree_and_parent', actual_tree == TREE and parents == [BASE])
    delta = differences(base, current)
    source_delta = differences(base, current, lambda p: not evidence(p))
    check('only_two_test_paths_change_outside_evidence',
          {r['path'] for r in source_delta} == REPAIRS)
    check('application_code_and_all_other_non_evidence_objects_preserved', all(
        current.get(p) == entry for p, entry in base.items() if not evidence(p) and p not in REPAIRS))
    expected_evidence = {REFRESH + name for name in [
        'README.md', 'attempt-083-evidence.index.json', 'attempt-083-evidence.tar.xz',
        'attempt-083.md', 'static-fixture-repair-evidence.index.json',
        'static-fixture-repair-evidence.tar.xz']}
    check('exact_eight_path_total_delta', {r['path'] for r in delta} == REPAIRS | expected_evidence)

    old_fixture, new_fixture = body(base, FIXTURE), body(current, FIXTURE)
    before_import = b"import 'package:quds_office_studio/studio_mail.dart';"
    after_import = b"import 'package:quds_office_studio/studio_mail_native.dart';"
    check('fixture_exact_single_native_import_replacement', old_fixture.count(before_import) == 1 and
          new_fixture == old_fixture.replace(before_import, after_import))
    old_operation, new_operation = body(base, OPERATION), body(current, OPERATION)
    annotation = (b'// These print probes verify that protocol output stays inside the private zone.\n'
                  b'// ignore_for_file: avoid_print\n\n')
    check('operation_test_executable_body_and_assertions_exact', new_operation == annotation + old_operation)
    check('all_twenty_intentional_print_probes_retained',
          len(re.findall(rb'\bprint\(', old_operation)) == len(re.findall(rb'\bprint\(', new_operation)) == 20)

    main_delta = differences(incoming, current, product)
    check('exact_ten_reviewed_exceptions_to_main',
          {r['path'] for r in main_delta} == OLD_EXCEPTIONS | REPAIRS)
    check('original_eight_exceptions_exactly_preserved_from_083',
          all(current.get(p) == base.get(p) for p in OLD_EXCEPTIONS))
    changed_old_evidence = [r for r in differences(base, current, evidence) if r['before'] is not None]
    check('only_prior_evidence_overview_changed',
          [r['path'] for r in changed_old_evidence] == [REFRESH + 'README.md'])
    check('prior_overview_text_retained_with_appended_rejection_note',
          body(current, REFRESH + 'README.md').startswith(body(base, REFRESH + 'README.md')))
    for path in [ROOT + 'final/plan.json', REFRESH + 'native-plan.json', REFRESH + 'node-plan.json',
                 REFRESH + 'incoming-overview-76fe761f.md', REFRESH + 'incoming-final-plan-76fe761f.json']:
        check('plan_or_historical_copy_exact:' + path, current.get(path) == base.get(path))
    final_records = {p: v for p, v in base.items() if p.startswith(ROOT + 'final/')}
    check('all_39_qualified_publication_files_preserved', len(final_records) == 39 and
          final_records == {p: v for p, v in current.items() if p.startswith(ROOT + 'final/')})
    relocations = {ROOT + 'README.md': REFRESH + 'incoming-overview-76fe761f.md',
                   ROOT + 'final/plan.json': REFRESH + 'incoming-final-plan-76fe761f.json'}
    main_evidence = {p: v for p, v in incoming.items() if evidence(p)}
    check('all_incoming_main_evidence_preserved_at_original_or_exact_copy', all(
        current.get(relocations.get(p, p)) == value for p, value in main_evidence.items()))
    for path in ['pubspec.yaml', 'pubspec.lock']:
        check('root_dependency_manifest_unchanged:' + path, current.get(path) == base.get(path))

    archives = {}
    member_maps = {}
    for name, expected_count, status in [
        ('attempt-083-evidence', 62, 'rejected-strict-analysis'),
        ('static-fixture-repair-evidence', 4, 'development-static-preflight')]:
        index = json.loads(body(current, REFRESH + name + '.index.json'))
        archive = body(current, REFRESH + name + '.tar.xz')
        check(name + ':archive_binding_and_hash', index['source_commit'] == BASE and index['status'] == status and
              index['archive'] == name + '.tar.xz' and index['bytes'] == len(archive) and index['sha256'] == sha(archive))
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as tar:
            members = {m.name: tar.extractfile(m).read() for m in tar if m.isfile()}
        manifest = {row['path']: row for row in index['members']}
        check(name + ':exact_member_inventory_and_hashes',
              len(members) == len(index['members']) == index['member_count'] == expected_count and
              set(members) == set(manifest) and all(
                  len(data) == manifest[path]['bytes'] and sha(data) == manifest[path]['sha256']
                  for path, data in members.items()))
        member_maps[name] = members
        archives[name] = {'bytes': len(archive), 'sha256': sha(archive), 'members': len(members), 'status': status}

    attempt = member_maps['attempt-083-evidence']
    verification = json.loads(attempt['qualification-refresh-main/verification.json'])
    check('retained_083_attempt_remains_rejected', verification['source_commit'] == BASE and
          verification['passed'] == 382 and not verification['success'])
    raw_groups = {}
    observed_suites = set()
    for name, data in attempt.items():
        if not name.startswith('qualification-refresh-main/checks/') or not name.endswith('.jsonl'):
            continue
        events = [json.loads(line) for line in data.splitlines() if line.strip()]
        starts = {event['test']['id']: event for event in events if event['type'] == 'testStart'}
        completions = [event for event in events if event['type'] == 'testDone']
        visible = [event for event in completions if not event.get('hidden', False)]
        terminal = [event for event in events if event['type'] == 'done']
        suites = [event['suite']['path'] for event in events if event['type'] == 'suite']
        observed_suites.update(suites)
        check('retained_raw_group_complete:' + name, len(starts) == len(completions) and
              set(starts) == {event['testID'] for event in completions} and
              all(event['result'] == 'success' and not event['skipped'] for event in completions) and
              len(terminal) == 1 and terminal[0]['success'] and
              not any(event['type'] == 'error' for event in events))
        raw_groups[name] = {'visible_cases': len(visible), 'suites': len(suites)}
    native_plan = json.loads(body(current, REFRESH + 'native-plan.json'))
    node_plan = json.loads(body(current, REFRESH + 'node-plan.json'))
    check('retained_083_native_382_cases_25_suites', len(raw_groups) == 8 and
          sum(group['visible_cases'] for group in raw_groups.values()) == 382 and len(observed_suites) == 25)
    analysis = attempt['qualification-refresh-main/checks/analysis.log'].decode()
    check('retained_analysis_failure_is_one_fixture_error_and_twenty_print_infos',
          analysis.count(' - undefined_named_parameter') == 1 and analysis.count(' - avoid_print') == 20 and
          '21 issues found.' in analysis)

    repair = member_maps['static-fixture-repair-evidence']
    receipt = json.loads(repair['diagnostics/static-fixture-repair/receipt.json'])
    log = repair['diagnostics/static-fixture-repair/analysis.log']
    check('preflight_exact_45_path_strict_analysis_scope', receipt['base'] == BASE and receipt['exit_code'] == 0 and
          receipt['command'][1:4] == ['analyze', '--fatal-infos', '--fatal-warnings'] and
          receipt['command'][4:] == native_plan['analysis'] and len(native_plan['analysis']) == 45 and
          receipt['log_sha256'] == sha(log) and b'No issues found!' in log)
    check('preflight_source_hashes_match_exact_two_committed_repairs',
          set(receipt['source_files']) == REPAIRS and all(
              row['before_sha256'] == sha(body(base, path)) and row['after_sha256'] == sha(body(current, path))
              for path, row in receipt['source_files'].items()))

    output = {
        'status': 'pass' if all(row['passed'] for row in checks) else 'fail',
        'source_commit': TARGET, 'source_tree': actual_tree, 'parents': parents, 'baseline_source': BASE,
        'incoming_main': MAIN, 'source_delta': source_delta, 'all_changed_paths': delta,
        'incoming_package_and_third_party_records': sum(product(p) for p in incoming),
        'incoming_package_and_third_party_records_exact': sum(product(p) and current.get(p) == v for p, v in incoming.items()),
        'reviewed_exceptions_to_main': main_delta,
        'incoming_evidence_records': len(main_evidence),
        'incoming_evidence_exact_original_paths': sum(current.get(p) == v for p, v in main_evidence.items()),
        'incoming_evidence_exact_relocations': relocations,
        'previous_qualified_final_records_preserved': len(final_records),
        'native_suite_count': sum(len(group['tests']) for group in native_plan['groups']),
        'node_suite_count': sum(len(group['tests']) for group in node_plan['groups']),
        'analysis_path_count': len(native_plan['analysis']),
        'preserved_rejected_083_runtime_groups': raw_groups, 'new_archives': archives,
        'checks': checks,
        'qualification_limits': [
            'The 382 passed native cases belong to rejected source 08336f71; they do not qualify this repaired source.',
            'The strict analysis preflight is development evidence; final 0f16754c gates are separately attributed.',
            'No product tests, index/source edits, tree writes, fetches, or Actions requests performed by this auditor.',
            'Original main-refresh-preservation-08336f71.json is retained unchanged; this is a supplemental repair review.'],
    }
    pathlib.Path(args.output).write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({'status': output['status'], 'source_commit': TARGET, 'source_tree': actual_tree,
                      'checks': len(checks), 'failed_checks': [row for row in checks if not row['passed']],
                      'product_exceptions': len(main_delta), 'preserved_rejected_native_cases': 382,
                      'new_archive_members': sum(row['members'] for row in archives.values()), 'report': args.output}))
    raise SystemExit(0 if output['status'] == 'pass' else 1)


if __name__ == '__main__':
    main()
