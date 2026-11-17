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
import re
from pathlib import Path
import shutil
import signal
import subprocess
import time

REPO = Path(__file__).resolve().parents[3]
ENGINE = ['font_subset_structure_test.dart', 'font_subset_unicode_test.dart', 'pdf_cid_encoding_test.dart', 'pdf_unicode_alias_export_test.dart', 'fonts_test.dart', 'office_named_fonts_test.dart', 'arabic_pdf_export_test.dart', 'office_pdf_export_test.dart', 'pdf_file_test.dart', 'pdf_toolbox_test.dart', 'word_pdf_test.dart', 'pdf_widgets_test.dart', 'pdf_widgets_catalog_test.dart', 'pdf_templates_test.dart', 'pdf_to_office_test.dart', 'bidi_test.dart', 'ods_sheet_writer_test.dart', 'ods_sheet_reader_test.dart', 'legacy_sheet_reader_test.dart']
EDITOR = ['pdf_font_faces_test.dart', 'font_subset_render_test.dart', 'pdf_surface_test.dart', 'pdf_viewer_options_test.dart', 'host_fonts_test.dart', 'word_run_metrics_test.dart', 'paint_run_text_unicode_test.dart', 'paint_font_fallback_test.dart']
ENGINE += ['pdf_actual_text_scope_test.dart', 'pdf_logical_text_export_test.dart',
           'sfnt_cmap_validation_test.dart', 'sheet_conditional_fidelity_test.dart',
           'sheet_rename_fidelity_test.dart', 'sheet_rename_adversarial_test.dart',
           'sheet_formula_test.dart', 'word_small_caps_test.dart',
           'sheet_save_cache_and_freeze_test.dart', 'english_hyphenation_test.dart',
           'german_hyphenation_context_test.dart',
           'proofing/proofing_text_ranges_test.dart',
           'proofing_hyphenation_test.dart', 'proofing/german_spelling_test.dart',
           'proofing/german_writing_rules_test.dart', 'proofing/office_proofing_test.dart',
           'word_run_measure_test.dart', 'word_run_measure_boundaries_test.dart']
EDITOR += ['word_hyphenation_caret_test.dart', 'word_hyphenation_paint_test.dart',
           'word_hyphenation_resume_test.dart', 'word_hyphenation_source_presentation_test.dart',
           'word_shaped_wrap_test.dart', 'word_proofing_correction_test.dart',
           'word_proofing_geometry_test.dart', 'word_proofing_dialog_test.dart',
           'word_proofing_session_test.dart']
HARPER = ['harper_provider_test.dart', 'harper_source_text_test.dart',
          'harper_source_contract_test.dart']
COHORTS = {'engine': ('quds_office_engine', ENGINE),
           'editor': ('quds_office_editor', EDITOR),
           'harper': ('quds_proofing_harper', HARPER)}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO).decode().strip()

def analysis_paths(package_name, tests):
    package = REPO / 'packages' / package_name
    changed = [p for p in git('diff', '--name-only', '51cc65f1dc7ec860c0ff7324b73adda9d70a86ef', '--',
                            f'packages/{package_name}').splitlines()
               if p.endswith('.dart')]
    untracked = set(git('ls-files', '--others', '--exclude-standard').splitlines())
    changed += [str(p.relative_to(REPO)) for p in package.rglob('*.dart')
                if str(p.relative_to(REPO)) in untracked]
    relative = [str((REPO / p).relative_to(package)) for p in sorted(set(changed))]
    if not relative:
        relative = sorted({str(p.relative_to(package))
                           for p in (package / 'lib').rglob('*.dart')}
                          | {'test/' + p for p in tests})
    return relative

def inputs(cohort, tests):
    paths = set()
    packages = ['quds_office_engine', 'legacy_doc_parser']
    if cohort == 'editor':
        packages.append('quds_office_editor')
    if cohort in ('editor', 'harper'):
        packages.append('quds_proofing_harper')
    for package in packages:
        paths.update((REPO / 'packages' / package / 'lib').rglob('*.dart'))
    package = REPO / 'packages' / COHORTS[cohort][0]
    paths.update(package / 'test' / test for test in tests)
    paths.update(package / p for p in analysis_paths(COHORTS[cohort][0], tests))
    paths.update((package / 'test' / 'support').rglob('*.dart'))
    # Include relative test/example/part imports in the executed source closure.
    pending = list(paths)
    seen = set()
    while pending:
        current = pending.pop()
        if current in seen or not current.is_file() or current.suffix != '.dart':
            continue
        seen.add(current)
        for uri in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", current.read_text()):
            if ':' in uri:
                continue
            dependency = (current.parent / uri).resolve()
            if dependency.is_relative_to(REPO) and dependency.is_file():
                paths.add(dependency)
                pending.append(dependency)
    # Binary fixtures are runtime inputs even when they are not Dart imports.
    paths.update(p for p in (REPO / 'packages/quds_office_engine/test/fixtures').rglob('*') if p.is_file())
    paths.update((REPO / 'packages/quds_office_editor/fonts').glob('*.ttf'))
    cairo = REPO / 'packages/quds_office_editor/example/fonts/Cairo-Regular.ttf'
    if cairo.is_file():
        paths.add(cairo)
    paths.update(REPO.glob('pubspec.*'))
    paths.update((REPO / 'packages').glob('*/pubspec.yaml'))
    paths.update((REPO / 'apps').glob('*/pubspec.yaml'))
    paths.add(REPO / '.dart_tool/package_config.json')
    paths.update(REPO.glob('analysis_options.yaml'))
    for parent in ('packages', 'apps'):
        paths.update((REPO / parent).glob('*/analysis_options.yaml'))
        paths.update((REPO / parent).glob('*/dart_test.yaml'))
        paths.update((REPO / parent).glob('*/test/flutter_test_config.dart'))
    paths.update(REPO.glob('dart_test.yaml'))
    return {str(p.relative_to(REPO)): sha(p.read_bytes()) for p in sorted(paths) if p.is_file()}

OPTIONAL_INPUTS = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
    '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf',
    '/home/mohammed/Desktop/al_tahreer_profile.pdf',
]

def optional_inputs():
    paths = [Path(p) for p in OPTIONAL_INPUTS]
    paths.append(REPO / 'packages/quds_office_editor/example/fonts/Cairo-Regular.ttf')
    return {str(p): sha(p.read_bytes()) if p.is_file() else None for p in paths}

def runtime_identity():
    launchers = {}
    for name in ('dart', 'flutter'):
        located = shutil.which(name)
        if located:
            path = Path(located).absolute()
            launchers[name] = {'path': str(path), 'resolved_path': str(path.resolve()),
                               'sha256': sha(path.read_bytes())}
    root = Path(os.environ['FLUTTER_ROOT'])
    members = ['bin/cache/dart-sdk/bin/dart',
               'bin/cache/artifacts/engine/linux-x64/flutter_tester']
    return {'launchers': launchers,
            'sdk_executables_sha256': {p: sha((root / p).read_bytes()) for p in members},
            'environment': {key: os.environ.get(key) for key in
                            ('FLUTTER_ROOT', 'PUB_CACHE', 'CI',
                             'DART_SUPPRESS_ANALYTICS', 'FLUTTER_SUPPRESS_ANALYTICS')}}

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
    parser.add_argument('--cohort', choices=list(COHORTS), required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--flutter', default='flutter', help='Flutter CLI executable or verified offline launcher')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    package_name, tests = COHORTS[args.cohort]
    package = REPO / 'packages' / package_name
    before = inputs(args.cohort, tests)
    optional_before = optional_inputs()
    runtime_before = runtime_identity()
    receipt = {'started_utc': now(), 'cohort': args.cohort,
               'head_before': git('rev-parse', 'HEAD'),
               'working_status_before': git('status', '--porcelain'),
               'source_before_sha256': before, 'tests': tests,
               'optional_before_sha256': optional_before,
               'runtime_before': runtime_before,
               'harness_sha256': sha(Path(__file__).read_bytes()),
               'commands': [], 'github_actions': 'No Actions access.'}
    relative = analysis_paths(package_name, tests)
    receipt['analysis_and_format_paths'] = relative
    test_command = (['dart', 'test'] if args.cohort != 'editor'
                    else [args.flutter, 'test', '--no-pub', '--dart-define=QUDS_SUBSET_RENDER_OUTPUT=' + str(output / 'render')])
    commands = [('tests', test_command + ['--reporter', 'json'] + ['test/' + p for p in tests]),
                ('analyze', ['dart', 'analyze', '--fatal-infos'] + relative),
                ('format', ['dart', 'format', '--output=none', '--set-exit-if-changed'] + relative)]
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    (output / 'validate-used.py').write_bytes(Path(__file__).read_bytes())
    for name, command in commands:
        executable = shutil.which(command[0])
        if not executable:
            raise RuntimeError('Executable not found: ' + command[0])
        command[0] = str(Path(executable).absolute())
        executable_sha256 = sha(Path(command[0]).read_bytes())
        start = time.monotonic()
        timeout = 120 if name == 'format' else 900
        timed_out = False
        raw_stdout = output / f'{name}.stdout'
        raw_stderr = output / f'{name}.stderr'
        print(json.dumps({'name': name, 'status': 'starting', 'timeout_seconds': timeout}), flush=True)
        with raw_stdout.open('wb') as out, raw_stderr.open('wb') as err:
            env = dict(os.environ, QUDS_ALIAS_RENDER_OUTPUT=str(output / 'render'),
                       QUDS_LOGICAL_RENDER_OUTPUT=str(output / 'logical-render'))
            process = subprocess.Popen(command, cwd=package, stdout=out, stderr=err,
                                       env=env, start_new_session=True)
            while True:
                remaining = timeout - (time.monotonic() - start)
                try:
                    exit_code = process.wait(timeout=max(0, min(60, remaining)))
                    break
                except subprocess.TimeoutExpired:
                    if remaining > 0:
                        print(json.dumps({'name': name, 'status': 'running',
                                          'elapsed_seconds': round(time.monotonic() - start, 1)}), flush=True)
                        continue
                    timed_out = True
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    exit_code = 124
                    break
        stdout_bytes = raw_stdout.read_bytes()
        stderr_bytes = raw_stderr.read_bytes()
        stdout = f'{name}.stdout.gz'
        stderr = f'{name}.stderr.gz'
        (output / stdout).write_bytes(gzip.compress(stdout_bytes, mtime=0))
        (output / stderr).write_bytes(gzip.compress(stderr_bytes, mtime=0))
        item = {'name': name, 'command': command, 'cwd': str(package),
                'executable_sha256': executable_sha256,
                'executable_after_sha256': sha(Path(command[0]).read_bytes()),
                'exit_code': exit_code, 'duration_seconds': time.monotonic() - start,
                'timeout_seconds': timeout, 'timed_out': timed_out,
                'test_artifact_directory': str(output / 'render'),
                'stdout': stdout, 'stderr': stderr,
                'stdout_sha256': sha(stdout_bytes), 'stderr_sha256': sha(stderr_bytes)}
        if name == 'tests':
            item['summary'] = summarize_events(stdout_bytes)
        receipt['commands'].append(item)
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        raw_stdout.unlink()
        raw_stderr.unlink()
        print(json.dumps({'name': name, 'exit_code': exit_code,
                          'summary': item.get('summary')}), flush=True)
    after = inputs(args.cohort, tests)
    optional_after = optional_inputs()
    runtime_after = runtime_identity()
    receipt.update({'finished_utc': now(), 'head_after': git('rev-parse', 'HEAD'),
                    'working_status_after': git('status', '--porcelain'),
                    'source_after_sha256': after,
                    'optional_after_sha256': optional_after,
                    'runtime_after': runtime_after,
                    'inputs_unchanged': before == after and optional_before == optional_after
                                        and runtime_before == runtime_after})
    receipt['runtime_lock_sha256'] = sha((REPO / 'pubspec.lock').read_bytes())
    receipt['passed'] = (receipt['inputs_unchanged']
                         and all(c['exit_code'] == 0 and c['executable_sha256'] == c['executable_after_sha256']
                                 for c in receipt['commands'])
                         and receipt['commands'][0]['summary']['runner_success']
                         and not receipt['commands'][0]['summary']['failures']
                         and not receipt['commands'][0]['summary']['skipped']
                         and not receipt['commands'][0]['summary']['errors'])
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'passed': receipt['passed'], 'inputs_unchanged': before == after,
                      'input_count': len(before)}), flush=True)
    raise SystemExit(0 if receipt['passed'] else 1)

if __name__ == '__main__':
    main()
