#!/usr/bin/env python3
"""Package preserved local Mail qualification without rerunning any gate."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--repository', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    repository = args.repository.resolve()
    validation = workspace / 'validation'
    output = repository / 'docs/validation/mail-flag-recovery-20261121'
    output.mkdir(parents=True, exist_ok=True)

    def read(name: str):
        return json.loads((validation / name).read_text())

    provider = read('provider-recovery-final/summary.json')
    core = read('core-recovery-final/summary.json')
    store = read('store-analysis-final/receipt.json')
    mail = read('final-mail-acceptance/receipt.json')
    analysis = read('final-source-analysis/receipt.json')
    zotero = read('integrated-zotero-final/qualification.json')
    word = read('integrated-word-accepted/tests.run.json')
    applicability = read('final-source-applicability.json')
    assert provider['passed'] == 192 and provider['failed'] == 0
    assert provider['source_config_runtime_stable'] is True
    assert core['strict_success'] is True and core['passed'] == 470
    assert store['accepted'] is True
    assert mail['accepted'] is True
    assert [check['tests']['passed'] for check in mail['checks']] == [266, 21]
    assert analysis['accepted'] is True
    assert zotero['total_tests_passed'] == 309 and zotero['failed'] == 0
    assert word['strict_success'] is True and word['counts']['passed'] == 154

    def git(*arguments: str) -> str:
        return subprocess.check_output(['git', *arguments], cwd=repository, text=True).strip()

    head = git('rev-parse', 'HEAD')
    source_paths = git('diff', '--name-only',
                      'bf761552d22dcd1eb8cbb0ab00ddab6507e1d572', 'HEAD',
                      '--', '*.dart').splitlines()
    source_paths += ['pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml']
    source = {
        'source_commit': head,
        'source_tree': git('rev-parse', 'HEAD^{tree}'),
        'scope': 'All changed Dart inputs plus workspace dependency/configuration files.',
        'files': {name: {'sha256': digest(repository / name),
                         'git_blob': git('rev-parse', 'HEAD:' + name)}
                  for name in sorted(set(source_paths))},
    }
    (output / 'final-source.json').write_text(json.dumps(source, indent=2) + '\n')
    for name in ['final-source-applicability.json', 'final-intake-refresh.json']:
        shutil.copyfile(validation / name, output / name)

    directories = [
        'core-recovery-final', 'provider-recovery-final', 'store-analysis-final',
        'studio-recovery-final', 'integrated-mail-final', 'final-mail-acceptance',
        'integrated-zotero-final', 'integrated-word-final', 'integrated-word-fixed',
        'integrated-word-accepted', 'format-analysis-final', 'format-normalization',
        'final-source-analysis',
    ]
    paths: dict[str, Path] = {}
    for name in directories:
        directory = validation / name
        assert directory.is_dir(), directory
        for path in directory.rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:
                paths['validation/' + str(path.relative_to(validation))] = path
    for pattern in ['host-loader-recovery*', 'existing-journal-ui*',
                    'final-intake-refresh*', 'run_*mail*.py', 'run_store_analysis.py',
                    'run_studio_flag_recovery.py', 'run_final_source_analysis.py',
                    'final-source-applicability.json']:
        for path in validation.glob(pattern):
            if path.is_file():
                paths['validation/' + path.name] = path
    for name in ['store-reconciliation-qualification.json',
                 'store-reconciliation-regression.log',
                 'store-reconciliation-analysis.log', 'store-existing-reconciliation.log']:
        paths[name] = workspace / name
    for name in ['README.md', 'setup-receipt.json', 'sdk-receipt.json',
                 'pub-cache-receipt.json', 'env.sh']:
        paths['runtime/' + name] = workspace / 'runtime' / name
    for path in (workspace / 'runtime/logs').glob('*'):
        if path.is_file():
            paths['runtime/logs/' + path.name] = path
    paths['package_mail_evidence.py'] = Path(__file__).resolve()

    archive = output / 'local-qualification.tar.xz'
    members = []
    with tarfile.open(archive, 'w:xz', preset=6) as bundle:
        for name, path in sorted(paths.items()):
            assert path.is_file(), path
            info = bundle.gettarinfo(str(path), arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            info.mtime = 0
            with path.open('rb') as stream:
                bundle.addfile(info, stream)
            members.append({'path': name, 'bytes': path.stat().st_size,
                            'sha256': digest(path)})
    index = {'archive': archive.name, 'archive_bytes': archive.stat().st_size,
             'archive_sha256': digest(archive), 'members': members}
    (output / 'evidence-index.json').write_text(json.dumps(index, indent=2) + '\n')
    visuals = output / 'visuals'
    visuals.mkdir(exist_ok=True)
    for path in (validation / 'final-mail-acceptance/visuals').glob('*.png'):
        shutil.copyfile(path, visuals / path.name)
    shutil.copyfile(Path(__file__).resolve(), output / 'package-evidence.py')
    summary = {
        'schema': 'quds-mail-flag-recovery-qualification/v1',
        'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': head, 'source_tree': source['source_tree'],
        'status': 'PASS',
        'cohorts': [
            {'name': 'Portable core', 'vm': 235, 'node': 235, 'passed': 470,
             'receipt': 'validation/core-recovery-final/summary.json'},
            {'name': 'Native store', 'passed': 791,
             'receipt': 'validation/store-analysis-final/receipt.json'},
            {'name': 'Node store error classification', 'passed': 3,
             'receipt': 'validation/store-analysis-final/receipt.json'},
            {'name': 'Provider observation and regression', 'vm': 186, 'node': 6,
             'passed': 192, 'receipt': 'validation/provider-recovery-final/summary.json'},
            {'name': 'Final integrated Studio', 'passed': 266,
             'receipt': 'validation/final-mail-acceptance/receipt.json'},
            {'name': 'Shared Mail UI and intake compatibility', 'passed': 21,
             'receipt': 'validation/final-mail-acceptance/receipt.json'},
            {'name': 'Incoming Zotero', 'passed': 309,
             'receipt': 'validation/integrated-zotero-final/qualification.json',
             'applicability': 'See final-source-applicability.json for the exact source binding and one later indentation-only test change.'},
            {'name': 'Incoming Word and section fidelity', 'passed': 154,
             'receipt': 'validation/integrated-word-accepted/tests.run.json'},
        ],
        'analysis': 'Final 53-file formatter and fatal-info analysis passed; supplemental namespace-qualified fidelity fixture is checked in the final Word evidence.',
        'archive': archive.name, 'archive_sha256': digest(archive),
        'visuals': {path.name: digest(path) for path in sorted(visuals.glob('*.png'))},
        'source_applicability': 'final-source-applicability.json',
        'counting': 'Do not add overlapping intermediate runs to the accepted cohorts; VM and Node core execute the same 235 cases.',
        'diagnostics': 'Earlier readiness, host fixture, pre-format and incoming Word failure attempts are retained separately and excluded from accepted counts.',
        'limits': 'Controlled providers, native Linux SQLite and Flutter tester; no live mailbox, installed-platform release, browser persistence, or power-loss claim.',
        'github_actions': 'Not queried or awaited.',
    }
    (output / 'qualification.json').write_text(json.dumps(summary, indent=2) + '\n')
    included = [p for p in output.rglob('*') if p.is_file() and p.name != 'SHA256SUMS']
    (output / 'SHA256SUMS').write_text(''.join(
        f'{digest(path)}  {path.relative_to(output)}\n' for path in sorted(included)))
    print(json.dumps({'output': str(output), 'archive_bytes': archive.stat().st_size,
                      'archive_members': len(members), 'source_commit': head}, indent=2))


if __name__ == '__main__':
    main()
