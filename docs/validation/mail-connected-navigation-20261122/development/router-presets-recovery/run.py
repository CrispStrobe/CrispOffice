#!/usr/bin/env python3
"""Record the authorized router/presets development check, before final freeze."""

import importlib.util
import os
from pathlib import Path


HERE = Path(__file__).resolve().parent
RUNNER = HERE.parents[1] / 'final' / 'qualify_mail.py'
spec = importlib.util.spec_from_file_location('mail_qualification', RUNNER)
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)

if (HERE / 'summary.json').exists():
    raise SystemExit('Existing evidence must remain unchanged; use a new directory.')

os.environ.update(BOT='true', CI='true', FLUTTER_SUPPRESS_ANALYTICS='true',
                  DART_SUPPRESS_ANALYTICS='true')
source = q.current_head()
runner_before = q.digest(q.stable_bytes(RUNNER))
driver_before = q.digest(q.stable_bytes(Path(__file__)))
before = q.capture_inputs(source)
manifest_before = q.save_manifest(HERE, 'inputs-before.json', before)
q.write_json(HERE / 'runtime.json', q.runtime_info())
files = [
    'test/studio_mail_account_navigation_router_test.dart',
    'test/studio_mail_presets_test.dart',
]
gate = {
    'name': 'router_presets',
    'cwd': str(q.STUDIO),
    'kind': 'tests',
    'expected_suites': [str(q.STUDIO / file) for file in files],
    'command': [str(Path(os.environ['FLUTTER_ROOT']) / 'bin/flutter'), 'test',
                '--no-pub', '--concurrency=2', '--reporter=json', *files],
}
result = q.execute_gate(gate, HERE, os.environ.copy())
after = q.capture_inputs(source)
manifest_after = q.save_manifest(HERE, 'inputs-after.json', after)
drift = q.source_drift(before, after)
report = result['reporter']
summary = {
    'scope': 'Focused development verification before final corrected-source freeze; not final qualification.',
    'head_at_start': source,
    'head_at_finish': q.current_head(),
    'source_input_count': len(before['entries']),
    'initial_inputs_differing_from_head': [path for path, row in before['entries'].items()
                                          if not row['matches_expected_head']],
    'source_drift': drift,
    'runner_sha256_before': runner_before,
    'runner_sha256_after': q.digest(q.stable_bytes(RUNNER)),
    'driver_sha256_before': driver_before,
    'driver_sha256_after': q.digest(q.stable_bytes(Path(__file__))),
    'manifests': {'before': manifest_before, 'after': manifest_after},
    'result': 'router_presets-result.json',
    'unique_started_cases': report['unique_started_cases'],
    'unique_completed_cases': report['unique_completed_cases'],
    'passed_cases': report['passed_cases'],
    'failed_cases': report['failed_cases'],
    'skipped_cases': report['skipped_cases'],
    'incomplete_cases': report['incomplete_cases'],
    'per_file_counts': report['per_file_counts'],
    'accepted_development_check': result['exit_code'] == 0 and report['reporter_success']
        and not report['failed_cases'] and not report['incomplete_cases']
        and not report['missing_suites'] and not report['unexpected_suites']
        and drift['stable'] and runner_before == q.digest(q.stable_bytes(RUNNER))
        and driver_before == q.digest(q.stable_bytes(Path(__file__))),
}
q.write_json(HERE / 'summary.json', summary)
(HERE / 'SHA256SUMS.txt').write_text(''.join(
    f'{q.digest(q.stable_bytes(path))}  {path.name}\n'
    for path in sorted(HERE.iterdir()) if path.is_file() and path.name != 'SHA256SUMS.txt'
))
print(q.json_bytes(summary).decode(), flush=True)
raise SystemExit(0 if summary['accepted_development_check'] else 1)
