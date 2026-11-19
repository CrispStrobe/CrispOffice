#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('incoming_ui', HERE / 'run-ui-validation.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
parser = argparse.ArgumentParser()
parser.add_argument('--group', choices=['editor', 'studio'], required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
if out.exists(): raise RuntimeError('Use a fresh output directory')
out.mkdir(parents=True)
selection = json.loads((HERE / 'incoming-ui-analysis-selection.json').read_text())
targets = [p for p in selection if ('/example/' in p) == (args.group == 'studio')]
package = helper.REPO / 'packages/quds_office_editor'
if args.group == 'studio': package /= 'example'
before, dep_before = helper.snapshots(args.group, package, helper.PLAN[args.group + '_tests'])
helper.write(out / 'source-before.json.gz', before)
helper.write(out / 'dependencies-before.json.gz', dep_before)
commands = []
for name, command in [
    ('analysis', [str(helper.RUNTIME / 'bin/dart'), 'analyze', '--fatal-infos', '--fatal-warnings', *targets]),
    ('format', [str(helper.RUNTIME / 'bin/dart'), 'format', '--output=none', '--set-exit-if-changed', *targets]),
]:
    started = datetime.now(timezone.utc).isoformat()
    start = time.monotonic()
    with (out / (name + '.stdout.log')).open('wb') as stdout, (out / (name + '.stderr.log')).open('wb') as stderr:
        result = subprocess.run(command, cwd=helper.REPO, stdout=stdout, stderr=stderr, timeout=600)
    commands.append({'name': name, 'command': command, 'cwd': str(helper.REPO), 'exit_code': result.returncode,
                     'started_at_utc': started, 'elapsed_seconds': round(time.monotonic()-start, 3),
                     'stdout_sha256': helper.digest(out / (name + '.stdout.log')),
                     'stderr_sha256': helper.digest(out / (name + '.stderr.log'))})
after, dep_after = helper.snapshots(args.group, package, helper.PLAN[args.group + '_tests'])
helper.write(out / 'source-after.json.gz', after)
helper.write(out / 'dependencies-after.json.gz', dep_after)
changed = sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))
dep_changed = sorted(k for k in dep_before.keys() | dep_after.keys() if dep_before.get(k) != dep_after.get(k))
receipt = {'success': all(c['exit_code'] == 0 for c in commands) and not changed and not dep_changed,
           'group': args.group, 'commands': commands, 'targets': targets,
           'source_inputs': len(before), 'dependency_inputs': len(dep_before),
           'changed_source_inputs': changed, 'changed_dependency_inputs': dep_changed,
           'executed_runner_sha256': helper.digest(Path(__file__))}
helper.write(out / 'receipt.json', receipt)
print(json.dumps(receipt, indent=2), flush=True)
raise SystemExit(0 if receipt['success'] else 1)
