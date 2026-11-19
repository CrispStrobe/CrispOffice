#!/usr/bin/env python3
"""Package frozen validation evidence without modifying or rerunning its gates.

Only Python's standard library is used. Original JSON/log bytes are retained;
the path map resolves their scratch paths after publication. Gzip has no source
filename and an mtime of zero. Generated runtime bundles are represented only
by hashes. A caller-supplied acceptance-summary hash pins the freeze boundary.

Examples:
  python3 package_layout_evidence.py --source /scratch/validation/layout-theme \
    --repository /scratch/crispoffice --destination docs/validation/run/local-acceptance \
    --acceptance-sha256 SHA256
  python3 package_layout_evidence.py --verify /checkout/docs/validation/run/local-acceptance
"""

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import shutil
import tempfile


SCHEMA = 1
GENERATOR = 'package_layout_evidence.py'
SCRIPT_TYPES = {'.py', '.sh'}
EVIDENCE_TYPES = {'.json', '.log', '.txt', '.diff', '.dart'}
LOG_THRESHOLD = 16 * 1024
JSON_THRESHOLD = 64 * 1024


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode('utf-8')


def file_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def deterministic_gzip(data):
    buffer = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', compresslevel=9,
                       fileobj=buffer, mtime=0) as stream:
        stream.write(data)
    return buffer.getvalue()


def contained(root, relative):
    path = root / relative
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Path escapes package: {relative}')
    return path


def inventory(source):
    result = {}
    for path in sorted(source.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Symlink is not evidence: {path}')
        if path.is_file():
            result[path] = (path.stat().st_size, file_hash(path))
    return result


def omission(path, source):
    relative = path.relative_to(source)
    if 'incoming-runtime' in relative.parts:
        return 'Generated incoming JS/maps and derivative bundles; hashes only.'
    if '__pycache__' in relative.parts or path.suffix == '.pyc':
        return 'Python bytecode cache; original scripts are included.'
    if path.suffix == '.index':
        return 'Temporary Git index; retain hash plus resolved tree/blob proof and candidate source.'
    if path.suffix not in SCRIPT_TYPES | EVIDENCE_TYPES:
        return 'Outside receipt, log, source-manifest and runner-script scope.'
    return None


def should_compress(path, size):
    if path.name == 'acceptance-summary.json':
        return False
    return (
        (path.suffix == '.json' and '.source-' in path.name)
        or (path.suffix == '.json' and size >= JSON_THRESHOLD)
        or (path.suffix == '.dart' and size >= JSON_THRESHOLD)
        or (path.suffix in {'.log', '.txt', '.diff'} and size >= LOG_THRESHOLD)
    )


def verify_package(destination):
    manifest = json.loads((destination / 'manifest.json').read_text())
    if manifest.get('schema_version') != SCHEMA or manifest.get('generator') != GENERATOR:
        raise ValueError('Not a recognized evidence package')
    for entry in manifest['files']:
        path = contained(destination, entry['path'])
        stored = path.read_bytes()
        if len(stored) != entry['stored_bytes'] or sha256(stored) != entry['stored_sha256']:
            raise ValueError(f'Stored content mismatch: {path}')
        raw = gzip.decompress(stored) if entry['encoding'] == 'gzip' else stored
        if len(raw) != entry['raw_bytes'] or sha256(raw) != entry['raw_sha256']:
            raise ValueError(f'Original content mismatch: {path}')
        if entry['encoding'] == 'gzip' and deterministic_gzip(raw) != stored:
            raise ValueError(f'Non-deterministic gzip metadata: {path}')
    path_map = (destination / 'path-map.json').read_bytes()
    if sha256(path_map) != manifest['path_map_sha256']:
        raise ValueError('Path-map content mismatch')
    expected = {entry['path'] for entry in manifest['files']}
    expected.update({'manifest.json', 'path-map.json'})
    actual = {str(path.relative_to(destination)) for path in destination.rglob('*') if path.is_file()}
    if actual != expected:
        raise ValueError(f'Unexpected/missing package paths: {sorted(actual ^ expected)}')
    return manifest


def package(args):
    source = Path(args.source).resolve()
    repository = Path(args.repository).resolve()
    destination = (repository / args.destination).resolve()
    if not destination.is_relative_to(repository):
        raise ValueError('Destination must be inside the requested repository')
    if destination == repository or destination.is_relative_to(source):
        raise ValueError('Destination must be a dedicated directory outside the source tree')
    repo_destination = destination.relative_to(repository).as_posix()
    summary = source / 'acceptance-summary.json'
    if file_hash(summary) != args.acceptance_sha256:
        raise ValueError('Acceptance summary does not match the caller-pinned freeze')
    json.loads(summary.read_text())
    before = inventory(source)
    payloads = {}
    files = []
    exact = {}
    excluded = []
    originals = {}

    def add(path, relative):
        path = path.resolve()
        raw = path.read_bytes()
        encoding = 'gzip' if should_compress(path, len(raw)) else 'identity'
        stored = deterministic_gzip(raw) if encoding == 'gzip' else raw
        relative = relative + ('.gz' if encoding == 'gzip' else '')
        if relative in payloads:
            raise ValueError(f'Duplicate output path: {relative}')
        payloads[relative] = stored
        originals[path] = sha256(raw)
        files.append({
            'path': relative, 'encoding': encoding,
            'raw_bytes': len(raw), 'raw_sha256': sha256(raw),
            'stored_bytes': len(stored), 'stored_sha256': sha256(stored),
        })
        exact[str(path)] = {
            'repository_path': f'{repo_destination}/{relative}',
            'encoding': encoding,
        }

    for path, (size, digest) in before.items():
        reason = omission(path, source)
        if reason:
            excluded.append({'original_path': str(path), 'raw_bytes': size,
                             'raw_sha256': digest, 'reason': reason})
            continue
        folder = 'harness' if path.suffix in SCRIPT_TYPES else 'evidence'
        relative = 'acceptance-summary.json' if path == summary else f'{folder}/{path.relative_to(source).as_posix()}'
        add(path, relative)

    add(Path(__file__), f'harness/{GENERATOR}')
    runtime = source.parent.parent / 'toolchain'
    for name in ['run_dart.sh', 'run_flutter.sh', 'env.sh', 'runtime.json']:
        path = runtime / name
        if path.is_file():
            add(path, f'runtime/{name}')

    runtime_hashes = {}
    for path in before:
        if path.suffix != '.json' or omission(path, source):
            continue
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            continue
        for field in ['runtime_source_sha256', 'compiled_artifact_sha256']:
            values = value.get(field, {})
            if isinstance(values, dict):
                for original, digest in values.items():
                    if original not in exact:
                        runtime_hashes.setdefault(original, set()).add(digest)

    # The preview test is deliberately removed after capture. Resolve its last
    # accepted path to the retained, byte-identical harness rather than to a
    # missing test file. Earlier snapshot hashes remain available unchanged.
    historical_harnesses = []
    for preview_receipt in sorted(source.glob('*images*.json')):
        preview = json.loads(preview_receipt.read_text())
        if not isinstance(preview, dict) or not {'harness', 'harness_sha256'} <= preview.keys():
            continue
        harness = repository / preview['harness']
        if not harness.is_file():
            continue
        harness_digest = file_hash(harness)
        originals[harness] = harness_digest
        if harness_digest != preview['harness_sha256']:
            historical_harnesses.append({
                'receipt': str(preview_receipt),
                'harness': preview['harness'],
                'recorded_sha256': preview['harness_sha256'],
                'current_sha256': harness_digest,
                'note': 'Historical receipt retained unchanged; do not substitute current harness bytes for its recorded version.',
            })
            continue
        for path in before:
            if path.suffix != '.json' or '.source-' not in path.name:
                continue
            snapshot = json.loads(path.read_text())
            for original, digest in snapshot.items():
                if original.endswith('/_layout_theme_previews_test.dart') and digest == harness_digest:
                    exact[str(repository / original)] = {
                        'repository_path': harness.relative_to(repository).as_posix(),
                        'encoding': 'identity', 'raw_sha256': harness_digest,
                        'note': 'Byte-identical retained copy of the removed preview harness; applies to matching source hashes.',
                    }

    path_map = {
        'schema_version': SCHEMA,
        'instructions': [
            'Raw receipt contents retain their original paths and hashes.',
            'Use exact first; gzip entries must be decompressed before checking raw hashes.',
            'Then consult hash-only runtime/omitted references; these dependencies are not copied.',
            'Remaining repository source paths resolve by the repository prefix mapping.',
        ],
        'exact': exact,
        'prefixes': [{'original_prefix': str(repository) + '/', 'repository_prefix': ''}],
        'hash_only_runtime_references': {
            path: sorted(digests) for path, digests in sorted(runtime_hashes.items())
        },
        'omitted_generated_or_out_of_scope': excluded,
        'historical_harness_references': historical_harnesses,
    }
    path_map_bytes = json_bytes(path_map)
    files.sort(key=lambda entry: entry['path'])
    manifest = {
        'schema_version': SCHEMA, 'generator': GENERATOR,
        'original_source_directory': str(source),
        'repository_destination': repo_destination,
        'acceptance_summary_raw_sha256': args.acceptance_sha256,
        'source_inventory_sha256': sha256(json_bytes({
            path.relative_to(source).as_posix(): digest
            for path, (_, digest) in before.items()
        })),
        'preservation': 'All supported artifacts are retained, including failed and superseded attempts. Packaging does not promote runs to accepted status.',
        'compression': {'format': 'gzip', 'level': 9, 'mtime': 0, 'filename': '',
                        'source_snapshots': 'always', 'large_json_threshold': JSON_THRESHOLD,
                        'large_dart_snapshot_threshold': JSON_THRESHOLD,
                        'large_log_threshold': LOG_THRESHOLD},
        'path_map': 'path-map.json', 'path_map_sha256': sha256(path_map_bytes),
        'totals': {'files': len(files), 'gzip_files': sum(entry['encoding'] == 'gzip' for entry in files),
                   'raw_bytes': sum(entry['raw_bytes'] for entry in files),
                   'stored_bytes': sum(entry['stored_bytes'] for entry in files),
                   'hash_only_artifacts': len(excluded)},
        'files': files,
    }
    payloads['path-map.json'] = path_map_bytes
    payloads['manifest.json'] = json_bytes(manifest)
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='evidence-stage-', dir=destination.parent))
    try:
        for relative, data in sorted(payloads.items()):
            target = contained(stage, relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        verify_package(stage)
        if inventory(source) != before or any(file_hash(path) != digest for path, digest in originals.items()):
            raise ValueError('Evidence changed during packaging; obtain a new freeze')
        if destination.exists():
            verify_package(destination)
            if (destination / 'manifest.json').read_bytes() == payloads['manifest.json']:
                return manifest
            if not args.replace:
                raise ValueError('Existing package differs; use --replace only after reviewing the new freeze')
            backup = Path(tempfile.mkdtemp(prefix='evidence-backup-', dir=destination.parent))
            backup.rmdir()
            destination.rename(backup)
            try:
                stage.rename(destination)
            except BaseException:
                backup.rename(destination)
                raise
            shutil.rmtree(backup)
        else:
            stage.rename(destination)
        return manifest
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', help='Verify an already packaged directory only')
    parser.add_argument('--source')
    parser.add_argument('--repository')
    parser.add_argument('--destination')
    parser.add_argument('--acceptance-sha256')
    parser.add_argument('--replace', action='store_true')
    args = parser.parse_args()
    if args.verify:
        manifest = verify_package(Path(args.verify).resolve())
    else:
        for field in ['source', 'repository', 'destination', 'acceptance_sha256']:
            if not getattr(args, field):
                parser.error(f'--{field.replace("_", "-")} is required for packaging')
        manifest = package(args)
    print(json.dumps({'verified': True, 'destination': manifest['repository_destination'],
                      **manifest['totals']}, sort_keys=True))


if __name__ == '__main__':
    main()
