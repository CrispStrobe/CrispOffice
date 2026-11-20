#!/usr/bin/env python3
"""Recheck the exact retained evidence and Word inputs from the frozen intake."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--target', help='Optional descendant to inspect instead of the recorded checkpoint')
    args = parser.parse_args()
    record = json.loads(Path(__file__).with_name('final-intake-retention.json').read_text())
    env = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0')

    def git(*argv):
        return subprocess.check_output(['git', '-C', str(args.repo), *argv], env=env).decode().strip()

    target = git('rev-parse', (args.target or record['target_commit']) + '^{commit}')
    subprocess.run(['git', '-C', str(args.repo), 'merge-base', '--is-ancestor',
                    record['target_commit'], target], env=env, check=True)
    for row in record['historical_evidence_checks']:
        if row['proof'] == 'exact Git blob equality':
            assert git('rev-parse', target + ':' + row['path']) == row['incoming_blob'], row['path']
        else:
            assert row['retained_added_line'] in git('show', target + ':' + row['path']).splitlines(), row['path']
    for row in record['exact_incoming_word_source_matches']:
        assert git('rev-parse', target + ':' + row['path']) == row['incoming_blob'], row['path']
    print(json.dumps({'target_commit': target,
                      'retained_incoming_evidence_paths': len(record['historical_evidence_checks']),
                      'exact_word_source_and_test_paths': len(record['exact_incoming_word_source_matches'])}, indent=2))


if __name__ == '__main__':
    main()
