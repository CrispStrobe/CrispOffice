#!/usr/bin/env python3
"""Verify recorded file bytes, archive members, and deterministic archive replay.

Run with Python's standard library. The index intentionally keeps intermediate,
rejected, and final accepted test runs separate; their pass counts are not added.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import runpy
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def repack(members, sort_order='lexical'):
    output = io.BytesIO()
    assert sort_order in ('lexical', 'path_components'), sort_order
    order = (
        (lambda entry: PurePosixPath(entry[0]).parts)
        if sort_order == 'path_components'
        else (lambda entry: entry[0])
    )
    with gzip.GzipFile(filename='', fileobj=output, mode='wb', mtime=0, compresslevel=9) as zipped:
        with tarfile.open(fileobj=zipped, mode='w', format=tarfile.PAX_FORMAT) as archive:
            for name, data in sorted(members.items(), key=order):
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o644
                info.mtime = 0
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def verify(index_path):
    index = json.loads(index_path.read_text())
    base = index_path.parent
    total_members = 0
    for item in index['archives']:
        data = (base / item['path']).read_bytes()
        assert len(data) == item['size'], item['path']
        assert digest(data) == item['sha256'], item['path']
        expected = {member['path']: member for member in item['members']}
        assert len(expected) == len(item['members']), 'Duplicate indexed archive member'
        actual = {}
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            for info in archive.getmembers():
                path = PurePosixPath(info.name)
                assert not path.is_absolute() and '..' not in path.parts, info.name
                assert info.isfile() and info.name not in actual, info.name
                assert info.name in expected, info.name
                payload = archive.extractfile(info).read()
                record = expected[info.name]
                assert len(payload) == record['size'], info.name
                assert digest(payload) == record['sha256'], info.name
                actual[info.name] = payload
        assert set(actual) == set(expected), item['path']
        if item.get('deterministic_repack', True):
            assert repack(actual, item.get('sort_order', 'lexical')) == data, ('Deterministic replay mismatch', item['path'])
        total_members += len(actual)
    for item in index.get('files', []):
        data = (base / item['path']).read_bytes()
        assert len(data) == item['size'] and digest(data) == item['sha256'], item['path']
    distinct_cases = None
    if index.get('case_accounting'):
        accounting = runpy.run_path(str(base / 'scripts/account_cases.py'))
        distinct_cases = accounting['verify_accounting'](base)
    print(json.dumps({
        'archives_verified': len(index['archives']),
        'members_verified': total_members,
        'standalone_files_verified': len(index.get('files', [])),
        'deterministic_repacking': 'passed',
        'distinct_accepted_cases': distinct_cases,
    }))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, default=Path(__file__).with_name('index.json'))
    verify(parser.parse_args().index.resolve())
