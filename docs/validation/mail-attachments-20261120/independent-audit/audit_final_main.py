#!/usr/bin/env python3
"""Read-only final-main applicability, replacement pin and static evidence audit."""
import argparse
from collections import Counter
import difflib
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('independent_helpers', HERE / 'audit_validation.py')
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
BASE = '6184051c75d882cac53be3c1a9384e4556588ad1'
FINAL = 'f8f36eb87b051a0b26ee68747dfd24c4717eaec1'
DART = 'packages/quds_proofing_spacy/lib/src/distribution.dart'
BUILD = 'packages/quds_office_editor/example/tool/build_macos_app.sh'
DOC = 'docs/release/macos-signing.md'
PIN = 'packages/quds_office_editor/example/test/studio_spacy_pin_test.dart'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    repo, evidence = args.repo.resolve(), args.evidence.resolve()
    issues = []
    def check(value, message):
        if not value:
            issues.append(message)
    def git(*argv):
        return subprocess.check_output(['git', '-C', str(repo), *argv])
    def check_file(path, expected):
        check(path.is_file(), 'Missing artifact/input: ' + str(path))
        if path.is_file():
            actual = h.record(path)
            check(all(actual[k] == v for k, v in expected.items() if k in actual),
                  'Hash mismatch: ' + str(path))
    def entries(head):
        return {r.split(b'\t', 1)[1].decode(): r.split(b'\t', 1)[0].decode().split()
                for r in git('ls-tree', '-r', '-z', head).split(b'\0') if r}
    immutable_names = ('report.json', 'supplemental-validation-report.json', 'supplemental-source-applicability.json')
    immutable = {name: h.record(HERE / name)['sha256'] for name in immutable_names}
    original = h.read_json(HERE / 'report.json')
    previous = h.read_json(HERE / 'supplemental-validation-report.json')
    check(previous['combined_distinct_passed_cases'] == 2049 and previous['status'] == 'passed', 'Prior combined acceptance differs')
    selected = {f for c in original['cohorts'] for f in c['selected_files']} | set(previous['supplemental_selected_files'])
    changed = git('diff', '--name-only', BASE, FINAL).decode().splitlines()
    check(set(changed) == {DART, BUILD, DOC}, 'Unexpected final-main changed paths')
    check(subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', BASE, FINAL]).returncode == 0,
          'Final main does not retain prior qualified source')
    before_tree, after_tree = entries(BASE), entries(FINAL)
    check(all(before_tree[p][:2] == after_tree[p][:2] for p in changed), 'A changed file mode/type differs')
    check(not selected.intersection(changed), 'A previously selected test source changed')
    before_dart, after_dart = [git('show', head + ':' + DART).decode() for head in (BASE, FINAL)]
    a, b = before_dart.splitlines(keepends=True), after_dart.splitlines(keepends=True)
    edits = [op for op in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes() if op[0] != 'equal']
    check(all(all(line.lstrip().startswith('///') for line in a[i:j] + b[k:l])
              for _, i, j, k, l in edits), 'Dart delta includes a non-documentation line')
    without_docs = lambda lines: ''.join(line for line in lines if not line.lstrip().startswith('///')).encode()
    check(without_docs(a) == without_docs(b), 'Non-documentation Dart bytes changed')
    before_build, after_build = [git('show', head + ':' + BUILD).decode() for head in (BASE, FINAL)]
    names = ['SPACY_PIN_SHA256', 'SPACY_PIN_REVISION', 'SPACY_PIN_BYTES', 'SPACY_PIN_REPOSITORY',
             'SPACY_PIN_CODE_SHA256', 'SPACY_PIN_UNSIGNED_SHA256']
    def pins(text):
        values = {}
        for name in names:
            match = re.search(r'^' + name + r'=([^\s]+)$', text, re.MULTILINE)
            check(match is not None, 'Missing pinned assignment: ' + name)
            values[name] = match.group(1) if match else None
        return values
    old_pins, new_pins = pins(before_build), pins(after_build)
    check(old_pins == new_pins, 'A value consumed by the pin test changed')
    literal_references = []
    for path in after_tree:
        if not path.endswith('.dart') or path.startswith('docs/'):
            continue
        for index, line in enumerate((repo / path).read_text().split('\n'), 1):
            if 'build_macos_app' in line or 'macos-signing.md' in line:
                literal_references.append({'path': path, 'line': index, 'text': line,
                                           'full_line_comment': line.lstrip().startswith('//')})
    executable_references = [row for row in literal_references if not row['full_line_comment']]
    check(len(executable_references) == 1 and executable_references[0]['path'] == PIN and
          "File('tool/build_macos_app.sh').readAsStringSync()" in executable_references[0]['text'],
          'Another non-comment Dart build-script reference needs review')
    commands = []
    mail = h.read_json(evidence / 'mail-packages/receipt.json')
    commands.extend({'cohort': step['name'], 'argv': step['argv']} for step in mail['steps'])
    for name in ('mail-host', 'editor-rendering', 'editor-zotero-materials', 'studio-spacy'):
        r = h.read_json(evidence / 'flutter-cohorts' / name / 'receipt.json')
        commands.append({'cohort': name, 'argv': r['command']})
    for name in ('engine-rendering', 'spacy-package', 'engine-macro-serialization'):
        commands.append({'cohort': name, 'argv': h.read_json(evidence / name / 'receipt.json')['command']})
    commands.append({'cohort': 'post-main-comment-draft', 'argv': h.read_json(evidence / 'post-main-comment-draft/tests/receipt.json')['command']})
    check(not any('build_macos_app' in value for command in commands for value in command['argv']),
          'A recorded acceptance command invokes the build script')
    io = h.read_json(HERE / 'final-main-selected-io-sites.json')
    check(io['selected_file_count'] == len(selected), 'I/O-site review does not cover the selected inventory')

    # The pin case is a replacement of one existing identity, never an addition.
    pin_dir = evidence / 'macos-portability-refresh/pin-test'
    pin_receipt = h.read_json(pin_dir / 'receipt.json')
    check(pin_receipt['source_head_at_start'] == pin_receipt['source_head_at_finish'] == FINAL, 'Replacement pin source differs')
    check(pin_receipt['status'] == 'passed' and pin_receipt['exit_code'] == 0 and all(pin_receipt['guards'].values()),
          'Replacement pin receipt rejected acceptance')
    check(pin_receipt['selected_repository_paths'] == [PIN], 'Replacement pin selection differs')
    for name, metadata in pin_receipt['artifacts'].items():
        check_file(pin_dir / name, metadata)
    events = [json.loads(line) for line in gzip.decompress((pin_dir / 'events.jsonl.gz').read_bytes()).decode().split('\n') if line.strip()]
    starts_list = [e['test'] for e in events if isinstance(e, dict) and e.get('type') == 'testStart']
    starts = {t['id']: t for t in starts_list}
    ends = [e for e in events if isinstance(e, dict) and e.get('type') == 'testDone']
    finals = [e for e in events if isinstance(e, dict) and e.get('type') == 'done']
    suites = [e['suite'] for e in events if isinstance(e, dict) and e.get('type') == 'suite']
    check(len(suites) == 1, 'Replacement suite count differs')
    check(not any(isinstance(e, dict) and e.get('type') == 'error' for e in events), 'Replacement pin has raw errors')
    check(len(starts_list) == len(starts) and Counter(e['testID'] for e in ends) == Counter(starts.keys()),
          'Replacement pin starts/completions are not unique and complete')
    check(all(e['result'] == 'success' and not e.get('skipped') for e in ends), 'Replacement pin failure/skip')
    check(len(finals) == 1 and finals[0]['success'], 'Replacement pin final event is not successful')
    substantive = [starts[e['testID']]['name'] for e in ends if not e.get('hidden') and
                   not starts[e['testID']]['name'].startswith('loading ') and
                   not starts[e['testID']]['name'].endswith(('(setUpAll)', '(tearDownAll)'))]
    old_cases = h.read_json(HERE / 'report-cases.json.gz')
    expected_pin_names = [c['name'] for c in old_cases if c['file'] == PIN and c['result'] == 'passed']
    check(substantive == expected_pin_names and len(substantive) == 1, 'Replacement identities do not match the original pin case')
    inputs = h.read_json(pin_dir / 'inputs.json.gz')['before']
    fingerprint = h.read_json(pin_dir / 'input-check.json')
    check(fingerprint == pin_receipt['fingerprints'], 'Replacement input-check differs from receipt')
    for area, records in inputs.items():
        check(h.digest(records) == fingerprint['before_sha256'][area] == fingerprint['after_sha256'][area],
              'Replacement input digest mismatch: ' + area)
        check(not fingerprint['changed_paths'][area], 'Replacement inputs changed: ' + area)
    for path, metadata in inputs['source'].items():
        check_file(repo / path, metadata)
        check(after_tree.get(path, ['', '', ''])[2] == metadata['git_blob_sha1'], 'Replacement source differs from final tree: ' + path)
    for path, metadata in inputs['workspace'].items():
        check_file(repo / path, metadata)
    for package, dependency in inputs['dependencies'].items():
        check(h.digest(dependency['files']) == dependency['inventory_sha256'], 'Replacement dependency manifest differs: ' + package)
        for path, metadata in dependency['files'].items():
            check_file(Path(dependency['root']) / path, metadata)
    for path, metadata in inputs['runtime'].items():
        check_file(Path(pin_receipt['runtime']['flutter_root']) / path, metadata)

    # The later 62-file static receipt is distinct from the immutable old audit.
    static_dir = evidence / 'changed-static-final'
    static = h.read_json(static_dir / 'receipt.json')
    check(static['accepted'] and static['inputs_unchanged'] and static['source_before'] == static['source_after'],
          'Final 62-file static receipt not accepted')
    check(static['head_before'] == static['head_after'] == '58c6962ec3ea82811bfcafec42981385f216f892',
          'Final static receipt source differs')
    check(len(static['selected_files']) == static['selected_count'] == 62, 'Final static selection count differs')
    for path, sha in static['source_before'].items():
        check(hashlib.sha256(git('show', static['head_before'] + ':' + path)).hexdigest() == sha,
              'Final static source hash differs: ' + path)
    for step in static['steps']:
        check_file(static_dir / step['log'], {'sha256': step['sha256']})
        check(step['exit_code'] == 0, 'Final static command failed: ' + step['name'])
        check(sorted(x for x in step['command'] if x.endswith('.dart')) == sorted(static['selected_files']),
              'Final static command targets differ')
    check('No issues found!' in (static_dir / 'analysis.log').read_text(), 'Final static analysis lacks clean completion')
    check('(0 changed)' in (static_dir / 'format.log').read_text(), 'Final static format changed files')

    shell_dir = evidence / 'macos-portability-refresh/script-checks'
    shell = h.read_json(shell_dir / 'receipt.json')
    check(shell['status'] == 'passed' and shell['source_head'] == FINAL and all(shell['guards'].values()),
          'Shell controls are not accepted at final source')
    check(shell['syntax_exit_code'] == 0, 'Bash syntax check failed')
    check(h.read_json(shell_dir / 'inputs-before.json') == h.read_json(shell_dir / 'inputs-after.json') == shell['source_inputs'],
          'Shell control inputs changed')
    for path, metadata in shell['source_inputs'].items():
        check_file(repo / path, metadata)
    scenarios = []
    for advertised in shell['scenarios']:
        case_dir = shell_dir / 'cases' / advertised['name']
        case = h.read_json(case_dir / 'receipt.json')
        check(case['accepted'] and all(case['checks'].values()), 'Shell scenario rejected: ' + advertised['name'])
        check(case['exit_code'] == case['scenario']['exit'] == advertised['exit_code'], 'Shell scenario exit differs')
        for path, metadata in case['artifacts'].items():
            check_file(case_dir / path, metadata)
        if case['scenario'].get('error'):
            check(case['scenario']['error'] in (case_dir / 'stderr.log').read_text(), 'Shell rejection diagnostic missing')
        scenarios.append({'name': advertised['name'], 'expected_exit': case['scenario']['exit'],
                          'actual_exit': case['exit_code'], 'accepted': case['accepted']})
    check(len(scenarios) == shell['scenario_count'] == 8 and len({s['name'] for s in scenarios}) == 8,
          'Shell scenario count/identity differs')
    refresh_dir = evidence / 'macos-portability-refresh'
    refresh = h.read_json(refresh_dir / 'receipt.json')
    check(refresh['status'] == 'passed' and refresh['source_head'] == FINAL,
          'macOS refresh aggregate is not accepted at final source')
    check_file(pin_dir / 'receipt.json', {'sha256': refresh['pin_receipt_sha256']})
    check_file(shell_dir / 'receipt.json', {'sha256': refresh['script_receipt_sha256']})
    check(refresh['application_test_total_unchanged'] == 2049 and refresh['optional_native_case_not_run_unchanged'] == 1,
          'macOS refresh aggregate inflates the distinct acceptance total')
    for name, sha in immutable.items():
        check(h.record(HERE / name)['sha256'] == sha, 'Earlier independent acceptance mutated: ' + name)
    patch = git('diff', BASE, FINAL)
    (HERE / 'final-main-source-delta.patch').write_bytes(patch)
    result = {
        'status': 'passed' if not issues else 'failed', 'base_source_head': BASE, 'final_source_head': FINAL,
        'final_source_tree': git('rev-parse', FINAL + '^{tree}').decode().strip(),
        'combined_distinct_passed_cases_retained': 2049, 'explicit_not_run_cases_retained': 1,
        'distinct_selected_files_retained': 113, 'replacement_pin_cases': len(substantive),
        'replacement_pin_cases_added_to_total': 0, 'auxiliary_shell_scenarios_added_to_total': 0,
        'exact_changed_paths': changed, 'file_modes_and_types_unchanged': True,
        'dart_delta_documentation_lines_only': True,
        'dart_non_doc_sha256': hashlib.sha256(without_docs(a)).hexdigest(),
        'pins_consumed_by_selected_test': {'before': old_pins, 'after': new_pins, 'identical': old_pins == new_pins},
        'literal_build_script_references': literal_references,
        'only_non_comment_reference_is_pin_file_read': len(executable_references) == 1,
        'recorded_runtime_commands': commands, 'recorded_command_invokes_build_script': False,
        'selected_test_io_review': {'files': io['selected_file_count'], 'sites': io['io_site_count'],
            'artifact': 'final-main-selected-io-sites.json', 'sha256': h.record(HERE / 'final-main-selected-io-sites.json')['sha256'],
            'review': 'Explicit subprocess targets are Dart mail crash fixtures, the Dart macro CLI, fixture git and mkfifo. Other reviewed reads use generated temporary data, committed fixtures/fonts, or injected fake providers. The changed build-script read is confined to the separately requalified pin test.'},
        'replacement_pin_receipt_sha256': h.record(pin_dir / 'receipt.json')['sha256'],
        'macos_refresh_aggregate_sha256': h.record(refresh_dir / 'receipt.json')['sha256'],
        'replacement_input_verification': {'source_files': len(inputs['source']),
            'dependency_files': sum(len(x['files']) for x in inputs['dependencies'].values()),
            'all_source_records_match_final_tree': True, 'all_area_digests_recomputed': True},
        'final_static_62': {'source_head': static['head_before'], 'selected_count': 62,
            'receipt_sha256': h.record(static_dir / 'receipt.json')['sha256'],
            'analysis_and_format_log_hashes_verified': True, 'status': 'passed'},
        'auxiliary_shell_controls': {'receipt_sha256': h.record(shell_dir / 'receipt.json')['sha256'],
            'syntax_exit_code': shell['syntax_exit_code'], 'scenarios': scenarios,
            'qualification_limit': shell['qualification_limit']},
        'earlier_audit_hashes_unchanged': immutable, 'source_delta_patch_sha256': hashlib.sha256(patch).hexdigest(),
        'auditor': h.record(Path(__file__)), 'issues': issues,
        'limits': ['No real macOS build/signing/native loading was executed or inferred.',
                   'Static I/O-site and literal-reference review is not a universal runtime file-access trace.',
                   'Reproduction requires the reconstructed original flat evidence layout and recorded Git/runtime/dependency inputs.'],
        'no_tests_or_analyzers_executed_by_independent_auditor': True,
    }
    (HERE / 'final-main-applicability.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('status', 'final_source_head', 'final_source_tree',
          'combined_distinct_passed_cases_retained', 'explicit_not_run_cases_retained',
          'replacement_pin_cases', 'replacement_pin_cases_added_to_total', 'issues')}, indent=2))
    return 0 if not issues else 1


if __name__ == '__main__':
    raise SystemExit(main())
