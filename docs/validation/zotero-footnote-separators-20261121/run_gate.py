#!/usr/bin/env python3
"""Run one local gate with complete workspace hashes and strict test receipts."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import time


WORKSPACE_ROOTS = {'.github', 'apps', 'packages', 'third_party', 'tool', 'tools'}
SNAPSHOT_SCOPE = (
    'All tracked files under .github/apps/packages/third_party/tool/tools, '
    'all tracked repository-root files, this runner, and generated package '
    'configurations beside tracked pubspec.yaml files. The after snapshot '
    'also retains every initial path so deletion or untracking cannot hide '
    'an input-content change.'
)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def workspace_paths(repo):
    """Include examples, local path dependencies, fixtures and assets too."""
    names = subprocess.check_output(
        ['git', '-C', str(repo), 'ls-files', '-z'], text=True,
    ).split('\0')
    tracked = {name for name in names if name}
    selected = {
        name for name in tracked
        if '/' not in name or name.split('/', 1)[0] in WORKSPACE_ROOTS
    }
    runner = Path(__file__).resolve()
    if runner.is_relative_to(repo):
        selected.add(str(runner.relative_to(repo)))
    for name in tracked:
        if Path(name).name == 'pubspec.yaml':
            config = Path(name).parent / '.dart_tool' / 'package_config.json'
            if (repo / config).is_file():
                selected.add(str(config))
    return selected


def snapshot(repo, initial_paths=()):
    # Keep initial paths even after removal from the index. A deleted input
    # becomes null in the after snapshot instead of disappearing silently.
    current = workspace_paths(repo)
    paths = current | set(initial_paths)
    result = {}
    for name in sorted(paths):
        path = repo / name
        if path.is_file():
            result[name] = digest(path)
        elif not initial_paths:
            raise FileNotFoundError(f'Tracked workspace input is missing: {name}')
        else:
            result[name] = None
    return result


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def inspect_test_events(raw, cwd):
    """Audit every lifecycle; successful hidden loaders are not test cases."""
    issues, unparsed, events = [], [], []
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as error:
        issues.append(f'Output is not UTF-8: {error}')
        text = raw.decode('utf-8', errors='replace')
    for number, line in enumerate(text.splitlines(), 1):
        try:
            event = json.loads(line)
        except ValueError:
            unparsed.append({'line': number, 'text': line})
            continue
        if not isinstance(event, dict) or not isinstance(event.get('type'), str):
            issues.append(f'Line {number}: event is not a typed object')
            continue
        events.append(event)

    suites, groups, starts, finishes = {}, {}, {}, {}
    errors, done, declared = [], [], []
    event_counts = Counter()
    for index, event in enumerate(events):
        kind = event['type']
        event_counts[kind] += 1
        if done:
            issues.append(f'Event {index}: event follows terminal done')
        if kind in ('suite', 'group', 'testStart'):
            key = {'suite': 'suite', 'group': 'group', 'testStart': 'test'}[kind]
            item = event.get(key)
            if not isinstance(item, dict) or type(item.get('id')) is not int:
                issues.append(f'Event {index}: invalid {key} identity')
                continue
            item_id = item['id']
            target = {'suite': suites, 'group': groups, 'testStart': starts}[kind]
            if item_id in target:
                issues.append(f'Duplicate {key} identity: {item_id}')
                continue
            target[item_id] = item
            if kind == 'suite':
                if not isinstance(item.get('path'), str) or not item['path']:
                    issues.append(f'Suite {item_id}: missing path')
            else:
                if item.get('suiteID') not in suites:
                    issues.append(f'{key} {item_id}: unknown suite')
                if kind == 'group':
                    if type(item.get('testCount')) is not int or item['testCount'] < 0:
                        issues.append(f'Group {item_id}: invalid test count')
                    parent = item.get('parentID')
                    if parent is not None and parent not in groups:
                        issues.append(f'Group {item_id}: unknown parent')
                else:
                    if not isinstance(item.get('name'), str) or not item['name']:
                        issues.append(f'Test {item_id}: missing name')
                    group_ids = item.get('groupIDs')
                    if not isinstance(group_ids, list):
                        issues.append(f'Test {item_id}: missing group identities')
                    else:
                        for group_id in group_ids:
                            group = groups.get(group_id)
                            if group is None or group.get('suiteID') != item.get('suiteID'):
                                issues.append(f'Test {item_id}: unknown or foreign group {group_id}')
        elif kind == 'testDone':
            test_id = event.get('testID')
            if type(test_id) is not int:
                issues.append(f'Event {index}: invalid completion identity')
                continue
            if test_id in finishes:
                issues.append(f'Duplicate completion for test {test_id}')
                continue
            finishes[test_id] = event
            if test_id not in starts:
                issues.append(f'Completion without start: {test_id}')
            if type(event.get('hidden')) is not bool or type(event.get('skipped')) is not bool:
                issues.append(f'Test {test_id}: missing hidden/skipped completion flags')
        elif kind == 'error':
            errors.append(event)
        elif kind == 'allSuites':
            declared.append(event)
        elif kind == 'done':
            done.append(event)

    for kind in ('start', 'allSuites', 'done'):
        if event_counts[kind] != 1:
            issues.append(f'Expected one {kind} event, found {event_counts[kind]}')
    if not events or events[0]['type'] != 'start':
        issues.append('The stream does not begin with start')
    if not events or events[-1]['type'] != 'done':
        issues.append('The stream does not end with done')
    if len(declared) == 1 and declared[0].get('count') != len(suites):
        issues.append(f'Declared suite count differs from observed {len(suites)}')
    missing = sorted(starts.keys() - finishes.keys())
    if missing:
        issues.append(f'Tests without completion: {missing}')

    identities, failures, skips = [], [], []
    hidden_failed, hidden_skipped, hidden_passed = [], [], 0
    hooks, hook_counts = [], Counter()
    visible_group_counts = Counter()
    unique_identities = set()
    for test_id, completion in finishes.items():
        test = starts.get(test_id, {})
        suite = suites.get(test.get('suiteID'), {})
        identity = {'path': suite.get('path'), 'name': test.get('name')}
        hidden = completion.get('hidden') is True
        name = test.get('name', '')
        is_hook = any(
            name == suffix or name.endswith(' ' + suffix)
            for suffix in ('(setUpAll)', '(tearDownAll)')
        )
        if is_hook:
            # Hooks are required lifecycle work, never independent test cases,
            # including reporter versions that mark a hook hidden:false.
            outcome = ('skipped' if completion.get('skipped') else
                       'passed' if completion.get('result') == 'success' else 'failed')
            hook_counts[outcome] += 1
            hooks.append({**identity, 'result': outcome, 'hidden': hidden})
            continue
        if hidden:
            if completion.get('skipped'):
                hidden_skipped.append(identity)
            elif completion.get('result') == 'success':
                hidden_passed += 1
            else:
                hidden_failed.append(identity)
            continue
        visible_group_counts.update(test.get('groupIDs', []))
        key = (str((cwd / identity['path']).resolve()) if identity['path'] else None,
               identity['name'])
        if key in unique_identities:
            issues.append(f'Duplicate visible test identity: {identity}')
        unique_identities.add(key)
        if completion.get('skipped'):
            skips.append(identity)
        elif completion.get('result') == 'success':
            identities.append(identity)
        else:
            failures.append(identity)
    for group_id, group in groups.items():
        if group.get('testCount') != visible_group_counts[group_id]:
            issues.append(
                f'Group {group_id}: declared {group.get("testCount")} tests, '
                f'observed {visible_group_counts[group_id]} visible completions'
            )
    summary = {
        'passed': len(identities), 'failed': len(failures), 'skipped': len(skips),
        'errors': len(errors), 'suites': len(suites), 'groups': len(groups),
        'started': len(starts), 'completed': len(finishes),
        'hidden_passed': hidden_passed, 'hidden_failed': len(hidden_failed),
        'hidden_skipped': len(hidden_skipped), 'done': done,
        'hooks_passed': hook_counts['passed'], 'hooks_failed': hook_counts['failed'],
        'hooks_skipped': hook_counts['skipped'], 'hook_results': hooks,
        'failures': failures, 'skips': skips,
        'hidden_failures': hidden_failed, 'hidden_skips': hidden_skipped,
        'unparsed_lines': unparsed, 'lifecycle_errors': issues,
    }
    accepted = (
        bool(identities) and not failures and not skips and not errors
        and not hidden_failed and not hidden_skipped
        and not hook_counts['failed'] and not hook_counts['skipped']
        and not unparsed and not issues
        and len(done) == 1 and done[0].get('success') is True
    )
    return summary, identities, accepted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--cwd', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--test-events', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A command after -- is required')
    repo = args.repo.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source_head = subprocess.check_output(
        ['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True,
    ).strip()
    before = snapshot(repo)
    inputs = json.dumps(before, sort_keys=True).encode()
    (output / 'inputs.json.gz').write_bytes(gzip.compress(inputs, mtime=0))
    receipt = {
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'source_head': source_head,
        'cwd': str(args.cwd.resolve()),
        'command': command,
        'input_scope': SNAPSHOT_SCOPE,
        'input_count': len(before),
        'input_manifest_sha256': hashlib.sha256(inputs).hexdigest(),
    }
    write_json(output / 'receipt.json', receipt)
    started = time.monotonic()
    with (output / 'stdout.log').open('wb') as stdout, (output / 'stderr.log').open('wb') as stderr:
        result = subprocess.run(command, cwd=args.cwd.resolve(), stdout=stdout, stderr=stderr)
    receipt.update(exit_code=result.returncode, duration_seconds=round(time.monotonic() - started, 3))
    after = snapshot(repo, before)
    changed = sorted(
        path for path in before.keys() | after.keys()
        if path not in before or path not in after or before[path] != after[path]
    )
    receipt['inputs_unchanged'] = not changed
    receipt['changed_inputs'] = changed
    good = result.returncode == 0 and not changed
    if args.test_events:
        summary, identities, events_accepted = inspect_test_events(
            (output / 'stdout.log').read_bytes(), args.cwd.resolve(),
        )
        receipt['tests'] = summary
        write_json(output / 'test-identities.json', identities)
        good = good and events_accepted
    for name in ('stdout.log', 'stderr.log'):
        path = output / name
        data = path.read_bytes()
        receipt[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        (output / (name + '.gz')).write_bytes(gzip.compress(data, mtime=0))
    receipt['accepted'] = good
    receipt['finished_utc'] = datetime.now(timezone.utc).isoformat()
    write_json(output / 'receipt.json', receipt)
    print(json.dumps({k: receipt[k] for k in ('source_head', 'exit_code', 'input_count', 'inputs_unchanged', 'accepted')}))
    if 'tests' in receipt:
        print(json.dumps({k: receipt['tests'][k] for k in ('passed', 'failed', 'skipped', 'errors', 'suites')}))
    raise SystemExit(0 if good else 1)


if __name__ == '__main__':
    main()
