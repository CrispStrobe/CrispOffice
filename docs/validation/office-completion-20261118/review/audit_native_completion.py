#!/usr/bin/env python3
"""Independently read back the frozen Office native sweep; never run inference.

Full mode requires both closed guarded gates and their complete indexed archives.
Partial mode audits completed arms only and never grants final acceptance.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import statistics
import subprocess
import tarfile

THREADS = [1, 2, 4, 8]
COHORTS = {
    'cases': 30, 'controls': 8, 'long_complete_check_probes': 3,
    'segmented_long_complete_check_probes': 2,
    'varied_segmented_long_complete_check_probes': 2,
    'segmentation_controls': 6,
}
EXCLUDED_TIMES = {'elapsed_ms', 'timing', 'inference_microseconds'}
REFERENCE = '9d33a0be66e68284277bd3d9e0e0fe404936cf804e2e715a8999b7ece14155d8'
MODEL = '549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b'
LIBRARY = '9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604'
PACK = '70187da9248c829ab511f566ba4db9093a0ec5a9c922ad4438d63db372880841'
CASES = 'ec3309ebf99a3b1be9bb065fc91cd2afce2e362ebaa81f2d64d39a231c6defb9'
checks = 0


def require(condition, label):
    global checks
    checks += 1
    if not condition:
        raise ValueError(label)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def decode(data):
    return json.loads(data, object_pairs_hook=object_pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite JSON: ' + value)))


def load(path):
    return decode(Path(path).read_bytes())


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def semantic(value):
    if isinstance(value, dict):
        return {k: semantic(v) for k, v in value.items() if k not in EXCLUDED_TIMES}
    if isinstance(value, list):
        return [semantic(v) for v in value]
    return value


def timing(value, count, label):
    samples = value['samples_ms']
    require(len(samples) == count and count > 0, label + ': sample count')
    require(all(type(v) in (int, float) and math.isfinite(v) and v >= 0 for v in samples), label + ': finite samples')
    ordered = sorted(samples)
    for key, expected in [('median_ms', statistics.median(samples)),
                          ('p95_ms', ordered[math.ceil(count * .95) - 1]),
                          ('maximum_ms', ordered[-1])]:
        require(math.isclose(value[key], expected, rel_tol=1e-12, abs_tol=1e-9), label + ': ' + key)
    return samples


def actual_work(record, row, label):
    require(type(record) is dict and record['complete'] is True and record['stop_reason'] == 'stable', label + ': actual decoder completion')
    passes = record['passes']
    require(type(passes) is list, label + ': actual passes')
    for item in passes:
        require(type(item['tokens']) is int and 2 <= item['tokens'] <= 512, label + ': sequence bounds')
        require(type(item['source_start']) is int and item['source_start'] >= 0, label + ': actual source coordinate')
        require(item['reused_inference'] is False, label + ': no inference reuse')
        fingerprint = item['prediction_input_sha256']
        require(isinstance(fingerprint, str) and len(fingerprint) == 64 and all(c in '0123456789abcdef' for c in fingerprint), label + ': prepared-input hash')
    for key, expected in [('pass_count', len(passes)), ('forward_count', len(passes)),
                          ('forward_tokens', sum(p['tokens'] for p in passes)),
                          ('decoded_tokens', sum(p['tokens'] for p in passes)), ('reused_pass_count', 0)]:
        require(type(record[key]) is int and record[key] == expected, label + ': reconstruct ' + key)
    planned = row.get('initial_segments')
    if planned is None:
        return False
    boundaries, extent = {0}, 0
    for character in row['input']:
        extent += len(character.encode('utf-16-le')) // 2
        boundaries.add(extent)
    require(row['source_code_units'] == extent and row['source_coverage_complete'] is True, label + ': original source extent')
    require(len(planned) > 0 and record['segment_count'] == row['initial_segment_count'] == len(planned), label + ': actual and planned segment counts')
    require(row['initial_model_tokens_total'] == sum(s['tokens'] for s in planned), label + ': initial token total')
    cursor = 0
    for segment in planned:
        start, end, tokens = (segment[k] for k in ('start', 'end', 'tokens'))
        require(type(start) is int and type(end) is int and start == cursor and start in boundaries and end in boundaries and end >= start, label + ': contiguous UTF-16 partition')
        require(type(tokens) is int and 2 < tokens <= 512, label + ': planned modeled sequence')
        cursor = end
    require(cursor == extent, label + ': source tail coverage')
    by_start = {s['start']: s for s in planned}
    first, previous = {}, -1
    for item in passes:
        start = item['source_start']
        require(start in by_start and start >= previous, label + ': ordered actual source segments')
        first.setdefault(start, item)
        previous = start
    require(set(first) == set(by_start), label + ': every planned segment has actual forward work')
    require(all(first[start]['tokens'] == planned_row['tokens'] for start, planned_row in by_start.items()), label + ': actual first-pass tokens')
    require(len({item['prediction_input_sha256'] for item in first.values()}) == row['initial_distinct_model_inputs'], label + ': actual initial diversity')
    return True


def audit_arm(report, threads, build, comparator, corpus):
    label = 'threads-' + str(threads)
    require(report['kind'] == 'quds-gector-native-dart-complete-check' and report['schema_version'] == 1, label + ': schema')
    for key in ('completed', 'source_stable', 'all_requested_checks_passed', 'operational_passed', 'segmentation_operational_passed', 'varied_segmentation_operational_passed'):
        require(report[key] is True, label + ': ' + key)
    require(report['source_files'] == build['source_files'], label + ': AOT source identity')
    require(report['runtime']['native_threads'] == threads and report['runtime']['product_mode'] is True, label + ': thread count and product mode')
    require(report['runtime']['warmups_per_input'] == 1 and report['runtime']['repeats_per_input'] == 3, label + ': warmups/repeats')
    require(all(report['runtime'][k] == build['runtime'][k] for k in ('entrypoint', 'executable')), label + ': AOT/runtime hash')
    require(report['model']['sha256'] == MODEL and report['native_library_sha256'] == LIBRARY and report['reference_sha256'] == REFERENCE and report['cases_sha256'] == CASES, label + ': immutable pins')
    config = report['decode_configuration']
    require(config['mode'] == 'sentence-segments' and config['segmentation']['target_tokens'] == 64 and config['segmentation']['inference_reuse'] is None, label + ': fixed segmentation/reuse')
    cases_by_id = {x['id']: x for x in corpus}
    require({x['id'] for x in report['cases']} == set(cases_by_id), label + ': original corpus IDs')
    require({x['id'] for x in report['controls']} == set(comparator.CONTROL_IDS), label + ': original control IDs')
    require({x['id'] for x in report['long_complete_check_probes']} == {f'repeated-sentences-up-to-{x}' for x in (64, 128, 256)}, label + ': original length probe IDs')
    require({x['id'] for x in report['segmented_long_complete_check_probes']} == {f'segmented-repeated-sentences-up-to-{x}' for x in (640, 1280)}, label + ': segmented probe IDs')
    require({x['id'] for x in report['varied_segmented_long_complete_check_probes']} == {f'varied-sentences-up-to-{x}' for x in (640, 1280)}, label + ': varied probe IDs')
    require({x['id'] for x in report['segmentation_controls']} == {
        'segmented-late-correction-utf16-offset', 'segmented-protected-code',
        'segmented-late-capacity-fails-whole-request', 'segmented-total-token-cap-fails-whole-request',
        'segmented-segment-cap-fails-whole-request', 'segmented-text-cap-fails-whole-request'}, label + ': segmented control IDs')
    covered = no_plan = output_records = work_records = 0
    short_samples = []
    for cohort, expected in COHORTS.items():
        rows = report[cohort]
        require(len(rows) == len({r['id'] for r in rows}) == expected, label + ': ' + cohort + ' coverage')
        for row in rows:
            where = label + '.' + cohort + '.' + row['id']
            comparator.validate_result(row, where, expected_id=row['id'], source=row['input'], language=row['language'], start_offset=137 if cohort == 'segmentation_controls' else 7)
            output_records += 1
            if cohort == 'cases':
                frozen = cases_by_id[row['id']]
                require(row['input'] == frozen['input'] and row['language'] == frozen.get('locale', 'de-DE'), where + ': frozen input and locale')
                require(row['kind'] == frozen['kind'] and row['expected'] == frozen.get('expected', frozen['input']), where + ': frozen kind and expected output')
                require(row['matches_expected'] is (row['corrected'] == row['expected']), where + ': expected-output flag')
            if 'timing' in row:
                samples = timing(row['timing'], 3, where)
                require(row['elapsed_ms'] == samples[0] and row['stable_repeats'] is True, where + ': first elapsed and stability claim')
                warmup = row['warmup']
                comparator.validate_result(warmup, where + '.warmup', expected_id=row['id'] + '-warmup', source=row['input'], language=row['language'])
                output_records += 1
                require(all(warmup[k] == row[k] for k in ('status', 'corrected', 'findings')), where + ': retained warmup output')
                require(len(row['decoder_samples']) == len(row['decoder_observation_samples']) == 3 and row['decoder'] == row['decoder_samples'][0], where + ': retained sample diagnostics')
                require(row['decoder_observation'] == row['decoder_observation_samples'][0], where + ': first worker observation')
                if cohort == 'cases' and row['status'] == 'success' and row['tokens_first_pass'] <= 64 or cohort == 'long_complete_check_probes' and row['token_budget'] == 64:
                    short_samples.extend(samples)
            if row['status'] == 'success':
                observations = [row['warmup']['decoder_observation'], *row['decoder_observation_samples']] if 'timing' in row else [row['decoder_observation']]
                require(all(o['worker_requested'] is True and o['worker_result_received'] is True and o['diagnostics_available'] is True and o['worker_error'] is None for o in observations), where + ': real worker observations')
                records = [row['warmup']['decoder'], *row['decoder_samples']] if 'timing' in row else [row['decoder']]
                for i, record in enumerate(records):
                    if actual_work(record, row, where + '.sample-' + str(i)):
                        covered += 1
                    else:
                        no_plan += 1
                    work_records += 1
            else:
                require(row['decoder'] is None, where + ': no invented work on rejected/unsupported request')
            if cohort in ('controls', 'segmentation_controls'):
                require(row['passed'] is True, where + ': control passed')
            if cohort == 'segmentation_controls':
                require(row['status'] == row['expected_status'] and row['corrected'] == row['expected'], where + ': expected control behavior')
                require(row['findings'] == row.get('expected_findings', row['findings']), where + ': expected findings')
                if row['status'] != 'success':
                    require(row['planning_admitted'] is False and row['planning_rejection'] in row['message'] and not row['findings'], where + ': whole-request rejection')
            if cohort == 'segmented_long_complete_check_probes':
                require(row['status'] == 'success' and row['corrected'] == row['input'] and row['matches_expected'] is True and row['exceeds_single_sequence_capacity'] is True and row['initial_segment_count'] > 1, where + ': structural segmentation control')
            if cohort == 'varied_segmented_long_complete_check_probes':
                require(row['status'] == 'success' and row['exceeds_single_sequence_capacity'] is True and row['initial_inputs_all_distinct'] is True and row['initial_distinct_model_inputs'] == row['initial_segment_count'], where + ': distinct varied inputs')
    require(len(short_samples) == 87, label + ': 87 unchanged short samples')
    require(timing(report['warm_checks_up_to_64_wordpieces'], len(short_samples), label + '.aggregate') == short_samples, label + ': exact aggregate samples')
    budgets = {
        'p95_at_most_500_ms': report['warm_checks_up_to_64_wordpieces']['p95_ms'] <= 500,
        'peak_rss_at_most_768_mib': report['peak_process_rss_bytes'] <= 768 * 1024 * 1024,
        'gguf_at_most_160_mib': report['model']['bytes'] <= 160 * 1024 * 1024,
    }
    require(all(report['engineering_budgets'][k] is v for k, v in budgets.items()), label + ': reconstruct separate engineering flags')
    require(covered == 142 and no_plan == 5, label + ': 142 complete-source records and five additional controls')
    errors = [x for x in report['cases'] if x['kind'] == 'error' and x['language'] == 'de-DE']
    clean = [x for x in report['cases'] if x['kind'] == 'clean' and x['language'] == 'de-DE']
    return {'thread_count': threads, 'cohort_counts': {k: len(report[k]) for k in COHORTS},
            'statuses': {k: dict(Counter(x['status'] for x in report[k])) for k in COHORTS},
            'short_samples': len(short_samples), 'retained_output_records_validated': output_records,
            'actual_decoder_records_reconstructed': work_records,
            'complete_source_decoder_records': covered, 'additional_control_decoder_records': no_plan,
            'supported_error_cases': len(errors), 'exact_error_fixes': sum(x['corrected'] == x['expected'] for x in errors),
            'supported_clean_controls': len(clean), 'clean_controls_unchanged': sum(x['corrected'] == x['input'] and not x['findings'] for x in clean),
            'short_timing': report['warm_checks_up_to_64_wordpieces'],
            'peak_rss_bytes': report['peak_process_rss_bytes'], 'setup_ms': report['setup_ms'],
            'engineering_budgets': budgets, 'semantics_accepted_independently_of_budget_flags': True}


def archive_check(run, native):
    archive = run.with_suffix('.tar.xz')
    index_path = archive.with_suffix('.index.json')
    index = load(index_path)
    require(sha(archive) == index['sha256'] and archive.stat().st_size == index['bytes'], 'Archive identity: ' + archive.name)
    indexed = {x['path']: x for x in index['members']}
    require(len(indexed) == len(index['members']) == index['member_count'], 'Unique indexed members')
    expected_live_members = {str(p.relative_to(run)) for p in run.rglob('*')
                             if p.is_file() and not p.is_symlink() and p.name != 'provider.aot'
                             and '__pycache__' not in p.parts}
    expected_live_members.update(('run_guarded_native.py', 'native_prepare_child.py'))
    require(set(indexed) == expected_live_members, 'Complete current gate archive coverage')
    required = {'orchestration.json', 'guard/receipt.json', 'guard/inputs-before.json.gz',
                'guard/inputs-after.json.gz', 'guard/child.stdout.log', 'guard/child.stderr.log',
                'guard.stdout.log', 'guard.stderr.log', 'run_guarded_native.py', 'native_prepare_child.py'}
    if run.name.startswith('native-prepare-'):
        required.update(('result/provider-build.json', 'result/audit-controls.json', 'result/commands.json'))
    else:
        required.update(('result/serial-receipt.json', 'result/threads-2-frozen-comparison.json'))
        required.update(f'result/threads-{thread}.{extension}' for thread in THREADS for extension in ('json', 'log'))
    require(required <= set(indexed), 'Required native gate receipts and raw reports archived')
    seen = set()
    with tarfile.open(archive) as tar:
        for member in tar:
            name = PurePosixPath(member.name)
            require(member.isfile() and not name.is_absolute() and '..' not in name.parts and member.name not in seen, 'Safe unique archive member')
            data = tar.extractfile(member).read()
            expected = indexed[member.name]
            require(len(data) == expected['bytes'] and digest(data) == expected['sha256'], 'Indexed member: ' + member.name)
            live = native / member.name if member.name in ('run_guarded_native.py', 'native_prepare_child.py') else run / member.name
            require(live.is_file() and live.read_bytes() == data, 'Archived/live bytes: ' + member.name)
            seen.add(member.name)
    require(seen == set(indexed), 'Complete archive member set')
    return {'path': str(archive), 'bytes': index['bytes'], 'sha256': index['sha256'], 'member_count': len(seen), 'all_members_read_back_and_match_live': True, 'index_sha256': sha(index_path)}


def guard_check(run, source, commit, rehash_runtime):
    receipt = load(run / 'guard/receipt.json')
    outer = load(run / 'orchestration.json')
    require(receipt['passed'] is True and receipt['child_exit_code'] == 0 and outer['passed'] is True and outer['exit_code'] == 0 and not outer.get('timeout'), 'Guard and orchestration complete exits')
    require(receipt['source_commit'] == outer['source_commit'] == commit, 'Guard source commit')
    for key in ('source_checkout_clean_before', 'source_checkout_clean_after', 'source_bytes_match_frozen_commit_before_and_after', 'runtime_and_workspace_unchanged'):
        require(receipt[key] is True, 'Guard status ' + key)
    before = decode(gzip.decompress((run / 'guard/inputs-before.json.gz').read_bytes()))
    after = decode(gzip.decompress((run / 'guard/inputs-after.json.gz').read_bytes()))
    require(before == after, 'Raw before/after maps byte identities')
    require(len(before['source']) == receipt['source_file_count'] and len(before['runtime']) == receipt['runtime_and_workspace_file_count'], 'Guard map counts')
    tree = {}
    for entry in subprocess.check_output(['git', '-C', str(source), 'ls-tree', '-rz', commit]).split(b'\0'):
        if not entry:
            continue
        meta, path = entry.split(b'\t', 1)
        mode, kind, blob = meta.decode().split()
        if kind == 'blob':
            tree[path.decode()] = (mode, blob)
    for name, row in before['source'].items():
        path = source / name
        data = os.readlink(path).encode() if row['mode'] == '120000' else path.read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        require(tree[name] == (row['mode'], row['git_blob']) and blob == row['git_blob'] and digest(data) == row['sha256'] and len(data) == row['bytes'], 'Guard source/Git blob ' + name)
    if rehash_runtime:
        for path, expected in before['runtime'].items():
            require(sha(path) == expected, 'Live guarded runtime ' + path)
    for name, expected in receipt['output_hashes'].items():
        require(sha(run / 'guard' / name) == expected, 'Guard output hash ' + name)
    return {'passed': True, 'source_commit': commit, 'source_files': len(before['source']),
            'runtime_files': len(before['runtime']), 'runtime_rehashed_live': rehash_runtime,
            'source_and_runtime_maps_identical': True, 'outer_exit_code': outer['exit_code'],
            'child_exit_code': receipt['child_exit_code'], 'duration_seconds': receipt['duration_seconds']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('task-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--commit', default='9d060658ee6be8ec97d73f56b9aec10d346b7952')
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    require(not args.output.exists(), 'Review output must be fresh')
    root = args.task_root.resolve(); source = root / 'qualification-source'; work = root / 'flutter-qualification/workspace'
    native = root / 'native-consumers'; prep = native / ('native-prepare-' + args.commit[:8]); run = native / ('native-sweep-' + args.commit[:8])
    dart = root / 'toolchains/flutter/bin/cache/dart-sdk/bin/dart'
    output = {'schema_version': 1, 'kind': 'independent-native-sweep-completion-review',
              'observed_utc': datetime.now(timezone.utc).isoformat(), 'source_commit': args.commit,
              'partial': args.partial, 'accepted': False, 'findings': [], 'native_inference_or_compilation_executed': False,
              'github_actions_workflow_check_status_calls': 0,
              'limits': [
                  'All timed outputs are not retained: per-input output stability across all timed repetitions remains a producer claim. First results, warmups and all timed decoder observations/pass records are audited.',
                  'The frozen 30-case synthetic panel and structural probes do not establish broad German precision/recall, intended-device performance, model deployment or release qualification.',
                  'Engineering latency/RSS/model-size flags are reconstructed and reported separately from semantic acceptance.',
                  'Generated provider.aot is omitted from archives; this audit rehashes the live executable against the retained source/dependency/SDK-bound build receipt.',
                  'Nonoverlap proves ordering of retained arm intervals and preparation; unobserved third-party host workloads are outside this receipt.'
              ]}
    try:
        before_head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
        before_status = subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True)
        require(before_head == args.commit and not before_status, 'Clean frozen execution checkout')
        builder = module(source / 'tools/proofing/german_model/build_gector_aot.py', 'review_builder')
        comparator = module(source / 'tools/proofing/german_model/compare_guarded_provider.py', 'review_comparator')
        harness = module(source / 'docs/validation/german-gector/2026-11-17-followup/native-threads/run_native_thread_sweep.py', 'review_harness')
        require(harness.THREADS == tuple(THREADS) and harness.COHORTS == COHORTS and harness.TIMING_FIELDS == EXCLUDED_TIMES, 'Unchanged sweep criteria')
        output['harness_sha256'] = sha(Path(harness.__file__)); output['comparator_sha256'] = sha(Path(comparator.__file__))
        build = load(prep / 'result/provider-build.json'); serial = load(run / 'result/serial-receipt.json')
        for key in ('completed', 'passed', 'source_stable', 'dependencies_stable', 'sdk_stable'):
            require(build[key] is True, 'AOT build ' + key)
        require(build['compile']['returncode'] == 0, 'AOT compile exit')
        for before, after in [('source_files', 'source_files_after'), ('dependency_inputs', 'dependency_inputs_after'), ('sdk_inputs', 'sdk_inputs_after')]:
            require(build[before] == build[after], 'AOT raw before/after ' + before)
        if not args.partial:
            require(builder.source_snapshot(work) == build['source_files'], 'Live source snapshot')
            require(builder.dependency_snapshot(work) == build['dependency_inputs'], 'Live dependency snapshot')
            require({name: builder.file_pin(path) for name, path in builder.sdk_files(dart).items()} == build['sdk_inputs'], 'Live SDK inputs')
            require(builder.file_pin(prep / 'result/provider.aot') == build['runtime']['entrypoint'], 'Live AOT binary')
            require(builder.file_pin(dart.parent / 'dartaotruntime') == build['runtime']['executable'], 'Live AOT runtime')
        require(sha(prep / 'result/provider-build.json') == serial['build_receipt_sha256'], 'Serial/build receipt identity')
        require(serial['source_files'] == build['source_files'] and serial['dependency_inputs'] == build['dependency_inputs'] and serial['sdk_inputs'] == build['sdk_inputs'], 'Serial input maps')
        require(serial['aot'] == build['runtime']['entrypoint'] and serial['runtime'] == build['runtime']['executable'], 'Serial AOT/runtime pins')
        require(serial['reference_sha256'] == REFERENCE and serial['pack_manifest_sha256'] == PACK and serial['model_sha256'] == MODEL and serial['native_library_sha256'] == LIBRARY, 'Serial immutable pins')
        pack = native / 'native-qualification-runtime/native-development-pack'; manifest = load(pack / 'pack.json')
        require(sha(pack / 'pack.json') == PACK and sha(native / 'native-qualification-runtime/reference-f32.json') == REFERENCE, 'Live pack/reference')
        if not args.partial:
            for item in manifest['files']:
                path = pack / item['path']
                require(path.stat().st_size == item['bytes'] and sha(path) == item['sha256'], 'Live pack member ' + item['path'])
        require(serial['thread_order'] == THREADS and serial['segment_target_tokens'] == 64 and serial['inference_reuse_enabled'] is False, 'Serial protocol')
        require(serial['github_actions_dispatched_polled_or_awaited'] is False, 'No CI claim')
        corpus = load(source / 'tools/proofing/german_model/cases.json')
        require(sha(source / 'tools/proofing/german_model/cases.json') == CASES, 'Frozen corpus bytes')
        reports, summaries = {}, []
        for row in serial['runs']:
            if args.partial and row['status'] == 'running':
                continue
            threads = row['native_threads']; require(threads in THREADS and threads not in reports, 'Unique thread arm')
            require(row['status'] == 'completed' and row['exit_code'] == 0, 'Native arm exited zero')
            require(row['finished_monotonic'] >= row['started_monotonic'], 'Arm monotonic interval')
            report_path = run / 'result' / row['report']; log_path = run / 'result' / row['log']
            require(sha(report_path) == row['report_sha256'] and sha(log_path) == row['log_sha256'], 'Native raw report/log hashes')
            report = load(report_path); reports[threads] = report
            summary = audit_arm(report, threads, build, comparator, corpus)
            require(harness.audit_arm_evidence(report, comparator) == row['independent_evidence_audit'], 'Producer reconstruction independently reproduced')
            summary.update(report_sha256=sha(report_path), log_sha256=sha(log_path), elapsed_seconds=row['finished_monotonic'] - row['started_monotonic'])
            summaries.append(summary)
        require([r['native_threads'] for r in serial['runs']] == THREADS[:len(serial['runs'])], 'Arm launch ordering')
        for first, second in zip(serial['runs'], serial['runs'][1:]):
            require(first['finished_monotonic'] <= second['started_monotonic'], 'Native arms do not overlap')
        output['arms'] = summaries
        output['build'] = {'source_files': len(build['source_files']), 'dependencies': len(build['dependency_inputs']['packages']), 'sdk_inputs': len(build['sdk_inputs']), 'all_rehashed_live': not args.partial, 'aot': build['runtime']['entrypoint']}
        if args.partial:
            output['deferred_until_closed_sweep'] = 'Full live source/dependency/SDK/AOT/pack/guard runtime rehashes and archive completeness; partial review reads closed reports while avoiding large competing disk scans.'
        if 2 in reports:
            historical = comparator.compare(comparator.DEFAULT_BASELINE.read_bytes(), (run / 'result/threads-2.json').read_bytes(), (source / 'tools/proofing/german_model/cases.json').read_bytes())
            require(historical['passed'] is True, 'Unchanged historical true two-thread comparator')
            output['historical_two_thread_comparison'] = historical
            comparisons = {}
            anchor = reports[2]
            for threads, report in reports.items():
                identities = all(report[k] == anchor[k] for k in ('model', 'native_library_sha256', 'reference_sha256', 'cases_sha256', 'bundle_assets', 'source_files', 'decode_configuration'))
                runtime = {k: v for k, v in report['runtime'].items() if k != 'native_threads'} == {k: v for k, v in anchor['runtime'].items() if k != 'native_threads'}
                cohorts = {cohort: semantic(report[cohort]) == semantic(anchor[cohort]) for cohort in COHORTS}
                require(identities and runtime and all(cohorts.values()), 'Cross-arm retained semantics ' + str(threads))
                comparisons[str(threads)] = {'comparable': True, 'passed': True, 'identities_match_threads_2': identities, 'runtime_matches_threads_2_except_thread_count': runtime, 'cohorts_match_threads_2_except_timing': cohorts}
            output['cross_arm_comparison'] = comparisons
        if not args.partial:
            require(list(reports) == THREADS and serial['completed'] is True and serial['passed'] is True, 'All four arms completed and accepted')
            require(serial['source_dependencies_sdk_stable'] is True and serial['all_runs_nonoverlapping'] is True and serial['frozen_two_thread_comparison_passed'] is True, 'Serial completion flags')
            require(output['historical_two_thread_comparison'] == load(run / 'result/threads-2-frozen-comparison.json'), 'Saved historical comparator exactly reproduced')
            require(output['cross_arm_comparison'] == serial['cross_arm_comparison'], 'Saved cross-arm comparison exactly reproduced')
            controls = load(prep / 'result/audit-controls.json')
            require(controls['passed'] is True and len(controls['controls']) == 23 and all(x['passed'] for x in controls['controls']), 'All 23 preparation auditor controls')
            require(controls['harness_sha256'] == output['harness_sha256'] and controls['comparator_sha256'] == output['comparator_sha256'], 'Prepared audit controls bind unchanged harness')
            output['guarded_preparation'] = guard_check(prep, source, args.commit, False)
            output['guarded_sweep'] = guard_check(run, source, args.commit, True)
            require(datetime.fromisoformat(load(prep / 'orchestration.json')['finished_utc']) <= datetime.fromisoformat(load(run / 'orchestration.json')['started_utc']), 'Preparation completed before sweep')
            output['archives'] = [archive_check(prep, native), archive_check(run, native)]
        after_head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
        after_status = subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True)
        require(after_head == before_head and after_status == before_status == '', 'Frozen checkout unchanged throughout review')
        output['completed_arms_reviewed'] = len(reports)
        output['review_passed'] = True
        output['accepted'] = not args.partial
    except Exception as error:
        output['findings'].append({'type': type(error).__name__, 'message': str(error)})
        output['review_passed'] = False
    output['checks_performed'] = checks
    output['review_script_sha256'] = sha(Path(__file__))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(output, stream, indent=2, ensure_ascii=False, allow_nan=False)
        stream.write('\n')
    print(json.dumps({k: output[k] for k in ('accepted', 'review_passed', 'partial', 'checks_performed', 'findings')}))
    return 0 if output['review_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
