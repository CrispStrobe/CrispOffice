"""Restore the recorded Flutter archive and independently hash each Pub archive."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time
import urllib.parse
import urllib.request
import yaml

ROOT = Path(__file__).resolve().parent
REPO = ROOT / 'quds_office_suite'
OUT = ROOT / 'runtime-restoration'
RUNTIME = ROOT / 'toolchains'
CACHE = RUNTIME / 'pub-cache'
SDK = RUNTIME / 'flutter'
SPEC = importlib.util.spec_from_file_location('recorded_bootstrap', REPO / 'docs/validation/proofing-20261116/integration-followup/flutter-setup/bootstrap_flutter.py')
BOOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BOOT)

def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')

def main():
    for path in (OUT, RUNTIME, CACHE / '_temp', CACHE / 'hosted/pub.dev', CACHE / 'hosted-hashes/pub.dev'):
        path.mkdir(parents=True, exist_ok=True)
    began = time.time()
    if not SDK.exists():
        expanded = 0
        last = time.time()
        manifest = []
        print('Downloading and verifying official Flutter archive', flush=True)
        with urllib.request.urlopen(BOOT.URL, timeout=120) as response:
            reader = BOOT.DigestReader(response)
            with tarfile.open(fileobj=reader, mode='r|xz') as archive:
                for member in archive:
                    if BOOT.selected(member.name):
                        expanded += member.size
                        if expanded > 3 * 1024**3 or shutil.disk_usage(RUNTIME).free < 2 * 1024**3:
                            raise RuntimeError('SDK extraction exceeded safety budget')
                        archive.extract(member, RUNTIME, filter='data')
                        if member.isfile():
                            manifest.append({'path': member.name, 'bytes': member.size})
                    if time.time() - last > 20:
                        print(json.dumps({'downloaded_bytes': reader.total, 'expanded_bytes': expanded}), flush=True)
                        last = time.time()
            while reader.read(1024**2):
                pass
            assert reader.hash.hexdigest() == BOOT.SHA256, reader.hash.hexdigest()
        write('flutter-install-receipt.json', {'url': BOOT.URL, 'sha256': reader.hash.hexdigest(), 'archive_bytes': reader.total, 'extracted_bytes': expanded, 'files': manifest})
    else:
        receipt = json.loads((OUT / 'flutter-install-receipt.json').read_text())
        assert receipt['sha256'] == BOOT.SHA256
    link = RUNTIME / 'flutter-sdk'
    if not link.exists():
        link.symlink_to('flutter', target_is_directory=True)

    locks = [SDK / 'packages/flutter_tools/pubspec.lock', REPO / 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock']
    assert BOOT.sha(locks[1]) == '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
    entries = {}
    for lock in locks:
        for name, value in yaml.safe_load(lock.read_text())['packages'].items():
            if value['source'] != 'hosted':
                continue
            assert value['description']['url'] == 'https://pub.dev'
            key = name + '-' + value['version']
            entry = {'name': name, 'version': value['version'], 'sha256': value['description']['sha256']}
            assert key not in entries or entries[key] == entry
            entries[key] = entry

    def fetch(item):
        key, entry = item
        target = CACHE / 'hosted/pub.dev' / key
        mark = CACHE / 'hosted-hashes/pub.dev' / (key + '.sha256')
        if target.exists() and mark.exists() and mark.read_text().strip() == entry['sha256']:
            return dict(entry, status='matching-restored-cache')
        url = 'https://pub.dev/api/archives/' + urllib.parse.quote(key, safe='-._+') + '.tar.gz'
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read()
        actual = hashlib.sha256(data).hexdigest()
        assert actual == entry['sha256'], key
        temporary = CACHE / '_temp' / key
        temporary.mkdir(exist_ok=False)
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            archive.extractall(temporary, filter='data')
        temporary.rename(target)
        mark.write_text(actual)
        return dict(entry, status='verified-download', url=url, archive_bytes=len(data), actual_sha256=actual)

    print('Restoring pinned Pub archives: ' + str(len(entries)), flush=True)
    with ThreadPoolExecutor(max_workers=16) as pool:
        results = list(pool.map(fetch, sorted(entries.items())))
    write('pub-cache-receipt.json', {'locks': {str(p): BOOT.sha(p) for p in locks}, 'packages': results})
    env = dict(os.environ, PUB_CACHE=str(CACHE), FLUTTER_ROOT=str(SDK), CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    commands = [
        ('flutter-tools-offline', [str(SDK / 'bin/cache/dart-sdk/bin/dart'), 'pub', '--suppress-analytics', '--directory', str(SDK / 'packages/flutter_tools'), 'get', '--example', '--offline']),
        ('flutter-version', [str(SDK / 'bin/flutter'), '--version', '--machine']),
        ('prepare-workspace', [os.sys.executable, str(REPO / 'docs/validation/office-reconciled-20261117/qualification/prepare_workspace.py'), '--source', str(REPO), '--workspace', str(ROOT / 'full-validation-workspace'), '--runtime', str(RUNTIME)]),
    ]
    records = []
    for label, command in commands:
        print('START ' + label, flush=True)
        with (OUT / (label + '.log')).open('wb') as stream:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
        records.append({'label': label, 'command': command, 'exit_code': result.returncode, 'log_sha256': BOOT.sha(OUT / (label + '.log'))})
        write('commands.json', records)
        assert result.returncode == 0, (OUT / (label + '.log')).read_text()[-12000:]
    version = json.loads((OUT / 'flutter-version.log').read_text())
    assert version['frameworkRevision'] == BOOT.REVISION and version['dartSdkVersion'] == '3.13.7'
    write('ready.json', {'version': version, 'workspace': str(ROOT / 'full-validation-workspace'), 'runtime': str(SDK), 'pub_cache': str(CACHE), 'elapsed_seconds': time.time() - began, 'finished_utc': datetime.now(timezone.utc).isoformat()})
    print('RUNTIME READY', flush=True)

if __name__ == '__main__':
    main()
