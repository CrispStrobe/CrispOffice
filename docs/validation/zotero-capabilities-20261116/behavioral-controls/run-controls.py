#!/usr/bin/env python3
"""Run identical regression assertions against pinned before/after sources."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent
TOOLCHAIN = ROOT.parent
DART = str(TOOLCHAIN / 'flutter-sdk/bin/cache/dart-sdk/bin/dart')
SNAPSHOT = str(TOOLCHAIN / 'flutter-sdk/bin/cache/flutter_tools.snapshot')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    setup = json.loads((ROOT / 'source-receipt.json').read_text())
    logs = ROOT / 'logs'
    logs.mkdir(exist_ok=True)
    receipt = {
        'recorded_utc': datetime.now(timezone.utc).isoformat(),
        'commits': setup['commits'],
        'source_receipt_sha256': sha(ROOT / 'source-receipt.json'),
        'scope': 'Behavioral before/after controls, not additional final-cohort test counts.',
        'production_sources_or_manifests_modified': False,
        'github_actions_queried_awaited_or_rerun': False,
        'runs': [],
    }
    for suite, package, args, passed_count in [
        ('alias', 'quds_office_engine', ['test', '--reporter', 'expanded', 'test/alias_bridge_control_test.dart'], 1),
        ('dialog', 'quds_office_editor', [SNAPSHOT, 'test', '--no-pub', '--reporter', 'expanded', 'test/word_zotero_dialog_scaling_test.dart'], 2),
    ]:
        for label in ['before', 'after']:
            cwd = ROOT / label / 'packages' / package
            command = [DART, *args]
            log = logs / f'{suite}-{label}.log'
            start = time.monotonic()
            with log.open('w') as stream:
                result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
            content = log.read_text()
            expected_failure = label == 'before'
            matches = (
                result.returncode == 1
                and ('Actual: [' in content and 'Which: has length of <2>' in content
                     if suite == 'alias'
                     else 'Actual: <4>' in content and 'Expected: <1>' in content)
                and 'Compilation failed' not in content
                and "Couldn't resolve" not in content
                if expected_failure
                else result.returncode == 0 and f'+{passed_count}: All tests passed!' in content
            )
            item = {
                'suite': suite,
                'version': label,
                'source_commit': setup['commits'][label],
                'cwd': str(cwd),
                'command': command,
                'exit_code': result.returncode,
                'elapsed_seconds': round(time.monotonic() - start, 3),
                'expected_behavioral_failure': expected_failure,
                'expected_observation_confirmed': matches,
                'log': str(log.relative_to(ROOT)),
                'log_sha256': sha(log),
                'test_sha256': sha(cwd / args[-1]),
                'manifest_sha256': sha(cwd / 'pubspec.yaml'),
                'lockfile_sha256': sha(cwd / 'pubspec.lock'),
                'package_config_sha256': sha(cwd / '.dart_tool/package_config.json'),
            }
            receipt['runs'].append(item)
            (ROOT / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
            print(json.dumps({k: item[k] for k in ['suite', 'version', 'exit_code', 'expected_observation_confirmed', 'log']}), flush=True)
    receipt['all_expected_observations_confirmed'] = all(row['expected_observation_confirmed'] for row in receipt['runs'])
    (ROOT / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not receipt['all_expected_observations_confirmed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
