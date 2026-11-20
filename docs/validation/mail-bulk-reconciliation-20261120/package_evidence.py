#!/usr/bin/env python3
"""Package existing sealed Mail receipts; never run tests or modify product files."""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import subprocess
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    repo, runtime, destination = (p.resolve() for p in
                                  [args.repo, args.runtime_root, args.destination])
    original = runtime / 'mail-final-qualification'
    corrective = runtime / 'mail-final-corrected'
    toolchain = runtime / 'flutter-toolchain'
    full = json.loads((original / 'qualification.json').read_text())
    fixed = json.loads((corrective / 'qualification.json').read_text())
    accepted = json.loads((corrective / 'accepted-union.json').read_text())
    assert full['status'] == 'failed' and full['passed'] == 1056
    assert fixed['status'] == 'passed' and fixed['passed'] == 32
    assert accepted['status'] == 'passed' and accepted['accepted_passed'] == 1056
    assert accepted['accepted_suites'] == 50
    source_head = 'cf25a0a3d80ee18d2550161af182bacc4e49d18f'
    assert fixed['source_head'] == source_head
    source_manifest = json.loads((corrective / 'source-after.json').read_text())
    for relative, row in source_manifest.items():
        assert sha((repo / relative).read_bytes()) == row['sha256'], relative

    members = {}

    def add(name, source):
        assert name not in members, name
        members[name] = Path(source).read_bytes()

    def add_flat(label, directory):
        for path in sorted(directory.iterdir()):
            if path.is_file() and path.suffix in {'.json', '.jsonl', '.log', '.stderr', '.py', '.patch'}:
                add(label + '/' + path.name, path)

    add_flat('original-attempt', original)
    for path in sorted((original / 'screenshots').rglob('*')):
        if path.is_file() and path.suffix in {'.png', '.json'}:
            add('original-attempt/' + str(path.relative_to(original)), path)
    add_flat('corrective', corrective)
    add_flat('development', runtime / 'mail-reconciliation-development')
    for name in ['runtime.json', 'pub-cache-receipt.json', 'archive-members.json',
                 'captured-workspace-pubspec.lock', 'env.sh', 'mail-workspace-resolution.json',
                 'mail-workspace-pub-get.log', 'sqlite-readiness.json', 'sqlite-readiness.log',
                 'sqlite_probe.dart']:
        add('runtime-provenance/' + name, toolchain / name)
    for path in sorted((toolchain / 'logs').iterdir()):
        if path.is_file():
            add('runtime-provenance/logs/' + path.name, path)
    for name in ['compile.log', 'runner-receipt.json', 'compile-test-runner.sh']:
        add('runtime-provenance/test-runner/' + name, toolchain / 'test-runner' / name)
    add('runtime-provenance/bootstrap.log', runtime / 'flutter-toolchain-bootstrap.log')
    add('runtime-provenance/bootstrap_flutter_toolchain.executed.py', runtime / 'bootstrap_flutter_toolchain.py')
    add('runtime-provenance/flutter-tools-pubspec.lock', toolchain / 'flutter/packages/flutter_tools/pubspec.lock')

    sealed_runtime = json.loads((corrective / 'runtime-after.json').read_text())
    for relative in ['.dart_tool/package_config.json', '.dart_tool/package_graph.json', '.dart_tool/native_assets.yaml']:
        path = repo / relative
        matching = [row for key, row in sealed_runtime.items() if key.endswith('quds_mail_integration/' + relative)]
        assert len(matching) == 1 and sha(path.read_bytes()) == matching[0]['sha256']
        add('runtime-provenance/configuration/' + path.name, path)
    for name in ['pubspec.yaml', 'pubspec.lock']:
        add('runtime-provenance/configuration/' + name, repo / name)

    exports = {
        'qualification.json': corrective / 'qualification.json',
        'original-qualification.json': original / 'qualification.json',
        'accepted-union.json': corrective / 'accepted-union.json',
        'accepted-test-cases.json': corrective / 'accepted-test-cases.json',
        'visual-review.json': original / 'visual-review.json',
        'screenshots.json': original / 'screenshots.json',
        'nonmail-fixture-audit.json': corrective / 'nonmail-fixture-audit.json',
        'qualify_mail_reconciled.py': corrective / 'qualification-runner.py',
        'verify_mail_retention.py': corrective / 'verification-runner.py',
        'audit_mail_word_fixture.py': runtime / 'audit_mail_word_fixture.py',
        'reproduce_flutter_runtime.py': runtime / 'reproduce_flutter_runtime.py',
    }
    for name, source in exports.items():
        content = source.read_bytes()
        if name.endswith('.py'):
            compile(content, name, 'exec')
        (destination / name).write_bytes(content)
        if name.endswith('.py'):
            members['reproduction/' + name] = content

    incoming = {
        'frozen_word_baseline': 'cb5909fefe6dd41db0f9c38207db83166072dcaf',
        'word_evidence': '467dcaffe016b9e647f944b59af473b13e3ae7f6',
        'bulk_actions': '9109fcc645d0d95fbe7a7568ddf1e0ebc07bc384',
        'bulk_flags': 'fcc7bd27f7df6200ac7d3174f6e21097f931cca0',
        'mail_branch_common_ancestor': 'b01cb23dc1b7bc94b691d68a2507b61dc6d48d7a',
        'captured_later_main': 'e975cec13b289fe067ef406cd3044701ecc44744',
        'original_execution': 'cdd98460c2eed261719c660351f11adc962e2ca5',
    }
    ancestry = []
    for name, commit in incoming.items():
        command = ['git', '-C', str(repo), 'merge-base', '--is-ancestor', commit, source_head]
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode == 0, (name, result.stderr)
        ancestry.append({'source': name, 'commit': commit, 'command': command, 'exit_code': result.returncode})
    incoming_record = {'qualified_source_head': source_head, 'qualified_source_tree': fixed['source_tree'],
                       'checks': ancestry, 'github_actions_used': False}
    (destination / 'incoming-heads.json').write_bytes(json_bytes(incoming_record))
    members['review/incoming-heads.json'] = json_bytes(incoming_record)
    add('review/README.md', destination / 'README.md')
    add('reproduction/package_evidence.py', Path(__file__))

    member_manifest = {name: {'sha256': sha(data), 'bytes': len(data)}
                       for name, data in sorted(members.items())}
    members['MANIFEST.json'] = json_bytes({'source_head': source_head,
        'source_tree': fixed['source_tree'], 'members': member_manifest})

    def build_archive():
        output = io.BytesIO()
        with lzma.LZMAFile(output, 'wb', format=lzma.FORMAT_XZ, preset=9) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
                for name, data in sorted(members.items()):
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    info.mtime = 0
                    info.mode = 0o644
                    info.uid = info.gid = 0
                    info.uname = info.gname = ''
                    archive.addfile(info, io.BytesIO(data))
        return output.getvalue()

    archive_bytes = build_archive()
    assert archive_bytes == build_archive(), 'Archive is not deterministic for identical inputs.'
    archive_name = 'mail-bulk-qualification.tar.xz'
    (destination / archive_name).write_bytes(archive_bytes)
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:xz') as archive:
        observed = archive.getmembers()
        assert [entry.name for entry in observed] == sorted(members)
        for entry in observed:
            assert entry.isfile() and entry.mtime == 0 and entry.uid == entry.gid == 0
            assert entry.mode == 0o644 and not entry.uname and not entry.gname
            assert archive.extractfile(entry).read() == members[entry.name]

    readable = [destination / name for name in [*exports, 'README.md', 'incoming-heads.json', 'package_evidence.py']]
    manifest = {
        'schema_version': 1, 'source_head': source_head, 'source_tree': fixed['source_tree'],
        'accepted_cases': 1056, 'accepted_suites': 50,
        'original_aggregate_status': full['status'], 'corrective_status': fixed['status'],
        'archive': {'name': archive_name, 'sha256': sha(archive_bytes), 'bytes': len(archive_bytes),
            'member_count': len(members), 'uncompressed_member_bytes': sum(map(len, members.values())),
            'deterministic_rebuild_equal': True, 'all_member_contents_verified': True,
            'tar_mtime': 0, 'tar_uid': 0, 'tar_gid': 0, 'tar_mode': '0644'},
        'excluded': ['SDK binaries', 'Pub/cache directories', 'compiled kernels', 'native libraries', 'JavaScript build outputs', 'temporary test directories'],
        'members': {name: {'sha256': sha(data), 'bytes': len(data)} for name, data in sorted(members.items())},
        'readable_exports': {p.name: {'sha256': sha(p.read_bytes()), 'bytes': p.stat().st_size} for p in sorted(readable)},
    }
    (destination / 'archive-manifest.json').write_bytes(json_bytes(manifest))
    checksummed = sorted([*readable, destination / archive_name, destination / 'archive-manifest.json'])
    (destination / 'SHA256SUMS').write_text(''.join(sha(p.read_bytes()) + '  ' + p.name + '\n' for p in checksummed))
    print(json.dumps({'archive': archive_name, 'sha256': sha(archive_bytes), 'archive_bytes': len(archive_bytes),
        'member_count': len(members), 'total_folder_bytes': sum(p.stat().st_size for p in destination.iterdir() if p.is_file()),
        'files': {p.name: p.stat().st_size for p in sorted(destination.iterdir()) if p.is_file()}}, indent=2))


if __name__ == '__main__':
    main()
