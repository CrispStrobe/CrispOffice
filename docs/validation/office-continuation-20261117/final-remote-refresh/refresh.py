import concurrent.futures
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess

OUTPUT = pathlib.Path('/workspace/scratch/f423a275b479/final-remote-refresh')
SOURCE = pathlib.Path(
    '/workspace/scratch/f423a275b479/quds_office_suite/docs/validation/'
    'office-continuation-20261117/incoming-inventory.json'
)
REPOSITORIES = {
    'fork': 'https://github.com/CrispStrobe/quds_office_suite.git',
    'upstream': 'https://github.com/MohammedAsaadAsaad/quds_office_suite.git',
}
EXPECTED_ADVANCES = {
    'refs/remotes/origin/codex/text-rendering-20261116',
    'refs/remotes/fork-pr/72',
}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def observe(item):
    name, repository = item
    command = [
        'git', 'ls-remote', repository, 'refs/heads/*', 'refs/pull/*/head',
    ]
    started = now()
    result = subprocess.run(
        command, capture_output=True, timeout=60,
        env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'},
    )
    finished = now()
    (OUTPUT / f'{name}.stdout.txt').write_bytes(result.stdout)
    (OUTPUT / f'{name}.stderr.txt').write_bytes(result.stderr)
    receipt = {
        'name': name,
        'command': command,
        'started_at_utc': started,
        'finished_at_utc': finished,
        'exit_code': result.returncode,
        'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
        'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(),
    }
    (OUTPUT / f'{name}.command.json').write_text(
        json.dumps(receipt, indent=2) + '\n',
    )
    if result.returncode:
        raise RuntimeError(f'{name} ls-remote failed: {result.returncode}')
    refs = {}
    for line in result.stdout.decode().splitlines():
        sha, ref = line.split('\t')
        if not re.fullmatch('[0-9a-f]{40}', sha):
            raise ValueError(f'Invalid object ID in {name} output')
        if ref.startswith('refs/heads/'):
            remote = 'origin' if name == 'fork' else 'upstream'
            mapped = f'refs/remotes/{remote}/{ref[len("refs/heads/"):]}'
        elif re.fullmatch(r'refs/pull/[0-9]+/head', ref):
            remote = 'fork-pr' if name == 'fork' else 'upstream-pr'
            mapped = f'refs/remotes/{remote}/{ref.split("/")[2]}'
        else:
            raise ValueError(f'Unexpected advertised ref: {ref}')
        if mapped in refs:
            raise ValueError(f'Duplicate advertised ref: {mapped}')
        refs[mapped] = sha
    return receipt, refs


OUTPUT.mkdir(exist_ok=True)
source_bytes = SOURCE.read_bytes()
(OUTPUT / 'incoming-inventory-used.json').write_bytes(source_bytes)
baseline = json.loads(source_bytes)
before = {item['ref']: item['sha'] for item in baseline['refs']}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    observations = list(executor.map(observe, REPOSITORIES.items()))
after = {ref: sha for _, refs in observations for ref, sha in refs.items()}
changes = [
    {
        'ref': ref,
        'previous_sha': before.get(ref),
        'observed_sha': after.get(ref),
        'kind': 'added' if ref not in before else 'removed' if ref not in after else 'advanced_or_changed',
    }
    for ref in sorted(before.keys() | after.keys())
    if before.get(ref) != after.get(ref)
]
expected = [
    change for change in changes
    if change['ref'] in EXPECTED_ADVANCES
    and change['previous_sha'] is not None
    and change['observed_sha'] is not None
]
external = [change for change in changes if change not in expected]
comparison = {
    'completed_at_utc': now(),
    'frozen_inventory_at_utc': baseline['frozen_at_utc'],
    'inventory_sha256': hashlib.sha256(source_bytes).hexdigest(),
    'commands': [receipt for receipt, _ in observations],
    'previous_reference_count': len(before),
    'observed_reference_count': len(after),
    'observed_distinct_shas': len(set(after.values())),
    'counts': {
        remote: sum(ref.startswith(f'refs/remotes/{remote}/') for ref in after)
        for remote in ['origin', 'fork-pr', 'upstream', 'upstream-pr']
    },
    'expected_work_branch_advances': expected,
    'external_changes': external,
    'external_refs_unchanged': not external,
    'refs': [{'ref': ref, 'sha': sha} for ref, sha in sorted(after.items())],
    'scope': 'One read-only ls-remote per repository; no CI, Actions, check or status endpoints queried; no local or remote refs changed.',
}
(OUTPUT / 'comparison.json').write_text(json.dumps(comparison, indent=2) + '\n')
print(json.dumps({key: value for key, value in comparison.items() if key != 'refs'}, indent=2))
