#!/usr/bin/env python3
"""Check release evidence archives against manifests and original run files."""
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
import gzip
import hashlib
import io
import json
import tarfile

root = Path('/workspace/scratch/0a420ffd2846')
repo = root / 'quds_office_suite'
delivery = repo / 'docs/validation/zotero-annotations-20261119'
review = root / 'annotation-review'
qualification = root / 'annotation-qualification-ff06'
diagnostics = root / 'annotation-diagnostics/ui'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def check_archive(directory, originals, count):
    manifest_bytes = (directory / 'archive.json').read_bytes()
    manifest = json.loads(manifest_bytes)
    filename = manifest['file']
    require(Path(filename).name == filename, 'Unsafe archive filename')
    data = (directory / filename).read_bytes()
    require(len(data) == manifest['bytes'], filename + ': byte count differs')
    require(sha(data) == manifest['sha256'], filename + ': archive hash differs')
    expected = {}
    for item in manifest['members']:
        name = item['path']
        require(name not in expected, filename + ': duplicate manifest member')
        expected[name] = item
    original_names = {entry.name for entry in originals.iterdir()}
    require(all(entry.is_file() and not entry.is_symlink() for entry in originals.iterdir()),
            filename + ': unexpected original directory/link')
    require(set(expected) == original_names, filename + ': original/manifest set mismatch')
    require(len(expected) == count, filename + ': unexpected member count')
    uncompressed = gzip.decompress(data)
    contents = {}
    final_offset = 0
    with tarfile.open(fileobj=io.BytesIO(uncompressed), mode='r:') as bundle:
        members = bundle.getmembers()
        require(len(members) == count, filename + ': tar member count differs')
        for member in members:
            name = member.name
            path = PurePosixPath(name)
            require(not path.is_absolute() and '..' not in path.parts and '.' not in path.parts
                    and str(path) == name and '\\' not in name,
                    filename + ': unsafe or noncanonical tar path')
            require(member.isfile() and member.sparse is None and not member.linkname,
                    filename + ': nonregular/sparse/link entry')
            require(name in expected and name not in contents,
                    filename + ': extra or duplicate tar member')
            payload = bundle.extractfile(member).read()
            item = expected[name]
            require(len(payload) == member.size == item['bytes'], filename + ': member size differs: ' + name)
            require(sha(payload) == item['sha256'], filename + ': member hash differs: ' + name)
            require(payload == (originals / name).read_bytes(), filename + ': member differs from original: ' + name)
            contents[name] = payload
            final_offset = max(final_offset, member.offset_data + (member.size + 511) // 512 * 512)
    require(set(contents) == set(expected), filename + ': missing tar member')
    trailing = uncompressed[final_offset:]
    require(len(trailing) >= 1024 and not any(trailing),
            filename + ': nonzero/unexpected data after final member or missing terminator')
    return {
        'file': filename, 'archive_sha256': sha(data), 'archive_bytes': len(data),
        'manifest_sha256': sha(manifest_bytes), 'members': len(contents),
        'exact_original_file_set': True, 'no_unsafe_extra_missing_duplicate_entries': True,
        'regular_files_only': True, 'member_bytes_and_hashes_match_manifest': True,
        'member_bytes_equal_original_files': True, 'trailing_tar_data_is_only_valid_zero_padding': True,
    }, contents

def main():
    final, final_contents = check_archive(delivery / 'final', qualification, 26)
    development, _ = check_archive(delivery / 'diagnostics', diagnostics, 11)
    summary = json.loads(final_contents['summary.json'])
    require(summary['commit'] == 'ff06e5544673ce7f70be983299241bcdcef780d3', 'Wrong qualification commit')
    gzip_checks = {}
    for gate_name, gate in summary['gates'].items():
        if 'compressed_log' not in gate:
            continue
        name = gate['compressed_log']
        payload = final_contents[name]
        require(sha(payload) == gate['compressed_log_sha256'], name + ': summary compressed hash differs')
        raw = gzip.decompress(payload)
        require(sha(raw) == gate['log_sha256'], name + ': summary raw hash differs')
        require(raw == gzip.decompress((qualification / name).read_bytes()), name + ': decoded original differs')
        gzip_checks[name] = sha(raw)
    for label in ('source-before', 'source-after'):
        name = label + '.json.gz'
        payload = final_contents[name]
        require(sha(payload) == summary[label + '_compressed_sha256'], name + ': snapshot compressed hash differs')
        raw = gzip.decompress(payload)
        require(sha(raw) == summary[label + '_sha256'], name + ': snapshot raw hash differs')
        require(raw == gzip.decompress((qualification / name).read_bytes()), name + ': decoded original differs')
        gzip_checks[name] = sha(raw)
    require(len(gzip_checks) == 8, 'Expected exactly six raw test logs and two source snapshots')
    copies = {}
    for name, original in [
        ('summary.json', qualification / 'summary.json'),
        ('independent-audit.json', review / 'independent-audit.json'),
        ('independent_gate_audit.py', review / 'independent_gate_audit.py'),
    ]:
        copied = (delivery / 'final' / name).read_bytes()
        require(copied == original.read_bytes(), 'Copied artifact differs from original: ' + name)
        copies[name] = sha(copied)
    return {
        'accepted': True, 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_commit': summary['commit'], 'final_results': final,
        'development_diagnostics': development,
        'gzip_original_raw_hashes_verified': gzip_checks,
        'copied_summary_audit_script_match_originals': copies,
        'qualification_and_diagnostic_archives_remain_separate': True,
        'tracked_source_modified_by_audit': False, 'tests_run_by_audit': 0,
    }

try:
    result = main()
except Exception as error:
    result = {'accepted': False, 'error': type(error).__name__ + ': ' + str(error)}
(review / 'archive-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['accepted'] else 1)
