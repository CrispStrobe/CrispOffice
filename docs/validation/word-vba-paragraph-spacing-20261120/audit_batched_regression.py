"""Independent bounded-regression evidence audit; no producer imports."""
import collections
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import tarfile

QUALIFIED = '0201b549d0dc3f601c50e36255d557034cb01699'
TREE = '86531c002a6b1d6e748849f7370a87072a5fa768'
ADDED = {'office_vba_word_line_spacing_test.dart': 99,
         'office_macro_word_line_spacing_test.dart': 96,
         'office_vba_word_line_spacing_integration_test.dart': 23,
         'word_font_line_metrics_test.dart': 5,
         'word_line_box_fidelity_test.dart': 7}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canon(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def load(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def audit_timeout_diagnostics(a, directory, reference):
    index_path = directory / 'diagnostics/attempts.json'
    if not index_path.exists():
        return []
    attempts = load(index_path)
    require([x['batch_id'] for x in attempts] == [2, 3], 'Known diagnostic timeout invocations')
    results = []
    for attempt in attempts:
        bd = a.base / attempt['preserved_directory']
        require(bd.is_relative_to(directory / 'diagnostics'), 'Diagnostic path remains outside accepted batch directories')
        require(attempt == load(bd / 'relocation-and-observation.json'), 'Exact relocation/observation index copy')
        require(attempt['accepted'] is False and attempt['count_contribution'] == 0, 'Diagnostic acceptance exclusion')
        for name, row in attempt['original_files'].items():
            raw = (bd / name).read_bytes()
            require(row == {'bytes': len(raw), 'sha256': sha(raw)}, 'Relocated original file size/digest')
        for name, digest in attempt['launcher_logs'].items():
            require(sha((a.base / name).read_bytes()) == digest, 'Preserved diagnostic launcher log')
        events = [json.loads(row) for row in (bd / 'stdout.jsonl').read_bytes().split(b'\n') if row]
        starts = {e['test']['id']: e['test'] for e in events if e['type'] == 'testStart'}
        errors = [{**e, 'test_name': starts[e['testID']]['name']} for e in events if e['type'] == 'error']
        require(errors == attempt['errors'] and all('TimeoutException after 0:02:00' in e['error'] for e in errors), 'Exact raw diagnostic timeout errors')
        dones = [e for e in events if e['type'] == 'done']
        require(bool(dones) == attempt['terminal_done_present'] and not any(e['success'] for e in dones), 'No successful diagnostic terminal result')
        before = load(bd / 'inputs-before.json.gz')
        if reference is not None:
            require(before == reference, 'Diagnostic source/runtime identical to accepted source selection')
        if attempt['automatic_after_snapshot_present']:
            require(before == load(bd / 'inputs-after.json.gz'), 'Diagnostic normal after snapshot identity')
        else:
            require(not (bd / 'inputs-after.json.gz').exists(), 'No synthesized diagnostic completion snapshot')
            require(before == load(bd / 'inputs-at-termination-observation.json.gz'), 'Separate diagnostic termination observation identity')
        require((bd / 'execution.json').exists() == attempt['execution_receipt_present'], 'Actual diagnostic process receipt presence')
        if attempt['execution_receipt_present']:
            require(load(bd / 'execution.json')['exit_code'] == attempt['tool_process_exit_code'] == 1, 'Recorded failed diagnostic process exit')
        else:
            require(attempt['owned_session_interrupt_requested'] is True and attempt['tool_process_exit_code'] == 130, 'Recorded tool interruption kept distinct from normal completion')
        visible = [e for e in events if e['type'] == 'testDone' and not e['hidden']]
        results.append({'batch_id': attempt['batch_id'], 'classification': 'FAILED_DIAGNOSTIC',
                        'visible_completed_cases': len(visible),
                        'visible_successful_cases': sum(e['result'] == 'success' and not e['skipped'] for e in visible),
                        'visible_failed_cases': sum(e['result'] != 'success' for e in visible),
                        'reporter_timeout_errors': len(errors), 'accepted_case_contribution': 0,
                        'source_and_recorded_runtime_unchanged': True,
                        'original_payloads_unchanged_through_relocation': True,
                        'normal_execution_receipt_present': attempt['execution_receipt_present'],
                        'recorded_tool_exit_code': attempt['tool_process_exit_code'],
                        'cause_claim': 'Resource contention remains an inference; the review verifies concrete timeout evidence and separately accepted retries.'})
    return results


def audit_batched_regression(a, allow_running):
    d = a.runtime / 'word-spacing-batched-final-0201b549'
    plan, batches = load(d / 'plan.json'), load(d / 'batches.json')
    require(plan['schema'] == 'quds-word-spacing-bounded-original-suite-gate/v1', 'Bounded gate schema')
    require(plan['source_commit'] == QUALIFIED, 'Bounded gate source')
    require([b['id'] for b in batches] == list(range(1, 9)), 'Eight unique bounded batch IDs')
    require([len(b['files']) for b in batches] == [10] * 7 + [5], 'Seven ten-file batches and one five-file batch')
    selected = [name for batch in batches for name in batch['files']]
    require(len(selected) == len(set(selected)) == 75 and selected == plan['files'], 'Every selected original file occurs exactly once')
    prior_dir = a.repo / 'docs/validation/word-vba-list-levels-20261120'
    prior_report = load(prior_dir / 'regression.json')
    require((prior_dir / 'regression.json').read_bytes() == a.git('show', QUALIFIED + ':docs/validation/word-vba-list-levels-20261120/regression.json'), 'Prior report immutable Git bytes')
    require(sha((prior_dir / 'regression.json').read_bytes()) == plan['prior_report_sha256'], 'Prior report SHA')
    require(load(d / 'prior-report.json') == prior_report, 'Prior report snapshot')
    prior_archive = prior_dir / 'regression-evidence.tar.xz'
    require(sha(prior_archive.read_bytes()) == plan['prior_archive_sha256'], 'Prior archive SHA')
    with tarfile.open(prior_archive, 'r:xz') as archive:
        raw_cases = archive.extractfile('runtime/word-office-final/cases.json.gz').read()
        raw_inputs = archive.extractfile('runtime/word-office-final/inputs-before.json.gz').read()
        raw_events = archive.extractfile('runtime/word-office-final/stdout.jsonl').read()
    for name, data in [('cases.json.gz', raw_cases), ('inputs-before.json.gz', raw_inputs), ('stdout.jsonl', raw_events)]:
        require(sha(data) == prior_report['hashes'][name], 'Prior archive member: ' + name)
    require((d / 'prior-cases.json.gz').read_bytes() == raw_cases, 'Prior raw cases snapshot')
    require((d / 'prior-inputs-before.json.gz').read_bytes() == raw_inputs, 'Prior raw inputs snapshot')
    require(gzip.decompress((d / 'prior-stdout.jsonl.gz').read_bytes()) == raw_events, 'Prior raw reporter snapshot')
    previous_files = set(prior_report['per_file_cases'])
    require(len(previous_files) == 70 and set(plan['previous_files']) == previous_files, 'Complete previous70 selection')
    old = a.reporter(raw_events, previous_files, legacy=True)
    prior_saved = json.loads(gzip.decompress(raw_cases))
    old_ids = {(c['file'], c['name'], c['occurrence']) for c in prior_saved}
    require(old['identities'] == old_ids and len(prior_saved) == old['passed_cases'] == 2569, 'Reconstructed exact prior2569 identities')
    expected = {**old['counts'], **ADDED}
    require(set(selected) == previous_files | set(ADDED), 'Previous70 plus five additional modules')
    require(plan['expected_per_file_cases'] == expected and plan['expected_total_cases'] == 2799, 'Expected complete counts')
    vba = {p.name for p in (a.engine / 'test').glob('office_vba_*_test.dart')}
    require(vba <= set(selected) and len(vba) == 48, 'All current48 VBA modules')
    for batch in batches:
        require(batch['expected_cases'] == sum(expected[f] for f in batch['files']), 'Batch planned case count')

    initial_dir = a.runtime / 'word-spacing-final-0201b549'
    initial_events = [json.loads(row) for row in (initial_dir / 'stdout.jsonl').read_bytes().split(b'\n') if row]
    initial_count = sum(e['type'] == 'testDone' and not e['hidden'] for e in initial_events)
    require(initial_count == 2679 and not any(e['type'] == 'done' for e in initial_events), 'Interrupted reporter remains incomplete diagnostic')
    require(not any((initial_dir / name).exists() for name in ['execution.json', 'inputs-after.json.gz', 'summary.json']), 'No invented original completion evidence')
    require(plan['interrupted_attempt']['accepted'] is False, 'Interrupted attempt excluded')
    interrupted = {'status': 'INCOMPLETE_DIAGNOSTIC', 'visible_completed_cases': initial_count,
                   'accepted_case_contribution': 0, 'terminal_done_present': False,
                   'process_exit_receipt_present': False, 'automatic_after_snapshot_present': False,
                   'raw_reporter_sha256': sha((initial_dir / 'stdout.jsonl').read_bytes()),
                   'artifact_manifest': a.files(initial_dir)}

    results, cases, records, identities, counts = [], [], [], set(), collections.Counter()
    namespace_starts, namespace_dones, execution_intervals = [], [], []
    reference = None
    for batch in batches:
        bd = d / f'batch-{batch["id"]:02d}'
        if not (bd / 'summary.json').exists():
            require(allow_running, 'Incomplete batch: ' + str(batch['id']))
            continue
        before, binding = a.bindings(bd, 3489)
        if reference is None:
            reference = before
            runtime_scope = a.regression_runtime_selection(before['runtime_inputs'], d)
        require(before == reference, 'Identical full source/runtime snapshot across batches')
        command, execution = load(bd / 'command.json'), load(bd / 'execution.json')
        require(command['batch_id'] == batch['id'] and command['source_commit'] == QUALIFIED, 'Batch command/source')
        require(command['cwd'] == str(a.engine), 'Batch engine cwd')
        argv = [str(a.tc / 'run-engine-tests.sh'), '--concurrency=2', '--reporter=json', *['test/' + name for name in batch['files']]]
        require(command['argv'] == argv, 'Exact original-suite batch argv')
        require(command['collector_sha256'] == sha((a.runtime / 'run_word_spacing_batched_gate.py').read_bytes()), 'Frozen bounded collector binding')
        require(execution['exit_code'] == 0 and execution['seconds'] > 0, 'Successful batch process receipt')
        start = datetime.datetime.fromisoformat(command['started_utc'])
        end = datetime.datetime.fromisoformat(execution['finished_utc'])
        require(end > start, 'Batch command time interval')
        execution_intervals.extend([(start, 1), (end, -1)])
        require((bd / 'stderr.log').read_bytes() == b'', 'Batch stderr')
        observed = a.reporter((bd / 'stdout.jsonl').read_bytes(), batch['files'])
        require(observed['counts'] == {f: expected[f] for f in batch['files']} and observed['passed_cases'] == batch['expected_cases'], 'Batch complete independently observed cases')
        require(not identities & observed['identities'], 'No duplicate global case identity')
        identities.update(observed['identities'])
        counts.update(observed['counts'])
        cases.extend(observed['cases'])
        expected_records = [dict(row, batch_id=batch['id']) for row in observed['records']]
        require(load(bd / 'cases.json.gz') == expected_records, 'Exact batch stored metadata/outcome/ID records')
        records.extend(expected_records)
        namespace_starts.extend([[batch['id'], ident] for ident in observed['start_ids']])
        namespace_dones.extend([[batch['id'], ident] for ident in observed['completion_ids']])
        s = load(bd / 'summary.json')
        for key, value in {'accepted': True, 'complete': True, 'problems': [], 'errors': [],
                           'batch_id': batch['id'], 'source_commit': QUALIFIED, 'source_tree': TREE,
                           'input_entries': 1131, 'runtime_input_entries': 3489,
                           'source_inputs_unchanged': True, 'runtime_inputs_unchanged': True,
                           'passing_cases': observed['passed_cases'], 'suite_count': len(batch['files']),
                           'failed_cases': 0, 'skipped_cases': 0, 'hidden_completions': observed['hidden_completions'],
                           'per_file_cases': observed['counts'], 'declared_per_file_cases': observed['counts'],
                           'start_ids': observed['start_ids'], 'completion_ids': observed['completion_ids'],
                           'exit_code': 0}.items():
            require(s[key] == value, f'Batch {batch["id"]} summary {key}')
        artifacts = a.files(bd)
        require(s['hashes'] == {k: v['sha256'] for k, v in artifacts.items() if k != 'summary.json'}, 'Exact batch artifact manifest')
        slim = {k: v for k, v in observed.items() if k not in ['cases', 'identities', 'records', 'start_ids', 'completion_ids']}
        results.append({'batch_id': batch['id'], 'status': 'PASS', **binding, 'command': command, 'execution': execution, 'raw_audit': slim})
        print(json.dumps({'reviewed_batch': batch['id'], 'cases': observed['passed_cases'], 'status': 'PASS'}), flush=True)
    common = {'previous_raw_reconstructed_cases': 2569, 'previous_files': 70,
              'original_vm_suites_selected': 75, 'all_current_office_vba_modules': 48,
              'expected_case_count': 2799, 'accepted_batch_reviews': results,
              'interrupted_attempt': interrupted,
              'failed_bounded_attempts': audit_timeout_diagnostics(a, d, reference),
              'collector_review': 'No blocking bookkeeping issue. Every original file occurs once; reporter IDs are namespaced by batch; the independent audit reconstructs every group declaration, case, source coordinate, outcome, and start/completion.'}
    if len(results) != 8 or not (d / 'summary.json').exists():
        require(allow_running, 'Global bounded gate incomplete')
        return {'status': 'RUNNING', **common}
    require(len(cases) == len(identities) == 2799 and dict(counts) == expected, 'Exact complete2799-case global selection')
    require(namespace_starts == namespace_dones and len(namespace_starts) == len({tuple(x) for x in namespace_starts}), 'Complete unique namespaced starts/completions')
    require(load(d / 'cases.json.gz') == records, 'Exact global raw-derived case records')
    current_previous = {x for x in identities if x[0] in previous_files}
    require(current_previous == old_ids, 'Previous2569 exact global identities')
    prior_inputs = json.loads(gzip.decompress(raw_inputs))
    per_file = {}
    for name in sorted(previous_files):
        path = 'packages/quds_office_engine/test/' + name
        require(prior_inputs['entries'][path] == reference['entries'][path], 'Previous test source exact unchanged: ' + name)
        old_count = sum(x[0] == name for x in old_ids)
        new_count = sum(x[0] == name for x in current_previous)
        per_file[name] = {'source_unchanged': True, 'previous_cases': old_count, 'current_cases': new_count, 'exact_case_identities_match': True}
    comparison = {'exact_match': True, 'previous_cases': 2569, 'current_cases': 2569, 'missing': [], 'extra': [], 'per_file': per_file}
    require(load(d / 'case-identity-comparison.json') == comparison, 'Exact previous-case comparison receipt')
    final_inputs = load(d / 'inputs-final.json.gz')
    require(final_inputs == reference, 'Final audit snapshot matches all16 before/after snapshots')
    if (d / 'inputs-before.json.gz').exists():
        require(load(d / 'inputs-before.json.gz') == reference, 'Published before-binding alias')
    if (d / 'inputs-after.json.gz').exists():
        require(load(d / 'inputs-after.json.gz') == final_inputs, 'Published final after-binding alias')
    a.sources(final_inputs)
    a.runtime_inputs(final_inputs['runtime_inputs'], 3489)
    active, peak = 0, 0
    for _, change in sorted(execution_intervals, key=lambda x: (x[0], x[1])):
        active += change
        peak = max(peak, active)
    require(active == 0 and peak <= 2, 'At most two independent command intervals overlap')
    s = load(d / 'summary.json')
    for key, value in {'accepted': True, 'complete': True, 'problems': [],
                       'source_commit': QUALIFIED, 'source_tree': TREE, 'file_count': 75, 'suite_count': 75,
                       'batch_count': 8, 'passing_cases': 2799, 'failed_cases': 0, 'skipped_cases': 0,
                       'reporter_errors': 0, 'input_entries': 1131, 'runtime_input_entries': 3489,
                       'inputs_unchanged': True, 'runtime_inputs_unchanged': True, 'head_matches_worktree': True,
                       'per_file_cases': dict(counts), 'namespaced_start_ids': namespace_starts,
                       'namespaced_completion_ids': namespace_dones, 'previous_case_identities': comparison,
                       'github_actions_queried_or_awaited': False}.items():
        require(s[key] == value, 'Global bounded summary ' + key)
    artifacts = a.files(d, recursive=True)
    require(s['hashes'] == {k: v['sha256'] for k, v in artifacts.items() if k != 'summary.json'}, 'Complete recursive bounded artifact manifest')
    return {'status': 'PASS', **common, 'binding_snapshots_verified': 17,
            'source': {'qualified_paths': 1131, 'actual_contents_modes_and_git_objects_verified': True},
            'runtime': {'recorded_paths': 3489, 'all_recorded_actual_contents_verified': True},
            'runtime_scope': runtime_scope, 'before_after_and_between_batches_exactly_equal': True,
            'independent_raw_audit': {'passed_cases': 2799, 'failed_cases': 0, 'skipped_cases': 0,
                                     'suite_count': 75, 'batch_count': 8, 'per_file_cases': dict(counts),
                                     'namespaced_start_completion_count': len(namespace_starts),
                                     'namespaced_start_completion_sha256': sha(canon(namespace_starts)),
                                     'maximum_overlapping_command_intervals': peak},
            'case_identity_set_sha256': sha(canon(sorted(identities))),
            'previous_70_exact_case_and_source_comparison': comparison,
            'new_feature_cases': 218, 'additional_existing_layout_cases': 12,
            'artifact_manifest': artifacts}
