#!/usr/bin/env python3
"""Render the repository visual fixture serially; retain exact run evidence."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path('/workspace/scratch/4a0b7fce84dc')
REPO = ROOT / 'quds_office_suite'
EXAMPLE = REPO / 'packages/quds_office_editor/example'
FIXTURE = REPO / 'docs/validation/document-review-drafts-20261118/render_comments.dart'
TEMPORARY = EXAMPLE / 'test/review_drafts_visual_fixture_test.dart'
RUNTIME = ROOT / 'toolchains'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*arguments):
    return subprocess.check_output(['git', '-C', str(REPO), *arguments], text=True).strip()


def snapshot():
    names = [
        'packages/quds_office_editor/example/lib/suite_workspace.dart',
        'packages/quds_office_editor/example/lib/studio_chrome.dart',
        'packages/quds_office_editor/lib/src/embed/office_controller.dart',
        'packages/quds_office_editor/lib/src/embed/office_editors.dart',
        'packages/quds_office_editor/lib/src/proofing/word_proofing.dart',
        str(FIXTURE.relative_to(REPO)),
    ]
    return {name: digest(REPO / name) for name in names}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--head')
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise RuntimeError('Choose a new output directory to retain prior attempts.')
    if TEMPORARY.exists():
        raise RuntimeError('Temporary fixture path is already occupied.')
    head = git('rev-parse', 'HEAD')
    if args.head and head != args.head:
        raise RuntimeError('HEAD differs from requested frozen source.')
    output.mkdir(parents=True, exist_ok=True)
    images = output / 'screenshots'
    images.mkdir()
    env = dict(os.environ)
    env.update(
        PUB_CACHE=str(RUNTIME / 'pub-cache'),
        FLUTTER_ROOT=str(RUNTIME / 'flutter'),
        CI='true',
        DART_SUPPRESS_ANALYTICS='true',
        FLUTTER_SUPPRESS_ANALYTICS='true',
        DASH__SUPPRESS_ANALYTICS='true',
        XDG_CONFIG_HOME=str(RUNTIME / 'config'),
        XDG_CACHE_HOME=str(RUNTIME / 'cache'),
        XDG_DATA_HOME=str(RUNTIME / 'data'),
        TMPDIR=str(RUNTIME / 'tmp'),
        QUDS_REVIEW_VISUAL_OUTPUT=str(images),
        PATH=str(RUNTIME / 'bin') + os.pathsep + env.get('PATH', ''),
    )
    command = [str(RUNTIME / 'bin/flutter'), 'test', '--no-pub', '--concurrency=1', '--reporter=json', 'test/' + TEMPORARY.name]
    record = {
        'source_commit': head,
        'source_tree': git('rev-parse', 'HEAD^{tree}'),
        'tracked_status_before': git('status', '--porcelain=v1', '--untracked-files=no'),
        'source_before': snapshot(),
        'command': command,
        'cwd': str(EXAMPLE),
        'runtime_receipt_sha256': digest(RUNTIME / 'runtime.json'),
        'github_actions_queried_or_awaited': False,
    }
    started = time.monotonic()
    log = output / 'visuals.jsonl'
    try:
        shutil.copyfile(FIXTURE, TEMPORARY)
        with log.open('wb') as stream:
            result = subprocess.run(command, cwd=EXAMPLE, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=900)
        record['exit_code'] = result.returncode
    except BaseException as error:
        record['runner_error'] = repr(error)
        record['exit_code'] = 1
    finally:
        TEMPORARY.unlink(missing_ok=True)
        record.update(
            elapsed_seconds=round(time.monotonic() - started, 3),
            source_after=snapshot(),
            source_head_after=git('rev-parse', 'HEAD'),
            tracked_status_after=git('status', '--porcelain=v1', '--untracked-files=no'),
        )
    tests = {}
    cases = []
    errors = []
    reporter_success = None
    if log.exists():
        for line in log.read_text(errors='replace').splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get('type') == 'testStart':
                tests[event['test']['id']] = event['test']['name']
            elif event.get('type') == 'testDone' and not event.get('hidden'):
                cases.append(dict(name=tests.get(event['testID']), result=event['result'], skipped=event['skipped']))
            elif event.get('type') == 'error':
                errors.append(event)
            elif event.get('type') == 'done':
                reporter_success = event['success']
        (output / 'visuals.jsonl.gz').write_bytes(gzip.compress(log.read_bytes(), mtime=0))
    record.update(
        cases=cases,
        errors=errors,
        reporter_success=reporter_success,
        passed=sum(case['result'] == 'success' and not case['skipped'] for case in cases),
        failed=sum(case['result'] != 'success' for case in cases),
        skipped=sum(case['skipped'] for case in cases),
        images=[dict(file=str(path.relative_to(output)), bytes=path.stat().st_size, sha256=digest(path)) for path in sorted(images.glob('*.png'))],
    )
    record['source_unchanged'] = record['source_before'] == record['source_after'] and record['source_commit'] == record['source_head_after']
    record['success'] = record['exit_code'] == 0 and reporter_success is True and record['passed'] == 3 and not errors and record['source_unchanged'] and len(record['images']) == 3
    (output / 'verification.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({key: record[key] for key in ('success', 'passed', 'failed', 'skipped', 'source_unchanged', 'exit_code', 'images')}, indent=2))
    return 0 if record['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
