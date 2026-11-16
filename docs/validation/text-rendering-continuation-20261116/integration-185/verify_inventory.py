#!/usr/bin/env python3
"""Read-only ancestry verification of a pinned GitHub branch/PR snapshot."""
import argparse
import datetime
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--head', default='HEAD')
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())

    def git(*parts):
        return subprocess.run(['git', '-C', str(args.repo), *parts],
                              text=True, capture_output=True)

    head_result = git('rev-parse', '--verify', args.head + '^{commit}')
    head_result.check_returncode()
    head = head_result.stdout.strip()
    results = []
    missing_objects = []
    missing_ancestors = []
    for ref in snapshot['refs']:
        sha = ref['sha']
        available = git('cat-file', '-e', sha + '^{commit}').returncode == 0
        included = available and git('merge-base', '--is-ancestor', sha, head).returncode == 0
        results.append(dict(ref, object_available=available, included=bool(included)))
        if not available:
            missing_objects.append(ref)
        elif not included:
            missing_ancestors.append(ref)
    unique_missing = sorted({r['sha'] for r in missing_ancestors})
    independent = []
    if unique_missing:
        independent_result = git('merge-base', '--independent', *unique_missing)
        independent_result.check_returncode()
        independent = independent_result.stdout.splitlines()
    report = {
        'recorded_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'snapshot_recorded_at_utc': snapshot['recorded_at_utc'],
        'head': head,
        'counts': snapshot['counts'],
        'total': len(results),
        'included_count': sum(r['included'] for r in results),
        'missing_objects': missing_objects,
        'missing_ancestors': missing_ancestors,
        'independent_missing_heads': independent,
        'refs': results,
        'passed': not missing_objects and not missing_ancestors,
        'github_actions_used': False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items()
                      if key not in ('refs', 'missing_objects', 'missing_ancestors')}, indent=2))
    print(f'Missing commit objects: {len(missing_objects)}; missing ancestors: {len(missing_ancestors)}')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
