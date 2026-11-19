#!/usr/bin/env python3
"""Recount completed offline controls and bind their exact source and interpreter."""
from __future__ import annotations
import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


def check(value: object, message: str) -> None:
    if not value:
        raise AssertionError(message)


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--historical-source', action='store_true')
    args = parser.parse_args()
    repo = args.repo.resolve()
    evidence = args.evidence.resolve()

    def git(*values: str) -> bytes:
        return subprocess.check_output(['git', '--no-lazy-fetch', '--no-replace-objects', '-C', str(repo), *values])

    source = git('rev-parse', '--verify', args.source + '^{commit}').decode().strip()
    source_tree = git('rev-parse', source + '^{tree}').decode().strip()
    receipt_raw = (evidence / 'verification.json').read_bytes()
    receipt = json.loads(receipt_raw)
    check(receipt.get('source_commit') == source and receipt.get('source_tree') == source_tree, 'exact source commit/tree')
    check(receipt.get('success') is True and receipt.get('finished_at_utc'), 'completed successful receipt required')
    check(not receipt.get('runner_error'), 'no runner error')
    check(receipt.get('github_actions_queried_or_awaited') is False, 'no Actions use')
    for key in ('source_unchanged', 'runtime_unchanged', 'source_head_unchanged', 'source_index_unchanged', 'tracked_worktree_clean_after'):
        check(receipt.get(key) is True, 'receipt invariant: ' + key)
    check(receipt['source_before'] == receipt['source_after'], 'source maps byte values identical')
    check(receipt['runtime_before'] == receipt['runtime_after'], 'interpreter maps identical')
    if not args.historical_source:
        check(git('rev-parse', 'HEAD').decode().strip() == source, 'live HEAD exact source')
        check(not git('status', '--porcelain=v1', '--untracked-files=no').strip(), 'tracked worktree clean')
    records = {}
    for entry in git('ls-tree', '-r', '-z', source).split(b'\0'):
        if not entry:
            continue
        metadata, path = entry.split(b'\t', 1)
        mode, kind, blob = metadata.decode().split()
        records[path.decode()] = {'mode': mode, 'kind': kind, 'blob': blob}
    source_names = {
        'docs/validation/office-resume-main-20261119/run_python_controls.py',
        'tools/mail/check_store.py', 'tools/mail/check_reader.py',
        'packages/quds_proofing_hunspell/tool/build.py',
        'packages/quds_proofing_hunspell/tool/test_build.py',
        'packages/quds_proofing_hunspell/LICENSE',
    }
    source_names.update(path for path in records if path.startswith('tools/proofing/ayaspell/') and path.endswith('.py'))
    source_names.update(path for path in records if path.startswith('packages/quds_proofing_hunspell/licenses/'))
    check(set(receipt['source_before']) == source_names, 'complete source closure exactly bound')
    inputs = []
    contents = {}
    for name in sorted(source_names):
        record = records[name]
        check(record['kind'] == 'blob' and record['mode'] in ('100644', '100755'), 'regular input: ' + name)
        raw = git('cat-file', 'blob', record['blob'])
        check(receipt['source_before'][name] == {'git_blob': record['blob'], 'sha256': sha(raw)}, 'source Git blob and digest: ' + name)
        if not args.historical_source:
            check((repo / name).read_bytes() == raw, 'live input identical: ' + name)
        contents[name] = raw
        inputs.append({'path': name, 'mode': record['mode'], 'git_blob': record['blob'], 'bytes': len(raw), 'sha256': sha(raw)})
    for directory in ('tools/proofing/ayaspell', 'packages/quds_proofing_hunspell/tool'):
        if not args.historical_source:
            discovered = {str(path.relative_to(repo)) for path in (repo / directory).glob('*.py')}
            check(discovered <= set(records), 'discovery inputs all tracked: ' + directory)
    runtime = receipt['runtime_before']
    python = Path(runtime['python_executable'])
    check(python.is_absolute() and python.resolve() == python and python.is_file(), 'interpreter canonical path')
    check(sha(python.read_bytes()) == runtime['sha256'], 'interpreter digest readback')
    check(bool(runtime['version']), 'interpreter version recorded')
    expected_groups = (
        ('bundle-controls', 'tools/proofing/ayaspell', 'test_build_bundle*.py'),
        ('packaging-controls', 'packages/quds_proofing_hunspell/tool', 'test_build.py'),
    )
    runs = receipt['runs']
    check(len(runs) == len(expected_groups), 'exactly two control groups')
    audited = []
    all_ids = set()
    for row, (name, directory, pattern) in zip(runs, expected_groups, strict=True):
        check(row['name'] == name and row['cwd'] == str(repo), 'group name and working directory')
        check(row['command'] == [str(python), '-B', '-m', 'unittest', 'discover', '-s', directory, '-p', pattern, '-v'], 'exact unittest command')
        check(row['exit_code'] == 0 and row['accepted'] is True, 'successful control process')
        log_path = Path(row['log'])
        check(not log_path.is_absolute() and '..' not in log_path.parts, 'relative evidence log')
        raw = (evidence / log_path).read_bytes()
        check(sha(raw) == row['log_sha256'], 'raw log digest')
        text = raw.decode()
        matches = re.findall(r'^(test\S+) \(([^\n)]+)\) \.\.\. ok$', text, re.MULTILINE)
        ids = [identity for _, identity in matches]
        check(all(identity.endswith('.' + method) for method, identity in matches), 'raw test method identity consistency')
        totals = re.findall(r'^Ran (\d+) tests? in [\d.]+s$', text, re.MULTILINE)
        check(len(totals) == 1 and int(totals[0]) == len(ids), 'independent terminal count')
        check(text.rstrip().endswith('\nOK'), 'terminal unittest OK')
        check(not re.search(r'^(?:FAIL|ERROR|FAILED|OK \()', text, re.MULTILINE), 'no failed/error/skip terminal')
        check(len(ids) == len(set(ids)) > 0, 'unique nonempty case identities')
        expected = set()
        files = sorted(path for path in contents if Path(path).parent.as_posix() == directory and Path(path).match(pattern))
        for path in files:
            syntax = ast.parse(contents[path].decode(), filename=path)
            for cls in syntax.body:
                if isinstance(cls, ast.ClassDef):
                    for method in cls.body:
                        if isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)) and method.name.startswith('test'):
                            expected.add(f'{Path(path).stem}.{cls.name}.{method.name}')
        check(set(ids) == expected, 'raw identities equal pinned source methods: ' + name)
        check(row['case_ids'] == ids and row['passed'] == len(ids), 'stored identities/count agree with raw')
        check(not (all_ids & set(ids)), 'no cross-group duplicate identities')
        all_ids.update(ids)
        audited.append({'name': name, 'test_files': files, 'case_ids': ids, 'passed': len(ids), 'raw_log': row['log'], 'raw_log_sha256': sha(raw), 'raw_log_bytes': len(raw), 'exit_code': 0, 'terminal_ok': True, 'exact_pinned_test_methods': True})
    check(receipt['passed'] == len(all_ids), 'combined count')
    result = {
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Independent audit of completed offline Python controls. No application tests rerun, network publication, real account sends, browser, installed-platform, or linguistic acceptance claimed.',
        'script_sha256': sha(Path(__file__).read_bytes()),
        'source_commit': source, 'source_tree': source_tree,
        'receipt_sha256': sha(receipt_raw), 'started_at_utc': receipt['started_at_utc'], 'finished_at_utc': receipt['finished_at_utc'],
        'historical_source_mode': args.historical_source,
        'source_binding': {'input_count': len(inputs), 'inputs': inputs, 'before_after_identical': True, 'pinned_git_blobs_verified': True, 'complete_control_input_closure': True},
        'interpreter_binding': {'before_after_identical': True, 'record': runtime, 'executable_sha256_readback_verified': True, 'stdlib_files_individually_bound': False},
        'groups': audited, 'group_count': len(audited), 'passed': len(all_ids), 'distinct_cases': len(all_ids), 'failures': 0, 'skips': 0, 'all_passed': True,
    }
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'source_commit': source, 'passed': len(all_ids), 'groups': {row['name']: row['passed'] for row in audited}, 'all_passed': True, 'output': str(args.output)}))


if __name__ == '__main__':
    main()
