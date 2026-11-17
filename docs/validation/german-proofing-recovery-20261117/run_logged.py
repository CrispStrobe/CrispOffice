"""Run a bounded local qualification command and preserve exact inputs/logs."""
import argparse
import collections
import datetime
import gzip
import hashlib
import json
import os
import subprocess
import time
from pathlib import Path

SCRIPT = Path(__file__).resolve()
DEFAULT_ROOT = SCRIPT.parent / 'quds_office_suite'
if not DEFAULT_ROOT.is_dir():
    DEFAULT_ROOT = SCRIPT.parents[3]
ROOT = Path(os.environ.get('QUDS_RECOVERY_REPO', str(DEFAULT_ROOT)))
RUNTIME = Path(os.environ.get('QUDS_RECOVERY_RUNTIME_ROOT', '/home/agent/.codex/skills/remote-skills/.quds-gector-work/runtime'))
EVIDENCE = ROOT / 'docs/validation/german-proofing-recovery-20261117/evidence'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def capture_inputs(scopes):
    result = {}
    for scope in scopes:
        base = ROOT / scope
        paths = sorted(base.rglob('*')) if base.is_dir() else [base]
        for path in paths:
            if path.is_file() and not any(p in {'.dart_tool', 'build', '__pycache__'} for p in path.relative_to(ROOT).parts):
                data = path.read_bytes()
                result[str(path.relative_to(ROOT))] = {'bytes': len(data), 'sha256': sha(data)}
    return result


def write_gzip(path, data):
    with path.open('wb') as raw:
        with gzip.GzipFile(fileobj=raw, mode='wb', mtime=0, filename='') as stream:
            stream.write(data)


parser = argparse.ArgumentParser()
parser.add_argument('--label', required=True)
parser.add_argument('--cwd', default='.')
parser.add_argument('--scope', action='append', default=[])
parser.add_argument('--timeout', type=int, default=900)
parser.add_argument('--expect-exit', type=int, default=0)
parser.add_argument('--dart-tests', action='store_true')
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
if not command:
    parser.error('A command is required')
EVIDENCE.mkdir(parents=True, exist_ok=True)
receipt_path = EVIDENCE / (args.label + '.json')
if receipt_path.exists():
    raise SystemExit('Refusing to overwrite existing receipt: ' + str(receipt_path))
scopes = list(dict.fromkeys([*args.scope, 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']))
before = capture_inputs(scopes)
config = ROOT / '.dart_tool/package_config.json'
config_before = sha(config.read_bytes()) if config.is_file() else None
harness_sha = sha(SCRIPT.read_bytes())
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
env = os.environ.copy()
env.update({'PUB_CACHE': str(RUNTIME / 'pub-cache'), 'FLUTTER_ROOT': str(RUNTIME / 'flutter-sdk'), 'DART_SUPPRESS_ANALYTICS': 'true', 'CI': 'true'})
env['PATH'] = str(RUNTIME / 'flutter-sdk/bin') + ':' + env['PATH']
if not env.get('TMPDIR') or not Path(env['TMPDIR']).is_dir():
    task_tmp = ROOT / '.dart_tool/recovery_tmp'
    task_tmp.mkdir(parents=True, exist_ok=True)
    env['TMPDIR'] = str(task_tmp)
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
start = time.monotonic()
try:
    run = subprocess.run(command, cwd=ROOT / args.cwd, env=env, capture_output=True, timeout=args.timeout)
    code, stdout, stderr = run.returncode, run.stdout, run.stderr
except subprocess.TimeoutExpired as error:
    code, stdout, stderr = 124, error.stdout or b'', error.stderr or b''
    stderr += b'\nQualification timeout reached.\n'
duration = time.monotonic() - start
after = capture_inputs(scopes)
changed = sorted(p for p in set(before) | set(after) if before.get(p) != after.get(p))
tests, completions, done, errors = {}, {}, [], []
for line in stdout.decode('utf-8', errors='replace').splitlines():
    try:
        event = json.loads(line)
    except (ValueError, TypeError):
        continue
    if not isinstance(event, dict):
        continue
    if event.get('type') == 'testStart':
        tests[event['test']['id']] = event['test']
    elif event.get('type') == 'testDone':
        completions[event['testID']] = event
    elif event.get('type') == 'done':
        done.append(event)
    elif event.get('type') == 'error':
        errors.append(event)
counts = collections.Counter()
for identity, event in completions.items():
    test = tests.get(identity, {})
    if event.get('hidden') or test.get('metadata', {}).get('skip') or event.get('skipped'):
        if event.get('skipped') and not event.get('hidden'):
            counts['skipped'] += 1
        continue
    counts[event.get('result', 'unknown')] += 1
outputs = {}
for kind, data in [('stdout', stdout), ('stderr', stderr)]:
    name = args.label + '.' + kind + '.gz'
    write_gzip(EVIDENCE / name, data)
    outputs[kind] = {'path': name, 'uncompressedBytes': len(data), 'uncompressedSha256': sha(data), 'compressedSha256': sha((EVIDENCE / name).read_bytes())}
manifest = {'before': before, 'after': after, 'changed': changed}
manifest_name = args.label + '.inputs.json.gz'
write_gzip(EVIDENCE / manifest_name, json.dumps(manifest, sort_keys=True, indent=2).encode() + b'\n')
dart = RUNTIME / 'flutter-sdk/bin/cache/dart-sdk/bin/dart'
terminal_ok = not args.dart_tests or (bool(counts) and len(done) == 1 and done[0].get('success') == (code == 0))
receipt = {'schemaVersion': 1, 'label': args.label, 'head': head, 'startedAt': started, 'finishedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'durationSeconds': duration, 'cwd': args.cwd, 'command': command, 'exitCode': code, 'expectedExitCode': args.expect_exit, 'sourceScopes': scopes, 'sourceInputCount': len(before), 'changedInputs': changed, 'inputManifest': manifest_name, 'inputManifestSha256': sha((EVIDENCE / manifest_name).read_bytes()), 'packageConfigSha256': sha(config.read_bytes()) if config.is_file() else None, 'dartExecutableSha256': sha(dart.read_bytes()), 'substantiveTestCounts': dict(counts), 'terminalEvents': done, 'testErrors': errors, 'outputs': outputs, 'passed': code == args.expect_exit and not changed and terminal_ok}
receipt['harnessSha256'] = harness_sha
receipt['packageConfigBeforeSha256'] = config_before
receipt['packageConfigStable'] = config_before == receipt['packageConfigSha256']
receipt['passed'] = receipt['passed'] and receipt['packageConfigStable']
receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: receipt[k] for k in ['label', 'head', 'exitCode', 'durationSeconds', 'sourceInputCount', 'changedInputs', 'substantiveTestCounts', 'passed']}, indent=2), flush=True)
if code != args.expect_exit:
    print(stdout.decode('utf-8', errors='replace')[-10000:])
    print(stderr.decode('utf-8', errors='replace')[-5000:])
raise SystemExit(0 if receipt['passed'] else 1)
