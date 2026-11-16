#!/usr/bin/env python3
"""Run an unchanged backoff widget assertion on isolated, pinned sources."""
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parent
TOOLCHAIN = ROOT.parent
REPO = TOOLCHAIN.parent / 'quds_office_suite'
PRIOR = TOOLCHAIN / 'behavioral-controls'
PACKAGES = ['quds_office_engine', 'quds_office_editor', 'quds_reports', 'legacy_doc_parser']
COMMITS = {
    'before': '357f7a3e87d8536c03ecca2a860a0a564b1659f0',
    'after': '039c1e293052f548367f9ea3b0fa5ff56949ccaa',
}
PATHS = [f'packages/{name}/lib' for name in PACKAGES] + [
    'packages/quds_office_editor/fonts', 'packages/quds_office_editor/templates',
]
TEST = 'word_zotero_backoff_session_test.dart'
CASE = 'reconnecting and reopening keep an online session pause'
DART = TOOLCHAIN / 'flutter-sdk/bin/cache/dart-sdk/bin/dart'
SNAPSHOT = TOOLCHAIN / 'flutter-sdk/bin/cache/flutter_tools.snapshot'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, indent=2) + '\n')


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def dependency_inputs(config_path):
    config = json.loads(config_path.read_text())
    result = {}
    for package in config['packages']:
        if package['name'] in PACKAGES:
            continue
        uri = urljoin(config_path.as_uri(), package['rootUri'])
        parsed = urlparse(uri)
        if parsed.scheme != 'file':
            raise ValueError(f'Nonlocal package input: {package["name"]}')
        folder = Path(unquote(parsed.path))
        paths = sorted(p for p in (folder / 'lib').rglob('*') if p.is_file())
        paths += [p for p in [folder / 'pubspec.yaml', folder / 'pubspec.lock'] if p.exists()]
        result[package['name']] = {
            'root': str(folder),
            'language_version': package.get('languageVersion'),
            'files': {str(p.relative_to(folder)): sha(p) for p in paths},
        }
    return result


def tracked_inputs(folder):
    result = {}
    for name in PACKAGES:
        for relative in [
            'pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
            '.dart_tool/package_graph.json',
        ]:
            path = folder / 'packages' / name / relative
            if path.exists():
                result[str(path.relative_to(folder))] = sha(path)
    test = folder / 'packages/quds_office_editor/test' / TEST
    result[str(test.relative_to(folder))] = sha(test)
    return result


def archived_sources(folder, commit):
    result = {}
    mismatches = []
    entries = git('ls-tree', '-r', '-z', commit, '--', *PATHS).split(b'\0')
    for entry in entries:
        if not entry:
            continue
        header, raw_name = entry.split(b'\t', 1)
        mode, kind, blob = header.decode().split()
        if kind != 'blob':
            raise ValueError(f'Non-blob archive entry: {entry!r}')
        name = raw_name.decode()
        path = folder / name
        data = os.readlink(path).encode() if mode == '120000' else path.read_bytes()
        actual_blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        result[name] = {'git_blob': blob, 'sha256': hashlib.sha256(data).hexdigest()}
        if actual_blob != blob:
            mismatches.append(name)
    if mismatches:
        raise ValueError(f'Archive source mismatches: {mismatches}')
    return result


def setup():
    prior_receipt = json.loads((PRIOR / 'source-receipt.json').read_text())
    shared_config = PRIOR / 'after/packages/quds_office_editor/.dart_tool/package_config.json'
    dependencies = dependency_inputs(shared_config)
    write('dependency-inputs.json', dependencies)
    fixture = git('show', COMMITS['after'] + ':packages/quds_office_editor/test/' + TEST)
    (ROOT / TEST).write_bytes(fixture)
    setup_receipt = {
        'recorded_utc': datetime.now(timezone.utc).isoformat(),
        'repository': 'CrispStrobe/quds_office_suite',
        'commits': COMMITS,
        'test_file': TEST,
        'test_source_commit': COMMITS['after'],
        'test_sha256': sha(ROOT / TEST),
        'case': CASE,
        'prior_control_source_receipt_sha256': sha(PRIOR / 'source-receipt.json'),
        'dependency_inputs_sha256': sha(ROOT / 'dependency-inputs.json'),
        'runtime': {
            'dart_version': subprocess.check_output([str(DART), '--version'], stderr=subprocess.STDOUT).decode().strip(),
            'binaries': {str(path.relative_to(TOOLCHAIN)): sha(path) for path in [
                DART, SNAPSHOT,
                TOOLCHAIN / 'flutter-sdk/bin/cache/artifacts/engine/linux-x64/flutter_tester',
            ]},
        },
        'graphs': {},
    }
    for label, commit in COMMITS.items():
        folder = ROOT / label
        if folder.exists():
            raise FileExistsError(f'Will not overwrite an existing control: {folder}')
        folder.mkdir()
        archive = git('archive', commit, *PATHS)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(folder, filter='data')
        copied_inputs = {}
        for name in PACKAGES:
            original = PRIOR / 'after/packages' / name
            target = folder / 'packages' / name
            prior_package = prior_receipt['graphs']['after']['packages'].get(name)
            if prior_package is not None:
                for filename, expected in [
                    ('pubspec.yaml', prior_package['manifest_sha256']),
                    ('pubspec.lock', prior_package['lockfile_sha256']),
                    ('.dart_tool/package_config.json', prior_package['isolated_config_sha256']),
                ]:
                    assert sha(original / filename) == expected, (name, filename)
            for filename in ['pubspec.yaml', 'pubspec.lock']:
                path = original / filename
                if path.exists():
                    shutil.copyfile(path, target / filename)
                    copied_inputs[str(path)] = sha(path)
            config_path = original / '.dart_tool/package_config.json'
            if config_path.exists():
                config = json.loads(config_path.read_text())
                for package in config['packages']:
                    package['rootUri'] = (
                        (folder / 'packages' / package['name']).as_uri() + '/'
                        if package['name'] in PACKAGES
                        else urljoin(config_path.as_uri(), package['rootUri'])
                    )
                (target / '.dart_tool').mkdir()
                (target / '.dart_tool/package_config.json').write_text(json.dumps(config, indent=2) + '\n')
                copied_inputs[str(config_path)] = sha(config_path)
                graph = original / '.dart_tool/package_graph.json'
                if graph.exists():
                    shutil.copyfile(graph, target / '.dart_tool/package_graph.json')
                    copied_inputs[str(graph)] = sha(graph)
        tests = folder / 'packages/quds_office_editor/test'
        tests.mkdir()
        (tests / TEST).write_bytes(fixture)
        setup_receipt['graphs'][label] = {
            'archive_sha256': hashlib.sha256(archive).hexdigest(),
            'archived_sources': archived_sources(folder, commit),
            'copied_inputs': copied_inputs,
            'isolated_inputs': tracked_inputs(folder),
        }
    write('source-receipt.json', setup_receipt)
    return setup_receipt


def main():
    setup_receipt = setup()
    logs = ROOT / 'logs'
    logs.mkdir(exist_ok=True)
    receipt = {
        'recorded_utc': datetime.now(timezone.utc).isoformat(),
        'source_receipt_sha256': sha(ROOT / 'source-receipt.json'),
        'scope': 'One behavioral before/after control; excluded from final qualification test counts.',
        'canonical_source_or_harness_mutations': False,
        'previous_control_mutations': False,
        'github_actions_queried_awaited_or_rerun': False,
        'runs': [],
    }
    for label, commit in COMMITS.items():
        cwd = ROOT / label / 'packages/quds_office_editor'
        command = [str(DART), str(SNAPSHOT), 'test', '--no-pub', '--reporter', 'expanded',
                   'test/' + TEST, '--plain-name', CASE]
        log = logs / f'backoff-{label}.log'
        started = time.monotonic()
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
        content = log.read_text()
        expected = (
            result.returncode == 1
            and 'has length of <2>' in content
            and 'Expected: an object with length of <1>' in content
            and 'Compilation failed' not in content
            and "Couldn't resolve" not in content
            if label == 'before'
            else result.returncode == 0 and '+1: All tests passed!' in content
        )
        observation = {
            'version': label, 'source_commit': commit, 'command': command, 'cwd': str(cwd),
            'exit_code': result.returncode, 'elapsed_seconds': round(time.monotonic() - started, 3),
            'expected_behavioral_failure': label == 'before',
            'expected_observation_confirmed': expected, 'log': str(log.relative_to(ROOT)),
            'log_sha256': sha(log), 'test_sha256': sha(cwd / 'test' / TEST),
        }
        receipt['runs'].append(observation)
        write('receipt.json', receipt)
        print(json.dumps(observation), flush=True)
    verification = {'graphs': {}, 'common_dependencies_unchanged': False, 'copied_inputs_unchanged': True}
    for label, commit in COMMITS.items():
        current_sources = archived_sources(ROOT / label, commit)
        original = setup_receipt['graphs'][label]
        current_inputs = tracked_inputs(ROOT / label)
        verification['graphs'][label] = {
            'source_files_verified_against_git': len(current_sources),
            'source_hashes_unchanged': current_sources == original['archived_sources'],
            'manifest_lock_config_and_test_hashes_unchanged': current_inputs == original['isolated_inputs'],
        }
        for path, expected in original['copied_inputs'].items():
            if sha(Path(path)) != expected:
                verification['copied_inputs_unchanged'] = False
    old_dependencies = json.loads((ROOT / 'dependency-inputs.json').read_text())
    current_dependencies = dependency_inputs(PRIOR / 'after/packages/quds_office_editor/.dart_tool/package_config.json')
    verification['common_dependencies_unchanged'] = current_dependencies == old_dependencies
    verification['dependency_packages_verified'] = len(current_dependencies)
    verification['dependency_files_verified'] = sum(len(p['files']) for p in current_dependencies.values())
    verification['tests_identical'] = all(run['test_sha256'] == setup_receipt['test_sha256'] for run in receipt['runs'])
    verification['all_checks_passed'] = all([
        verification['common_dependencies_unchanged'], verification['copied_inputs_unchanged'],
        verification['tests_identical'],
        *(g['source_hashes_unchanged'] and g['manifest_lock_config_and_test_hashes_unchanged']
          for g in verification['graphs'].values()),
    ])
    write('verification.json', verification)
    receipt['verification_sha256'] = sha(ROOT / 'verification.json')
    receipt['all_expected_observations_confirmed'] = all(r['expected_observation_confirmed'] for r in receipt['runs'])
    write('receipt.json', receipt)
    print(json.dumps(verification), flush=True)
    if not receipt['all_expected_observations_confirmed'] or not verification['all_checks_passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
