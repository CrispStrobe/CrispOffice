#!/usr/bin/env python3
"""Run current regression probes against a verified pre-change source snapshot.

The workspace must have been extracted from BASE with the production sources,
workspace manifests, and bundled fonts intact. Its baseline-source.json lists
those source paths. Current probes and the unchanged dependency lock are copied
separately. A real offline Pub resolution with the verified Flutter SDK creates
package metadata.
Expected regression failures are evidence, not a passing qualification gate.
"""
import argparse
import datetime
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

REPO = Path(__file__).resolve().parents[3]
BASE = '0d19b16e10c6bc8492f47880321df2d9f2561223'
PROBES = ['font_subset_structure_test.dart', 'pdf_unicode_alias_export_test.dart']
SUPPORT = ['support/pdf_alias_fixture.dart']


def digest(data):
    return hashlib.sha256(data).hexdigest()


def blob_id(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    metadata = json.loads((workspace / 'baseline-source.json').read_text())
    if metadata['base_commit'] != BASE:
        raise ValueError('The source snapshot is not the specified baseline')
    tree = subprocess.check_output(['git', 'ls-tree', '-r', '-z', BASE], cwd=REPO)
    blobs = {}
    for record in tree.split(b'\0'):
        if not record:
            continue
        header, name = record.split(b'\t', 1)
        blobs[name.decode()] = header.split()[2].decode()
    source_hashes = {}
    for relative in metadata['source_paths']:
        data = (workspace / relative).read_bytes()
        if blob_id(data) != blobs[relative]:
            raise ValueError('Baseline source differs: ' + relative)
        source_hashes[relative] = digest(data)
    probe_hashes = {}
    for relative in PROBES + SUPPORT:
        path = Path('packages/quds_office_engine/test') / relative
        destination = workspace / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / path, destination)
        probe_hashes[str(path)] = digest(destination.read_bytes())
    shutil.copyfile(REPO / 'pubspec.lock', workspace / 'pubspec.lock')
    lock_hash = digest((workspace / 'pubspec.lock').read_bytes())
    receipt = {'started_utc': now(), 'baseline_commit': BASE,
               'current_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO).decode().strip(),
               'source_method': metadata['source_method'],
               'source_sha256': source_hashes, 'probe_sha256': probe_hashes,
               'lock_sha256': lock_hash, 'commands': [],
               'harness_sha256': digest(Path(__file__).read_bytes()),
               'github_actions': 'No Actions access.'}
    receipt_path = output / 'receipt.json'

    def save():
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')

    def run(name, command, cwd):
        started = time.monotonic()
        raw_out = output / (name + '.stdout')
        raw_err = output / (name + '.stderr')
        with raw_out.open('wb') as out, raw_err.open('wb') as err:
            result = subprocess.run(command, cwd=cwd, stdout=out, stderr=err,
                                    env=dict(os.environ, QUDS_ALIAS_RENDER_OUTPUT=''))
        stdout, stderr = raw_out.read_bytes(), raw_err.read_bytes()
        item = {'name': name, 'command': command, 'cwd': str(cwd),
                'exit_code': result.returncode, 'duration_seconds': time.monotonic() - started,
                'stdout_sha256': digest(stdout), 'stderr_sha256': digest(stderr),
                'stdout': name + '.stdout.gz', 'stderr': name + '.stderr.gz'}
        (output / item['stdout']).write_bytes(gzip.compress(stdout, mtime=0))
        (output / item['stderr']).write_bytes(gzip.compress(stderr, mtime=0))
        raw_out.unlink()
        raw_err.unlink()
        receipt['commands'].append(item)
        save()
        return item, stdout

    save()
    resolution, _ = run('resolve', ['dart', 'pub', 'get', '--offline', '--enforce-lockfile'], workspace)
    if resolution['exit_code']:
        raise SystemExit('Baseline dependency resolution failed; see receipt')
    if digest((workspace / 'pubspec.lock').read_bytes()) != lock_hash:
        raise ValueError('The baseline lock changed during resolution')
    config = workspace / '.dart_tool/package_config.json'
    receipt['package_config_sha256'] = digest(config.read_bytes())
    package_data = json.loads(config.read_text())
    engine = next(p for p in package_data['packages'] if p['name'] == 'quds_office_engine')
    from urllib.parse import unquote, urlparse
    root = engine['rootUri']
    resolved = (Path(unquote(urlparse(root).path)) if root.startswith('file:')
                else (config.parent / unquote(root)).resolve())
    if resolved != workspace / 'packages/quds_office_engine':
        raise ValueError('Pub did not resolve the baseline engine source')
    save()
    item, stdout = run('tests', ['dart', 'test', '--reporter', 'json'] + ['test/' + p for p in PROBES],
                       workspace / 'packages/quds_office_engine')
    spec = importlib.util.spec_from_file_location('qualification', Path(__file__).with_name('validate.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    item['summary'] = module.summarize_events(stdout)
    receipt['source_unchanged'] = all(digest((workspace / p).read_bytes()) == h
                                     for p, h in source_hashes.items())
    receipt['probes_match_current'] = all(digest((REPO / p).read_bytes()) == h
                                         for p, h in probe_hashes.items())
    receipt['finished_utc'] = now()
    receipt['interpretation'] = 'Pre-change regression probe results; failing tests are expected and are not a qualification pass.'
    save()
    print(json.dumps({'summary': item['summary'],
                      'source_unchanged': receipt['source_unchanged'],
                      'probes_match_current': receipt['probes_match_current']}), flush=True)


if __name__ == '__main__':
    main()
