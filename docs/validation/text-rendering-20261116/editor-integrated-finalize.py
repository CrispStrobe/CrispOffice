"""Finish receipts from the completed test run; never execute or rerun tests."""

from pathlib import Path
import datetime
import hashlib
import json


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False)
        stream.write('\n')


def main():
    evidence = Path(__file__).resolve().parent
    prefix = 'editor-integrated'
    before = json.loads((evidence / f'{prefix}-inputs-before.json').read_text())
    after = json.loads((evidence / f'{prefix}-inputs-after.json').read_text())
    original_path = evidence / f'{prefix}-run.py'
    original = original_path.read_bytes()
    assert digest(original) == before['runner_sha256']
    assert before['git_head'] == '4c1d71adea066bd5ee4d510a8b60b79b64f96a49'
    assert before['test_file_count'] == 16
    # Preserve the executed runner. Correct only its event-path shadowing in
    # memory, then reuse its parser and archive code on existing output.
    source = original.decode('utf-8')
    corrections = [
        ('def parse_events(path, work):', 'def parse_events(event_path, work):'),
        ('lines = path.read_text().splitlines() if path.is_file() else []',
         'lines = event_path.read_text().splitlines() if event_path.is_file() else []'),
        ("'event_log_found': path.is_file(),", "'event_log_found': event_path.is_file(),"),
    ]
    for old, new in corrections:
        assert source.count(old) == 1, old
        source = source.replace(old, new, 1)
    namespace = {'__name__': 'receipt_postprocessor', '__file__': str(original_path)}
    exec(compile(source, str(original_path), 'exec'), namespace)
    command = before['command']
    reporter = command[command.index('--file-reporter') + 1]
    assert reporter.startswith('json:')
    raw_events = Path(reporter[len('json:'):])
    raw_log = raw_events.with_name(f'{prefix}.log')
    assert raw_events.is_file() and raw_log.is_file()
    outcomes = namespace['parse_events'](raw_events, Path(before['cwd']))
    missing = sorted(set(before['test_files']) - set(outcomes['observed_suite_files']))
    changed = sorted(name for name in before['source_sha256'].keys() | after['source_sha256'].keys()
                     if before['source_sha256'].get(name) != after['source_sha256'].get(name))
    assert changed == after['changed_inputs']
    qualified = (
        after['exit_code'] == 0 and not changed
        and after['git_head'] == before['git_head']
        and not after['published_source_mismatches_after']
        and after['dependency_lock_matches_published_receipt']
        and outcomes['runner_done'] is not None
        and outcomes['runner_done'].get('success') is True
        and not outcomes['failures'] and not outcomes['hidden_failures']
        and not outcomes['runner_errors'] and not outcomes['malformed_event_lines']
        and not outcomes['unfinished_tests'] and not outcomes['duplicate_test_done_ids']
        and not outcomes['orphan_test_done_ids'] and not missing
    )
    targets = [evidence / f'{prefix}{suffix}' for suffix in (
        '.log.gz', '-events.jsonl.gz', '-summary.json', '-finalization.json',
    )]
    assert not any(path.exists() for path in targets), 'Existing evidence must not be overwritten.'
    archives = [
        namespace['archive'](raw_log, evidence / f'{prefix}.log.gz'),
        namespace['archive'](raw_events, evidence / f'{prefix}-events.jsonl.gz'),
    ]
    finalization = {
        'finalized_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'test_process_exit_code': after['exit_code'],
        'original_runner_sha256': digest(original),
        'postprocessor_sha256': digest(Path(__file__).read_bytes()),
        'reason': 'Tests completed and before/after input receipts were saved. The runner then failed while adding event_log_found because its event Path parameter was shadowed by a per-test path string.',
        'correction': 'Rename only the event-path parameter/references in memory while retaining the exact executed runner. Parse and archive the completed run output.',
        'tests_rerun': False,
        'original_runner_and_input_receipts_preserved': True,
        'repository_source_or_dependency_files_changed': False,
    }
    summary = {
        'git_head_at_start': before['git_head'], 'git_head_at_finish': after['git_head'],
        'started_utc': before['started_utc'], 'finished_utc': after['finished_utc'],
        'command': command, 'cwd': before['cwd'],
        'test_file_count': before['test_file_count'], 'test_files': before['test_files'],
        'input_file_count': len(before['source_sha256']), 'changed_inputs': changed,
        'published_source_mismatches_after': after['published_source_mismatches_after'],
        'dependency_lock_provenance': before['dependency_lock_provenance'],
        'exit_code': after['exit_code'], 'qualified': qualified, 'missing_suite_files': missing,
        'excluded_test_name_pattern': None, 'excluded_image_golden_tests': 0,
        **outcomes, 'archives': archives,
        'receipt_finalization': finalization,
    }
    write_json(evidence / f'{prefix}-finalization.json', finalization)
    write_json(evidence / f'{prefix}-summary.json', summary)
    print(json.dumps({key: summary[key] for key in (
        'qualified', 'exit_code', 'counts', 'distinct_visible_tests', 'test_file_count',
        'input_file_count', 'changed_inputs', 'missing_suite_files', 'failures', 'hidden_failures',
    )}, indent=2))
    return 0 if qualified else 2


if __name__ == '__main__':
    raise SystemExit(main())
