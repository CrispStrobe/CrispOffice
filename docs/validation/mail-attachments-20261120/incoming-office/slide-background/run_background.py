#!/usr/bin/env python3
import datetime
import hashlib
import json
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

OUT = Path(__file__).resolve().parent
REPO = OUT.parents[1] / 'quds_office_suite'
PHASE = sys.argv[1]
CONFIG = REPO / '.dart_tool/package_config.json'
package = next(p for p in json.loads(CONFIG.read_text())['packages'] if p['name'] == 'test')
runner = Path(urllib.parse.urlparse(urllib.parse.urljoin(CONFIG.as_uri(), package['rootUri'])).path) / 'bin/test.dart'
paths = sorted(set([
    'pubspec.lock', 'pubspec.yaml',
    'packages/quds_office_engine/pubspec.yaml',
    'packages/quds_office_engine/test/slide_import_fidelity_test.dart',
    *[str(p.relative_to(REPO)) for p in (REPO/'packages/quds_office_engine/lib').rglob('*.dart')],
    *[str(p.relative_to(REPO)) for p in (REPO/'packages/legacy_doc_parser/lib').rglob('*.dart')],
]))


def snapshot():
    return {p: hashlib.sha256((REPO/p).read_bytes()).hexdigest() for p in paths}


before = snapshot()
(OUT/f'{PHASE}-inputs.json').write_text(json.dumps(before, indent=2)+'\n')
cmd = [
    str(OUT.parents[1]/'runtime/flutter/bin/cache/dart-sdk/bin/dart'),
    '--packages='+str(CONFIG), str(runner),
    'packages/quds_office_engine/test/slide_import_fidelity_test.dart',
    '--reporter=json', '--concurrency=2',
]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
t = time.monotonic()
with (OUT/f'{PHASE}-events.jsonl').open('w') as log, (OUT/f'{PHASE}-stderr.log').open('w') as err:
    run = subprocess.run(cmd, cwd=REPO, stdout=log, stderr=err, timeout=180)
after = snapshot()
events = [json.loads(line) for line in (OUT/f'{PHASE}-events.jsonl').read_text().splitlines() if line.startswith('{')]
done = [event for event in events if event.get('type') == 'testDone' and not event.get('hidden')]
receipt = {
    'phase': PHASE, 'startedAtUtc': started,
    'command': cmd, 'exitCode': run.returncode, 'elapsedSeconds': time.monotonic()-t,
    'inputCount': len(paths), 'inputsUnchanged': before == after,
    'changedInputs': [p for p in paths if before[p] != after[p]],
    'passed': sum(event.get('result') == 'success' and not event.get('skipped') for event in done),
    'failed': sum(event.get('result') != 'success' for event in done),
    'skipped': sum(bool(event.get('skipped')) for event in done),
    'failures': [event for event in events if event.get('type') == 'error'],
    'done': [event for event in events if event.get('type') == 'done'],
}
(OUT/f'{PHASE}-inputs-after.json').write_text(json.dumps(after, indent=2)+'\n')
(OUT/f'{PHASE}-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps({k:v for k,v in receipt.items() if k not in ('failures','command')}, indent=2))
