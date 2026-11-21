#!/usr/bin/env python3
"""Package sealed PR277 Mail evidence without tests or Git mutations."""
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
    repo, runtime, destination = [path.resolve() for path in
        (args.repo, args.runtime_root, args.destination)]
    focused = runtime / 'mail-pr277-qualification'
    accepted = runtime / 'mail-pr277-accepted'
    receipt = json.loads((accepted / 'accepted-union.json').read_text())
    assert receipt['status'] == 'passed'
    assert (receipt['accepted_passed'], receipt['accepted_suites'], receipt['platform_recheck_passed']) == (1536, 73, 230)
    destination.mkdir(parents=True, exist_ok=True)
    members = {}

    def add(name, path):
        assert name not in members, name
        members[name] = Path(path).read_bytes()

    def flat(label, directory, suffixes=None):
        suffixes = suffixes or {'.json', '.jsonl', '.log', '.stderr', '.py', '.patch', '.dart'}
        for path in sorted(directory.iterdir()):
            if path.is_file() and path.suffix in suffixes:
                add(label + '/' + path.name, path)

    flat('focused', focused)
    flat('accepted', accepted)
    for path in sorted((focused / 'screenshots').rglob('*.png')):
        add('focused/' + str(path.relative_to(focused)), path)
    for name in ['mail-pr277-qualification.log', 'mail-pr277-retention-verification.log',
                 'pr277-mail-incoming-evidence-audit.log', 'quds-merge-final-runtime-mapping.json',
                 'quds-merge-final-native-assets.json']:
        add('execution-diagnostics/' + name, runtime / name)
    flat('historical-development', runtime / 'mail383-development')
    add('historical-development/original-format.log', runtime / 'mail383-format.log')
    for name in ['pr277-mail-peer-review.json', 'pr277-mail-incoming-evidence-audit.json',
                 'pr277-mail-visual-comparison.json', 'pr277-mail-visual-independent-review.json',
                 'mail383-changed-paths.json']:
        add('review/' + name, runtime / name)
    for name in ['pr277-mail-final-independent-review.json', 'audit_pr277_mail_union.py']:
        add('review/' + name, runtime / name)
    for name in ['accepted-union.json', 'accepted-test-cases.json', 'accepted-platform-recheck-cases.json']:
        add('baseline/accepted/' + name, runtime / 'mail-latest-accepted' / name)
    for name in ['qualification.json', 'source-after.json', 'dependencies-after.json', 'runtime-after.json',
                 'resolved-packages.json', 'hosted-lock-verification.json']:
        add('baseline/sealed/' + name, runtime / 'mail-latest-fixture-qualification' / name)
    old = repo / 'docs/validation/mail-latest-main-integration-20261120'
    for name in ['archive-manifest.json', 'SHA256SUMS']:
        add('baseline/package/' + name, old / name)
    old_manifest = json.loads((old / 'archive-manifest.json').read_text())
    old_archive = old / old_manifest['archive']['name']
    assert digest(old_archive.read_bytes()) == old_manifest['archive']['sha256']
    with tarfile.open(old_archive, 'r:xz') as archive:
        for row in archive.getmembers():
            if row.isfile() and row.name.startswith('runtime-provenance/'):
                data = archive.extractfile(row).read()
                assert digest(data) == old_manifest['members'][row.name]['sha256']
                members[row.name] = data
    sealed = json.loads((focused / 'runtime-after.json').read_text())
    for name in ['package_config.json', 'package_graph.json', 'native_assets.yaml']:
        data = (repo / '.dart_tool' / name).read_bytes()
        assert digest(data) == sealed[repo.name + '/.dart_tool/' + name]['sha256']
        assert data == members['runtime-provenance/configuration/' + name]
    for name in ['pubspec.yaml', 'pubspec.lock']:
        assert (repo / name).read_bytes() == members['runtime-provenance/configuration/' + name]
    exports = {
        'accepted-union.json': accepted / 'accepted-union.json',
        'accepted-test-cases.json': accepted / 'accepted-test-cases.json',
        'platform-recheck-cases.json': accepted / 'accepted-platform-recheck-cases.json',
        'incoming-heads.json': accepted / 'incoming-heads.json',
        'focused-qualification.json': focused / 'qualification.json',
        'source-peer-review.json': runtime / 'pr277-mail-peer-review.json',
        'incoming-evidence-audit.json': runtime / 'pr277-mail-incoming-evidence-audit.json',
        'visual-comparison.json': runtime / 'pr277-mail-visual-comparison.json',
        'visual-review.json': runtime / 'pr277-mail-visual-independent-review.json',
        'qualify_mail_pr277.py': focused / 'qualification-runner.py',
        'verify_mail_pr277_retention.py': runtime / 'verify_mail_pr277_retention.py',
        'audit_pr277_mail_evidence.py': runtime / 'audit_pr277_mail_evidence.py',
        'reproduce_flutter_runtime.py': runtime / 'reproduce_flutter_runtime.py',
        'package_evidence.py': Path(__file__),
    }
    for name, path in exports.items():
        data = path.read_bytes()
        if name.endswith('.py'):
            compile(data, name, 'exec')
            members['reproduction/' + name] = data
        (destination / name).write_bytes(data)
    add('review/README.md', destination / 'README.md')
    members['MANIFEST.json'] = encoded({
        'accepted_source_head': receipt['accepted_source_head'],
        'accepted_source_tree': receipt['accepted_source_tree'],
        'members': {name: {'sha256': digest(data), 'bytes': len(data)} for name, data in sorted(members.items())}})

    def build():
        buffer = io.BytesIO()
        with lzma.LZMAFile(buffer, 'wb', format=lzma.FORMAT_XZ, preset=9) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
                for name, data in sorted(members.items()):
                    row = tarfile.TarInfo(name)
                    row.size, row.mode, row.mtime = len(data), 0o644, 0
                    row.uid = row.gid = 0
                    row.uname = row.gname = ''
                    archive.addfile(row, io.BytesIO(data))
        return buffer.getvalue()

    data = build()
    assert data == build()
    archive_name = 'mail-pr277-qualification.tar.xz'
    (destination / archive_name).write_bytes(data)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as archive:
        assert [row.name for row in archive.getmembers()] == sorted(members)
        for row in archive.getmembers():
            assert row.isfile() and row.mtime == row.uid == row.gid == 0
            assert row.mode == 0o644 and row.uname == row.gname == ''
            assert archive.extractfile(row).read() == members[row.name]
    readable = [destination / name for name in ['README.md', *exports]]
    manifest = {
        'schema_version': 1, 'accepted_source_head': receipt['accepted_source_head'],
        'accepted_source_tree': receipt['accepted_source_tree'],
        'accepted_cases': 1536, 'accepted_suites': 73, 'additional_platform_rechecks': 230,
        'fresh_cases': 411, 'retained_cases': 1125, 'focused_aggregate_passed': True,
        'archive': {'name': archive_name, 'sha256': digest(data), 'bytes': len(data),
            'member_count': len(members), 'uncompressed_member_bytes': sum(map(len, members.values())),
            'deterministic_rebuild_equal': True, 'all_member_contents_verified': True,
            'tar_mtime': 0, 'tar_uid': 0, 'tar_gid': 0, 'tar_mode': '0644'},
        'excluded': ['SDK binaries', 'Pub/cache directories', 'compiled kernels', 'native libraries',
            'JavaScript build outputs', 'temporary test directories'],
        'members': {name: {'sha256': digest(value), 'bytes': len(value)} for name, value in sorted(members.items())},
        'readable_exports': {path.name: {'sha256': digest(path.read_bytes()), 'bytes': path.stat().st_size}
            for path in sorted(readable)}}
    (destination / 'archive-manifest.json').write_bytes(encoded(manifest))
    paths = sorted([*readable, destination / archive_name, destination / 'archive-manifest.json'])
    (destination / 'SHA256SUMS').write_text(''.join(digest(path.read_bytes()) + '  ' + path.name + '\n' for path in paths))
    print(json.dumps({'archive': archive_name, 'sha256': digest(data), 'archive_bytes': len(data),
        'member_count': len(members),
        'total_folder_bytes': sum(path.stat().st_size for path in destination.iterdir() if path.is_file()),
        'files': {path.name: path.stat().st_size for path in sorted(destination.iterdir()) if path.is_file()}}, indent=2))


if __name__ == '__main__':
    main()
