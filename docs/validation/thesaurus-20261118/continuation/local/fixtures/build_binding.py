"""Validate the successful compile and exact inputs behind browser acceptance.

The receipt is evidence produced by our local runner, not a signed attestation.
These checks reject stale, incomplete, or mixed evidence directories and builds.
"""
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

from workspace_binding import SCHEMA as WORKSPACE_SCHEMA

SCHEMA = 'quds-thesaurus-browser-build-v2'
FIXTURE_FILES = (
    'lib/main.dart', 'native_pack_test.dart', 'native_visual_test.dart',
    'install_offline.py', 'run_browser.py', 'run_final_validation.py',
    'test_browser_harness.py', 'build_binding.py', 'workspace_binding.py',
    'test_workspace_binding.py',
)
SOURCE_HELPER_FILES = ('tools/thesaurus/build_packs.py',
                       'tools/thesaurus/export_review_packet.py')


def repository_root(fixture=None):
    fixture = (fixture or Path(__file__).parent).resolve()
    for candidate in (fixture, *fixture.parents):
        if all((candidate / name).is_file() for name in SOURCE_HELPER_FILES):
            return candidate
    raise ValueError('Acceptance fixture must remain with its source-verification helpers')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def digest(value):
    return sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def file_record(path, data):
    return {'path': path, 'bytes': len(data), 'sha256': sha256(data)}


def binding_metadata(output):
    """Link the finalized input and artifact inventories into the run receipt."""
    return {
        'schema': SCHEMA,
        'source_inputs': {
            'path': 'source-inputs.json.gz',
            'sha256': sha256((output / 'source-inputs.json.gz').read_bytes()),
        },
        'compiled_files': {
            'path': 'browser-build-files.json.gz',
            'sha256': sha256((output / 'browser-build-files.json.gz').read_bytes()),
        },
    }


def read_member(directory, member, expected_hash):
    if not isinstance(member, str):
        raise ValueError('Compile evidence member must have a relative path')
    relative = PurePosixPath(member)
    if relative.is_absolute() or not relative.parts or '..' in relative.parts:
        raise ValueError('Compile evidence member escapes its receipt directory')
    path = directory / member
    if path.is_symlink() or directory.resolve() not in path.resolve().parents:
        raise ValueError('Compile evidence member must remain inside its receipt directory')
    data = path.read_bytes()
    if sha256(data) != expected_hash:
        raise ValueError('Compile evidence member hash differs: ' + member)
    return data


def validate_records(records):
    if not isinstance(records, list) or not records:
        raise ValueError('Compile inventory is empty or malformed')
    names = []
    for record in records:
        if not isinstance(record, dict) or set(record) != {'path', 'bytes', 'sha256'}:
            raise ValueError('Compile inventory record is malformed')
        name, size, checksum = record['path'], record['bytes'], record['sha256']
        if not isinstance(name, str) or '\\' in name:
            raise ValueError('Compile inventory path is malformed')
        path = PurePosixPath(name)
        if path.is_absolute() or not path.parts or '..' in path.parts or str(path) != name:
            raise ValueError('Compile inventory path is not canonical')
        if type(size) is not int or size < 0 or not isinstance(checksum, str) or not re.fullmatch(r'[0-9a-f]{64}', checksum):
            raise ValueError('Compile inventory size or digest is malformed')
        names.append(name)
    if names != sorted(set(names)):
        raise ValueError('Compile inventory paths must be unique and sorted')
    if not {'index.html', 'flutter_bootstrap.js', 'main.dart.js'} <= set(names):
        raise ValueError('Compile inventory lacks Flutter entry points')


def load_compile_receipt(receipt_path, fixture=None):
    """Read a completed, internally consistent compile and its exact inventory."""
    receipt_path = Path(receipt_path).resolve()
    fixture = (fixture or Path(__file__).parent).resolve()
    raw = receipt_path.read_bytes()
    receipt = json.loads(raw)
    if receipt.get('status') != 'native_passed_web_compiled_browser_not_run':
        raise ValueError('Compile receipt is not a completed successful run')
    if receipt.get('source_unchanged_during_build') is not True or receipt.get('source_unchanged_during_tests') is not True:
        raise ValueError('Compile receipt does not establish unchanged source inputs')
    binding = receipt.get('browser_build_binding', {})
    if binding.get('schema') != SCHEMA:
        raise ValueError('Compile receipt has no supported browser-build binding; rebuild the fixture')
    inputs_meta = binding['source_inputs']
    inputs_bytes = read_member(receipt_path.parent, inputs_meta['path'], inputs_meta['sha256'])
    inputs = json.loads(gzip.decompress(inputs_bytes))
    if digest(inputs) != receipt.get('input_digest'):
        raise ValueError('Compile source inventory does not match the input digest')
    if inputs.get('__workspace_binding__', {}).get('schema') != WORKSPACE_SCHEMA:
        raise ValueError('Compile source inventory does not verify effective workspace roots')
    fixture_inputs = {}
    for name in FIXTURE_FILES:
        checksum = sha256((fixture / name).read_bytes())
        if inputs.get('__fixture__/' + name, {}).get('sha256') != checksum:
            raise ValueError('Compile receipt uses a different acceptance fixture: ' + name)
        fixture_inputs[name] = checksum
    helper_inputs = {}
    repo = repository_root(fixture)
    for name in SOURCE_HELPER_FILES:
        checksum = sha256((repo / name).read_bytes())
        if inputs.get('__helper__/' + name, {}).get('sha256') != checksum:
            raise ValueError('Compile receipt uses a different source-verification helper: ' + name)
        helper_inputs[name] = checksum
    files_meta = binding['compiled_files']
    files_bytes = read_member(receipt_path.parent, files_meta['path'], files_meta['sha256'])
    records = json.loads(gzip.decompress(files_bytes))
    validate_records(records)
    if receipt.get('compiled_browser_files') != len(records) or receipt.get('compiled_browser_bytes') != sum(record['bytes'] for record in records):
        raise ValueError('Compile artifact totals differ from the bound inventory')
    runs = [run for run in receipt.get('runs', []) if run.get('name') == 'browser-build']
    if len(runs) != 1 or runs[0].get('exit_code') != 0:
        raise ValueError('Compile receipt requires one successful browser-build command')
    run = runs[0]
    command = run.get('command', [])
    required = {'web', '--release', '--csp', '--no-web-resources-cdn', '--pwa-strategy=none'}
    if not isinstance(command, list) or not required <= set(command):
        raise ValueError('Compile command did not select the qualified offline fixture settings')
    target = [value.removeprefix('--target=') for value in command if value.startswith('--target=')]
    if len(target) != 1 or not target[0].replace('\\', '/').endswith('/fixtures/lib/main.dart'):
        raise ValueError('Compile command does not target the acceptance fixture')
    for stream in ('stdout', 'stderr'):
        read_member(receipt_path.parent, run[stream], run[stream + '_sha256'])
    return records, {
        'schema': SCHEMA,
        'receipt_path': str(receipt_path),
        'receipt_sha256': sha256(raw),
        'source_commit': receipt.get('base_commit'),
        'source_input_digest': receipt['input_digest'],
        'source_inventory_sha256': inputs_meta['sha256'],
        'compiled_inventory_sha256': files_meta['sha256'],
        'compiled_files': len(records),
        'compiled_bytes': receipt['compiled_browser_bytes'],
        'fixture_inputs': fixture_inputs,
        'source_verification_helpers': helper_inputs,
        'workspace_binding_schema': WORKSPACE_SCHEMA,
        'build_command': command,
    }
