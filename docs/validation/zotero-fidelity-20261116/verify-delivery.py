#!/usr/bin/env python3
"""Compare delivered bytes with separately qualified Zotero/host/terminal inputs.

Read-only apart from the requested JSON output. No tests, builds, dependency
resolution, network calls, or GitHub Actions operations are performed. A newer
documentation commit is permitted; the recorded production inputs must match.

After the final Quds documentation commit and companion pin, write the final
cross-repository receipt into the companion repository with --output. This
avoids making a receipt's own Quds commit hash self-referential.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess


HERE = Path(__file__).resolve().parent
EVIDENCE = Path('docs/validation/zotero-fidelity-20261116')
PACKAGES = ('quds_office_engine', 'quds_office_editor', 'quds_reports',
            'legacy_doc_parser')
HASH = re.compile(r'[0-9a-f]{64}\Z')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value, *, compact=False):
    if compact:
        return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def git_text(repo, *args):
    return git(repo, *args).decode().strip()


def git_paths(repo, *args):
    return [p.decode() for p in git(repo, *args).split(b'\0') if p]


def child(root, name):
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or '..' in path.parts or '\\' in name:
        raise ValueError('Unsafe recorded relative path: ' + repr(name))
    return root.joinpath(*path.parts)


def stored_bytes(path):
    """Hash original log bytes even when the archive stores lossless .gz logs."""
    if path.is_file():
        return path.read_bytes(), path, 'original'
    compressed = Path(str(path) + '.gz')
    if compressed.is_file():
        return gzip.decompress(compressed.read_bytes()), compressed, 'gzip'
    raise FileNotFoundError(str(path))


def load(path):
    data, _, _ = stored_bytes(path)
    return json.loads(data)


def issue(section, message, **details):
    section['issues'].append({'message': message, **details})


def require(section, condition, message, **details):
    if not condition:
        issue(section, message, **details)


def hash_file(path):
    before = path.stat()
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError('File changed while hashing: ' + str(path))
    return value.hexdigest()


def compare_map(section, mapping, resolver, label, *, regular=False):
    if not isinstance(mapping, dict) or not mapping:
        raise ValueError(label + ' has no recorded input map')
    missing, mismatched = [], []
    for name, expected in sorted(mapping.items()):
        if not isinstance(expected, str) or not HASH.fullmatch(expected):
            raise ValueError(label + ' has an invalid SHA-256 for ' + name)
        path = resolver(name)
        if not path.is_file() or (regular and path.is_symlink()):
            missing.append(name)
            continue
        actual = hash_file(path)
        if actual != expected:
            mismatched.append({'path': name, 'expected': expected, 'actual': actual})
    result = {'recorded_files': len(mapping), 'checked_files': len(mapping) - len(missing),
              'missing': missing, 'mismatched': mismatched,
              'all_recorded_bytes_match': not missing and not mismatched}
    require(section, result['all_recorded_bytes_match'], label + ' differs from current bytes',
            missing=missing, mismatched=mismatched)
    return result


def verify_artifacts(section, base, mapping, label):
    missing, changed, compressed = [], [], []
    for name, expected in sorted(mapping.items()):
        try:
            data, path, storage = stored_bytes(child(base, name))
        except FileNotFoundError:
            missing.append(name)
            continue
        if digest(data) != expected:
            changed.append(name)
        if storage == 'gzip':
            compressed.append({'recorded': name, 'stored': str(path.relative_to(base))})
    require(section, not missing and not changed, label + ' artifact mismatch',
            missing=missing, mismatched=changed)
    return {'recorded_files': len(mapping), 'missing': missing, 'mismatched': changed,
            'lossless_gzip_remappings': compressed}


def source_pair(section, directory, receipt, *, kind):
    maps = []
    for stage in ('before', 'after'):
        if kind == 'host':
            name = receipt['source_inventory_' + stage]
            metadata = {'files': receipt['source_file_count'],
                        'aggregate_sha256': receipt['source_aggregate_sha256_' + stage]}
        else:
            metadata = receipt.get('source_' + stage, {}) if kind != 'live' else {}
            name = metadata.get('map', 'source-' + stage + '.json')
        data, actual_path, storage = stored_bytes(child(directory, name))
        payload = json.loads(data)
        mapping = payload.get('sha256_by_path', payload)
        if not isinstance(mapping, dict) or not mapping:
            raise ValueError('Empty source map: ' + name)
        file_hash = (receipt.get('source_' + stage + '_sha256') if kind == 'live'
                     else metadata.get('map_sha256'))
        if file_hash is not None:
            require(section, digest(data) == file_hash, 'Recorded source-map digest differs', map=name)
        expected_count = receipt['source_files'] if kind == 'live' else metadata.get('files')
        require(section, expected_count == len(mapping), 'Recorded source-map count differs',
                map=name, recorded=expected_count, actual=len(mapping))
        aggregate = digest(encoded(mapping, compact=kind == 'host'))
        if 'aggregate_sha256' in metadata:
            require(section, metadata['aggregate_sha256'] == aggregate,
                    'Receipt aggregate differs from its source map', map=name)
        if 'sha256_by_path' in payload:
            require(section, payload.get('files') == len(mapping) and
                    payload.get('aggregate_sha256') == aggregate,
                    'Source-map internal count/aggregate differs', map=name)
        section['source_' + stage] = {'map': name, 'stored_path': str(actual_path),
            'storage': storage, 'map_sha256': digest(data), 'files': len(mapping),
            'aggregate_sha256': aggregate}
        maps.append(mapping)
    require(section, maps[0] == maps[1], 'Before/after source maps differ')
    require(section, receipt.get('source_unchanged') is True,
            'Original qualification did not record unchanged source')
    return maps[0]


def log_map(receipt, key):
    return {step['log']: step['log_sha256'] for step in receipt.get(key, [])
            if 'log' in step and 'log_sha256' in step}


def canonical_scope(name):
    parts = PurePosixPath(name).parts
    return (PurePosixPath(name).name in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}
            or (len(parts) >= 4 and parts[0] == 'packages' and parts[2] in {'lib', 'test'})
            or name.startswith('packages/quds_office_editor/example/'))


def canonical_inventory(section, repo, mapping):
    current = {p for p in git_paths(repo, 'ls-files', '-z') if canonical_scope(p)}
    untracked = {p for p in git_paths(repo, 'ls-files', '--others', '--exclude-standard', '-z')
                 if canonical_scope(p)}
    additional = sorted((current | untracked) - set(mapping))
    production = [p for p in additional if not p.startswith('docs/')]
    dirty = [p for p in git_paths(repo, 'diff', '--name-only', '-z', 'HEAD')
             if canonical_scope(p) and not p.startswith('docs/')]
    require(section, not production, 'Unqualified production inputs were added', paths=production)
    require(section, not dirty, 'Qualified production inputs differ from current Quds HEAD', paths=dirty)
    return {'additional_production_inputs': production,
            'additional_documentation_inputs': [p for p in additional if p.startswith('docs/')],
            'production_changes_from_current_head': dirty}


def host_inventory(repo, tests):
    paths = {child(repo, name) for name in tests}
    for relative in ('lib', *(f'packages/{name}/lib' for name in PACKAGES)):
        paths.update(p for p in (repo / relative).rglob('*') if p.is_file())
    for base in (repo, *(repo / 'packages' / name for name in PACKAGES)):
        paths.update(base / name for name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')
                     if (base / name).is_file())
    return {str(p.relative_to(repo)) for p in paths}


def terminal_dependency_paths(repo, receipt):
    """Recheck reachable local imports so a newly present import cannot escape the map."""
    libraries = {}
    for base in (repo, *sorted((repo / 'packages').glob('*'))):
        manifest = base / 'pubspec.yaml'
        if manifest.is_file():
            match = re.search(r'^name:\s*([A-Za-z0-9_]+)\s*$', manifest.read_text(), re.MULTILINE)
            if match:
                libraries[match[1]] = base / 'lib'
    pending = [repo / 'test' / name for name in receipt.get('tests', []) + receipt.get('live_tests', [])]
    paths = set()
    while pending:
        path = pending.pop().resolve()
        if path in paths or not path.is_file() or not path.is_relative_to(repo):
            continue
        paths.add(path)
        for directive in re.findall(r'\b(?:import|export|part)\s+([^;]*);', path.read_text()):
            for uri in re.findall(r'''['"]([^'"]+)['"]''', directive):
                if uri.startswith('package:'):
                    package, _, suffix = uri[8:].partition('/')
                    if package in libraries:
                        pending.append(libraries[package] / suffix)
                elif ':' not in uri:
                    pending.append(path.parent / uri)
    paths.update(repo / name for name in git_paths(repo, 'ls-files', '-z', 'packages/dartssh2'))
    paths.update((repo / 'packages/crisp_storage/hook').rglob('*.dart'))
    return {str(path.relative_to(repo)) for path in paths}


def retained_bundle(section, receipt, root, *, required):
    mapping = receipt.get('bundle_files', {})
    require(section, isinstance(mapping, dict) and 'kernel_blob.bin' in mapping,
            'Build receipt does not identify the actual application kernel')
    if not root.is_dir():
        require(section, not required, 'Retained application bundle is unavailable', path=str(root))
        return {'available': False, 'status': 'not_available', 'path': str(root),
                'original_compilation_recorded_passed': receipt.get('passed') is True}
    result = compare_map(section, mapping, lambda name: child(root, name), 'Retained application bundle')
    additional = sorted(str(p.relative_to(root)) for p in root.rglob('*')
                        if p.is_file() and str(p.relative_to(root)) not in mapping)
    require(section, not additional, 'Retained bundle inventory differs', additional=additional)
    return {'available': True, 'path': str(root), **result, 'additional_files': additional,
            'kernel_sha256': hash_file(root / 'kernel_blob.bin') if (root / 'kernel_blob.bin').is_file() else None}


def verify_index(section, repo, paths):
    object_format = git_text(repo, 'rev-parse', '--show-object-format')
    if object_format not in ('sha1', 'sha256'):
        raise ValueError('Unsupported Git object format: ' + object_format)
    entries = {}
    for record in git(repo, 'ls-files', '--stage', '-z').split(b'\0'):
        if record:
            metadata, name = record.split(b'\t', 1)
            entries.setdefault(name.decode(), []).append(tuple(metadata.decode().split()))
    changed = []
    for name in sorted(paths):
        path = child(repo, name)
        if not path.is_file() or path.is_symlink():
            changed.append(name)
            continue
        data = path.read_bytes()
        oid = hashlib.new(object_format, b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        mode = '100755' if path.stat().st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH) else '100644'
        if entries.get(name) != [(mode, oid, '0')]:
            changed.append(name)
    require(section, not changed, 'Managed files or declarations differ from the Git index', paths=changed)
    return {'checked_files': len(paths), 'mismatched': changed, 'matches_index': not changed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=HERE.parents[2], help='Current Quds repository')
    parser.add_argument('--companion-repo', '--companion', type=Path, help='Current CrispCloud repository')
    parser.add_argument('--quds-commit', default='HEAD', help='Must resolve to the current Quds HEAD')
    parser.add_argument('--workspace', type=Path, help='Root containing optional retained runtime artifacts')
    parser.add_argument('--studio-bundle', type=Path, help='Retained Studio build/flutter_assets directory')
    parser.add_argument('--live-kernel', type=Path, help='Retained executed native acceptance kernel')
    parser.add_argument('--companion-kernel-receipt', '--companion-bundle-receipt',
                        dest='companion_kernel_receipt', type=Path,
                        help='Optional full-app receipt with independently successful Dart kernel target')
    parser.add_argument('--require-runtime-artifacts', action='store_true',
                        help='Fail if optional retained kernel/bundle files are absent')
    parser.add_argument('--output', type=Path, default=HERE / 'delivery-source-proof.json')
    args = parser.parse_args()
    source = args.source.resolve()
    companion = (args.companion_repo or source.parent / 'CrispCloud').resolve()
    workspace = (args.workspace or source.parent).resolve()
    evidence = source / EVIDENCE
    companion_evidence = companion / EVIDENCE
    source_head = git_text(source, 'rev-parse', 'HEAD')
    expected_head = git_text(source, 'rev-parse', '--verify', '--end-of-options', args.quds_commit + '^{commit}')
    companion_head = git_text(companion, 'rev-parse', 'HEAD') if companion.is_dir() else None
    report = {'schema': 1, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
              'verifier_sha256': hash_file(Path(__file__)), 'source': str(source),
              'companion': str(companion), 'quds_head': source_head,
              'requested_quds_commit': args.quds_commit, 'resolved_quds_commit': expected_head,
              'companion_head': companion_head, 'sections': {}, 'issues': [],
              'read_only_verification': True, 'tests_or_builds_reexecuted': False,
              'uses_github_actions': False, 'network_used': False}
    require(report, expected_head == source_head, 'Requested Quds commit is not current HEAD')

    def run(name, action, *, required=True):
        section = {'required': required, 'available': True, 'issues': []}
        report['sections'][name] = section
        try:
            action(section)
        except FileNotFoundError as error:
            section['available'] = False
            issue(section, 'Required verification input is unavailable', path=str(error))
        except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
            issue(section, 'Verification could not complete', error=str(error))
        section['passed'] = section['available'] and not section['issues']
        return section

    def qualify_canonical(section):
        directory = evidence / 'final'
        receipt = load(directory / 'receipt.json')
        section.update(receipt=str(directory / 'receipt.json'), qualified_commit=receipt['source_commit'],
                       recorded_tests_passed=receipt.get('total_tests_passed'))
        require(section, receipt.get('qualified') is True and receipt.get('all_commands_passed') is True,
                'Canonical receipt is not qualified')
        mapping = source_pair(section, directory, receipt, kind='canonical')
        section['inputs'] = compare_map(section, mapping, lambda name: child(source, name), 'Canonical qualification')
        section['inventory'] = canonical_inventory(section, source, mapping)
        section['logs'] = verify_artifacts(section, directory, log_map(receipt, 'commands'), 'Canonical logs')

    def qualify_live(section):
        directory = evidence / 'live-zotero'
        receipt = load(directory / 'logs/acceptance-receipt.json')
        section.update(receipt=str(directory / 'logs/acceptance-receipt.json'),
                       qualified_commit=receipt['source_commit'], original_result=receipt['result'])
        require(section, receipt.get('result') == 'passed' and receipt.get('kernel_unchanged') is True,
                'Live native receipt did not pass with an unchanged kernel')
        mapping = source_pair(section, directory / 'logs', receipt, kind='live')
        remappings = {
            'zotero-toolchain/harness/quds_office_studio/.dart_tool/package_config.json': 'inputs/studio-package_config.json',
            'zotero-toolchain/harness/quds_office_studio/pubspec.lock': 'inputs/studio-pubspec.lock',
            'zotero-toolchain/harness/quds_office_studio/pubspec.yaml': 'inputs/studio-pubspec.yaml',
        }
        resolved = {}
        def resolve(name):
            if name.startswith('quds_office_suite/'):
                return child(source, name.removeprefix('quds_office_suite/'))
            if name.startswith('zotero-native-fidelity-acceptance/'):
                archive = name.removeprefix('zotero-native-fidelity-acceptance/')
            elif name in remappings:
                archive = remappings[name]
            else:
                raise ValueError('Unknown live-input remapping: ' + name)
            resolved[name] = archive
            return child(directory, archive)
        section['inputs'] = compare_map(section, mapping, resolve, 'Live native qualification')
        section['archived_input_remappings'] = resolved
        section['artifacts'] = verify_artifacts(section, directory, receipt['artifact_hashes'], 'Live native artifacts')
        require(section, hash_file(directory / 'scripts/run-live-acceptance.py') == receipt['runner_sha256'],
                'Archived native runner differs from the executed runner')
        kernel = (args.live_kernel or workspace / 'zotero-native-fidelity-acceptance/fidelity-live.dill').resolve()
        if kernel.is_file():
            actual = hash_file(kernel)
            require(section, actual == receipt['kernel_sha256'], 'Retained executed native kernel differs')
            section['retained_kernel'] = {'available': True, 'path': str(kernel),
                'sha256': actual, 'matches_executed_kernel': actual == receipt['kernel_sha256']}
        else:
            require(section, not args.require_runtime_artifacts, 'Retained executed native kernel is unavailable')
            section['retained_kernel'] = {'available': False, 'status': 'not_available',
                'recorded_executed_sha256': receipt['kernel_sha256']}
        section['scope'] = 'Actual native component acceptance with an isolated warm synthetic profile; no full native app or cold-start claim.'

    def qualify_studio(section):
        directory = evidence / 'studio-bundle'
        receipt = load(directory / 'receipt.json')
        section.update(receipt=str(directory / 'receipt.json'), qualified_commit=receipt['source_commit'])
        require(section, receipt.get('passed') is True and receipt.get('exit_code') == 0,
                'Studio compilation receipt did not pass')
        mapping = source_pair(section, directory, receipt, kind='studio')
        section['inputs'] = compare_map(section, mapping, lambda name: child(source, name), 'Studio compilation inputs')
        section['inventory'] = canonical_inventory(section, source, mapping)
        section['logs'] = verify_artifacts(section, directory, {'build.log': receipt['log_sha256']}, 'Studio compilation log')
        root = (args.studio_bundle or workspace / 'zotero-toolchain/harness/quds_office_studio/build/flutter_assets').resolve()
        section['retained_bundle'] = retained_bundle(section, receipt, root, required=args.require_runtime_artifacts)
        section['scope'] = 'Complete Studio Dart/assets compilation; not a native executable or GUI acceptance.'

    host_receipt = None
    def qualify_host(section):
        nonlocal host_receipt
        directory = companion_evidence / 'final'
        host_receipt = load(directory / 'host-validation-receipt.json')
        receipt = host_receipt
        section.update(receipt=str(directory / 'host-validation-receipt.json'),
                       qualified_commit=receipt.get('head_at_completion'),
                       recorded_tests_passed=receipt.get('passed_test_count'))
        require(section, receipt.get('status') == 'passed', 'Host receipt did not pass')
        mapping = source_pair(section, directory, receipt, kind='host')
        section['inputs'] = compare_map(section, mapping, lambda name: child(companion, name), 'Companion host qualification')
        current = host_inventory(companion, receipt['tests'])
        added, removed = sorted(current - set(mapping)), sorted(set(mapping) - current)
        require(section, not added and not removed, 'Host source inventory differs', added=added, removed=removed)
        section['inventory'] = {'additional': added, 'removed': removed}
        section['logs'] = verify_artifacts(section, directory, log_map(receipt, 'steps'), 'Host logs')
        section['scope'] = 'Focused host tests against genuine locked dependencies; live native and canonical tests are separate.'

    def qualify_vendor(section):
        manifest_path = companion / 'tool/office_fidelity_manifest.json'
        manifest = load(manifest_path)
        section.update(manifest=str(manifest_path), final_quds_pin=manifest['source_commit'],
                       required_quds_pin=source_head)
        require(section, manifest['source_commit'] == source_head == expected_head,
                'Companion Office pin is not the current requested Quds HEAD')
        require(section, manifest.get('source_repository') == 'CrispStrobe/quds_office_suite',
                'Unexpected canonical repository declaration')
        standalone = manifest.get('standalone_sources', {})
        require(section, set(standalone) == {'packages/legacy_doc_parser'},
                'Unexpected standalone vendor boundary')
        mapping = manifest['files']
        section['managed_files'] = compare_map(section, mapping, lambda name: child(companion, name),
                                               'Managed vendor files', regular=True)
        quds = {name: value for name, value in mapping.items()
                if not any(name.startswith(prefix + '/') for prefix in standalone)}
        section['quds_files'] = compare_map(section, quds, lambda name: child(source, name),
                                            'Quds-managed canonical source', regular=True)
        declarations = {'tool/office_fidelity_manifest.json', 'pubspec.yaml'}
        for prefix, pin in standalone.items():
            declaration = prefix + '/UPSTREAM.json'
            declarations.add(declaration)
            require(section, load(child(companion, declaration)) == {**pin, 'patches': []},
                    'Standalone provenance differs from manifest', prefix=prefix)
            require(section, pin.get('repository') == 'CrispStrobe/legacy-doc-parser' and
                    re.fullmatch(r'[0-9a-f]{40}', pin.get('commit', '')) is not None,
                    'Invalid standalone provenance pin')
            expected_prefix = {name for name in mapping if name.startswith(prefix + '/')}
            tracked_prefix = set(git_paths(companion, 'ls-files', '-z', prefix)) - {declaration}
            require(section, tracked_prefix == expected_prefix,
                    'Standalone tracked inventory differs from manifest', prefix=prefix,
                    additional=sorted(tracked_prefix - expected_prefix),
                    missing=sorted(expected_prefix - tracked_prefix))
        section['standalone_sources'] = standalone
        section['index'] = verify_index(section, companion, set(mapping) | declarations)
        dirty = set(git_paths(companion, 'diff', '--name-only', '-z', 'HEAD')) & (set(mapping) | declarations)
        require(section, not dirty, 'Vendor delivery differs from current companion HEAD', paths=sorted(dirty))
        section['managed_inventory_sha256'] = digest(encoded(mapping, compact=True))
        if host_receipt is not None:
            qualified = host_receipt['vendor_manifest_after']
            require(section, qualified['managed_inventory_sha256'] == section['managed_inventory_sha256'] and
                    qualified['managed_file_count'] == len(mapping),
                    'Managed bytes/inventory differ from host-qualified vendor')
            require(section, qualified['standalone_sources'] == standalone,
                    'Standalone source pin differs from host qualification')
            section['host_qualified_quds_pin'] = qualified['source_commit']
            section['pin_only_metadata_change_permitted'] = True

    def qualify_terminal(section, directory=None):
        directory = directory or companion_evidence / 'terminal-integration'
        receipt = load(directory / 'receipt.json')
        section.update(receipt=str(directory / 'receipt.json'), qualified_commit=receipt['source_commit'],
                       selection=receipt.get('selection'), selected_tests=receipt.get('tests'))
        require(section, receipt.get('qualified') is True and receipt.get('all_commands_passed') is True,
                'Terminal receipt did not qualify')
        mapping = source_pair(section, directory, receipt, kind='terminal')
        section['inputs'] = compare_map(section, mapping, lambda name: child(companion, name), 'Terminal qualification')
        additional = sorted(terminal_dependency_paths(companion, receipt) - set(mapping))
        require(section, not additional, 'New reachable terminal inputs escaped the recorded map', paths=additional)
        section['additional_reachable_inputs'] = additional
        section['logs'] = verify_artifacts(section, directory, log_map(receipt, 'commands'), 'Terminal logs')
        section['scope'] = receipt.get('source_scope')
        section['recorded_command_counts'] = [{key: step[key] for key in
            ('name', 'passed_tests', 'skipped_tests', 'failed_tests', 'passed', 'seconds') if key in step}
            for step in receipt.get('commands', [])]

    def qualify_companion_kernel(section, receipt_path):
        directory = receipt_path.parent
        receipt = load(receipt_path)
        kernel = receipt['kernel_compilation']
        section.update(receipt=str(receipt_path), qualified_commit=receipt['source_commit'],
                       original_bundle_passed=receipt.get('bundle_passed'),
                       original_kernel_compilation_status=kernel.get('status'),
                       native_assets=receipt.get('native_assets'),
                       scope='Full application Dart kernel only; the required Cargo native-assets hook blocked the complete bundle.')
        require(section, kernel.get('status') == 'passed' and kernel.get('target') == 'kernel_snapshot_program',
                'Application kernel target was not independently qualified')
        require(section, receipt.get('source_unchanged') is True and
                receipt.get('dependency_manifests_unchanged') is True,
                'Kernel invocation did not preserve original source/dependency inputs')
        maps = []
        for stage in ('before', 'after'):
            name = receipt['source_' + stage]
            raw, _, _ = stored_bytes(child(directory, name))
            require(section, digest(raw) == receipt['source_' + stage + '_sha256'],
                    'Full-app source-map digest differs', map=name)
            mapping = json.loads(raw)
            require(section, len(mapping) == receipt['source_files'], 'Full-app source-map count differs', map=name)
            maps.append(mapping)
        require(section, maps[0] == maps[1], 'Full-app before/after source maps differ')
        # This broad build-input snapshot includes pin metadata. Preserve its
        # strict byte result even when an independently verified final pin is
        # the sole permitted change; do not call all original bytes unchanged.
        broad = {'issues': []}
        section['broad_source_inputs'] = compare_map(broad, maps[0],
            lambda name: child(companion, name), 'Full-app build-input snapshot')
        changes = section['broad_source_inputs']['mismatched']
        missing = section['broad_source_inputs']['missing']
        allowed = False
        pin_path = 'tool/office_fidelity_manifest.json'
        if not missing and len(changes) == 1 and changes[0]['path'] == pin_path:
            original = git(companion, 'show', receipt['source_commit'] + ':' + pin_path)
            original_json = json.loads(original)
            current_json = load(companion / pin_path)
            metadata_only = current_json == {**original_json, 'source_commit': source_head}
            vendor = report['sections']['companion_vendor']
            allowed = (digest(original) == maps[0][pin_path] and metadata_only and
                       vendor.get('passed') is True and current_json['source_commit'] == expected_head)
            section['metadata_only_pin_advance'] = {
                'verified': allowed, 'path': pin_path,
                'original_blob_commit': receipt['source_commit'],
                'original_blob_sha256': digest(original),
                'recorded_blob_sha256': maps[0][pin_path],
                'current_sha256': hash_file(companion / pin_path),
                'original_quds_pin': original_json.get('source_commit'),
                'current_quds_pin': current_json.get('source_commit'),
                'json_diff_is_exactly_source_commit': metadata_only,
                'managed_inventory_and_standalone_pins_unchanged':
                    original_json.get('files') == current_json.get('files') and
                    original_json.get('standalone_sources') == current_json.get('standalone_sources'),
                'canonical_vendor_section_passed': vendor.get('passed') is True}
        require(section, (not missing and not changes) or allowed,
                'Full-app recorded inputs changed outside the independently verified final pin',
                missing=missing, mismatched=changes)
        section['source_code_and_build_inputs_continuity_verified'] = (not missing and not changes) or allowed
        compiler_artifacts = {kernel[key]: kernel[key + '_sha256']
                              for key in ('stamp', 'depfile', 'compiler_inputs')}
        section['compiler_evidence'] = verify_artifacts(section, directory, compiler_artifacts,
                                                       'Application compiler evidence')
        inputs = load(child(directory, kernel['compiler_inputs']))
        require(section, len(inputs) == kernel['compiler_inputs_count'], 'Compiler input count differs')
        original_source = Path(receipt['source'])
        original_project = Path(receipt['isolated_project'])
        original_workspace = original_source.parent
        def resolve_environment(name):
            path = Path(name)
            if path.is_relative_to(original_source):
                return companion / path.relative_to(original_source)
            if path.is_relative_to(original_workspace / 'zotero-toolchain'):
                return workspace / path.relative_to(original_workspace)
            raise ValueError('Unknown compiler-input root: ' + name)
        compiler_check = {'issues': []}
        section['compiler_inputs'] = compare_map(compiler_check, inputs, resolve_environment,
                                                 'Actual application compiler inputs')
        require(section, not section['compiler_inputs']['mismatched'], 'Actual application compiler inputs changed',
                mismatched=section['compiler_inputs']['mismatched'])
        if section['compiler_inputs']['missing']:
            require(section, not args.require_runtime_artifacts,
                    'Retained application compiler inputs are unavailable',
                    missing=section['compiler_inputs']['missing'])
            section['compiler_inputs']['availability_note'] = 'Some original environment files are unavailable; their current bytes are not claimed verified.'
        retained = resolve_environment(kernel['kernel_path'])
        if retained.is_file():
            actual = hash_file(retained)
            require(section, actual == kernel['kernel_sha256'] and retained.stat().st_size == kernel['kernel_bytes'],
                    'Retained actual application kernel differs')
            section['retained_kernel'] = {'available': True, 'path': str(retained),
                'sha256': actual, 'bytes': retained.stat().st_size,
                'matches_compiled_kernel': actual == kernel['kernel_sha256']}
        else:
            require(section, not args.require_runtime_artifacts, 'Retained full application kernel is unavailable')
            section['retained_kernel'] = {'available': False, 'status': 'not_available',
                'recorded_compiled_sha256': kernel['kernel_sha256']}
        copy = receipt['copied_lib_source']
        require(section, copy.get('pre_generation_copy_match') is True and
                copy.get('post_generation_matches_except_declared_outputs') is True,
                'Isolated compilation source did not match canonical source with declared generated outputs')
        section['declared_generated_localization_outputs'] = copy.get('generated_outputs', [])
        section['isolated_project_remapping'] = {'recorded': str(original_project),
            'current': str(resolve_environment(str(original_project)))}
        section['logs'] = verify_artifacts(section, directory, log_map(receipt, 'commands'),
                                           'Full application invocation logs')

    run('canonical', qualify_canonical)
    run('live_native', qualify_live)
    run('studio_bundle', qualify_studio)
    run('companion_host', qualify_host)
    run('companion_vendor', qualify_vendor)
    terminal_path = companion_evidence / 'terminal-integration/receipt.json'
    if terminal_path.is_file():
        run('terminal', qualify_terminal, required=False)
    else:
        report['sections']['terminal'] = {'required': False, 'available': False,
            'passed': None, 'status': 'not_available', 'issues': [],
            'scope': 'No terminal qualification was claimed because its receipt is absent.'}
    loopback = companion_evidence / 'terminal-integration/loopback'
    if (loopback / 'receipt.json').is_file():
        run('terminal_loopback', lambda section: qualify_terminal(section, loopback), required=False)
    supplemental = companion_evidence / 'terminal-integration/supplemental'
    if (supplemental / 'receipt.json').is_file():
        attempt = load(supplemental / 'receipt.json')
        interpretation = load(supplemental / 'interpretation.json')
        report['blocked_supplemental_attempt'] = {
            'receipt': str(supplemental / 'receipt.json'),
            'status': interpretation.get('status'), 'reason': interpretation.get('reason'),
            'selected_suites': attempt.get('tests'), 'recorded_passed_tests': attempt.get('passed_tests'),
            'original_qualified': attempt.get('qualified'),
            'included_in_qualified_test_count': False,
            'note': 'A blocked attempt is retained as a limitation, not treated as a passing qualification.'}
    application_receipt = (args.companion_kernel_receipt or
                           companion_evidence / 'full-app-build/receipt.json').resolve()
    if args.companion_kernel_receipt or application_receipt.is_file():
        run('companion_application_kernel', lambda section:
            qualify_companion_kernel(section, application_receipt), required=False)
    report['quds_head_after'] = git_text(source, 'rev-parse', 'HEAD')
    report['companion_head_after'] = git_text(companion, 'rev-parse', 'HEAD') if companion.is_dir() else None
    require(report, report['quds_head_after'] == source_head and
            report['companion_head_after'] == companion_head, 'Repository HEAD advanced during verification')
    report['all_available_sections_verified'] = all(
        item.get('passed') is True for item in report['sections'].values() if item.get('available'))
    report['missing_optional_sections'] = [name for name, item in report['sections'].items()
        if not item['required'] and not item.get('available')]
    report['passed'] = not report['issues'] and all(
        item.get('passed') is True or (not item['required'] and item.get('passed') is None)
        for item in report['sections'].values())
    report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(encoded(report))
    print(json.dumps({'passed': report['passed'], 'quds_head': source_head,
        'companion_head': companion_head, 'sections': {name: item.get('passed')
        for name, item in report['sections'].items()}, 'receipt': str(output)}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
