#!/usr/bin/env python3
"""Audit fresh local receipts, exact source/runtime inputs and remote ancestry.

This reuses the preceding independent auditor's log/source/runtime checks, not
the qualification runner. It does not rerun tests or access GitHub Actions.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BASELINE = '74b6b39e7941ab351133023b4165cbd6101d2877'
PREVIOUS = HERE.parent / 'office-continuation-20261117' / 'verify_final.py'
spec = importlib.util.spec_from_file_location('previous_independent_auditor', PREVIOUS)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
audit.HERE = HERE
audit.REPO = REPO
audit.BASELINE = BASELINE
audit.EXPECTED_TESTS = json.loads((HERE / 'cohorts.json').read_bytes())
require = audit.require
sha = audit.sha


def read_json(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def verify_inventory(head, tree):
    directory = HERE / 'incoming'
    stored = read_json(directory / 'sha256.json')
    for name, expected in stored.items():
        path = directory / name
        require(path.resolve().is_relative_to(directory), 'Inventory path escapes directory')
        raw = path.read_bytes()
        require(len(raw) == expected['bytes'] and sha(raw) == expected['sha256'],
                'Stored inventory hash mismatch: ' + name)
        audit.verify_committed(path, tree)
    audit.verify_committed(directory / 'sha256.json', tree)
    captured = read_json(directory / 'captured-sha256.json')
    for name, expected in captured.items():
        if name in {'README.md', 'inventory.json'}:
            raw = gzip.decompress((directory / 'snapshot-originals' / (name + '.gz')).read_bytes())
        elif name.startswith('raw/'):
            raw = gzip.decompress((directory / (name + '.gz')).read_bytes())
        else:
            raw = (directory / name).read_bytes()
        require(len(raw) == expected['bytes'] and sha(raw) == expected['sha256'],
                'Captured inventory payload changed: ' + name)
    inventory = read_json(directory / 'inventory.json')
    original = read_json(directory / 'snapshot-originals/inventory.json.gz')
    routed = json.loads(json.dumps(inventory))
    routed.pop('raw_storage')
    for observation in routed['observations']:
        observation['file'] = observation['file'].removesuffix('.gz')
    require(routed == original, 'Normalized inventory changed beyond compressed-file routing')
    reconstructed = {}
    pages = {}
    for observation in inventory['observations']:
        key = observation['key']
        if key == 'fork-metadata':
            continue
        source, kind, page = key.split('-')
        rows = read_json(directory / observation['file'])
        require(len(rows) == observation['count'], 'Inventory page count changed: ' + key)
        pages.setdefault((source, kind), []).append((int(page), len(rows)))
        for row in rows:
            if kind == 'branches':
                ref, commit = 'refs/heads/' + row['name'], row['commit']['sha']
            else:
                ref, commit = 'refs/pull/' + str(row['number']) + '/head', row['head']['sha']
            identity = (source, ref)
            require(identity not in reconstructed, 'Duplicated raw reference: ' + repr(identity))
            reconstructed[identity] = commit
    for identity, observations in pages.items():
        observations.sort()
        require([number for number, _ in observations] == list(range(1, len(observations) + 1)),
                'Nonconsecutive inventory pages: ' + repr(identity))
        require(observations[-1][1] == 0, 'Collection lacks its terminal empty page')
    refs = inventory['refs']
    normalized = {(row['source'], row['ref']): row['sha'] for row in refs}
    require(len(normalized) == len(refs) == inventory['reference_count'] == 204,
            'Reference count/identity mismatch')
    require(normalized == reconstructed, 'Normalized refs differ from captured API pages')
    commits = set(normalized.values())
    require(len(commits) == inventory['distinct_head_commits'] == 137,
            'Distinct head count mismatch')
    for commit in sorted(commits):
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', commit, head], cwd=REPO).returncode == 0,
                'Pinned incoming head is absent from final ancestry: ' + commit)
    counts = Counter(row['source'] + '_' + ('branches' if row['kind'] == 'branch' else 'pulls')
                     for row in refs)
    require(dict(counts) == inventory['counts'], 'Reference category counts differ')
    return {'references': len(refs), 'distinct_heads': len(commits), 'counts': dict(counts),
            'observation_started_at': inventory['observation_started_at'],
            'observation_completed_at': inventory['observation_completed_at'],
            'all_included_by_ancestry': True, 'captured_payload_hashes_verified': len(captured)}


def verify_refresh(head, tree):
    directory = HERE / 'final-refresh'
    inventory = read_json(directory / 'inventory.json')
    audit.verify_committed(directory / 'inventory.json', tree)
    reconstructed = {}
    for observation in inventory['captured']:
        path = directory / observation['file']
        raw = path.read_bytes()
        require(sha(raw) == observation['sha256'], 'Refresh raw observation changed')
        audit.verify_committed(path, tree)
        for line in raw.decode().splitlines():
            commit, ref = line.split()
            key = (observation['source'], ref)
            require(key not in reconstructed, 'Duplicate refreshed reference')
            reconstructed[key] = commit
    refs = inventory['refs']
    normalized = {(row['source'], row['ref']): row['sha'] for row in refs}
    require(reconstructed == normalized and len(normalized) == len(refs) == 206,
            'Refreshed reference identities/count differ')
    require(len(set(normalized.values())) == inventory['distinct_heads'] == 138,
            'Refreshed distinct head count differs')
    original = read_json(HERE / 'incoming/inventory.json')['refs']
    union = {(row['source'], row['ref'], row['sha']) for row in original + refs}
    heads = {row[2] for row in union}
    require(len(union) == inventory['union_reference_revision_pairs'] == 213,
            'Union reference/revision count differs')
    require(len(heads) == inventory['union_distinct_heads'] == 142,
            'Union commit count differs')
    for commit in sorted(heads):
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', commit, head], cwd=REPO).returncode == 0,
                'A captured original/refreshed head is absent: ' + commit)
    return {'references': len(refs), 'distinct_heads': len(set(normalized.values())),
            'union_reference_revision_pairs': len(union), 'union_distinct_heads': len(heads),
            'observed_at_utc': [item['observed_at_utc'] for item in inventory['captured']],
            'all_original_and_refreshed_heads_included': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--head', required=True)
    parser.add_argument('--branch', default='codex/text-rendering-20261116')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = {'started_utc': datetime.now(timezone.utc).isoformat(), 'head': args.head,
              'branch': args.branch, 'github_actions_used': False}
    try:
        require(audit.git('rev-parse', 'HEAD') == args.head, 'Checkout is not the requested head')
        require(not audit.git('status', '--porcelain', '--untracked-files=no'), 'Tracked checkout is dirty')
        advertised = audit.git('ls-remote', 'origin', 'refs/heads/' + args.branch).split()
        require(advertised == [args.head, 'refs/heads/' + args.branch],
                'Advertised remote branch differs from the requested head')
        tree = audit.tree_entries(args.head)
        for path in [Path(__file__), PREVIOUS, HERE / 'cohorts.json', HERE / 'validate.py']:
            audit.verify_committed(path, tree)
        runtime = audit.runtime_audit(tree)
        cohorts = {name: audit.cohort_audit(name, args.head, tree, runtime)
                   for name in audit.EXPECTED_TESTS}
        # The inherited auditor covers render/logical-render. Bind the new
        # fixture directories and their independent verification receipts too.
        for name in ['conditional-render', 'odf-fixtures']:
            directory = HERE / 'engine' / name
            require(directory.is_dir(), 'Missing new fixture directory: ' + name)
            for path in sorted(directory.rglob('*')):
                if path.is_file():
                    cohorts['engine']['artifacts'][str(path.relative_to(HERE / 'engine'))] = audit.verify_committed(path, tree)
        for name in ['verify_conditional_pdf.py', 'verify_odf_fixtures.py']:
            audit.verify_committed(HERE / name, tree)
        report['runtime'] = runtime
        report['cohorts'] = cohorts
        report['incoming'] = verify_inventory(args.head, tree)
        report['final_refresh'] = verify_refresh(args.head, tree)
        report['total_passed_tests'] = sum(item['passed_tests'] for item in cohorts.values())
        report['total_test_files'] = sum(item['test_files'] for item in cohorts.values())
        report['remote_head'] = args.head
        report['remote_tree'] = audit.git('rev-parse', args.head + '^{tree}')
        report['passed'] = True
    except Exception as error:
        report['passed'] = False
        report['error'] = str(error)
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items()
                      if key not in {'runtime', 'cohorts'}}))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
