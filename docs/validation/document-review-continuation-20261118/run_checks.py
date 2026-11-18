"""Run frozen-source document-review and incoming integration checks locally."""
import argparse, gzip, hashlib, importlib.util, json, os, subprocess, time
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path('/workspace/scratch/d322553a8b9d/quds_office_suite')
RUNTIME=ROOT.parent/'review-toolchain'
parser=argparse.ArgumentParser()
parser.add_argument('--head',required=True)
parser.add_argument('--base',default='7c85d83fef2f0b98523653f0d9e5068e9143c7d6')
parser.add_argument('--output',default=str(RUNTIME/'final-checks'))
parser.add_argument('--editor-test',action='append',default=[])
args=parser.parse_args()
OUT=Path(args.output)
OUT.mkdir(parents=True,exist_ok=True)
CHECKS=OUT/'checks'
CHECKS.mkdir(exist_ok=True)

def git(*argv):
    return subprocess.check_output(['git','-C',str(ROOT),*argv],text=True).strip()
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def write(name,data):
    (OUT/name).write_text(json.dumps(data,indent=2)+'\n')

assert git('rev-parse','HEAD')==args.head, 'unexpected source head'
assert not git('diff','--name-only'), 'tracked local changes at final gate'
assert not git('diff','--cached','--name-only'), 'staged local changes at final gate'
spec=importlib.util.spec_from_file_location('prior_checks',ROOT/'docs/validation/document-review-live-20261118/run_checks.py')
prior=importlib.util.module_from_spec(spec);spec.loader.exec_module(prior)
editor=list(prior.EDITOR_TESTS)
new_editor=['word_review_controller_test.dart','word_incremental_proofing_test.dart','word_incremental_proofing_menu_test.dart','word_live_review_changes_test.dart','word_proofing_capture_cache_test.dart']
changed=git('diff','--name-only',args.base,'HEAD').splitlines()
new_editor.extend(Path(p).name for p in changed if p.startswith('packages/quds_office_editor/test/') and p.endswith('_test.dart'))
new_editor.extend(args.editor_test)
for name in new_editor:
    if name not in editor:editor.append(name)
studio=list(prior.STUDIO_TESTS)
test_paths=[f'packages/quds_office_editor/test/{name}' for name in editor]+[f'packages/quds_office_editor/example/test/{name}' for name in studio]
for path in test_paths:
    assert (ROOT/path).is_file(), path

selected=set(test_paths)
for name in git('ls-files').splitlines():
    if name in {'pubspec.yaml','analysis_options.yaml','.fvmrc'} or (
        name.startswith(('packages/','apps/')) and (
            ('/lib/' in name and name.endswith('.dart')) or
            name.endswith(('/pubspec.yaml','/analysis_options.yaml')) or
            ('/assets/fonts/' in name and name.endswith(('.ttf','.otf')))
        )
    ):selected.add(name)
def snapshot():
    return {name:sha(ROOT/name) for name in sorted(selected)}
before=snapshot()
write('source-before.json',before)
record={
    'started_at_utc':datetime.now(timezone.utc).isoformat(),
    'source_commit':args.head,'source_tree':git('rev-parse',args.head+'^{tree}'),
    'source_base':args.base,
    'source_file_count':len(before),
    'source_before_manifest':'source-before.json',
    'source_after_manifest':'source-after.json',
    'editor_suites':editor,'studio_suites':studio,
    'workspace_lock_sha256':sha(ROOT/'pubspec.lock'),
    'runtime_receipt_sha256':sha(RUNTIME/'runtime.json'),
    'runtime':json.loads((RUNTIME/'runtime.json').read_text())['runtime'],
    'runs':[],
    'github_actions_queried_or_awaited':False,
}
write('verification.json',record)

def run(name,command,cwd,tests=False):
    print('START '+name,flush=True)
    started=time.monotonic()
    path=CHECKS/(name+('.jsonl' if tests else '.log'))
    with path.open('wb') as stream:
        p=subprocess.run(command,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT)
    item={'name':name,'command':command,'cwd':str(cwd.relative_to(ROOT)) or '.','exit_code':p.returncode,'elapsed_seconds':round(time.monotonic()-started,3),'log':str(path.relative_to(OUT)),'log_sha256':sha(path)}
    if tests:
        cases={};suites={};hidden=0;done=None;errors=[]
        for line in path.read_text().splitlines():
            try:e=json.loads(line)
            except ValueError:continue
            if e.get('type')=='suite':
                suites[e['suite']['id']]=e['suite']['path']
            elif e.get('type')=='testStart':
                t=e['test'];cases[t['id']]={'name':t['name'],'suite_id':t['suiteID'],'suite':suites.get(t['suiteID'])}
            elif e.get('type')=='testDone':
                if e.get('hidden'):hidden+=1;cases.pop(e['testID'],None)
                elif e['testID'] in cases:cases[e['testID']].update(result=e['result'],skipped=e['skipped'])
            elif e.get('type')=='done':done=e['success']
            elif e.get('type')=='error':errors.append(e)
        item.update(
            passed=sum(c.get('result')=='success' and not c.get('skipped') for c in cases.values()),
            failed=sum(c.get('result') in {'error','failure'} for c in cases.values()),
            skipped=sum(bool(c.get('skipped')) for c in cases.values()),
            hidden_events_excluded=hidden,reporter_success=done,
        )
        counts={}
        for c in cases.values():
            key=Path(c['suite']).name if c.get('suite') else str(c['suite_id'])
            count=counts.setdefault(key,{'passed':0,'failed':0,'skipped':0})
            count['passed']+=int(c.get('result')=='success' and not c.get('skipped'))
            count['failed']+=int(c.get('result') in {'error','failure'})
            count['skipped']+=int(bool(c.get('skipped')))
        item['per_suite']=counts
        (CHECKS/(name+'-cases.json')).write_text(json.dumps(list(cases.values()),indent=2)+'\n')
        (CHECKS/(name+'-errors.json')).write_text(json.dumps(errors,indent=2)+'\n')
        compressed=path.with_suffix(path.suffix+'.gz')
        compressed.write_bytes(gzip.compress(path.read_bytes(),mtime=0))
        item['compressed_log']=str(compressed.relative_to(OUT));item['compressed_log_sha256']=sha(compressed)
    record['runs'].append(item);write('verification.json',record)
    print(json.dumps(item),flush=True)
    return item

run('editor',['flutter','test','--no-pub','--reporter','json',*['test/'+name for name in editor]],ROOT/'packages/quds_office_editor',True)
run('studio',['flutter','test','--no-pub','--reporter','json',*['test/'+name for name in studio]],ROOT/'packages/quds_office_editor/example',True)
dart_files=[p for p in changed if p.endswith('.dart') and p.startswith(('packages/','apps/')) and (ROOT/p).is_file()]
record['analyzed_files']=dart_files
run('analysis',['dart','analyze','--fatal-infos','--fatal-warnings',*dart_files],ROOT)
run('format',['dart','format','--output=none','--set-exit-if-changed',*dart_files],ROOT)
run('whitespace',['git','diff','--check',args.base,'HEAD'],ROOT)
after=snapshot()
write('source-after.json',after)
record['source_unchanged_during_checks']=before==after
record['source_mismatches']=[name for name in sorted(selected) if before.get(name)!=after.get(name)]
record['source_manifest_sha256']={'before':sha(OUT/'source-before.json'),'after':sha(OUT/'source-after.json')}
record['source_head_unchanged']=git('rev-parse','HEAD')==args.head
record['tracked_worktree_clean_after']=not git('diff','--name-only')
record['passed']=sum(r.get('passed',0) for r in record['runs'])
record['failed']=sum(r.get('failed',0) for r in record['runs'])
record['skipped']=sum(r.get('skipped',0) for r in record['runs'])
record['success']=before==after and record['source_head_unchanged'] and record['tracked_worktree_clean_after'] and all(r['exit_code']==0 and r.get('reporter_success',True) is True and r.get('failed',0)==0 and r.get('skipped',0)==0 for r in record['runs'])
record['finished_at_utc']=datetime.now(timezone.utc).isoformat()
write('verification.json',record)
print(json.dumps({'success':record['success'],'passed':record['passed'],'failed':record['failed'],'skipped':record['skipped'],'source_files':len(before)}),flush=True)
raise SystemExit(0 if record['success'] else 1)
