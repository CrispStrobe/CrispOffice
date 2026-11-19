#!/usr/bin/env python3
"""Package original proofing outputs without combining qualification attempts."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--index', type=Path, required=True)
    args = parser.parse_args()
    sources = {
        'accepted-ba7c1e26': args.workspace / 'qualification-release-arabic-final',
        'attempt-05582479': args.workspace / 'qualification-release-arabic',
        'development': args.workspace / 'review/arabic',
        'independent-audit-adapter': args.workspace / 'reconciliation-audit/arabic-audit-adapter',
        'independent-audit': args.workspace / 'reconciliation-audit/arabic-final-audit.log',
    }
    accepted = json.loads((sources['accepted-ba7c1e26'] / 'verification.json').read_text())
    earlier = json.loads((sources['attempt-05582479'] / 'verification.json').read_text())
    assert accepted['source_commit'] == 'ba7c1e26cdc409915e04eba49dd1f1c002280cf8'
    assert accepted['success'] and accepted['passed'] == 179
    assert earlier['source_commit'] == '05582479e1249a8cf4d526740a0d43149c3cf5ae'
    assert not earlier['success'] and earlier['passed'] == 179
    rows, originals = [], {}
    for prefix, directory in sources.items():
        paths = [directory] if directory.is_file() else sorted(directory.rglob('*'))
        for path in paths:
            if path.is_file():
                relative = path.name if directory.is_file() else path.relative_to(directory).as_posix()
                name = prefix + '/' + relative
                data = path.read_bytes()
                originals[name] = data
                rows.append({'path': name, 'bytes': len(data), 'sha256': digest(data)})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.output, 'w:xz', format=tarfile.PAX_FORMAT) as archive:
        for row in rows:
            info = tarfile.TarInfo(row['path'])
            info.size, info.mode, info.mtime = row['bytes'], 0o644, 0
            info.uid, info.gid = 0, 0
            info.uname, info.gname = '', ''
            archive.addfile(info, io.BytesIO(originals[row['path']]))
    with tarfile.open(args.output, 'r:xz') as archive:
        assert archive.getnames() == [row['path'] for row in rows]
        for member in archive.getmembers():
            assert member.isfile()
            assert archive.extractfile(member).read() == originals[member.name]
    result = {
        'archive': args.output.name, 'bytes': args.output.stat().st_size,
        'sha256': digest(args.output.read_bytes()), 'member_count': len(rows),
        'members': rows, 'all_members_reopened_and_compared_to_originals': True,
        'accepted_source': accepted['source_commit'], 'accepted_application_cases': 179,
        'earlier_attempt_and_development_added_to_accepted_total': 0,
        'earlier_mail_836_and_python_78_included_in_this_total': False,
        'builder_sha256': digest(Path(__file__).read_bytes()),
    }
    args.index.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['archive', 'bytes', 'sha256', 'member_count']}))


if __name__ == '__main__':
    main()
