#!/usr/bin/env python3
"""Analyze the committed Phase B files and complete their bound receipt."""
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess

WORK = Path(__file__).resolve().parents[1]
ROOT = WORK / 'quds_office_suite'
BASE = Path(__file__).resolve().parent
OUT = BASE / 'phase-b-positive'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


test_receipt = json.loads((OUT / 'validation.json').read_text())
assert test_receipt['exit_code'] == 0 and test_receipt['passed_tests'] == 80
hashes = json.loads(gzip.decompress((OUT / 'inputs.json.gz').read_bytes()))


def changed():
    return [name for name, digest in hashes.items()
            if not (ROOT / name).is_file() or sha((ROOT / name).read_bytes()) != digest]


assert not changed()
runtime = json.loads((OUT / 'runtime.json').read_text())
command = [
    str(WORK / 'toolchain/flutter/bin/flutter'), 'analyze', '--no-pub',
    'packages/quds_office_editor/lib/src/embed/office_controller.dart',
    'packages/quds_office_editor/test/sheet_grid_history_test.dart',
]
receipt = {
    'version': 1, 'source_commit': test_receipt['source_commit'],
    'inputs_manifest': 'inputs.json.gz', 'command': command,
    'working_directory': '.', 'started_at': now(),
}
path = OUT / 'analysis.json'
assert not path.exists()
path.write_text(json.dumps(receipt, indent=2) + '\n')
log = OUT / 'focused-analysis.log'
with log.open('xb') as output:
    result = subprocess.run(command, cwd=ROOT,
                            env=dict(os.environ, **runtime['environment']),
                            stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT)
receipt.update({
    'completed_at': now(), 'exit_code': result.returncode,
    'log': log.name, 'log_sha256': sha(log.read_bytes()),
    'changed_inputs_during_analysis': changed(),
    'source_commit_at_end': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
})
receipt['passed'] = result.returncode == 0 and not receipt['changed_inputs_during_analysis']
path.write_text(json.dumps(receipt, indent=2) + '\n')
baseline = json.loads(gzip.decompress((BASE / 'phase-b-baseline-corrected/inputs.json.gz').read_bytes()))
input_changes = sorted(name for name in hashes if hashes[name] != baseline.get(name))
counts = Counter()
for line in (OUT / 'editor-tests.log').read_text().splitlines():
    match = re.search(r'([^/ ]+_test\.dart): (?!loading )', line)
    if match:
        counts[match.group(1)] += 1
assert sum(counts.values()) == 80, counts
assert input_changes == ['packages/quds_office_editor/lib/src/embed/office_controller.dart'], input_changes
completion = {
    'version': 1, 'completed_at': now(), 'passed': receipt['passed'],
    'source_commit': test_receipt['source_commit'],
    'source_commit_at_end': receipt['source_commit_at_end'],
    'tests_passed': test_receipt['passed_tests'], 'tests_failed': test_receipt['failed_tests'],
    'tests_by_file': dict(sorted(counts.items())),
    'analysis_items': 2, 'analysis_exit_code': result.returncode,
    'input_files': len(hashes), 'changed_inputs_during_execution': changed(),
    'baseline_source_commit': 'ec88aa0700eff40c22e873fa0c221f98f825f011',
    'baseline_failed_tests': 14,
    'baseline_evidence': '../phase-b-baseline-corrected/validation.json',
    'inputs_changed_since_baseline': input_changes,
    'test_source_identical_to_baseline': hashes[test_receipt['test_path']] == baseline[test_receipt['test_path']],
    'files_sha256': {item.name: sha(item.read_bytes()) for item in sorted(OUT.iterdir()) if item.is_file()},
}
(OUT / 'completion.json').write_text(json.dumps(completion, indent=2) + '\n')
print(json.dumps(completion, indent=2), flush=True)
raise SystemExit(0 if receipt['passed'] else 1)
