#!/usr/bin/env python3
"""Audit the post-main unselected-test delta and its separate validation.

Reads Git objects and saved evidence only. Does not execute tests or analysis.
The original report.json and its 2034-case acceptance remain immutable.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urljoin, urlparse, unquote


HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('independent_helpers', HERE / 'audit_validation.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
BASE = '58c6962ec3ea82811bfcafec42981385f216f892'
FINAL = '6184051c75d882cac53be3c1a9384e4556588ad1'
TARGET = 'packages/quds_office_editor/example/test/studio_comment_draft_proofing_test.dart'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    repo, evidence = args.repo.resolve(), args.evidence.resolve()
    folder = evidence / 'post-main-comment-draft'
    issues = []

    def check(value, message):
        if not value:
            issues.append(message)

    def git(*argv):
        return subprocess.check_output(['git', '-C', str(repo), *argv])

    def check_file(path, expected):
        if not path.is_file():
            issues.append('Missing artifact/input: ' + str(path))
            return
        actual = helpers.record(path)
        check(all(actual[k] == v for k, v in expected.items() if k in actual),
              'Artifact/input hash mismatch: ' + str(path))

    original_bytes = (HERE / 'report.json').read_bytes()
    original = json.loads(original_bytes)
    check(original['status'] == 'passed' and original['final_source_head'] == BASE,
          'Original independent acceptance differs')
    changed = git('diff', '--name-only', BASE, FINAL).decode().splitlines()
    check(changed == [TARGET], 'Source delta exceeds the one unselected test')
    check(subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', BASE, FINAL]).returncode == 0,
          'Final source does not retain original qualified commit by ancestry')
    selected = {f for cohort in original['cohorts'] for f in cohort['selected_files']}
    check(TARGET not in selected, 'Changed test overlaps original selected files')
    configpath = repo / '.dart_tool/package_config.json'
    roots = {p['name']: Path(unquote(urlparse(urljoin(configpath.as_uri(), p['rootUri'])).path)).resolve() / p.get('packageUri', 'lib/')
             for p in helpers.read_json(configpath)['packages']}
    tracked = git('ls-tree', '-r', '--name-only', FINAL).decode().splitlines()
    dart = [f for f in tracked if f.endswith('.dart') and not f.startswith('docs/')]
    directives = re.compile(r'\b(?:import|export|part)\s+([^;]+);', re.DOTALL)
    quoted = re.compile(r'''(?:r)?["']([^"']+)["']''')
    references, edges = [], []
    for relative in dart:
        path = repo / relative
        text = path.read_text()
        if relative != TARGET and Path(TARGET).stem in text:
            references.append(relative)
        for clause in directives.findall(text):
            for uri in quoted.findall(clause):
                if uri.startswith('dart:'):
                    continue
                if uri.startswith('package:'):
                    name, _, tail = uri[len('package:'):].partition('/')
                    if name not in roots:
                        continue
                    resolved = (roots[name] / tail).resolve()
                else:
                    resolved = (path.parent / uri).resolve()
                if resolved == (repo / TARGET).resolve():
                    edges.append({'source': relative, 'uri': uri})
    check(not references and not edges, 'Changed test has an incoming reference')
    diff = git('diff', BASE, FINAL)
    (HERE / 'supplemental-source-delta.patch').write_bytes(diff)
    source_proof = {
        'status': 'passed' if not issues else 'failed', 'base_source_head': BASE,
        'final_source_head': FINAL, 'final_tree': git('rev-parse', FINAL + '^{tree}').decode().strip(),
        'original_audit_report_sha256': hashlib.sha256(original_bytes).hexdigest(),
        'original_passed_cases_retained': original['summary']['distinct_passed_application_cases'],
        'original_not_run_cases_retained': original['summary']['explicit_not_run_cases'],
        'exact_changed_paths': changed, 'all_application_libraries_and_other_files_identical': changed == [TARGET],
        'changed_test_is_an_original_selected_entry_point': TARGET in selected,
        'tracked_non_document_dart_files_scanned': len(dart), 'incoming_import_export_part_edges': edges,
        'filename_references_outside_changed_test': references,
        'source_delta_patch_sha256': hashlib.sha256(diff).hexdigest(),
        'new_test_execution_claimed': False, 'issues': list(issues),
    }
    (HERE / 'supplemental-source-applicability.json').write_text(json.dumps(source_proof, indent=2) + '\n')

    if not (folder / 'receipt.json').exists():
        print(json.dumps({'source_applicability': source_proof['status'], 'supplemental_validation': 'pending'}))
        return 2
    aggregate = helpers.read_json(folder / 'receipt.json')
    check(aggregate['status'] == 'passed' and aggregate['source_head'] == FINAL,
          'Supplemental aggregate receipt is not accepted at the final head')
    for subdir, field in [('tests', 'test_receipt_sha256'), ('checks', 'checks_receipt_sha256')]:
        check_file(folder / subdir / 'receipt.json', {'sha256': aggregate[field]})
    check(all(aggregate['test_guards'].values()) and all(aggregate['checks_guards'].values()),
          'Supplemental aggregate guards rejected acceptance')
    test_dir = folder / 'tests'
    receipt = helpers.read_json(test_dir / 'receipt.json')
    if receipt.get('status') == 'running':
        print(json.dumps({'source_applicability': source_proof['status'], 'supplemental_validation': 'running'}))
        return 2
    raw = gzip.decompress((test_dir / 'events.jsonl.gz').read_bytes())
    events, parse_errors = [], []
    for number, line in enumerate(raw.decode().split('\n'), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
            if isinstance(value, dict) and 'type' in value:
                events.append(value)
            elif not (isinstance(value, list) and all(isinstance(v, dict) and str(v.get('event', '')).startswith('test.') for v in value)):
                parse_errors.append(number)
        except ValueError:
            parse_errors.append(number)
    starts_list = [e['test'] for e in events if e['type'] == 'testStart']
    starts = {t['id']: t for t in starts_list}
    completions = [e for e in events if e['type'] == 'testDone']
    ends = Counter(e['testID'] for e in completions)
    suites = [e['suite'] for e in events if e['type'] == 'suite']
    finals = [e for e in events if e['type'] == 'done']
    errors = [e for e in events if e['type'] == 'error']
    def suite_path(value):
        path = Path(unquote(urlparse(value).path)) if value.startswith('file:') else Path(value)
        return str((path if path.is_absolute() else Path(receipt['cwd']) / path).resolve().relative_to(repo))
    check([suite_path(s['path']) for s in suites] == [TARGET], 'Supplemental suite coverage is not exactly the changed file')
    check(receipt['selected_repository_paths'] == [TARGET], 'Supplemental declared selection differs')
    check(not parse_errors and not errors, 'Supplemental event parse/error failure')
    check(len(starts_list) == len(starts) and set(starts) == set(ends) and all(n == 1 for n in ends.values()),
          'Supplemental starts/completions are not unique and complete')
    check(all(e['result'] == 'success' for e in completions), 'Supplemental failed completion, including hidden event')
    check(len(finals) == 1 and finals[0]['success'], 'Supplemental final success event absent')
    real, excluded = [], []
    for done in completions:
        test = starts[done['testID']]
        name = test['name']
        if done.get('hidden') or (name.startswith('loading ') and test.get('url') is None) or name.endswith(('(setUpAll)', '(tearDownAll)')):
            excluded.append(name)
        else:
            real.append({'file': TARGET, 'name': name, 'result': done['result'],
                         'skipped': bool(done.get('skipped') or test.get('metadata', {}).get('skip'))})
    check(not any(t['skipped'] for t in real), 'Supplemental unexpected skip')
    check(len({t['name'] for t in real}) == len(real), 'Supplemental duplicate case name')
    check(receipt['tests']['passed'] == len(real) and receipt['tests']['failed'] == 0 and receipt['tests']['skipped'] == 0,
          'Supplemental receipt count differs from independent recount')
    check(receipt['status'] == 'passed' and receipt['exit_code'] == 0 and all(receipt['guards'].values()),
          'Supplemental raw receipt is not accepted')
    input_reports = []
    blobs = {row.split(b'\t', 1)[1].decode(): row.split(b'\t', 1)[0].decode().split()[2]
             for row in git('ls-tree', '-r', '-z', FINAL).split(b'\0') if row}
    for name in ('tests', 'checks'):
        directory = folder / name
        saved = helpers.read_json(directory / 'receipt.json')
        check(saved['source_head_at_start'] == saved['source_head_at_finish'] == FINAL,
              name + ': source head changed or differs from final')
        check(saved['status'] == 'passed' and all(saved['guards'].values()), name + ': receipt is not accepted')
        for filename, metadata in saved.get('artifacts', {}).items():
            check_file(directory / filename, metadata)
        for step in saved.get('steps', []):
            check(step['exit_code'] == 0, 'Supplemental static command failed: ' + step['name'])
            check([x for x in step['command'] if x.endswith('.dart')] == [TARGET],
                  'Supplemental static command selected another file')
            for channel in ('stdout', 'stderr'):
                check_file(directory / (step['name'] + '-' + channel + '.log'), step[channel])
            if step['name'] == 'analysis':
                check('--fatal-infos' in step['command'] and '--fatal-warnings' in step['command'],
                      'Supplemental analysis command is not strict')
                check('No issues found!' in (directory / 'analysis-stdout.log').read_text(),
                      'Supplemental analysis log lacks a clean completion')
            elif step['name'] == 'format':
                check('(0 changed)' in (directory / 'format-stdout.log').read_text(),
                      'Supplemental format log is not unchanged')
        inputs = helpers.read_json(directory / 'inputs.json.gz')['before']
        fingerprint = helpers.read_json(directory / 'input-check.json')
        for area, records in inputs.items():
            computed = helpers.digest(records)
            check(computed == fingerprint['before_sha256'][area] == fingerprint['after_sha256'][area],
                  name + ':' + area + ' input digests differ')
            check(not fingerprint['changed_paths'][area], name + ':' + area + ' inputs changed during validation')
        for path, metadata in inputs['source'].items():
            check_file(repo / path, metadata)
            check(blobs.get(path) == metadata['git_blob_sha1'], name + ': source differs from final commit: ' + path)
        for path, metadata in inputs['workspace'].items():
            check_file(repo / path, metadata)
        for package, dependency in inputs['dependencies'].items():
            check(helpers.digest(dependency['files']) == dependency['inventory_sha256'], name + ':' + package + ' manifest digest mismatch')
            for path, metadata in dependency['files'].items():
                check_file(Path(dependency['root']) / path, metadata)
        sdk = Path(saved.get('runtime', {}).get('flutter_root', evidence.parent / 'runtime/flutter'))
        for path, metadata in inputs['runtime'].items():
            check_file(sdk / path, metadata)
        input_reports.append({'scope': name, 'source_files': len(inputs['source']),
                              'dependency_files': sum(len(x['files']) for x in inputs['dependencies'].values()),
                              'receipt_sha256': helpers.record(directory / 'receipt.json')['sha256']})
    check((HERE / 'report.json').read_bytes() == original_bytes, 'Original independent acceptance changed during supplemental audit')
    result = {
        'status': 'passed' if not issues else 'failed', 'final_source_head': FINAL,
        'final_source_tree': source_proof['final_tree'],
        'original_audit_report_sha256': hashlib.sha256(original_bytes).hexdigest(),
        'original_passed_cases_retained': original['summary']['distinct_passed_application_cases'],
        'supplemental_passed_cases': len(real), 'supplemental_failed_cases': 0 if not errors else len(errors),
        'supplemental_not_run_cases': sum(t['skipped'] for t in real),
        'combined_distinct_passed_cases': original['summary']['distinct_passed_application_cases'] + len(real),
        'combined_explicit_not_run_cases': original['summary']['explicit_not_run_cases'],
        'combined_distinct_selected_files': len(selected) + 1,
        'supplemental_selected_files': [TARGET], 'supplemental_cases': real,
        'supplemental_hidden_or_lifecycle_excluded': len(excluded),
        'inputs_independently_verified': input_reports,
        'aggregate_receipt_sha256': helpers.record(folder / 'receipt.json')['sha256'],
        'aggregate_receipt': aggregate, 'issues': issues,
        'auditor': helpers.record(Path(__file__)),
        'no_tests_or_analysis_executed_by_auditor': True,
    }
    (HERE / 'supplemental-validation-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('supplemental_cases', 'aggregate_receipt')}, indent=2))
    return 0 if not issues else 1


if __name__ == '__main__':
    raise SystemExit(main())
