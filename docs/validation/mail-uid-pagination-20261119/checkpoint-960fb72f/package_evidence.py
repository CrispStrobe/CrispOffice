"""Package completed local evidence without rewriting original log bytes."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import tarfile


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    archive = args.archive.resolve()
    if archive == source or source in archive.parents:
        raise RuntimeError('Archive must be outside the source evidence directory')
    if archive.exists():
        raise RuntimeError('Preserve existing evidence archives')
    files = sorted(path for path in source.rglob('*') if path.is_file())
    if any(path.is_symlink() for path in source.rglob('*')):
        raise RuntimeError('Evidence must contain ordinary files only')
    index = []
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'w:xz', preset=6) as output:
        for path in files:
            record = {'path': path.relative_to(source).as_posix(),
                      'bytes': path.stat().st_size, 'sha256': digest(path)}
            output.add(path, arcname=record['path'], recursive=False)
            if path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
                raise RuntimeError('Evidence changed during packaging: ' + str(path))
            index.append(record)
    receipt = {'created_at_utc': datetime.now(timezone.utc).isoformat(),
               'source_directory': str(source), 'archive': archive.name,
               'archive_bytes': archive.stat().st_size, 'archive_sha256': digest(archive),
               'member_count': len(index), 'members': index}
    archive.with_suffix('.index.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: value for key, value in receipt.items() if key != 'members'}))


if __name__ == '__main__':
    main()
