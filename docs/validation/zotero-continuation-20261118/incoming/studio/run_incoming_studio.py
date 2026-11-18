#!/usr/bin/env python3
"""Qualify the changed Studio document-comparison suite locally."""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl,hashlib,json,os
from pathlib import Path
import subprocess,time
from urllib.parse import unquote,urljoin,urlparse

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo',type=Path,required=True)
parser.add_argument('--workspace',type=Path,required=True)
parser.add_argument('--toolchain',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
a=parser.parse_args()
repo,workspace,toolchain,out=[p.resolve() for p in (a.repo,a.workspace,a.toolchain,a.output)]
out.mkdir(parents=True,exist_ok=True)
if (out/'run.json').exists():raise RuntimeError('Use a fresh output directory')
def now():return datetime.now(timezone.utc).isoformat()
def record(path):
    payload=path.read_bytes()
    return {'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest(),'git_blob_sha1':hashlib.sha1(b'blob '+str(len(payload)).encode()+b'\0'+payload).hexdigest()}
def write(name,payload):(out/name).write_text(json.dumps(payload,indent=2,sort_keys=True)+'\n')
selected=['packages/quds_office_editor/example/test/studio_document_comparison_test.dart']
def source():
    files=[repo/p for p in selected]
    for folder in ['packages/quds_office_editor/example/lib','packages/quds_office_editor/lib','packages/quds_office_engine/lib','packages/legacy_doc_parser/lib']:
        files.extend(p for p in (repo/folder).rglob('*') if p.is_file())
    return {str(p.relative_to(repo)):record(p) for p in sorted(set(files))}
config=workspace/'.dart_tool/package_config.json'
packages=json.loads(config.read_text())['packages']
test_entry=next(p for p in packages if p['name']=='test')
test_root=Path(unquote(urlparse(urljoin(config.as_uri(),test_entry['rootUri'])).path))
sdk=toolchain/'flutter-sdk'
dart=sdk/'bin/cache/dart-sdk/bin/dart'
command=[str(sdk/'bin/flutter'),'test','--no-pub','--reporter','json','--concurrency','2']+['test/'+Path(p).name for p in selected]
env=dict(os.environ,FLUTTER_ROOT=str(sdk),PUB_CACHE=str(toolchain/'pub-cache'),TMPDIR=str(toolchain/'tmp'),XDG_CONFIG_HOME=str(toolchain/'config'),CI='true',DART_SUPPRESS_ANALYTICS='true',DASH__SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true')
lock_path=toolchain/'flutter-cli.lock'
lock_stream=lock_path.open('a')
print('Waiting for shared Flutter CLI lock: '+str(lock_path),flush=True)
fcntl.flock(lock_stream.fileno(),fcntl.LOCK_EX)
print('Acquired shared Flutter CLI lock',flush=True)
before=source()
write('source-before.json',before)
bindings=[config,workspace/'pubspec.lock',workspace/'.dart_tool/package_graph.json',dart,sdk/'bin/cache/artifacts/engine/linux-x64/flutter_tester',test_root/'pubspec.yaml']
bound_before={str(p):record(p) for p in bindings}
write('runtime-binding-before.json',bound_before)
run={'started_at_utc':now(),'command':command,'cwd':str(workspace/'packages/quds_office_editor/example'),'head_at_start':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'selected_test_files':selected,'source_file_count':len(before),'runner_sha256':record(Path(__file__))['sha256'],'flutter_lock_path':str(lock_path),'dart_version':subprocess.check_output([str(dart),'--version'],env=env,text=True).strip(),'scope':'Existing changed Studio comparison parser tests; independent of Zotero cohort; serialized with the shared Flutter CLI lock; no CI or golden rendering.'}
write('run.json',run)
start=time.monotonic()
with (out/'events.jsonl').open('wb') as stdout,(out/'stderr.log').open('wb') as stderr:
    try:
        actual=subprocess.run(command,cwd=run['cwd'],env=env,stdout=stdout,stderr=stderr,timeout=600)
        exit_code=actual.returncode
        timeout=False
    except subprocess.TimeoutExpired:
        exit_code=None
        timeout=True
elapsed=time.monotonic()-start
after=source()
write('source-after.json',after)
bound_after={str(p):record(p) for p in bindings}
write('runtime-binding-after.json',bound_after)
events=[];parse_errors=[]
for line_no,line in enumerate((out/'events.jsonl').read_text().splitlines(),1):
    try:events.append(json.loads(line))
    except json.JSONDecodeError:parse_errors.append({'line':line_no,'text':line})
starts={e['test']['id']:e['test'] for e in events if e.get('type')=='testStart'}
suites={e['suite']['id']:e['suite'] for e in events if e.get('type')=='suite'}
finishes=[e for e in events if e.get('type')=='testDone']
completion=[e for e in events if e.get('type')=='done']
errors=[e for e in events if e.get('type')=='error']
cases=[];excluded=[]
for e in finishes:
    test=starts.get(e['testID'],{})
    row={'id':e['testID'],'name':test.get('name'),'suite':suites.get(test.get('suiteID'),{}).get('path'),'result':e['result'],'skipped':e.get('skipped',False)}
    (excluded if e.get('hidden') or test.get('name','').endswith(('(setUpAll)','(tearDownAll)')) else cases).append(row)
guards={'source_unchanged':before==after,'runtime_graph_locks_unchanged':bound_before==bound_after,'selected_suite_executed':len(suites)==len(selected),'every_started_event_finished_once':set(starts)=={e['testID'] for e in finishes} and len(starts)==len(finishes)}
passed=exit_code==0 and all(guards.values()) and not errors and not parse_errors and len(completion)==1 and completion[0].get('success') and bool(cases) and all(e['result']=='success' and not e['skipped'] for e in cases)
write('cases.json',cases);write('excluded-events.json',excluded)
summary={**run,'status':'passed' if passed else 'failed','finished_at_utc':now(),'elapsed_seconds':elapsed,'actual_process_exit_code':exit_code,'timed_out':timeout,'suite_count':len(suites),'substantive_test_count':len(cases),'substantive_results':dict(Counter(c['result'] for c in cases)),'skipped':sum(bool(c['skipped']) for c in cases),'guards':guards,'error_events':errors,'parse_errors':parse_errors,'completion_events':completion,'head_at_end':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()}
summary['artifacts']={p.name:record(p) for p in sorted(out.iterdir()) if p.is_file() and p.name!='summary.json'}
write('summary.json',summary)
print(json.dumps({k:summary[k] for k in ['status','suite_count','substantive_test_count','substantive_results','skipped','actual_process_exit_code','elapsed_seconds','guards']},indent=2),flush=True)
raise SystemExit(0 if passed else 1)
