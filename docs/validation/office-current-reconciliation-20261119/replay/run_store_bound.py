"""Run the existing Store gate with additional full native input snapshots."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'runtime', 'native', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--head', required=True)
    args = parser.parse_args()
    repo, runtime, native, output = [getattr(args, key).resolve() for key in ('repo', 'runtime', 'native', 'output')]
    output.mkdir(parents=True, exist_ok=False)

    def sha(path):
        if not path.is_file():
            return None
        with path.open('rb') as stream:
            return hashlib.file_digest(stream, 'sha256').hexdigest()

    def write(name, data):
        (output / name).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')

    def git(*argv):
        return subprocess.check_output(['git', '-C', str(repo), *argv], text=True).strip()

    source_template = json.loads((native / 'source-before.json').read_text())
    env_template = json.loads((native / 'environment-before.json').read_text())

    def source():
        return {name: sha(repo / name) for name in sorted(source_template)}

    def environment():
        paths = {}
        for name in env_template:
            if name.startswith('runtime/'):
                paths[name] = runtime / name.removeprefix('runtime/')
            elif name.startswith('additional/'):
                paths[name] = Path(name.removeprefix('additional/'))
            elif name == 'workspace/package_config.json':
                paths[name] = repo / '.dart_tool/package_config.json'
            elif name == 'workspace/native_assets.yaml':
                paths[name] = repo / '.dart_tool/native_assets.yaml'
            elif name == 'sdk/flutter_tools/package_config.json':
                paths[name] = runtime / 'flutter/packages/flutter_tools/.dart_tool/package_config.json'
            elif name.startswith('workspace/'):
                paths[name] = repo / name.removeprefix('workspace/')
            else:
                raise ValueError('Unknown input mapping: ' + name)
        return {name: sha(path) for name, path in sorted(paths.items())}

    if git('rev-parse', 'HEAD') != args.head or git('status', '--porcelain=v1', '--untracked-files=no'):
        raise RuntimeError('Expected clean frozen source')
    before_source, before_env = source(), environment()
    if before_source != {name: item['sha256'] for name, item in source_template.items()} or before_env != env_template:
        raise RuntimeError('Inputs differ from the preceding native gate')
    write('source-before.json', before_source)
    write('environment-before.json', before_env)
    command = [sys.executable, 'tools/mail/check_store.py', '--flutter-sdk', str(runtime / 'flutter'), '--offline', '--direct-tests', '--command-timeout', '300', '--output', str(output / 'gate')]
    receipt = {'source_commit': args.head, 'source_tree': git('rev-parse', 'HEAD^{tree}'), 'driver_sha256': sha(Path(__file__)), 'started_at_utc': datetime.now(timezone.utc).isoformat(), 'command': command, 'source_input_count': len(before_source), 'runtime_input_count': len(before_env), 'github_actions_queried_or_awaited': False}
    write('driver-receipt.json', receipt)
    env = dict(os.environ)
    env.update(PUB_CACHE=str(runtime / 'pub-cache'), FLUTTER_ROOT=str(runtime / 'flutter'), CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true', DASH__SUPPRESS_ANALYTICS='true', XDG_CONFIG_HOME=str(runtime / 'config'), XDG_CACHE_HOME=str(runtime / 'cache'), XDG_DATA_HOME=str(runtime / 'data'), TMPDIR=str(runtime / 'tmp'), PATH=str(runtime / 'bin') + os.pathsep + env.get('PATH', ''))
    sys.path.insert(0, str(repo / 'tools/mail'))
    from check_store import execute
    exit_code = 127
    try:
        with (output / 'store.log').open('wb') as log:
            exit_code = execute(command, cwd=repo, env=env, stdout=log, timeout=1800)
    except (OSError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        exit_code = 124 if isinstance(error, subprocess.TimeoutExpired) else 130 if isinstance(error, KeyboardInterrupt) else 127
        receipt['error'] = repr(error)
    finally:
        after_source, after_env = source(), environment()
        write('source-after.json', after_source)
        write('environment-after.json', after_env)
        receipt.update(exit_code=exit_code, finished_at_utc=datetime.now(timezone.utc).isoformat(), source_unchanged=before_source == after_source, runtime_unchanged=before_env == after_env, log_sha256=sha(output / 'store.log'), head_unchanged=git('rev-parse', 'HEAD') == args.head, tracked_worktree_clean=not git('status', '--porcelain=v1', '--untracked-files=no'))
        receipt['accepted'] = exit_code == 0 and all(receipt[key] for key in ('source_unchanged', 'runtime_unchanged', 'head_unchanged', 'tracked_worktree_clean'))
        write('driver-receipt.json', receipt)
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['accepted'] else 1


if __name__ == '__main__':
    sys.exit(main())
