#!/usr/bin/env python3
"""Read-only independent verification of retained late qualification evidence."""
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path('/workspace/scratch/76a795caf82b')
RUN = Path(sys.argv[1]).resolve()
DEST = Path(sys.argv[2]).resolve()
EXPECTED_HOST = sys.argv[3]
EXPECTED_QUDS = '732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2'
RUNTIME = ROOT / 'runtime'
evidence_findings = []
qualification_findings = []


def require(value, description):
    if not value:
        evidence_findings.append(description)
    return bool(value)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def aggregate(value, compact=False):
    options = {'sort_keys': True}
    if compact:
        options['separators'] = (',', ':')
    return digest(json.dumps(value, **options).encode())


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def prove_git_sources(repo, commit, mapping):
    tree = {}
    for row in git(repo, 'ls-tree', '-rz', commit).split(b'\0'):
        if row:
            meta, path = row.split(b'\t', 1)
            tree[path.decode()] = meta.split()[2].decode()
    missing = sorted(set(mapping) - set(tree))
    require(not missing, f'{repo.name}: source paths absent from pinned Git tree: {missing}')
    blobs = {}
    for path in mapping:
        if path in tree:
            blobs.setdefault(tree[path], []).append(path)
    mismatches = []
    process = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for blob, paths in blobs.items():
            process.stdin.write(blob.encode() + b'\n')
            process.stdin.flush()
            header = process.stdout.readline().split()
            if len(header) != 3 or header[1] != b'blob':
                raise RuntimeError(f'Unexpected Git object header {header!r}')
            size = int(header[2])
            sha = hashlib.sha256()
            sha1 = hashlib.sha1(b'blob ' + str(size).encode() + b'\0')
            remaining = size
            while remaining:
                chunk = process.stdout.read(min(remaining, 1024 * 1024))
                if not chunk:
                    raise RuntimeError('Incomplete Git blob stream')
                sha.update(chunk)
                sha1.update(chunk)
                remaining -= len(chunk)
            if process.stdout.read(1) != b'\n':
                raise RuntimeError('Missing Git blob delimiter')
            require(sha1.hexdigest() == blob, f'{repo.name}: Git blob identity mismatch {blob}')
            mismatches.extend(path for path in paths if mapping[path] != sha.hexdigest())
    finally:
        process.stdin.close()
        process.stdout.close()
        process.wait(timeout=30)
    require(not mismatches, f'{repo.name}: receipt SHA-256 differs from pinned source: {mismatches}')
    return {'commit': commit, 'source_paths': len(mapping), 'unique_git_blobs': len(blobs),
            'all_source_sha256_match_pinned_git_blobs': not missing and not mismatches,
            'missing_paths': missing, 'mismatch_paths': mismatches,
            'proof_method': 'SHA-256 recomputed directly from immutable Git blob contents; live working-tree changes after execution cannot replace the tested identity.'}


def check_files(mapping, resolver, label):
    bad = []
    for name, expected in mapping.items():
        path = resolver(name)
        if not path.is_file() or file_hash(path) != expected:
            bad.append(name)
    require(not bad, f'{label}: current retained input mismatch: {bad}')
    return {'files': len(mapping), 'all_hashes_match': not bad, 'mismatch_paths': bad}


def command_review(receipt, folder):
    rows = []
    for item in receipt['commands']:
        path = folder / item['log']
        matches = path.is_file() and file_hash(path) == item.get('log_sha256')
        require(matches, f'{folder.name}/{item["name"]}: log hash mismatch')
        row = {'name': item['name'], 'status': item['status'], 'exit_code': item.get('exit_code'),
               'log': str(path.relative_to(ROOT)), 'log_sha256': file_hash(path) if path.is_file() else None,
               'matches_retained_log_hash': matches, 'timed_out': item.get('timed_out', False)}
        if item['status'] != 'passed' or item.get('exit_code') != 0:
            qualification_findings.append({'cohort': folder.name, 'command': item['name'], 'status': item['status'],
                'exit_code': item.get('exit_code'), 'log': row['log'], 'last_log_lines': path.read_text(errors='replace').splitlines()[-8:]})
        if item['name'] in {'sheet-tests', 'host-tests', 'service-tests'}:
            matches = re.findall(r'\+(\d+)(?:\s+~(\d+))?: All tests passed!', path.read_text(errors='replace'))
            require(len(matches) == 1, f'{folder.name}/{item["name"]}: expected exactly one terminal success marker')
            if matches:
                row['passed_tests'] = int(matches[-1][0])
                row['skipped_tests'] = int(matches[-1][1] or 0)
                require(row['skipped_tests'] == 0, f'{folder.name}/{item["name"]}: skipped tests')
        if item['name'] == 'python-sync-verifier-tests':
            text = path.read_text(errors='replace')
            matches = re.findall(r'Ran (\d+) tests? in', text)
            require(len(matches) == 1 and re.search(r'^OK\s*$', text, re.M) is not None, 'Python terminal success/count marker missing')
            if matches:
                row['passed_tests'] = int(matches[-1])
                row['skipped_tests'] = 0
            require('skipped=' not in text and not re.search(r'\.\.\. skipped', text), 'Python skipped tests')
        rows.append(row)
    return rows


outer = read(RUN / 'receipt.json')
canonical = read(RUN / 'canonical/receipt.json')
host = read(RUN / 'host/receipt.json')
require(outer['quds_source_commit'] == canonical['source_commit'] == EXPECTED_QUDS, 'Canonical source pin mismatch')
require(outer['host_source_commit'] == host['source_commit'] == EXPECTED_HOST, 'Host source pin mismatch')
require(outer['status'] in {'passed', 'failed'}, 'Outer receipt is not terminal')
require(outer['counts_are_overlapping_reruns_not_additive_unique_tests'], 'Overlapping-count attribution missing')
canonical_commands = command_review(canonical, RUN / 'canonical')
host_commands = command_review(host, RUN / 'host')
expected_canonical = ['sheet-tests', 'sheet-strict-analysis', 'sheet-format']
require([r['name'] for r in canonical_commands] == expected_canonical, 'Unexpected canonical command selection')
missing_host = [name for name in host['expected_commands'] if name not in [r['name'] for r in host_commands]]
actual_host_commands = [r['name'] for r in host_commands]
require(actual_host_commands == host['expected_commands'][:len(actual_host_commands)], 'Host command order/selection differs from expected cohort')
if missing_host:
    qualification_findings.append({'cohort': 'host', 'required_commands_not_executed': missing_host})

outer_checks = []
for row in outer['cohorts']:
    receipt_path = RUN / row.get('receipt', row['name'] + '/receipt.json')
    log_path = RUN / row['log']
    runner = Path(row['command'][1])
    checks = {'cohort': row['name'], 'receipt_hash_matches': file_hash(receipt_path) == row['receipt_sha256'] if 'receipt_sha256' in row else None,
              'independent_child_receipt_sha256': file_hash(receipt_path), 'outer_receipt_hash_recorded': 'receipt_sha256' in row,
              'launcher_log_hash_matches': file_hash(log_path) == row['log_sha256'],
              'runner_hash_matches': file_hash(runner) == row['runner_sha256'],
              'status': row['status'], 'exit_code': row.get('exit_code')}
    require(all(checks[k] for k in ('launcher_log_hash_matches', 'runner_hash_matches')), f'{row["name"]}: outer binding mismatch')
    if row['status'] == 'passed' or 'receipt_sha256' in row:
        require(checks['receipt_hash_matches'], f'{row["name"]}: child receipt binding mismatch')
    outer_checks.append(checks)
require(file_hash(RUNTIME / 'late-main/run-late-integration.py') == outer['runner_sha256'], 'Outer runner hash mismatch')
require(file_hash(RUNTIME / 'late-main/canonical-support.py') == canonical['frozen_support_sha256'], 'Frozen canonical helper hash mismatch')

canon_before = read(RUN / 'canonical/source-before.json')
canon_after = read(RUN / 'canonical/source-after.json')
host_before = read(RUN / 'host/source-before.json')
host_after = read(RUN / 'host/source-after.json')
require(canon_before == canon_after, 'Canonical source maps changed during run')
require(host_before == host_after, 'Host source maps changed during run')
require(canon_after['files'] == canonical['source_file_count'] == len(canon_after['sha256_by_path']), 'Canonical source count mismatch')
require(len(host_after) == host['source_file_count'], 'Host source count mismatch')
require(aggregate(canon_after['sha256_by_path']) == canon_after['aggregate_sha256'], 'Canonical source aggregate mismatch')
require(aggregate(host_after, True) == host['source_after_aggregate_sha256'], 'Host source aggregate mismatch')
source_proofs = [prove_git_sources(ROOT / 'quds', EXPECTED_QUDS, canon_after['sha256_by_path']),
                 prove_git_sources(ROOT / 'crisp', EXPECTED_HOST, host_after)]

canon_deps_before = read(RUN / 'canonical/dependencies-before.json')
canon_deps_after = read(RUN / 'canonical/dependencies-after.json')
host_deps_before = read(RUN / 'host/dependencies-before.json')
host_deps_after = read(RUN / 'host/dependencies-after.json')
require(canon_deps_before == canon_deps_after, 'Canonical dependency/runtime maps changed')
require(host_deps_before == host_deps_after, 'Host dependency/runtime/declaration maps changed')
require(aggregate(canon_deps_after['sha256_by_path']) == canon_deps_after['aggregate_sha256'], 'Canonical dependency aggregate mismatch')
require(aggregate(host_deps_after, True) == host['dependencies_after_aggregate_sha256'], 'Host dependency aggregate mismatch')
canonical_dependencies = check_files(canon_deps_after['sha256_by_path'], lambda key: RUNTIME / key, 'Canonical dependencies/runtime')
require(canonical['harness_inputs_before'] == canonical['harness_inputs_after'], 'Canonical harness maps changed')
canonical_harness = check_files(canonical['harness_inputs_after'], lambda key: RUNTIME / key, 'Canonical harness')
harness = Path(host['harness'])
roots = host_deps_after['package_roots']


def host_dependency_path(key):
    if key == '.dart_tool/package_config.json':
        return harness / key
    package, relative = key.split('/', 1)
    if relative.startswith('lib/'):
        return Path(roots[package]['library']) / relative[4:]
    return Path(roots[package]['root']) / relative


local_libraries = {'crisp_cloud': 'lib/'}
local_libraries.update({name: f'packages/{name}/lib/' for name in ('quds_office_engine', 'quds_office_editor', 'quds_reports', 'legacy_doc_parser')})
external_and_manifest_dependencies = {}
local_dependency_checks = []
additional_local_source_inputs = {}
post_run_live_source_differences = []
for key, expected in host_deps_after['dependency_files'].items():
    package, separator, relative = key.partition('/')
    if package in local_libraries and relative.startswith('lib/'):
        source_path = local_libraries[package] + relative[4:]
        if source_path in host_after:
            matches = host_after[source_path] == expected
            require(matches, f'Host local dependency differs from proven pinned source map: {key}')
            local_dependency_checks.append(matches)
        else:
            # The dependency inventory additionally captures non-managed local
            # package library files outside the primary vendor source inventory.
            additional_local_source_inputs[source_path] = expected
            local_dependency_checks.append(True)
        actual_path = ROOT / 'crisp' / source_path
        if actual_path.is_file() and file_hash(actual_path) != expected:
            post_run_live_source_differences.append(source_path)
    else:
        external_and_manifest_dependencies[key] = expected
host_dependencies = check_files(external_and_manifest_dependencies, host_dependency_path, 'Host external dependencies and harness manifests')
host_dependencies.update(total_snapshot_files=len(host_deps_after['dependency_files']),
                         local_library_inputs_verified_against_pinned_source=len(local_dependency_checks),
                         all_local_library_inputs_match_pinned_source=all(local_dependency_checks))
additional_local_source_proof = prove_git_sources(ROOT / 'crisp', EXPECTED_HOST, additional_local_source_inputs)
host_runtime = check_files(host_deps_after['runtime_files'], lambda key: RUNTIME / 'flutter-sdk' / key, 'Host runtime')
declarations = {key: item['sha256'] for key, item in host_deps_after['declarations'].items()}
host_harness = check_files(declarations, lambda key: harness / key.removeprefix('harness/'), 'Host harness declarations')
require(all(digest(item['text'].encode()) == item['sha256'] for item in host_deps_after['declarations'].values()), 'Retained harness declaration text/hash mismatch')
fixtures_before = read(RUN / 'canonical/fixtures-before.json')
fixtures_after = read(RUN / 'canonical/fixtures-after.json')
require(fixtures_before == fixtures_after, 'Canonical fixture maps changed')
for path, row in fixtures_after.items():
    p = Path(path)
    require(p.is_file() == row['present'], f'Fixture presence changed: {path}')
    if row['present']:
        require(p.stat().st_size == row['bytes'] and file_hash(p) == row['sha256'], f'Fixture hash changed: {path}')

gate_names = {'canonical': ['source_inputs_unchanged', 'dependencies_unchanged', 'harness_inputs_unchanged', 'fixtures_unchanged', 'analyzer_config_restored', 'published_source_still_matches'],
              'host': ['source_unchanged', 'dependencies_unchanged', 'analysis_config_restored', 'tracked_inputs_match_published_source']}
gates = {name: {key: data[key] for key in gate_names[name]} for name, data in [('canonical', canonical), ('host', host)]}
require(all(value for section in gates.values() for value in section.values()), 'A recorded source/dependency/restoration gate failed')
restoration = {'canonical_declared_restored': canonical['analyzer_config_restored'],
               'canonical_config_present_at_review': (ROOT / 'quds/.dart_tool/package_config.json').exists(),
               'host_declared_restored': host['analysis_config_restored'],
               'host_original_config_present': host['analysis_config_preexisting'],
               'host_config_present_at_review': (ROOT / 'crisp/.dart_tool/package_config.json').exists()}
if outer['status'] == 'passed':
    require(restoration['host_config_present_at_review'] == host['analysis_config_preexisting'], 'Host analyzer configuration presence differs from pre-run baseline')
    if host['analysis_config_preexisting']:
        require(file_hash(ROOT / 'crisp/.dart_tool/package_config.json') == host['analysis_config_before_sha256'], 'Host analyzer configuration bytes differ from pre-run baseline')
runtime_version = read(RUNTIME / 'flutter-sdk/bin/cache/flutter.version.json')
require(canonical['runtime'] == host['runtime'] == runtime_version, 'Recorded runtime versions differ from actual frozen SDK')
require(runtime_version['frameworkRevision'] == '737ba8f885dc774b53b442759999a312c9461e4e' and runtime_version['engineRevision'] == 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8' and runtime_version['dartSdkVersion'] == '3.13.7', 'Runtime is not the approved pinned Flutter/Dart build')

setup_path = Path(host['service_graph_setup'])
setup = read(setup_path)
require(file_hash(setup_path) == host['service_graph_setup_sha256'] == outer['service_setup_sha256'], 'Setup receipt binding mismatch')
setup_commands = []
for row in setup['setup_commands']:
    matches = file_hash(Path(row['log'])) == row['log_sha256']
    require(matches, f'Setup log hash mismatch: {row["name"]}')
    setup_commands.append({'name': row['name'], 'status': row['status'], 'exit_code': row['exit_code'], 'log_hash_matches': matches})
require(file_hash(harness / 'pubspec.lock') == setup['final_lock_sha256'], 'Final service lock changed')
require(file_hash(ROOT / 'crisp/pubspec.lock') == setup['production_lock_sha256'], 'Host production lock differs from setup source')
require(setup['status'] == 'passed' and setup['original_package_identities_preserved'] and setup['new_packages_match_production_lock'], 'Service setup identity gate failed')
setup_failure = [row for row in setup_commands if row['status'] != 'passed' or row['exit_code'] != 0]

all_commands = canonical_commands + host_commands
counts = {row['name']: row['passed_tests'] for row in all_commands if 'passed_tests' in row}
require(counts.get('sheet-tests') == canonical.get('passed_tests'), 'Canonical terminal count differs from receipt')
require(counts.get('host-tests') == host.get('passed_host_tests'), 'Host terminal count differs from receipt')
require(counts.get('service-tests') == host.get('passed_service_tests'), 'Service terminal count differs from receipt')
if 'python-sync-verifier-tests' in counts:
    require(counts['python-sync-verifier-tests'] == host.get('passed_python_tests'), 'Python terminal count differs from receipt')
report = {'reviewed_at_utc': datetime.now(timezone.utc).isoformat(),
          'status': 'passed' if outer['status'] == 'passed' and not evidence_findings and not qualification_findings else 'failed',
          'retained_evidence_integrity': 'passed' if not evidence_findings else 'failed',
          'reviewed_output_directory': str(RUN.relative_to(ROOT)), 'outer_receipt_status': outer['status'],
          'source_pair': {'canonical': EXPECTED_QUDS, 'host': EXPECTED_HOST},
          'evidence_findings': evidence_findings, 'qualification_findings': qualification_findings,
          'outer_bindings': outer_checks, 'canonical_commands': canonical_commands, 'host_commands': host_commands,
          'source_proofs': source_proofs, 'input_maps_before_after_equal': True if not any('maps changed' in x for x in evidence_findings) else False,
          'recorded_integrity_gates': gates, 'canonical_dependencies': canonical_dependencies,
          'canonical_harness': canonical_harness, 'host_dependencies': host_dependencies,
          'additional_host_local_library_source_proof': additional_local_source_proof,
          'post_run_live_source_differences': {'paths': post_run_live_source_differences,
              'handling': 'Current checkout may advance after a terminal run. Source/library receipt maps are instead verified against their immutable Git pins; before/after execution maps must still match.'},
          'host_runtime': host_runtime, 'host_harness': host_harness,
          'canonical_fixtures': {'observed': len(fixtures_after), 'present': sum(x['present'] for x in fixtures_after.values()), 'before_after_equal': fixtures_before == fixtures_after},
          'restoration': restoration, 'viewer_scope': host['viewer_analysis'],
          'service_setup': {'status': setup['status'], 'package_count': setup['final_package_count'], 'final_lock_sha256': setup['final_lock_sha256'],
                            'commands': setup_commands, 'recovered_failed_setup_commands': setup_failure,
                            'recovery': setup.get('path_rebase_correction'), 'counts_excluded_from_application_tests': True},
          'completed_test_counts': counts, 'completed_test_executions': sum(counts.values()),
          'completed_test_skips': sum(row.get('skipped_tests', 0) for row in all_commands),
          'analysis_target_counts': {'canonical': len(canonical['analysis_and_format_targets']),
              'host': len(host['host_analysis_targets']), 'vendored': len(host['vendored_analysis_targets']),
              'viewer': 0, 'viewer_format_only': 1},
          'missing_host_commands': missing_host, 'initial_broad_run': outer['prior_qualification'],
          'counts_are_overlapping_reruns_not_additive_unique_tests': True,
          'github_actions_used': False, 'application_tests_rerun_by_review': False, 'repository_mutated_by_review': False}
DEST.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: report[key] for key in ('status', 'retained_evidence_integrity', 'source_pair', 'evidence_findings', 'qualification_findings', 'completed_test_counts', 'completed_test_executions')}, indent=2))
print(str(DEST))
