#!/usr/bin/env python3
"""Independently audit the preserved union archive and bounded source continuity.

Reads pinned Git objects only; does not execute application tests or mutate repo.
"""
import argparse,collections,gzip,hashlib,io,json,re,subprocess,tarfile
from pathlib import Path,PurePosixPath

parser=argparse.ArgumentParser()
parser.add_argument('--repo',type=Path,required=True)
parser.add_argument('--current-ref',default='HEAD')
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args();root=args.repo.resolve()
def git(*xs,input=None):return subprocess.check_output(['git','-C',str(root),*xs],input=input)
def read(rev,path):return git('show',rev+':'+path)
def sha(data):return hashlib.sha256(data).hexdigest()
def tree(rev):
 result={}
 for row in git('ls-tree','-rz','--full-tree',rev).split(b'\0'):
  if not row:continue
  head,path=row.split(b'\t',1);mode,kind,digest=head.decode().split()
  result[path.decode()]={'mode':mode,'kind':kind,'git_blob':digest}
 return result
current=git('rev-parse',args.current_ref).decode().strip()
source='39843ed4874c7b56572c7aa8195716e5892aeca2'
path='docs/validation/thesaurus-20261118/resumed-20261119/evidence/'
index=json.loads(read(current,path+'combined-final-index.json'))
raw=read(current,path+'combined-final.tar.xz')
assert len(raw)==index['archive_bytes'] and sha(raw)==index['archive_sha256']
assert index['source_commit']==source and index['status']=='complete_passed'
archive=tarfile.open(fileobj=io.BytesIO(raw));members=archive.getmembers()
assert all(x.isfile() and not x.name.startswith('/') and '..' not in PurePosixPath(x.name).parts for x in members)
assert len({x.name for x in members})==len(members)
content={x.name:archive.extractfile(x).read() for x in members}
expected={x['path']:x for x in index['files']};assert len(expected)==len(index['files'])
assert set(content)==set(expected)
for name,data in content.items():
 assert len(data)==expected[name]['bytes'] and sha(data)==expected[name]['sha256'],name
 if name.endswith('.gz'):assert gzip.decompress(data)==content[name[:-3]],name
receipt=json.loads(content['receipt.json'])
assert receipt['source_commit']==source and receipt['success'] and receipt['status']=='passed'
assert receipt['source_tree']==git('rev-parse',source+'^{tree}').decode().strip()
for name,digest in receipt['evidence_sha256'].items():assert sha(content[name])==digest,name
assert content['source-before.json']==content['source-after.json']
assert content['environment-before.json']==content['environment-after.json']
source_records=json.loads(content['source-before.json']);environment=json.loads(content['environment-before.json'])
ordinary={k:v for k,v in source_records.items() if not k.startswith('__')}
base_tree=tree(source);current_tree=tree(current)
assert len(ordinary)==4992
for offset in range(0,len(ordinary),64):
 paths=list(ordinary)[offset:offset+64]
 blobs=[base_tree[p]['git_blob'] for p in paths]
 payload=git('cat-file','--batch',input=('\n'.join(blobs)+'\n').encode());cursor=0
 for p,blob in zip(paths,blobs):
  end=payload.index(b'\n',cursor);observed,kind,length=payload[cursor:end].decode().split();length=int(length);cursor=end+1
  data=payload[cursor:cursor+length];cursor+=length+1
  assert observed==blob and kind=='blob'
  assert len(data)==ordinary[p]['bytes'] and sha(data)==ordinary[p]['sha256'],p
assert source_records['__workspace_lock__']==ordinary['pubspec.lock']
plan=receipt['plan'];plan_path='docs/validation/thesaurus-20261118/reconciled/plan.json'
assert plan==json.loads(read(source,plan_path))
for name,digest in receipt['harness_sha256'].items():assert sha(read(source,name))==digest,name
old_root=receipt['requested_plan'][:-len(plan_path)].rstrip('/')
def normalize_suite(name,cwd):
 if name.startswith(old_root+'/'):return name[len(old_root)+1:]
 assert not name.startswith('/'),name
 return str(PurePosixPath(cwd)/name)
expected_gates=[g['name'] for g in plan['groups']]+['analysis','format']
assert [r['name'] for r in receipt['runs']]==expected_gates
runs={r['name']:r for r in receipt['runs']}
all_cases=set();all_suites=set();cohorts=[]
for group in plan['groups']:
 name=group['name'];run=runs[name]
 assert run['cwd']==group['cwd'] and run['accepted'] and run['status']=='completed' and run['exit_code']==0
 command=[receipt['requested_runtime']+'/bin/'+group['runner'],'test']
 if group['runner']=='flutter':command.append('--no-pub')
 command+=['--concurrency='+str(receipt['concurrency']),'--reporter=json',*group['tests']]
 assert command==run['command'],name
 expected_suites={str(PurePosixPath(group['cwd'])/x) for x in group['tests']}
 assert len(expected_suites)==len(group['tests'])
 stdout=content[run['stdout']];stderr=content[run['stderr']]
 assert stderr==b''
 events=[json.loads(line) for line in stdout.decode().splitlines() if line.strip()]
 assert sum(e.get('type')=='start' for e in events)==1
 assert sum(e.get('type')=='done' for e in events)==1 and events[-1]['type']=='done' and events[-1]['success'] is True
 suites={};starts={};ends={}
 for event in events:
  kind=event['type']
  assert kind!='error'
  if kind=='suite':
   suite=event['suite'];assert suite['id'] not in suites
   suites[suite['id']]=normalize_suite(suite['path'],group['cwd'])
  elif kind=='testStart':
   test=event['test'];assert test['id'] not in starts;starts[test['id']]=test
  elif kind=='testDone':
   assert event['testID'] not in ends;ends[event['testID']]=event
 assert len(set(suites.values()))==len(suites) and set(suites.values())==expected_suites
 assert set(starts)==set(ends)
 cases=set();per_suite=collections.Counter();excluded=0
 for id,completion in ends.items():
  assert completion['result']=='success' and not completion.get('skipped',False)
  test=starts[id]
  if completion.get('hidden'):
   assert test['name'].startswith('loading ') or test['name'].endswith('(setUpAll)') or test['name'].endswith('(tearDownAll)'),test
   excluded+=1;continue
  identity=(suites[test['suiteID']],test['name'])
  assert identity not in cases and identity not in all_cases
  cases.add(identity);per_suite[identity[0]]+=1
 assert all(per_suite[s]>0 for s in expected_suites)
 saved=json.loads(content[name+'-cases.json'])
 saved_cases={(normalize_suite(x['suite'],group['cwd']),x['name']) for x in saved}
 assert len(saved)==len(saved_cases) and saved_cases==cases
 assert all(x['result']=='success' and not x['skipped'] and not x.get('hidden') for x in saved)
 assert len(cases)==run['passed']
 assert not re.search(r'A Render\w+ overflowed|RenderBox was not laid out|A hit test.*failed|would not hit test|does not hit test|does not receive pointer events|missed.tap',stdout.decode(),re.I)
 all_cases.update(cases);assert not all_suites.intersection(expected_suites);all_suites.update(expected_suites)
 cohorts.append({'name':name,'suites':len(suites),'passed':len(cases),'excluded_loading_or_lifecycle_cases':excluded,'failed':0,'skipped':0,'errors':0,'complete_starts_and_ends':True,'exact_planned_suites_and_command':True,'terminal_success':True,'layout_or_tap_diagnostics':0})
assert len(all_suites)==receipt['suite_count']==129
assert len(all_cases)==receipt['passed']==2018
for run in receipt['runs']:
 assert run['accepted'] and run['exit_code']==0 and run['status']=='completed'
 for name,item in run['logs'].items():
  assert sha(content[name])==item['sha256']
  assert sha(content[item['compressed']])==item['compressed_sha256']
assert runs['analysis']['command']==[receipt['requested_runtime']+'/bin/dart','analyze','--fatal-infos','--fatal-warnings',*plan['analysis']]
assert runs['format']['command']==[receipt['requested_runtime']+'/bin/dart','format','--output=none','--set-exit-if-changed',*plan['format']]
assert len(set(plan['analysis']))==len(set(plan['format']))==30
allowed_delta=set('''packages/quds_mail_core/CHANGELOG.md
packages/quds_mail_core/README.md
packages/quds_mail_core/lib/src/model/message.dart
packages/quds_mail_core/lib/src/ports/provider.dart
packages/quds_mail_core/test/models_test.dart
packages/quds_mail_store/CHANGELOG.md
packages/quds_mail_store/README.md
packages/quds_mail_store/lib/src/codec.dart
packages/quds_mail_store/lib/src/repository.dart
packages/quds_mail_store/lib/src/schema/database.dart
packages/quds_mail_store/test/codec_test.dart
packages/quds_mail_store/test/migration_test.dart
packages/quds_mail_store/test/repository_test.dart
tools/mail/check_store.py
tools/mail/test_check_store.py'''.splitlines())
changed={p for p in base_tree.keys()|current_tree.keys() if base_tree.get(p)!=current_tree.get(p)}
non_docs={p for p in changed if not p.startswith('docs/')}
assert non_docs==allowed_delta,(non_docs-allowed_delta,allowed_delta-non_docs)
unchanged_groups={}
for prefix in ['packages/quds_office_engine/','packages/quds_office_editor/','apps/','packages/quds_mail_ui/','packages/quds_mail_mime/','third_party/']:
 paths={p for p in base_tree.keys()|current_tree.keys() if p.startswith(prefix)}
 assert not paths.intersection(changed),prefix
 unchanged_groups[prefix]={'tracked_paths':len(paths),'exact_git_mode_kind_and_blob_identity':True}
assert base_tree[plan_path]==current_tree[plan_path]
harness_changed=[p for p in receipt['harness_sha256'] if base_tree[p]!=current_tree[p]]
assert harness_changed==['docs/validation/thesaurus-20261118/reconciled/test_run_targeted.py', 'tools/mail/check_store.py'],harness_changed
ordinary_changed=[p for p in ordinary if base_tree.get(p)!=current_tree.get(p)]
output={
 'accepted':True,'audit_kind':'Independent preserved-evidence verification and source-continuity audit; no fresh application test execution',
 'qualified_source':source,'integrated_source':current,
 'archive':{'path':path+index['archive'],'bytes':len(raw),'sha256':sha(raw),'member_count':len(members),'all_member_names_sizes_hashes_verified':True,'compressed_and_raw_log_bytes_identical':True},
 'qualification':{'suite_count':len(all_suites),'distinct_cases':len(all_cases),'cohorts':cohorts,'analysis_targets':30,'format_targets':30,'strict_analysis_and_format_commands_verified':True,'ordinary_source_blobs_verified_against_qualified_git':len(ordinary),'source_records':len(source_records),'environment_records':len(environment),'historical_source_environment_and_harness_unchanged':all(receipt[x] for x in ['source_unchanged','environment_unchanged','harness_unchanged']),'source_and_environment_before_after_identical':True,'workspace_lock_matches_committed_lock':True,'harness_inputs_bound_to_qualified_git':len(receipt['harness_sha256'])},
 'continuity':{'all_changes_outside_docs_exactly_match_reviewed_mail_delta':True,'changed_paths_outside_docs':sorted(non_docs),'changed_inventory_paths':ordinary_changed,'unchanged_product_groups':unchanged_groups,'analysis_format_and_129_suite_plan_unchanged':True,'changed_historical_harness_inputs':harness_changed,'current_lock_and_manifests_unchanged':not any(p in changed for p in base_tree if p.endswith(('pubspec.yaml','pubspec.lock','analysis_options.yaml')) or p=='.fvmrc')},
 'scope':{'historical_2018_cases_were_not_rerun':True,'full_integrated_source_is_not_identical_to_qualified_source':True,'new_mail_flags_and_migration_require_fresh_validation':True,'mail_ui_tests_overlap_historical_30_cases':True,'fresh_counts_must_be_reported_separately':True,'recommended_fresh_scope':'Full Mail core/store VM and portable Node qualification, four Mail UI suites and MIME consumer tests; preserve the unchanged Office qualification with this explicit source continuity.', 'external_acceptance_gates':'Actual offline browser, installed Studio/OS/IME/live Zotero interoperability and independent human linguistic review remain unverified.'},
 'github_actions':'NOT QUERIED OR AWAITED'}
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps(output,indent=2))
