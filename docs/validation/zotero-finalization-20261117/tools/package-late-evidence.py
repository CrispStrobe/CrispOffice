#!/usr/bin/env python3
"""Package completed late integration receipts and their exact reproduction inputs."""
from pathlib import Path
import argparse
import gzip
import hashlib
import io
import json
import os
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_text())


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--workspace', type=Path, required=True)
args = parser.parse_args()
root = args.workspace.resolve()
late = root / 'runtime/late-main'
run = late / 'qualification-2'
outer = load(run / 'receipt.json')
canonical = load(run / 'canonical/receipt.json')
host = load(run / 'host/receipt.json')
independent = load(root / 'publication/late-main-independent-review.json')
assert independent['status'] == 'passed'
for receipt in (outer, canonical, host):
    assert receipt['status'] == 'passed', receipt['status']
assert outer['quds_source_commit'] == '732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2'
assert outer['host_source_commit'] == '084815b665df7779357155d86c5fff9bd31bfc43'
for receipt, folder in [(canonical, run / 'canonical'), (host, run / 'host')]:
    for command in receipt['commands']:
        assert command['status'] == 'passed' and command['exit_code'] == 0, command['name']
        assert digest((folder / command['log']).read_bytes()) == command['log_sha256'], command['name']
counts = {
    'canonical_sheet': canonical['passed_tests'],
    'host_existing': host['passed_host_tests'],
    'host_document_service': host['passed_service_tests'],
    'python_sync_verifier': host['passed_python_tests'],
}
assert counts == {'canonical_sheet': 18, 'host_existing': 41,
                  'host_document_service': 39, 'python_sync_verifier': 28}, counts
assert host['service_skipped_tests'] == 0

# Package inputs and receipts, not downloaded packages, generated builds, or SDKs.
excluded_dirs = {'qualification-1', 'pub-cache', 'service-harness', 'downloads',
                 'tmp', 'config', '__pycache__'}
contents = {}
for folder, dirs, names in os.walk(late, followlinks=False):
    here = Path(folder)
    dirs[:] = sorted(d for d in dirs if d not in excluded_dirs
                     and not (here / d).is_symlink())
    for name in sorted(names):
        path = here / name
        if (path.is_symlink() or name.endswith('.tmp') or name == 'qualification.lock'
                or name == 'viewer-formatted-proposal.dart'):
            continue
        contents['late-main/' + str(path.relative_to(late))] = path.read_bytes()

audit_names = [
    'late-main-canonical-review.json', 'late-main-canonical-final.json',
    'late-main-host-before-format.json', 'late-main-host-final.json',
    'late-main-sync-preflight.json', 'late-main-guarded-sync.log',
    'late-main-vendor-precommit.log', 'late-main-attempt-1-review.json',
    'late-main-independent-review.json',
    'quds-later-main-observation.json', 'post-qualification-main-movement.json',
]
for name in audit_names:
    contents['audit/' + name] = (root / 'publication' / name).read_bytes()
provenance = root / 'publication/late-main-setup-provenance'
contents['late-main/setup-provenance/README-before-addendum.md'] = (late / 'README.md').read_bytes()
for path in sorted(provenance.iterdir()):
    if path.is_file():
        contents['late-main/setup-provenance/' + path.name] = path.read_bytes()
contents['late-main/README.md'] = (provenance / 'README-replacement.md').read_bytes()
contents['tools/package-late-evidence.py'] = Path(__file__).read_bytes()
contents['tools/review-late-qualification.py'] = (root / 'publication/review-late-qualification.py').read_bytes()
index = {name: {'bytes': len(data), 'sha256': digest(data)}
         for name, data in sorted(contents.items())}
contents['archive-index.json'] = (json.dumps(index, indent=2) + '\n').encode()
target = root / 'publication/late-main-evidence.tar.gz'
with target.open('wb') as stream:
    with gzip.GzipFile(fileobj=stream, mode='wb', mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode='w') as archive:
            for name, data in sorted(contents.items()):
                entry = tarfile.TarInfo(name)
                entry.size, entry.mode = len(data), 0o644
                archive.addfile(entry, io.BytesIO(data))
with tarfile.open(target, 'r:gz') as archive:
    assert set(archive.getnames()) == set(contents)
    for name, data in contents.items():
        assert archive.extractfile(name).read() == data, name

summary = {
    'status': 'passed',
    'canonical_source': outer['quds_source_commit'],
    'canonical_tree': canonical['source_tree'],
    'host_source': outer['host_source_commit'],
    'host_tree': host['implementation_tree'],
    'tests': counts,
    'bounded_test_executions': sum(counts.values()),
    'initial_1128_tests_remain_bound_to_original_source_pair': True,
    'counts_overlap_initial_qualification_and_are_not_added_to_unique_total': True,
    'failed_attempt_1_is_preserved_and_excluded_from_passing_total': True,
    'canonical_source_inputs': canonical['source_file_count'],
    'canonical_dependency_runtime_inputs': canonical['dependency_file_count'],
    'host_source_inputs': host['source_file_count'],
    'host_dependency_runtime_inputs': host['dependency_file_count'],
    'host_graph_packages': host['dependency_package_count'],
    'canonical_analysis_and_format_targets': canonical['analysis_and_format_targets'],
    'host_analysis_targets': host['host_analysis_targets'],
    'vendor_analysis_targets': host['vendored_analysis_targets'],
    'viewer_scope': 'Exact delivered source and formatting; no full viewer analysis, compilation or widget execution',
    'github_actions_used': False,
    'later_concurrent_production_work_excluded': {
        'canonical_main': '8a3f5a9de14c556fd01ffacb3897629c51f4fa7e',
        'host_main': '8fe921d030d7623046e28127abec5949c4d8b991',
        'feature': 'New bounded ODT writer and host Export as ODT action',
        'reason': 'Arrived after the qualified source freeze and changes production inputs',
    },
    'archive': {'file': target.name, 'bytes': target.stat().st_size,
                'sha256': digest(target.read_bytes()), 'entries': len(contents)},
    'failed_attempt_archive': {
        'url': 'https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/checkpoints/late-main-attempt-1.tar.gz',
        'sha256': '33160f5efc5a56fa14501e77bbbbdef2bc92b9d25c0ad004c1d976aa742ff948',
    },
}
(root / 'publication/late-main-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({'status': summary['status'], 'tests': counts,
                  'total_executions': sum(counts.values()), 'archive': summary['archive']}))
