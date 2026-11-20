#!/usr/bin/env python3
"""Verify reviewed incoming blobs and local shell/YAML syntax, without CI."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

import yaml


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    here = Path(__file__).resolve().parent

    def git(*command):
        return subprocess.check_output(['git', '-C', str(repo), *command])

    def source(sha, path):
        return git('show', f'{sha}:{path}')

    def blob(sha, path):
        return git('rev-parse', f'{sha}:{path}').decode().strip()

    head = git('rev-parse', args.head + '^{commit}').decode().strip()
    initial = 'e79c32e77f1990e303527e477e4909df993c1b9b'
    main_sha = '6b2f392c7301d4b19f16d6ccf150258f14bf7ad7'
    portable = 'bf606aa08f8905ceef35342772df91630840a9b2'
    comment_test = 'a56397df5f53b991f5016f3cc8e1ab53b7ce12f1'
    distribution = 'packages/quds_proofing_spacy/lib/src/distribution.dart'
    workspace = 'packages/quds_office_editor/example/lib/suite_workspace.dart'
    sources = [
        ('current main', 'fe076d22a1b25d27c34b861fa5b0b2a32833b33e', main_sha, {distribution, workspace}),
        ('macOS portability', '85c019cd8fda1a735a727bff98c2a56fb25a368e', portable, {distribution}),
        ('comment draft test', main_sha, comment_test, set()),
    ]
    source_paths = {}
    latest_by_path = {}
    for label, base, incoming, exceptions in sources:
        paths = list(filter(None, git(
            'diff', '--no-renames', '--name-only', '-z', base, incoming
        ).decode().split('\0')))
        source_paths[incoming] = paths
        for path in paths:
            latest_by_path[path] = incoming
    preservation = []
    for label, base, incoming, exceptions in sources:
        paths = source_paths[incoming]
        rows = []
        for path in paths:
            incoming_blob, final_blob = blob(incoming, path), blob(head, path)
            equal = incoming_blob == final_blob
            latest = latest_by_path[path]
            expected_blob = blob(latest, path)
            selected_equal = expected_blob == final_blob
            assert selected_equal or path in exceptions, (label, path)
            rows.append({
                'path': path, 'incoming_blob': incoming_blob,
                'final_blob': final_blob, 'identical_to_this_incoming': equal,
                'latest_selected_source': latest,
                'latest_selected_blob': expected_blob,
                'identical_to_latest_selected_source': selected_equal,
                'reviewed_combination': not selected_equal and path in exceptions,
            })
        preservation.append({'source': label, 'commit': incoming, 'paths': rows})

    main_distribution = source(main_sha, distribution).decode()
    final_distribution = source(head, distribution).decode()
    without_docs = lambda text: '\n'.join(
        line for line in text.splitlines() if not line.lstrip().startswith('///')
    )
    assert without_docs(main_distribution) == without_docs(final_distribution)
    before = '''    _slides.applyTransform(
      shape,
      PmlTransform(
        x: nextX,
        y: nextY,
        cx: t.cx,
        cy: t.cy,
        rot: t.rot,
        flipH: t.flipH,
        flipV: t.flipV,
      ),
    );'''
    after = '    _slides.applyTransform(shape, t.copyWith(x: nextX, y: nextY));'
    main_workspace = source(main_sha, workspace).decode()
    final_workspace = source(head, workspace).decode()
    assert main_workspace.count(before) == 1
    assert main_workspace.replace(before, after, 1) == final_workspace
    assert after in source(initial, workspace).decode()

    script = 'packages/quds_office_editor/example/tool/build_macos_app.sh'
    workflow = '.github/workflows/macos-app-weekly.yml'
    script_bytes, workflow_bytes = source(head, script), source(head, workflow)
    assert (repo / script).read_bytes() == script_bytes
    assert (repo / workflow).read_bytes() == workflow_bytes
    shell = subprocess.run(
        ['bash', '-n'], input=script_bytes, capture_output=True
    )
    assert shell.returncode == 0, shell.stderr.decode()
    parsed = yaml.load(workflow_bytes.decode(), Loader=yaml.BaseLoader)
    assert isinstance(parsed, dict) and set(parsed['jobs']) == {'build', 'signed'}
    fragments = []
    upload_paths = []
    for name, job in parsed['jobs'].items():
        assert job['runs-on'] == 'macos-15'
        assert any(s.get('name') == 'Paths' for s in job['steps'])
        for step in job['steps']:
            if step.get('uses') == 'actions/upload-artifact@v4':
                path = step['with']['path']
                assert '..' not in path
                upload_paths.append({'job': name, 'path': path})
            if 'run' in step:
                # GitHub expressions are substituted by the runner before bash.
                # A neutral token checks shell structure without running jobs.
                text = re.sub(r'\$\{\{.*?\}\}', 'EXPRESSION', step['run'])
                result = subprocess.run(
                    ['bash', '-n'], input=text.encode(), capture_output=True
                )
                assert result.returncode == 0, (name, step.get('name'), result.stderr.decode())
                fragments.append({'job': name, 'step': step.get('name'), 'exit_code': result.returncode})

    out = {
        'schema_version': 1,
        'recorded_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'head': head, 'tree': git('rev-parse', head + '^{tree}').decode().strip(),
        'status': 'passed',
        'scope': 'Immutable incoming-blob preservation and syntax checks only. No macOS build, signing, native execution, or GitHub Actions execution is claimed.',
        'preservation': preservation,
        'combined_paths': {
            distribution: 'All non-documentation lines exactly match current main; portable change is the reviewed stripped-form documentation.',
            workspace: 'Exactly current main plus the previously qualified Zotero-branch transform copyWith replacement; every other byte matches current main.',
        },
        'build_script': {'path': script, 'sha256': hashlib.sha256(script_bytes).hexdigest(), 'command': 'bash -n (exact committed bytes via stdin)', 'exit_code': shell.returncode},
        'workflow': {'path': workflow, 'sha256': hashlib.sha256(workflow_bytes).hexdigest(), 'parser': 'PyYAML BaseLoader', 'jobs': list(parsed['jobs']), 'shell_fragments': fragments, 'upload_paths': upload_paths},
        'verifier_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'github_actions_queried': False,
    }
    output = args.output or here / 'incoming-review.json'
    output.write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps({'head': head, 'status': out['status'], 'reviewed_path_observations': sum(len(x['paths']) for x in preservation), 'workflow_shell_fragments': len(fragments)}, indent=2))


if __name__ == '__main__':
    main()
