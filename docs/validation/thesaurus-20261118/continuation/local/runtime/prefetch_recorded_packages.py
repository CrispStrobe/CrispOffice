#!/usr/bin/env python3
"""Restore the recorded hosted package set, verifying every archive digest."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import tarfile
import time
import urllib.request

runtime = Path(__file__).resolve().parent
records = json.loads((runtime / 'setup/prefetch-162.json').read_text())['packages']
cache = runtime / 'pub-cache'
hosted = cache / 'hosted/pub.dev'
hashes = cache / 'hosted-hashes/pub.dev'
hosted.mkdir(parents=True, exist_ok=True)
hashes.mkdir(parents=True, exist_ok=True)


def restore(record):
    name, version, expected = (record[k] for k in ['name', 'version', 'sha256'])
    assert re.fullmatch(r'[a-zA-Z0-9_]+', name), name
    assert re.fullmatch(r'[a-zA-Z0-9.+-]+', version), version
    assert re.fullmatch(r'[0-9a-f]{64}', expected), expected
    filename = f'{name}-{version}'
    url = f'https://pub.dev/api/archives/{filename}.tar.gz'
    assert record.get('url', url) == url, record
    destination = hosted / filename
    digest_path = hashes / f'{filename}.sha256'
    if destination.exists():
        assert digest_path.read_text().strip() == expected, filename
        return dict(name=name, version=version, sha256=expected, status='verified-cache')
    started = time.monotonic()
    with urllib.request.urlopen(url, timeout=90) as response:
        data = response.read()
    actual = hashlib.sha256(data).hexdigest()
    assert actual == expected, (filename, actual, expected)
    temporary = hosted / f'.{filename}.restore'
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.mkdir()
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as bundle:
        bundle.extractall(temporary, filter='data')
    temporary.rename(destination)
    digest_path.write_text(actual)
    return dict(name=name, version=version, sha256=expected, actual_sha256=actual,
                url=url, bytes=len(data), seconds=time.monotonic()-started,
                status='verified-download')


started = time.monotonic()
results = []
with ThreadPoolExecutor(max_workers=8) as executor:
    jobs = [executor.submit(restore, record) for record in records]
    for job in as_completed(jobs):
        result = job.result()
        results.append(result)
        print(json.dumps(result), flush=True)
receipt = dict(recorded_at_utc=datetime.now(timezone.utc).isoformat(),
               source='docs/validation/zotero-continuation-20261118/runtime/setup.tar.gz',
               packages=sorted(results, key=lambda r: (r['name'], r['version'])),
               seconds=time.monotonic()-started)
(runtime / 'setup/prefetch-current.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(dict(restored=len(results), seconds=receipt['seconds'])), flush=True)
