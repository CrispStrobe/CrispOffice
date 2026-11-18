"""Seal only completed native arms while the full guarded sweep continues."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
run = args.run.resolve()
output = args.output.resolve()
stage = root / 'continuation/native-partial-staging' / output.name.removesuffix('.tar.xz')
stage.mkdir(parents=True, exist_ok=False)
receipt_path = run / 'result/serial-receipt.json'
raw = receipt_path.read_bytes()
receipt = json.loads(raw)
closed = [row for row in receipt['runs']
          if row.get('status') == 'completed' and row.get('exit_code') == 0
          and row.get('independent_evidence_audit') and row.get('summary')]
assert closed, 'No completed, audited arms yet'
files = {}

def copy(name, data):
    target = stage / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    files[name] = target

copy('result/serial-receipt.json', raw)
for row in closed:
    for key in ('report', 'log'):
        name = row[key]
        assert Path(name).name == name
        data = (run / 'result' / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == row[key + '_sha256']
        copy('result/' + name, data)
for name in ('orchestration.json', 'guard/receipt.json', 'guard/inputs-before.json.gz'):
    copy(name, (run / name).read_bytes())
copy('run_guarded_native.py', (root / 'native-consumers/run_guarded_native.py').read_bytes())
copy('snapshot_native.py', Path(__file__).read_bytes())
state = {
    'observed_utc': datetime.now(timezone.utc).isoformat(),
    'source_commit': '9d060658ee6be8ec97d73f56b9aec10d346b7952',
    'completed_audited_arms': [row['native_threads'] for row in closed],
    'full_sweep_completed_at_snapshot': receipt.get('completed') is True,
    'final_guard_acceptance_claimed': False,
    'scope': 'Stable completed-arm reports and logs only. Final sweep comparison and after-input guard remain separate requirements.',
}
copy('checkpoint.json', (json.dumps(state, indent=2) + '\n').encode())
spec = importlib.util.spec_from_file_location('pack_checkpoint', root / 'qualification-source/docs/validation/office-reconciled-20261117/resume/package_checkpoint.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.pack(output, files, 'Partial native sweep; completed arms only; final qualification not yet accepted')
