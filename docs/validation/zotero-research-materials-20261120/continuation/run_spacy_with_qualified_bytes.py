#!/usr/bin/env python3
"""Run spaCy unit tests with the pinned dylib used strictly as byte data."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


EXPECTED_SHA256 = 'ccc96620e01164d18e8d2e46b9a383677e4430c8889833bedab5b56c16a1b40f'
EXPECTED_BYTES = 2322928


def record(path):
    data = path.read_bytes()
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'git_blob_sha1': hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    fixture = args.fixture.resolve()
    before = record(fixture)
    if before['bytes'] != EXPECTED_BYTES or before['sha256'] != EXPECTED_SHA256:
        raise RuntimeError('The fixture does not match the exact pinned macOS library')
    wrapper = Path(__file__).resolve()
    adapter = wrapper.with_name('run_continuation.py')
    code_before = {'wrapper': record(wrapper), 'adapter': record(adapter)}
    command = [sys.executable, str(adapter), 'spacy', '--repo', str(args.repo.resolve()),
               '--expected-head', args.expected_head, '--output', str(args.output.resolve())]
    environment = os.environ.copy()
    environment['QUDS_SPACY_MACOS_LIBRARY'] = str(fixture)
    started = datetime.now(timezone.utc).isoformat()
    result = subprocess.run(command, env=environment, check=False)
    after = record(fixture)
    code_after = {'wrapper': record(wrapper), 'adapter': record(adapter)}
    unchanged = before == after and code_before == code_after
    supplement = {
        'status': 'passed' if result.returncode == 0 and unchanged else 'failed',
        'started_at_utc': started,
        'finished_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': args.expected_head,
        'fixture_path': str(fixture),
        'fixture_before': before,
        'fixture_after': after,
        'fixture_unchanged': before == after,
        'code_before': code_before,
        'code_after': code_after,
        'code_unchanged': code_before == code_after,
        'command': command,
        'environment_addition': {'QUDS_SPACY_MACOS_LIBRARY': str(fixture)},
        'primary_and_adapter_exit_code': result.returncode,
        'host_platform': sys.platform,
        'native_library_loaded_or_executed': False,
        'scope': 'The existing test reads the pinned dylib as a byte array to verify whole-file and Mach-O code digests. No dlopen, signing or macOS execution is performed.',
    }
    output = args.output.resolve()
    supplement_path = output / 'qualified-bytes.json'
    supplement_path.write_text(json.dumps(supplement, indent=2, sort_keys=True) + '\n')
    receipt_path = output / 'receipt.json'
    receipt = json.loads(receipt_path.read_text())
    receipt['qualified_bytes_fixture'] = supplement
    receipt['guards']['qualified_bytes_fixture_and_wrapper_unchanged'] = unchanged
    receipt['artifacts'][supplement_path.name] = record(supplement_path)
    if not unchanged:
        receipt['status'] = 'failed'
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'qualified_bytes': supplement['status'], 'fixture_sha256': after['sha256'],
                      'native_library_loaded_or_executed': False}), flush=True)
    return result.returncode if unchanged else 1


if __name__ == '__main__':
    sys.exit(main())
