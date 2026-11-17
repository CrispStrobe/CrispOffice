#!/usr/bin/env python3
"""Wrap an unchanged runner with exact Git-source and runtime stability checks.

This is an external evidence wrapper. It changes no test, oracle, package,
source, SDK, fixture, or child command. Output must be outside the source tree.
"""
import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def write_map(path, value):
    with gzip.GzipFile(filename=str(path), mode='wb', mtime=0) as stream:
        stream.write((json.dumps(value, indent=2) + '\n').encode())


def exact_source(repo, commit):
    assert git(repo, 'rev-parse', 'HEAD').decode().strip() == commit, 'Frozen HEAD changed'
    status = git(repo, 'status', '--porcelain', '--untracked-files=all').decode()
    assert not status, 'Source checkout must be clean: ' + status
    roots = ['packages', 'tools', 'pubspec.yaml',
             'docs/validation/office-reconciled-20261117/resume/consumer-new',
             'docs/validation/german-gector/2026-11-17-followup/native-threads']
    records = git(repo, 'ls-tree', '-rz', commit, '--', *roots).split(b'\0')
    result = {}
    for record in records:
        if not record:
            continue
        meta, raw_name = record.split(b'\t', 1)
        mode, kind, expected = meta.decode().split()
        name = raw_name.decode()
        if kind != 'blob':
            continue
        # Package-local documentation does not contribute to execution.
        if name.startswith('packages/'):
            parts = Path(name).parts
            if len(parts) > 3 and parts[2] not in ('lib', 'test', 'fonts', 'example'):
                continue
        path = repo / name
        data = os.readlink(path).encode() if mode == '120000' else path.read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        assert actual == expected, 'Tracked source bytes differ from commit: ' + name
        result[name] = {'git_blob': expected, 'sha256': hashlib.sha256(data).hexdigest(),
                        'bytes': len(data), 'mode': mode}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'workspace', 'dart', 'consumer-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--extra-input', type=Path, action='append', default=[])
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    repo, workspace, dart, consumer, output = [p.resolve() for p in
        (args.repo, args.workspace, args.dart, args.consumer_root, args.output)]
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    assert command and not output.exists() and not output.is_relative_to(repo)
    output.mkdir(parents=True)
    receipt = {'kind': 'external-frozen-source-run-guard', 'source_commit': args.commit,
               'command': command, 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'passed': False, 'child_exit_code': None,
               'source_checkout_clean_before': False, 'source_checkout_clean_after': False}
    sys.path.insert(0, str(consumer / 'wave3-runner'))
    import verify_consumers as base
    try:
        source_before = exact_source(repo, args.commit)
        receipt['source_checkout_clean_before'] = True
        for package in ('quds_office_engine', 'legacy_doc_parser', 'quds_proofing_gector'):
            assert (workspace / 'packages' / package / 'lib').resolve() == \
                   (repo / 'packages' / package / 'lib').resolve(), package
        base.configured_packages(workspace)
        import fitz
        import pymupdf
        java = Path(shutil.which('java'))
        extra = [workspace / 'pubspec.yaml', workspace / 'pubspec.lock',
                 workspace / '.dart_tool/package_config.json',
                 consumer / 'tools/jing-20241231.jar', Path(__file__).resolve(),
                 java, java.resolve(), *[p.resolve(strict=True) for p in args.extra_input]]
        def runtime_files():
            modules = base.all_files(Path(fitz.__file__).parent) + base.all_files(Path(pymupdf.__file__).parent)
            return sorted(set(base.runtime_inputs(dart, consumer / 'schemas', workspace) +
                              extra + [p for p in modules if '__pycache__' not in p.parts]))
        runtime_paths = runtime_files()
        runtime_before = base.snapshot(runtime_paths)
        write_map(output / 'inputs-before.json.gz', {'source': source_before, 'runtime': runtime_before})
        write_json(output / 'receipt.json', receipt)
        start = time.monotonic()
        with (output / 'child.stdout.log').open('wb') as stdout, \
             (output / 'child.stderr.log').open('wb') as stderr:
            completed = subprocess.run(command, cwd=repo, stdout=stdout, stderr=stderr, check=False)
        receipt['duration_seconds'] = time.monotonic() - start
        receipt['child_exit_code'] = completed.returncode
        source_after = exact_source(repo, args.commit)
        receipt['source_checkout_clean_after'] = True
        runtime_after = base.snapshot(runtime_files())
        write_map(output / 'inputs-after.json.gz', {'source': source_after, 'runtime': runtime_after})
        receipt['source_bytes_match_frozen_commit_before_and_after'] = source_before == source_after
        receipt['runtime_and_workspace_unchanged'] = runtime_before == runtime_after
        receipt['source_file_count'] = len(source_before)
        receipt['runtime_and_workspace_file_count'] = len(runtime_before)
        receipt['passed'] = completed.returncode == 0 and source_before == source_after and runtime_before == runtime_after
    except Exception as error:
        receipt['error'] = repr(error)
    finally:
        receipt['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        receipt['output_hashes'] = {p.name: digest(p) for p in sorted(output.iterdir())
                                    if p.is_file() and p.name != 'receipt.json'}
        write_json(output / 'receipt.json', receipt)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
