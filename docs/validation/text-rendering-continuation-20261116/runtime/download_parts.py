#!/usr/bin/env python3
"""Fetch official, pinned runtime artifacts with bounded parallel ranges."""
import argparse
import concurrent.futures
import hashlib
import http.client
import json
import os
from pathlib import Path
import threading
import time
from urllib.request import Request, urlopen

parser = argparse.ArgumentParser()
parser.add_argument('url')
parser.add_argument('output', type=Path)
parser.add_argument('--bytes', type=int, required=True)
parser.add_argument('--sha256')
parser.add_argument('--workers', type=int, default=12)
parser.add_argument('--priority-dart', action='store_true')
args = parser.parse_args()
args.output.parent.mkdir(parents=True, exist_ok=True)
parts = args.output.with_name(args.output.name + '.parts')
parts.mkdir(exist_ok=True)
chunk = 4 * 1024 * 1024
guard = threading.Lock()
started = time.monotonic()
record = {'url': args.url, 'expected_bytes': args.bytes, 'expected_sha256': args.sha256,
          'chunk_bytes': chunk, 'workers': args.workers, 'parts': [], 'status': 'running'}

def save():
    args.output.with_suffix(args.output.suffix + '.receipt.json').write_text(json.dumps(record, indent=2) + '\n')

with urlopen(Request(args.url, method='HEAD'), timeout=30) as response:
    if int(response.headers['Content-Length']) != args.bytes:
        raise ValueError('Unexpected artifact length')
    record['official_headers'] = {key: value for key, value in response.headers.items()
                                  if key.lower() in ['content-length', 'x-goog-hash', 'etag', 'last-modified']}
save()

def fetch(start):
    end = min(start + chunk, args.bytes) - 1
    dest = parts / f'{start:012d}.part'
    if dest.is_file() and dest.stat().st_size == end - start + 1:
        return {'start': start, 'end': end, 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest(), 'reused': True}
    failures = 0
    requests = 0
    while not dest.exists() or dest.stat().st_size != end - start + 1:
        received = dest.stat().st_size if dest.exists() else 0
        request_start = start + received
        request_end = min(request_start + 512 * 1024 - 1, end)
        try:
            req = Request(args.url, headers={'Range': f'bytes={request_start}-{request_end}'})
            requests += 1
            with urlopen(req, timeout=25) as response:
                expected = f'bytes {request_start}-{request_end}/{args.bytes}'
                if response.status != 206 or response.headers.get('Content-Range') != expected:
                    raise ValueError(f'Unexpected range response: {response.status}, {response.headers.get("Content-Range")}')
                received_now = 0
                with dest.open('ab') as stream:
                    while True:
                        try:
                            payload = response.read(64 * 1024)
                        except http.client.IncompleteRead as error:
                            payload = error.partial
                        if not payload:
                            break
                        stream.write(payload)
                        received_now += len(payload)
                        if received_now > request_end - request_start + 1:
                            raise ValueError('Server sent excess range bytes')
            if not received_now:
                raise ValueError('Empty range')
            failures = 0
            if dest.stat().st_size < end - start + 1:
                continue
            entry = {'start': start, 'end': end, 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest(), 'requests': requests}
            with guard:
                record['parts'].append(entry)
                record['downloaded_bytes'] = sum(p['end'] - p['start'] + 1 for p in record['parts'])
                record['elapsed_seconds'] = time.monotonic() - started
                save()
                print(json.dumps({'file': args.output.name, 'complete_parts': len(record['parts']),
                                  'downloaded_bytes': record['downloaded_bytes'], 'seconds': round(record['elapsed_seconds'], 1)}), flush=True)
            return entry
        except Exception as e:
            failures += 1
            with guard:
                print(json.dumps({'start': request_start, 'failures': failures, 'error': str(e)}), flush=True)
            if failures == 4:
                raise
            time.sleep(failures)

try:
    ordered_starts = list(range(0, args.bytes, chunk))
    if args.priority_dart:
        metadata = json.loads((args.output.parent / 'dart-central.json').read_text())
        required = set()
        snapshots = {'dartdev_aot.dart.snapshot', 'analysis_server_aot.dart.snapshot',
                     'frontend_server_aot.dart.snapshot', 'kernel-service.dart.snapshot',
                     'kernel_worker_aot.dart.snapshot', 'dds_aot.dart.snapshot'}
        for info in metadata:
            name = info['filename']
            if name.startswith('dart-sdk/lib/') or name in {
                'dart-sdk/bin/dart', 'dart-sdk/bin/dartvm', 'dart-sdk/bin/dartaotruntime',
                'dart-sdk/version', 'dart-sdk/revision', 'dart-sdk/sdk_packages.yaml',
            } or name.removeprefix('dart-sdk/bin/snapshots/') in snapshots:
                first = info['header_offset'] // chunk * chunk
                last = (info['header_offset'] + info['compressed_size'] + 65536) // chunk * chunk
                required.update(range(first, last + 1, chunk))
        ordered_starts.sort(key=lambda start: (start not in required, start))
    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        entries = list(pool.map(fetch, ordered_starts))
    entries.sort(key=lambda entry: entry['start'])
    digest = hashlib.sha256()
    with args.output.open('wb') as stream:
        for entry in entries:
            data = (parts / f'{entry["start"]:012d}.part').read_bytes()
            digest.update(data)
            stream.write(data)
    record['sha256'] = digest.hexdigest()
    if args.sha256 and digest.hexdigest() != args.sha256:
        raise ValueError('Official SHA-256 mismatch')
    record['status'] = 'passed'
    record['elapsed_seconds'] = time.monotonic() - started
    record['parts'] = entries
    save()
    print(json.dumps({'status': 'passed', 'file': str(args.output), 'sha256': record['sha256'], 'seconds': record['elapsed_seconds']}), flush=True)
except BaseException as e:
    record['status'] = 'failed'
    record['error'] = repr(e)
    save()
    raise
