#!/usr/bin/env python3
"""Verify and activate genuine pinned Flutter components for local tests."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import subprocess
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / 'flutter-source'
REPO = ROOT.parent / 'quds_office_suite'
OUT = ROOT / 'setup'
PRIOR = REPO / 'docs/validation/text-rendering-continuation-20261116/runtime-resume'
ENGINE = 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
record = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
          'status': 'running', 'commands': [], 'github_actions_used': False}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save():
    (OUT / 'runtime-receipt.json').write_text(json.dumps(record, indent=2) + '\n')

env = dict(os.environ, PUB_CACHE=str(ROOT / 'pub-cache'),
           TMPDIR=str(ROOT / 'tmp'), FLUTTER_ROOT=str(SDK), CI='true',
           DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true',
           XDG_CONFIG_HOME=str(ROOT / 'config'), XDG_CACHE_HOME=str(ROOT / 'cache'),
           XDG_DATA_HOME=str(ROOT / 'data'))

def run(label, args, cwd=REPO, timeout=300):
    print('START ' + label, flush=True)
    log = OUT / (label + '.log')
    start = datetime.now(timezone.utc)
    with log.open('wb') as stream:
        result = subprocess.run([str(x) for x in args], cwd=cwd, env=env,
                                stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    record['commands'].append({'label': label, 'argv': [str(x) for x in args],
                               'cwd': str(cwd), 'exit_code': result.returncode,
                               'started_at_utc': start.isoformat(),
                               'log_sha256': sha(log)})
    save()
    print('END ' + label + ' ' + str(result.returncode), flush=True)
    if result.returncode:
        raise RuntimeError(label + ': ' + log.read_text(errors='replace')[-8000:])
    return log

try:
    save()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SDK, text=True).strip()
    if revision != '737ba8f885dc774b53b442759999a312c9461e4e':
        raise RuntimeError('Incorrect Flutter checkout')
    record['framework_revision'] = revision
    prior_dart = json.loads((PRIOR / 'receipts/dart-selected-install.json').read_text())
    current_dart = json.loads((OUT / 'dart-selected-install.json').read_text())
    if current_dart['files'] != prior_dart['files']:
        raise RuntimeError('Selected Dart member verification differs from prior pinned installation')
    record['dart_selected_members'] = len(current_dart['files'])
    record['dart_selected_receipt_sha256'] = sha(OUT / 'dart-selected-install.json')
    prior_common = json.loads((PRIOR / 'receipts/common-install.json').read_text())
    current_common = json.loads((OUT / 'common-install.json').read_text())
    if current_common != prior_common:
        raise RuntimeError('Common engine archive/member verification differs')
    record['common_receipt_sha256'] = sha(OUT / 'common-install.json')
    pin = json.loads((PRIOR / 'receipts/engine-install.json').read_text())
    archive = ROOT / 'downloads/linux-x64-artifacts.zip'
    if sha(archive) != pin['archive_sha256']:
        raise RuntimeError('Engine archive SHA256 mismatch')
    target = SDK / 'bin/cache/artifacts/engine/linux-x64'
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise RuntimeError('Engine ZIP CRC failure')
        for info in bundle.infolist():
            path = target / info.filename
            if not path.resolve().is_relative_to(target.resolve()):
                raise RuntimeError('Unsafe engine archive member')
            bundle.extract(info, target)
            if path.is_file():
                path.chmod((info.external_attr >> 16) & 0o777 or 0o644)
    if sha(target / 'flutter_tester') != pin['flutter_tester_sha256']:
        raise RuntimeError('Engine tester SHA256 mismatch')
    (OUT / 'engine-install.json').write_text(json.dumps(pin, indent=2) + '\n')
    record['engine_receipt_sha256'] = sha(OUT / 'engine-install.json')
    metadata_url = 'https://storage.googleapis.com/flutter_infra_release/flutter/' + ENGINE + '/engine_stamp.json'
    with urllib.request.urlopen(metadata_url, timeout=60) as response:
        metadata = response.read()
    if hashlib.sha256(metadata).hexdigest() != '00adfb4cd85c87da165d9cccfcb6d238e34ada530fd12e3d458431b38ddd1e5b':
        raise RuntimeError('Engine metadata SHA256 mismatch')
    (SDK / 'bin/cache/engine_stamp.json').write_bytes(metadata)
    (OUT / 'engine_stamp.json').write_bytes(metadata)
    run('engine-version', [SDK / 'bin/internal/update_engine_version.sh'], SDK)
    if (SDK / 'bin/cache/engine.stamp').read_text().strip() != ENGINE:
        raise RuntimeError('Generated engine stamp differs')
    (SDK / 'bin/cache/flutter_sdk.stamp').write_text(ENGINE)
    record['cache_stamp_note'] = 'Records the actual verified official engine artifacts installed above; SDK identity is unmodified.'
    dart = SDK / 'bin/cache/dart-sdk/bin/dart'
    run('dart-version', [dart, '--version'])
    deadline = time.monotonic() + 300
    while not (OUT / 'prefetch-162.json').is_file():
        if time.monotonic() > deadline:
            raise RuntimeError('Pinned Pub archive download did not finish within preparation bound')
        time.sleep(5)
    prefetch = json.loads((OUT / 'prefetch-162.json').read_text())
    if len(prefetch['packages']) != 162 or any(x['status'] == 'failed' for x in prefetch['packages']):
        raise RuntimeError('Pinned Pub archive closure incomplete')
    record['pub_receipt_sha256'] = sha(OUT / 'prefetch-162.json')
    run('flutter-tools-offline', [dart, 'pub', '--suppress-analytics', '--directory', SDK / 'packages/flutter_tools', 'get', '--offline'])
    flutter = ROOT / 'bin/flutter'
    flutter.write_text('#!/bin/sh\nexec "' + str(dart) + '" --packages="' + str(SDK / 'packages/flutter_tools/.dart_tool/package_config.json') + '" "' + str(SDK / 'packages/flutter_tools/bin/flutter_tools.dart') + '" "$@"\n')
    flutter.chmod(0o755)
    dart_shim = ROOT / 'bin/dart'
    dart_shim.write_text('#!/bin/sh\nexec "' + str(dart) + '" "$@"\n')
    dart_shim.chmod(0o755)
    env['PATH'] = str(ROOT / 'bin') + ':' + env.get('PATH', '')
    (ROOT / 'env.sh').write_text('\n'.join('export ' + key + '=' + value for key, value in env.items() if key in ['PUB_CACHE', 'TMPDIR', 'FLUTTER_ROOT', 'CI', 'DART_SUPPRESS_ANALYTICS', 'FLUTTER_SUPPRESS_ANALYTICS', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME']) + '\nexport PATH=' + str(ROOT / 'bin') + ':"$PATH"\n')
    version_log = run('flutter-version', [flutter, '--version', '--machine'])
    record['actual_runtime'] = json.loads(version_log.read_text())
    record['workspace_activation'] = 'deferred until repository integration completes'
    record['sdk_tracked_changes'] = subprocess.check_output(['git', 'diff', '--name-only'], cwd=SDK, text=True).splitlines()
    if record['sdk_tracked_changes']:
        raise RuntimeError('Flutter tracked source changed')
    record['executables_sha256'] = {str(path.relative_to(SDK)): sha(path) for path in [dart, target / 'flutter_tester']}
    record['launcher_sha256'] = {'dart': sha(dart_shim), 'flutter': sha(flutter)}
    record['status'] = 'ready'
except BaseException as error:
    record['status'] = 'failed'
    record['error'] = repr(error)
    raise
finally:
    record['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    print(json.dumps(record), flush=True)
