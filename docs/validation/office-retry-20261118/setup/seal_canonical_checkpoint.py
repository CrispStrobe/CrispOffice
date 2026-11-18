#!/usr/bin/env python3
"""Archive only closed canonical commands without disturbing a running gate."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--run', type=Path, required=True)
parser.add_argument('--staging', type=Path, required=True)
parser.add_argument('--archive', type=Path, required=True)
args = parser.parse_args()
raw = (args.run / 'receipt.json').read_bytes()
receipt = json.loads(raw)
closed = [row for row in receipt['commands'] if row['status'] != 'running']
args.staging.mkdir(parents=True, exist_ok=False)
for path in args.run.iterdir():
    if path.is_file() and path.name not in {'receipt.json', 'run.lock'}:
        shutil.copy2(path, args.staging / path.name)
(args.staging / 'receipt.json').write_bytes(raw)
for row in closed:
    shutil.copytree(args.run / row['name'], args.staging / row['name'])
state = {'sealed_utc': datetime.now(timezone.utc).isoformat(),
         'source_commit': receipt['source_commit'], 'whole_run_status': receipt['status'],
         'completed_command_names': [row['name'] for row in closed],
         'running_commands_omitted': [row['name'] for row in receipt['commands'] if row['status'] == 'running'],
         'final_input_integrity_available': 'input_integrity' in receipt,
         'whole_run_accepted': receipt.get('all_passed', False)}
(args.staging / 'checkpoint-state.json').write_text(json.dumps(state, indent=2) + '\n')
spec = importlib.util.spec_from_file_location('pack', args.repo / 'docs/validation/office-reconciled-20261117/resume/package_checkpoint.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)
files = {str(path.relative_to(args.staging)): path for path in args.staging.rglob('*') if path.is_file() and not path.is_symlink()}
pack.pack(args.archive, files, 'Canonical checkpoint; whole-run acceptance=' + str(state['whole_run_accepted']) + '; final integrity available=' + str(state['final_input_integrity_available']))
print(json.dumps(state))
