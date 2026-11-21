#!/usr/bin/env python3
"""Package retained local Mail/engine evidence without rerunning any tests."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', type=Path, required=True)
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    destination = Path(__file__).resolve().parent
    entries = {}

    def add_file(path, name):
        if not path.is_file():
            raise FileNotFoundError(path)
        if name in entries:
            raise ValueError('Duplicate archive name: ' + name)
        entries[name] = path.read_bytes()

    def add_directory(path, prefix):
        for file in sorted(path.rglob('*')):
            if file.is_file():
                add_file(file, prefix + '/' + file.relative_to(path).as_posix())

    integrated = scratch / 'integrated-acceptance'
    for file in sorted(integrated.iterdir()):
        if not file.is_file():
            continue
        if file.name.startswith('engine'):
            add_file(file, 'engine/' + file.name)
        elif file.name == 'run_integrated_acceptance.py':
            add_file(file, 'runners/engine-original.py')
        else:
            add_file(file, 'prior-accepted/initial-mail/' + file.name)
    add_file(scratch / 'engine-node-filesystem-cases.json',
             'engine/engine-node-filesystem-cases.json')
    add_directory(scratch / 'final-mail-acceptance', 'mail')
    add_directory(scratch / 'late-mail-acceptance', 'late-mail')
    for source, name in [
        ('run_integrated_acceptance.py', 'runners/final-mail.py'),
        ('run_late_mail_acceptance.py', 'runners/late-mail.py'),
        ('publication-journal.json', 'publication/checkpoints.json'),
        ('publish_checkpoint.js', 'publication/publish_checkpoint.js'),
    ]:
        add_file(scratch / source, name)

    # Preserve early failures and useful intermediate probes as diagnostics.
    # Their successes are not added to the final accepted cohort counts.
    for name in [
        'journal-existing-host-initial.jsonl',
        'journal-host-analysis-initial.log',
        'journal-host-analysis-second.log',
        'note-type-vm.jsonl', 'note-type-vm.stderr',
        'ews-feedback.jsonl', 'ews-feedback.stderr',
        'reader-ui-suite.log', 'reader-final-affected-tests.log',
        'reader-analysis-final.log', 'reader-merge-ui-final.log',
        'reader-merge-host-final.log', 'reader-journal-analysis-accepted.log',
        'journal-host-history-acceptance.log', 'journal-final-pub-get.log',
        'late-mail-test-merge-analysis.log', 'final-format-check.log',
    ]:
        path = scratch / name
        if path.is_file():
            add_file(path, 'diagnostics/' + name)

    archive = destination / 'mail-engine-evidence.tar.xz'
    with tarfile.open(archive, 'w:xz', format=tarfile.USTAR_FORMAT,
                      preset=6) as tar:
        for name, data in sorted(entries.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            tar.addfile(info, io.BytesIO(data))
    index = {
        'schema': 'quds-mail-engine-evidence/v1',
        'archive': archive.name,
        'archive_sha256': sha(archive.read_bytes()),
        'members': [{'path': name, 'bytes': len(data), 'sha256': sha(data)}
                    for name, data in sorted(entries.items())],
        'note': 'Preserved local execution evidence; packaging is not a new test execution. Diagnostics and prior accepted runs are separate from final cohort counts.',
    }
    (destination / 'mail-engine-evidence-index.json').write_text(
        json.dumps(index, indent=2) + '\n')

    visuals = destination / 'visuals'
    visuals.mkdir(exist_ok=True)
    rows = []
    for image in sorted((scratch / 'journal-visuals').glob('*.png')):
        target = visuals / image.name
        shutil.copyfile(image, target)
        data = target.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n'
        rows.append({
            'path': 'visuals/' + target.name,
            'sha256': sha(data), 'bytes': len(data),
            'width': int.from_bytes(data[16:20], 'big'),
            'height': int.from_bytes(data[20:24], 'big'),
            'review': 'Visually inspected: readable history/receipt/details, reachable close controls, no observed overflow. German/Arabic compact cases use 1.4x text scale.',
        })
    assert len(rows) == 9
    (destination / 'visual-review.json').write_text(json.dumps({
        'scope': 'Rendered deterministic Flutter widget captures; no live account or installed-platform claim.',
        'images': rows,
    }, indent=2) + '\n')
    print(json.dumps({'archive': archive.name, 'bytes': archive.stat().st_size,
                      'members': len(entries), 'visuals': len(rows)}))


if __name__ == '__main__':
    main()
