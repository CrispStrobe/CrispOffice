#!/usr/bin/env python3
"""Select accepted runs, recount raw test events and verify their exact inputs."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/mail'))
from check_store import test_summary  # noqa: E402

RUNS = (
    ('mail-cached-store-final-recovery/receipt.json', None),
    ('mail-cached-shared-final-recovery/receipt.json', None),
    ('mail-cached-studio-final-recovery/receipt.json', None),
    ('mail_intake_audit/word-qualification/receipt.json', ('word-regression',)),
    ('mail_intake_audit/word-portable-final/receipt.json', None),
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def source_hash(value: str | dict[str, str]) -> str:
    return value if isinstance(value, str) else value['sha256']


def suite_paths(log: Path) -> list[str]:
    suites = set()
    for line in log.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict) and event.get('type') == 'suite':
            path = event.get('suite', {}).get('path')
            if path:
                suites.add(path)
    return sorted(suites)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    accepted, union = [], {}
    for name, selection in RUNS:
        path = scratch / name
        receipt = json.loads(path.read_text())
        if selection is None:
            require(receipt['status'] == 'PASS', 'Run not passing: ' + name)
        require(receipt['source_unchanged'], 'Source changed during: ' + name)
        before, after = receipt['source_before'], receipt['source_after']
        require(before == after, 'Source manifests differ: ' + name)
        for relative, value in before.items():
            expected = source_hash(value)
            require(sha(ROOT / relative) == expected, 'Source differs now: ' + relative)
            require(relative not in union or union[relative] == expected,
                    'Conflicting accepted source: ' + relative)
            union[relative] = expected
        for first, last in (
            ('runtime_before', 'runtime_after'),
            ('direct_launcher_inputs_before', 'direct_launcher_inputs_after'),
        ):
            if first in receipt:
                require(receipt[first] == receipt[last], 'Runtime changed: ' + name)
                for file, expected in receipt[first].items():
                    require(expected is not None and sha(Path(file)) == expected,
                            'Runtime input differs: ' + file)
        runtime = receipt.get('runtime')
        if runtime is not None:
            require(receipt['runtime_configuration_unchanged'], 'Word runtime changed')
            for key in ('dart', 'package_config', 'test_entry'):
                require(sha(Path(runtime[key])) == runtime[key + '_sha256'],
                        'Word runtime differs: ' + key)
        selected = [check for check in receipt['checks']
                    if selection is None or check['name'] in selection]
        if selection is not None:
            require({check['name'] for check in selected} == set(selection),
                    'Selected checks missing: ' + name)
        checks = []
        for check in selected:
            require(check['status'] == 'PASS' and check['exit_code'] == 0,
                    'Check not passing: ' + check['name'])
            log = path.parent / check['log']
            require(sha(log) == check['log_sha256'], 'Raw log changed: ' + str(log))
            if 'stderr' in check:
                require(sha(path.parent / check['stderr']) == check['stderr_sha256'],
                        'Stderr changed: ' + check['name'])
            result = dict(name=check['name'], status='PASS', log=check['log'],
                          log_sha256=check['log_sha256'])
            recorded = check.get('tests', check.get('summary'))
            if recorded is not None:
                summary = test_summary(log)
                recounted = {key: value for key, value in summary.items() if key != 'cases'}
                require(recounted == recorded and summary['valid'],
                        'Raw event recount differs: ' + check['name'])
                result.update(tests=recounted, test_files=suite_paths(log))
            checks.append(result)
        accepted.append(dict(receipt=name, receipt_sha256=sha(path),
                             selection=list(selection) if selection else 'all',
                             source_inputs=len(before), checks=checks))
    changed = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'],
                                      cwd=ROOT, text=True).splitlines()
    require(not set(changed).intersection(union), 'Qualified source is uncommitted')
    portable = json.loads((scratch / RUNS[-1][0]).read_text())
    require(portable['portable_raw_equal'] and portable['portable_json_equal'],
            'Word VM/Node outputs differ')
    result = dict(
        status='PASS', verified_at=datetime.now(timezone.utc).isoformat(),
        verified_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                cwd=ROOT, text=True).strip(),
        verified_tree=subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'],
                                              cwd=ROOT, text=True).strip(),
        accepted=accepted, unique_source_inputs=len(union),
        source_fingerprints_sha256=hashlib.sha256(
            json.dumps(union, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        all_accepted_sources_match_current_tree=True,
        raw_test_events_recounted=True,
        github_actions='NOT QUERIED OR AWAITED',
        partial_selection_reason=(
            'Only word-regression is selected from the initial Word aggregate; '
            'its unrelated Node invocation was rejected for empty output. '
            'The corrected complete portable-static run is accepted separately. '
            'Earlier development runs and interrupted Studio attempts are retained '
            'but contribute no final counts.'),
    )
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'accepted'}))
    for item in accepted:
        for check in item['checks']:
            if 'tests' in check:
                print(json.dumps(dict(run=item['receipt'], check=check['name'],
                                      passed=check['tests']['passed'],
                                      files=len(check['test_files']))))


if __name__ == '__main__':
    main()
