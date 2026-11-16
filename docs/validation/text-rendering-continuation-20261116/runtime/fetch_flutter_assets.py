#!/usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor
import hashlib
import http.client
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen
import zipfile

root = Path('/workspace/scratch/796b63b8623e/toolchain')
engine = 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
prefix = 'flutter_infra_release/flutter/' + engine + '/'
paths = [prefix + name for name in ['sky_engine.zip', 'flutter_gpu.zip',
         'flutter_patched_sdk.zip', 'flutter_patched_sdk_product.zip', 'engine_stamp.json', 'linux-x64/font-subset.zip']]
paths += [(root / ('flutter-runtime/bin/internal/' + name + '.version')).read_text().strip()
          for name in ['material_fonts', 'gradle_wrapper']]

def fetch(path):
    target = root / 'mirror' / path
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + '.partial')
    url = 'https://storage.googleapis.com/' + path
    with urlopen(Request(url, method='HEAD'), timeout=30) as response:
        total = int(response.headers['Content-Length'])
    if target.exists() and target.stat().st_size == total:
        return {'url': url, 'bytes': total, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'reused': True}
    for attempt in range(1, 100):
        have = partial.stat().st_size if partial.exists() else 0
        if have == total:
            break
        end = min(have + 512 * 1024, total) - 1
        try:
            with urlopen(Request(url, headers={'Range': f'bytes={have}-{end}'}), timeout=30) as response:
                if response.status != 206 or response.headers.get('Content-Range') != f'bytes {have}-{end}/{total}':
                    raise ValueError('Invalid ranged response')
                try:
                    data = response.read()
                except http.client.IncompleteRead as error:
                    data = error.partial
            if not data:
                raise ValueError('Empty response')
            with partial.open('ab') as stream:
                stream.write(data)
        except Exception as error:
            if attempt >= 99:
                raise
            print('RETRY ' + path + ' ' + repr(error), flush=True)
            time.sleep(1)
    if not partial.exists() or partial.stat().st_size != total:
        raise ValueError('Incomplete asset')
    if path.endswith('.zip'):
        with zipfile.ZipFile(partial) as archive:
            if archive.testzip() is not None:
                raise ValueError('Archive CRC failed')
    partial.rename(target)
    entry = {'url': url, 'bytes': total, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
             'zip_entries_crc_verified': path.endswith('.zip')}
    print(json.dumps(entry), flush=True)
    return entry

with ThreadPoolExecutor(6) as pool:
    entries = list(pool.map(fetch, paths))
(root / 'setup/flutter-assets-receipt.json').write_text(json.dumps(entries, indent=2) + '\n')
