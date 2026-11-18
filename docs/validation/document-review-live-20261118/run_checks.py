"""Run local live-review regressions with an already prepared Flutter SDK.

Activate the pinned runtime/cache first. This script never invokes GitHub or
downloads dependencies. Its JSON reports bind results to the source files.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EDITOR = ROOT / 'packages/quds_office_editor'
STUDIO = EDITOR / 'example'
CHECKS = HERE / 'checks'
EDITOR_TESTS = [
    'word_live_proofing_session_test.dart',
    'word_live_review_selection_test.dart',
    'word_live_review_surface_test.dart',
    'word_review_pane_test.dart',
    'word_proofing_session_test.dart',
    'word_manual_proofing_test.dart',
    'word_proofing_dialog_test.dart',
    'word_proofing_context_test.dart',
    'word_proofing_geometry_test.dart',
    'word_proofing_navigation_test.dart',
    'word_review_dialog_test.dart',
    'word_revision_story_test.dart',
    'word_input_focus_test.dart',
    'office_input_ownership_test.dart',
    'editor_test.dart',
    'word_zotero_stored_details_dialog_test.dart',
    'word_zotero_stored_details_test.dart',
]
STUDIO_TESTS = [
    'studio_review_pane_test.dart',
    'widget_test.dart',
    'studio_document_comparison_test.dart',
]


def git(*args: str) -> str:
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def source_hashes() -> dict[str, str]:
    selected_tests = {
        *(str((EDITOR / 'test' / name).relative_to(ROOT)) for name in EDITOR_TESTS),
        *(str((STUDIO / 'test' / name).relative_to(ROOT)) for name in STUDIO_TESTS),
    }
    paths = git('ls-files').splitlines()
    return {
        name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        for name in paths
        if name in selected_tests
        or name in {'pubspec.yaml', 'analysis_options.yaml', '.fvmrc'}
        or (name.startswith(('packages/', 'apps/')) and (
            ('/lib/' in name and name.endswith('.dart'))
            or name.endswith(('/pubspec.yaml', '/analysis_options.yaml'))
            or ('/assets/fonts/' in name and name.endswith(('.ttf', '.otf')))
        ))
    }


def run(name: str, command: list[str], cwd: Path, *, tests: bool = False) -> dict[str, object]:
    started = time.time()
    env = dict(os.environ)
    env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
    path = CHECKS / (name + ('.jsonl' if tests else '.log'))
    with path.open('w') as output:
        completed = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT)
    result: dict[str, object] = {
        'name': name,
        'command': command,
        'cwd': str(cwd.relative_to(ROOT)),
        'exit_code': completed.returncode,
        'elapsed_seconds': round(time.time() - started, 3),
        'log': str(path.relative_to(HERE)),
        'log_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    }
    if tests:
        cases: dict[int, dict[str, object]] = {}
        hidden = 0
        done = None
        for line in path.read_text().splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get('type') == 'testStart':
                test = event['test']
                cases[test['id']] = {'name': test['name'], 'suite_id': test['suiteID']}
            elif event.get('type') == 'testDone':
                if event.get('hidden', False):
                    hidden += 1
                    cases.pop(event['testID'], None)
                elif event['testID'] in cases:
                    cases[event['testID']].update(result=event['result'], skipped=event['skipped'])
            elif event.get('type') == 'done':
                done = event.get('success')
        result.update(
            passed=sum(c.get('result') == 'success' and not c.get('skipped') for c in cases.values()),
            failed=sum(c.get('result') in {'error', 'failure'} for c in cases.values()),
            skipped=sum(bool(c.get('skipped')) for c in cases.values()),
            hidden_events_excluded=hidden,
            reporter_success=done,
        )
        (CHECKS / (name + '-cases.json')).write_text(json.dumps(list(cases.values()), indent=2) + '\n')
    print(json.dumps(result), flush=True)
    return result


def main() -> None:
    CHECKS.mkdir(exist_ok=True)
    before = source_hashes()
    (HERE / 'source-sha256.json').write_text(json.dumps(before, indent=2) + '\n')
    source_commit = git('rev-parse', 'HEAD')
    runs = [
        run('editor', ['flutter', 'test', '--no-pub', '--reporter', 'json',
                       *(f'test/{name}' for name in EDITOR_TESTS)], EDITOR, tests=True),
        run('studio', ['flutter', 'test', '--no-pub', '--reporter', 'json',
                       *(f'test/{name}' for name in STUDIO_TESTS)], STUDIO, tests=True),
    ]
    dart_paths = git('diff', '--name-only', '3840e19ff949f5fc03ecf1ec30ab0a71f67e8c68', 'HEAD', '--', '*.dart').splitlines()
    # Validation fixtures in docs are historical evidence, not package sources.
    dart_paths = [name for name in dart_paths if name.startswith(('packages/', 'apps/'))]
    runs.append(run('analysis', ['dart', 'analyze', '--fatal-infos', *dart_paths], ROOT))
    runs.append(run('format', ['dart', 'format', '--output=none', '--set-exit-if-changed', *dart_paths], ROOT))
    runs.append(run('whitespace', ['git', 'diff', '--check', '3840e19ff949f5fc03ecf1ec30ab0a71f67e8c68', 'HEAD'], ROOT))
    after = source_hashes()
    result = {
        'source_commit': source_commit,
        'source_tree': git('rev-parse', f'{source_commit}^{{tree}}'),
        'source_file_count': len(before),
        'source_manifest': 'source-sha256.json',
        'source_unchanged_during_checks': before == after,
        'workspace_lock_sha256': hashlib.sha256((ROOT / 'pubspec.lock').read_bytes()).hexdigest(),
        'runs': runs,
        'github_actions_queried_or_awaited': False,
        'passed': sum(int(r.get('passed', 0)) for r in runs),
        'skipped': sum(int(r.get('skipped', 0)) for r in runs),
    }
    result['success'] = before == after and all(
        r['exit_code'] == 0 and r.get('reporter_success', True) is True
        and r.get('failed', 0) == 0 and r.get('skipped', 0) == 0
        for r in runs
    )
    (HERE / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'success': result['success'], 'passed': result['passed'], 'skipped': result['skipped']}))
    raise SystemExit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()
