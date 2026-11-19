#!/usr/bin/env python3
"""Read-only Mail applicability check; does not rerun or reattribute prior tests.

Reads immutable Git objects and live bytes. It never calls status/write-tree,
changes an index, or writes in the repository/runtime. Supply a separate output.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import subprocess
import sys

BASE = Path(__file__).resolve().parent


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read(path: Path):
    return json.loads(path.read_text())


def file_hash(path: Path):
    if not path.exists() and not path.is_symlink():
        return None
    return sha(path.read_bytes())


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(['git', '-C', str(repo), *args])


def tree(repo: Path, commit: str):
    result = {}
    for entry in git(repo, 'ls-tree', '-r', '-z', commit).split(b'\0'):
        if not entry:
            continue
        meta, name = entry.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        result[name.decode()] = {'mode': mode, 'kind': kind, 'git_blob': oid}
    return result


def blobs(repo: Path, ids):
    ids = sorted(set(ids))
    p = subprocess.run(['git', '-C', str(repo), 'cat-file', '--batch'],
                       input=('\n'.join(ids) + '\n').encode(),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    out = p.stdout
    result = {}
    position = 0
    for oid in ids:
        end = out.index(b'\n', position)
        header = out[position:end].decode().split()
        if len(header) != 3 or header[0] != oid or header[1] != 'blob':
            raise ValueError(f'Unexpected object header: {header!r}')
        size = int(header[2])
        position = end + 1
        result[oid] = out[position:position + size]
        position += size
        if out[position:position + 1] != b'\n':
            raise ValueError('Malformed cat-file boundary')
        position += 1
    if position != len(out):
        raise ValueError('Unconsumed cat-file output')
    return result


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, default=BASE / 'quds_office_suite')
    p.add_argument('--target', required=True, help='Immutable final commit SHA')
    p.add_argument('--prior-report', type=Path, default=BASE / 'post_29dd_mail_continuity.json')
    p.add_argument('--qualified-review', type=Path, default=BASE / 'latest_final_review.json')
    p.add_argument('--store-receipt', type=Path, default=BASE / 'qualification/latest-store/receipt.json')
    p.add_argument('--focused-receipt', type=Path, default=BASE / 'qualification/latest-final/verification.json')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    repo = a.repo.resolve()
    output = a.output.resolve()
    require(not output.is_relative_to(repo), 'Output must remain outside tracked repository')
    require(output != a.prior_report.resolve(), 'Do not replace the prior continuity report')
    prior = read(a.prior_report)
    review = read(a.qualified_review)
    store = read(a.store_receipt)
    focused = read(a.focused_receipt)
    qualified = prior['qualified_source']
    target = git(repo, 'rev-parse', f'{a.target}^{{commit}}').decode().strip()
    require(target == a.target, '--target must be the complete immutable commit SHA')
    require(review['accepted'] is True and review['qualified_source'] == qualified,
            'Prior accepted audit source mismatch')
    require(store['status'] == 'PASS' and store['starting_commit'] == qualified,
            'Prior store receipt is not the qualified pass')
    require(focused['success'] is True and focused['source_commit'] == qualified,
            'Prior focused receipt is not the qualified pass')
    require(store['source_before'] == store['source_after'] and store['source_unchanged'],
            'Original store source interval changed')
    require(store['direct_launcher_inputs_before'] == store['direct_launcher_inputs_after'],
            'Original store direct input interval changed')
    require(all(x['status'] == 'PASS' and x['exit_code'] == 0 for x in store['checks']),
            'Prior store receipt contains a nonpassing check')

    phases = {'qualified': qualified, 'incoming_main': prior['incoming_target'],
              'prior_merged_checkpoint': prior['merged_head_readback']['head'],
              'final_target': target}
    trees = {name: tree(repo, commit) for name, commit in phases.items()}
    inventory = prior['unchanged_input_inventory']
    paths = {x['path'] for x in inventory}
    require(len(paths) == len(inventory) == 403, 'Unexpected continuity inventory')
    prefixes = tuple(prior['scope']['package_prefixes'])
    package_paths = {name for name in trees['qualified'] if name.startswith(prefixes)}
    require(len(package_paths) == 394, 'Unexpected original Mail package selection')
    exception = prior['analysis_scope_exception']['path']
    require(package_paths - paths == {exception}, 'Unaccounted Mail package records')
    require({x['path'] for x in prior['scope']['changed_package_configurations']} == {exception},
            'Unexpected permitted configuration changes')
    selected = paths | set(store['source_before']) | {exception}
    global_config_paths = {name for name in trees['qualified']
                           if '/' not in name and PurePosixPath(name).suffix in {'.yaml', '.lock'}}
    selected |= global_config_paths
    inherited_controls = {f'{parent}{name}' for parent in ('', 'packages/', 'third_party/')
                          for name in ('dart_test.yaml', 'flutter_test_config.dart',
                                       'pubspec_overrides.yaml')}
    selected |= inherited_controls & set(trees['qualified'])
    contents = blobs(repo, [t[path]['git_blob'] for t in trees.values()
                           for path in selected if path in t and t[path]['kind'] == 'blob'])
    historical_checks = {}
    package_deltas = {}
    for phase, t in trees.items():
        require({name for name in t if name.startswith(prefixes)} == package_paths,
                f'Mail package path set changed at {phase}')
        deltas = []
        for path in sorted(package_paths):
            before = trees['qualified'][path]
            after = t[path]
            require(before['kind'] == after['kind'] == 'blob',
                    f'Unexpected package object type: {phase}:{path}')
            before_digest = sha(contents[before['git_blob']])
            after_digest = sha(contents[after['git_blob']])
            if before != after or before_digest != after_digest:
                deltas.append({'path': path,
                               'qualified': {**before, 'sha256': before_digest},
                               'compared': {**after, 'sha256': after_digest}})
        require({entry['path'] for entry in deltas} <= {exception},
                f'Unreviewed Mail package delta at {phase}')
        package_deltas[phase] = deltas
        for entry in inventory:
            path = entry['path']
            expected = {k: entry[k] for k in ('mode', 'kind', 'git_blob')}
            require(t.get(path) == expected, f'Inventory Git identity changed: {phase}:{path}')
            require(sha(contents[entry['git_blob']]) == entry['sha256'],
                    f'Inventory content digest differs: {phase}:{path}')
        configs = {name for name in t if '/' not in name
                   and PurePosixPath(name).suffix in {'.yaml', '.lock'}}
        require(configs == global_config_paths, f'Root YAML/lock path set changed at {phase}')
        require(all(t[path] == trees['qualified'][path] for path in configs),
                f'Root YAML/lock identity changed at {phase}')
        require({name: t.get(name) for name in inherited_controls} ==
                {name: trees['qualified'].get(name) for name in inherited_controls},
                f'Inherited test/override configuration changed at {phase}')
        for path, digest in store['source_before'].items():
            require(path in t and sha(contents[t[path]['git_blob']]) == digest,
                    f'Store source input changed: {phase}:{path}')
        historical_checks[phase] = {'source': phases[phase],
                                   'unchanged_inventory_records_verified': len(inventory),
                                   'mail_package_path_sets_identical': True,
                                   'mail_package_records_verified': len(package_paths),
                                   'unchanged_mail_package_records': len(package_paths) - len(deltas),
                                   'mail_package_deltas': deltas,
                                   'root_yaml_lock_path_sets_and_blobs_identical': True,
                                   'core_store_receipt_inputs_verified': len(store['source_before'])}

    allowed_options = {trees['qualified'][exception]['git_blob'],
                       trees['incoming_main'][exception]['git_blob']}
    for phase in ('prior_merged_checkpoint', 'final_target'):
        require(trees[phase][exception]['git_blob'] in allowed_options,
                f'Mail UI analyzer configuration has an unreviewed variant at {phase}')
        require(trees[phase][exception]['mode'] == trees['qualified'][exception]['mode']
                and trees[phase][exception]['kind'] == 'blob',
                f'Mail UI analyzer configuration type/mode changed at {phase}')
    # Check only the recorded two reviewed variants, rather than allowing arbitrary changes.
    require(contents[trees['incoming_main'][exception]['git_blob']] ==
            contents[trees['qualified'][exception]['git_blob']].replace(
                b'analyzer:\n  exclude:\n    - build/**\n', b'', 1),
            'Analyzer exception is broader than the reviewed exclusion removal')
    live_paths = selected | {exception}
    for path in sorted(live_paths):
        item = trees['final_target'][path]
        f = repo / path
        require(item['kind'] == 'blob', f'Unexpected non-blob selected input: {path}')
        if item['mode'] == '120000':
            require(f.is_symlink(), f'Live link type changed: {path}')
            actual = str(f.readlink()).encode()
        else:
            require(f.is_file() and not f.is_symlink(), f'Live input type changed: {path}')
            require(bool(f.stat().st_mode & stat.S_IXUSR) == (item['mode'] == '100755'),
                    f'Live input executable mode changed: {path}')
            actual = f.read_bytes()
        require(actual == contents[item['git_blob']], f'Live input content changed: {path}')
    for path in inherited_controls - set(trees['qualified']):
        require(not (repo / path).exists(), f'New untracked inherited configuration: {path}')

    for path, digest in store['direct_launcher_inputs_after'].items():
        require(file_hash(Path(path)) == digest, f'Live store launcher/native input changed: {path}')
    environment_files = {}
    for name in ('environment-before.json', 'environment-after.json'):
        f = a.focused_receipt.parent / name
        require(file_hash(f) == focused['manifest_sha256'][name], f'Original manifest digest mismatch: {name}')
        environment_files[name] = read(f)
    require(environment_files['environment-before.json'] == environment_files['environment-after.json'],
            'Original focused environment interval changed')
    package_config_hash = environment_files['environment-before.json']['workspace/package_config.json']
    require(file_hash(repo / '.dart_tool/package_config.json') == package_config_hash,
            'Resolved package mapping differs from qualified mapping')
    require(file_hash(repo / 'pubspec.lock') == focused['workspace_lock_sha256'],
            'Resolved workspace lock differs from qualified lock')

    case_path = a.qualified_review.parent / review['case_inventory']['file']
    require(file_hash(case_path) == review['case_inventory']['sha256'], 'Prior case inventory hash mismatch')
    cases = read(case_path)
    mail_cases = [case for case in cases if case['suite'].startswith(prefixes)]
    identities = {(c['suite'], c['name']) for c in mail_cases}
    require(len(identities) == len(mail_cases), 'Duplicate Mail scenario identities')
    cohorts = Counter()
    suite_counts = Counter()
    platforms = set()
    for case in mail_cases:
        suite_counts[case['suite']] += 1
        seen = set()
        for execution in case['executions']:
            key = (execution['cohort'], execution['platform'])
            require(key not in seen, f'Duplicate execution for {case["suite"]}:{case["name"]}')
            seen.add(key)
            cohorts[execution['cohort']] += 1
            platforms.add((case['suite'], execution['platform']))
    executions = sum(cohorts.values())
    retained = {'executions': executions, 'distinct_scenarios': len(identities),
                'distinct_suites': len(suite_counts), 'platform_repeat_executions': executions - len(identities)}
    for key, value in retained.items():
        require(value == prior['retained_mail_test_evidence'][key], f'Prior Mail count differs: {key}')
    require(retained == {'executions': 608, 'distinct_scenarios': 508,
                        'distinct_suites': 33, 'platform_repeat_executions': 100},
            'Unexpected retained Mail totals')
    core_store_cohorts = ('core-vm', 'core-node', 'store-vm', 'portable-node')
    core_store_cases = [c for c in mail_cases if c['suite'].startswith(
        ('packages/quds_mail_core/', 'packages/quds_mail_store/'))]
    require(sum(cohorts[name] for name in core_store_cohorts) == 250 and len(core_store_cases) == 162,
            'Unexpected core/store contribution')
    retained.update({'execution_source': qualified, 'executions_at_final_target': 0,
                     'core_store_executions': 250, 'core_store_distinct_scenarios': 162,
                     'focused_mail_executions': 346, 'configuration_node_repeat_executions': 12,
                     'cohorts': dict(cohorts), 'suite_counts': dict(sorted(suite_counts.items()))})
    require(cohorts['mail-configuration-node'] == 12 and executions - 250 - 12 == 346,
            'Unexpected focused Mail contribution')

    bound_files = [a.prior_report, a.qualified_review, case_path, a.store_receipt, a.focused_receipt,
                   a.focused_receipt.parent / 'environment-before.json',
                   a.focused_receipt.parent / 'environment-after.json']
    result = {
        'schema': 2,
        'accepted': True,
        'audited_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_source': qualified,
        'final_target': target,
        'final_tree': git(repo, 'rev-parse', f'{target}^{{tree}}').decode().strip(),
        'observed_live_head': git(repo, 'rev-parse', 'HEAD').decode().strip(),
        'scope': 'Read-only source/dependency continuity. No product tests executed or reattributed.',
        'phase_readbacks': historical_checks,
        'unchanged_inventory_records': len(inventory),
        'mail_package_records': len(package_paths),
        'unchanged_mail_package_records': len(package_paths) - len(package_deltas['final_target']),
        'final_mail_package_deltas': package_deltas['final_target'],
        'all_final_mail_package_records_identical_to_qualified': not package_deltas['final_target'],
        'unchanged_dart_source_test_tool_records': sum(
            path.endswith('.dart') and trees['qualified'][path] == trees['final_target'][path]
            for path in package_paths),
        'final_mail_package_inventory': [
            {'path': path, **trees['final_target'][path],
             'sha256': sha(contents[trees['final_target'][path]['git_blob']]),
             'identical_to_qualified': trees['final_target'][path] == trees['qualified'][path]}
            for path in sorted(package_paths)
        ],
        'all_selected_live_source_records_verified': len(live_paths),
        'root_yaml_lock_inputs': sorted(global_config_paths),
        'inherited_test_override_controls': sorted(inherited_controls),
        'incoming_analysis_configuration_observation': {
            'path': exception,
            'incoming_source': phases['incoming_main'],
            'incoming_change': prior['analysis_scope_exception']['change'],
            'qualified_git_blob': trees['qualified'][exception]['git_blob'],
            'incoming_git_blob': trees['incoming_main'][exception]['git_blob'],
            'final_git_blob': trees['final_target'][exception]['git_blob'],
            'final_sha256': sha(contents[trees['final_target'][exception]['git_blob']]),
            'incoming_change_retained_in_final':
                trees['final_target'][exception] != trees['qualified'][exception],
            'final_matches_qualified':
                trees['final_target'][exception] == trees['qualified'][exception],
            'live_bytes_match_final_commit': True,
        },
        'dependency_binding': {
            'source_import_closure': prior['dependency_closure'],
            'resolved_package_config_sha256': package_config_hash,
            'resolved_package_config_matches_qualified_environment': True,
            'workspace_lock_sha256': focused['workspace_lock_sha256'],
            'store_direct_launcher_native_input_records': len(store['direct_launcher_inputs_after']),
            'all_store_direct_launcher_native_inputs_match_original_interval_and_live': True,
            'scope': 'Source import closure and resolved mapping remain unchanged. This readback checks the seven recorded direct store launcher/native inputs; it does not add a new full-runtime interval capture. The separately audited host run owns its recorded runtime interval.',
        },
        'retained_mail_test_evidence': retained,
        'fresh_host_consumer': {
            'path': 'packages/quds_office_editor/example/lib/studio_mail.dart',
            'outside_prior_mail_execution_closure': True,
            'report': 'docs/validation/office-main-integration-20261119/host-final/README.md',
            'counts_added_to_retained_mail_totals': 0,
        },
        'input_reports': [{'path': str(f.resolve()), 'sha256': file_hash(f)} for f in bound_files],
        'script_sha256': file_hash(Path(__file__)),
        'github_actions': 'NOT QUERIED OR AWAITED',
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'accepted': True, 'target': target, 'retained_mail_counts':
                      {k: retained[k] for k in ('executions', 'distinct_scenarios', 'distinct_suites', 'platform_repeat_executions')},
                      'source_inventory_records': len(inventory), 'output': str(output),
                      'output_sha256': file_hash(output)}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f'Mail continuity audit failed: {error}', file=sys.stderr)
        raise SystemExit(1)
