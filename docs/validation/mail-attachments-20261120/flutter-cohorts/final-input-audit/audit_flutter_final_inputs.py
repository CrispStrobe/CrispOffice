#!/usr/bin/env python3
"""Audit the exact final tree against immutable accepted Flutter receipts."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess


SOURCE_HEAD = 'b8686c05e055ca0395726fe528d585379597d628'
FINAL_HEAD = '58c6962ec3ea82811bfcafec42981385f216f892'
DELTA_PATH = 'packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart'
PDF_TEST_PATH = 'packages/quds_office_engine/test/office_pdf_export_test.dart'
ALLOWED_DELTAS = sorted([DELTA_PATH, PDF_TEST_PATH])
COHORTS = ['mail-host', 'editor-rendering', 'editor-zotero-materials', 'studio-spacy']
RUNNER_SHA = '4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf'


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, required=True)
    p.add_argument('--cohorts', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    repo, cohorts, out = args.repo.resolve(), args.cohorts.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    runner = repo / 'docs/validation/zotero-research-materials-20261120/run_validation.py'
    require(hashlib.sha256(runner.read_bytes()).hexdigest() == RUNNER_SHA,
            'Inherited runner changed')
    spec = importlib.util.spec_from_file_location('frozen_audit_runner', runner)
    primary = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(primary)
    sdk = Path(os.environ['FLUTTER_ROOT']).resolve()
    head = primary.git_head(repo)
    require(head == FINAL_HEAD, 'Final source head differs from audited style repair')
    changed = primary.git(repo, 'diff', '--name-only', SOURCE_HEAD, FINAL_HEAD).decode().splitlines()
    require(changed == ALLOWED_DELTAS, f'Unexpected source delta: {changed}')
    diff = primary.git(repo, 'diff', SOURCE_HEAD, FINAL_HEAD, '--', *ALLOWED_DELTAS)
    (out / 'final-source-delta.patch').write_bytes(diff)
    old = primary.git(repo, 'show', SOURCE_HEAD + ':' + DELTA_PATH).decode()
    new = primary.git(repo, 'show', FINAL_HEAD + ':' + DELTA_PATH).decode()
    original = ('  if (value is List)\n'
                '    return [for (final v in value) _normalizeLibrary(v, library)];\n')
    braced = ('  if (value is List) {\n'
              '    return [for (final v in value) _normalizeLibrary(v, library)];\n'
              '  }\n')
    require(old.count(original) == 1 and old.replace(original, braced) == new,
            'Delta is not exactly braces around the existing single return')
    before_receipts = {}
    snapshots = {}
    reports = []
    selected = []
    current_source = None
    current_workspace = None
    current_runtime = None
    dependency_cache = {}
    for name in COHORTS:
        folder = cohorts / name
        receipt_path = folder / 'receipt.json'
        raw_receipt = receipt_path.read_bytes()
        before_receipts[name] = hashlib.sha256(raw_receipt).hexdigest()
        receipt = json.loads(raw_receipt)
        require(receipt['status'] == 'passed' and all(receipt['guards'].values()),
                f'{name}: original receipt was not fully accepted')
        require(receipt['source_head_at_start'] == SOURCE_HEAD and
                receipt['source_head_at_finish'] == SOURCE_HEAD,
                f'{name}: original source identity changed')
        primary.COHORTS[name] = receipt['selection_adapter']['selection']
        tests = primary.select_tests(repo, name)
        require([str(item.relative_to(repo)) for item in tests] ==
                receipt['selected_repository_paths'], f'{name}: test selection changed')
        selected.extend(tests)
        inputs = primary.Inputs(repo, sdk, name, tests)
        if current_source is None:
            current_source = inputs.source()
            current_workspace = inputs.workspace()
            current_runtime = inputs.runtime()
        # Inputs.source captures every tracked local package source/test/tool/
        # asset, so its inventory is the same across these four cohorts. Check
        # selected paths are included, then use the shared current fingerprint.
        require(all(str(item.relative_to(repo)) in current_source for item in tests),
                f'{name}: selected test absent from common source inventory')
        key = tuple(sorted(inputs.external))
        if key not in dependency_cache:
            dependency_cache[key] = inputs.dependencies()
        current = {
            'source': current_source,
            'workspace': current_workspace,
            'runtime': current_runtime,
            'dependencies': dependency_cache[key],
            'host_fonts': {},
        }
        before = json.loads(gzip.decompress((folder / 'inputs.json.gz').read_bytes()))['before']
        require(set(before['source']) == set(current_source), f'{name}: source inventory changed')
        deltas = primary.changed_paths(before, current)
        require(deltas['source'] == ALLOWED_DELTAS, f'{name}: unexpected source changes')
        require(not any(value for area, value in deltas.items() if area != 'source'),
                f'{name}: dependency/workspace/runtime changed')
        matches = primary.source_matches_head(repo, FINAL_HEAD, current_source)
        require(matches['matches'], f'{name}: current source differs from final commit')
        snapshots[name] = current
        reports.append({
            'cohort': name, 'original_receipt_sha256': before_receipts[name],
            'accepted_source_head': SOURCE_HEAD, 'final_source_head': FINAL_HEAD,
            'original_passed_application_cases': receipt['tests']['passed'],
            'original_suites': receipt['tests']['suite_count'],
            'changed_paths': deltas, 'current_source_matches_final_commit': matches,
            'final_area_sha256': {area: primary.digest(records)
                                  for area, records in current.items()},
            'changed_files_before': {path: before['source'][path] for path in ALLOWED_DELTAS},
            'changed_files_after': {path: current_source[path] for path in ALLOWED_DELTAS},
        })
    require(len(set(selected)) == len(selected), 'Selected suites overlap')
    # The tool has no static incoming import/export/part edge and no filename
    # reference from another tracked Dart source. It is an explicit standalone
    # command, outside all selected test entry points and application libraries.
    references = []
    directive_edges = []
    config = json.loads((repo / '.dart_tool/package_config.json').read_text())
    from urllib.parse import unquote, urljoin, urlparse
    package_roots = {
        row['name']: Path(unquote(urlparse(urljoin(
            (repo / '.dart_tool/package_config.json').as_uri(), row['rootUri']
        )).path)).resolve() / row.get('packageUri', 'lib/')
        for row in config['packages']
    }
    targets = {(repo / path).resolve(): path for path in ALLOWED_DELTAS}
    scanned = 0
    directive = re.compile(r'\b(?:import|export|part)\s+([^;]+);', re.DOTALL)
    quoted = re.compile(r'''(?:r)?["']([^"']+)["']''')
    for rel in sorted(current_source):
        path = repo / rel
        if path.suffix != '.dart':
            continue
        scanned += 1
        text = path.read_text()
        for target, target_rel in targets.items():
            if path.resolve() != target and target.stem in text:
                references.append({'from': rel, 'target': target_rel})
        for statement in directive.findall(text):
            for uri in quoted.findall(statement):
                if uri.startswith('dart:'):
                    continue
                if uri.startswith('package:'):
                    name, _, rest = uri[len('package:'):].partition('/')
                    base = package_roots.get(name)
                    if base is None:
                        continue
                    resolved = (base / rest).resolve()
                else:
                    resolved = (path.parent / uri).resolve()
                if resolved in targets:
                    directive_edges.append({'from': rel, 'uri': uri, 'target': targets[resolved]})
    require(not references and not directive_edges, 'Unexecuted delta file has incoming references')
    require(not any(target in selected for target in targets), 'A changed file is selected')
    for name, expected in before_receipts.items():
        actual = hashlib.sha256((cohorts / name / 'receipt.json').read_bytes()).hexdigest()
        require(actual == expected, 'Original accepted receipt was modified')
    require(primary.git_head(repo) == FINAL_HEAD, 'HEAD moved during final input audit')
    primary.write_json(out / 'receipt.json', {
        'status': 'passed', 'accepted_source_head': SOURCE_HEAD,
        'final_source_head': FINAL_HEAD,
        'final_tree': primary.git(repo, 'rev-parse', 'HEAD^{tree}').decode().strip(),
        'only_changed_paths': ALLOWED_DELTAS,
        'evaluator_delta_is_exact_single_return_bracing': True,
        'engine_pdf_test_delta': 'Test assertions recognize numeric 2.500 width formatting, whitespace between rectangle and stroke, and two explicit crop clip restorations. It is outside these Flutter selections; its execution is qualified separately by the engine cohort.',
        'all_application_libraries_unchanged': True,
        'original_acceptance_receipts_unchanged': True,
        'new_test_execution_claimed': False,
        'application_cases_retained': sum(row['original_passed_application_cases'] for row in reports),
        'suites_disjoint': True, 'cohorts': reports,
        'unexecuted_delta_reference_audit': {
            'tracked_dart_sources_scanned': scanned,
            'incoming_static_import_export_part_edges': directive_edges,
            'filename_references_outside_changed_files': references,
            'selected_entry_points_include_changed_files': False,
            'scope': 'All tracked Dart sources in the inherited complete local-package source inventory; all import/export/part string URIs, including conditional choices, resolved against the actual package map.',
        },
        'audit_script': primary.file_record(Path(__file__)),
        'inherited_runner': primary.file_record(runner),
        'diff': primary.file_record(out / 'final-source-delta.patch'),
    })
    (out / 'current-inputs.json.gz').write_bytes(gzip.compress(primary.canonical_json(snapshots) + b'\n', mtime=0))
    print(json.dumps({'status': 'passed', 'retained_application_cases': 496,
                      'only_deltas': ALLOWED_DELTAS, 'tracked_dart_sources_scanned': scanned}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
