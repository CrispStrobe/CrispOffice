import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('scope', choices=['engine', 'editor', 'studio', 'renderer'])
p.add_argument('--repo', required=True)
p.add_argument('--output', required=True)
p.add_argument('--concurrency', type=int, default=4)
a = p.parse_args()
repo = Path(a.repo).resolve()
out = Path(a.output).resolve() / a.scope
out.mkdir(parents=True, exist_ok=True)
package = {'engine': 'packages/quds_office_engine',
           'editor': 'packages/quds_office_editor',
           'renderer': 'packages/quds_office_editor',
           'studio': 'packages/quds_office_editor/example'}[a.scope]
cwd = repo / package
patterns = {
    'engine': ['*zotero*_test.dart', 'odt_*_test.dart', 'word_table*_test.dart',
               'word_deserializer*_test.dart', 'word_all_caps*_test.dart'],
    'editor': ['word_odt*_test.dart', 'word_zotero_*controller_test.dart',
               'word_zotero_snapshot_test.dart', 'word_zotero_format_test.dart',
               'word_selection_paint_test.dart', 'word_proofing_geometry_test.dart',
               'word_proofing_capture_cache_test.dart'],
    'studio': ['studio_odt_open_test.dart', 'studio_zotero_odt_export_test.dart',
               'studio_zotero_citing_transport_test.dart', 'studio_zotero_shortcuts_test.dart'],
    'renderer': ['word_selection_path_cache_test.dart', 'word_selection_paint_test.dart',
                 'word_proofing_geometry_test.dart', 'word_proofing_capture_cache_test.dart'],
}[a.scope]
tests = sorted({str(f.relative_to(cwd)) for pattern in patterns
                for f in (cwd / 'test').glob(pattern)})
assert tests

def write(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args]).decode().strip()

def source_manifest():
    paths = git('ls-files', '-z').split('\0')
    selected = [name for name in paths if name and (
        (name.startswith(('packages/', 'third_party/')) and name.endswith('.dart'))
        or name.endswith(('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')))]
    selected += ['.dart_tool/package_config.json']
    return {name: hashlib.sha256((repo/name).read_bytes()).hexdigest()
            for name in sorted(selected) if (repo/name).is_file()}

before = source_manifest()
write('source-before.json', before)
command = (['dart', '--packages='+str(repo/'.dart_tool/package_config.json'),
            str(Path(os.environ['PUB_CACHE'])/'hosted/pub.dev/test-1.31.1/bin/test.dart'),
            '--reporter=json', '--concurrency='+str(a.concurrency)] if a.scope == 'engine' else
           ['flutter', 'test', '--no-pub', '--reporter=json', '--concurrency=2']) + tests
receipt = dict(scope=a.scope, cwd=str(cwd), command=command, tests=tests,
               source_commit=git('rev-parse', 'HEAD'), source_tree=git('rev-parse', 'HEAD^{tree}'),
               started=time.time(), source_files=len(before))
write('receipt.json', receipt)
with (out/'events.jsonl').open('w') as stdout, (out/'stderr.log').open('w') as stderr:
    result = subprocess.run(command, cwd=cwd, stdout=stdout, stderr=stderr)
after = source_manifest()
write('source-after.json', after)
events, other = [], []
for line in (out/'events.jsonl').read_text().splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        if line.strip(): other.append(line)
        continue
    if isinstance(event, dict): events.append(event)
starts = {e['test']['id']:e['test'] for e in events if e.get('type')=='testStart'}
cases = [{**starts.get(e['testID'], {}), 'result':e['result'],
          'skipped':e.get('skipped', False)} for e in events
         if e.get('type')=='testDone' and not e.get('hidden', False)]
errors = [e for e in events if e.get('type')=='error']
raw = (out/'events.jsonl').read_text() + (out/'stderr.log').read_text()
background_errors = [marker for marker in ['Unhandled exception:', 'EXCEPTION CAUGHT BY'] if marker in raw]
write('cases.json', cases)
receipt.update(finished=time.time(), exit_code=result.returncode,
               passed=sum(c['result']=='success' and not c['skipped'] for c in cases),
               failed=sum(c['result']!='success' for c in cases),
               skipped=sum(c['skipped'] for c in cases), errors=errors,
               raw_background_error_markers=background_errors,
               source_changes=[name for name in sorted(set(before)|set(after)) if before.get(name)!=after.get(name)],
               runner_done=[e for e in events if e.get('type')=='done'],
               non_json_output=other,
               stderr_bytes=(out/'stderr.log').stat().st_size)
receipt['accepted'] = bool(result.returncode==0 and receipt['passed']>0
                           and not receipt['failed'] and not receipt['skipped'] and not errors
                           and not background_errors and not receipt['source_changes']
                           and receipt['runner_done'] and receipt['runner_done'][-1].get('success'))
write('receipt.json', receipt)
print(json.dumps({k:receipt[k] for k in ['scope','source_commit','passed','failed','skipped',
                                      'exit_code','accepted','source_changes','stderr_bytes']}))
raise SystemExit(0 if receipt['accepted'] else 1)
