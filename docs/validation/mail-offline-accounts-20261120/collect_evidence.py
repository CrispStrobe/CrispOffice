#!/usr/bin/env python3
"""Seal completed local qualification, retaining rejected development evidence."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = Path(__file__).resolve().parent


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_receipt(path: Path, *, accepted: bool = True) -> dict:
    receipt = json.loads(path.read_text())
    if accepted:
        assert receipt['status'] == 'PASS', (path, receipt['status'])
        assert receipt['source_unchanged'] is True, path
    return receipt


def test_cases(log: Path, cwd: str) -> dict[tuple[str, str, int], str]:
    suites, starts, cases, occurrences = {}, {}, {}, {}
    for line in log.read_text().split('\n'):
        record = line.strip()
        for prefix in ('Running build hooks...', 'Running link hooks...'):
            if record.startswith(prefix):
                record = record[len(prefix):].lstrip()
        if not record:
            continue
        event = json.loads(record)
        kind = event.get('type')
        if kind == 'suite':
            suite = event['suite']
            path = Path(suite['path'])
            absolute = path if path.is_absolute() else Path(cwd) / path
            suites[suite['id']] = str(absolute.relative_to(ROOT))
        elif kind == 'testStart':
            case = event['test']
            starts[case['id']] = case
            if not case['name'].startswith('loading '):
                identity = (suites[case['suiteID']], case['name'])
                occurrences[identity] = occurrences.get(identity, 0) + 1
                case['coverage_key'] = (*identity, occurrences[identity])
        elif kind == 'testDone':
            case = starts[event['testID']]
            if event['hidden'] or case['name'].startswith('loading '):
                continue
            assert not event['skipped'], case
            key = case['coverage_key']
            assert key not in cases, key
            cases[key] = event['result']
    return cases


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-workspace', required=True, type=Path)
    args = parser.parse_args()
    workspace = args.runtime_workspace.resolve()
    accepted = {
        name: read_receipt(workspace / directory / 'receipt.json')
        for name, directory in (
            ('store', 'accepted-store-checks'),
            ('mail', 'accepted-mail-checks'),
            ('office', 'accepted-office-checks'),
        )
    }
    broad = read_receipt(workspace / 'final-host-checks/receipt.json', accepted=False)
    assert broad['source_unchanged'] is True
    checks = {item['name']: item for item in broad['checks']}
    for name in ('shared-mail-ui', 'mime-transport'):
        assert checks[name]['status'] == 'PASS'
    # The unchanged shared UI/MIME/transport inputs retain their broad evidence.
    for path, expected in broad['source_after'].items():
        if path.startswith(('packages/quds_mail_core/', 'packages/quds_mail_ui/',
                            'packages/quds_mail_mime/', 'packages/quds_mail_transport/',
                            'third_party/enough_mail/')) or path in ('.fvmrc', 'pubspec.yaml', 'pubspec.lock'):
            assert digest((ROOT / path).read_bytes()) == expected, path
    base = test_cases(workspace / 'final-host-checks/incoming-automation.jsonl',
                      checks['incoming-automation']['cwd'])
    assert len(base) == checks['incoming-automation']['tests']['passed'] + checks['incoming-automation']['tests']['failed']
    original_paths = {key[0] for key in base}
    original_failed = {key for key, result in base.items() if result != 'success'}
    replacements = []
    for name in ('automation-cli-retry', 'word-preservation'):
        check = next(item for item in accepted['office']['checks'] if item['name'] == name)
        current = test_cases(workspace / 'accepted-office-checks' / check['log'], check['cwd'])
        assert all(result == 'success' for result in current.values())
        relevant = {key: value for key, value in current.items() if key[0] in original_paths}
        paths = {key[0] for key in relevant}
        old_keys = {key for key in base if key[0] in paths}
        assert old_keys.issubset(relevant), (name, old_keys - relevant.keys())
        base = {key: value for key, value in base.items() if key[0] not in paths}
        base.update(relevant)
        replacements.append(dict(cohort=name, replaced_paths=sorted(paths), accepted_cases=len(relevant)))
    assert all(result == 'success' for result in base.values())
    assert all(base[key] == 'success' for key in original_failed)
    current_inputs = accepted['mail']['source_after']
    for path, expected in current_inputs.items():
        assert digest((ROOT / path).read_bytes()) == expected, path
    for receipt in accepted.values():
        for path, expected in receipt['source_after'].items():
            assert digest((ROOT / path).read_bytes()) == expected, path
    summary = dict(
        status='PASS', sealed_at=datetime.now(timezone.utc).isoformat(),
        source_commit=accepted['mail']['source_commit'], source_tree=accepted['mail']['source_tree'],
        current_code_inputs_match=True, github_actions='NOT USED',
        accepted_checks={name: receipt['checks'] for name, receipt in accepted.items()},
        unchanged_broad_checks={name: checks[name] for name in ('shared-mail-ui', 'mime-transport')},
        automation_coverage=dict(
            accepted_cases=len(base), files=len(original_paths),
            initial_passed=checks['incoming-automation']['tests']['passed'],
            initial_failed=checks['incoming-automation']['tests']['failed'],
            complete_file_replacements=replacements,
            method='Retain broad cases; replace complete affected files with final passing runs; add new Word regressions; never count overlaps twice.',
            qualification_scope='Broad original incoming source plus complete affected-file reruns on final reviewed source; not a second execution of all 53 automation files.'),
        boundaries=['Native fixture qualification; no live providers or installed app packages.',
                    'Browser entry/worker compilation and Node checks do not execute browser storage.',
                    'Local draft entry does not provide an offline inbox or provider Drafts synchronization.'])
    members: dict[str, bytes] = {}
    for directory, label in (
        ('accepted-store-checks', 'accepted/store'), ('accepted-mail-checks', 'accepted/mail'),
        ('accepted-office-checks', 'accepted/office'), ('final-store-checks', 'prior/store'),
        ('final-host-checks', 'prior/host'), ('word-namespace-checks', 'review/word'),
    ):
        for path in sorted((workspace / directory).iterdir()):
            if path.is_file() and path.suffix in ('.json', '.jsonl', '.log', '.stderr'):
                members[f'{label}/{path.name}'] = path.read_bytes()
    for pattern in ('analysis-*.log', 'store-directory-*.jsonl', 'store-directory-*.stderr',
                    'store-migration-*.jsonl', 'store-migration-*.stderr',
                    'studio-directory-*.jsonl', 'studio-directory-*.stderr',
                    'directory-review*.jsonl', 'directory-review*.stderr', 'directory-review*.log'):
        for path in sorted(workspace.glob(pattern)):
            members[f'development/{path.name}'] = path.read_bytes()
    for filename in ('runtime.json', 'pub-cache-receipt.json', 'env.sh'):
        path = workspace / 'runtime' / filename
        members[f'runtime/{filename}'] = path.read_bytes()
    for path in sorted((workspace / 'runtime/logs').glob('*.log')):
        members[f'runtime/logs/{path.name}'] = path.read_bytes()
    for path in sorted((workspace / 'retained-cli-timeout-artifacts').rglob('*')):
        if path.is_file():
            members['development/timeout-artifacts/' + str(path.relative_to(workspace / 'retained-cli-timeout-artifacts'))] = path.read_bytes()
    for filename in ('run_host_checks.py', 'collect_evidence.py', 'peer-review.md'):
        members[f'method/{filename}'] = (OUTPUT / filename).read_bytes()
    summary_bytes = (json.dumps(summary, indent=2) + '\n').encode()
    members['qualification.json'] = summary_bytes
    archive = OUTPUT / 'evidence.tar.xz'
    with tarfile.open(archive, 'w:xz', preset=6) as tar:
        for name, data in sorted(members.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    with tarfile.open(archive, 'r:xz') as tar:
        actual = {item.name: tar.extractfile(item).read() for item in tar.getmembers()}
    assert actual == members
    manifest = dict(archive=archive.name, sha256=digest(archive.read_bytes()), bytes=archive.stat().st_size,
                    member_count=len(members), members=[dict(name=name, bytes=len(data), sha256=digest(data))
                                                       for name, data in sorted(members.items())])
    (OUTPUT / 'evidence-files.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (OUTPUT / 'qualification.json').write_bytes(summary_bytes)
    print(json.dumps({key: value for key, value in manifest.items() if key != 'members'}))
    print(json.dumps(summary['automation_coverage']))


if __name__ == '__main__':
    main()
