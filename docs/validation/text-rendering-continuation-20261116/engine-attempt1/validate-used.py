#!/usr/bin/env python3
"""Run scoped local gates and record source-bound evidence, without CI access.

Activate a genuine locked Dart/Flutter workspace before running. Output is
written to the specified directory; each invocation is a separate receipt.
"""
import argparse
import collections
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

REPO = Path(__file__).resolve().parents[3]
ENGINE = ['font_subset_structure_test.dart', 'font_subset_unicode_test.dart', 'pdf_cid_encoding_test.dart', 'pdf_unicode_alias_export_test.dart', 'fonts_test.dart', 'office_named_fonts_test.dart', 'arabic_pdf_export_test.dart', 'office_pdf_export_test.dart', 'pdf_file_test.dart', 'pdf_toolbox_test.dart', 'word_pdf_test.dart', 'pdf_widgets_test.dart', 'pdf_widgets_catalog_test.dart', 'pdf_templates_test.dart', 'pdf_to_office_test.dart', 'bidi_test.dart', 'ods_sheet_writer_test.dart']
EDITOR = ['pdf_font_faces_test.dart', 'font_subset_render_test.dart', 'pdf_surface_test.dart', 'pdf_viewer_options_test.dart', 'host_fonts_test.dart', 'word_run_metrics_test.dart', 'paint_run_text_unicode_test.dart', 'paint_font_fallback_test.dart']

def sha(data):
    return hashlib.sha256(data).hexdigest()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO).decode().strip()

def inputs(cohort, tests):
    paths = set()
    packages = ['quds_office_engine', 'legacy_doc_parser']
    if cohort == 'editor':
        packages.append('quds_office_editor')
    for package in packages:
        paths.update((REPO / 'packages' / package / 'lib').rglob('*.dart'))
    package = REPO / 'packages' / f'quds_office_{cohort}'
    paths.update(package / 'test' / test for test in tests)
    paths.update((package / 'test' / 'support').rglob('*.dart'))
    paths.update((REPO / 'packages/quds_office_editor/fonts').glob('*.ttf'))
    paths.update(REPO.glob('pubspec.*'))
    paths.update((REPO / 'packages').glob('*/pubspec.yaml'))
    paths.update((REPO / 'apps').glob('*/pubspec.yaml'))
    paths.add(REPO / '.dart_tool/package_config.json')
    return {str(p.relative_to(REPO)): sha(p.read_bytes()) for p in sorted(paths) if p.is_file()}

def summarize_events(raw):
    events = []
    for line in raw.decode(errors='replace').splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict):
            events.append(value)
    starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    results = collections.Counter()
    failures = []
    skipped = []
    for event in events:
        if event.get('type') != 'testDone' or event.get('hidden'):
            continue
        name = starts.get(event['testID'], {}).get('name', str(event['testID']))
        outcome = 'skipped' if event.get('skipped') else event.get('result', 'unknown')
        results[outcome] += 1
        if outcome != 'success':
            (skipped if outcome == 'skipped' else failures).append(name)
    done = [e for e in events if e.get('type') == 'done']
    return {'outcomes': dict(results), 'failures': failures, 'skipped': skipped,
            'errors': [e for e in events if e.get('type') == 'error'],
            'runner_success': bool(done and done[-1].get('success'))}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cohort', choices=['engine', 'editor'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    tests = ENGINE if args.cohort == 'engine' else EDITOR
    package = REPO / 'packages' / f'quds_office_{args.cohort}'
    before = inputs(args.cohort, tests)
    receipt = {'started_utc': now(), 'cohort': args.cohort,
               'head_before': git('rev-parse', 'HEAD'),
               'working_status_before': git('status', '--porcelain'),
               'source_before_sha256': before, 'tests': tests,
               'harness_sha256': sha(Path(__file__).read_bytes()),
               'commands': [], 'github_actions': 'No Actions access.'}
    changed = [p for p in git('diff', '--name-only', '0d19b16e10c6bc8492f47880321df2d9f2561223', '--',
                            f'packages/quds_office_{args.cohort}').splitlines()
               if p.endswith('.dart')]
    untracked = set(git('ls-files', '--others', '--exclude-standard').splitlines())
    changed += [str(p.relative_to(REPO)) for p in package.rglob('*.dart')
                if str(p.relative_to(REPO)) in untracked]
    changed = sorted(set(changed))
    relative = [str((REPO / p).relative_to(package)) for p in changed]
    test_command = (['dart', 'test'] if args.cohort == 'engine'
                    else ['flutter', 'test', '--no-pub', '--dart-define=QUDS_SUBSET_RENDER_OUTPUT=' + str(output / 'render')])
    commands = [('tests', test_command + ['--reporter', 'json'] + ['test/' + p for p in tests]),
                ('analyze', ['dart', 'analyze', '--fatal-infos'] + relative),
                ('format', ['dart', 'format', '--output=none', '--set-exit-if-changed'] + relative)]
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    (output / 'validate-used.py').write_bytes(Path(__file__).read_bytes())
    for name, command in commands:
        start = time.monotonic()
        raw_stdout = output / f'{name}.stdout'
        raw_stderr = output / f'{name}.stderr'
        with raw_stdout.open('wb') as out, raw_stderr.open('wb') as err:
            env = dict(os.environ, QUDS_ALIAS_RENDER_OUTPUT=str(output / 'render'))
            result = subprocess.run(command, cwd=package, stdout=out, stderr=err, env=env)
        stdout_bytes = raw_stdout.read_bytes()
        stderr_bytes = raw_stderr.read_bytes()
        stdout = f'{name}.stdout.gz'
        stderr = f'{name}.stderr.gz'
        (output / stdout).write_bytes(gzip.compress(stdout_bytes, mtime=0))
        (output / stderr).write_bytes(gzip.compress(stderr_bytes, mtime=0))
        item = {'name': name, 'command': command, 'cwd': str(package),
                'exit_code': result.returncode, 'duration_seconds': time.monotonic() - start,
                'test_artifact_directory': str(output / 'render'),
                'stdout': stdout, 'stderr': stderr,
                'stdout_sha256': sha(stdout_bytes), 'stderr_sha256': sha(stderr_bytes)}
        if name == 'tests':
            item['summary'] = summarize_events(stdout_bytes)
        receipt['commands'].append(item)
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        raw_stdout.unlink()
        raw_stderr.unlink()
        print(json.dumps({'name': name, 'exit_code': result.returncode,
                          'summary': item.get('summary')}), flush=True)
    after = inputs(args.cohort, tests)
    receipt.update({'finished_utc': now(), 'head_after': git('rev-parse', 'HEAD'),
                    'working_status_after': git('status', '--porcelain'),
                    'source_after_sha256': after, 'inputs_unchanged': before == after})
    receipt['passed'] = (before == after and all(c['exit_code'] == 0 for c in receipt['commands'])
                         and receipt['commands'][0]['summary']['runner_success'])
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'passed': receipt['passed'], 'inputs_unchanged': before == after,
                      'input_count': len(before)}), flush=True)
    raise SystemExit(0 if receipt['passed'] else 1)

if __name__ == '__main__':
    main()
