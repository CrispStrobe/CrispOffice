#!/usr/bin/env python3
"""Run the unchanged whole-delta static checker on one frozen publication head."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

PRIMARY_CHECKER_SHA256 = 'dda5b6b794c5b8572491347b1e247e62c2ab78f68d86cc5760baeda3d445de1a'
MILESTONE_BASE = 'a452efdadc9000c51a8e5e9ba2f16405d4979e2e'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    wrapper = Path(__file__).resolve()
    checker = wrapper.parents[2]/'check_changed_dart.py'

    def head():
        return subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    before = {'head':head(),'checker_sha256':digest(checker),'wrapper_sha256':digest(wrapper)}
    assert before['head'] == args.expected_head
    assert before['checker_sha256'] == PRIMARY_CHECKER_SHA256
    assert not output.exists()
    command = [sys.executable,str(checker),'--repo',str(repo),'--base',MILESTONE_BASE,'--output',str(output)]
    result = subprocess.run(command,cwd=repo)
    after = {'head':head(),'checker_sha256':digest(checker),'wrapper_sha256':digest(wrapper)}
    unchanged = before == after
    receipt_path = output/'receipt.json'
    primary = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
    accepted = result.returncode == 0 and unchanged and primary is not None and primary['accepted']
    provenance = {
        'status':'passed' if accepted else 'failed',
        'expected_head':args.expected_head,
        'milestone_base':MILESTONE_BASE,
        'before':before,
        'after':after,
        'checker_and_source_head_unchanged':unchanged,
        'unchanged_primary_checker_command':command,
        'primary_exit_code':result.returncode,
        'primary_receipt_sha256':digest(receipt_path) if receipt_path.exists() else None,
        'changed_dart_targets':len(primary['paths']) if primary is not None else None,
        'sdk_cache_configuration_or_source_writes_requested':False,
    }
    output.mkdir(parents=True,exist_ok=True)
    (output/'checker-wrapper.json').write_text(json.dumps(provenance,indent=2)+'\n')
    print(json.dumps({'publication_static':provenance['status'],'targets':provenance['changed_dart_targets'],'head_unchanged':unchanged}),flush=True)
    return 0 if accepted else 1


if __name__ == '__main__':
    raise SystemExit(main())
