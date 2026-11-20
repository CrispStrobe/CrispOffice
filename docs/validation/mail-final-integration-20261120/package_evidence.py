#!/usr/bin/env python3
"""Package sealed c623 Mail evidence without tests, product edits or Git mutations."""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    repo, runtime, destination = [p.resolve() for p in (args.repo, args.runtime_root, args.destination)]
    initial = runtime / 'mail-final-union-qualification'
    continued = runtime / 'mail-final-union-continuation'
    accepted = runtime / 'mail-final-union-accepted'
    toolchain = runtime / 'flutter-toolchain'
    receipt = json.loads((accepted / 'qualification.json').read_text())
    assert receipt['status'] == 'passed' and receipt['accepted_passed'] == 1161
    assert receipt['accepted_suites'] == 52 and receipt['additional_platform_rechecks'] == 218
    members = {}

    def add(name, source):
        assert name not in members, name
        members[name] = Path(source).read_bytes()

    def add_flat(label, directory):
        for path in sorted(directory.iterdir()):
            if path.is_file() and path.suffix in {'.json', '.jsonl', '.log', '.stderr', '.py', '.patch'}:
                add(label + '/' + path.name, path)

    add_flat('initial', initial)
    add_flat('continuation', continued)
    add_flat('accepted', accepted)
    for path in sorted((continued / 'screenshots').rglob('*')):
        if path.is_file() and path.suffix in {'.png', '.json'}:
            add('continuation/' + str(path.relative_to(continued)), path)
    for name in ['mail-final-union-run.log', 'mail-final-union-continuation.log',
                 'mail-final-union-verification.log', 'quds-delivery-runtime-mapping.json',
                 'quds-delivery-native-assets.json']:
        add('execution-diagnostics/' + name, runtime / name)
    add('review/studio-visual-review.json', runtime / 'delivery-mail-studio-visual-review.json')
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
    sealed = json.loads((continued / 'runtime-after.json').read_text())
    for name in ['package_config.json', 'package_graph.json', 'native_assets.yaml']:
        path = repo / '.dart_tool' / name
        key = 'quds_delivery/.dart_tool/' + name
        assert sha(path.read_bytes()) == sealed[key]['sha256']
        add('runtime-provenance/configuration/' + name, path)
    for name in ['pubspec.yaml', 'pubspec.lock']:
        add('runtime-provenance/configuration/' + name, repo / name)
    native_outputs = list((repo / '.dart_tool/hooks_runner/sqlite3').glob('*/output.json'))
    assert native_outputs, 'Actual Flutter SQLite hook output is required.'
    for path in native_outputs:
        add('runtime-provenance/sqlite-hook/' + path.parent.name + '-output.json', path)
    library = repo / '.dart_tool/hooks_runner/shared/sqlite3/build/download-0a658527/libsqlite3.so'
    assert sha(library.read_bytes()) == '0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b'
    members['runtime-provenance/sqlite-hook/library-hash.json'] = encoded({
        'sha256': sha(library.read_bytes()), 'bytes': library.stat().st_size,
        'binary_excluded': True, 'source': 'Actual Flutter sqlite3 3.9.1 build-hook output'})
    previous = repo / 'docs/validation/mail-bulk-reconciliation-20261120'
    for name in ['accepted-test-cases.json', 'accepted-union.json', 'archive-manifest.json']:
        add('historical/' + name, previous / name)
    # Preserve earlier development failures as history; they are not c623 test outcomes.
    add_flat('historical-development', runtime / 'mail-reconciliation-development')
    exports = {
        'qualification.json': accepted / 'qualification.json',
        'accepted-test-cases.json': accepted / 'accepted-test-cases.json',
        'platform-recheck-cases.json': accepted / 'platform-recheck-cases.json',
        'historical-overlap.json': accepted / 'historical-overlap.json',
        'source-git-verification.json': accepted / 'source-git-verification.json',
        'interruption-seal.json': initial / 'interruption-seal.json',
        'continuation-qualification.json': continued / 'qualification.json',
        'screenshots.json': continued / 'screenshots.json',
        'visual-review.json': accepted / 'visual-review.json',
        'incoming-heads.json': accepted / 'incoming-heads.json',
        'qualify_mail_final_union.py': initial / 'qualification-runner.py',
        'verify_mail_final_union.py': runtime / 'verify_mail_final_union.py',
        'reproduce_flutter_runtime.py': runtime / 'reproduce_flutter_runtime.py',
        'package_evidence.py': Path(__file__),
    }
    for name, source in exports.items():
        data = source.read_bytes()
        if name.endswith('.py'):
            compile(data, name, 'exec')
            members['reproduction/' + name] = data
        (destination / name).write_bytes(data)
    add('review/README.md', destination / 'README.md')
    member_manifest = {name: {'sha256': sha(data), 'bytes': len(data)} for name, data in sorted(members.items())}
    members['MANIFEST.json'] = encoded({'source_head': receipt['source_head'],
        'source_tree': receipt['source_tree'], 'members': member_manifest})

    def build():
        output = io.BytesIO()
        with lzma.LZMAFile(output, 'wb', format=lzma.FORMAT_XZ, preset=9) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
                for name, data in sorted(members.items()):
                    info = tarfile.TarInfo(name)
                    info.size, info.mode, info.mtime = len(data), 0o644, 0
                    info.uid = info.gid = 0
                    info.uname = info.gname = ''
                    archive.addfile(info, io.BytesIO(data))
        return output.getvalue()

    data = build()
    assert data == build()
    archive_name = 'mail-final-qualification.tar.xz'
    (destination / archive_name).write_bytes(data)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as archive:
        assert [row.name for row in archive.getmembers()] == sorted(members)
        for row in archive.getmembers():
            assert row.isfile() and row.mtime == row.uid == row.gid == 0
            assert row.mode == 0o644 and row.uname == row.gname == ''
            assert archive.extractfile(row).read() == members[row.name]
    readable = [destination / name for name in ['README.md', *exports]]
    manifest = {'schema_version': 1, 'source_head': receipt['source_head'], 'source_tree': receipt['source_tree'],
        'accepted_cases': 1161, 'accepted_suites': 52, 'additional_platform_rechecks': 218,
        'original_aggregate_passed': False, 'continuation_passed': True,
        'archive': {'name': archive_name, 'sha256': sha(data), 'bytes': len(data),
            'member_count': len(members), 'uncompressed_member_bytes': sum(map(len, members.values())),
            'deterministic_rebuild_equal': True, 'all_member_contents_verified': True,
            'tar_mtime': 0, 'tar_uid': 0, 'tar_gid': 0, 'tar_mode': '0644'},
        'excluded': ['SDK binaries', 'Pub/cache directories', 'compiled kernels', 'native libraries',
            'JavaScript build outputs', 'temporary test directories'],
        'members': {name: {'sha256': sha(content), 'bytes': len(content)} for name, content in sorted(members.items())},
        'readable_exports': {path.name: {'sha256': sha(path.read_bytes()), 'bytes': path.stat().st_size} for path in sorted(readable)}}
    (destination / 'archive-manifest.json').write_bytes(encoded(manifest))
    checksummed = sorted([*readable, destination / archive_name, destination / 'archive-manifest.json'])
    (destination / 'SHA256SUMS').write_text(''.join(sha(path.read_bytes()) + '  ' + path.name + '\n' for path in checksummed))
    print(json.dumps({'archive': archive_name, 'sha256': sha(data), 'archive_bytes': len(data),
        'member_count': len(members), 'total_folder_bytes': sum(path.stat().st_size for path in destination.iterdir() if path.is_file()),
        'files': {path.name: path.stat().st_size for path in sorted(destination.iterdir()) if path.is_file()}}, indent=2))


if __name__ == '__main__':
    main()
