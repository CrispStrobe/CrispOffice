#!/usr/bin/env python3
"""Verify retained evidence hashes and equality with the locally qualified source."""

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main() -> None:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=here.parents[2])
    parser.add_argument('--runtime', action='store_true',
                        help='Also verify the original absolute runtime paths on this host.')
    args = parser.parse_args()
    repo = args.repository.resolve()
    evidence = json.loads((here / 'EVIDENCE.json').read_text())
    errors = []
    for name, expected in evidence['files'].items():
        path = (here / name).resolve()
        if not path.is_relative_to(here) or not path.is_file():
            errors.append('Missing or escaping evidence: ' + name)
        elif path.stat().st_size != expected['bytes'] or digest(path) != expected['sha256']:
            errors.append('Evidence mismatch: ' + name)

    receipt = json.loads((here / 'integration/receipt.json').read_text())
    if receipt.get('status') != 'passed' or receipt.get('passed') is not True:
        errors.append('The integration receipt did not pass.')
    manifest = here / 'integration' / receipt['source_after']['path']
    if digest(manifest) != receipt['source_after']['sha256']:
        errors.append('Qualified source manifest hash mismatch.')
    qualified = json.loads(gzip.decompress(manifest.read_bytes()))

    spec = importlib.util.spec_from_file_location(
        'proofing_integration', repo / 'tools/proofing/verify_integration.py')
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    current = module.source_hashes()
    if current != qualified:
        errors.extend('Source mismatch: ' + name for name in sorted(set(current) | set(qualified))
                      if current.get(name) != qualified.get(name))

    def git(*values: str) -> str:
        return subprocess.check_output(['git', *values], cwd=repo, text=True).strip()

    source_commit = receipt['source_commit']
    diff = git('diff', '--name-only', source_commit, 'HEAD').splitlines()
    nondoc = [name for name in diff if not name.startswith('docs/')]
    if nondoc:
        errors.append('Non-documentation changes after qualification: ' + ', '.join(nondoc))
    reconciliation = json.loads((here / 'final-reconciliation.json').read_text())
    for sha in sorted({row['sha'] for row in reconciliation['refs']}):
        result = subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'HEAD'], cwd=repo)
        if result.returncode:
            errors.append('Missing captured incoming head: ' + sha)

    runtime_count = 0
    if args.runtime:
        for name, expected in receipt['runtime_sha256_after'].items():
            path = Path(name)
            if not path.is_file() or digest(path) != expected:
                errors.append('Runtime mismatch: ' + name)
            runtime_count += 1

    result = {
        'status': 'passed' if not errors else 'failed',
        'verified_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_source': source_commit, 'checked_head': git('rev-parse', 'HEAD'),
        'evidence_files': len(evidence['files']), 'source_inputs': len(current),
        'runtime_files_checked': runtime_count,
        'captured_refs': len(reconciliation['refs']),
        'captured_distinct_heads': len({row['sha'] for row in reconciliation['refs']}),
        'changes_after_qualification_are_documentation_only': not nondoc,
        'errors': errors,
    }
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if not errors else 1)


if __name__ == '__main__':
    main()
