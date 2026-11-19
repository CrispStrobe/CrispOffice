#!/usr/bin/env python3
"""Replay the AyaSpell output-directory guard checks without network access.

These isolated helper checks are excluded from the 836 application executions
and 78 Python qualification controls. Only the real helper's directory creation
and argument-error behavior execute; fetch and publication are replaced by stubs.
"""
import argparse
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import types
from unittest import mock


class FetchReached(Exception):
    """Stop a fresh-directory run at its first would-be download."""


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def snapshot(root):
    result = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            result[relative] = ['symlink', str(path.readlink())]
        elif path.is_dir():
            result[relative] = ['directory']
        else:
            result[relative] = ['file', sha256(path.read_bytes())]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    helper_path = repo / 'tools/proofing/ayaspell/build_bundle.py'
    helper_bytes = helper_path.read_bytes()
    helper_code = compile(helper_bytes, str(helper_path), 'exec')
    checks = []
    issues = []
    cases = ['existing_nonempty_directory', 'existing_empty_directory',
             'existing_file', 'existing_dangling_symlink',
             'existing_directory_symlink', 'racing_directory', 'fresh_directory']
    sentinel = b'Synthetic local sentinel: never publish this file.\n'

    with tempfile.TemporaryDirectory(prefix='proofing-output-guard-', dir=repo.parent) as temp:
        for name in cases:
            root = Path(temp) / name
            root.mkdir()
            output = root / 'output'
            if name == 'existing_nonempty_directory':
                output.mkdir()
                (output / 'sentinel.txt').write_bytes(sentinel)
            elif name == 'existing_empty_directory':
                output.mkdir()
            elif name == 'existing_file':
                output.write_bytes(sentinel)
            elif name == 'existing_dangling_symlink':
                output.symlink_to('missing-target')
            elif name == 'existing_directory_symlink':
                (root / 'target').mkdir()
                (root / 'target' / 'sentinel.txt').write_bytes(sentinel)
                output.symlink_to('target', target_is_directory=True)

            expected = snapshot(root)
            module = types.ModuleType('proofing_bundle_under_check')
            module.__file__ = str(helper_path)
            exec(helper_code, module.__dict__)
            fetch_calls = []
            publish_calls = []
            mkdir_flags = []
            race_injected = False
            real_mkdir = Path.mkdir

            def stub_fetch(url):
                fetch_calls.append(url)
                raise FetchReached()

            def forbid_publication(*unused_args, **unused_kwargs):
                publish_calls.append('HfApi')
                raise AssertionError('Publication must not be reached')

            def observed_mkdir(path, *positional, **keywords):
                nonlocal expected, race_injected
                if path == output:
                    mkdir_flags.append(keywords.get('exist_ok'))
                    if name == 'racing_directory' and not race_injected:
                        race_injected = True
                        real_mkdir(output, parents=True, exist_ok=False)
                        (output / 'sentinel.txt').write_bytes(sentinel)
                        expected = snapshot(root)
                return real_mkdir(path, *positional, **keywords)

            hf_stub = types.ModuleType('huggingface_hub')
            hf_stub.HfApi = forbid_publication
            stderr, stdout = io.StringIO(), io.StringIO()
            exit_code = None
            outcome = 'returned'
            argv = ['build_bundle.py', '--output', str(output),
                    '--publish', 'example/never-publish']
            with (mock.patch.object(sys, 'argv', argv),
                  mock.patch.object(module, 'fetch', stub_fetch),
                  mock.patch.dict(sys.modules, {'huggingface_hub': hf_stub}),
                  mock.patch('urllib.request.urlopen', side_effect=AssertionError('Network forbidden')) as network,
                  mock.patch.object(Path, 'mkdir', observed_mkdir),
                  redirect_stderr(stderr), redirect_stdout(stdout)):
                try:
                    module.main()
                except SystemExit as error:
                    exit_code = error.code
                    outcome = 'argument_error'
                except FetchReached:
                    outcome = 'stubbed_fetch'
                except Exception as error:
                    outcome = type(error).__name__

            errors = []
            if publish_calls or network.call_count:
                errors.append('Unexpected publication or network attempt')
            if mkdir_flags != [False]:
                errors.append('Output creation did not use exist_ok=False exactly once')
            if name == 'fresh_directory':
                if (outcome != 'stubbed_fetch' or len(fetch_calls) != 1
                        or not output.is_dir() or list(output.iterdir())):
                    errors.append('Fresh output did not create an empty directory before stubbed fetch')
            else:
                if outcome != 'argument_error' or exit_code != 2 or fetch_calls:
                    errors.append('Existing output was not rejected before fetch/publication')
                if 'choose a new directory for --output' not in stderr.getvalue():
                    errors.append('Missing actionable argument error')
                if snapshot(root) != expected:
                    errors.append('Existing output or sentinel changed')
            if name == 'racing_directory' and not race_injected:
                errors.append('Concurrent directory creation was not exercised')
            check = {'name': name, 'passed': not errors, 'outcome': outcome,
                     'exit_code': exit_code, 'fetch_stub_calls': len(fetch_calls),
                     'publication_stub_calls': len(publish_calls),
                     'network_attempts': network.call_count, 'issues': errors}
            checks.append(check)
            issues.extend(name + ': ' + error for error in errors)

    result = {
        'schema': 'quds.proofing.output_guard_checks.v1',
        'passed': not issues, 'issues': issues,
        'helper_path': 'tools/proofing/ayaspell/build_bundle.py',
        'helper_sha256': sha256(helper_bytes),
        'check_script_sha256': sha256(Path(__file__).read_bytes()),
        'checks': checks,
        'network_or_publish_performed': False,
        'added_to_application_or_python_qualification_totals': 0,
        'validation_scope': 'Seven isolated helper checks; no bundle download, upload or product tests',
        'replay': 'python3 docs/validation/office-main-completion-20261119/release/'
                  'check_proofing_output_guard.py --repo "$QUDS_REPO" --output "$QUDS_RECEIPT"',
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'passed': result['passed'], 'checks': len(checks), 'issues': issues}, sort_keys=True))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
