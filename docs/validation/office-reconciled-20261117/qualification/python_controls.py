#!/usr/bin/env python3
"""Run preserved and newly discovered Python controls with ONNX required."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import prior_python_controls as prior

HERE = Path(__file__).resolve().parent
ORIGINAL_MODULES = list(prior.MODULES)
original_snapshot = prior.snapshot


def snapshot():
    result = original_snapshot()
    assert result['onnx_available'] and result['onnxruntime_available'], 'Real ONNX converter control is required.'
    dependency_inputs = {}
    for name in ('onnx', 'onnxruntime', 'ml_dtypes', 'google.protobuf', 'flatbuffers', 'sympy', 'packaging'):
        spec = importlib.util.find_spec(name)
        assert spec and spec.origin, f'Missing Python dependency {name}'
        root = Path(spec.origin).resolve().parent
        dependency_inputs[name] = {
            'root': str(root),
            'sha256_by_path': {str(path): prior.sha(path) for path in sorted(root.rglob('*'))
                               if path.is_file() and path.suffix in ('.py', '.so', '.json', '.txt')},
        }
    result['onnx_dependency_inputs'] = dependency_inputs
    result['control_runner_sha256'] = prior.sha(Path(__file__).resolve())
    result['inherited_runner_sha256'] = prior.sha(HERE / 'prior_python_controls.py')
    return result


if __name__ == '__main__':
    position = sys.argv.index('--repo')
    source = Path(sys.argv[position + 1]).resolve() / 'tools/proofing/german_model'
    modules = sorted(path.stem for path in source.glob('test_*.py'))
    assert set(ORIGINAL_MODULES) <= set(modules), 'A historical Python test module disappeared.'
    prior.MODULES = modules
    prior.snapshot = snapshot
    prior.main()
