#!/usr/bin/env python3
"""Package completed local qualification without changing source or receipts."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import gzip
import hashlib
import io
import json
import shutil
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--workspace', type=Path, required=True)
ROOT = parser.parse_args().workspace.resolve()
OUT = ROOT / 'quds/docs/validation/zotero-finalization-20261117'
OUT.mkdir(parents=True, exist_ok=True)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def load(path):
    return json.loads(path.read_text())

def archive(name, groups):
    contents = {}
    for folder, prefix in groups:
        for path in sorted(folder.rglob('*')):
            if (path.is_file() and not path.is_symlink()
                    and not path.name.endswith(('.lock', '.tmp'))
                    and '__pycache__' not in path.parts):
                contents[prefix + '/' + str(path.relative_to(folder))] = path.read_bytes()
    index = {n: {'bytes': len(b), 'sha256': sha(b)} for n, b in contents.items()}
    contents['archive-index.json'] = (json.dumps(index, indent=2) + '\n').encode()
    target = OUT / name
    with target.open('wb') as stream:
        with gzip.GzipFile(fileobj=stream, mode='wb', mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode='w') as tar:
                for path, data in sorted(contents.items()):
                    info = tarfile.TarInfo(path)
                    info.size, info.mode = len(data), 0o644
                    tar.addfile(info, io.BytesIO(data))
    with tarfile.open(target, 'r:gz') as tar:
        for path, data in contents.items():
            assert tar.extractfile(path).read() == data, path
    return {'file': name, 'bytes': target.stat().st_size,
            'sha256': sha(target.read_bytes()), 'entries': len(contents)}

canonical_dir = ROOT / 'runtime/canonical-final'
host_dir = ROOT / 'runtime/host-final'
harper_dir = ROOT / 'runtime/harper-final'
canonical, host, harper = (load(p / 'receipt.json') for p in [canonical_dir, host_dir, harper_dir])
assert canonical['status'] == host['status'] == harper['status'] == 'passed'
assert canonical['all_passed']
for receipt, folder in [(canonical, canonical_dir), (host, host_dir), (harper, harper_dir)]:
    for row in receipt['commands']:
        assert row['status'] == 'passed' and row['exit_code'] == 0, row['name']
        for field in (['log'] if 'log' in row else ['stdout', 'stderr']):
            assert sha((folder / row[field]).read_bytes()) == row[field + '_sha256'], row['name']
for key in ['source_inputs_unchanged', 'external_dependency_and_runtime_inputs_unchanged',
            'fixture_inputs_unchanged', 'harness_inputs_unchanged',
            'analysis_config_restored', 'published_source_still_matches']:
    assert canonical[key], key
for key in ['source_unchanged', 'dependencies_unchanged', 'analysis_config_restored']:
    assert host[key], key
for key in ['source_inputs_unchanged', 'dependency_runtime_harness_inputs_unchanged',
            'analysis_config_restored', 'published_inputs_still_match']:
    assert harper[key], key
for row in canonical['commands'] + harper['commands']:
    if 'passed_tests' in row and row['passed_tests'] is not None:
        assert row.get('skipped_tests', 0) == 0, row['name']

counts = {'canonical_zotero': canonical['zotero_passed_tests'],
          'canonical_integration': canonical['integration_passed_tests'],
          'harper_adapter': harper['passed_tests'],
          'actual_host': host['passed_host_tests'], 'python_sync': host['passed_python_tests']}
assert counts == {'canonical_zotero': 576, 'canonical_integration': 460,
                  'harper_adapter': 23, 'actual_host': 41, 'python_sync': 28}
summary = {
    'schema_version': 1, 'status': 'passed',
    'packaged_utc': datetime.now(timezone.utc).isoformat(),
    'canonical_source': canonical['qualified_published_source_commit'],
    'canonical_tree': canonical['qualified_source_tree'],
    'host_source': host['published_source'],
    'host_tree': '276d73be08e5e37ee467cce4ad196f5dde1eac04',
    'tests': counts, 'total_fresh_tests': sum(counts.values()),
    'canonical_cohorts': canonical['passed_tests_by_cohort'],
    'test_file_counts': {'canonical': 63, 'harper': 3, 'host': 4},
    'strict_analysis_and_format_targets': {'canonical': 49, 'harper': 5, 'studio': 1, 'host_and_vendor': 34},
    'managed_files': {'canonical': 664, 'standalone_parser': 1857, 'total': 2521},
    'frozen_refs': {'quds': {'refs': 189, 'ancestors': 189},
                    'host': {'refs': 274, 'ancestors': 214, 'exact_tree_aliases': 60}},
    'all_source_dependency_harness_and_config_gates_passed': True,
    'historical_and_intermediate_counts_added': False,
    'github_actions_queried_awaited_or_rerun': False,
    'scope_limits': ['Focused test graphs, not a new full application build',
                     'No fresh live Zotero, Word/LibreOffice, native picker, platform launch or keychain acceptance',
                     'Harper adapter uses injected transports; no new native/Wasm acceptance',
                     'Eight inherited host executable-mode differences preserved'],
}
for folder, name in [(canonical_dir, 'canonical-receipt.json'), (harper_dir, 'harper-studio-receipt.json'),
                     (host_dir, 'host-receipt.json')]:
    shutil.copy2(folder / 'receipt.json', OUT / name)
summary['archives'] = [
    archive('canonical-evidence.tar.gz', [(canonical_dir, 'canonical')]),
    archive('harper-studio-evidence.tar.gz', [(harper_dir, 'harper-studio')]),
    archive('setup-evidence.tar.gz', [(ROOT / 'publication/setup', 'setup')]),
    archive('incoming-audit-evidence.tar.gz', [(ROOT / 'incoming-audits/quds', 'quds'),
                                             (ROOT / 'incoming-audits/host', 'host')]),
]
summary['host_archive'] = {
    'url': 'https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-recovery-20261116/docs/validation/zotero-finalization-20261117/host-evidence.tar.gz',
    **load(ROOT / 'crisp/docs/validation/zotero-finalization-20261117/host-publication.json'),
}
(OUT / 'qualification-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
shutil.copy2(ROOT / 'publication/english-notice-final-check.json', OUT / 'english-notice-final-check.json')
shutil.copy2(ROOT / 'publication/setup/README.md', OUT / 'REPRODUCE.md')
for name in ['quds-independent-review.json']:
    if (ROOT / 'publication' / name).is_file():
        shutil.copy2(ROOT / 'publication' / name, OUT / name)
tools_dir = OUT / 'tools'
tools_dir.mkdir(exist_ok=True)
shutil.copy2(Path(__file__), tools_dir / Path(__file__).name)
print(json.dumps({'tests': counts, 'total': summary['total_fresh_tests'], 'archives': summary['archives']}, indent=2))
