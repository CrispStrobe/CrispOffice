#!/usr/bin/env python3
"""Run local Mail qualification without using hosted GitHub Actions."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid


def source_hashes(root: Path) -> dict[str, str]:
    selected = [root / relative for relative in (
        '.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
        'tools/mail/check_reader.py',
        'third_party/enough_mail/pubspec.yaml',
        'third_party/enough_mail/analysis_options.yaml',
        'third_party/enough_mail/LICENSE',
        'third_party/enough_mail/UPSTREAM.json',
        'third_party/enough_mail/DEPENDENCIES.json',
        'third_party/enough_mail/PORTABLE_CLOSURE.json',
        'third_party/enough_mail/QUDS_PATCHES.md',
    )]
    for relative in ('packages/quds_mail_core', 'packages/quds_mail_mime',
                     'packages/quds_mail_ui', 'third_party/enough_mail/lib'):
        for path in (root / relative).rglob('*'):
            if path.is_file() and not any(
                part in {'.dart_tool', 'build', '.git', 'ephemeral', '__pycache__'}
                for part in path.parts
            ):
                selected.append(path)
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(set(selected)) if path.exists()}


def write_receipt(path: Path, receipt: dict[str, object]) -> None:
    """Replace a checkpoint atomically; never expose a partly written receipt."""
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode='w', encoding='utf-8', dir=path.parent,
            prefix='.receipt-', suffix='.tmp', delete=False,
        ) as stream:
            temporary = Path(stream.name)
            json.dump(receipt, stream, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-sdk', required=True, type=Path)
    parser.add_argument('--output', type=Path,
                        default=Path('build/mail-qualification'))
    parser.add_argument('--chrome', type=Path,
                        help='Run actual Chrome tests using this executable.')
    parser.add_argument('--web-build', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt_path = output / 'receipt.json'
    results: list[dict[str, object]] = []
    before: dict[str, str] | None = None
    receipt: dict[str, object] = dict(
        status='RUNNING', run_id=uuid.uuid4().hex,
        started_utc=datetime.now(timezone.utc).isoformat(),
        checks=results, active_check=None,
        source_before=None, source_after=None, source_unchanged=None,
        browser_execution='requested' if args.chrome else 'NOT RUN',
        github_actions='NOT USED',
    )
    # Invalidate a previous PASS before SDK validation, hashing or commands.
    write_receipt(receipt_path, receipt)
    exit_code = 1

    def checkpoint() -> None:
        write_receipt(receipt_path, receipt)

    try:
        sdk = args.flutter_sdk.resolve()
        dart = sdk / 'bin/cache/dart-sdk/bin/dart'
        snapshot = sdk / 'bin/cache/flutter_tools.snapshot'
        node = shutil.which('node')
        if not dart.is_file() or not snapshot.is_file() or node is None:
            raise FileNotFoundError('A complete Flutter SDK and Node on PATH are required.')
        temp = output / 'tmp'
        temp.mkdir(exist_ok=True)
        env = dict(os.environ, FLUTTER_ROOT=str(sdk), TMPDIR=str(temp),
                   CI='true', DASH__SUPPRESS_ANALYTICS='true',
                   FLUTTER_SUPPRESS_ANALYTICS='true')
        env['PATH'] = str(dart.parent) + os.pathsep + env.get('PATH', '')
        if args.chrome:
            env['CHROME_EXECUTABLE'] = str(args.chrome.resolve())
        dart_cmd = [str(dart)]
        flutter_cmd = [str(dart), str(snapshot), '--no-version-check']
        before = source_hashes(root)
        receipt['source_before'] = before
        checkpoint()

        def run(name: str, command: list[str], cwd: Path = root) -> bool:
            print(name, flush=True)
            log = output / (name + '.txt')
            entry: dict[str, object] = dict(
                name=name, command=command, cwd=str(cwd),
                status='RUNNING', exit_code=None, log=log.name,
            )
            results.append(entry)
            receipt['active_check'] = name
            checkpoint()
            try:
                with log.open('wb') as stream:
                    result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                            stderr=subprocess.STDOUT, check=False)
                entry['exit_code'] = result.returncode
                entry['status'] = 'PASS' if result.returncode == 0 else 'FAIL'
                return result.returncode == 0
            except KeyboardInterrupt:
                entry['status'] = 'INTERRUPTED'
                raise
            except OSError as error:
                entry['status'] = 'ERROR'
                entry['error'] = f'{type(error).__name__}: {error}'
                raise
            finally:
                if log.exists():
                    entry['log_sha256'] = hashlib.sha256(log.read_bytes()).hexdigest()
                receipt['active_check'] = None
                checkpoint()

        # Resolve with the caller's existing lock. Unavailable dependencies are
        # failures, never a reason to substitute another source tree.
        ok = run('resolution', dart_cmd + ['pub', 'get', '--enforce-lockfile'])
        if ok:
            for package in ('quds_mail_core', 'quds_mail_mime'):
                directory = root / 'packages' / package
                ok &= run(package + '-analysis', dart_cmd + ['analyze', '--fatal-infos'], directory)
                ok &= run(package + '-native-js', dart_cmd +
                          ['test', '--platform', 'vm,node', '--reporter', 'expanded'], directory)
                if args.chrome:
                    ok &= run(package + '-chrome', dart_cmd +
                              ['test', '--platform', 'chrome', '--reporter', 'expanded'], directory)
            ui = root / 'packages/quds_mail_ui'
            ok &= run('ui-analysis', dart_cmd + ['analyze', '--fatal-infos'], ui)
            ok &= run('ui-native', flutter_cmd + ['test', '--no-pub', '--reporter', 'expanded'], ui)
            if args.chrome:
                ok &= run('ui-chrome', flutter_cmd +
                          ['test', '--no-pub', '--platform', 'chrome', '--reporter', 'expanded'], ui)
            if args.web_build:
                ok &= run('reader-web-build', flutter_cmd +
                          ['build', 'web', '--no-pub', '--no-web-resources-cdn'],
                          ui / 'example')
            script = root / 'packages/quds_mail_mime/test/compile/portable_import.dart'
            js = output / 'portable.js'
            compiled = run('mime-js-compile', dart_cmd +
                           ['compile', 'js', str(script), '-o', str(js)])
            ok &= compiled
            native_ok = run('mime-vm-projection', dart_cmd + [str(script)])
            if compiled:
                js_ok = run('mime-js-projection', [node, str(js)])
            else:
                # A failed compile must never execute output left by an old run.
                js_ok = False
                results.append(dict(name='mime-js-projection', status='SKIPPED',
                                    reason='The current JavaScript compilation failed.'))
                checkpoint()
            projection_equal = native_ok and js_ok and (
                (output / 'mime-vm-projection.txt').read_bytes() ==
                (output / 'mime-js-projection.txt').read_bytes())
            results.append(dict(name='native-js-equivalence',
                                status='PASS' if projection_equal else 'FAIL',
                                pass_result=projection_equal))
            checkpoint()
            ok &= projection_equal
        receipt['status'] = 'PASS' if ok else 'FAIL'
        exit_code = 0 if ok else 1
    except KeyboardInterrupt:
        receipt['status'] = 'INTERRUPTED'
        receipt['error'] = 'Qualification was interrupted before completion.'
        exit_code = 130
    except OSError as error:
        receipt['status'] = 'FAIL'
        receipt['error'] = f'{type(error).__name__}: {error}'
        print(receipt['error'], file=sys.stderr)
    finally:
        if before is not None:
            try:
                after = source_hashes(root)
                receipt['source_after'] = after
                receipt['source_unchanged'] = before == after
                if before != after:
                    if receipt['status'] != 'INTERRUPTED':
                        receipt['status'] = 'FAIL'
                    exit_code = exit_code or 1
            except OSError as error:
                receipt['source_unchanged'] = None
                receipt['source_hash_error'] = f'{type(error).__name__}: {error}'
                receipt['status'] = 'FAIL'
                exit_code = exit_code or 1
        if receipt['status'] == 'RUNNING':
            # Also cover unexpected exceptions without leaving a successful or
            # apparently still-running result after this process has ended.
            receipt['status'] = 'FAIL'
            receipt['error'] = 'Qualification ended without a terminal result.'
        receipt['active_check'] = None
        receipt['finished_utc'] = datetime.now(timezone.utc).isoformat()
        checkpoint()
    print(f"{receipt['status']}: {receipt_path}")
    return exit_code


if __name__ == '__main__':
    sys.exit(main())
