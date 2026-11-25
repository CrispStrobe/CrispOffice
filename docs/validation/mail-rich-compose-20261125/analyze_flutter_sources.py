import json
import hashlib
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import time

BASE = Path('/workspace/scratch/5be74ff50514')
TOOL = BASE / 'toolchain'
REPO = BASE / 'crispoffice'
ROOT = TOOL / 'ui-analysis'
names = sys.argv[1:] or [
    'lib/studio_mail_compose.dart',
    'lib/studio_mail_rich_strings.dart',
    'lib/studio_mail_rich_body.dart',
    'lib/studio_mail_rich_preview.dart',
    'lib/studio_mail_rich_preview_data.dart',
    'lib/studio_mail_outbox_review.dart',
    'lib/studio_mail_outbox_strings.dart',
    'test/studio_mail_rich_compose_test.dart',
    'test/studio_mail_rich_preview_test.dart',
]
paths = [str((REPO / 'packages/quds_office_editor/example' / name).resolve()) for name in names]
source_hashes = {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in paths}
def repository_sources():
    tracked = subprocess.check_output(['git', 'ls-files', '-z', '*.dart'], cwd=REPO).decode().split('\0')
    digest = hashlib.sha256()
    count = 0
    for name in sorted(tracked):
        path = REPO / name
        if name and path.is_file():
            digest.update(name.encode() + b'\0')
            digest.update(hashlib.sha256(path.read_bytes()).digest())
            count += 1
    return {'count': count, 'sha256': digest.hexdigest()}
repository_before = repository_sources()
free_before = shutil.disk_usage(BASE).free
if free_before < 12 * 1024 * 1024:
    raise RuntimeError('Need 12 MiB free before analysis to preserve source reserve')
env = dict(os.environ)
env.update({
    'XDG_CONFIG_HOME': str(TOOL / 'config'),
    'TMPDIR': str(TOOL / 'tmp'),
    'DART_SUPPRESS_ANALYTICS': 'true',
})
command = [
    str(TOOL / 'dart-sdk/bin/dartaotruntime'),
    str(TOOL / 'dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot'),
    '--dart-sdk=' + str(TOOL / 'dart-sdk'),
    '--packages=' + str(ROOT / '.dart_tool/package_config.json'),
    '--cache=' + str(ROOT / 'cache'),
    '--protocol=analyzer',
    '--client-id=crispoffice-source-validation',
]
process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, bufsize=1)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
def send(identifier, method, params=None):
    request = {'id': identifier, 'method': method}
    if params is not None:
        request['params'] = params
    process.stdin.write(json.dumps(request) + '\n')
    process.stdin.flush()

send('subscribe', 'server.setSubscriptions', {'subscriptions': ['STATUS']})
send('roots', 'analysis.setAnalysisRoots', {'included': paths, 'excluded': []})
buffers = {'stdout': '', 'stderr': ''}
errors = {}
server_errors = []
stderr = []
started = False
roots_accepted = False
complete = False
deadline = time.monotonic() + 150
try:
    while time.monotonic() < deadline:
        if shutil.disk_usage(BASE).free < 10 * 1024 * 1024:
            server_errors.append({'disk_reserve': 'Analysis stopped below 10 MiB free'})
            break
        for key, _ in selector.select(timeout=1):
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                selector.unregister(key.fileobj)
                continue
            buffers[key.data] += chunk.decode('utf-8')
            lines = buffers[key.data].split('\n')
            buffers[key.data] = lines.pop()
            for line in lines:
                if key.data == 'stderr':
                    stderr.append(line.rstrip())
                    continue
                event = json.loads(line)
                if event.get('error'):
                    server_errors.append(event)
                if event.get('id') == 'roots' and not event.get('error'):
                    roots_accepted = True
                if event.get('event') == 'analysis.errors':
                    params = event['params']
                    if params['file'] in paths:
                        errors[params['file']] = params['errors']
                if event.get('event') == 'server.error':
                    server_errors.append(event)
                if event.get('event') == 'server.status':
                    analyzing = event.get('params', {}).get('analysis', {}).get('isAnalyzing')
                    if analyzing is True:
                        started = True
                    if analyzing is False and started and roots_accepted:
                        complete = True
                        break
        if complete or process.poll() is not None:
            break
finally:
    try:
        send('shutdown', 'server.shutdown')
        process.wait(timeout=5)
    except (BrokenPipeError, subprocess.TimeoutExpired):
        process.kill()
        process.wait()

final_hashes = {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in paths}
repository_after = repository_sources()
stable = source_hashes == final_hashes and repository_before == repository_after
result = {
    'source_hashes': source_hashes,
    'final_source_hashes': final_hashes,
    'sources_stable': stable,
    'repository_sources_before': repository_before,
    'repository_sources_after': repository_after,
    'free_bytes_before': free_before,
    'free_bytes_after': shutil.disk_usage(BASE).free,
    'complete': complete,
    'paths': paths,
    'reported_paths': list(errors),
    'diagnostics': errors,
    'server_errors': server_errors,
    'stderr': stderr,
    'command': command,
}
(ROOT / 'analysis_result.json').write_text(json.dumps(result, indent=2) + '\n')
all_errors = [item for values in errors.values() for item in values]
print('Analysis finished:', complete, 'files reported:', len(errors), '/', len(paths))
for path, items in errors.items():
    for item in items:
        location = item['location']
        print(f"{item['severity']} {item['code']} {Path(path).name}:{location['startLine']}:{location['startColumn']} {item['message']}")
print('Diagnostics:', len(all_errors), 'server errors:', len(server_errors))
if stderr:
    print('Server stderr:', '\n'.join(stderr[:5]))
sys.exit(0 if complete and stable and len(errors) == len(paths) and not all_errors and not server_errors else 1)
