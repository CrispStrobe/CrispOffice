#!/usr/bin/env python3
"""Reparse preserved events after documenting duplicate legacy fixture rows.

This does not execute tests or replace the original runner/run receipts.
"""
import argparse
import gzip
import importlib.util
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    runner_path = Path(__file__).with_name('run_regressions.py')
    spec = importlib.util.spec_from_file_location('regressions', runner_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = {}
    for cohort in ('engine', 'editor'):
        folder = args.evidence / cohort
        original = json.loads((folder / 'summary-at-execution.json').read_text())
        run = json.loads((folder / 'run.json').read_text())
        cwd = Path(run['cwd'])
        workspace = cwd.parents[1]
        detail = module.parse_events(folder / 'events.jsonl.gz', cwd, [workspace / path for path in run['selected_files']])
        old_cases = json.loads(gzip.decompress((folder / 'cases.json.gz').read_bytes()))
        assert detail.pop('cases') == old_cases
        assert detail.pop('excluded_events') == json.loads((folder / 'excluded-events.json').read_text())
        assert detail.pop('machine_envelopes') == json.loads((folder / 'machine-envelopes.json').read_text())
        for key in ('suite_count', 'substantive_test_count', 'results', 'skipped'):
            assert detail[key] == original[key], key
        assert module.record(folder / 'run_regressions_at_execution.py') == original['runner']
        guards = {key: value for key, value in original['guards'].items() if key != 'no_duplicate_case_identities'}
        guards.update(detail.pop('guards'))
        summary = {**original, **detail, 'guards': guards,
                   'status': 'passed' if all(guards.values()) else 'failed',
                   'accounting_correction': {
                       'reason': 'Eight pre-existing duplicate grammar fixture rows have distinct registered test IDs. Preserve all executions and disclose the distinct suite/name count.',
                       'original_receipt': 'summary-at-execution.json',
                       'original_runner': 'run_regressions_at_execution.py',
                       'raw_events': module.record(folder / 'events.jsonl.gz'),
                       'accounting_runner': module.record(runner_path),
                       'correction_script': module.record(Path(__file__)),
                       'product_tests_rerun': False,
                   }}
        module.write_json(folder / 'summary.json', summary)
        result[cohort] = {key: summary[key] for key in ('status', 'substantive_test_count', 'distinct_named_test_count', 'duplicate_registration_count', 'actual_process_exit_code')}
    module.write_json(args.evidence / 'accounting-correction.json', result)
    print(json.dumps(result, indent=2))
    if not all(item['status'] == 'passed' for item in result.values()):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
