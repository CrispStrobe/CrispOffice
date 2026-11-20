#!/usr/bin/env python3
"""Run local, source-bound host/integration cohorts without hosted CI."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/mail'))
from check_store import execute, test_summary  # noqa: E402


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs() -> dict[str, str]:
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    selected = [ROOT / name for name in names if name and (
        name.endswith(('.dart', '.yaml', '.yml')) or name in
        ('.fvmrc', '.cursorrules', 'CONTRIBUTING.md', 'pubspec.lock',
         'tools/mail/check_store.py', 'tools/mail/check_reader.py'))]
    selected.append(Path(__file__).resolve())
    return {str(path.relative_to(ROOT)): sha(path) for path in sorted(set(selected))
            if path.is_file()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-sdk', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--phase', choices=('broad', 'mail-final', 'office-final'), default='broad')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dart = str(args.flutter_sdk.resolve() / 'bin/cache/dart-sdk/bin/dart')
    flutter = str(args.flutter_sdk.resolve() / 'bin/flutter')
    studio = ROOT / 'packages/quds_office_editor/example'
    editor = ROOT / 'packages/quds_office_editor'
    engine = ROOT / 'packages/quds_office_engine'
    studio_tests = sorted(str(path.relative_to(studio)) for path in (studio / 'test').glob('*_test.dart')
                          if path.name.startswith(('studio_mail', 'studio_saved_mail', 'studio_credential')))
    automation = sorted({str(path.relative_to(engine)) for pattern in
                         ('office_macro*_test.dart', 'office_vba*_test.dart')
                         for path in (engine / 'test').glob(pattern)})
    # Each case belongs to one cohort; focused development reruns are recorded separately.
    commands = [
        ('studio-mail', [flutter, 'test', '--no-pub', '--concurrency=2', '--reporter', 'json', *studio_tests], studio, True),
        ('shared-mail-ui', [flutter, 'test', '--no-pub', '--concurrency=2', '--reporter', 'json'], ROOT / 'packages/quds_mail_ui', True),
        ('mime-transport', [dart, 'test', '--concurrency=2', '--reporter', 'json',
                            'packages/quds_mail_mime/test', 'packages/quds_mail_transport/test'], ROOT, True),
        ('incoming-automation', [dart, 'test', '--concurrency=2', '--reporter', 'json', *automation], engine, True),
        ('incoming-zotero', [flutter, 'test', '--no-pub', '--reporter', 'json',
                             'test/word_zotero_add_note_controller_test.dart'], editor, True),
        ('incoming-automation-analysis', [dart, 'analyze', '--fatal-infos',
            'lib/src/automation', 'test/office_macro_word_list_format_test.dart',
            'test/office_vba_word_lists_integration_test.dart', 'test/office_vba_word_lists_test.dart',
            'tool/macros/web_vba_word_lists_smoke.dart'], engine, False),
        ('incoming-word-browser-compile', [dart, 'compile', 'js', 'tool/macros/web_vba_word_lists_smoke.dart',
                                           '-o', str(output / 'word-lists.js')], engine, False),
        ('incoming-word-node', ['node', str(output / 'word-lists.js')], engine, False),
    ]
    if args.phase == 'mail-final':
        changed = subprocess.check_output(
            ['git', 'diff', '--name-only', '5c48058bedc42dd8cbf3fb9d6f1fb492b2ac1eb8', 'HEAD'],
            cwd=ROOT, text=True).splitlines()
        dart_files = sorted(name for name in changed if name.endswith('.dart'))
        mail_files = [name for name in dart_files if name.startswith(
            ('packages/quds_mail_store/', 'packages/quds_office_editor/example/'))]
        commands = [commands[0],
                    ('mail-analysis', [dart, 'analyze', '--fatal-infos', *mail_files], ROOT, False),
                    ('changed-format', [dart, 'format', '--output=none', '--set-exit-if-changed', *dart_files], ROOT, False)]
    elif args.phase == 'office-final':
        cli_files = ['test/office_macro_cli_test.dart', 'test/office_vba_arguments_integration_test.dart',
                     'test/office_vba_powerpoint_cli_test.dart', 'test/office_vba_word_cli_test.dart']
        word_files = ['test/office_macro_word_list_format_test.dart', 'test/office_vba_word_lists_test.dart',
                      'test/office_vba_word_lists_integration_test.dart', 'test/style_cascade_test.dart',
                      'test/numbering_collision_test.dart', 'test/word_list_numbering_snapshot_test.dart',
                      'test/word_styles_layout_test.dart', 'test/word_style_introduction_test.dart',
                      'test/office_macro_word_tab_stops_test.dart']
        # Retest complete affected CLI files; only the runner time allowance
        # changes. Assertions, input/output checks and test source stay intact.
        cli = ('automation-cli-retry', [dart, 'test', '--timeout=120s', '--concurrency=2',
                                        '--reporter', 'json', *cli_files], engine, True)
        word = ('word-preservation', [dart, 'test', '--concurrency=2', '--reporter', 'json', *word_files], engine, True)
        analysis = ('reviewed-word-analysis', [dart, 'analyze', '--fatal-infos', 'lib/src/automation',
                    'lib/src/word/serial/word_style_cascade.dart', 'test/office_macro_word_list_format_test.dart',
                    'test/office_vba_word_lists_test.dart', 'test/office_vba_word_lists_integration_test.dart',
                    'tool/macros/web_vba_word_lists_smoke.dart'], engine, False)
        commands = [cli, word, commands[4], analysis, commands[6], commands[7]]
    receipt = dict(status='RUNNING', phase=args.phase, started_at=datetime.now(timezone.utc).isoformat(),
                   source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                   source_tree=subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=ROOT, text=True).strip(),
                   source_before=inputs(), github_actions='NOT USED', checks=[])
    receipt_file = output / 'receipt.json'

    def save() -> None:
        receipt_file.write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    env = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
    accepted = True
    try:
        for name, command, cwd, is_tests in commands:
            print(name, flush=True)
            log = output / (name + ('.jsonl' if is_tests else '.log'))
            error_log = output / (name + '.stderr')
            check = dict(name=name, command=command, cwd=str(cwd), status='RUNNING', log=log.name,
                         stderr=error_log.name, timeout_seconds=900)
            receipt['checks'].append(check)
            save()
            with log.open('wb') as stream, error_log.open('wb') as errors:
                check['exit_code'] = execute(command, cwd=cwd, env=env, stdout=stream, stderr=errors, timeout=900)
            ok = check['exit_code'] == 0
            if is_tests:
                summary = test_summary(log)
                case_file = output / (name + '-cases.json')
                case_file.write_text(json.dumps(summary, indent=2) + '\n')
                check['tests'] = {key: value for key, value in summary.items() if key != 'cases'}
                check['case_list'] = case_file.name
                ok = ok and bool(summary['valid'])
            check['log_sha256'] = sha(log)
            check['stderr_sha256'] = sha(error_log)
            check['status'] = 'PASS' if ok else 'FAIL'
            accepted = accepted and ok
            save()
        receipt['status'] = 'PASS' if accepted else 'FAIL'
    except (Exception, KeyboardInterrupt) as error:
        receipt['status'] = 'FAIL'
        receipt['error'] = f'{type(error).__name__}: {error}'
    finally:
        receipt['source_after'] = inputs()
        receipt['source_unchanged'] = receipt['source_before'] == receipt['source_after']
        if not receipt['source_unchanged']:
            receipt['status'] = 'FAIL'
        receipt['finished_at'] = datetime.now(timezone.utc).isoformat()
        save()
    print(receipt['status'], flush=True)
    return 0 if receipt['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
