#!/usr/bin/env python3
"""Install authentic archives with unmodified Flutter bootstrap/cache tools."""
from datetime import datetime, timezone
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time
import zipfile

root = Path('/workspace/scratch/796b63b8623e/toolchain')
repo = root.parent / 'quds_office_suite'
sdk = root / 'flutter-runtime'
engine = 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
out = root / 'setup/installation'
out.mkdir(exist_ok=True)
record = {'started_at_utc': datetime.now(timezone.utc).isoformat(), 'commands': [],
          'sdk_sources_modified': False, 'native_binaries_rebuilt': False,
          'storage_note': 'Unmodified official archives are served locally solely for Flutter installation. The official scripts generate cache metadata.'}

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

for source, tail in [('dart-sdk-linux-x64.zip', 'dart-sdk-linux-x64.zip'),
                     ('linux-x64-artifacts.zip', 'linux-x64/artifacts.zip')]:
    archive = root / 'archives' / source
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise ValueError('ZIP integrity failure: ' + source)
    target = root / 'mirror/flutter_infra_release/flutter' / engine / tail
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        os.link(archive, target)

class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(root / 'mirror')))
threading.Thread(target=server.serve_forever, daemon=True).start()
env = {**os.environ, 'TMPDIR': str(root / 'tmp'), 'PUB_CACHE': str(root / 'pub-cache'),
       'FLUTTER_ROOT': str(sdk), 'CI': 'true', 'DART_SUPPRESS_ANALYTICS': 'true',
       'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'FLUTTER_STORAGE_BASE_URL': f'http://127.0.0.1:{server.server_port}'}

def run(label, command, cwd=repo, timeout=240):
    log = out / (label + '.log')
    begin = time.monotonic()
    print('START ' + label, flush=True)
    with log.open('wb') as stream:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    item = {'label': label, 'command': command, 'cwd': str(cwd), 'exit_code': result.returncode,
            'elapsed_seconds': time.monotonic() - begin, 'log_sha256': digest(log)}
    record['commands'].append(item)
    (out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print('END ' + label + ' ' + str(result.returncode), flush=True)
    if result.returncode:
        print(log.read_text()[-10000:], flush=True)
        raise RuntimeError(label)
    return log

try:
    run('engine-version', [str(sdk / 'bin/internal/update_engine_version.sh')])
    run('dart-sdk-install', [str(sdk / 'bin/internal/update_dart_sdk.sh')])
    dart = str(sdk / 'bin/cache/dart-sdk/bin/dart')
    expected = '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb'
    if digest(Path(dart)) != expected:
        raise ValueError('Dart executable does not match prior qualification')
    run('flutter-tools-offline', [dart, 'pub', '--directory', str(sdk / 'packages/flutter_tools'), 'get', '--offline'])
    flutter = str(sdk / 'bin/flutter')
    version_log = run('flutter-version', [flutter, '--version', '--machine'])
    record['version'] = json.loads(version_log.read_text()[version_log.read_text().find('{'):])
    run('universal-artifacts', [flutter, 'precache', '--no-web', '--no-android', '--no-ios',
                              '--no-linux', '--no-windows', '--no-macos', '--no-fuchsia'])
    paths = subprocess.check_output(['git', 'ls-files', 'pubspec.yaml', '**/pubspec.yaml'], cwd=repo, text=True).splitlines()
    record['workspace_manifests_before'] = {p: digest(repo / p) for p in paths}
    record['lock_before'] = digest(repo / 'pubspec.lock')
    run('workspace-resolution', [flutter, 'pub', 'get', '--offline', '--enforce-lockfile'])
    record['lock_after'] = digest(repo / 'pubspec.lock')
    record['workspace_manifests_after'] = {p: digest(repo / p) for p in paths}
    if record['lock_before'] != record['lock_after'] or record['workspace_manifests_before'] != record['workspace_manifests_after']:
        raise ValueError('Workspace dependency inputs changed')
    tester = sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester'
    if digest(tester) != '800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f':
        raise ValueError('Flutter tester differs from prior qualification')
    record['dart_executable_sha256'] = digest(Path(dart))
    record['flutter_tester_sha256'] = digest(tester)
    record['sdk_tracked_changes'] = subprocess.check_output(['git', 'diff', '--name-only'], cwd=sdk, text=True).splitlines()
    if record['sdk_tracked_changes']:
        raise ValueError('SDK source unexpectedly changed')
    record['status'] = 'passed'
except BaseException as error:
    record['status'] = 'failed'
    record['error'] = repr(error)
    raise
finally:
    record['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    (out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    server.shutdown()
    print('INSTALL_COMPLETE ' + record['status'], flush=True)
