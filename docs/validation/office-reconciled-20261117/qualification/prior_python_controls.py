#!/usr/bin/env python3
"""Run the authored offline Python tooling controls with explicit skip accounting."""
from pathlib import Path
import argparse
import ast
import hashlib
import importlib.util
import json
import platform
import sys
import unittest

MODULES = [
    'test_export_reference', 'test_qualification', 'test_native_pack',
    'test_native_qualification', 'test_gector_aot_build',
    'test_guarded_provider_comparison',
]
OPTIONAL_CASE = 'test_qualification.TinyConverterTests.test_real_quantizer_preserves_both_head_matrices'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot():
    specification = importlib.util.find_spec('numpy')
    assert specification and specification.origin, 'Authored export controls require NumPy.'
    root = Path(specification.origin).parent
    paths = sorted(p for p in root.rglob('*') if p.is_file() and p.suffix in ('.py', '.so', '.json', '.txt'))
    return {
        'python_version': sys.version, 'platform': platform.platform(),
        'python_executable': str(Path(sys.executable).resolve()),
        'python_executable_sha256': sha(Path(sys.executable).resolve()),
        'numpy_inputs_sha256': {str(p): sha(p) for p in paths},
        'onnx_available': importlib.util.find_spec('onnx') is not None,
        'onnxruntime_available': importlib.util.find_spec('onnxruntime') is not None,
    }


class RecordingResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.successes = []
        self.started = []

    def startTest(self, test):
        self.started.append(test.id())
        super().startTest(test)

    def addSuccess(self, test):
        self.successes.append(test.id())
        super().addSuccess(test)


def flatten(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from flatten(item)
        else:
            yield item.id()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = args.repo.resolve() / 'tools/proofing/german_model'
    assert all((source / (name + '.py')).is_file() for name in MODULES)
    incoming_backend = source / 'onnx_probe_backend.py'
    ast.parse(incoming_backend.read_text(), filename=str(incoming_backend))
    incoming_syntax_check = {'path': str(incoming_backend), 'sha256': sha(incoming_backend), 'parsed': True, 'imported_or_executed': False, 'counted_as_product_test': False}
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(source))
    before = snapshot()
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromNames(MODULES)
    assert not loader.errors, loader.errors
    selected = list(flatten(suite))
    assert selected and len(selected) == len(set(selected)), 'Missing or duplicated test selection.'
    result = unittest.TextTestRunner(stream=sys.stderr, verbosity=2, resultclass=RecordingResult).run(suite)
    after = snapshot()
    skips = [{'test': test.id(), 'reason': reason} for test, reason in result.skipped]
    optional_missing = not before['onnx_available'] or not before['onnxruntime_available']
    allowed = {OPTIONAL_CASE} if optional_missing else set()
    unexpected_skips = [row for row in skips if row['test'] not in allowed]
    missing = sorted(set(selected) - set(result.started))
    summary = {
        'modules': MODULES, 'selected_test_ids': selected,
        'incoming_backend_syntax_check': incoming_syntax_check,
        'test_source_sha256': {str(source / (name + '.py')): sha(source / (name + '.py')) for name in MODULES},
        'tests_run': result.testsRun, 'substantive_success_count': len(result.successes),
        'successful_test_ids': result.successes, 'skipped_cases': skips,
        'unexpected_skipped_cases': unexpected_skips, 'missing_selected_tests': missing,
        'failures': [{'test': test.id(), 'traceback': error} for test, error in result.failures],
        'errors': [{'test': test.id(), 'traceback': error} for test, error in result.errors],
        'expected_failures': [test.id() for test, _ in result.expectedFailures],
        'unexpected_successes': [test.id() for test in result.unexpectedSuccesses],
        'runtime_before': before, 'runtime_after': after, 'runtime_unchanged': before == after,
        'scope': 'Authored offline integrity, packing, qualification, AOT-build and provider-comparison controls. No real model download, inference, training, or publication is performed.',
        'passed': result.wasSuccessful() and not unexpected_skips and not missing
                  and not result.expectedFailures and not result.unexpectedSuccesses
                  and len(result.started) == len(selected) and before == after,
    }
    args.output.write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({key: summary[key] for key in ('tests_run', 'substantive_success_count', 'skipped_cases', 'passed')}))
    raise SystemExit(0 if summary['passed'] else 1)


if __name__ == '__main__':
    main()
