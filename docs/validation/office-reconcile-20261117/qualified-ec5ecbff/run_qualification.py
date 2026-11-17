#!/usr/bin/env python3
"""Extend the exact prior canonical runner while retaining every selected suite.

The prior runner remains byte-exact beside this file. This adapter expands its
selection, authenticates real native fixtures, and makes skips fail this run.
It does not import historical pass counts into the fresh result.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

import prior_run_qualification as prior

HERE = Path(__file__).resolve().parent
OLD_COMMIT = '7a9702c3b74e0e905c76fcf467d608bbb852d004'
OLD_RUNNER_HASH = 'd5b52d06f778704d17aad737651c4b63548c6f1b5ad931cb7651d25314d6579a'
NATIVE_HASHES = {
    'GECTOR_TEST_LIBRARY': '9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604',
    'GECTOR_TEST_MODEL': '549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b',
}

assert hashlib.sha256((HERE / 'prior_run_qualification.py').read_bytes()).hexdigest() == OLD_RUNNER_HASH
historical = json.loads((HERE / 'historical-plan-179.json').read_text())
assert historical['unique_test_files'] == 179
original_make_plan = prior.make_plan
original_harness_snapshot = prior.harness_snapshot
original_system_snapshot = prior.system_snapshot
original_fixture_audit = prior.fixture_audit
original_test_summary = prior.test_summary
BASE_PACKAGE_NAMES = dict(prior.PACKAGE_NAMES)


def make_plan(repo, commit):
    # The inherited builder knows the four historical package kinds. Extend
    # the resulting plan only after it has built those cohorts unchanged.
    prior.PACKAGE_NAMES = dict(BASE_PACKAGE_NAMES)
    plan = original_make_plan(repo, commit)
    aot = repo / 'packages/quds_proofing_aot'
    assert aot.is_dir(), 'The integrated optional AOT package is required.'
    aot_tests = sorted(str(path.relative_to(aot)) for path in (aot / 'test').rglob('*_test.dart'))
    assert len(aot_tests) >= 6, 'The six incoming AOT test files must all be present.'
    plan['cohorts']['aot-contract'] = {'kind': 'aot', 'tests': aot_tests}
    prior.PACKAGE_NAMES['aot'] = 'quds_proofing_aot'
    studio_test = 'example/test/studio_aot_test.dart'
    assert (repo / 'packages/quds_office_editor' / studio_test).is_file()
    plan['cohorts']['editor-integration']['tests'] = sorted(
        set(plan['cohorts']['editor-integration']['tests']) | {studio_test})
    aot_analysis = sorted(str(path.relative_to(repo))
                          for directory in ('lib', 'test', 'tool')
                          for path in (aot / directory).rglob('*.dart'))
    plan['analysis_targets']['aot'] = aot_analysis
    studio_analysis = ['packages/quds_office_editor/example/lib/studio_aot.dart',
                       'packages/quds_office_editor/' + studio_test]
    plan['analysis_targets']['editor'] = sorted(set(plan['analysis_targets']['editor']) | set(studio_analysis))
    # Existing changed-file formatting already includes these handwritten
    # files; state the complete AOT surface explicitly to prevent omissions.
    plan['format_targets'] = sorted(set(plan['format_targets']) | set(aot_analysis) | set(studio_analysis))
    old_pairs = set()
    for cohort, group in historical['cohorts'].items():
        current = plan['cohorts'][cohort]
        assert current['kind'] == group['kind']
        old_pairs.update((group['kind'], path) for path in group['tests'])
        current['tests'] = sorted(set(current['tests']) | set(group['tests']))
    pairs = [(group['kind'], path)
             for group in plan['cohorts'].values() for path in group['tests']]
    assert len(pairs) == len(set(pairs)), 'Duplicate suite selection'
    for kind, path in pairs:
        assert (repo / 'packages' / prior.PACKAGE_NAMES[kind] / path).is_file(), (kind, path)
    assert old_pairs <= set(pairs), 'Historical suite disappeared'
    plan['unique_test_files'] = len(pairs)
    plan['historical_selection'] = {
        'source_commit': OLD_COMMIT,
        'plan_sha256': prior.sha(HERE / 'historical-plan-179.json'),
        'retained_files': len(old_pairs),
        'missing_files': [],
        'added_files': [list(pair) for pair in sorted(set(pairs) - old_pairs)],
        'historical_test_outcomes_used': False,
    }
    tools = repo / 'tools/proofing/german_model'
    dart_tools = sorted(str(path.relative_to(repo)) for path in tools.glob('*.dart'))
    assert dart_tools, 'Missing incoming AOT/provider Dart tools'
    plan['analysis_targets']['proofing-aot-tools'] = dart_tools
    plan['required_native_fixture'] = NATIVE_HASHES
    plan['allowed_test_skips'] = []
    plan['required_python_modules'] = ['onnx', 'onnxruntime', 'numpy']
    plan['optional_aot_scope'] = {
        'package': 'packages/quds_proofing_aot',
        'test_files': aot_tests,
        'strict_analysis': aot_analysis,
        'studio_widget_test': studio_test,
        'test_runner': 'Dart for the AOT package; Flutter for the Studio widget',
        'external_aot_service_queried': False,
    }
    plan['historical_zotero_counts_for_reference_only'] = {'engine': 390, 'editor': 186}
    plan['derivation'] += ' This continuation additionally requires every one of the previous 179 suites and analyzes every current German model/AOT Dart tool. All pass counts are recounted from this invocation.'
    return plan


def native_fixtures():
    result = {}
    for variable, expected in NATIVE_HASHES.items():
        value = os.environ.get(variable)
        assert value, f'Missing required native fixture variable {variable}'
        path = Path(value).resolve()
        assert path.is_file(), path
        actual = prior.sha(path)
        assert actual == expected, f'Native fixture changed: {path}'
        assert os.environ.get(variable + '_SHA256') == expected, variable
        result[str(path)] = {'environment_variable': variable,
                             'sha256': actual, 'bytes': path.stat().st_size}
    return result


def system_snapshot():
    result = original_system_snapshot()
    for path, row in native_fixtures().items():
        result[path] = row['sha256']
    return result


def fixture_audit(repo, workspace, plan):
    result = original_fixture_audit(repo, workspace, plan)
    result['required_native_fixtures'] = native_fixtures()
    result['native_test_skip_allowed'] = False
    return result


def harness_snapshot(repo, output):
    result = original_harness_snapshot(repo, output)
    for name in ('prior_run_qualification.py', 'prior_python_controls.py',
                 'historical-plan-179.json', 'prepare_workspace.py', 'run_frozen.py'):
        path = HERE / name
        result[str(path)] = prior.sha(path)
    return result


def test_summary(stdout, selected, private_pdf_absent, cwd):
    result = original_test_summary(stdout, selected, private_pdf_absent, cwd)
    skipped = [row for row in result['completed_tests'] if row['outcome'] == 'skipped']
    result['allowed_skipped_cases'] = []
    result['unexpected_skipped_cases'] = skipped
    result['passed'] = result['passed'] and not skipped
    return result


prior.make_plan = make_plan
prior.harness_snapshot = harness_snapshot
prior.system_snapshot = system_snapshot
prior.fixture_audit = fixture_audit
prior.test_summary = test_summary
# Exact historical counts are reference data. Fresh test events determine this
# run's counts; newly added tests must not be rejected for increasing a count.
prior.EXPECTED_ZOTERO_COUNTS = {}
# The inherited runner writes its executed adapter and invokes its adjacent
# Python controls. Both originals are independently sealed in the harness map.
prior.__file__ = str(Path(__file__).resolve())

if __name__ == '__main__':
    prior.main()
