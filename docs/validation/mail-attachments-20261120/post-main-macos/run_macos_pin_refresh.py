#!/usr/bin/env python3
"""Select the complete incoming macOS spaCy pin suite using the frozen inherited runner.

Only the in-memory cohort selection is adapted. The inherited test runner,
source/dependency/runtime fingerprinting, shared Flutter lock, application
timeouts and JSON-event acceptance logic are unchanged.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys


PRIMARY_RELATIVE = Path('docs/validation/zotero-research-materials-20261120/run_validation.py')
PRIMARY_SHA256 = '4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf'
NAMES = ('macos-pin-refresh',)
EXPLICIT_SPECS = {
    'macos-pin-refresh': {
        'package': 'packages/quds_office_editor/example',
        'patterns': [],
        'additional': ['studio_spacy_pin_test.dart'],
        'runner': 'flutter',
    },
}


def record(path: Path) -> dict:
    data = path.read_bytes()
    return {'path': str(path.resolve()), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cohort', choices=NAMES)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--expected-head')
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--list', action='store_true')
    args = parser.parse_args()
    if not args.list and (args.output is None or args.expected_head is None):
        parser.error('--output and --expected-head are required for qualification')
    repo = args.repo.resolve()
    adapter = Path(__file__).resolve()
    runner = repo / PRIMARY_RELATIVE
    before = {'adapter': record(adapter), 'primary_runner': record(runner)}
    if before['primary_runner']['sha256'] != PRIMARY_SHA256:
        raise RuntimeError('Inherited runner bytes differ from the reviewed version')
    spec = importlib.util.spec_from_file_location('frozen_flutter_primary', runner)
    if spec is None or spec.loader is None:
        raise RuntimeError('Cannot load the frozen primary runner')
    primary = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(primary)
    primary.COHORTS = copy.deepcopy(EXPLICIT_SPECS)
    selections = primary.validate_disjoint_selections(repo)
    delegated = [str(runner), args.cohort, '--repo', str(repo),
                 '--timeout', str(args.timeout)]
    if args.output is not None:
        delegated.extend(['--output', str(args.output.resolve())])
    if args.expected_head:
        delegated.extend(['--expected-head', args.expected_head])
    if args.list:
        delegated.append('--list')
    original_argv = sys.argv
    try:
        sys.argv = delegated
        result = primary.main()
    finally:
        sys.argv = original_argv
    if args.list:
        return result
    after = {'adapter': record(adapter), 'primary_runner': record(runner)}
    unchanged = before == after
    provenance = {
        'purpose': 'Final main-refresh macOS spaCy pin Flutter validation with one complete suite',
        'cohort': args.cohort,
        'selection': primary.COHORTS[args.cohort],
        'all_disjoint_selections': selections,
        'adapter_command': original_argv,
        'delegated_arguments': delegated,
        'code_before': before, 'code_after': after, 'code_unchanged': unchanged,
        'primary_runner_exit_code': result,
        'primary_test_audit_and_fingerprint_logic_unchanged': True,
    }
    output = args.output.resolve()
    provenance_path = output / 'selection-adapter.json'
    primary.write_json(provenance_path, provenance)
    receipt_path = output / 'receipt.json'
    receipt = json.loads(receipt_path.read_text())
    receipt['selection_adapter'] = provenance
    receipt['guards']['selection_adapter_and_primary_runner_unchanged'] = unchanged
    receipt['artifacts'][provenance_path.name] = primary.file_record(provenance_path)
    if not unchanged:
        receipt['status'] = 'failed'
    primary.write_json(receipt_path, receipt)
    print(json.dumps({'cohort': args.cohort, 'adapter_unchanged': unchanged,
                      'status': receipt['status']}), flush=True)
    return result if unchanged else 1


if __name__ == '__main__':
    sys.exit(main())
