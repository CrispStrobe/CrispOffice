#!/usr/bin/env python3
"""Requalify the frozen merged Office source locally; never contact CI.

Test selection starts with the committed office-fidelity manifest, adds all
Zotero suites and the recovered proofing/layout boundary suites, and removes
overlap. Test execution uses an unchanged locked external workspace whose
implementation directories point at the exact frozen canonical checkout.
"""
from __future__ import annotations

import argparse
import collections
import datetime
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import traceback
from urllib.parse import unquote, urljoin, urlparse

EXPECTED_LOCK = '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
BASELINE = '518fb28b'
PRIVATE_PDF = '/home/mohammed/Desktop/al_tahreer_profile.pdf'
PRIVATE_CASES = {
    'TrueType subsets without cmap get ToUnicode cmap for the host',
    'JPEG with DCT SMask attaches softMaskJpeg for the host',
}
SYSTEM_INPUTS = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
    '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf',
    PRIVATE_PDF,
]
PACKAGE_NAMES = {
    'engine': 'quds_office_engine',
    'editor': 'quds_office_editor',
    'harper': 'quds_proofing_harper',
    'gector': 'quds_proofing_gector',
}
OPTIONAL_GECTOR_CASE = 'real native dual heads own their output and reject use after dispose'
OPTIONAL_PYTHON_CASE = 'test_qualification.TinyConverterTests.test_real_quantizer_preserves_both_head_matrices'
EXPECTED_ZOTERO_COUNTS = {'engine-zotero': 390, 'editor-zotero': 186}
BASELINE_PLAN_SHA256 = '8cc03280a15f06e51cf09d8b021d5d7fd6b913fda2b23cda61fc905917d67c6f'
REQUIRED_INCOMING_TESTS = {
    'test/odf_frame_extraction_test.dart',
    'test/odt_section_integration_test.dart',
    'test/proofing/german_lexical_gap_test.dart',
    'test/proofing/german_spelling_quotes_test.dart',
    'test/odt_paragraph_decoration_test.dart',
    'test/odt_page_field_fidelity_test.dart',
}
NODE_TIMEOUT_SECONDS = 600
NODE_UNAVAILABLE_TEST_IMPORTS = {'dart:io', 'dart:ffi', 'dart:isolate', 'dart:html'}
RECOVERED_PRODUCTION_FORMAT_TARGETS = {
    'packages/quds_office_engine/lib/src/word/model/word_zotero.dart',
    'packages/quds_office_engine/lib/src/zotero/zotero_client.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_format.dart',
}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_bytes(path):
    return os.readlink(path).encode() if path.is_symlink() else path.read_bytes()


def sha(path):
    return digest(file_bytes(path))


def save(path, value):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.replace(path)


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def git_text(repo, *args):
    return git(repo, *args).decode().strip()


def git_entries(repo, commit):
    result = {}
    for row in git(repo, 'ls-tree', '-r', '-z', commit).split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        mode, kind, blob = meta.decode().split()
        if kind == 'blob':
            result[name.decode()] = {'mode': mode, 'blob': blob}
    return result


def source_snapshot(repo, commit):
    entries = git_entries(repo, commit)
    result = {}
    mismatches = []
    for relative, expected in entries.items():
        # Evidence/report edits do not change qualified program inputs.
        if relative.startswith('docs/'):
            continue
        path = repo / relative
        data = file_bytes(path)
        mode = '120000' if path.is_symlink() else ('100755' if path.stat().st_mode & 0o111 else '100644')
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        result[relative] = {'sha256': digest(data), 'git_blob': blob, 'git_mode': mode}
        if blob != expected['blob'] or mode != expected['mode']:
            mismatches.append(relative)
    untracked = [p.decode() for p in git(repo, 'ls-files', '--others', '--exclude-standard', '-z').split(b'\0')
                 if p and not p.decode().startswith('docs/')]
    return {'files': result, 'count': len(result), 'commit_mismatches': mismatches,
            'untracked_non_evidence_paths': untracked}


def normalized_graph(config, repo):
    graph = json.loads(config.read_text())
    assert graph['configVersion'] == 2
    locals_by_name = {}
    for manifest in [repo / 'pubspec.yaml', *repo.glob('packages/*/pubspec.yaml'),
                     *repo.glob('packages/*/example/pubspec.yaml'), *repo.glob('apps/*/pubspec.yaml')]:
        name = re.search(r'^name:\s*(\S+)', manifest.read_text(), re.M)
        if name:
            locals_by_name[name.group(1)] = manifest.parent
    for package in graph['packages']:
        if package['name'] in locals_by_name:
            root = locals_by_name[package['name']]
        else:
            uri = urlparse(urljoin(config.as_uri(), package['rootUri']))
            assert uri.scheme == 'file' and uri.netloc in ('', 'localhost'), uri
            root = Path(unquote(uri.path)).resolve()
        assert root.is_dir(), root
        package['rootUri'] = root.as_uri() + '/'
    return graph


def dependency_snapshot(graph, repo):
    files = {}
    roots = {}
    for package in graph['packages']:
        root = Path(unquote(urlparse(package['rootUri']).path)).resolve()
        if root.is_relative_to(repo):
            continue
        roots[package['name']] = str(root)
        paths = {root / name for name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')}
        for directory in ('lib', 'bin', 'assets'):
            paths.update(p for p in (root / directory).rglob('*') if p.is_file())
        for path in sorted(paths):
            if path.is_file():
                files[str(path)] = sha(path)
    return {'package_roots': roots, 'sha256_by_path': files, 'count': len(files)}


def runtime_snapshot(root):
    names = [
        'bin/cache/dart-sdk/bin/dart', 'bin/cache/dart-sdk/bin/dartaotruntime',
        'bin/cache/dart-sdk/bin/snapshots/dartdev_aot.dart.snapshot',
        'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
        'bin/cache/dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot',
        'bin/cache/dart-sdk/bin/snapshots/kernel-service.dart.snapshot',
        'bin/cache/flutter_tools.snapshot', 'bin/cache/flutter.version.json',
        'bin/cache/artifacts/engine/linux-x64/flutter_tester',
        'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill',
        'bin/cache/artifacts/engine/common/flutter_patched_sdk_product/platform_strong.dill',
        'bin/internal/engine.version', 'packages/flutter_tools/pubspec.lock',
    ]
    files = {str(root / name): sha(root / name) if (root / name).is_file() else None for name in names}
    node = shutil.which('node')
    assert node, 'The separately qualified JavaScript lane requires Node.'
    node = Path(node).resolve()
    files[str(node)] = sha(node)
    return files


def workspace_snapshot(workspace):
    paths = {workspace / name for name in ('pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json')}
    paths.update(workspace.glob('packages/*/pubspec.yaml'))
    paths.update(workspace.glob('packages/*/example/pubspec.yaml'))
    paths.update(workspace.glob('apps/*/pubspec.yaml'))
    for manifest in [*workspace.glob('packages/*/pubspec.yaml'), *workspace.glob('packages/*/example/pubspec.yaml'), *workspace.glob('apps/*/pubspec.yaml')]:
        paths.update(path for path in manifest.parent.iterdir() if path.is_symlink())
    paths.add(workspace / 'tools')
    return {str(path): sha(path) for path in sorted(paths) if path.is_file() or path.is_symlink()}


def system_snapshot():
    return {name: sha(Path(name)) if Path(name).is_file() else None for name in SYSTEM_INPUTS}


def fixture_audit(repo, workspace, plan):
    """Bind the actual Linux font choices that prevent inherited no-op paths."""
    required = [Path(name) for name in SYSTEM_INPUTS if name != PRIVATE_PDF]
    required += [workspace / 'packages/quds_office_editor' / path for path in
                 ('fonts/NotoNaskhArabic-Regular.ttf', 'fonts/LiberationSans-Regular.ttf',
                  'example/fonts/Cairo-Regular.ttf')]
    required_rows = {str(path): {'present': path.is_file(), 'sha256': sha(path) if path.is_file() else None,
                                'resolved_path': str(path.resolve())} for path in required}
    missing = [path for path, value in required_rows.items() if not value['present']]
    assert not missing, 'Required font fixtures missing; audit exclusions before qualification: ' + repr(missing)
    selected = [repo / 'packages' / PACKAGE_NAMES[group['kind']] / path
                for group in plan['cohorts'].values() for path in group['tests']]
    pending = list(selected)
    closure = set()
    while pending:
        path = pending.pop().resolve()
        if path in closure:
            continue
        closure.add(path)
        for uri in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", path.read_text()):
            if ':' not in uri:
                dependency = (path.parent / uri).resolve()
                if dependency.is_file() and dependency.suffix == '.dart':
                    pending.append(dependency)
    guarded = {}
    for path in sorted(closure):
        lines = path.read_text().splitlines()
        hits = [{'line': i + 1, 'text': line.strip()} for i, line in enumerate(lines)
                if re.search(r'existsSync|\.exists\(|markTestSkipped|/usr/share/fonts|/home/', line)]
        if hits:
            guarded[str(path.relative_to(repo))] = {'sha256': sha(path), 'guards_and_paths': hits}
    return {'method': 'Reviewed file-existence/skip conditions across selected suites and relative Dart import closure. All Linux and bundled font choices are present. Windows alternatives are unused on this Linux host. The only absent private-fixture early returns are the two explicitly named pdf_file tests.',
            'selected_test_files': len(selected), 'relative_dart_closure_files': len(closure),
            'required_font_inputs': required_rows, 'guarded_source_files': guarded,
            'private_pdf_present': Path(PRIVATE_PDF).is_file(),
            'optional_native_fixture_environment_present': {key: bool(os.environ.get(key)) for key in ('GECTOR_TEST_LIBRARY', 'GECTOR_TEST_MODEL', 'GECTOR_TEST_MODEL_SHA256', 'GECTOR_TEST_LIBRARY_SHA256')},
            'optional_native_case_if_fixtures_absent': OPTIONAL_GECTOR_CASE,
            'private_pdf_excluded_case_names_if_absent': sorted(PRIVATE_CASES)}


def harness_snapshot(repo, output):
    paths = [Path(__file__).resolve(), output / 'plan.json', output / 'run-used.py',
             output / 'analysis-package-config.json',
             repo / 'docs/validation/office-fidelity-20261117/cohorts.json',
             repo / 'docs/validation/office-fidelity-20261117/validate.py',
             output / 'fixture-audit.json',
             Path(__file__).with_name('python_controls.py'),
             Path(__file__).with_name('baseline-plan-b32dee6f.json')]
    return {str(path): sha(path) for path in paths}


def node_selection(package, tests):
    """Review platform dependencies in focused test files and relative helpers.

    The production package's conditional imports remain unchanged; successful
    compilation and execution, not this source screen, establish Node support.
    Tests requiring dart:io are retained in the primary VM cohort.
    """
    selected, excluded, review = [], {}, {}
    candidates = sorted(path for path in tests
                        if Path(path).name.startswith(('odt', 'odf', 'odp')))
    for relative in candidates:
        pending, visited, reasons = [package / relative], set(), []
        while pending:
            path = pending.pop().resolve()
            if path in visited:
                continue
            visited.add(path)
            contents = path.read_text()
            # Focused suites currently have no platform directives. Refuse to
            # silently interpret a newly introduced custom platform expression.
            assert not re.search(r'@TestOn\s*\(', contents), 'Review Node platform directive: ' + str(path)
            for uri in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", contents):
                if uri in NODE_UNAVAILABLE_TEST_IMPORTS:
                    reasons.append({'path': str(path.relative_to(package)), 'import': uri})
                elif ':' not in uri:
                    dependency = (path.parent / uri).resolve()
                    if dependency.is_file() and dependency.suffix == '.dart':
                        pending.append(dependency)
        review[relative] = {
            'source_sha256': sha(package / relative),
            'relative_dart_closure_sha256': {str(path.relative_to(package)): sha(path) for path in sorted(visited)},
            'selected_for_node': not reasons,
        }
        if reasons:
            excluded[relative] = {
                'reason': 'Focused test or its relative helper imports a platform library unavailable to this Node/dart2js lane; unchanged test remains in the VM cohort.',
                'imports': reasons,
            }
        else:
            selected.append(relative)
    assert selected, 'Expected focused ODT/ODF/ODP Node repetitions.'
    return {'kind': 'engine', 'platform': 'node', 'repeats': 'engine-integration',
            'tests': selected, 'candidates': candidates, 'excluded_tests': excluded,
            'selection_review': review, 'process_timeout_seconds': NODE_TIMEOUT_SECONDS,
            'suite_load_timeout': '180s', 'case_timeout': '60s',
            'new_unique_test_cases_claimed': False}


def make_plan(repo, commit):
    manifest = repo / 'docs/validation/office-fidelity-20261117/cohorts.json'
    fidelity = json.loads(manifest.read_text())
    cohorts = {}
    for kind in ('engine', 'editor'):
        package = repo / 'packages' / PACKAGE_NAMES[kind]
        zotero = {str(p.relative_to(package)) for p in (package / 'test').rglob('*zotero*test.dart')}
        selected = {'test/' + name for name in fidelity[kind]} - zotero
        if kind == 'engine':
            selected.update(str(p.relative_to(package)) for p in (package / 'test/proofing').glob('*_test.dart'))
            selected.update(('test/word_layout_test.dart', 'test/word_styles_layout_test.dart'))
        else:
            for pattern in ('word_proofing*_test.dart', 'word_hyphenation*_test.dart'):
                selected.update(str(p.relative_to(package)) for p in (package / 'test').glob(pattern))
            selected.add('test/platform_spelling_provider_test.dart')
        changed_tests = git_text(repo, 'diff', '--name-only', BASELINE, commit, '--', 'packages/' + PACKAGE_NAMES[kind] + '/test').splitlines()
        selected.update(str((repo / p).relative_to(package)) for p in changed_tests if p.endswith('_test.dart') and (repo / p).is_file())
        if kind == 'engine':
            selected.update(REQUIRED_INCOMING_TESTS)
            for pattern in ('odt*_test.dart', 'ods*_test.dart', 'odp*_test.dart', 'odf*_test.dart', 'office_text*_test.dart', 'office_search*_test.dart'):
                selected.update(str(p.relative_to(package)) for p in (package / 'test').glob(pattern))
        selected -= zotero
        cohorts[kind + '-zotero'] = {'kind': kind, 'tests': sorted(zotero)}
        cohorts[kind + '-integration'] = {'kind': kind, 'tests': sorted(selected)}
    cohorts['harper-contract'] = {'kind': 'harper', 'tests': ['test/' + p for p in fidelity['harper']]}
    gector = repo / 'packages' / PACKAGE_NAMES['gector']
    cohorts['gector-contract'] = {'kind': 'gector', 'tests': sorted(str(p.relative_to(gector)) for p in (gector / 'test').rglob('*_test.dart'))}
    # Put core recovery first; all five cohorts are disjoint by package/file.
    cohorts = {name: cohorts[name] for name in ('engine-zotero', 'editor-zotero', 'engine-integration', 'editor-integration', 'harper-contract', 'gector-contract')}
    selected = [(value['kind'], path) for value in cohorts.values() for path in value['tests']]
    assert len(selected) == len(set(selected)) and len(selected) >= 144, len(selected)
    prior_path = Path(__file__).with_name('baseline-plan-b32dee6f.json')
    assert sha(prior_path) == BASELINE_PLAN_SHA256, 'Preserved original selection changed.'
    prior = json.loads(prior_path.read_text())
    prior_selected = {(value['kind'], path) for value in prior['cohorts'].values() for path in value['tests']}
    assert len(prior_selected) == prior['unique_test_files'] == 174
    missing_prior = sorted(prior_selected - set(selected))
    assert not missing_prior, 'Original 174-file coverage was lost: ' + repr(missing_prior)
    additions = sorted(set(selected) - prior_selected)
    for kind, relative in selected:
        assert (repo / 'packages' / PACKAGE_NAMES[kind] / relative).is_file(), relative
    targets = {}
    for kind, name in PACKAGE_NAMES.items():
        changed = git_text(repo, 'diff', '--name-only', BASELINE, commit, '--', 'packages/' + name).splitlines()
        paths = {p for p in changed if p.endswith('.dart') and (repo / p).is_file()}
        # Include directly recovered Zotero source even when already on main.
        if kind in ('engine', 'editor'):
            paths.update(str(p.relative_to(repo)) for p in (repo / 'packages' / name / 'lib').rglob('*zotero*.dart'))
            paths.update('packages/' + name + '/' + p for p in cohorts[kind + '-zotero']['tests'])
        else:
            paths.update(str(p.relative_to(repo)) for p in (repo / 'packages' / name / 'lib').rglob('*.dart'))
            paths.update('packages/' + name + '/' + p for p in cohorts[kind + '-contract']['tests'])
        assert paths, kind
        targets[kind] = sorted(paths)
    changed_existing_dart = {p for p in git_text(repo, 'diff', '--name-only', BASELINE, commit).splitlines()
                             if p.endswith('.dart') and not p.startswith('docs/') and (repo / p).is_file()}
    generated = {}
    package = repo / 'packages/quds_office_engine'
    for relative in ('third_party/proofing/manifest.json', 'third_party/proofing/morphology_manifest.json'):
        manifest_path = package / relative
        generated_manifest = json.loads(manifest_path.read_text())
        for path, expected in generated_manifest['generated_files'].items():
            generated_path = package / path
            assert sha(generated_path) == expected, 'Generated data hash mismatch: ' + str(generated_path)
            if path.endswith('.dart'):
                assert generated_path.read_text().startswith('// GENERATED by tool/proofing/'), path
                generated[str(generated_path.relative_to(repo))] = {'sha256': expected, 'manifest': str(manifest_path.relative_to(repo)), 'manifest_sha256': sha(manifest_path), 'reason': 'Generator-owned byte output; adjacent encoded-literal indentation is intentionally preserved and checked against the committed manifest.'}
    format_targets = sorted((changed_existing_dart | RECOVERED_PRODUCTION_FORMAT_TARGETS) - set(generated))
    node = node_selection(repo / 'packages/quds_office_engine', cohorts['engine-integration']['tests'])
    return {'source_commit': commit, 'analysis_baseline': git_text(repo, 'rev-parse', BASELINE),
            'source_manifest': str(manifest.relative_to(repo)), 'source_manifest_sha256': sha(manifest),
            'derivation': 'Retained Office fidelity and complete Zotero cohorts, current engine proofing, complete ODF writer/reader/extraction suites, all engine/editor test files changed since previously landed main, and all GECToR contract tests. Package/file selections are disjoint.',
            'cohorts': cohorts, 'unique_test_files': len(selected),
            'preserved_prior_coverage': {'source_commit': prior['source_commit'],
                'plan_sha256': BASELINE_PLAN_SHA256, 'unique_test_files': len(prior_selected),
                'missing_files': missing_prior, 'added_files': additions},
            'node_repetitions': {'engine-focused-node': node},
            'primary_and_node_file_executions': len(selected) + len(node['tests']),
            'analysis_targets': targets, 'format_targets': format_targets,
            'format_scope': 'Every existing non-evidence Dart path changed since previously landed main plus four recovered Zotero production targets, excluding only explicitly manifest-authenticated generated data. Unchanged inherited test formatting is not claimed.',
            'generated_format_exclusions': {path: generated[path] for path in sorted(generated) if path in changed_existing_dart},
            'generated_data_manifest_check': generated,
            'optional_missing_native_fixture_case': OPTIONAL_GECTOR_CASE,
            'optional_missing_python_converter_case': OPTIONAL_PYTHON_CASE,
            'changed_existing_dart_paths': sorted(changed_existing_dart),
            'coverage_exclusions_if_private_pdf_absent': sorted(PRIVATE_CASES)}


def test_summary(stdout, selected, private_pdf_absent, cwd):
    events = []
    for line in stdout.decode(errors='replace').splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict):
            events.append(item)
    starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    suites = {e['suite']['id']: e['suite'] for e in events if e.get('type') == 'suite'}
    outcomes = collections.Counter()
    completed = []
    exclusions = []
    allowed_skips = []
    for event in events:
        if event.get('type') != 'testDone' or event.get('hidden'):
            continue
        record = starts.get(event['testID'])
        assert record is not None, event
        outcome = 'skipped' if event.get('skipped') else event.get('result', 'unknown')
        outcomes[outcome] += 1
        row = {'test_id': event['testID'], 'suite_id': record['suiteID'], 'name': record['name'], 'outcome': outcome}
        suite = suites.get(record['suiteID'], {})
        suite_path = suite.get('path', '')
        suite_path = unquote(urlparse(suite_path).path) if suite_path.startswith('file:') else suite_path
        row['resolved_suite_path'] = str((Path(suite_path) if Path(suite_path).is_absolute() else cwd / suite_path).resolve())
        completed.append(row)
        if outcome == 'skipped' and record['name'] == OPTIONAL_GECTOR_CASE and suite.get('path', '').endswith('/native_backend_test.dart'):
            allowed_skips.append(row | {'reason': 'Four explicitly pinned native model/library fixture variables are not provided. No real native acceptance claimed.'})
        matched_private_case = next((case for case in PRIVATE_CASES
                                     if record['name'] == case or record['name'].endswith(' ' + case)), None)
        if outcome == 'success' and private_pdf_absent and matched_private_case and suite.get('path', '').endswith('/pdf_file_test.dart'):
            exclusions.append(row | {'matched_case_name': matched_private_case,
                                      'reason': 'Unavailable optional private PDF fixture; inherited early return before assertions.'})
    done = [e for e in events if e.get('type') == 'done']
    errors = [e for e in events if e.get('type') == 'error']
    start_counts = collections.Counter(e['test']['id'] for e in events if e.get('type') == 'testStart')
    completion_counts = collections.Counter(e['testID'] for e in events if e.get('type') == 'testDone')
    missing_completions = sorted(set(starts) - set(completion_counts))
    duplicate_starts = sorted(test_id for test_id, count in start_counts.items() if count != 1)
    duplicate_completions = sorted(test_id for test_id, count in completion_counts.items() if count != 1)
    actual_paths = [unquote(urlparse(s['path']).path) if s['path'].startswith('file:') else s['path'] for s in suites.values()]
    actual_resolved = {(Path(path) if Path(path).is_absolute() else cwd / path).resolve() for path in actual_paths}
    expected_resolved = {(cwd / path).resolve() for path in selected}
    missing_suites = [path for path in selected if (cwd / path).resolve() not in actual_resolved]
    unexpected_suites = sorted(str(path) for path in actual_resolved - expected_resolved)
    expected_exclusions = PRIVATE_CASES if private_pdf_absent and 'test/pdf_file_test.dart' in selected else set()
    exclusions_exact = (len(exclusions) == len(expected_exclusions)
                        and {row['matched_case_name'] for row in exclusions} == expected_exclusions)
    unexpected_skips = [row for row in completed if row['outcome'] == 'skipped' and row['test_id'] not in {item['test_id'] for item in allowed_skips}]
    return {'raw_runner_outcomes': dict(outcomes), 'completed_tests': completed,
            'raw_success_count': outcomes['success'], 'substantive_success_count': outcomes['success'] - len(exclusions),
            'excluded_success_cases': exclusions, 'suite_paths': actual_paths,
            'allowed_skipped_cases': allowed_skips, 'unexpected_skipped_cases': unexpected_skips,
            'resolved_suite_paths': sorted(str(path) for path in actual_resolved),
            'missing_selected_suites': missing_suites, 'unexpected_suites': unexpected_suites, 'errors': errors,
            'missing_test_completions': missing_completions,
            'duplicate_test_start_ids': duplicate_starts, 'duplicate_test_completion_ids': duplicate_completions,
            'expected_exclusion_names': sorted(expected_exclusions), 'exclusions_exact': exclusions_exact,
            'runner_success': bool(done and done[-1].get('success')),
            'passed': bool(done and done[-1].get('success')) and not errors and not missing_suites and not unexpected_suites and exclusions_exact
                      and bool(completed) and not missing_completions and not duplicate_starts and not duplicate_completions
                      and not unexpected_skips and all(k in ('success', 'skipped') or v == 0 for k, v in outcomes.items())}


def compare_repetition(primary_summary, repeated_summary, selected, cwd):
    paths = {str((cwd / path).resolve()) for path in selected}
    def cases(summary):
        return collections.Counter((row['resolved_suite_path'], row['name'], row['outcome'])
                                   for row in summary['completed_tests']
                                   if row['resolved_suite_path'] in paths)
    primary, repeated = cases(primary_summary), cases(repeated_summary)
    def rows(counter):
        return [{'suite_path': path, 'name': name, 'outcome': outcome, 'count': count}
                for (path, name, outcome), count in sorted(counter.items())]
    return {'method': 'Exact multiset comparison of selected VM and Node case identities and outcomes; invocation-local test IDs are ignored.',
            'vm_case_executions': sum(primary.values()), 'node_case_executions': sum(repeated.values()),
            'missing_or_changed_from_vm': rows(primary - repeated),
            'unexpected_or_changed_in_node': rows(repeated - primary),
            'passed': bool(primary) and primary == repeated}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--flutter-root', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--plan-only', action='store_true')
    args = parser.parse_args()
    repo, runtime, workspace, output = (p.resolve() for p in (args.repo, args.flutter_root, args.workspace, args.output))
    output.mkdir(parents=True, exist_ok=True)
    assert re.fullmatch('[a-f0-9]{40}', args.source_commit)
    assert git_text(repo, 'rev-parse', 'HEAD') == args.source_commit
    assert not git_text(repo, 'status', '--porcelain', '--untracked-files=no'), 'Tracked checkout must be clean.'
    plan = make_plan(repo, args.source_commit)
    save(output / 'plan.json', plan)
    if args.plan_only:
        print(json.dumps({'test_files': plan['unique_test_files'], 'cohorts': {k: len(v['tests']) for k, v in plan['cohorts'].items()}, 'analysis_paths': {k: len(v) for k, v in plan['analysis_targets'].items()}, 'format_paths': len(plan['format_targets']), 'prior_174_files_preserved': not plan['preserved_prior_coverage']['missing_files'], 'added_files': plan['preserved_prior_coverage']['added_files'], 'node_repetition_files': {k: len(v['tests']) for k, v in plan['node_repetitions'].items()}, 'node_excluded_files': {k: sorted(v['excluded_tests']) for k, v in plan['node_repetitions'].items()}}))
        return
    assert not (output / 'receipt.json').exists(), 'Never overwrite an attempt; use a fresh output directory.'
    run_lock = (output / 'run.lock').open('a+')
    fcntl.flock(run_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    dart = runtime / 'bin/cache/dart-sdk/bin/dart'
    snapshot = runtime / 'bin/cache/flutter_tools.snapshot'
    graph_path = workspace / '.dart_tool/package_config.json'
    assert sha(workspace / 'pubspec.lock') == EXPECTED_LOCK
    metadata = json.loads((runtime / 'bin/cache/flutter.version.json').read_text())
    assert metadata['frameworkRevision'] == '737ba8f885dc774b53b442759999a312c9461e4e', metadata
    assert metadata['engineRevision'] == 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8', metadata
    assert metadata['dartSdkVersion'] == '3.13.7', metadata
    for executable in (dart, snapshot, runtime / 'bin/cache/artifacts/engine/linux-x64/flutter_tester'):
        assert executable.is_file(), executable
    node_executable = shutil.which('node')
    assert node_executable, 'Node executable not found.'
    node_executable = Path(node_executable).resolve()
    node_metadata = {'executable': str(node_executable), 'sha256': sha(node_executable),
                     'version': subprocess.check_output([str(node_executable), '--version'], text=True, timeout=30).strip()}
    graph = normalized_graph(graph_path, repo)
    assert (workspace / 'tools').resolve() == repo / 'tools'
    for manifest in [workspace / 'pubspec.yaml', workspace / 'analysis_options.yaml', *workspace.glob('packages/*/pubspec.yaml'), *workspace.glob('packages/*/example/pubspec.yaml'), *workspace.glob('apps/*/pubspec.yaml')]:
        assert manifest.read_bytes() == (repo / manifest.relative_to(workspace)).read_bytes(), 'Workspace manifest differs from frozen source: ' + str(manifest)
    for name in PACKAGE_NAMES.values():
        for folder in ('lib', 'test'):
            assert (workspace / 'packages' / name / folder).resolve() == repo / 'packages' / name / folder
    source_before = source_snapshot(repo, args.source_commit)
    assert not source_before['commit_mismatches'], source_before['commit_mismatches']
    assert not source_before['untracked_non_evidence_paths'], source_before['untracked_non_evidence_paths']
    before = {'source': source_before, 'dependencies': dependency_snapshot(graph, repo),
              'runtime': runtime_snapshot(runtime), 'workspace': workspace_snapshot(workspace), 'system': system_snapshot()}
    save(output / 'analysis-package-config.json', graph)
    (output / 'run-used.py').write_bytes(Path(__file__).read_bytes())
    save(output / 'fixture-audit.json', fixture_audit(repo, workspace, plan))
    before['harness'] = harness_snapshot(repo, output)
    for key, value in before.items():
        save(output / (key + '-before.json'), value)
    original_config = repo / '.dart_tool/package_config.json'
    original_bytes = original_config.read_bytes() if original_config.exists() else None
    original_directory_existed = original_config.parent.exists()
    if original_bytes is not None:
        (output / 'analysis-original-package-config.json').write_bytes(original_bytes)
    env_keys = ('FLUTTER_ROOT', 'PUB_CACHE', 'TMPDIR', 'XDG_CONFIG_HOME', 'CI', 'DART_SUPPRESS_ANALYTICS', 'FLUTTER_SUPPRESS_ANALYTICS')
    receipt = {'started_utc': now(), 'status': 'running', 'source_commit': args.source_commit,
               'source_tree': git_text(repo, 'rev-parse', args.source_commit + '^{tree}'),
               'repo': str(repo), 'test_workspace': str(workspace), 'flutter_root': str(runtime),
               'runner_sha256': sha(Path(__file__)), 'plan_sha256': sha(output / 'plan.json'),
               'historical_qualifications_counted': False, 'cohorts_disjoint': True,
               'cohorts_disjoint_scope': 'Primary VM/Flutter cohorts only; Node is reported separately as repetition.',
               'node_runtime': node_metadata, 'node_cases_are_repetitions': True,
               'enforced_workspace_lock_sha256': EXPECTED_LOCK,
               'runtime_metadata': metadata, 'expected_zotero_counts': EXPECTED_ZOTERO_COUNTS,
               'environment': {key: os.environ.get(key) for key in env_keys},
               'original_analyzer_config_sha256': digest(original_bytes) if original_bytes is not None else None,
               'github_actions_queried_awaited_or_rerun': False, 'commands': []}
    save(output / 'receipt.json', receipt)

    def command(name, argv, cwd, *, selected=None, extra_env=None, timeout_seconds=900, repetition_of=None):
        directory = output / name
        directory.mkdir()
        row = {'name': name, 'command': [str(x) for x in argv], 'cwd': str(cwd),
               'started_utc': now(), 'status': 'running', 'timeout_seconds': timeout_seconds,
               'environment_overrides': extra_env or {}}
        receipt['commands'].append(row)
        save(output / 'receipt.json', receipt)
        print(json.dumps({'event': 'command-start', 'name': name}), flush=True)
        start = time.monotonic()
        timed_out = False
        with (directory / 'stdout').open('wb') as out, (directory / 'stderr').open('wb') as err:
            process = subprocess.Popen(row['command'], cwd=cwd, stdout=out, stderr=err,
                                       env=dict(os.environ, **(extra_env or {})), start_new_session=True)
            while True:
                remaining = timeout_seconds - (time.monotonic() - start)
                try:
                    code = process.wait(timeout=max(0, min(15, remaining)))
                    break
                except subprocess.TimeoutExpired:
                    if remaining > 0:
                        print(json.dumps({'event': 'heartbeat', 'name': name, 'elapsed_seconds': round(time.monotonic() - start, 1)}), flush=True)
                        continue
                    timed_out = True
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    code = 124
                    break
        row.update({'finished_utc': now(), 'duration_seconds': round(time.monotonic() - start, 3),
                    'exit_code': code, 'timed_out': timed_out})
        for stream in ('stdout', 'stderr'):
            raw = (directory / stream).read_bytes()
            packed = gzip.compress(raw, mtime=0)
            (directory / (stream + '.gz')).write_bytes(packed)
            row[stream] = str((directory / (stream + '.gz')).relative_to(output))
            row[stream + '_sha256'] = digest(raw)
            row[stream + '_gzip_sha256'] = digest(packed)
            (directory / stream).unlink()
            if stream == 'stdout' and selected is not None:
                row['test_summary'] = test_summary(raw, selected, before['system'][PRIVATE_PDF] is None, cwd)
                if name in EXPECTED_ZOTERO_COUNTS:
                    summary = row['test_summary']
                    summary['expected_raw_success_count'] = EXPECTED_ZOTERO_COUNTS[name]
                    summary['expected_core_count_matched'] = summary['raw_success_count'] == EXPECTED_ZOTERO_COUNTS[name]
                    summary['passed'] = summary['passed'] and summary['expected_core_count_matched']
                if repetition_of is not None:
                    primary = next(item for item in receipt['commands'] if item['name'] == repetition_of)
                    assert primary['status'] == 'passed', 'Node repetition requires accepted VM cases.'
                    summary = row['test_summary']
                    summary['repetition_comparison'] = compare_repetition(primary['test_summary'], summary, selected, cwd)
                    summary['passed'] = summary['passed'] and summary['repetition_comparison']['passed']
                    row['repetition_of'] = repetition_of
                save(directory / 'test-summary.json', row['test_summary'])
        if name == 'python-controls' and code == 0:
            summary_path = output / 'python-controls-summary.json'
            row['python_summary'] = json.loads(summary_path.read_text())
            row['python_summary_sha256'] = sha(summary_path)
        row['status'] = 'passed' if code == 0 and (selected is None or row['test_summary']['passed']) and (name != 'python-controls' or row.get('python_summary', {}).get('passed')) else 'failed'
        save(output / 'receipt.json', receipt)
        print(json.dumps({'event': 'command-finish', 'name': name, 'status': row['status'],
                          'raw_passes': row.get('test_summary', {}).get('raw_success_count'),
                          'qualified_passes': row.get('test_summary', {}).get('substantive_success_count')}), flush=True)
        if row['status'] != 'passed':
            raise RuntimeError(name + ' failed; original logs retained')

    error = None
    try:
        # A strict preflight avoids wasting full test runs on incoming source lints.
        original_config.parent.mkdir(exist_ok=True)
        original_config.write_text(json.dumps(graph, indent=2) + '\n')
        for kind, paths in plan['analysis_targets'].items():
            command(kind + '-strict-analysis', [dart, 'analyze', '--fatal-infos', *paths], repo)
        format_paths = plan['format_targets']
        command('format', [dart, 'format', '--language-version=3.12', '--output=none', '--set-exit-if-changed', *format_paths], repo)
        command('python-controls', [sys.executable, Path(__file__).with_name('python_controls.py'), '--repo', repo, '--output', output / 'python-controls-summary.json'], repo, extra_env={'PYTHONDONTWRITEBYTECODE': '1'})
        # Restore the original analyzer configuration before running tests.
        if original_bytes is None:
            original_config.unlink()
        else:
            original_config.write_bytes(original_bytes)
        for name, cohort in plan['cohorts'].items():
            kind = cohort['kind']
            artifact = output / name / 'artifacts'
            exports = {'QUDS_ALIAS_RENDER_OUTPUT': str(artifact / 'render'),
                       'QUDS_LOGICAL_RENDER_OUTPUT': str(artifact / 'logical-render'),
                       'QUDS_CONDITIONAL_RENDER_OUTPUT': str(artifact / 'conditional-render'),
                       'QUDS_ODF_FIXTURE_OUTPUT': str(artifact / 'odf-fixtures')}
            argv = ([dart, snapshot, 'test', '--no-pub', '--dart-define=QUDS_SUBSET_RENDER_OUTPUT=' + str(artifact / 'render')]
                    if kind == 'editor' else [dart, 'test'])
            argv += ['--concurrency=2', '--reporter=json', *cohort['tests']]
            command(name, argv, workspace / 'packages' / PACKAGE_NAMES[kind], selected=cohort['tests'], extra_env=exports)
        for name, cohort in plan['node_repetitions'].items():
            argv = [dart, 'test', '--platform=node', '--concurrency=2', '--reporter=json',
                    '--suite-load-timeout=' + cohort['suite_load_timeout'],
                    '--timeout=' + cohort['case_timeout'], *cohort['tests']]
            command(name, argv, workspace / 'packages/quds_office_engine', selected=cohort['tests'],
                    extra_env={'PATH': str(node_executable.parent) + os.pathsep + os.environ['PATH']},
                    timeout_seconds=cohort['process_timeout_seconds'], repetition_of=cohort['repeats'])
    except BaseException as caught:
        error = caught
        save(output / 'runner-error.json', {'error': type(caught).__name__ + ': ' + str(caught), 'traceback': traceback.format_exc(), 'recorded_utc': now()})
    finally:
        if original_bytes is None:
            original_config.unlink(missing_ok=True)
            if not original_directory_existed and original_config.parent.exists() and not any(original_config.parent.iterdir()):
                original_config.parent.rmdir()
        else:
            original_config.write_bytes(original_bytes)
        after = {'source': source_snapshot(repo, args.source_commit), 'dependencies': dependency_snapshot(graph, repo),
                 'runtime': runtime_snapshot(runtime), 'workspace': workspace_snapshot(workspace), 'system': system_snapshot(),
                 'harness': harness_snapshot(repo, output)}
        for key, value in after.items():
            save(output / (key + '-after.json'), value)
        receipt['input_integrity'] = {key + '_unchanged': before[key] == after[key] for key in before}
        receipt['analysis_config_restored'] = (original_config.read_bytes() if original_config.exists() else None) == original_bytes
        receipt['working_head_after'] = git_text(repo, 'rev-parse', 'HEAD')
        receipt['source_matches_frozen_commit'] = not after['source']['commit_mismatches'] and not after['source']['untracked_non_evidence_paths']
        receipt['tests_by_cohort'] = {row['name']: {k: row['test_summary'][k] for k in ('raw_success_count', 'substantive_success_count', 'excluded_success_cases', 'raw_runner_outcomes', 'allowed_skipped_cases')}
                                      for row in receipt['commands'] if 'test_summary' in row and row['name'] in plan['cohorts']}
        receipt['repetitions_by_cohort'] = {row['name']: {k: row['test_summary'].get(k) for k in ('raw_success_count', 'substantive_success_count', 'excluded_success_cases', 'raw_runner_outcomes', 'allowed_skipped_cases', 'repetition_comparison')}
                                          for row in receipt['commands'] if 'test_summary' in row and row['name'] in plan['node_repetitions']}
        receipt['raw_runner_success_total'] = sum(v['raw_success_count'] for v in receipt['tests_by_cohort'].values())
        receipt['substantive_success_total'] = sum(v['substantive_success_count'] for v in receipt['tests_by_cohort'].values())
        receipt['node_substantive_success_total'] = sum(v['substantive_success_count'] for v in receipt['repetitions_by_cohort'].values())
        receipt['all_runtime_successful_executions'] = receipt['substantive_success_total'] + receipt['node_substantive_success_total']
        receipt['count_scope'] = 'Primary substantive_success_total retains the original VM/Flutter scope. Node successes are repetitions and are only added in all_runtime_successful_executions.'
        receipt['python_controls_summary'] = next((row['python_summary'] for row in receipt['commands'] if 'python_summary' in row), None)
        receipt['all_passed'] = (error is None and len(receipt['commands']) == len(plan['analysis_targets']) + len(plan['cohorts']) + len(plan['node_repetitions']) + 2
                                 and all(row['status'] == 'passed' for row in receipt['commands'])
                                 and all(receipt['input_integrity'].values()) and receipt['analysis_config_restored']
                                 and receipt['source_matches_frozen_commit']
                                 and receipt['working_head_after'] == args.source_commit)
        receipt.update({'finished_utc': now(), 'status': 'passed' if receipt['all_passed'] else 'failed'})
        save(output / 'receipt.json', receipt)
        print(json.dumps({key: receipt[key] for key in ('status', 'tests_by_cohort', 'substantive_success_total', 'repetitions_by_cohort', 'node_substantive_success_total', 'input_integrity', 'analysis_config_restored')}), flush=True)
    if not receipt['all_passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
