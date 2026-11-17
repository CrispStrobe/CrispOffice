#!/usr/bin/env python3
"""Independently audit saved local qualification receipts; never contact CI.

Recounts runner events and verifies recorded bytes, input maps, selected suites,
and source attribution. It does not replace consumer semantic oracles or runtime
execution. Run only after all selected producers have completed.
"""
from __future__ import annotations

import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
from urllib.parse import unquote, urlparse

PRIVATE_CASES = {
    'TrueType subsets without cmap get ToUnicode cmap for the host',
    'JPEG with DCT SMask attaches softMaskJpeg for the host',
}
LOCK = '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
NATIVE = {
    'GECTOR_TEST_LIBRARY': '9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604',
    'GECTOR_TEST_MODEL': '549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b',
}


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def checked_path(root, name):
    relative = PurePosixPath(name)
    require(not relative.is_absolute() and '..' not in relative.parts,
            f'Unsafe output/member path: {name}')
    path = root / name
    require(path.is_file(), f'Missing output: {path}')
    return path


def source_identity(repo, commit, recorded):
    entries = {}
    for row in subprocess.check_output(
            ['git', '-C', str(repo), 'ls-tree', '-r', '-z', commit]).split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        mode, kind, blob = meta.decode().split()
        path = name.decode()
        if kind == 'blob' and not path.startswith('docs/'):
            entries[path] = (mode, blob)
    actual = recorded['files']
    require(set(actual) == set(entries), 'Source inventory differs from commit')
    require(not recorded['commit_mismatches'], 'Runner recorded source mismatch')
    require(not recorded['untracked_non_evidence_paths'], 'Untracked product input')
    for name, (mode, blob) in entries.items():
        require(actual[name]['git_blob'] == blob and actual[name]['git_mode'] == mode,
                f'Recorded input is not from frozen commit: {name}')
    return len(entries)


def events(raw, selected, cwd, private_pdf_absent=False):
    rows = []
    for line in raw.decode(errors='replace').splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict):
            rows.append(value)
    require(not any(e.get('type') == 'error' for e in rows), 'Runner error event')
    done = [e for e in rows if e.get('type') == 'done']
    require(len(done) == 1 and done[0].get('success') is True,
            'Missing or unsuccessful terminal runner event')
    suites = {e['suite']['id']: e['suite'] for e in rows if e.get('type') == 'suite'}
    starts = {e['test']['id']: e['test'] for e in rows if e.get('type') == 'testStart'}
    actual_paths = set()
    for suite in suites.values():
        name = suite['path']
        path = Path(unquote(urlparse(name).path) if name.startswith('file:') else name)
        actual_paths.add((path if path.is_absolute() else cwd / path).resolve())
    require(actual_paths == {(cwd / name).resolve() for name in selected},
            'Runner suite set differs from selection')
    outcomes = Counter()
    exclusions = []
    seen = set()
    for row in rows:
        if row.get('type') != 'testDone' or row.get('hidden'):
            continue
        identifier = row['testID']
        require(identifier not in seen and identifier in starts,
                'Duplicate or unstarted visible test completion')
        seen.add(identifier)
        outcome = 'skipped' if row.get('skipped') else row.get('result')
        outcomes[outcome] += 1
        test = starts[identifier]
        path = suites[test['suiteID']]['path']
        if private_pdf_absent and path.endswith('/pdf_file_test.dart'):
            for name in PRIVATE_CASES:
                if test['name'] == name or test['name'].endswith(' ' + name):
                    exclusions.append(name)
    require(outcomes and set(outcomes) == {'success'},
            f'Nonpassing or empty visible test outcomes: {dict(outcomes)}')
    expected = PRIVATE_CASES if private_pdf_absent and 'test/pdf_file_test.dart' in selected else set()
    require(len(exclusions) == len(expected) and set(exclusions) == expected,
            'Private fixture exclusions differ from exactly named cases')
    return {'suites': len(actual_paths), 'raw_passes': outcomes['success'],
            'substantive_passes': outcomes['success'] - len(exclusions),
            'excluded_private_cases': sorted(exclusions), 'skips': 0, 'errors': 0}


def full(root, repo, commit, tree):
    receipt = read_json(root / 'receipt.json')
    plan = read_json(root / 'plan.json')
    require(receipt['source_commit'] == commit and receipt['source_tree'] == tree,
            'Broad receipt source identity differs')
    require(receipt['all_passed'] is True and receipt['status'] == 'passed',
            'Broad qualification did not pass')
    require(receipt['working_head_after'] == commit and receipt['analysis_config_restored'],
            'Broad HEAD/config restoration failed')
    require(receipt['source_matches_frozen_commit'], 'Broad source mismatch')
    require(receipt['enforced_workspace_lock_sha256'] == LOCK, 'Different dependency lock')
    for name in ('source', 'dependencies', 'runtime', 'workspace', 'system', 'harness'):
        before = read_json(root / f'{name}-before.json')
        after = read_json(root / f'{name}-after.json')
        require(before == after and receipt['input_integrity'][name + '_unchanged'],
                f'Broad {name} changed')
        if name == 'source':
            source_identity(repo, commit, before)
    fixture = read_json(root / 'fixture-audit.json')
    native = {v['environment_variable']: v['sha256']
              for v in fixture['required_native_fixtures'].values()}
    require(native == NATIVE and fixture['native_skip_allowed'] is False,
            'Native fixture pins or no-skip policy differ')
    require(all(row['present'] for row in fixture['required_font_inputs'].values()),
            'A required public font fixture is missing')
    selected = [(group['kind'], name) for group in plan['cohorts'].values()
                for name in group['tests']]
    require(len(selected) == len(set(selected)) == plan['unique_test_files'],
            'Broad suite plan is duplicated or inconsistent')
    expected_commands = [name + '-strict-analysis' for name in plan['analysis_targets']]
    expected_commands += ['format', 'python-controls', *plan['cohorts']]
    commands = receipt['commands']
    require({r['name'] for r in commands} == set(expected_commands)
            and len(commands) == len(expected_commands), 'Broad command inventory differs')
    counted = {}
    for command in commands:
        require(command['exit_code'] == 0 and command['status'] == 'passed'
                and not command['timed_out'], f'Failed command {command["name"]}')
        for stream in ('stdout', 'stderr'):
            packed = checked_path(root, command[stream]).read_bytes()
            raw = gzip.decompress(packed)
            require(digest(packed) == command[stream + '_gzip_sha256']
                    and digest(raw) == command[stream + '_sha256'],
                    f'Log hash mismatch: {command["name"]}/{stream}')
            if stream == 'stdout' and command['name'] in plan['cohorts']:
                summary = events(raw, plan['cohorts'][command['name']]['tests'],
                                 Path(command['cwd']), not fixture['private_pdf_present'])
                require(summary['raw_passes'] == command['test_summary']['raw_success_count']
                        and summary['substantive_passes'] == command['test_summary']['substantive_success_count'],
                        f'Recount disagrees: {command["name"]}')
                counted[command['name']] = summary
    python = read_json(root / 'python-controls-summary.json')
    require(python['passed'] is True and not python.get('skipped_cases'),
            'Python controls failed or skipped')
    require(sum(v['raw_passes'] for v in counted.values()) == receipt['raw_runner_success_total']
            and sum(v['substantive_passes'] for v in counted.values()) == receipt['substantive_success_total'],
            'Broad summed count disagrees')
    return {'receipt_sha256': digest((root / 'receipt.json').read_bytes()),
            'unique_test_files': len(selected), 'cohorts': counted,
            'python_tests': python.get('tests_run')}


def portable(root, repo, commit, tree):
    receipt = read_json(root / 'receipt.json')
    require(receipt['source_commit'] == commit and receipt['source_tree'] == tree,
            'Portable source identity differs')
    require(receipt['passed'] is True and receipt['exit_code'] == 0
            and receipt['head_unchanged'] is True, 'Portable run failed')
    before, after = (read_json(root / f'inputs-{name}.json.gz') for name in ('before', 'after'))
    require(before == after and all(receipt['input_integrity'].values()),
            'Portable inputs changed')
    source_identity(repo, commit, before['source'])
    for stream in ('stdout', 'stderr'):
        packed = (root / (stream + '.gz')).read_bytes()
        raw = gzip.decompress(packed)
        row = receipt['outputs'][stream]
        require(digest(packed) == row['compressed_sha256'] and digest(raw) == row['sha256']
                and len(raw) == row['bytes'], f'Portable {stream} hash mismatch')
        if stream == 'stdout':
            summary = events(raw, receipt['selected_files'], Path(receipt['cwd']))
    require(summary['raw_passes'] == receipt['test_summary']['raw_success_count'],
            'Portable recount disagrees')
    return {'receipt_sha256': digest((root / 'receipt.json').read_bytes()), **summary}


def output_hashes(root, recorded):
    for name, expected in recorded.items():
        require(digest(checked_path(root, name).read_bytes()) == expected,
                f'Consumer output hash mismatch: {name}')
    return len(recorded)


def retained(root, commit, tree):
    receipt = read_json(root / 'receipt.json')
    require(receipt['source_head'] == commit and receipt['source_tree'] == tree,
            'Retained consumer source identity differs')
    require(receipt['passed'] is True and all(receipt[name + '_unchanged']
            for name in ('source', 'runtime', 'fixtures', 'head')),
            'Retained consumer failed or inputs changed')
    require(read_json(root / 'inputs.json.gz') == read_json(root / 'inputs-after.json.gz'),
            'Retained consumer input maps differ')
    require(digest((root / 'inputs.json.gz').read_bytes()) == receipt['inputs_sha256'],
            'Retained input map digest mismatch')
    require(all(c['exit_code'] == 0 for c in receipt['commands']),
            'Retained consumer command failed')
    names = [f['name'] for f in receipt['fixtures']]
    require(len(names) == len(set(names)) and all(f['passed'] for f in receipt['fixtures']),
            'Repeated or failing retained fixture')
    parts = 0
    for fixture in receipt['fixtures']:
        schema = fixture['schema']
        checked = schema.get('jing_passed_parts', schema.get('passed_parts', []))
        require(set(checked) == {'content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml'}
                and not schema.get('jing_failures', schema.get('failures')),
                f'Retained schema checks incomplete: {fixture["name"]}')
        parts += len(checked)
    require(receipt['summary']['fixtures'] == len(names)
            and receipt['summary']['passed'] == len(names)
            and receipt['summary']['failed'] == 0
            and receipt['summary']['schema_parts_passed'] == parts,
            'Retained counts inconsistent')
    return {'receipt_sha256': digest((root / 'receipt.json').read_bytes()),
            'fixture_names': names, 'schema_parts': parts,
            'hashed_outputs': output_hashes(root, receipt['output_hashes'])}


def boundary(root, commit):
    receipt = read_json(root / 'receipt.json')
    require(receipt['source_commit'] == commit and receipt['passed'] is True
            and receipt['inputs_unchanged'] is True, 'Boundary run failed or source differs')
    require(read_json(root / 'inputs-before.json') == read_json(root / 'inputs-after.json'),
            'Boundary input maps differ')
    require(all(c['exit_code'] == 0 for c in receipt['commands']), 'Boundary command failed')
    require(len(receipt['fixtures']) == 5, 'Boundary fixture count differs')
    variants = parts = 0
    for fixture in receipt['fixtures']:
        require(set(fixture['variants']) == {'direct', 'imported', 'source'},
                f'Incomplete boundary variants: {fixture["name"]}')
        for name, row in fixture['variants'].items():
            variants += 1
            if name != 'source':
                require(set(row['odt']['schema_accepted_parts']) ==
                        {'content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml'},
                        'Incomplete boundary ODF checks')
                parts += 4
    return {'receipt_sha256': digest((root / 'receipt.json').read_bytes()),
            'fixtures': 5, 'pdf_variants': variants, 'schema_parts': parts,
            'scope': 'Four strict repaired layouts plus one bounded precedence control.',
            'hashed_outputs': output_hashes(root, receipt['output_sha256']),
            'limitation': 'Harness alone does not recheck HEAD or match source bytes to the commit. Broad frozen-source audit and external freeze evidence are required.'}


def archive(index_path):
    index = read_json(index_path)
    path = checked_path(index_path.parent, index['archive'])
    require(path.stat().st_size == index['bytes'] and digest(path.read_bytes()) == index['sha256'],
            'Archive digest or size differs')
    rows = index['members']
    require(len(rows) == index['member_count'], 'Archive member count differs')
    with tarfile.open(path) as source:
        require(source.getnames() == [row['path'] for row in rows], 'Archive inventory differs')
        for row in rows:
            member = source.getmember(row['path'])
            require(member.isfile() and not member.issym(), 'Archive member is not a regular file')
            data = source.extractfile(member).read()
            require(len(data) == row['bytes'] and digest(data) == row['sha256'],
                    f'Archive member mismatch: {row["path"]}')
    return {'archive': path.name, 'sha256': index['sha256'], 'members': len(rows)}


def guard(root, repo, commit):
    receipt = read_json(root / 'receipt.json')
    require(receipt['kind'] == 'external-frozen-source-run-guard'
            and receipt['source_commit'] == commit and receipt['passed'] is True,
            'External source/run guard failed or identifies different source')
    for name in ('source_checkout_clean_before', 'source_checkout_clean_after',
                 'source_bytes_match_frozen_commit_before_and_after',
                 'runtime_and_workspace_unchanged'):
        require(receipt[name] is True, 'External guard failed: ' + name)
    require(receipt['child_exit_code'] == 0, 'External guarded command failed')
    before, after = (read_json(root / f'inputs-{name}.json.gz') for name in ('before', 'after'))
    require(before == after, 'External guard input maps differ')
    expected = {}
    for record in subprocess.check_output(
            ['git', '-C', str(repo), 'ls-tree', '-r', '-z', commit]).split(b'\0'):
        if record:
            meta, name = record.split(b'\t', 1)
            mode, kind, blob = meta.decode().split()
            if kind == 'blob':
                expected[name.decode()] = (mode, blob)
    for path, record in before['source'].items():
        require(expected.get(path) == (record['mode'], record['git_blob']),
                'External guard source identity differs: ' + path)
    core = {name for name in expected if name.startswith((
        'packages/quds_office_engine/lib/', 'packages/legacy_doc_parser/lib/',
        'packages/quds_proofing_gector/lib/'))}
    require(core <= before['source'].keys(), 'External guard omits core source inputs')
    require(len(before['source']) == receipt['source_file_count']
            and len(before['runtime']) == receipt['runtime_and_workspace_file_count'],
            'External guard inventory counts disagree')
    return {'receipt_sha256': digest((root / 'receipt.json').read_bytes()),
            'command': receipt['command'], 'source_files': len(before['source']),
            'runtime_and_workspace_files': len(before['runtime']),
            'hashed_outputs': output_hashes(root, receipt['output_hashes'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--commit', required=True)
    for name in ('full', 'portable', 'boundary', 'output'):
        parser.add_argument('--' + name, type=Path)
    for name in ('retained', 'archive-index', 'guard'):
        parser.add_argument('--' + name, type=Path, action='append', default=[])
    args = parser.parse_args()
    tree = subprocess.check_output(['git', '-C', str(args.repo), 'rev-parse',
                                    args.commit + '^{tree}'], text=True).strip()
    result = {'source_commit': args.commit, 'source_tree': tree, 'audits': {},
              'scope': 'Independent receipt/event/byte audit; consumer semantic oracles are not rerun.',
              'github_actions_queried_or_awaited': False}
    try:
        if args.full:
            result['audits']['full'] = full(args.full, args.repo, args.commit, tree)
        if args.portable:
            result['audits']['portable'] = portable(args.portable, args.repo, args.commit, tree)
        if args.retained:
            result['audits']['retained'] = [retained(p, args.commit, tree) for p in args.retained]
            names = [name for r in result['audits']['retained'] for name in r['fixture_names']]
            require(len(names) == len(set(names)), 'Retained cohorts overlap')
        if args.boundary:
            result['audits']['boundary'] = boundary(args.boundary, args.commit)
        if args.archive_index:
            result['audits']['archives'] = [archive(p) for p in args.archive_index]
        if args.guard:
            result['audits']['external_guards'] = [guard(p, args.repo, args.commit)
                                                  for p in args.guard]
        require(bool(result['audits']), 'No receipts selected')
        result['all_requested_audits_passed'] = True
    except Exception as error:
        result['all_requested_audits_passed'] = False
        result['error'] = f'{type(error).__name__}: {error}'
    result['all_qualification_gate_kinds_present'] = all(
        name in result['audits'] for name in ('full', 'portable', 'retained', 'boundary'))
    rendered = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered)
    return 0 if result['all_requested_audits_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
