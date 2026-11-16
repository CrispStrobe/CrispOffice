from datetime import datetime, timezone
from pathlib import Path
from collections import Counter
import hashlib
import json
import os
import subprocess

root = Path('/workspace/scratch/f423a275b479')
out = root / 'negative-controls'
base = root / 'sheet-work/baseline-source'
cwd = base / 'packages/quds_office_engine'
toolchain = root / 'toolchain'
command = [
    str(toolchain / 'bin/dart'),
    '--packages=' + str(cwd / '.dart_tool/package_config.json'),
    str(toolchain / 'pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart'),
    '--reporter=json',
    'test/pdf_actual_text_scope_test.dart',
    'test/pdf_logical_text_export_test.dart',
]
env = dict(os.environ, PUB_CACHE=str(toolchain / 'pub-cache'),
           FLUTTER_ROOT=str(toolchain / 'flutter-source'),
           TMPDIR=str(toolchain / 'tmp'), CI='true',
           DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true',
           XDG_CONFIG_HOME=str(toolchain / 'config'),
           XDG_DATA_HOME=str(toolchain / 'data'),
           XDG_CACHE_HOME=str(toolchain / 'cache'))
receipt = {'baseline_commit': 'becfa07c1be62429a8bcf78910aa1ffb46248b1a',
           'command': command, 'cwd': str(cwd),
           'started_at_utc': datetime.now(timezone.utc).isoformat(),
           'production_source_modified': False,
           'github_actions_used': False}
log = out / 'pdf-baseline.jsonl'
with log.open('wb') as stream:
    result = subprocess.run(command, cwd=cwd, env=env,
                            stdout=stream, stderr=subprocess.STDOUT, timeout=120)
receipt['exit_code'] = result.returncode
receipt['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
receipt['log_sha256'] = hashlib.sha256(log.read_bytes()).hexdigest()
events = [json.loads(line) for line in log.read_text().splitlines() if line.startswith('{')]
tests = {event['test']['id']: event['test'] for event in events if event.get('type') == 'testStart'}
suites = {event['suite']['id']: event['suite']['path'] for event in events if event.get('type') == 'suite'}
summary = {}
for event in events:
    if event.get('type') != 'testDone' or event.get('hidden'):
        continue
    test = tests[event['testID']]
    suite = suites[test['suiteID']]
    counts = summary.setdefault(suite, {'success': 0, 'failure': 0, 'error': 0, 'skipped': 0})
    counts[event['result']] += 1
    counts['skipped'] += int(event['skipped'])
receipt['results'] = summary
receipt['terminal'] = events[-1]
manifest = json.loads((out / 'pdf-baseline-inputs.json').read_text())
after = {path: hashlib.sha256((base / path).read_bytes()).hexdigest() for path in manifest}
receipt['inputs_unchanged'] = manifest == after
receipt['inputs_sha256'] = hashlib.sha256((out / 'pdf-baseline-inputs.json').read_bytes()).hexdigest()
(out / 'pdf-baseline-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
