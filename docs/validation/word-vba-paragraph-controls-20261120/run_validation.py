#!/usr/bin/env python3
"""Run source-bound Word/Office gates with genuine, separate package:test suites.

The default invocation runs regression, whole-engine strict analysis and changed
Dart formatting. --plan-only records no acceptance and starts no Dart process.
Portable BAS/JavaScript checks use the exported deterministic manifest helpers.
"""

import argparse
import collections
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tarfile
import time
from urllib.parse import unquote, urljoin, urlparse


HERE = Path(__file__).resolve().parent
ENGINE = 'packages/quds_office_engine'
PARSER = 'packages/legacy_doc_parser'
VALIDATION = 'docs/validation/word-vba-paragraph-controls-20261120'
PREVIOUS = 'docs/validation/word-vba-list-levels-20261120'


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def write_gzip_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()
    path.write_bytes(gzip.compress(data, mtime=0))


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def file_signature(path):
    """Content, absolute path and modes; no timestamps or mutable cache metadata."""
    path = Path(path).absolute()
    info = path.lstat()
    link = stat.S_ISLNK(info.st_mode)
    if not (link or stat.S_ISREG(info.st_mode)):
        raise ValueError('Expected a regular file or link: ' + str(path))
    length = len(os.readlink(path).encode()) if link else info.st_size
    sha256 = hashlib.sha256()
    blob = hashlib.sha1(f'blob {length}\0'.encode())
    if link:
        content = os.readlink(path).encode()
        sha256.update(content)
        blob.update(content)
    else:
        with path.open('rb') as source:
            for block in iter(lambda: source.read(1024 * 1024), b''):
                sha256.update(block)
                blob.update(block)
    result = dict(path=str(path), bytes=length, sha256=sha256.hexdigest(),
                  mode=format(stat.S_IMODE(info.st_mode), '04o'),
                  kind='symlink' if link else 'file', git_blob=blob.hexdigest(),
                  git_mode='120000' if link else '100755' if info.st_mode & 0o111 else '100644')
    if link:
        result['target'] = os.readlink(path)
        resolved = path.resolve(strict=True)
        if resolved.is_file():
            result['referent'] = file_signature(resolved)
    return result


def collect_source_inputs(repo):
    """All engine/parser files and fixtures, root config, and acceptance controls."""
    repo = Path(repo).resolve()
    raw = git(repo, 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
              '--', ENGINE, PARSER)
    paths = {item.decode() for item in raw.split(b'\0') if item}
    paths.update({'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
                  VALIDATION + '/run_validation.py',
                  VALIDATION + '/regression-selection.json',
                  PREVIOUS + '/regression.json',
                  PREVIOUS + '/regression-evidence.tar.xz'})
    if (repo / 'dart_test.yaml').exists():
        paths.add('dart_test.yaml')
    return {path: file_signature(repo / path) for path in sorted(paths)}


def collect_runtime_inputs(repo, runtime, extra_paths=()):
    """Bind SDK and dependency sources plus the actual config and test runner.

    Only static bin/lib/package metadata is selected. Generated caches, logs,
    temporary test output and the SDK download archive are not runtime inputs.
    """
    repo, runtime = Path(repo).resolve(), Path(runtime).resolve()
    config = repo / '.dart_tool/package_config.json'
    paths = {config, runtime / 'env.sh', runtime / 'run-engine-tests.sh',
             runtime / 'test-runner/test-runner.dill'}
    sdk = runtime / 'dart-sdk'
    for folder in [sdk / 'bin', sdk / 'lib']:
        paths.update(path for path in folder.rglob('*') if path.is_file() or path.is_symlink())
    for name in ['version', 'revision', 'sdk_packages.yaml']:
        if (sdk / name).exists():
            paths.add(sdk / name)
    for package in json.loads(config.read_text())['packages']:
        uri = urlparse(urljoin(config.as_uri(), package['rootUri']))
        if uri.scheme != 'file':
            raise ValueError('Unbound package URI: ' + package['rootUri'])
        root = Path(unquote(uri.path)).resolve()
        if root.is_relative_to(repo):
            continue
        for name in ['pubspec.yaml', 'pubspec.lock']:
            if (root / name).exists():
                paths.add(root / name)
        for name in ['lib', 'bin']:
            if (root / name).is_dir():
                paths.update(path for path in (root / name).rglob('*')
                             if path.is_file() or path.is_symlink())
    paths.update(Path(path).absolute() for path in extra_paths)
    return {str(path): file_signature(path) for path in sorted(paths)}


def source_matches_head(repo, inputs):
    entries = {}
    for raw in git(repo, 'ls-tree', '-r', '-z', 'HEAD').split(b'\0'):
        if raw:
            header, name = raw.split(b'\t', 1)
            mode, kind, oid = header.decode().split()
            entries[name.decode()] = [mode, kind, oid]
    mismatches = [path for path, value in inputs.items()
                  if entries.get(path) != [value['git_mode'], 'blob', value['git_blob']]]
    return dict(matches=not mismatches, mismatches=mismatches)


def load_environment(runtime):
    raw = subprocess.check_output(
        ['bash', '-c', 'source "$1"; env -0', 'quds-validation', str(runtime / 'env.sh')],
    )
    return dict(row.decode().split('=', 1) for row in raw.split(b'\0') if row)


def read_selection(repo):
    selection = json.loads((repo / VALIDATION / 'regression-selection.json').read_text())
    paths = [entry['path'] for entry in selection['files']]
    if len(paths) != len(set(paths)) or len(paths) != selection['file_count']:
        raise ValueError('Duplicate or mismatched regression selection')
    actual_vba = {str(path.relative_to(repo / ENGINE))
                  for path in (repo / ENGINE / 'test').glob('office_vba_*_test.dart')}
    selected_vba = {path for path in paths if Path(path).name.startswith('office_vba_')}
    if actual_vba != selected_vba:
        raise ValueError('Selection no longer contains exactly all office_vba_* modules')
    prior = json.loads((repo / selection['previous_record']).read_text())
    expected_prior = {'test/' + name for name in prior['per_file_cases']}
    selected_prior = {entry['path'] for entry in selection['files']
                      if 'previous_gate' in entry['groups']}
    if selected_prior != expected_prior or len(selected_prior) != 70:
        raise ValueError('Previous complete 70-module gate was changed or truncated')
    for path in paths:
        if not (repo / ENGINE / path).is_file():
            raise ValueError('Selected original test file is missing: ' + path)
    return selection


def parse_events(path, engine, selected_paths):
    """Require paired genuine test events and preserve every substantive case."""
    suites, tests, finished, cases = {}, {}, {}, []
    problems, errors, terminals = [], [], []
    starts, announced = 0, []
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        for prefix in ['Running build hooks...', 'Running link hooks...']:
            if line.startswith(prefix):
                line = line[len(prefix):].strip()
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            problems.append('Non-JSON stdout at line ' + str(number))
            continue
        if terminals:
            problems.append('Event after terminal at line ' + str(number))
        kind = event.get('type')
        if kind == 'start':
            starts += 1
        elif starts != 1:
            problems.append('Missing/duplicate start before line ' + str(number))
        if kind == 'suite':
            suite = event['suite']
            identifier = suite['id']
            if identifier in suites:
                problems.append('Duplicate suite ID ' + str(identifier))
            suite_path = Path(suite['path'])
            suite_path = suite_path if suite_path.is_absolute() else engine / suite_path
            try:
                normalized = str(suite_path.resolve().relative_to(engine.resolve()))
            except ValueError:
                normalized = str(suite_path)
                problems.append('Suite outside the engine: ' + normalized)
            suites[identifier] = normalized
            if suite.get('platform') != 'vm':
                problems.append('Unexpected suite platform: ' + str(suite.get('platform')))
        elif kind == 'allSuites':
            announced.append(event['count'])
        elif kind == 'testStart':
            case = event['test']
            if case['id'] in tests:
                problems.append('Duplicate test start ' + str(case['id']))
            tests[case['id']] = case
        elif kind == 'testDone':
            identifier = event['testID']
            if identifier not in tests or identifier in finished:
                problems.append('Unpaired/duplicate test completion ' + str(identifier))
            finished[identifier] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            terminals.append(event)
    if starts != 1 or len(terminals) != 1 or not terminals[0].get('success'):
        problems.append('Protocol requires one start and one successful terminal')
    if tests.keys() != finished.keys():
        problems.append('Test start/completion identities do not match')
    if set(suites.values()) != set(selected_paths) or len(suites) != len(selected_paths):
        problems.append('Observed separate-file suite inventory differs from selection')
    if announced != [len(selected_paths)]:
        problems.append('Declared suite count differs from selection')
    occurrences, per_file = collections.Counter(), collections.Counter()
    failed = skipped = hidden = 0
    for identifier, result in finished.items():
        if result.get('result') != 'success':
            failed += 1
        if result.get('skipped') is not False:
            skipped += 1
        case = tests.get(identifier)
        if case is None:
            continue
        suite = suites.get(case['suiteID'])
        if suite is None:
            problems.append('Case references absent suite ' + str(case['suiteID']))
            continue
        if result.get('hidden') is True or case['name'].startswith('loading '):
            hidden += 1
            continue
        key = (suite, case['name'])
        occurrences[key] += 1
        per_file[suite] += 1
        cases.append(dict(file=Path(suite).name, suite=suite, name=case['name'],
                          occurrence=occurrences[key], result=result.get('result'),
                          skipped=result.get('skipped'), test_id=identifier))
    if set(per_file) != set(selected_paths):
        problems.append('One or more selected suites has no substantive completed cases')
    accepted = not (problems or errors or failed or skipped)
    return dict(accepted=accepted, passing_cases=sum(case['result'] == 'success'
                                                     and case['skipped'] is False for case in cases),
                failed_cases=failed, skipped_cases=skipped, error_events=len(errors),
                errors=errors, problems=problems, hidden_completions=hidden,
                file_count=len(suites), per_file_cases=dict(sorted(per_file.items())),
                start_events=starts, terminal_events=len(terminals),
                terminal_success=len(terminals) == 1 and terminals[0].get('success') is True,
                cases=cases)


def compare_previous(repo, selection, cases, source_inputs):
    archive = repo / selection['previous_case_archive']
    with tarfile.open(archive, 'r:xz') as handle:
        raw = handle.extractfile(selection['previous_case_member']).read()
    if hashlib.sha256(raw).hexdigest() != selection['previous_case_member_sha256']:
        raise ValueError('Previous accepted case member identity changed')
    previous = json.loads(gzip.decompress(raw))
    old, current = collections.defaultdict(list), collections.defaultdict(list)
    for case in previous:
        old[case['file']].append([case['name'], case['occurrence']])
    for case in cases:
        current[case['file']].append([case['name'], case['occurrence']])
    comparisons, problems = [], []
    for entry in selection['files']:
        if 'previous_gate' not in entry['groups']:
            continue
        name = Path(entry['path']).name
        identical = source_inputs[ENGINE + '/' + entry['path']]['sha256'] == entry['previous_source_sha256']
        matches = sorted(old[name]) == sorted(current[name])
        comparisons.append(dict(file=name, source_unchanged=identical,
                                previous_cases=len(old[name]), current_cases=len(current[name]),
                                exact_case_identities_equal=matches))
        if identical and not matches:
            problems.append('Unchanged previous module changed case identities: ' + name)
    return dict(accepted=not problems, problems=problems, files=comparisons,
                unchanged_modules=sum(item['source_unchanged'] for item in comparisons),
                unchanged_cases=sum(item['previous_cases'] for item in comparisons if item['source_unchanged']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--phase', nargs='+', choices=['regression', 'analysis', 'format'],
                        default=['regression', 'analysis', 'format'])
    parser.add_argument('--expected-head')
    parser.add_argument('--plan-only', action='store_true')
    args = parser.parse_args()
    repo, runtime, out = args.repo.resolve(), args.runtime.resolve(), args.output_dir.resolve()
    selection = read_selection(repo)
    engine = repo / ENGINE
    dart = runtime / 'dart-sdk/bin/dart'
    head = git(repo, 'rev-parse', 'HEAD').decode().strip()
    if args.expected_head and head != args.expected_head:
        raise ValueError('Current HEAD differs from the requested source freeze')
    changed = git(repo, 'diff', '--name-only', '-z', selection['format_baseline'], '--', ENGINE).decode().split('\0')
    untracked = git(repo, 'ls-files', '-z', '--others', '--exclude-standard', '--', ENGINE).decode().split('\0')
    format_paths = sorted({path for path in changed + untracked if path.endswith('.dart') and (repo / path).is_file()})
    commands = {
        'regression': [str(dart), '--old_gen_heap_size=768', '--packages=' + str(repo / '.dart_tool/package_config.json'),
                       str(runtime / 'test-runner/test-runner.dill'), '--compiler', 'kernel',
                       '--concurrency=1', '--timeout=4x', '--suite-load-timeout=3m',
                       '--fail-fast', '--reporter=json', *[entry['path'] for entry in selection['files']]],
        'analysis': [str(dart), 'analyze', '--fatal-infos', '--fatal-warnings', '.'],
        'format': [str(dart), 'format', '--output=none', '--set-exit-if-changed',
                   *[str(repo / path) for path in format_paths]],
    }
    plan = dict(source_commit=head, source_tree=git(repo, 'rev-parse', 'HEAD^{tree}').decode().strip(),
                engine_cwd=str(engine), phases=args.phase, commands={key: commands[key] for key in args.phase},
                selection=selection, changed_dart_files=format_paths,
                github_actions='NOT QUERIED OR AWAITED',
                execution='Genuine package:test; original test files are distinct VM suites; kernel compiler; concurrency 1.')
    if args.plan_only:
        print(json.dumps(plan, indent=2))
        return 0
    out.mkdir(parents=True, exist_ok=False)
    environment = load_environment(runtime)
    keep = ['QUDS_VALIDATION_ROOT', 'QUDS_DART_ROOT', 'PUB_CACHE', 'TMPDIR',
            'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'DART_SUPPRESS_ANALYTICS', 'PATH']
    plan['environment'] = {name: environment.get(name) for name in keep}
    write_json(out / 'command.json', plan)
    receipt = dict(schema='quds-word-office-local-gate/v1', status='RUNNING',
                   started_utc=utc_now(), source_commit=head, source_tree=plan['source_tree'],
                   github_actions='NOT QUERIED OR AWAITED', checks=[])
    write_json(out / 'receipt.json', receipt)
    for phase in args.phase:
        print(json.dumps(dict(phase=phase, status='RUNNING', at=utc_now())), flush=True)
        before = collect_source_inputs(repo)
        runtime_before = collect_runtime_inputs(repo, runtime)
        head_binding = source_matches_head(repo, before)
        if not head_binding['matches']:
            raise ValueError('Source inputs are not all committed: ' + str(head_binding['mismatches']))
        write_gzip_json(out / (phase + '-source-before.json.gz'), before)
        write_gzip_json(out / (phase + '-runtime-before.json.gz'), runtime_before)
        stdout = out / (phase + ('.jsonl' if phase == 'regression' else '.stdout'))
        stderr = out / (phase + '.stderr')
        started, tick = utc_now(), time.monotonic()
        with stdout.open('wb') as output, stderr.open('wb') as error:
            process = subprocess.run(commands[phase], cwd=engine, env=environment,
                                     stdout=output, stderr=error)
        after = collect_source_inputs(repo)
        runtime_after = collect_runtime_inputs(repo, runtime)
        write_gzip_json(out / (phase + '-source-after.json.gz'), after)
        write_gzip_json(out / (phase + '-runtime-after.json.gz'), runtime_after)
        unchanged_head = git(repo, 'rev-parse', 'HEAD').decode().strip() == head
        check = dict(name=phase, command=commands[phase], cwd=str(engine),
                     started_utc=started, finished_utc=utc_now(), seconds=round(time.monotonic() - tick, 3),
                     exit_code=process.returncode, source_entries=len(before),
                     source_unchanged=before == after, source_matches_head=head_binding['matches'],
                     runtime_entries=len(runtime_before), runtime_unchanged=runtime_before == runtime_after,
                     head_unchanged=unchanged_head, stdout=stdout.name, stderr=stderr.name,
                     stdout_sha256=file_signature(stdout)['sha256'], stderr_sha256=file_signature(stderr)['sha256'])
        accepted = process.returncode == 0 and before == after and runtime_before == runtime_after and unchanged_head
        if phase == 'regression':
            result = parse_events(stdout, engine, [entry['path'] for entry in selection['files']])
            cases = result.pop('cases')
            write_gzip_json(out / 'cases.json.gz', cases)
            comparison = compare_previous(repo, selection, cases, before)
            write_json(out / 'previous-case-comparison.json', comparison)
            check['tests'] = result
            check['previous_case_comparison'] = {key: value for key, value in comparison.items() if key != 'files'}
            accepted = accepted and result['accepted'] and comparison['accepted']
        elif phase == 'analysis':
            check['no_issues_reported'] = 'No issues found!' in stdout.read_text()
            accepted = accepted and check['no_issues_reported']
        else:
            check['changed_dart_files'] = format_paths
            accepted = accepted and bool(format_paths)
        check['status'] = 'PASS' if accepted else 'FAIL'
        receipt['checks'].append(check)
        receipt['status'] = 'RUNNING' if accepted else 'FAIL'
        write_json(out / 'receipt.json', receipt)
        print(json.dumps(dict(phase=phase, status=check['status'], seconds=check['seconds'],
                              passing_cases=check.get('tests', {}).get('passing_cases'))), flush=True)
        if not accepted:
            break
    receipt['finished_utc'] = utc_now()
    receipt['status'] = 'PASS' if len(receipt['checks']) == len(args.phase) and all(
        item['status'] == 'PASS' for item in receipt['checks']) else 'FAIL'
    receipt['evidence'] = {path.name: dict(bytes=path.stat().st_size, sha256=file_signature(path)['sha256'])
                           for path in sorted(out.iterdir()) if path.is_file() and path.name != 'receipt.json'}
    write_json(out / 'receipt.json', receipt)
    print(json.dumps(dict(status=receipt['status'], receipt=str(out / 'receipt.json'))), flush=True)
    return 0 if receipt['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
