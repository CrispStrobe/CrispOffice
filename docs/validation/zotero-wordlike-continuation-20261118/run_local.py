#!/usr/bin/env python3
"""Replay the Zotero continuation's local gates without GitHub Actions.

Use the repository's pinned Flutter SDK, resolve its workspace dependencies,
then run this script with --repo and --output. Gates run sequentially to avoid
SDK shell-wrapper startup races in containers that share a cache and PID space.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    def git(*command):
        return subprocess.check_output(['git', *command], cwd=repo, text=True).strip()

    start_commit = git('rev-parse', 'HEAD')
    if git('status', '--porcelain', '--untracked-files=no'):
        parser.error('Commit tracked changes before running a source-bound gate.')
    lock = repo / 'pubspec.lock'
    recorded_lock = Path(__file__).with_name('workspace-pubspec.lock.txt')
    if not lock.is_file():
        parser.error('Resolve the workspace with the recorded lockfile first.')
    if recorded_lock.is_file() and digest(lock) != digest(recorded_lock):
        parser.error('Use workspace-pubspec.lock.txt and pub get --enforce-lockfile.')
    flutter = Path(shutil.which('flutter') or '').resolve()
    sdk = Path(os.environ.get('FLUTTER_ROOT', flutter.parent.parent)).resolve()
    dart = sdk / 'bin/cache/dart-sdk/bin/dart'
    flutter_tools = sdk / 'bin/cache/flutter_tools.snapshot'
    if not dart.is_file() or not flutter_tools.is_file():
        parser.error('Bootstrap the pinned Flutter SDK first and put it on PATH.')
    flutter_command = [str(dart), str(flutter_tools)]
    version = json.loads(subprocess.check_output(
        flutter_command + ['--version', '--machine'], text=True))
    pinned = json.loads((repo / '.fvmrc').read_text())['flutter']
    if version['frameworkVersion'] != pinned:
        parser.error(f'Expected Flutter {pinned}, got {version["frameworkVersion"]}.')
    editor = repo / 'packages/quds_office_editor'
    engine = repo / 'packages/quds_office_engine'
    studio = editor / 'example'

    def tests(directory, patterns):
        return sorted({str(p.relative_to(directory))
                       for pattern in patterns for p in directory.glob(pattern)})

    tracked = subprocess.check_output(
        ['git', 'ls-files', 'packages/quds_office_engine',
         'packages/quds_office_editor', 'pubspec.yaml', '.fvmrc',
         'analysis_options.yaml'], cwd=repo, text=True).splitlines()
    before = {path: digest(repo / path) for path in tracked}
    runtime_inputs = [dart, flutter_tools, lock, repo / '.dart_tool/package_config.json']
    runtime_before = {str(path): digest(path) for path in runtime_inputs}
    changed = subprocess.check_output(
        ['git', 'diff', '--name-only',
         'b2597485b923003f01c1bd69e02d0c62a6943514', 'HEAD', '--', '*.dart'],
        cwd=repo, text=True).splitlines()
    gates = [
        ('engine', engine, [str(dart), 'test', *tests(engine, [
            'test/*zotero*_test.dart', 'test/word_note_numbering_test.dart']),
            '--reporter', 'expanded', '--concurrency=4']),
        ('editor', editor, [*flutter_command, 'test', '--no-pub', *tests(editor, [
            'test/word_zotero*_test.dart', 'test/word_notes_editing_test.dart',
            'test/word_note_numbering_test.dart', 'test/word_text_proofing*_test.dart',
            'test/word_live_review*_test.dart', 'test/word_review*_test.dart']),
            '--reporter', 'expanded', '--concurrency=4']),
        ('studio', studio, [*flutter_command, 'test', '--no-pub',
            'test/studio_zotero_citing_transport_test.dart', 'test/widget_test.dart',
            'test/studio_comment_review_test.dart', 'test/studio_review_pane_test.dart',
            '--reporter', 'expanded', '--concurrency=2']),
        ('analysis', repo, [str(dart), 'analyze', '--fatal-infos', *changed]),
        ('format', repo, [str(dart), 'format', '--output=none',
            '--set-exit-if-changed', *changed]),
        ('whitespace', repo, ['git', 'diff', '--check',
            'b2597485b923003f01c1bd69e02d0c62a6943514', 'HEAD']),
    ]
    results = []
    for name, directory, command in gates:
        log = output / f'{name}.log'
        start = time.monotonic()
        with log.open('w') as stream:
            completed = subprocess.run(command, cwd=directory,
                                       stdout=stream, stderr=subprocess.STDOUT)
        contents = log.read_text()
        match = re.search(r'\+(\d+): All tests passed!', contents)
        result = dict(name=name, directory=str(directory), command=command,
                      exit_code=completed.returncode, log=log.name,
                      sha256=digest(log), duration_seconds=time.monotonic()-start)
        if match:
            result['passed'] = int(match[1])
        results.append(result)
        print(json.dumps(result), flush=True)
    after = {path: digest(repo / path) for path in tracked}
    mismatches = [path for path in tracked if before[path] != after[path]]
    runtime_mismatches = [str(path) for path in runtime_inputs
                          if runtime_before[str(path)] != digest(path)]
    end_commit = git('rev-parse', 'HEAD')
    end_status = git('status', '--porcelain', '--untracked-files=no')
    summary = dict(
        commit=start_commit, commit_after=end_commit,
        tracked_status_after=end_status,
        runtime=version, dart_sha256=digest(dart),
        workspace_lock_sha256=digest(repo / 'pubspec.lock'),
        source_files=before, source_mismatches=mismatches,
        runtime_inputs=runtime_before, runtime_mismatches=runtime_mismatches,
        results=results, github_actions_used=False,
    )
    (output / 'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    failed = (mismatches or runtime_mismatches or end_status or
              start_commit != end_commit or any(r['exit_code'] for r in results))
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
