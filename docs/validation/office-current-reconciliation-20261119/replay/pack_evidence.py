"""Create a deterministic indexed archive of selected qualification files."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tree', action='append', default=[])
    parser.add_argument('--file', action='append', default=[])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    files = {}
    for entry in args.tree:
        label, folder = entry.split('=', 1)
        root = Path(folder)
        for path in sorted(root.rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                files[label + '/' + path.relative_to(root).as_posix()] = path
    for entry in args.file:
        label, source = entry.split('=', 1)
        if label in files:
            raise ValueError('Duplicate archive path: ' + label)
        files[label] = Path(source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    index = []
    with tarfile.open(args.output, 'w:xz', format=tarfile.PAX_FORMAT) as archive:
        for name, path in sorted(files.items()):
            data = path.read_bytes()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            import io
            archive.addfile(info, io.BytesIO(data))
            index.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    with tarfile.open(args.output, 'r:xz') as archive:
        members = archive.getmembers()
        if [m.name for m in members] != [r['path'] for r in index]:
            raise RuntimeError('Archive inventory mismatch')
        for member, row in zip(members, index):
            data = archive.extractfile(member).read()
            if len(data) != row['bytes'] or hashlib.sha256(data).hexdigest() != row['sha256']:
                raise RuntimeError('Archive member mismatch: ' + member.name)
    result = {'archive': args.output.name, 'bytes': args.output.stat().st_size, 'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(), 'member_count': len(index), 'members': index, 'reopened_and_verified': True}
    args.output.with_suffix('.index.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'members'}))


if __name__ == '__main__':
    main()
