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
from urllib.parse import unquote, urljoin, urlparse

REPO = Path(__file__).resolve().parents[3]
BASELINE = '57bc0f98eb94997b73f22cc267bd8d61dccaee59'
LOCK_REFERENCE = REPO / 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
EXPECTED_RUNTIME = {'flutter': '3.47.8', 'dart': '3.13.7',
                    'framework_revision': '737ba8f885dc774b53b442759999a312c9461e4e'}
ENGINE = ['font_subset_structure_test.dart',
 'font_subset_unicode_test.dart',
 'pdf_cid_encoding_test.dart',
 'pdf_unicode_alias_export_test.dart',
 'fonts_test.dart',
 'office_named_fonts_test.dart',
 'arabic_pdf_export_test.dart',
 'office_pdf_export_test.dart',
 'pdf_file_test.dart',
 'pdf_toolbox_test.dart',
 'word_pdf_test.dart',
 'pdf_widgets_test.dart',
 'pdf_widgets_catalog_test.dart',
 'pdf_templates_test.dart',
 'pdf_to_office_test.dart',
 'bidi_test.dart',
 'ods_sheet_writer_test.dart',
 'ods_sheet_reader_test.dart',
 'legacy_sheet_reader_test.dart',
 'pdf_actual_text_scope_test.dart',
 'pdf_logical_text_export_test.dart',
 'sfnt_cmap_validation_test.dart',
 'sheet_conditional_fidelity_test.dart',
 'sheet_rename_fidelity_test.dart',
 'sheet_rename_adversarial_test.dart',
 'sheet_formula_test.dart',
 'word_small_caps_test.dart',
 'sheet_save_cache_and_freeze_test.dart',
 'english_hyphenation_test.dart',
 'german_hyphenation_context_test.dart',
 'proofing/proofing_text_ranges_test.dart',
 'proofing_hyphenation_test.dart',
 'proofing/german_spelling_test.dart',
 'proofing/german_writing_rules_test.dart',
 'proofing/office_proofing_test.dart',
 'word_run_measure_test.dart',
 'word_run_measure_boundaries_test.dart',
 'sheet_authored_number_format_test.dart',
 'sheet_cell_state_preservation_test.dart',
 'sheet_comments_namespace_test.dart',
 'sheet_comments_schema_test.dart',
 'sheet_conditional_rendering_test.dart',
 'sheet_conditional_style_priority_integration_test.dart',
 'sheet_explicit_style_fidelity_test.dart',
 'sheet_fill_fidelity_test.dart',
 'sheet_formula_cache_fidelity_test.dart',
 'sheet_formula_dependency_cache_test.dart',
 'sheet_import_fidelity_test.dart',
 'sheet_macro_preservation_test.dart',
 'sheet_nav_test.dart',
 'sheet_normal_font_metrics_test.dart',
 'sheet_qualified_name_error_test.dart',
 'sheet_qualified_names_test.dart',
 'sheet_schema_fidelity_test.dart',
 'sheet_style_namespace_fidelity_test.dart',
 'sheet_time_number_format_test.dart',
 'sheet_wrap_text_fidelity_test.dart',
 'native_spreadsheet_test.dart',
 'odt_document_writer_test.dart',
 'odp_presentation_writer_test.dart',
 'odf_export_text_fidelity_test.dart',
 'odt_structure_fidelity_test.dart',
 'office_search_fidelity_test.dart',
 'pdf_text_string_encoding_test.dart',
 'toolkit_builders_test.dart',
 'sheet_conditional_dxf_edit_test.dart',
 'proofing/german_grammar_test.dart',
 'proofing/german_suggestion_quality_test.dart',
 'proofing/proofing_locale_test.dart',
 'word_field_span_test.dart',
 'word_zotero_test.dart',
 'odt_table_merge_test.dart',
 'odt_paragraph_properties_test.dart',
 'odt_header_footer_fidelity_test.dart',
 'odp_table_fidelity_test.dart',
 'odf_covered_cell_extraction_test.dart',
 'word_table_test.dart',
 'word_table_grid_addressing_test.dart',
 'word_table_direction_test.dart',
 'table_grid_steps_test.dart',
 'word_table_nested_layout_test.dart',
 'proofing/german_agreement_context_test.dart']
EDITOR = ['pdf_font_faces_test.dart', 'font_subset_render_test.dart', 'pdf_surface_test.dart', 'pdf_viewer_options_test.dart', 'host_fonts_test.dart', 'word_run_metrics_test.dart', 'paint_run_text_unicode_test.dart', 'paint_font_fallback_test.dart', 'word_hyphenation_caret_test.dart', 'word_hyphenation_paint_test.dart', 'word_hyphenation_resume_test.dart', 'word_hyphenation_source_presentation_test.dart', 'word_shaped_wrap_test.dart', 'word_proofing_correction_test.dart', 'word_proofing_geometry_test.dart', 'word_proofing_dialog_test.dart', 'word_proofing_session_test.dart', 'sheet_cell_state_history_test.dart', 'sheet_conditional_rendering_test.dart', 'sheet_explicit_style_history_test.dart', 'sheet_fill_intent_history_test.dart', 'sheet_font_color_intent_test.dart', 'sheet_grid_history_test.dart', 'sheet_hidden_sheet_test.dart', 'sheet_navigation_controller_test.dart', 'sheet_navigation_widget_test.dart', 'sheet_normal_font_auto_test.dart', 'sheet_normal_font_metrics_test.dart', 'sheet_rename_controller_test.dart', 'sheet_sort_history_test.dart', 'sheet_style_history_test.dart', 'sheet_view_history_test.dart', 'word_german_grammar_integration_test.dart', 'word_proofing_context_test.dart']
HARPER = ['harper_provider_test.dart', 'harper_source_text_test.dart', 'harper_source_contract_test.dart']
NODE = ['odt_table_merge_test.dart', 'odt_paragraph_properties_test.dart',
        'odf_covered_cell_extraction_test.dart']
COHORTS = {'engine': ('quds_office_engine', ENGINE),
           'editor': ('quds_office_editor', EDITOR),
           'harper': ('quds_proofing_harper', HARPER),
           'node': ('quds_office_engine', NODE)}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file_sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO).decode().strip()

def analysis_paths(package_name, tests):
    package = REPO / 'packages' / package_name
    changed = [p for p in git('diff', '--name-only', BASELINE, '--',
                            f'packages/{package_name}').splitlines()
               if p.endswith('.dart') and (REPO / p).is_file()]
    changed += [p for p in git('ls-files', '--others', '--exclude-standard').splitlines()
                if p.startswith(f'packages/{package_name}/') and p.endswith('.dart')]
    relative = [str((REPO / p).relative_to(package)) for p in sorted(set(changed))]
    if not relative:
        relative = sorted({str(p.relative_to(package))
                           for p in (package / 'lib').rglob('*.dart')}
                          | {'test/' + p for p in tests})
    return relative

def tree_files(path):
    if path.is_file():
        return {path}
    return {p for p in path.rglob('*') if p.is_file()} if path.is_dir() else set()

def configured_packages(config):
    """Resolve the activated package map, including workspace and SDK packages."""
    result = {}
    for package in json.loads(config.read_text())['packages']:
        root_url = urljoin(config.as_uri(), package['rootUri'])
        parsed = urlparse(root_url)
        if parsed.scheme != 'file':
            raise ValueError('Non-file package root: ' + root_url)
        root = Path(unquote(parsed.path)).resolve()
        lib_url = urljoin(root.as_uri().rstrip('/') + '/', package.get('packageUri', 'lib/'))
        result[package['name']] = (root, Path(unquote(urlparse(lib_url).path)))
    return result

def inputs(cohort, tests):
    config = REPO / '.dart_tool/package_config.json'
    package_map = configured_packages(config)
    paths = {Path(__file__).resolve(), config, REPO / 'pubspec.lock', LOCK_REFERENCE}
    packages = ['quds_office_engine', 'legacy_doc_parser']
    if cohort == 'editor':
        packages += ['quds_office_editor', 'quds_reports']
    if cohort in ('editor', 'harper'):
        packages.append('quds_proofing_harper')
    for name in packages:
        package_root = REPO / 'packages' / name
        actual = package_map.get(name)
        if actual is None or actual[0] != package_root.resolve():
            raise ValueError(f'Activated package {name} does not resolve to this checkout')
        # Include non-Dart runtime assets and all fixtures for the dependency
        # packages, not only the engine fixtures or directly imported sources.
        for directory in ('lib', 'assets', 'fonts', 'templates', 'third_party',
                          'test/fixtures', 'test/support', 'test/goldens',
                          'example/fonts'):
            paths.update(tree_files(package_root / directory))
    package = REPO / 'packages' / COHORTS[cohort][0]
    paths.update(package / 'test' / test for test in tests)
    paths.update(package / p for p in analysis_paths(COHORTS[cohort][0], tests))
    # Include relative, conditional and local package imports in the executed
    # source closure. External dependency source is bound by runtime_identity.
    pending = list(paths)
    seen = set()
    while pending:
        current = pending.pop()
        if current in seen or not current.is_file() or current.suffix != '.dart':
            continue
        seen.add(current)
        for directive in re.findall(r"\b(?:import|export|part)\s+[^;]+;", current.read_text()):
            for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive):
                if uri.startswith('package:'):
                    name, separator, relative = uri[len('package:'):].partition('/')
                    if not separator or name not in package_map:
                        continue
                    dependency = (package_map[name][1] / relative).resolve()
                elif ':' not in uri:
                    dependency = (current.parent / uri).resolve()
                else:
                    continue
                if dependency.is_relative_to(REPO) and dependency.is_file():
                    paths.add(dependency)
                    pending.append(dependency)
    paths.update(REPO.glob('pubspec.*'))
    paths.update((REPO / 'packages').glob('*/pubspec.yaml'))
    paths.update((REPO / 'apps').glob('*/pubspec.yaml'))
    paths.update(REPO.glob('analysis_options.yaml'))
    for parent in ('packages', 'apps'):
        paths.update((REPO / parent).glob('*/analysis_options.yaml'))
        paths.update((REPO / parent).glob('*/dart_test.yaml'))
        paths.update((REPO / parent).glob('*/test/flutter_test_config.dart'))
    paths.update(REPO.glob('dart_test.yaml'))
    return {str(p.relative_to(REPO)): file_sha(p) for p in sorted(paths) if p.is_file()}

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
    return {str(p): file_sha(p) if p.is_file() else None for p in paths}

def runtime_identity(manifest_path, flutter='flutter', include_node=False):
    launchers = {}
    executables = [('dart', 'dart'), ('flutter', flutter)]
    if include_node:
        executables.append(('node', 'node'))
    for name, executable in executables:
        located = shutil.which(executable)
        if located:
            path = Path(located).absolute()
            launchers[name] = {'path': str(path), 'resolved_path': str(path.resolve()),
                               'sha256': file_sha(path)}
        else:
            raise RuntimeError('Executable not found: ' + executable)
    root = Path(os.environ['FLUTTER_ROOT']).resolve()
    members = ['bin/cache/dart-sdk/bin/dart',
               'bin/cache/artifacts/engine/linux-x64/flutter_tester']
    paths = set()
    # Bind the actual SDK, engine artifacts, compiler snapshots and Flutter
    # tool source used by the verified offline launcher. Generated test kernels
    # and build caches are outputs, not source inputs.
    for directory in ('bin/cache/dart-sdk', 'bin/cache/artifacts/engine',
                      'packages/flutter/lib', 'packages/flutter_test/lib',
                      'packages/flutter_tools/lib', 'packages/flutter_tools/bin'):
        paths.update(tree_files(root / directory))
    configs = [REPO / '.dart_tool/package_config.json',
               root / 'packages/flutter_tools/.dart_tool/package_config.json']
    for config in configs:
        paths.add(config)
        for package_root, library in configured_packages(config).values():
            if package_root.is_relative_to(REPO):
                continue
            paths.update(tree_files(library))
            paths.update(tree_files(package_root / 'bin'))
            paths.update(tree_files(package_root / 'pubspec.yaml'))
            paths.update(tree_files(package_root / 'pubspec.lock'))
    for member in ('version', 'bin/internal/engine.version',
                   'bin/cache/flutter.version.json'):
        paths.update(tree_files(root / member))
    manifest = {str(path): file_sha(path) for path in sorted(paths) if path.is_file()}
    raw = (json.dumps(manifest, sort_keys=True, indent=2) + '\n').encode()
    manifest_path.write_bytes(gzip.compress(raw, mtime=0))
    return {'launchers': launchers,
            'sdk_executables_sha256': {p: file_sha(root / p) for p in members},
            'runtime_input_count': len(manifest),
            'runtime_input_manifest_sha256': sha(raw),
            'framework_revision': subprocess.check_output(
                ['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
            'environment': {key: os.environ.get(key) for key in
                            ('FLUTTER_ROOT', 'PUB_CACHE', 'CI',
                             'DART_SUPPRESS_ANALYTICS', 'FLUTTER_SUPPRESS_ANALYTICS',
                             'NODE_OPTIONS', 'NODE_PATH')}}

def version_identity(output, flutter, include_node=False):
    versions = {}
    commands = [('dart', ['dart', '--version']),
                ('flutter', [flutter, '--version', '--machine'])]
    if include_node:
        commands.append(('node', ['node', '--version']))
    for name, command in commands:
        executable = shutil.which(command[0])
        if not executable:
            raise RuntimeError('Executable not found: ' + command[0])
        command[0] = str(Path(executable).absolute())
        result = subprocess.run(command, cwd=REPO, capture_output=True, timeout=60)
        (output / f'{name}-version.stdout').write_bytes(result.stdout)
        (output / f'{name}-version.stderr').write_bytes(result.stderr)
        versions[name] = {'command': command, 'exit_code': result.returncode,
                          'stdout_sha256': sha(result.stdout),
                          'stderr_sha256': sha(result.stderr)}
        if result.returncode:
            raise RuntimeError(f'{name} version command failed; inspect saved version logs')
        if name == 'flutter':
            versions[name]['metadata'] = json.loads(result.stdout)
        else:
            versions[name]['version'] = (result.stdout + result.stderr).decode().strip()
    return versions

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
    if len(tests) != len(set(tests)):
        raise ValueError('Duplicate test file in cohort')
    missing = [test for test in tests if not (package / 'test' / test).is_file()]
    if missing:
        raise FileNotFoundError('Missing selected tests: ' + ', '.join(missing))
    include_node = args.cohort == 'node'
    versions = version_identity(output, args.flutter, include_node=include_node)
    flutter_version = versions['flutter']['metadata']
    runtime_versions_match = (
        flutter_version.get('frameworkVersion') == EXPECTED_RUNTIME['flutter']
        and flutter_version.get('dartSdkVersion') == EXPECTED_RUNTIME['dart']
        and flutter_version.get('frameworkRevision') == EXPECTED_RUNTIME['framework_revision']
        and f"Dart SDK version: {EXPECTED_RUNTIME['dart']} " in versions['dart']['version'])
    lock_before = file_sha(REPO / 'pubspec.lock')
    expected_lock = file_sha(LOCK_REFERENCE)
    before = inputs(args.cohort, tests)
    optional_before = optional_inputs()
    print(json.dumps({'status': 'binding-runtime-inputs'}), flush=True)
    runtime_before = runtime_identity(output / 'runtime-inputs.before.json.gz', args.flutter,
                                      include_node=include_node)
    receipt = {'started_utc': now(), 'cohort': args.cohort,
               'analysis_baseline': BASELINE,
               'head_before': git('rev-parse', 'HEAD'),
               'working_status_before': git('status', '--porcelain'),
               'source_before_sha256': before, 'tests': tests,
               'test_file_count': len(tests), 'versions': versions,
               'expected_runtime': EXPECTED_RUNTIME,
               'runtime_versions_match': runtime_versions_match,
               'runtime_lock_before_sha256': lock_before,
               'expected_lock_sha256': expected_lock,
               'optional_before_sha256': optional_before,
               'runtime_before': runtime_before,
               'harness_sha256': file_sha(Path(__file__)),
               'commands': [], 'github_actions': 'No Actions access.'}
    relative = analysis_paths(package_name, tests)
    receipt['analysis_and_format_paths'] = relative
    test_command = (['dart', 'test', '--platform', 'node'] if include_node
                    else ['dart', 'test'] if args.cohort != 'editor'
                    else [args.flutter, 'test', '--no-pub', '--dart-define=QUDS_SUBSET_RENDER_OUTPUT=' + str(output / 'render')])
    commands = [('tests', test_command + ['--reporter', 'json'] + ['test/' + p for p in tests]),
                ('analyze', ['dart', 'analyze', '--fatal-infos'] + relative),
                ('format', ['dart', 'format', '--output=none', '--set-exit-if-changed'] + relative)]
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    (output / 'validate-used.py').write_bytes(Path(__file__).read_bytes())
    if not runtime_versions_match or lock_before != expected_lock:
        receipt.update({'passed': False, 'finished_utc': now(),
                        'preflight_failure': 'Runtime version or pinned dependency lock mismatch'})
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        raise SystemExit(1)
    for name, command in commands:
        executable = shutil.which(command[0])
        if not executable:
            raise RuntimeError('Executable not found: ' + command[0])
        command[0] = str(Path(executable).absolute())
        executable_sha256 = file_sha(Path(command[0]))
        start = time.monotonic()
        timeout = 120 if name == 'format' else 900
        timed_out = False
        raw_stdout = output / f'{name}.stdout'
        raw_stderr = output / f'{name}.stderr'
        print(json.dumps({'name': name, 'status': 'starting', 'timeout_seconds': timeout}), flush=True)
        with raw_stdout.open('wb') as out, raw_stderr.open('wb') as err:
            env = dict(os.environ, QUDS_ALIAS_RENDER_OUTPUT=str(output / 'render'),
                       QUDS_LOGICAL_RENDER_OUTPUT=str(output / 'logical-render'),
                       QUDS_CONDITIONAL_RENDER_OUTPUT=str(output / 'conditional-render'),
                       QUDS_ODF_FIXTURE_OUTPUT=str(output / 'odf-fixtures'))
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
                'executable_after_sha256': file_sha(Path(command[0])),
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
    print(json.dumps({'status': 'rebinding-runtime-inputs'}), flush=True)
    runtime_after = runtime_identity(output / 'runtime-inputs.after.json.gz', args.flutter,
                                     include_node=include_node)
    receipt.update({'finished_utc': now(), 'head_after': git('rev-parse', 'HEAD'),
                    'working_status_after': git('status', '--porcelain'),
                    'source_after_sha256': after,
                    'optional_after_sha256': optional_after,
                    'runtime_after': runtime_after,
                    'inputs_unchanged': before == after and optional_before == optional_after
                                        and runtime_before == runtime_after})
    receipt['runtime_lock_sha256'] = file_sha(REPO / 'pubspec.lock')
    receipt['head_unchanged'] = receipt['head_before'] == receipt['head_after']
    receipt['lock_unchanged_and_pinned'] = (
        lock_before == receipt['runtime_lock_sha256'] == expected_lock)
    receipt['harness_after_sha256'] = file_sha(Path(__file__))
    receipt['passed'] = (receipt['inputs_unchanged']
                         and receipt['head_unchanged']
                         and receipt['lock_unchanged_and_pinned']
                         and receipt['runtime_versions_match']
                         and receipt['harness_sha256'] == receipt['harness_after_sha256']
                         and all(c['exit_code'] == 0 and c['executable_sha256'] == c['executable_after_sha256']
                                 for c in receipt['commands'])
                         and receipt['commands'][0]['summary']['runner_success']
                         and not receipt['commands'][0]['summary']['failures']
                         and not receipt['commands'][0]['summary']['skipped']
                         and not receipt['commands'][0]['summary']['errors'])
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'passed': receipt['passed'],
                     'inputs_unchanged': receipt['inputs_unchanged'],
                     'input_count': len(before), 'test_file_count': len(tests),
                     'outcomes': receipt['commands'][0]['summary']['outcomes']}), flush=True)
    raise SystemExit(0 if receipt['passed'] else 1)

if __name__ == '__main__':
    main()
