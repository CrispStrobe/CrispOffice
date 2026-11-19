import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

root = Path('/workspace/scratch/9c3338a48b2c')
repo = root / 'crispoffice'
out = root / 'validation/layout-theme'
name, cwd_text, *command = sys.argv[1:]
cwd = Path(cwd_text)
if name == 'incoming-archive-scoped-analysis' and (out / 'pause-before-old-mail').exists():
    hold = {'status': 'not_started', 'reason': 'Root requested source integration after completed VBA gate, before old mail gates.',
            'name': name, 'cwd': str(cwd), 'command_not_run': command}
    (out / 'pre-mail-integration-boundary.json').write_text(json.dumps(hold, indent=2) + '\n')
    print(json.dumps(hold, indent=2), flush=True)
    sys.exit(75)


def snapshot():
    paths = set(repo.glob('packages/*/lib/**/*.dart'))
    paths.update(repo.glob('packages/*/example/lib/**/*.dart'))
    paths.update(repo.glob('packages/*/tool/**/*.dart'))
    paths.update(repo.glob('packages/*/example/macros/**/*.bas'))
    paths.update(repo.glob('packages/*/example/macros/**/*.json'))
    paths.update(repo.glob('packages/*/test/support/**/*.dart'))
    paths.update(repo.glob('packages/*/example/test/support/**/*.dart'))
    paths.update(repo.glob('packages/*/pubspec.yaml'))
    paths.update(repo.glob('packages/*/example/pubspec.yaml'))
    paths.update(repo / p for p in ['.fvmrc', 'pubspec.yaml', 'pubspec.lock'])
    paths.update((cwd / p).resolve() for p in command if p.endswith('.dart') and (cwd / p).is_file())
    return {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths) if p.is_file() and p.is_relative_to(repo)}


def save_snapshot(label, value):
    path = out / f'{name}.source-{label}.json'
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'file_count': len(value)}


before = snapshot()
before_manifest = save_snapshot('before', before)
runtime_paths = {root / 'toolchain' / p for p in ['run_dart.sh', 'run_flutter.sh', 'env.sh', 'runtime.json']}
runtime_paths.update(repo / '.dart_tool' / p for p in ['package_config.json', 'native_assets.yaml'])
runtime_paths.update((cwd / p).resolve() for p in command if p.endswith('.dart') and (cwd / p).is_file() and not (cwd / p).resolve().is_relative_to(repo))
runtime_hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(runtime_paths) if p.is_file()}
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
started = time.time()
log = out / f'{name}.log'
with log.open('w') as stream:
    result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
after = snapshot()
changed = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
receipt = {
    'head': head, 'cwd': str(cwd), 'command': command,
    'exit_code': result.returncode, 'elapsed_seconds': round(time.time() - started, 3),
    'log': str(log), 'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
    'source_before': before_manifest, 'source_changed_during_run': changed,
    'runtime_source_sha256': runtime_hashes,
}
log_text = log.read_text()
if '--reporter=json' in command:
    suites, tests, cases, done_event = {}, {}, [], None
    for line in log_text.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']
        elif kind == 'testStart':
            tests[event['test']['id']] = event['test']
        elif kind == 'testDone' and not event.get('hidden'):
            test = tests[event['testID']]
            suite = suites[test['suiteID']]
            file = Path(suite['path'])
            if not file.is_absolute():
                file = (cwd / file).resolve()
            cases.append({
                'file': str(file.relative_to(repo)) if file.is_relative_to(repo) else str(file),
                'name': test['name'], 'platform': suite['platform'],
                'result': event['result'], 'skipped': event.get('skipped', False),
                'line': test.get('root_line', test.get('line')),
            })
        elif kind == 'done':
            done_event = event
    cases_path = out / f'{name}.cases.json'
    cases_path.write_text(json.dumps(cases, indent=2) + '\n')
    receipt['test_summary'] = {
        'completed_cases': len(cases),
        'passed': sum(case['result'] == 'success' and not case['skipped'] for case in cases),
        'skipped': sum(case['skipped'] for case in cases),
        'failed': sum(case['result'] != 'success' for case in cases),
        'runner_done': done_event,
        'cases': str(cases_path),
        'cases_sha256': hashlib.sha256(cases_path.read_bytes()).hexdigest(),
    }
if changed:
    receipt['source_after'] = save_snapshot('after', after)
(out / f'{name}.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2), flush=True)
print(log_text[-4000:] if '--reporter=json' in command else log_text[-22000:], flush=True)
sys.exit(result.returncode)
