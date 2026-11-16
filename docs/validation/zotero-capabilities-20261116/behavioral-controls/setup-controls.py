#!/usr/bin/env python3
"""Archive genuine before/after sources and rebase existing locked graphs."""
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
from urllib.parse import urljoin

ROOT = Path(__file__).resolve().parent
TOOLCHAIN = ROOT.parent
WORKSPACE = TOOLCHAIN.parent
REPO = WORKSPACE / 'quds_office_suite'
COMMITS = {
    'before': 'e5e1e9af6beb0972a010d8208c1690a642809113',
    'after': '357f7a3e87d8536c03ecca2a860a0a564b1659f0',
}
PACKAGES = ['quds_office_engine', 'quds_office_editor', 'quds_reports', 'legacy_doc_parser']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    paths = [f'packages/{name}/lib' for name in PACKAGES]
    paths += ['packages/quds_office_editor/fonts', 'packages/quds_office_editor/templates']
    receipt = {
        'recorded_utc': datetime.now(timezone.utc).isoformat(),
        'repository': 'CrispStrobe/quds_office_suite',
        'commits': COMMITS,
        'production_sources_or_manifests_modified': False,
        'graphs': {},
    }
    widget = subprocess.check_output([
        'git', '-C', str(REPO), 'show',
        COMMITS['after'] + ':packages/quds_office_editor/test/word_zotero_dialog_scaling_test.dart',
    ])
    (ROOT / 'word_zotero_dialog_scaling_test.dart').write_bytes(widget)
    for label, commit in COMMITS.items():
        folder = ROOT / label
        folder.mkdir(exist_ok=True)
        archive = subprocess.check_output(['git', '-C', str(REPO), 'archive', commit, *paths])
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(folder, filter='data')
        graph_receipt = {'archived_paths': paths, 'archive_sha256': hashlib.sha256(archive).hexdigest(), 'packages': {}}
        for name in PACKAGES:
            target = folder / 'packages' / name
            original = TOOLCHAIN / 'harness' / name
            shutil.copyfile(original / 'pubspec.yaml', target / 'pubspec.yaml')
            if (original / 'pubspec.lock').exists():
                shutil.copyfile(original / 'pubspec.lock', target / 'pubspec.lock')
            config_path = original / '.dart_tool/package_config.json'
            if not config_path.exists():
                continue
            config = json.loads(config_path.read_text())
            for package in config['packages']:
                package['rootUri'] = (
                    (folder / 'packages' / package['name']).as_uri() + '/'
                    if package['name'] in PACKAGES
                    else urljoin(config_path.as_uri(), package['rootUri'])
                )
            (target / '.dart_tool').mkdir(exist_ok=True)
            (target / '.dart_tool/package_config.json').write_text(json.dumps(config, indent=2) + '\n')
            if (original / '.dart_tool/package_graph.json').exists():
                shutil.copyfile(original / '.dart_tool/package_graph.json', target / '.dart_tool/package_graph.json')
            graph_receipt['packages'][name] = {
                'upstream_config': str(config_path),
                'upstream_config_sha256': sha(config_path),
                'isolated_config_sha256': sha(target / '.dart_tool/package_config.json'),
                'manifest_sha256': sha(target / 'pubspec.yaml'),
                'lockfile_sha256': sha(target / 'pubspec.lock'),
                'sources': {str(p.relative_to(target)): sha(p) for p in sorted((target / 'lib').rglob('*')) if p.is_file()},
            }
        for package, filename in [
            ('quds_office_engine', 'alias_bridge_control_test.dart'),
            ('quds_office_editor', 'word_zotero_dialog_scaling_test.dart'),
        ]:
            target = folder / 'packages' / package / 'test'
            target.mkdir(exist_ok=True)
            shutil.copyfile(ROOT / filename, target / filename)
        receipt['graphs'][label] = graph_receipt
    receipt['tests_sha256'] = {name: sha(ROOT / name) for name in [
        'alias_bridge_control_test.dart', 'word_zotero_dialog_scaling_test.dart',
    ]}
    (ROOT / 'source-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'commits': COMMITS, 'tests': receipt['tests_sha256']}, indent=2))


if __name__ == '__main__':
    main()
