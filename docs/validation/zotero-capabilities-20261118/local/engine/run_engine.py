#!/usr/bin/env python3
"""Run the selected Zotero engine cohort with complete machine-event evidence."""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', required=True, type=Path)
parser.add_argument('--workspace', required=True, type=Path)
parser.add_argument('--toolchain', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
repo, workspace, toolchain, out = [p.resolve() for p in (args.repo, args.workspace, args.toolchain, args.output)]
out.mkdir(parents=True, exist_ok=True)
if (out/'summary.json').exists():
    raise RuntimeError('Use a new output directory; existing evidence is not overwritten')
sdk = (toolchain/'flutter-sdk').resolve()
dart = sdk/'bin/cache/dart-sdk/bin/dart'
cwd = workspace/'packages/quds_office_engine'

def sha(p: Path) -> str:
    h = hashlib.sha256()
    with p.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()

def file_record(p: Path) -> dict:
    return {'bytes': p.stat().st_size, 'sha256': sha(p)}

def compressed_json(name: str, payload) -> str:
    data = (json.dumps(payload, indent=2, sort_keys=True)+'\n').encode()
    path = out/name
    path.write_bytes(gzip.compress(data, mtime=0))
    return sha(path)

selected = sorted((repo/'packages/quds_office_engine/test').glob('*zotero*_test.dart'))
assert selected and any(p.name == 'zotero_catalog_query_test.dart' for p in selected)
selected_paths = [str(p.relative_to(repo)) for p in selected]
config_path = workspace/'.dart_tool/package_config.json'
graph_path = workspace/'.dart_tool/package_graph.json'
config = json.loads(config_path.read_text())
graph = {p['name']:p for p in json.loads(graph_path.read_text())['packages']}
config_by_name = {p['name']:p for p in config['packages']}
queue = ['quds_office_engine'] + graph['quds_office_engine']['devDependencies']
reachable = set()
while queue:
    name = queue.pop()
    if name in reachable: continue
    reachable.add(name)
    queue.extend(graph[name].get('dependencies', []))

def source_snapshot():
    paths = set(selected)
    for directory in [repo/'packages/quds_office_engine/lib', repo/'packages/legacy_doc_parser/lib', repo/'packages/quds_office_engine/test/fixtures/zotero']:
        paths.update(p for p in directory.rglob('*') if p.is_file())
    for rel in ['pubspec.yaml', 'analysis_options.yaml', 'packages/quds_office_engine/pubspec.yaml', 'packages/legacy_doc_parser/pubspec.yaml']:
        paths.add(repo/rel)
    return {str(p.relative_to(repo)):file_record(p) for p in sorted(paths)}

def dependency_snapshot():
    result = {}
    for name in sorted(reachable):
        if name in {'quds_office_engine', 'legacy_doc_parser'}: continue
        item = config_by_name[name]
        root = Path(unquote(urlparse(urljoin(config_path.as_uri(), item['rootUri'])).path))
        paths = [root/'pubspec.yaml']
        for sub in ['lib','bin']:
            if (root/sub).is_dir(): paths.extend(p for p in (root/sub).rglob('*') if p.is_file())
        for p in sorted(set(paths)):
            result[name+'/'+str(p.relative_to(root))] = file_record(p)
    return result

def runtime_snapshot():
    base = sdk/'bin/cache/dart-sdk'
    return {str(p.relative_to(sdk)):file_record(p) for p in sorted(base.rglob('*')) if p.is_file()}

def workspace_snapshot():
    paths = [config_path, graph_path, workspace/'pubspec.yaml', workspace/'pubspec.lock', workspace/'analysis_options.yaml', cwd/'pubspec.yaml', workspace/'packages/legacy_doc_parser/pubspec.yaml']
    return {str(p.relative_to(workspace)):file_record(p) for p in paths}

def head():
    return subprocess.check_output(['git','rev-parse','HEAD'], cwd=repo, text=True).strip()

started = datetime.now(timezone.utc).isoformat()
source_before = source_snapshot()
deps_before = dependency_snapshot()
runtime_before = runtime_snapshot()
workspace_before = workspace_snapshot()
head_before = head()
compressed_json('source-before.json.gz', source_before)
compressed_json('dependencies-before.json.gz', deps_before)
compressed_json('runtime-before.json.gz', runtime_before)
compressed_json('workspace-before.json.gz', workspace_before)
command = [str(dart), 'test', '--reporter', 'json', '--concurrency', '4'] + ['test/'+p.name for p in selected]
env = dict(os.environ, FLUTTER_ROOT=str(sdk), PUB_CACHE=str(toolchain/'pub-cache'), TMPDIR=str(toolchain/'tmp'), XDG_CONFIG_HOME=str(toolchain/'config'), CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true')
run_record = {'status':'running','started_at_utc':started,'command':command,'cwd':str(cwd),'source_head_at_start':head_before,'selected_test_files':selected_paths,'reachable_packages':sorted(reachable),'runner_sha256':sha(Path(__file__))}
(out/'run.json').write_text(json.dumps(run_record,indent=2)+'\n')
print('RUN engine Zotero suites: '+str(len(selected)), flush=True)
start = time.monotonic()
with (out/'events.jsonl').open('wb') as stdout, (out/'stderr.log').open('wb') as stderr:
    result = subprocess.run(command,cwd=cwd,env=env,stdout=stdout,stderr=stderr,timeout=600)
elapsed = time.monotonic()-start
source_after = source_snapshot()
deps_after = dependency_snapshot()
runtime_after = runtime_snapshot()
workspace_after = workspace_snapshot()
compressed_json('source-after.json.gz', source_after)
compressed_json('dependencies-after.json.gz', deps_after)
compressed_json('runtime-after.json.gz', runtime_after)
compressed_json('workspace-after.json.gz', workspace_after)

events = []
parse_errors = []
for index,line in enumerate((out/'events.jsonl').read_text().splitlines(),start=1):
    try: events.append(json.loads(line))
    except json.JSONDecodeError: parse_errors.append({'line':index,'text':line})
starts = {e['test']['id']:e['test'] for e in events if e.get('type')=='testStart'}
dones = [e for e in events if e.get('type')=='testDone']
substantive = [e for e in dones if not e.get('hidden', False)]
hidden = [e for e in dones if e.get('hidden', False)]
errors = [e for e in events if e.get('type')=='error']
final_events = [e for e in events if e.get('type')=='done']
suite_events = {e['suite']['id']:e['suite'] for e in events if e.get('type')=='suite'}
cases = []
for e in substantive:
    test = starts[e['testID']]
    suite = suite_events.get(test['suiteID'],{})
    cases.append({'id':e['testID'],'name':test['name'],'suite':suite.get('path'),'result':e['result'],'skipped':e['skipped']})
compressed_json('cases.json.gz', cases)
guards = {'source_unchanged':source_before==source_after,'dependencies_unchanged':deps_before==deps_after,'runtime_unchanged':runtime_before==runtime_after,'workspace_inputs_unchanged':workspace_before==workspace_after,'selected_tests_unchanged':selected_paths==[str(p.relative_to(repo)) for p in sorted((repo/'packages/quds_office_engine/test').glob('*zotero*_test.dart'))]}
summary = {**run_record,'finished_at_utc':datetime.now(timezone.utc).isoformat(),'elapsed_seconds':elapsed,'exit_code':result.returncode,'source_head_at_end':head(),'status':'passed' if result.returncode==0 and all(guards.values()) and not errors and not parse_errors and len(final_events)==1 and final_events[0].get('success') else 'failed','suite_count':len(suite_events),'substantive_test_count':len(substantive),'substantive_results':dict(Counter(e['result'] for e in substantive)),'substantive_skips':sum(bool(e['skipped']) for e in substantive),'hidden_test_count':len(hidden),'hidden_results':dict(Counter(e['result'] for e in hidden)),'test_done_event_count':len(dones),'error_events':errors,'json_parse_errors':parse_errors,'final_events':final_events,'guards':guards,'source_file_count':len(source_before),'dependency_file_count':len(deps_before),'runtime_file_count':len(runtime_before),'workspace_file_count':len(workspace_before),'scope':'All current engine test/*zotero*_test.dart suites. Earlier setup smokes excluded. Local synthetic documents, fixtures and transports; no live-account or external Word/LibreOffice acceptance claimed.'}
for name in ['events.jsonl','stderr.log']:
    path=out/name
    data=path.read_bytes()
    (out/(name+'.gz')).write_bytes(gzip.compress(data,mtime=0))
    path.unlink()
summary['artifacts'] = {p.name:file_record(p) for p in sorted(out.iterdir()) if p.is_file() and p.name!='summary.json'}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:summary[k] for k in ['status','exit_code','suite_count','substantive_test_count','substantive_results','substantive_skips','hidden_test_count','guards']}),flush=True)
if summary['status']!='passed': raise SystemExit(1)
