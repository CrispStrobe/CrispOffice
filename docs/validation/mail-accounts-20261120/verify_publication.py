#!/usr/bin/env python3
"""Verify that a publication preserves the qualified source and captured main.

This uses committed Git objects, not checkout timestamps or generated runtime
paths. Only the three documented documentation areas may differ from the
qualified commit. It does not execute Dart or Flutter tests.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--ref', default='HEAD')
    parser.add_argument('--manifest', type=Path,
                        default=Path(__file__).with_name('source-continuity.json'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())

    def git(*values):
        return subprocess.check_output(['git', *values], cwd=args.repo)

    def allowed(path):
        return (path in manifest['allowed_documentation_paths']
                or any(path.startswith(prefix) for prefix in
                       manifest['allowed_documentation_prefixes']))

    def entries(ref):
        result = {}
        for item in git('ls-tree', '-r', '-z', ref).split(b'\0'):
            if not item:
                continue
            metadata, raw_path = item.split(b'\t', 1)
            mode, kind, sha = metadata.decode().split()
            path = raw_path.decode()
            if not allowed(path):
                result[path] = {'mode': mode, 'type': kind, 'sha': sha}
        return result

    def ancestor(ref, target):
        result = subprocess.run(['git', 'merge-base', '--is-ancestor', ref, target],
                                cwd=args.repo, capture_output=True)
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.decode())
        return result.returncode == 0

    qualified = manifest['qualified_source_commit']
    qualified_entries = entries(qualified)
    expected = manifest.get('protected_entries', qualified_entries)
    target = git('rev-parse', args.ref + '^{commit}').decode().strip()
    observed = entries(target)
    baseline_matches = qualified_entries == expected
    differences = [path for path in sorted(expected.keys() | observed.keys())
                   if expected.get(path) != observed.get(path)]
    qualified_ancestor = ancestor(qualified, target)
    main_ancestor = ancestor(manifest['captured_main_commit'], target)
    digest = hashlib.sha256(json.dumps(expected, sort_keys=True,
                                      separators=(',', ':')).encode()).hexdigest()
    manifest_valid = digest == manifest['protected_entries_sha256']
    passed = (manifest_valid and baseline_matches and not differences
              and qualified_ancestor and main_ancestor)
    result = {
        'verified_at_utc': datetime.now(timezone.utc).isoformat(),
        'ref': args.ref, 'publication_commit': target,
        'publication_tree': git('rev-parse', target + '^{tree}').decode().strip(),
        'qualified_source_commit': qualified,
        'captured_main_commit': manifest['captured_main_commit'],
        'protected_file_count': len(expected),
        'protected_entries_sha256': digest,
        'manifest_digest_valid': manifest_valid,
        'qualified_blob_manifest_matches': baseline_matches,
        'qualified_source_is_ancestor': qualified_ancestor,
        'captured_main_is_ancestor': main_ancestor,
        'unexpected_changed_paths': differences,
        'allowed_changed_paths': git('diff', '--name-only', qualified, target)
            .decode().splitlines(),
        'passed': passed,
        'scope': 'Committed-source continuity and ancestry; not test execution.',
    }
    rendered = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end='')
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
