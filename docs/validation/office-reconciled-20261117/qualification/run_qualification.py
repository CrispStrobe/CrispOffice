#!/usr/bin/env python3
"""Requalify current Office sources while respecting the deliberate AOT removal.

The sealed historical runner supplies source/dependency/runtime integrity checks,
exact suite-event accounting, strict analysis and explicit private-fixture
exclusions. This adapter retains all 179 baseline suites, selects the current
Office/proofing additions and requires the available native and ONNX controls.
"""
import hashlib
import json
import os
from pathlib import Path

import prior_run_qualification as prior

HERE = Path(__file__).resolve().parent
HISTORICAL = json.loads((HERE / 'historical-plan-179.json').read_text())
assert HISTORICAL['unique_test_files'] == 179
assert prior.sha(HERE / 'prior_run_qualification.py') == 'd5b52d06f778704d17aad737651c4b63548c6f1b5ad931cb7651d25314d6579a'
NATIVE_HASHES = {
    'GECTOR_TEST_LIBRARY': '9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604',
    'GECTOR_TEST_MODEL': '549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b',
}
old_make_plan = prior.make_plan
old_system_snapshot = prior.system_snapshot
old_fixture_audit = prior.fixture_audit
old_harness_snapshot = prior.harness_snapshot
old_test_summary = prior.test_summary


def make_plan(repo, commit):
    plan = old_make_plan(repo, commit)
    assert not (repo / 'packages/quds_proofing_aot').exists()
    assert 'quds_proofing_aot' not in (repo / 'pubspec.yaml').read_text()
    old_pairs = {(group['kind'], path) for group in HISTORICAL['cohorts'].values() for path in group['tests']}
    for name, group in HISTORICAL['cohorts'].items():
        current = plan['cohorts'][name]
        assert current['kind'] == group['kind']
        current['tests'] = sorted(set(current['tests']) | set(group['tests']))
    pairs = [(group['kind'], path) for group in plan['cohorts'].values() for path in group['tests']]
    assert len(pairs) == len(set(pairs)) and old_pairs <= set(pairs)
    for kind, path in pairs:
        assert (repo / 'packages' / prior.PACKAGE_NAMES[kind] / path).is_file(), (kind, path)
    plan['unique_test_files'] = len(pairs)
    plan['historical_selection'] = {
        'plan_sha256': prior.sha(HERE / 'historical-plan-179.json'),
        'retained_baseline_files': len(old_pairs), 'missing_baseline_files': [],
        'added_files': [list(pair) for pair in sorted(set(pairs) - old_pairs)],
        'historical_outcomes_counted': False,
        'intentional_exclusion': 'The subsequently added AOT/RML package and Studio AOT integration were removed upstream by explicit owner direction. Their historical tests and outcomes are not included in this qualification.',
    }
    plan['analysis_targets'].pop('incoming-onnx-tool')
    plan['analysis_targets']['proofing-tools'] = sorted(str(path.relative_to(repo)) for path in (repo / 'tools/proofing/german_model').glob('*.dart'))
    plan['required_native_fixture'] = NATIVE_HASHES
    plan['allowed_test_skips'] = []
    plan['required_python_modules'] = ['onnx', 'onnxruntime', 'numpy']
    return plan


def native_fixtures():
    result = {}
    for variable, expected in NATIVE_HASHES.items():
        path = Path(os.environ[variable]).resolve()
        assert path.is_file() and prior.sha(path) == expected
        assert os.environ[variable + '_SHA256'] == expected
        result[str(path)] = {'environment_variable': variable, 'sha256': expected, 'bytes': path.stat().st_size}
    return result


def system_snapshot():
    result = old_system_snapshot()
    result.update({path: row['sha256'] for path, row in native_fixtures().items()})
    return result


def fixture_audit(repo, workspace, plan):
    result = old_fixture_audit(repo, workspace, plan)
    result['required_native_fixtures'] = native_fixtures()
    result['native_skip_allowed'] = False
    return result


def harness_snapshot(repo, output):
    result = old_harness_snapshot(repo, output)
    for name in ('prior_run_qualification.py', 'prior_python_controls.py', 'historical-plan-179.json', 'prepare_workspace.py'):
        result[str(HERE / name)] = prior.sha(HERE / name)
    return result


def test_summary(stdout, selected, private_pdf_absent, cwd):
    result = old_test_summary(stdout, selected, private_pdf_absent, cwd)
    skipped = [row for row in result['completed_tests'] if row['outcome'] == 'skipped']
    result['allowed_skipped_cases'] = []
    result['unexpected_skipped_cases'] = skipped
    result['passed'] = result['passed'] and not skipped
    return result


prior.make_plan = make_plan
prior.system_snapshot = system_snapshot
prior.fixture_audit = fixture_audit
prior.harness_snapshot = harness_snapshot
prior.test_summary = test_summary
prior.EXPECTED_ZOTERO_COUNTS = {}
prior.__file__ = str(Path(__file__).resolve())

if __name__ == '__main__':
    prior.main()
