#!/usr/bin/env python3
"""Package the sealed latest-main Mail union without tests or Git mutations."""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    repo, runtime, destination = [value.resolve() for value in
        (args.repo, args.runtime_root, args.destination)]
    initial = runtime / 'mail-latest-delta-qualification'
    correction = runtime / 'mail-latest-fixture-qualification'
    accepted = runtime / 'mail-latest-accepted'
    receipt = json.loads((accepted / 'accepted-union.json').read_text())
    assert receipt['status'] == 'passed'
    assert receipt['accepted_passed'] == 1471 and receipt['accepted_suites'] == 70
    assert receipt['platform_recheck_passed'] == 228 and receipt['corrective_passed'] == 171
    destination.mkdir(parents=True, exist_ok=True)
    members = {}

    def add(name, path):
        assert name not in members, name
        members[name] = Path(path).read_bytes()

    def add_flat(label, directory, suffixes=None):
        suffixes = suffixes or {'.json', '.jsonl', '.log', '.stderr', '.py', '.patch', '.dart'}
        for path in sorted(directory.iterdir()):
            if path.is_file() and path.suffix in suffixes:
                add(label + '/' + path.name, path)

    add_flat('initial', initial)
    add_flat('correction', correction)
    add_flat('accepted', accepted)
    for path in sorted((initial / 'screenshots').rglob('*.png')):
        add('initial/' + str(path.relative_to(initial)), path)
    for name in ['mail-latest-delta-qualification.log', 'mail-latest-fixture-qualification.log',
                 'mail-latest-retention-verification.log', 'quds-merge-final-runtime-mapping.json',
                 'quds-merge-final-native-assets.json']:
        add('execution-diagnostics/' + name, runtime / name)
    add_flat('fixture-diagnostics', runtime / 'mail-latest-fixture-diagnostics')
    add_flat('historical-development', runtime / 'mail-latest-development')
    for name in ['late-mail-reader-peer-review.json', 'mail-fixture-followup-review.json',
                 'mail-latest-visual-comparison.json', 'mail-latest-focused-scope.json',
                 'mail-latest-retention-plan.json', 'mail-latest-impact-review.json']:
        add('review/' + name, runtime / name)
    for name in ['qualification.json', 'accepted-test-cases.json', 'platform-recheck-cases.json',
                 'incoming-heads.json', 'visual-review.json']:
        add('baseline/accepted/' + name, runtime / 'mail-final-union-accepted' / name)
    for name in ['source-after.json', 'dependencies-after.json', 'runtime-after.json',
                 'resolved-packages.json', 'hosted-lock-verification.json']:
        add('baseline/sealed/' + name, runtime / 'mail-final-union-continuation' / name)
    old = repo / 'docs/validation/mail-final-integration-20261120'
    for name in ['archive-manifest.json', 'SHA256SUMS']:
        add('baseline/package/' + name, old / name)
    old_manifest = json.loads((old / 'archive-manifest.json').read_text())
    old_archive = old / old_manifest['archive']['name']
    assert digest(old_archive.read_bytes()) == old_manifest['archive']['sha256']
    with tarfile.open(old_archive, 'r:xz') as archive:
        for row in archive.getmembers():
            if row.name.startswith('runtime-provenance/') and row.isfile():
                content = archive.extractfile(row).read()
                assert digest(content) == old_manifest['members'][row.name]['sha256']
                if row.name.startswith('runtime-provenance/configuration/'):
                    name = row.name.replace('runtime-provenance/configuration/', 'baseline/configuration/', 1)
                else:
                    name = row.name
                assert name not in members, name
                members[name] = content
    sealed = json.loads((correction / 'runtime-after.json').read_text())
    for name in ['package_config.json', 'package_graph.json', 'native_assets.yaml']:
        path = repo / '.dart_tool' / name
        assert digest(path.read_bytes()) == sealed[repo.name + '/.dart_tool/' + name]['sha256']
        add('runtime-provenance/configuration/' + name, path)
    for name in ['pubspec.yaml', 'pubspec.lock']:
        add('runtime-provenance/configuration/' + name, repo / name)
    library = repo / '.dart_tool/lib/libsqlite3.so'
    assert digest(library.read_bytes()) == '0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b'
    members['runtime-provenance/current-sqlite-registration.json'] = encoded({
        'sha256': digest(library.read_bytes()), 'bytes': library.stat().st_size,
        'binary_excluded': True,
        'provenance': 'Exact pinned sqlite3 3.9.1 artifact from the c623 qualification, registered in the new worktree.'})
    exports = {
        'accepted-union.json': accepted / 'accepted-union.json',
        'incoming-heads.json': accepted / 'incoming-heads.json',
        'accepted-test-cases.json': accepted / 'accepted-test-cases.json',
        'platform-recheck-cases.json': accepted / 'accepted-platform-recheck-cases.json',
        'initial-qualification.json': initial / 'qualification.json',
        'corrective-qualification.json': correction / 'qualification.json',
        'visual-comparison.json': runtime / 'mail-latest-visual-comparison.json',
        'reader-peer-review.json': runtime / 'late-mail-reader-peer-review.json',
        'fixture-peer-review.json': runtime / 'mail-fixture-followup-review.json',
        'qualify_mail_latest_delta.py': initial / 'qualification-runner.py',
        'verify_mail_latest_retention.py': runtime / 'verify_mail_latest_retention.py',
        'reproduce_flutter_runtime.py': runtime / 'reproduce_flutter_runtime.py',
        'package_evidence.py': Path(__file__),
    }
    for name, path in exports.items():
        content = path.read_bytes()
        if name.endswith('.py'):
            compile(content, name, 'exec')
            members['reproduction/' + name] = content
        (destination / name).write_bytes(content)
    add('review/README.md', destination / 'README.md')
    members['MANIFEST.json'] = encoded({
        'accepted_source_head': receipt['accepted_source_head'],
        'accepted_source_tree': receipt['accepted_source_tree'],
        'members': {name: {'sha256': digest(content), 'bytes': len(content)}
            for name, content in sorted(members.items())}})

    def build():
        target = io.BytesIO()
        with lzma.LZMAFile(target, 'wb', format=lzma.FORMAT_XZ, preset=9) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
                for name, content in sorted(members.items()):
                    row = tarfile.TarInfo(name)
                    row.size, row.mode, row.mtime = len(content), 0o644, 0
                    row.uid = row.gid = 0
                    row.uname = row.gname = ''
                    archive.addfile(row, io.BytesIO(content))
        return target.getvalue()

    content = build()
    assert content == build()
    archive_name = 'mail-latest-qualification.tar.xz'
    (destination / archive_name).write_bytes(content)
    with tarfile.open(fileobj=io.BytesIO(content), mode='r:xz') as archive:
        assert [row.name for row in archive.getmembers()] == sorted(members)
        for row in archive.getmembers():
            assert row.isfile() and row.mtime == row.uid == row.gid == 0
            assert row.mode == 0o644 and row.uname == row.gname == ''
            assert archive.extractfile(row).read() == members[row.name]
    readable = [destination / name for name in ['README.md', *exports]]
    manifest = {
        'schema_version': 1,
        'accepted_source_head': receipt['accepted_source_head'],
        'accepted_source_tree': receipt['accepted_source_tree'],
        'accepted_cases': 1471, 'accepted_suites': 70,
        'additional_platform_rechecks': 228,
        'initial_aggregate_passed': False, 'corrective_aggregate_passed': True,
        'archive': {'name': archive_name, 'sha256': digest(content), 'bytes': len(content),
            'member_count': len(members), 'uncompressed_member_bytes': sum(map(len, members.values())),
            'deterministic_rebuild_equal': True, 'all_member_contents_verified': True,
            'tar_mtime': 0, 'tar_uid': 0, 'tar_gid': 0, 'tar_mode': '0644'},
        'excluded': ['SDK binaries', 'Pub/cache directories', 'compiled kernels', 'native libraries',
            'JavaScript build outputs', 'temporary test directories'],
        'members': {name: {'sha256': digest(data), 'bytes': len(data)} for name, data in sorted(members.items())},
        'readable_exports': {path.name: {'sha256': digest(path.read_bytes()), 'bytes': path.stat().st_size}
            for path in sorted(readable)}}
    (destination / 'archive-manifest.json').write_bytes(encoded(manifest))
    paths = sorted([*readable, destination / archive_name, destination / 'archive-manifest.json'])
    (destination / 'SHA256SUMS').write_text(''.join(digest(path.read_bytes()) + '  ' + path.name + '\n' for path in paths))
    print(json.dumps({'archive': archive_name, 'sha256': digest(content), 'archive_bytes': len(content),
        'member_count': len(members),
        'total_folder_bytes': sum(path.stat().st_size for path in destination.iterdir() if path.is_file()),
        'files': {path.name: path.stat().st_size for path in sorted(destination.iterdir()) if path.is_file()}}, indent=2))


if __name__ == '__main__':
    main()
