#!/usr/bin/env python3
"""Prepare only the package archives pinned by actual SDK/workspace locks."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import http.client
import io
import json
from pathlib import Path
import tarfile
import time
import urllib.parse
import urllib.request
import yaml

root = Path('/workspace/scratch/796b63b8623e/toolchain')
cache = root / 'pub-cache'
locks = [root / 'prior-setup/setup/workspace-pubspec.lock']
historical = root / 'prior-setup/setup/pub-cache-receipt.json'
packages = {p['name'] + '-' + p['version']:
            {k: p[k] for k in ['name', 'version', 'sha256']}
            for p in json.loads(historical.read_text())['packages']}
for lock in locks:
    for name, item in yaml.safe_load(lock.read_text())['packages'].items():
        if item['source'] != 'hosted':
            continue
        info = item['description']
        if info['url'] != 'https://pub.dev':
            raise ValueError('Unapproved package host')
        key = name + '-' + item['version']
        entry = {'name': name, 'version': item['version'], 'sha256': info['sha256']}
        if key in packages and packages[key] != entry:
            raise ValueError('Conflicting pinned package')
        packages[key] = entry
for d in [cache / '_temp', cache / 'hosted/pub.dev', cache / 'hosted-hashes/pub.dev']:
    d.mkdir(parents=True, exist_ok=True)

def fetch(pair):
    key, entry = pair
    target = cache / 'hosted/pub.dev' / key
    expected = entry['sha256']
    hash_file = cache / 'hosted-hashes/pub.dev' / (key + '.sha256')
    if target.is_dir() and hash_file.exists() and hash_file.read_text().strip() == expected:
        return {**entry, 'status': 'verified-cache'}
    url = 'https://pub.dev/api/archives/' + urllib.parse.quote(key, safe='-._+') + '.tar.gz'
    payload = b''
    total = None
    for attempt in range(1, 25):
        try:
            headers = {'Range': 'bytes=' + str(len(payload)) + '-'} if payload else {}
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=90) as response:
                if payload and response.status == 200:
                    payload = b''
                if total is None:
                    total = int(response.headers['Content-Length'])
                try:
                    payload += response.read()
                except http.client.IncompleteRead as error:
                    payload += error.partial
            if len(payload) < total:
                continue
            digest = hashlib.sha256(payload).hexdigest()
            if digest != expected:
                raise ValueError('Pinned archive SHA-256 mismatch')
            temp = cache / '_temp' / key
            temp.mkdir(exist_ok=True)
            with tarfile.open(fileobj=io.BytesIO(payload), mode='r:gz') as archive:
                archive.extractall(temp, filter='data')
            temp.rename(target)
            hash_file.write_text(digest)
            print('VERIFIED ' + key, flush=True)
            return {**entry, 'url': url, 'bytes': len(payload), 'attempt': attempt,
                    'actual_sha256': digest, 'status': 'verified-download'}
        except Exception as e:
            if attempt == 24:
                print('FAILED ' + key + ' ' + repr(e), flush=True)
                return {**entry, 'url': url, 'status': 'failed', 'error': repr(e)}
            time.sleep(min(attempt, 3))

begin = time.monotonic()
with ThreadPoolExecutor(8) as pool:
    results = list(pool.map(fetch, sorted(packages.items())))
record = {'finished_at_utc': datetime.now(timezone.utc).isoformat(),
          'historical_sdk_lock_receipt_sha256': hashlib.sha256(historical.read_bytes()).hexdigest(),
          'locks': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in locks},
          'elapsed_seconds': time.monotonic() - begin, 'packages': results,
          'passed': all(p['status'] != 'failed' for p in results)}
(root / 'setup/pub-cache-receipt.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'passed': record['passed'], 'package_count': len(results), 'seconds': record['elapsed_seconds']}), flush=True)
raise SystemExit(0 if record['passed'] else 1)
