#!/usr/bin/env python3
"""Audit the incoming lock metadata and reuse the verified runtime read-only."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import unquote, urljoin, urlparse

import yaml


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--before', required=True)
    parser.add_argument('--incoming', required=True)
    parser.add_argument('--previous-inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()

    def git(*arguments):
        return subprocess.check_output(['git', *arguments], cwd=repo)

    def digest(data):
        return hashlib.sha256(data).hexdigest()

    before = git('rev-parse', args.before).decode().strip()
    incoming = git('rev-parse', args.incoming).decode().strip()
    old_bytes = git('show', before + ':pubspec.lock')
    new_bytes = git('show', incoming + ':pubspec.lock')
    old = yaml.safe_load(old_bytes)
    new = yaml.safe_load(new_bytes)
    old_kind = old['packages']['image'].pop('dependency')
    new_kind = new['packages']['image'].pop('dependency')
    assert old_kind == 'direct main' and new_kind == 'transitive'
    assert old == new, 'The lock changes more than image dependency classification'

    config_path = repo/'.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    packages = {}
    manifests = {}
    for package in config['packages']:
        path = Path(unquote(urlparse(urljoin(config_path.as_uri(), package['rootUri'])).path))
        packages[package['name']] = path
        if path.is_relative_to(repo):
            manifest = (path/'pubspec.yaml').relative_to(repo).as_posix()
            left = git('show', before + ':' + manifest)
            right = git('show', incoming + ':' + manifest)
            assert left == right, manifest
            manifests[manifest] = digest(left)
    for manifest in ['pubspec.yaml']:
        left = git('show', before + ':' + manifest)
        right = git('show', incoming + ':' + manifest)
        assert left == right, manifest
        manifests[manifest] = digest(left)

    lock_checks = []
    cache = Path(os.environ['PUB_CACHE'])
    for name, record in new['packages'].items():
        if record['source'] != 'hosted':
            continue
        root = packages[name]
        installed = yaml.safe_load((root/'pubspec.yaml').read_text())
        assert str(installed['version']) == record['version'], name
        checksum = cache/'hosted-hashes/pub.dev'/f'{name}-{record["version"]}.sha256'
        assert checksum.read_text().strip() == record['description']['sha256'], name
        lock_checks.append(name)

    previous_path = args.previous_inputs.resolve()
    previous = json.loads(gzip.decompress(previous_path.read_bytes()))['before']
    sdk = Path(os.environ['FLUTTER_ROOT'])
    counters = {'dependency_files': 0, 'runtime_files': 0, 'workspace_files': 0}
    mismatches = []

    def verify(path, record, category):
        counters[category] += 1
        if not path.is_file() or path.stat().st_size != record['bytes'] or digest(path.read_bytes()) != record['sha256']:
            mismatches.append(str(path))

    for package in previous['dependencies'].values():
        root = Path(package['root'])
        for name, record in package['files'].items():
            verify(root/name, record, 'dependency_files')
    for name, record in previous['runtime'].items():
        verify(sdk/name, record, 'runtime_files')
    for name, record in previous['workspace'].items():
        verify(repo/name, record, 'workspace_files')
    assert not mismatches, mismatches
    result = {
        'status': 'passed',
        'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
        'before_commit': before,
        'incoming_commit': incoming,
        'observed_checkout_head': git('rev-parse', 'HEAD').decode().strip(),
        'lock_before_sha256': digest(old_bytes),
        'lock_incoming_sha256': digest(new_bytes),
        'only_changed_field': 'packages.image.dependency',
        'old_value': old_kind,
        'new_value': new_kind,
        'all_other_parsed_lock_fields_identical': True,
        'unchanged_package_manifests': manifests,
        'locked_hosted_packages_checked': len(lock_checks),
        'locked_hosted_package_names': sorted(lock_checks),
        'previous_input_inventory': str(previous_path.relative_to(repo)),
        'previous_input_inventory_sha256': digest(previous_path.read_bytes()),
        'exact_rechecked_inputs': counters,
        'mismatches': mismatches,
        'dependency_resolution_or_cache_write_performed': False,
        'reason': 'Only direct/transitive classification changed. Package manifests, versions, URLs, archive hashes, resolved graph and verified runtime/dependency bytes are unchanged.',
        'checker_sha256': digest(Path(__file__).read_bytes()),
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    assert not output.exists()
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: result[k] for k in ['status', 'only_changed_field', 'locked_hosted_packages_checked', 'exact_rechecked_inputs', 'dependency_resolution_or_cache_write_performed']}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
