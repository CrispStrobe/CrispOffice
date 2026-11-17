#!/usr/bin/env python3
"""Run a fixed serial 1/2/4/8-thread sweep after compilation and tests finish.

Every arm uses one source-bound AOT, segmentation target 64, and reuse off.
All outputs are fresh; failed runs remain available. This script neither builds
the executable nor dispatches CI. It must be invoked only when other shared-host
tests/compiles/model jobs have completed.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

THREADS = (1, 2, 4, 8)
COHORTS = {
    'cases': 30,
    'controls': 8,
    'long_complete_check_probes': 3,
    'segmented_long_complete_check_probes': 2,
    'varied_segmented_long_complete_check_probes': 2,
    'segmentation_controls': 6,
}
TIMING_FIELDS = {'elapsed_ms', 'timing', 'inference_microseconds'}
REFERENCE_SHA256 = '9d33a0be66e68284277bd3d9e0e0fe404936cf804e2e715a8999b7ece14155d8'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def utc():
    return datetime.now(timezone.utc).isoformat()


def semantics(value):
    if isinstance(value, dict):
        return {key: semantics(item) for key, item in value.items() if key not in TIMING_FIELDS}
    if isinstance(value, list):
        return [semantics(item) for item in value]
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-root', 'dart', 'aot', 'build-receipt', 'pack', 'reference', 'output-dir'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    root = args.source_root.resolve(strict=True)
    dart = args.dart.resolve(strict=True)
    aot = args.aot.resolve(strict=True)
    build_path = args.build_receipt.resolve(strict=True)
    pack = args.pack.resolve(strict=True)
    reference = args.reference.resolve(strict=True)
    output = args.output_dir.resolve()
    if output.exists():
        raise ValueError('Use a fresh output directory; existing evidence is never overwritten.')
    if output.is_relative_to(root) or output.is_relative_to(dart.parent.parent):
        raise ValueError('Keep measurement outputs outside source and SDK.')
    output.mkdir(parents=True)
    receipt_path = output / 'serial-receipt.json'
    receipt = {
        'schema_version': 1, 'kind': 'quds-gector-native-thread-sweep',
        'started_utc': utc(), 'completed': False, 'passed': False,
        'thread_order': list(THREADS), 'segment_target_tokens': 64,
        'inference_reuse_enabled': False, 'measurements_are_serial': True,
        'scope': 'Local-host exploratory CPU-thread sweep. Same complete-check runner and frozen short controls in every arm. Not intended-device qualification.',
        'independent_output_comparison_scope': 'Every retained first result, warmup, finding, source partition, decoder pass/input identity and diagnostic counter. Per-input stability across all timed outputs is a producer claim; per-sample decoder records and timings are retained.',
        'github_actions_dispatched_polled_or_awaited': False,
        'runs': [],
    }

    def save():
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    try:
        builder = load_module(root / 'tools/proofing/german_model/build_gector_aot.py', 'gector_build')
        comparator = load_module(root / 'tools/proofing/german_model/compare_guarded_provider.py', 'gector_compare')
        build = json.loads(build_path.read_text())
        assert all(build[key] is True for key in ('completed', 'passed', 'source_stable', 'dependencies_stable', 'sdk_stable'))
        assert build.get('target', 'provider') == 'provider'
        runtime = dart.parent / 'dartaotruntime'
        assert builder.file_pin(aot) == build['runtime']['entrypoint']
        assert builder.file_pin(runtime) == build['runtime']['executable']
        assert builder.source_snapshot(root) == build['source_files']
        assert builder.dependency_snapshot(root) == build['dependency_inputs']
        assert {name: builder.file_pin(path) for name, path in builder.sdk_files(dart).items()} == build['sdk_inputs']
        assert sha(reference) == REFERENCE_SHA256
        manifest = json.loads((pack / 'pack.json').read_text())
        for entry in manifest['files']:
            path = pack / entry['path']
            assert path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256'], entry['path']
        model_dir = pack / manifest['model']['directory']
        model = model_dir / manifest['model']['file']
        library = pack / manifest['native']['path']
        receipt.update(build_receipt_sha256=sha(build_path), aot=builder.file_pin(aot), runtime=builder.file_pin(runtime), source_files=build['source_files'], dependency_inputs=build['dependency_inputs'], sdk_inputs=build['sdk_inputs'], reference_sha256=sha(reference), pack_manifest_sha256=sha(pack / 'pack.json'), model_sha256=manifest['model']['sha256'], native_library_sha256=manifest['native']['sha256'])
        env = os.environ.copy()
        env.update(CRISPEMBED_GECTOR='1', PYTHONDONTWRITEBYTECODE='1')
        reports = {}
        for threads in THREADS:
            assert builder.source_snapshot(root) == build['source_files'], 'Source changed before arm'
            name = f'threads-{threads}'
            report_path = output / (name + '.json')
            log_path = output / (name + '.log')
            command = [str(runtime), str(aot), '--source-root', str(root), '--bundle-dir', str(model_dir), '--model', str(model), '--model-sha256', manifest['model']['sha256'], '--library', str(library), '--library-sha256', manifest['native']['sha256'], '--reference', str(reference), '--segment-target-tokens', '64', '--native-threads', str(threads), '--output', str(report_path)]
            row = {'native_threads': threads, 'report': report_path.name, 'log': log_path.name, 'started_utc': utc(), 'started_monotonic': time.monotonic(), 'load_average_before': list(os.getloadavg()), 'status': 'running'}
            row['command'] = ['<dartaotruntime>', '<same-provider-aot>', '--source-root', '<source-root>', '--bundle-dir', '<verified-model-directory>', '--model', '<verified-model>', '--model-sha256', manifest['model']['sha256'], '--library', '<verified-native-library>', '--library-sha256', manifest['native']['sha256'], '--reference', '<pinned-reference-f32>', '--segment-target-tokens', '64', '--native-threads', str(threads), '--output', report_path.name]
            receipt['runs'].append(row)
            save()
            print('START', name, flush=True)
            with log_path.open('x') as log:
                result = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=900)
            row.update(exit_code=result.returncode, finished_utc=utc(), finished_monotonic=time.monotonic(), log_sha256=sha(log_path), status='completed' if result.returncode == 0 else 'failed')
            if report_path.exists():
                row['report_sha256'] = sha(report_path)
            save()
            if result.returncode != 0:
                row['validation_error'] = f'Provider exited with {result.returncode}; partial receipt retained.'
                save()
                print('FAILED', name, row['validation_error'], flush=True)
                continue
            report = json.loads(report_path.read_text())
            reports[threads] = report
            assert all(report[key] is True for key in ('completed', 'source_stable', 'all_requested_checks_passed', 'operational_passed', 'segmentation_operational_passed', 'varied_segmentation_operational_passed'))
            assert report['source_files'] == build['source_files']
            assert report['runtime']['entrypoint'] == build['runtime']['entrypoint']
            assert report['runtime']['executable'] == build['runtime']['executable']
            assert report['runtime']['product_mode'] is True
            assert report['runtime']['native_threads'] == threads
            assert report['runtime']['warmups_per_input'] == 1 and report['runtime']['repeats_per_input'] == 3
            assert report['reference_sha256'] == REFERENCE_SHA256
            for cohort, count in COHORTS.items():
                assert len(report[cohort]) == count, cohort
                assert len({r['id'] for r in report[cohort]}) == count, cohort
                for item in report[cohort]:
                    if 'timing' in item:
                        comparator.validate_timing(item['timing'], f'{name}.{cohort}.{item["id"]}', 3)
            row['summary'] = {'setup_ms': report['setup_ms'], 'peak_rss_mib': report['peak_process_rss_bytes'] / 1024 / 1024, 'short_timing': report['warm_checks_up_to_64_wordpieces'], 'engineering_budgets': report['engineering_budgets'], 'exact_de_DE_error_fixes': sum(r['language'] == 'de-DE' and r['kind'] == 'error' and r['matches_expected'] for r in report['cases']), 'clean_de_DE_unchanged': sum(r['language'] == 'de-DE' and r['kind'] == 'clean' and r['corrected'] == r['input'] and not r['findings'] for r in report['cases']), 'probes': {cohort: [{'id':r['id'], 'tokens':r['tokens_first_pass'], 'segments':r['initial_segment_count'], 'timing':r['timing'], 'decoder_samples':r['decoder_samples']} for r in report[cohort]] for cohort in ('long_complete_check_probes','segmented_long_complete_check_probes','varied_segmented_long_complete_check_probes')}}
            save()
            print('DONE', name, json.dumps({'short_p95_ms': row['summary']['short_timing']['p95_ms'], 'rss_mib': row['summary']['peak_rss_mib']}), flush=True)
        # Keep the historical two-thread comparator unchanged and retain its
        # authenticated evidence; never rewrite another arm's thread metadata.
        comparison = None
        if 2 in reports:
            comparison = comparator.compare(comparator.DEFAULT_BASELINE.read_bytes(), (output / 'threads-2.json').read_bytes(), (root / 'tools/proofing/german_model/cases.json').read_bytes())
            (output / 'threads-2-frozen-comparison.json').write_text(json.dumps(comparison, indent=2) + '\n')
        anchor = reports.get(2)
        comparisons = {}
        for threads, report in reports.items():
            if anchor is None:
                comparisons[str(threads)] = {'comparable':False, 'reason':'Two-thread control did not complete successfully.'}
                continue
            identities = all(report[key] == anchor[key] for key in ('model', 'native_library_sha256', 'reference_sha256', 'cases_sha256', 'bundle_assets', 'source_files', 'decode_configuration'))
            cohort_matches = {cohort: semantics(report[cohort]) == semantics(anchor[cohort]) for cohort in COHORTS}
            runtime_matches = {k:v for k,v in report['runtime'].items() if k != 'native_threads'} == {k:v for k,v in anchor['runtime'].items() if k != 'native_threads'}
            comparisons[str(threads)] = {'comparable':True, 'passed':identities and runtime_matches and all(cohort_matches.values()), 'identities_match_threads_2': identities, 'runtime_matches_threads_2_except_thread_count':runtime_matches, 'cohorts_match_threads_2_except_timing':cohort_matches}
        receipt['cross_arm_comparison'] = comparisons
        assert all(a['finished_monotonic'] <= b['started_monotonic'] for a,b in zip(receipt['runs'], receipt['runs'][1:]))
        assert builder.source_snapshot(root) == build['source_files']
        assert builder.dependency_snapshot(root) == build['dependency_inputs']
        assert {name: builder.file_pin(path) for name,path in builder.sdk_files(dart).items()} == build['sdk_inputs']
        assert sha(aot) == receipt['aot']['sha256']
        passed = len(reports) == len(THREADS) and comparison is not None and comparison['passed'] is True and all(row.get('passed') is True for row in comparisons.values())
        receipt.update(completed=True, passed=passed, finished_utc=utc(), source_dependencies_sdk_stable=True, all_runs_nonoverlapping=True, frozen_two_thread_comparison_passed=comparison is not None and comparison['passed'] is True)
        save()
        return 0 if passed else 1
    except Exception as error:
        receipt.update(error_type=type(error).__name__, error=str(error), finished_utc=utc())
        save()
        raise


if __name__ == '__main__':
    sys.exit(main())
