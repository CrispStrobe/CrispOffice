#!/usr/bin/env python3
"""Restore the preserved locked canonical workspace without editing source."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shlex
import subprocess
import time
import yaml

BASE = Path(__file__).resolve().parent
REPO = BASE.parent / 'quds_office_suite'
SDK = BASE / 'flutter-sdk'
CACHE = SDK.parent / 'pub-cache'
WORKSPACE = BASE / 'quds'
LOCK_PATH = 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
LOCK_SHA = '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
EXPECTED = {
    'bin/cache/dart-sdk/bin/dart': '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',
    'bin/cache/artifacts/engine/linux-x64/flutter_tester': '800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-ref', required=True)
    args = parser.parse_args()
    source_commit = git('rev-parse', args.source_ref).decode().strip()
    assert not WORKSPACE.exists(), f'Refuse to replace existing workspace: {WORKSPACE}'
    for relative, expected in EXPECTED.items():
        assert sha((SDK / relative).read_bytes()) == expected, relative
    assert subprocess.check_output(['git', '-C', str(SDK), 'rev-parse', 'HEAD'], text=True).strip() == '737ba8f885dc774b53b442759999a312c9461e4e'
    assert subprocess.check_output(['git', '-C', str(SDK), 'status', '--porcelain', '--untracked-files=no'], text=True) == ''
    manifest = git('show', source_commit + ':pubspec.yaml')
    members = yaml.safe_load(manifest)['workspace']
    lock = git('show', source_commit + ':' + LOCK_PATH)
    assert sha(lock) == LOCK_SHA
    for name in ['logs', 'receipts', 'bin', 'tmp', 'config']:
        (BASE / name).mkdir(parents=True, exist_ok=True)
    WORKSPACE.mkdir()
    manifests = {}
    for relative in ['pubspec.yaml', 'analysis_options.yaml'] + [name + '/pubspec.yaml' for name in members]:
        data = git('show', source_commit + ':' + relative)
        target = WORKSPACE / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifests[relative] = sha(data)
    (WORKSPACE / 'pubspec.lock').write_bytes(lock)
    excluded = {'.dart_tool', 'build', '.git', 'pubspec.lock', 'pubspec.yaml', 'pubspec_overrides.yaml'}
    links = []
    for relative in members:
        children = git('ls-tree', '-z', source_commit + ':' + relative).split(b'\0')
        for row in children:
            if not row:
                continue
            metadata, encoded_name = row.split(b'\t', 1)
            name = encoded_name.decode()
            if name in excluded or relative + '/' + name in members:
                continue
            target = WORKSPACE / relative / name
            source = REPO / relative / name
            target.symlink_to(source, target_is_directory=metadata.startswith(b'040000'))
            links.append({'path': str(target.relative_to(WORKSPACE)), 'source': str(source)})
    env_values = {
        'FLUTTER_ROOT': str(SDK), 'PUB_CACHE': str(CACHE), 'TMPDIR': str(BASE / 'tmp'),
        'XDG_CONFIG_HOME': str(BASE / 'config'), 'CI': 'true',
        'DART_SUPPRESS_ANALYTICS': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    }
    (BASE / 'env.sh').write_text('\n'.join('export ' + key + '=' + shlex.quote(value) for key, value in env_values.items()) + '\nexport PATH=' + shlex.quote(str(BASE / 'bin')) + ':"$PATH"\n')
    dart = SDK / 'bin/cache/dart-sdk/bin/dart'
    snapshot = SDK / 'bin/cache/flutter_tools.snapshot'
    for name, command in [('dart', [str(dart)]), ('flutter', [str(dart), str(snapshot)])]:
        launcher = BASE / 'bin' / name
        launcher.write_text('#!/bin/sh\nexec ' + shlex.join(command) + ' "$@"\n')
        launcher.chmod(0o755)
    runtime_files = list(EXPECTED) + ['bin/cache/flutter_tools.snapshot', 'packages/flutter_tools/pubspec.lock', 'bin/cache/flutter_tools.stamp']
    runtime_hashes = {name: sha((SDK / name).read_bytes()) for name in runtime_files}
    receipt = {
        'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'prepared', 'source_manifest_commit': source_commit,
        'source_checkout_head_at_setup': git('rev-parse', 'HEAD').decode().strip(),
        'source_checkout_may_advance_before_qualification': True,
        'workspace': str(WORKSPACE), 'workspace_members': members,
        'manifest_sha256': manifests, 'links': links, 'lock_source': LOCK_PATH,
        'lock_sha256_before': LOCK_SHA, 'runtime_sha256_before': runtime_hashes,
        'environment': env_values, 'dependency_constraints_modified': False,
        'production_files_modified': False, 'tests_run': False,
        'snapshot_note': 'Locally generated official Flutter tool snapshot is recorded with its actual hash; no byte identity with historical generated snapshots is claimed.',
        'reproduction_inputs': ['docs/validation/zotero-landing-20261117/runtime-setup.tar.gz:validation-runtime/prepare-canonical-workspace.py', 'docs/validation/zotero-landing-20261117/runtime-setup.tar.gz:validation-runtime/resolve-canonical-workspace.py'],
        'setup_script_sha256': sha(Path(__file__).read_bytes()), 'commands': [],
    }
    receipt_path = BASE / 'receipts/canonical-workspace-setup.json'

    def save():
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    env = dict(os.environ, **env_values)
    env['PATH'] = str(BASE / 'bin') + ':' + env['PATH']
    for label, command in [
        ('flutter-version', [str(dart), str(snapshot), '--version', '--machine']),
        ('canonical-pub-get', [str(dart), str(snapshot), 'pub', 'get', '--offline', '--enforce-lockfile']),
    ]:
        output = BASE / 'logs' / (label + '.log')
        record = {'label': label, 'command': command, 'cwd': str(WORKSPACE), 'status': 'running', 'log': str(output)}
        receipt['commands'].append(record)
        save()
        print(json.dumps({'starting': label}), flush=True)
        started = time.monotonic()
        with output.open('wb') as stream:
            process = subprocess.Popen(command, cwd=WORKSPACE, env=env, stdout=stream, stderr=subprocess.STDOUT)
            while process.poll() is None:
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    print(json.dumps({'running': label, 'elapsed_seconds': round(time.monotonic() - started)}), flush=True)
                if time.monotonic() - started > 600:
                    process.terminate()
                    process.wait(timeout=10)
                    raise RuntimeError('Resolver exceeded 600 seconds')
        record.update(exit_code=process.returncode, elapsed_seconds=round(time.monotonic() - started, 3), log_sha256=sha(output.read_bytes()), status='passed' if process.returncode == 0 else 'failed')
        save()
        if process.returncode:
            receipt['status'] = 'failed'
            save()
            raise RuntimeError(output.read_text())
    assert sha((WORKSPACE / 'pubspec.lock').read_bytes()) == LOCK_SHA
    graph_path = WORKSPACE / '.dart_tool/package_config.json'
    graph = json.loads(graph_path.read_text())
    assert graph['flutterVersion'] == '3.47.8'
    assert graph['flutterRoot'] == SDK.as_uri()
    assert all(sha((WORKSPACE / name).read_bytes()) == value for name, value in manifests.items())
    runtime_after = {name: sha((SDK / name).read_bytes()) for name in runtime_files}
    assert runtime_hashes == runtime_after
    receipt.update(status='ready_for_source_freeze', package_count=len(graph['packages']), package_config_sha256=sha(graph_path.read_bytes()), lock_sha256_after=sha((WORKSPACE / 'pubspec.lock').read_bytes()), manifest_inputs_unchanged=True, runtime_sha256_after=runtime_after, finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    save()
    print(json.dumps({'status': receipt['status'], 'package_count': receipt['package_count'], 'receipt': str(receipt_path)}), flush=True)


if __name__ == '__main__':
    main()
