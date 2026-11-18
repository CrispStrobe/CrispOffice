#!/usr/bin/env python3
"""Run a canonical Flutter Zotero cohort with source/runtime guards and raw events."""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse
import yaml

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', required=True, type=Path)
parser.add_argument('--workspace', required=True, type=Path)
parser.add_argument('--toolchain', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--package', default='packages/quds_office_editor')
args = parser.parse_args()
repo, workspace, toolchain, out = [p.resolve() for p in (args.repo, args.workspace, args.toolchain, args.output)]
out.mkdir(parents=True, exist_ok=True)
if (out/'summary.json').exists():
    raise RuntimeError('Use a new output directory; existing evidence is not overwritten')
sdk = (toolchain/'flutter-sdk').resolve()
flutter = sdk/'bin/flutter'
cwd = workspace/args.package
source_package = repo/args.package
package_name = yaml.safe_load((source_package/'pubspec.yaml').read_text())['name']

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

selected = sorted((source_package/'test').glob('*zotero*_test.dart'))
assert selected
selected_paths = [str(p.relative_to(repo)) for p in selected]
config_path = workspace/'.dart_tool/package_config.json'
graph_path = workspace/'.dart_tool/package_graph.json'
config = json.loads(config_path.read_text())
graph = {p['name']:p for p in json.loads(graph_path.read_text())['packages']}
config_by_name = {p['name']:p for p in config['packages']}
queue = [package_name] + graph[package_name]['devDependencies']
reachable = set()
while queue:
    name = queue.pop()
    if name in reachable: continue
    reachable.add(name)
    queue.extend(graph[name].get('dependencies', []))
package_roots = {name:Path(unquote(urlparse(urljoin(config_path.as_uri(), config_by_name[name]['rootUri'])).path)) for name in reachable}
canonical = {name:repo/root.relative_to(workspace) for name,root in package_roots.items() if root.is_relative_to(workspace)}
assert package_name in canonical

def add_directory(paths: set, directory: Path):
    if directory.is_dir(): paths.update(p for p in directory.rglob('*') if p.is_file())
    elif directory.is_file(): paths.add(directory)

def source_snapshot():
    paths = set(selected)
    for directory in canonical.values():
        add_directory(paths,directory/'lib')
        paths.add(directory/'pubspec.yaml')
        if (directory/'analysis_options.yaml').is_file(): paths.add(directory/'analysis_options.yaml')
        manifest = yaml.safe_load((directory/'pubspec.yaml').read_text())
        for entry in (manifest.get('flutter') or {}).get('assets', []):
            asset = entry if isinstance(entry,str) else entry['path']
            add_directory(paths,directory/asset)
        for family in (manifest.get('flutter') or {}).get('fonts', []):
            for font in family.get('fonts', []): add_directory(paths,directory/font['asset'])
    add_directory(paths,repo/'packages/quds_office_engine/test/fixtures/zotero')
    for rel in ['pubspec.yaml', 'analysis_options.yaml']:
        paths.add(repo/rel)
    return {str(p.relative_to(repo)):file_record(p) for p in sorted(paths)}

def dependency_snapshot():
    result = {}
    for name in sorted(reachable):
        if name in canonical: continue
        root = package_roots[name]
        paths = {root/'pubspec.yaml'}
        for sub in ['lib','bin']:
            add_directory(paths,root/sub)
        for p in sorted(paths):
            result[name+'/'+str(p.relative_to(root))] = file_record(p)
    return result

def runtime_snapshot():
    paths = set()
    for rel in ['bin/cache/dart-sdk', 'bin/cache/artifacts/engine/common', 'bin/cache/artifacts/engine/linux-x64', 'bin/cache/artifacts/material_fonts', 'bin/internal']:
        add_directory(paths,sdk/rel)
    for rel in ['bin/flutter', 'bin/cache/flutter_tools.snapshot', 'bin/cache/flutter_tools.stamp', 'packages/flutter_tools/pubspec.yaml', 'packages/flutter_tools/pubspec.lock', 'packages/flutter_tools/.dart_tool/package_config.json']:
        if (sdk/rel).is_file(): paths.add(sdk/rel)
    return {str(p.relative_to(sdk)):file_record(p) for p in sorted(paths)}

def workspace_paths():
    paths = {config_path, graph_path, workspace/'pubspec.yaml', workspace/'pubspec.lock', workspace/'analysis_options.yaml'}
    for name in canonical:
        paths.add(package_roots[name]/'pubspec.yaml')
        if (package_roots[name]/'analysis_options.yaml').is_file(): paths.add(package_roots[name]/'analysis_options.yaml')
    return sorted(paths)

def workspace_snapshot():
    return {str(p.relative_to(workspace)):file_record(p) for p in workspace_paths()}

def head():
    return subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()

lock_path = toolchain/'flutter-cli.lock'
lock = lock_path.open('a')
print('Waiting for shared Flutter CLI lock', flush=True)
fcntl.flock(lock,fcntl.LOCK_EX)
started = datetime.now(timezone.utc).isoformat()
source_before = source_snapshot()
deps_before = dependency_snapshot()
runtime_before = runtime_snapshot()
workspace_before = workspace_snapshot()
head_before = head()
for label,value in [('source',source_before),('dependencies',deps_before),('runtime',runtime_before),('workspace',workspace_before)]:
    compressed_json(label+'-before.json.gz',value)
command = [str(flutter),'test','--no-pub','--machine','--concurrency','4'] + ['test/'+p.name for p in selected]
env = dict(os.environ,FLUTTER_ROOT=str(sdk),PUB_CACHE=str(toolchain/'pub-cache'),TMPDIR=str(toolchain/'tmp'),XDG_CONFIG_HOME=str(toolchain/'config'),CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true')
run_record = {'status':'running','started_at_utc':started,'command':command,'cwd':str(cwd),'package':args.package,'package_name':package_name,'shared_lock':str(lock_path),'source_head_at_start':head_before,'selected_test_files':selected_paths,'reachable_packages':sorted(reachable),'canonical_source_packages':{k:str(v.relative_to(repo)) for k,v in sorted(canonical.items())},'runner_sha256':sha(Path(__file__))}
(out/'run.json').write_text(json.dumps(run_record,indent=2)+'\n')
print('RUN '+package_name+' Zotero suites: '+str(len(selected)),flush=True)
start = time.monotonic()
with (out/'events.jsonl').open('wb') as stdout,(out/'stderr.log').open('wb') as stderr:
    result = subprocess.run(command,cwd=cwd,env=env,stdout=stdout,stderr=stderr,timeout=900)
elapsed = time.monotonic()-start
source_after = source_snapshot()
deps_after = dependency_snapshot()
runtime_after = runtime_snapshot()
workspace_after = workspace_snapshot()
for label,value in [('source',source_after),('dependencies',deps_after),('runtime',runtime_after),('workspace',workspace_after)]:
    compressed_json(label+'-after.json.gz',value)
contents = {str(p.relative_to(workspace)):{**file_record(p),'text':p.read_text()} for p in workspace_paths()}
compressed_json('workspace-inputs.json.gz',contents)
fcntl.flock(lock,fcntl.LOCK_UN)
lock.close()

events = []
parse_errors = []
for index,line in enumerate((out/'events.jsonl').read_text().splitlines(),start=1):
    try: events.append(json.loads(line))
    except json.JSONDecodeError: parse_errors.append({'line':index,'text':line})
starts = {e['test']['id']:e['test'] for e in events if e.get('type')=='testStart'}
dones = [e for e in events if e.get('type')=='testDone']
substantive = [e for e in dones if not e.get('hidden',False)]
hidden = [e for e in dones if e.get('hidden',False)]
errors = [e for e in events if e.get('type')=='error']
final_events = [e for e in events if e.get('type')=='done']
suite_events = {e['suite']['id']:e['suite'] for e in events if e.get('type')=='suite'}
cases = []
for e in substantive:
    test = starts[e['testID']]
    suite = suite_events.get(test['suiteID'],{})
    cases.append({'id':e['testID'],'name':test['name'],'suite':suite.get('path'),'result':e['result'],'skipped':e['skipped']})
compressed_json('cases.json.gz',cases)
guards = {'source_unchanged':source_before==source_after,'dependencies_unchanged':deps_before==deps_after,'runtime_unchanged':runtime_before==runtime_after,'workspace_inputs_unchanged':workspace_before==workspace_after,'selected_tests_unchanged':selected_paths==[str(p.relative_to(repo)) for p in sorted((source_package/'test').glob('*zotero*_test.dart'))]}
passed = result.returncode==0 and all(guards.values()) and not errors and not parse_errors and len(final_events)==1 and final_events[0].get('success') and len(suite_events)==len(selected) and len(substantive)>0 and all(e['result']=='success' and not e['skipped'] for e in substantive)
summary = {**run_record,'finished_at_utc':datetime.now(timezone.utc).isoformat(),'elapsed_seconds':elapsed,'exit_code':result.returncode,'source_head_at_end':head(),'status':'passed' if passed else 'failed','suite_count':len(suite_events),'substantive_test_count':len(substantive),'substantive_results':dict(Counter(e['result'] for e in substantive)),'substantive_skips':sum(bool(e['skipped']) for e in substantive),'hidden_test_count':len(hidden),'hidden_results':dict(Counter(e['result'] for e in hidden)),'test_done_event_count':len(dones),'error_events':errors,'json_parse_errors':parse_errors,'final_events':final_events,'guards':guards,'source_file_count':len(source_before),'dependency_file_count':len(deps_before),'runtime_file_count':len(runtime_before),'workspace_file_count':len(workspace_before),'scope':'All current selected package test/*zotero*_test.dart suites. Earlier setup and focused smokes excluded. Genuine Flutter engine with synthetic documents/transport doubles; no live-account or external Word/LibreOffice acceptance claimed.'}
for name in ['events.jsonl','stderr.log']:
    path=out/name
    (out/(name+'.gz')).write_bytes(gzip.compress(path.read_bytes(),mtime=0))
    path.unlink()
summary['artifacts'] = {p.name:file_record(p) for p in sorted(out.iterdir()) if p.is_file() and p.name!='summary.json'}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:summary[k] for k in ['status','exit_code','suite_count','substantive_test_count','substantive_results','substantive_skips','hidden_test_count','guards']}),flush=True)
if not passed: raise SystemExit(1)
