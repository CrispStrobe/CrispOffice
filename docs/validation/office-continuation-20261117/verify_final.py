#!/usr/bin/env python3
"""Independently audit the three completed local cohorts at a published head.

This verifier does not import or execute the qualification harness or rerun
tests. It reads Git objects and the advertised branch ref; it never accesses
GitHub Actions, checks, or commit statuses. Run after committing and pushing the
receipts, for example:

  python docs/validation/office-continuation-20261117/verify_final.py \
    --head FULL_COMMIT_SHA --branch codex/text-rendering-20261116 \
    --output /absolute/scratch/path/final-audit.json

The output should be outside the checkout for an audit of an already published
final commit. A subsequent evidence-only commit can be audited again.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
from urllib.parse import unquote, urljoin, urlparse

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BASELINE = '51cc65f1dc7ec860c0ff7324b73adda9d70a86ef'
IGNORED_INPUTS = {'pubspec.lock', '.dart_tool/package_config.json'}
PACKAGES = {'engine': 'quds_office_engine', 'editor': 'quds_office_editor',
            'harper': 'quds_proofing_harper'}
EXPECTED_TESTS = {
    'engine': [
        'font_subset_structure_test.dart', 'font_subset_unicode_test.dart',
        'pdf_cid_encoding_test.dart', 'pdf_unicode_alias_export_test.dart',
        'fonts_test.dart', 'office_named_fonts_test.dart',
        'arabic_pdf_export_test.dart', 'office_pdf_export_test.dart',
        'pdf_file_test.dart', 'pdf_toolbox_test.dart', 'word_pdf_test.dart',
        'pdf_widgets_test.dart', 'pdf_widgets_catalog_test.dart',
        'pdf_templates_test.dart', 'pdf_to_office_test.dart', 'bidi_test.dart',
        'ods_sheet_writer_test.dart', 'ods_sheet_reader_test.dart',
        'legacy_sheet_reader_test.dart', 'pdf_actual_text_scope_test.dart',
        'pdf_logical_text_export_test.dart', 'sfnt_cmap_validation_test.dart',
        'sheet_conditional_fidelity_test.dart', 'sheet_rename_fidelity_test.dart',
        'sheet_rename_adversarial_test.dart', 'sheet_formula_test.dart',
        'word_small_caps_test.dart', 'sheet_save_cache_and_freeze_test.dart',
        'english_hyphenation_test.dart', 'german_hyphenation_context_test.dart',
        'proofing/proofing_text_ranges_test.dart', 'proofing_hyphenation_test.dart',
        'proofing/german_spelling_test.dart', 'proofing/german_writing_rules_test.dart',
        'proofing/office_proofing_test.dart', 'word_run_measure_test.dart',
        'word_run_measure_boundaries_test.dart',
    ],
    'editor': [
        'pdf_font_faces_test.dart', 'font_subset_render_test.dart',
        'pdf_surface_test.dart', 'pdf_viewer_options_test.dart',
        'host_fonts_test.dart', 'word_run_metrics_test.dart',
        'paint_run_text_unicode_test.dart', 'paint_font_fallback_test.dart',
        'word_hyphenation_caret_test.dart', 'word_hyphenation_paint_test.dart',
        'word_hyphenation_resume_test.dart',
        'word_hyphenation_source_presentation_test.dart',
        'word_shaped_wrap_test.dart', 'word_proofing_correction_test.dart',
        'word_proofing_geometry_test.dart', 'word_proofing_dialog_test.dart',
        'word_proofing_session_test.dart',
    ],
    'harper': ['harper_provider_test.dart', 'harper_source_text_test.dart',
               'harper_source_contract_test.dart'],
}
OPTIONAL_INPUTS = {
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
    '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf',
    '/home/mohammed/Desktop/al_tahreer_profile.pdf',
    str(REPO / 'packages/quds_office_editor/example/fonts/Cairo-Regular.ttf'),
}


class AuditFailure(Exception):
    pass


def require(condition, message):
    if not condition:
        raise AuditFailure(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_bytes())


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO).decode().strip()


def repository_path(name):
    relative = PurePosixPath(name)
    require(not relative.is_absolute() and '..' not in relative.parts,
            'Input path escapes checkout: ' + name)
    path = REPO / str(relative)
    require(path.resolve().is_relative_to(REPO),
            'Input resolves outside checkout: ' + name)
    return path


def git_blob_sha(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def tree_entries(head):
    raw = subprocess.check_output(['git', 'ls-tree', '-r', '-z', head], cwd=REPO)
    result = {}
    for entry in raw.split(b'\0'):
        if not entry:
            continue
        metadata, name = entry.decode().split('\t', 1)
        mode, kind, object_id = metadata.split()
        result[name] = {'mode': mode, 'kind': kind, 'blob': object_id}
    return result


def verify_committed(path, tree):
    name = str(path.relative_to(REPO))
    require(name in tree and tree[name]['kind'] == 'blob',
            'Evidence/source file is not committed: ' + name)
    raw = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
    require(git_blob_sha(raw) == tree[name]['blob'],
            'Working file differs from committed Git blob: ' + name)
    return {'sha256': sha(raw), 'git_blob': tree[name]['blob']}


def expected_source_paths(cohort):
    """Reconstruct the audited source/config/fixture closure without the runner."""
    names = ['quds_office_engine', 'legacy_doc_parser']
    if cohort == 'editor':
        names.append('quds_office_editor')
    if cohort in {'editor', 'harper'}:
        names.append('quds_proofing_harper')
    paths = {p for name in names for p in (REPO / 'packages' / name / 'lib').rglob('*.dart')}
    package = REPO / 'packages' / PACKAGES[cohort]
    for test in EXPECTED_TESTS[cohort]:
        path = package / 'test' / test
        require(path.is_file(), 'Selected test is missing: ' + str(path))
        paths.add(path)
    paths.update((package / 'test/support').rglob('*.dart'))
    # Analysis/formatting also read changed Dart files outside selected tests,
    # including the separately scoped native/Wasm transport probes.
    analyzed = git('diff', '--name-only', BASELINE, '--',
                   str(package.relative_to(REPO))).splitlines()
    analyzed += git('ls-files', '--others', '--exclude-standard', '--',
                    str(package.relative_to(REPO))).splitlines()
    paths.update(REPO / name for name in analyzed
                 if name.endswith('.dart') and (REPO / name).is_file())
    pending = list(paths)
    seen = set()
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        if current.suffix != '.dart':
            continue
        # Include every URI in conditional imports, not only the first URI.
        declarations = re.findall(r'^\s*(?:import|export|part)\s+([^;]+);',
                                  current.read_text(), re.MULTILINE)
        for declaration in declarations:
            for uri in re.findall(r"['\"]([^'\"]+)['\"]", declaration):
                if ':' in uri:
                    continue
                dependency = (current.parent / uri).resolve()
                if dependency.is_relative_to(REPO) and dependency.is_file() and dependency not in paths:
                    paths.add(dependency)
                    pending.append(dependency)
    paths.update(p for p in (REPO / 'packages/quds_office_engine/test/fixtures').rglob('*') if p.is_file())
    paths.update((REPO / 'packages/quds_office_editor/fonts').glob('*.ttf'))
    cairo = REPO / 'packages/quds_office_editor/example/fonts/Cairo-Regular.ttf'
    if cairo.is_file():
        paths.add(cairo)
    paths.update(REPO.glob('pubspec.*'))
    paths.update(REPO.glob('analysis_options.yaml'))
    paths.update(REPO.glob('dart_test.yaml'))
    for root in ['packages', 'apps']:
        for pattern in ['*/pubspec.yaml', '*/analysis_options.yaml',
                        '*/dart_test.yaml', '*/test/flutter_test_config.dart']:
            paths.update((REPO / root).glob(pattern))
    paths.add(REPO / '.dart_tool/package_config.json')
    return {str(path.relative_to(REPO)) for path in paths if path.is_file()}


def event_summary(raw, cwd, expected_tests):
    events = []
    for line in raw.decode(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict):
            events.append(event)
    starts = {}
    suites = {}
    completions = {}
    outcomes = Counter()
    per_suite = Counter()
    failures = []
    skipped = []
    errors = []
    terminals = []
    for event in events:
        kind = event.get('type')
        if kind == 'suite':
            suite = event['suite']
            require(suite['id'] not in suites, 'Duplicate suite ID in test log')
            raw_path = suite['path']
            path = Path(unquote(urlparse(raw_path).path)) if raw_path.startswith('file:') else Path(raw_path)
            suites[suite['id']] = str((cwd / path).resolve().relative_to(cwd / 'test'))
        elif kind == 'testStart':
            test = event['test']
            require(test['id'] not in starts, 'Duplicate test ID in test log')
            starts[test['id']] = test
        elif kind == 'testDone':
            test_id = event['testID']
            require(test_id in starts and test_id not in completions,
                    'Missing start or duplicate completion for a test')
            completions[test_id] = event
            if event.get('hidden'):
                require(event.get('result') == 'success', 'Hidden loader test did not succeed')
                continue
            test = starts[test_id]
            require(test['suiteID'] in suites, 'Test has no known suite')
            result = 'skipped' if event.get('skipped') else event.get('result', 'unknown')
            outcomes[result] += 1
            per_suite[suites[test['suiteID']]] += 1
            if result != 'success':
                (skipped if result == 'skipped' else failures).append(test['name'])
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            terminals.append(event)
    require(starts and set(starts) == set(completions), 'Incomplete test lifecycle in log')
    require(len(terminals) == 1, 'Expected exactly one terminal test event')
    require(set(suites.values()) == set(expected_tests), 'Executed suite files differ from selected tests')
    require(set(per_suite) == set(expected_tests), 'A selected suite completed no visible tests')
    summary = {'outcomes': dict(outcomes), 'failures': failures, 'skipped': skipped,
               'errors': errors, 'runner_success': bool(terminals[0].get('success'))}
    return summary, dict(sorted(per_suite.items()))


def runtime_audit(tree):
    directory = HERE / 'runtime'
    manifest = read_json(directory / 'manifest.json')
    manifest_entries = {}
    for item in manifest:
        name = item['path']
        relative = PurePosixPath(name)
        require(not relative.is_absolute() and '..' not in relative.parts,
                'Runtime manifest path escapes its directory')
        path = directory / name
        require(path.resolve().is_relative_to(directory),
                'Runtime manifest file resolves outside its directory')
        raw = path.read_bytes()
        decoded = gzip.decompress(raw) if name.endswith('.gz') else raw
        require(sha(raw) == item['stored_sha256'] and sha(decoded) == item['decoded_sha256'],
                'Runtime manifest hash mismatch: ' + name)
        require(len(decoded) == item['bytes'], 'Runtime decoded size mismatch: ' + name)
        manifest_entries[name] = verify_committed(path, tree)
    runtime = read_json(directory / 'runtime-receipt.json')
    require(runtime.get('status') == 'ready', 'Runtime preparation did not succeed')
    require(runtime.get('github_actions_used') is False, 'Unexpected runtime CI attribution')
    require(all(command['exit_code'] == 0 for command in runtime['commands']),
            'A runtime preparation command failed')
    require(runtime['sdk_tracked_changes'] == [], 'Runtime receipt records modified SDK sources')
    bindings = read_json(directory / 'workspace-inputs.json')
    for name, expected in bindings['sha256'].items():
        require(sha(repository_path(name).read_bytes()) == expected,
                'Fresh runtime input binding differs: ' + name)
    require(IGNORED_INPUTS <= set(bindings['sha256']), 'Missing runtime workspace input bindings')
    require(bindings['sha256']['pubspec.lock'] == runtime['workspace_lock_sha256'],
            'Current dependency lock differs from installed runtime lock')
    config_path = REPO / '.dart_tool/package_config.json'
    config = read_json(config_path)
    require(len(config['packages']) == runtime['workspace_package_count'],
            'Workspace package count differs from runtime')
    package_map = {item['name']: item for item in config['packages']}
    for package in ['quds_office_engine', 'quds_office_editor', 'legacy_doc_parser',
                    'quds_proofing_harper', 'quds_reports']:
        item = package_map[package]
        location = urlparse(urljoin(config_path.as_uri(), item['rootUri']))
        actual = Path(unquote(location.path)).resolve()
        require(location.scheme == 'file' and actual == REPO / 'packages' / package,
                'Workspace package routes to a different source checkout: ' + package)
    sdk = Path(runtime['actual_runtime']['flutterRoot'])
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=sdk).decode().strip()
            == runtime['framework_revision'], 'Installed Flutter framework revision differs')
    require(not subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], cwd=sdk).strip(),
            'Installed Flutter tracked sources changed')
    for name, expected in runtime['executables_sha256'].items():
        require(sha((sdk / name).read_bytes()) == expected, 'Runtime executable differs: ' + name)
    launchers = {}
    for name, expected in runtime['launcher_sha256'].items():
        path = sdk.parent / 'bin' / name
        require(sha(path.read_bytes()) == expected, 'Runtime launcher differs: ' + name)
        launchers[name] = {'path': str(path), 'resolved_path': str(path.resolve()),
                           'sha256': expected}
    setup = directory / 'runtime-receipt.json'
    for field, name in [('dart_selected_receipt_sha256', 'dart-selected-install.json.gz'),
                        ('common_receipt_sha256', 'common-install.json.gz'),
                        ('engine_receipt_sha256', 'engine-install.json.gz'),
                        ('pub_receipt_sha256', 'prefetch-162.json.gz')]:
        require(sha(gzip.decompress((directory / name).read_bytes())) == runtime[field],
                'Runtime sub-receipt does not match preparation record: ' + name)
    for command in runtime['commands']:
        log = directory / (command['label'] + '.log.gz')
        if log.is_file():
            require(sha(gzip.decompress(log.read_bytes())) == command['log_sha256'],
                    'Runtime command log differs: ' + command['label'])
    verify_committed(directory / 'manifest.json', tree)
    verify_committed(directory / 'workspace-inputs.json', tree)
    return {'workspace_bindings': bindings['sha256'],
            'workspace_package_count': len(config['packages']),
            'runtime_receipt_sha256': sha(setup.read_bytes()),
            'actual_runtime': runtime['actual_runtime'],
            'runtime_files': manifest_entries,
            'installed_executables_sha256': runtime['executables_sha256'],
            'installed_launchers': launchers}


def cohort_audit(cohort, head, tree, runtime):
    directory = HERE / cohort
    receipt_path = directory / 'receipt.json'
    receipt = read_json(receipt_path)
    require(receipt['cohort'] == cohort, 'Receipt cohort differs: ' + cohort)
    require(receipt.get('passed') is True and receipt.get('finished_utc'),
            'Cohort receipt is incomplete or failed: ' + cohort)
    tests = receipt['tests']
    require(tests == EXPECTED_TESTS[cohort] and len(tests) == len(set(tests)),
            'Cohort selected tests changed: ' + cohort)
    before = receipt['source_before_sha256']
    after = receipt['source_after_sha256']
    require(before == after and receipt['inputs_unchanged'] is True,
            'Cohort source changed during execution: ' + cohort)
    missing = expected_source_paths(cohort) - set(before)
    require(not missing, 'Source/config/fixture closure missing inputs: ' + repr(sorted(missing)))
    committed = {}
    for name, expected in before.items():
        path = repository_path(name)
        require(sha(path.read_bytes()) == expected,
                'Current source differs from tested input: ' + name)
        if name in IGNORED_INPUTS:
            require(expected == runtime['workspace_bindings'][name],
                    'Cohort ignored input differs from fresh runtime capture: ' + name)
        else:
            committed[name] = verify_committed(path, tree)
    require(receipt['runtime_lock_sha256'] == runtime['workspace_bindings']['pubspec.lock'],
            'Cohort dependency lock differs: ' + cohort)
    identity = receipt['runtime_before']
    require(identity == receipt['runtime_after'], 'Runtime identity changed during cohort: ' + cohort)
    require(identity['launchers'] == runtime['installed_launchers'],
            'Cohort launchers differ from the installed, verified runtime: ' + cohort)
    require(identity['sdk_executables_sha256'] == runtime['installed_executables_sha256'],
            'Cohort SDK binaries differ from the verified runtime: ' + cohort)
    sdk = Path(runtime['actual_runtime']['flutterRoot'])
    require(identity['environment']['FLUTTER_ROOT'] == str(sdk),
            'Cohort Flutter root differs from verified runtime: ' + cohort)
    require(Path(identity['environment']['PUB_CACHE']).resolve() == sdk.parent / 'pub-cache',
            'Cohort Pub cache differs from restored locked dependencies: ' + cohort)
    optional = receipt['optional_before_sha256']
    require(optional == receipt['optional_after_sha256'] and set(optional) == OPTIONAL_INPUTS,
            'Optional input presence or contents changed: ' + cohort)
    for name, expected in optional.items():
        path = Path(name)
        actual = sha(path.read_bytes()) if path.is_file() else None
        require(actual == expected, 'Optional runtime input now differs: ' + name)
    harness = (directory / 'validate-used.py').read_bytes()
    require(sha(harness) == receipt['harness_sha256'] == sha((HERE / 'validate.py').read_bytes()),
            'Captured/current harness differs from cohort receipt: ' + cohort)
    commands = receipt['commands']
    require([item['name'] for item in commands] == ['tests', 'analyze', 'format'],
            'Cohort lacks the expected three gates: ' + cohort)
    logs = []
    summary = None
    per_suite = None
    cwd = REPO / 'packages' / PACKAGES[cohort]
    for item in commands:
        require(Path(item['cwd']).resolve() == cwd, 'Gate ran in unexpected checkout')
        require(item['exit_code'] == 0 and item['timed_out'] is False, 'Gate failed or timed out')
        launcher_name = 'flutter' if cohort == 'editor' and item['name'] == 'tests' else 'dart'
        launcher = identity['launchers'][launcher_name]
        require(item['command'][0] == launcher['path'],
                'Gate command did not invoke the recorded absolute runtime launcher')
        require(item['executable_sha256'] == item['executable_after_sha256'] == launcher['sha256'],
                'Gate executable hash differs from the verified runtime launcher')
        for channel in ['stdout', 'stderr']:
            filename = item[channel]
            require(Path(filename).name == filename, 'Log path escapes cohort directory')
            log = directory / filename
            stored = log.read_bytes()
            raw = gzip.decompress(stored)
            require(sha(raw) == item[channel + '_sha256'], 'Decoded gate log hash mismatch: ' + str(log))
            logs.append({'path': str(log.relative_to(REPO)), 'decoded_sha256': sha(raw),
                         'stored_sha256': sha(stored)})
            verify_committed(log, tree)
            if item['name'] == 'tests' and channel == 'stdout':
                summary, per_suite = event_summary(raw, cwd, tests)
        command = item['command']
        if item['name'] == 'tests':
            prefix = [launcher['path'], 'test']
            if cohort == 'editor':
                prefix += ['--no-pub', '--dart-define=QUDS_SUBSET_RENDER_OUTPUT=' + str(directory / 'render')]
            require(command == prefix + ['--reporter', 'json'] + ['test/' + test for test in tests],
                    'Executed test command differs from the reviewed invocation')
            require(command[-len(tests):] == ['test/' + test for test in tests],
                    'Executed test arguments differ from receipt selection')
            require(summary == item['summary'], 'Recomputed test summary differs from receipt')
            require(summary['runner_success'] and not summary['errors']
                    and not summary['failures'] and not summary['skipped'],
                    'Test event stream contains failure/error/skip')
            require(set(summary['outcomes']) == {'success'}, 'Unexpected final test outcomes')
        elif item['name'] == 'analyze':
            require(command[:3] == [launcher['path'], 'analyze', '--fatal-infos'],
                    'Analysis command is not strict')
            require(len(command) > 3, 'Analysis command has no explicit source scope')
        else:
            require(command[:4] == [launcher['path'], 'format', '--output=none', '--set-exit-if-changed']
                    and len(command) > 4, 'Formatting command lacks checked paths')
    require(commands[1]['command'][3:] == commands[2]['command'][4:],
            'Analysis and formatting source scopes differ')
    analyzed_paths = commands[1]['command'][3:]
    require(receipt['analysis_and_format_paths'] == analyzed_paths,
            'Recorded analysis/formatting scope differs from actual commands')
    changed = git('diff', '--name-only', BASELINE, head, '--', 'packages/' + PACKAGES[cohort]).splitlines()
    for name in changed:
        if not name.endswith('.dart') or not (REPO / name).is_file():
            continue
        relative = str((REPO / name).relative_to(cwd))
        require(any(relative == scope or relative.startswith(scope.rstrip('/') + '/')
                    for scope in analyzed_paths), 'Changed Dart file was not analyzed/formatted: ' + name)
    for name in ['receipt.json', 'validate-used.py']:
        verify_committed(directory / name, tree)
    for ancestor in [receipt['head_before'], receipt['head_after']]:
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', ancestor, head], cwd=REPO).returncode == 0,
                'Cohort source checkpoint is not an ancestor of final head')
    artifacts = {}
    for name in ['render', 'logical-render']:
        for path in sorted((directory / name).rglob('*')):
            if path.is_file():
                artifacts[str(path.relative_to(directory))] = verify_committed(path, tree)
    return {'passed_tests': summary['outcomes']['success'], 'test_files': len(tests),
            'per_suite_tests': per_suite, 'source_input_count': len(before),
            'committed_source_inputs': committed, 'ignored_runtime_inputs':
            {name: before[name] for name in sorted(IGNORED_INPUTS)},
            'optional_inputs': optional, 'logs': logs, 'artifacts': artifacts,
            'runtime_identity': identity,
            'receipt_sha256': sha(receipt_path.read_bytes()),
            'harness_sha256': receipt['harness_sha256'],
            'source_checkpoints': [receipt['head_before'], receipt['head_after']]}


def refresh_audit(directory, original, ancestors, tree):
    """Check the bounded second observation without replacing older tips."""
    comparison = read_json(directory / 'comparison.json')
    require(comparison['inventory_sha256'] == sha((HERE / 'incoming-inventory.json').read_bytes()),
            'Final observation is not based on the original pinned inventory')
    require(comparison['previous_reference_count'] == 189,
            'Final observation has an unexpected original reference count')
    refs = comparison['refs']
    require(len(refs) == comparison['observed_reference_count'] == 195,
            'Final observation must contain the exact 195-reference snapshot')
    require(len({item['ref'] for item in refs}) == len(refs),
            'Final observation has duplicate reference names')
    require(len({item['sha'] for item in refs}) == comparison['observed_distinct_shas'] == 132,
            'Final observation distinct commit count differs')
    commands = comparison['commands']
    require({item['name'] for item in commands} == {'fork', 'upstream'} and len(commands) == 2,
            'Final observation must contain one query per repository')
    advertised = {}
    logs = {}
    for command in commands:
        name = command['name']
        repository = 'CrispStrobe/quds_office_suite' if name == 'fork' else 'MohammedAsaadAsaad/quds_office_suite'
        require(command['command'] == ['git', 'ls-remote', 'https://github.com/' + repository + '.git',
                                       'refs/heads/*', 'refs/pull/*/head'],
                'Final observation command does not enumerate all branch/PR heads')
        require(command['exit_code'] == 0, 'Final observation command failed')
        require(read_json(directory / (name + '.command.json')) == command,
                'Final observation command receipt differs from comparison')
        for channel in ['stdout', 'stderr']:
            path = directory / (name + '.' + channel + '.txt')
            raw = path.read_bytes()
            require(sha(raw) == command[channel + '_sha256'],
                    'Final observation log hash mismatch: ' + path.name)
            logs[path.name] = verify_committed(path, tree)
            if channel != 'stdout':
                continue
            for line in raw.decode().splitlines():
                object_id, ref = line.split('\t')
                require(re.fullmatch('[0-9a-f]{40}', object_id) is not None,
                        'Final observation contains an invalid object ID')
                if ref.startswith('refs/heads/'):
                    remote = 'origin' if name == 'fork' else 'upstream'
                    mapped = 'refs/remotes/' + remote + '/' + ref[len('refs/heads/'):]
                else:
                    require(re.fullmatch(r'refs/pull/[0-9]+/head', ref) is not None,
                            'Final observation contains an unexpected ref')
                    remote = 'fork-pr' if name == 'fork' else 'upstream-pr'
                    mapped = 'refs/remotes/' + remote + '/' + ref.split('/')[2]
                require(mapped not in advertised, 'Duplicate advertised reference')
                advertised[mapped] = object_id
        verify_committed(directory / (name + '.command.json'), tree)
    require(advertised == {item['ref']: item['sha'] for item in refs},
            'Final comparison inventory differs from raw remote advertisements')
    require((directory / 'incoming-inventory-used.json').read_bytes()
            == (HERE / 'incoming-inventory.json').read_bytes(),
            'Preserved first inventory differs from original')
    for name in ['comparison.json', 'incoming-inventory-used.json', 'refresh.py']:
        verify_committed(directory / name, tree)
    union = {(item['ref'], item['sha']) for item in original['refs'] + refs}
    missing = sorted((ref, object_id) for ref, object_id in union if object_id not in ancestors)
    require(not missing, 'A current or superseded pinned tip is absent from ancestry: ' + repr(missing))
    return {'checked_references': len(refs), 'included': len(refs),
            'distinct_commits': comparison['observed_distinct_shas'],
            'snapshot_utc': comparison['completed_at_utc'],
            'comparison_sha256': sha((directory / 'comparison.json').read_bytes()),
            'observation_logs': logs,
            'union_reference_revision_pairs': len(union),
            'union_distinct_commits': len({object_id for _, object_id in union}),
            'union_reference_revision_pairs_sha256': sha(json.dumps(sorted(union), separators=(',', ':')).encode())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', required=True, help='Full published commit SHA to audit')
    parser.add_argument('--branch', required=True, help='Remote branch carrying that exact commit')
    parser.add_argument('--remote', default='origin')
    parser.add_argument('--refresh', type=Path, default=HERE / 'final-remote-refresh',
                        help='Committed directory containing the final 195-reference comparison')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
              'requested_head': args.head, 'passed': False,
              'github_actions_used': False, 'tests_rerun': False}
    exit_code = 1
    try:
        require(re.fullmatch(r'[0-9a-f]{40}', args.head) is not None, 'Expected a full commit SHA')
        require(git('rev-parse', 'HEAD') == args.head, 'Current HEAD differs from requested head')
        require(not git('diff', '--name-only', args.head, '--'),
                'Tracked checkout differs from requested published tree')
        tree = tree_entries(args.head)
        report['git_tree'] = git('rev-parse', args.head + '^{tree}')
        report['verifier'] = verify_committed(Path(__file__).resolve(), tree)
        verify_committed(HERE / 'validate.py', tree)
        runtime = runtime_audit(tree)
        report['runtime'] = runtime
        report['cohorts'] = {}
        for cohort in EXPECTED_TESTS:
            report['cohorts'][cohort] = cohort_audit(cohort, args.head, tree, runtime)
        inventory = read_json(HERE / 'incoming-inventory.json')
        refs = inventory['refs']
        require(len(refs) == inventory['reference_count'] == 189,
                'Pinned inventory must contain exactly 189 named references')
        require(len({entry['ref'] for entry in refs}) == len(refs), 'Duplicate pinned reference names')
        require(len({entry['sha'] for entry in refs}) == inventory['distinct_shas'] == 128,
                'Pinned unique commit count differs')
        ancestors = set(git('rev-list', args.head).splitlines())
        missing = [entry for entry in refs if entry['sha'] not in ancestors]
        require(not missing, 'Pinned references absent from final ancestry: ' + repr(missing))
        verify_committed(HERE / 'incoming-inventory.json', tree)
        verify_committed(HERE / 'integrated-ancestry.json', tree)
        report['ancestry'] = {'checked_references': len(refs), 'included': len(refs),
                              'distinct_commits': inventory['distinct_shas'],
                              'snapshot_utc': inventory['frozen_at_utc'],
                              'inventory_sha256': sha((HERE / 'incoming-inventory.json').read_bytes())}
        report['ancestry']['final_observation'] = refresh_audit(
            args.refresh.resolve(), inventory, ancestors, tree)
        ref = 'refs/heads/' + args.branch
        remote_lines = git('ls-remote', '--heads', args.remote, ref).splitlines()
        require(len(remote_lines) == 1, 'Expected one exact remote branch advertisement')
        remote_sha, remote_ref = remote_lines[0].split('\t')
        require(remote_ref == ref and remote_sha == args.head,
                'Remote branch differs from the requested final commit')
        report['remote'] = {'remote': args.remote, 'ref': ref, 'head': remote_sha,
                            'tree': report['git_tree'],
                            'verification': 'Advertised remote commit equals the local content-addressed commit; that commit binds the complete Git tree.'}
        report['total_passing_tests'] = sum(item['passed_tests'] for item in report['cohorts'].values())
        report['total_test_files'] = sum(item['test_files'] for item in report['cohorts'].values())
        report['passed'] = True
        exit_code = 0
    except (AuditFailure, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        report['error'] = str(error)
    finally:
        report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({key: report[key] for key in ['passed', 'requested_head',
                          'total_passing_tests', 'total_test_files', 'error'] if key in report}))
    raise SystemExit(exit_code)


if __name__ == '__main__':
    main()
